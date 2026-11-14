using JSON
using SHA

const CONTENT_TEST_ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const CONTENT_TEST_IDENTITY_FIELDS = Dict(
    1 => "key", 2 => "tag", 3 => "message_key", 9 => "edition_id",
    12 => "exercise_id", 13 => "reference")

"""Return the canonical SHA-256 identity for one JSON Lines stream."""
stream_fingerprint(path::String) = bytes2hex(sha256(read(path)))

"""Write mutated JSON records to a corpus file and return its digest."""
function write_content_fixture(path::String, records)
    open(path, "w") do io
        for record in records
            println(io, JSON.json(record))
        end
    end
    return stream_fingerprint(path)
end

"""Derive the order-check identity with the builder's primary-key grammar."""
function record_identity_for_test(record::AbstractDict{String,Any})
    kind = record["kind"]
    field = get(CONTENT_TEST_IDENTITY_FIELDS, kind, nothing)
    if field !== nothing
        return record[field]
    elseif kind == 4
        return "$(record["message_key"])|$(lpad(record["ordinal"], 2, '0'))"
    elseif kind == 5
        return "$(record["locale_tag"])|$(record["message_key"])"
    elseif kind == 6 || kind == 7
        return "$(record["source_namespace"])|$(record["animation_id"])"
    elseif kind == 8
        return "$(record["source_namespace"])|$(record["animation_id"])|$(record["locale_tag"])"
    end
    return join((record["source_namespace"], record["animation_id"],
        record["locale_tag"], record["edition_id"]), "|")
end

@testset "Schema-4 immutable content database" begin
    mktempdir() do directory
        corpus_path = joinpath(directory, "content.jsonl")
        fingerprint = Main.export_content_records(corpus_path)
        @test fingerprint == stream_fingerprint(corpus_path)
        canonical = [JSON.parse(line) for line in
            split(read(corpus_path, String), '\n') if !isempty(line)]
        @test all(record["schema"] == 4 for record in canonical)
        @test issorted([(record["kind"], record_identity_for_test(record))
            for record in canonical])
        counts = [count(record -> record["kind"] == kind, canonical)
            for kind in 1:13]
        @test counts == [
            6, 1, 207, counts[4], 207, 141, 140, 140, 3, 141, 140, 1, 0]
        @test counts[4] <= 32
        exercise = only(filter(record -> record["kind"] == 12, canonical))
        @test exercise["exercise_id"] == "a9237c51-c9f6-4d54-8bf5-f8c651906e1c"
        @test exercise["animation_id"] == "76fdebfe-2600-551e-be64-03f1942f4f49"
        @test exercise["reference"] == "elements-i-1"
        @test exercise["instructions"] ==
            "On a given finite straight line to construct an equilateral triangle."
        catalog_nodes = filter(record -> record["kind"] == 7, canonical)
        @test count(record -> record["node_kind"] == 2, catalog_nodes) == 1
        @test all(record -> record["node_kind"] ==
            (record["implementation_path"] === nothing ? 2 : 1), catalog_nodes)
        @test length(canonical) <= 4096
        @test length(read(corpus_path)) <= 4 * 1024 * 1024

        compatibility_script = joinpath(
            CONTENT_TEST_ROOT, "tools", "test", "fixtures",
            "verify_search_projection.jl")
        compatibility = Main.run_command(Cmd([
            Main.JULIA_EXE,
            "--depwarn=error",
            "--project=$(Main.JULIA_TEST_PROJECT)",
            compatibility_script,
        ]); cwd=CONTENT_TEST_ROOT, capture_output=true)
        @test compatibility.exit_code == 0
        @test strip(compatibility.stdout) == "search projection compatibility passed"

        builder = Main.build_content_database_builder()
        first_database = joinpath(directory, "content.first.sqlite3")
        second_database = joinpath(directory, "content.second.sqlite3")
        Main.run_content_database_builder(
            builder, corpus_path, first_database, fingerprint)
        Main.run_content_database_builder(
            builder, corpus_path, second_database, fingerprint)
        @test isfile(first_database)
        @test stream_fingerprint(first_database) == stream_fingerprint(second_database)
        standalone_builder = joinpath(directory, basename(builder))
        cp(builder, standalone_builder)
        standalone_database = joinpath(directory, "standalone.sqlite3")
        standalone = Main.run_command(Cmd([
            standalone_builder, corpus_path, standalone_database, fingerprint,
        ]); cwd=directory, capture_output=true)
        @test standalone.exit_code == 0
        @test isempty(standalone.stderr)
        @test isfile(standalone_database)
        @test stream_fingerprint(standalone_database) ==
            stream_fingerprint(first_database)
        @test_throws ErrorException Main.run_content_database_builder(
            builder, corpus_path, joinpath(directory, "wrong-fingerprint.sqlite3"),
            repeat("0", 64))

        malformed_cases = [
            ("old corpus schema", records -> (records[1]["schema"] = 2)),
            ("removed catalogue kind", records -> begin
                index = first(findall(record -> record["kind"] == 7, records))
                records[index]["node_kind"] = 3
            end),
            ("missing translation", records -> deleteat!(
                records, first(findall(record -> record["kind"] == 5, records)))),
            ("unknown availability edition", records -> begin
                index = first(findall(record -> record["kind"] == 10, records))
                records[index]["edition_id"] = "undeclared-edition"
            end),
            ("invalid placeholder signature", records -> begin
                index = first(findall(record ->
                    record["kind"] == 5 && occursin("{", record["template"]),
                    records))
                records[index]["template"] = "{undeclared}"
            end),
            ("missing default", records -> begin
                foreach(record -> record["is_default"] = false,
                    filter(record -> record["kind"] == 10, records))
            end),
            ("invalid exercise UUID", records -> begin
                index = first(findall(record -> record["kind"] == 12, records))
                records[index]["exercise_id"] = "not-a-uuid"
            end),
            ("invalid exercise reference", records -> begin
                index = first(findall(record -> record["kind"] == 12, records))
                records[index]["reference"] = "Elements-I-1"
            end),
            ("missing exercise animation", records -> begin
                index = first(findall(record -> record["kind"] == 12, records))
                records[index]["animation_id"] =
                    "00000000-0000-0000-0000-000000000001"
            end),
            ("blank exercise instructions", records -> begin
                index = first(findall(record -> record["kind"] == 12, records))
                records[index]["instructions"] = " \n\t"
            end),
            ("oversized exercise instructions", records -> begin
                index = first(findall(record -> record["kind"] == 12, records))
                records[index]["instructions"] = repeat("x", 32 * 1024 + 1)
            end),
            ("reused retired reference", records -> begin
                exercise = only(filter(record -> record["kind"] == 12, records))
                push!(records, Dict(
                    "schema" => 4, "kind" => 13,
                    "exercise_id" => exercise["exercise_id"],
                    "reference" => exercise["reference"],
                    "identity_retired" => false))
                sort!(records; by=record -> (
                    record["kind"], record_identity_for_test(record)))
            end),
            ("reused retired identity", records -> begin
                exercise = only(filter(record -> record["kind"] == 12, records))
                push!(records, Dict(
                    "schema" => 4, "kind" => 13,
                    "exercise_id" => exercise["exercise_id"],
                    "reference" => "elements-i-old",
                    "identity_retired" => true))
                sort!(records; by=record -> (
                    record["kind"], record_identity_for_test(record)))
            end),
        ]
        for (name, mutate!) in malformed_cases
            records = deepcopy(canonical)
            mutate!(records)
            malformed_path = joinpath(
                directory, replace(name, ' ' => '-') * ".jsonl")
            malformed_fingerprint = write_content_fixture(malformed_path, records)
            output_path = joinpath(
                directory, replace(name, ' ' => '-') * ".sqlite3")
            @test_throws ErrorException Main.run_content_database_builder(
                builder, malformed_path, output_path, malformed_fingerprint)
        end

        renamed_records = deepcopy(canonical)
        exercise = only(filter(record -> record["kind"] == 12, renamed_records))
        push!(renamed_records, Dict(
            "schema" => 4, "kind" => 13,
            "exercise_id" => exercise["exercise_id"],
            "reference" => "elements-i-old",
            "identity_retired" => false))
        sort!(renamed_records; by=record -> (
            record["kind"], record_identity_for_test(record)))
        renamed_path = joinpath(directory, "renamed-reference.jsonl")
        renamed_fingerprint = write_content_fixture(renamed_path, renamed_records)
        Main.run_content_database_builder(
            builder, renamed_path, joinpath(directory, "renamed-reference.sqlite3"),
            renamed_fingerprint)

        full_text_records = deepcopy(canonical)
        full_text_exercise = only(filter(
            record -> record["kind"] == 12, full_text_records))
        full_text_exercise["instructions"] = repeat("x", 32 * 1024)
        full_text_path = joinpath(directory, "maximum-exercise-text.jsonl")
        full_text_fingerprint = write_content_fixture(full_text_path, full_text_records)
        Main.run_content_database_builder(
            builder, full_text_path,
            joinpath(directory, "maximum-exercise-text.sqlite3"),
            full_text_fingerprint)

        @testset "Content builder compile-time input identity" begin
            mktempdir() do directory
                source = joinpath(directory, "main.odin")
                sql_directory = joinpath(directory, "sql")
                mkpath(sql_directory)
                schema = joinpath(sql_directory, "schema.sql")
                write(source, "package main\n")
                write(schema, "CREATE TABLE example (value INTEGER);\n")
                original = Main.content_builder_input_fingerprint(directory)
                @test original == Main.content_builder_input_fingerprint(directory)
                write(schema, "CREATE TABLE example (value TEXT);\n")
                @test original != Main.content_builder_input_fingerprint(directory)
                write(schema, "CREATE TABLE example (value INTEGER);\n")
                @test original == Main.content_builder_input_fingerprint(directory)
                renamed = joinpath(sql_directory, "renamed.sql")
                mv(schema, renamed)
                @test original != Main.content_builder_input_fingerprint(directory)
                mv(renamed, schema)
                write(source, "package main\n// changed\n")
                @test original != Main.content_builder_input_fingerprint(directory)
            end
        end

        canonical_lines = split(read(corpus_path, String), '\n'; keepempty=false)
        malformed_shapes = [
            ("reordered-fields", replace(canonical_lines[1],
                "\"schema\":4,\"kind\":1" => "\"kind\":1,\"schema\":4")),
            ("unknown-field", replace(canonical_lines[1],
                "\"value\":\"en-US\"}" => "\"value\":\"en-US\",\"unknown\":0}")),
            ("noncompact-record", replace(canonical_lines[1],
                "{\"schema\"" => "{ \"schema\"")),
        ]
        for (name, malformed_line) in malformed_shapes
            lines = copy(canonical_lines)
            lines[1] = malformed_line
            malformed_path = joinpath(directory, "$name.jsonl")
            open(malformed_path, "w") do io
                foreach(line -> println(io, line), lines)
            end
            malformed_fingerprint = stream_fingerprint(malformed_path)
            @test_throws ErrorException Main.run_content_database_builder(
                builder, malformed_path, joinpath(directory, "$name.sqlite3"),
                malformed_fingerprint)
        end
    end
end

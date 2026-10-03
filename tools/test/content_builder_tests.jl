using JSON
using SHA

const CONTENT_TEST_ROOT = normpath(joinpath(@__DIR__, "..", ".."))

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
    if kind == 1
        return record["key"]
    elseif kind == 2
        return record["tag"]
    elseif kind == 3
        return record["message_key"]
    elseif kind == 4
        return "$(record["message_key"])|$(lpad(record["ordinal"], 2, '0'))"
    elseif kind == 5
        return "$(record["locale_tag"])|$(record["message_key"])"
    elseif kind == 6 || kind == 7
        return "$(record["source_namespace"])|$(record["animation_id"])"
    elseif kind == 8
        return "$(record["source_namespace"])|$(record["animation_id"])|$(record["locale_tag"])"
    elseif kind == 9
        return record["edition_id"]
    end
    return join((record["source_namespace"], record["animation_id"],
        record["locale_tag"], record["edition_id"]), "|")
end

@testset "Schema-3 immutable content database" begin
    mktempdir() do directory
        corpus_path = joinpath(directory, "content.jsonl")
        fingerprint = Main.export_content_records(corpus_path)
        @test fingerprint == stream_fingerprint(corpus_path)
        canonical = [JSON.parse(line) for line in
            split(read(corpus_path, String), '\n') if !isempty(line)]
        @test all(record["schema"] == 3 for record in canonical)
        @test issorted([(record["kind"], record_identity_for_test(record))
            for record in canonical])
        counts = [count(record -> record["kind"] == kind, canonical)
            for kind in 1:11]
        @test counts == [6, 1, 69, counts[4], 69, 139, 138, 138, 3, 139, 138]
        @test counts[4] <= 32
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
        @test_throws ErrorException Main.run_content_database_builder(
            builder, corpus_path, joinpath(directory, "wrong-fingerprint.sqlite3"),
            repeat("0", 64))

        malformed_cases = [
            ("old corpus schema", records -> (records[1]["schema"] = 2)),
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

        canonical_lines = split(read(corpus_path, String), '\n'; keepempty=false)
        malformed_shapes = [
            ("reordered-fields", replace(canonical_lines[1],
                "\"schema\":3,\"kind\":1" => "\"kind\":1,\"schema\":3")),
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

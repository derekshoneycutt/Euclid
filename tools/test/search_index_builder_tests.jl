using JSON

@testset "Schema-2 search index builder" begin
    mktempdir() do directory
        corpus_path = joinpath(directory, "catalog.jsonl")
        fingerprint = Main.export_search_corpus(corpus_path)
        builder = Main.build_search_index_builder()
        canonical = [JSON.parse(line) for line in
            split(read(corpus_path, String), '\n') if !isempty(line)]
        @test length(canonical) == 138

        valid_database = joinpath(directory, "valid.sqlite3")
        Main.run_search_index_builder(
            builder, corpus_path, valid_database, fingerprint)
        @test isfile(valid_database)

        root_indices = findall(record ->
            record["parent_animation_id"] === nothing, canonical)
        child_groups = Dict{String,Vector{Int}}()
        for (index, record) in enumerate(canonical)
            parent = record["parent_animation_id"]
            parent === nothing && continue
            push!(get!(child_groups, parent, Int[]), index)
        end
        child_pair = first(filter(indices -> length(indices) >= 2,
            collect(values(child_groups))))[1:2]
        terminal_index = only(findall(record -> record["node_kind"] == 3,
            canonical))
        path_backed_index = first(findall(record -> record["node_kind"] != 3,
            canonical))

        malformed_cases = [
            ("missing parent", records ->
                (records[first(root_indices)]["parent_animation_id"] =
                    "ffffffff-ffff-ffff-ffff-ffffffffffff")),
            ("duplicate root order", records ->
                (records[root_indices[2]]["sibling_order"] =
                    records[root_indices[1]]["sibling_order"])),
            ("duplicate child order", records ->
                (records[child_pair[2]]["sibling_order"] =
                    records[child_pair[1]]["sibling_order"])),
            ("invalid node kind", records ->
                (records[path_backed_index]["node_kind"] = 9)),
            ("Terminal implementation path", records ->
                (records[terminal_index]["implementation_path"] = "terminal.jl")),
            ("unsafe implementation path", records ->
                (records[path_backed_index]["implementation_path"] = "../escape.jl")),
        ]

        for (name, mutate!) in malformed_cases
            records = deepcopy(canonical)
            mutate!(records)
            @test records != canonical
            file_stem = replace(name, ' ' => '-')
            malformed_path = joinpath(directory, file_stem * ".jsonl")
            write(malformed_path,
                join((JSON.json(record) for record in records), "\n") * "\n")
            output_path = joinpath(directory, file_stem * ".sqlite3")
            @test_throws ErrorException Main.run_search_index_builder(
                builder, malformed_path, output_path, fingerprint)
        end
    end
end
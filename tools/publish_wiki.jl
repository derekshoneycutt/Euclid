#!/usr/bin/env julia

include("code_wiki.jl")

using .CodeWiki

"""Synchronize a validated artifact into an existing GitHub Wiki checkout."""
function main(arguments::Vector{String}=ARGS)
    length(arguments) == 2 || error(
        "Usage: julia tools/publish_wiki.jl <artifact-root> <wiki-checkout>")
    manifest = load_wiki_manifest(joinpath(@__DIR__, "code_wiki.toml"))
    published = sync_wiki_artifact(manifest, abspath(arguments[1]), abspath(arguments[2]))
    foreach(path -> println("Published ", path), published)
    return 0
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(main())
end
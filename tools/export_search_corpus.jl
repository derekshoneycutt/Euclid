#!/usr/bin/env julia

using SHA

const REPOSITORY_ROOT = normpath(joinpath(@__DIR__, ".."))
const JULIA_ROOT = joinpath(REPOSITORY_ROOT, "src", "julia")
const CONTENT_ROOT = joinpath(REPOSITORY_ROOT, "src", "content")

include(joinpath(JULIA_ROOT, "script.jl"))
include(joinpath(JULIA_ROOT, "search", "search_corpus.jl"))

"""Return authored search content from one loaded production sidecar."""
function load_search_content(generation, descriptor)
    loader = Base.invokelatest(
        getfield, generation.animation_catalog, :ensure_animation_loaded)
    implementation = Base.invokelatest(loader, generation.content, descriptor.id)
    animation_module = parentmodule(implementation.entry)
    content_name = Symbol(string(nameof(animation_module)), "Content")
    isdefined(animation_module, content_name) || error(
        "animation sidecar module is missing: $(descriptor.implementation_path)")
    content_module = Base.invokelatest(getfield, animation_module, content_name)
    getter = Base.invokelatest(getfield, content_module, :get_search_content)
    return Base.invokelatest(getter)
end

"""Build and atomically publish the canonical built-in search corpus."""
function export_search_corpus(destination::String)
    generation = create_euclid_runtime_generation(CONTENT_ROOT)
    descriptors = Base.invokelatest(
        getfield, generation.animation_catalog, :AnimationDescriptors)
    documents = EuclidSearchCorpus.build_search_documents(
        descriptors, descriptor -> load_search_content(generation, descriptor))
    mkpath(dirname(destination))
    candidate = destination * ".candidate"
    try
        open(candidate, "w") do io
            EuclidSearchCorpus.write_search_corpus(io, documents)
        end
        mv(candidate, destination; force=true)
    finally
        isfile(candidate) && rm(candidate; force=true)
    end
    return bytes2hex(open(sha256, destination))
end

"""Validate command arguments and run the search corpus exporter."""
function main(arguments::Vector{String})
    length(arguments) == 1 || error(
        "usage: export_search_corpus.jl OUTPUT.jsonl")
    println(export_search_corpus(abspath(only(arguments))))
    return nothing
end

main(ARGS)
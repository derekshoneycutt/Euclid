#!/usr/bin/env julia

using SHA

const REPOSITORY_ROOT = normpath(joinpath(@__DIR__, ".."))
const JULIA_ROOT = joinpath(REPOSITORY_ROOT, "src", "julia")
const CONTENT_ROOT = joinpath(REPOSITORY_ROOT, "src", "content")

include(joinpath(JULIA_ROOT, "script.jl"))
include(joinpath(JULIA_ROOT, "search", "search_corpus.jl"))

module BuildAnimationCatalogInput
using UUIDs
using ..AnimationCatalog
include(joinpath(@__DIR__, "..", "src", "content", "animation_catalog_data.jl"))
end

"""Create a disposable owner module for build-time animation and sidecar loading."""
function create_build_content_module()
    content = Module(gensym(:EuclidBuildContent), false, false)
    Core.eval(content, :(const OdinJuliaBridge = $OdinJuliaBridge))
    Core.eval(content, :(const EuclidAnimations = $EuclidAnimations))
    Core.eval(content, :(const EuclidGeometry = $EuclidGeometry))
    Core.eval(content, :(const EuclidLatex = $EuclidLatex))
    Core.eval(content, :(const EuclidSearchContent = $EuclidSearchContent))
    Core.eval(content, :(const AnimationCatalog = $AnimationCatalog))
    Base.include(content, joinpath(CONTENT_ROOT, "nullanimation.jl"))
    return content
end

"""Return authored search content from one loaded build-time sidecar."""
function load_search_content(content, descriptors, descriptor)
    implementation = AnimationCatalog.ensure_animation_loaded(
        CONTENT_ROOT, descriptors, descriptor.id; owner=content)
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
    descriptors = BuildAnimationCatalogInput.AnimationDescriptors
    content = create_build_content_module()
    records = EuclidSearchCorpus.build_catalog_corpus(
        descriptors, descriptor -> load_search_content(content, descriptors, descriptor))
    mkpath(dirname(destination))
    candidate = destination * ".candidate"
    try
        open(candidate, "w") do io
            EuclidSearchCorpus.write_catalog_corpus(io, records)
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
#!/usr/bin/env julia

using SHA

const REPOSITORY_ROOT = normpath(joinpath(@__DIR__, ".."))
const JULIA_ROOT = joinpath(REPOSITORY_ROOT, "src", "julia")
const CONTENT_ROOT = joinpath(REPOSITORY_ROOT, "src", "content")

include(joinpath(JULIA_ROOT, "script.jl"))
include(joinpath(JULIA_ROOT, "search", "content_corpus.jl"))

module BuildContentInput
using UUIDs
using ..AnimationCatalog
using ..LocalizedContent
include(joinpath(
    @__DIR__, "..", "src", "content", "animation_catalog_generation.jl"))
const AnimationDescriptors = AnimationCatalogGeneration.AnimationDescriptors
const AuthoredManifest = AnimationCatalogGeneration.AuthoredManifest
end

"""Create an isolated owner module for build-time content sidecars."""
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

"""Load the search projection authored beside one animation implementation."""
function load_search_content(content, descriptors, descriptor)
    implementation = AnimationCatalog.ensure_animation_loaded(
        CONTENT_ROOT, descriptors, descriptor.id; owner=content)
    animation_module = parentmodule(implementation.entry)
    content_name = Symbol(string(nameof(animation_module)), "Content")
    Base.invokelatest(isdefined, animation_module, content_name) || error(
        "animation sidecar module is missing: $(descriptor.implementation_path)")
    content_module = Base.invokelatest(getfield, animation_module, content_name)
    getter = Base.invokelatest(getfield, content_module, :get_search_content)
    return Base.invokelatest(getter)
end

"""Export the canonical content record stream atomically and return its digest."""
function export_content_records(destination::String)
    content = create_build_content_module()
    records = EuclidContentCorpus.build_content_records(
        BuildContentInput.AnimationDescriptors,
        BuildContentInput.AuthoredManifest,
        descriptor -> load_search_content(
            content, BuildContentInput.AnimationDescriptors, descriptor))
    mkpath(dirname(destination))
    candidate = destination * ".candidate"
    try
        open(candidate, "w") do io
            EuclidContentCorpus.write_content_records(io, records)
        end
        mv(candidate, destination; force=true)
    finally
        isfile(candidate) && rm(candidate; force=true)
    end
    return bytes2hex(open(sha256, destination))
end

"""Validate arguments and run the deterministic content exporter."""
function main(arguments::Vector{String})
    length(arguments) == 1 || error(
        "usage: export_content_records.jl OUTPUT.jsonl")
    println(export_content_records(abspath(only(arguments))))
    return nothing
end

main(ARGS)

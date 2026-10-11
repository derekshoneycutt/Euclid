const REPOSITORY_ROOT = normpath(joinpath(@__DIR__, "..", "..", ".."))
const JULIA_ROOT = joinpath(REPOSITORY_ROOT, "src", "julia")
const CONTENT_ROOT = joinpath(REPOSITORY_ROOT, "src", "content")

include(joinpath(JULIA_ROOT, "script.jl"))
include(joinpath(JULIA_ROOT, "search", "content_corpus.jl"))
include(joinpath(@__DIR__, "legacy_search_corpus.jl"))

module ProjectionCompatibilityInput
using UUIDs
using ..AnimationCatalog
using ..LocalizedContent
include(joinpath(
    @__DIR__, "..", "..", "..", "src", "content",
    "animation_catalog_generation.jl"))
const AnimationDescriptors = AnimationCatalogGeneration.AnimationDescriptors
const AuthoredManifest = AnimationCatalogGeneration.AuthoredManifest
end

"""Create an isolated Julia owner module for the current sidecar sources."""
function create_projection_content_owner()
    owner = Module(gensym(:EuclidProjectionCompatibility), false, false)
    Core.eval(owner, :(const OdinJuliaBridge = $OdinJuliaBridge))
    Core.eval(owner, :(const EuclidAnimations = $EuclidAnimations))
    Core.eval(owner, :(const EuclidGeometry = $EuclidGeometry))
    Core.eval(owner, :(const EuclidLatex = $EuclidLatex))
    Core.eval(owner, :(const EuclidSearchContent = $EuclidSearchContent))
    Core.eval(owner, :(const AnimationCatalog = $AnimationCatalog))
    Base.include(owner, joinpath(CONTENT_ROOT, "nullanimation.jl"))
    return owner
end

"""Load one animation sidecar's unchanged search projection."""
function load_projection_content(owner, descriptors, descriptor)
    implementation = AnimationCatalog.ensure_animation_loaded(
        CONTENT_ROOT, descriptors, descriptor.id; owner)
    animation_module = parentmodule(implementation.entry)
    sidecar_name = Symbol(string(nameof(animation_module)), "Content")
    sidecar = Base.invokelatest(getfield, animation_module, sidecar_name)
    getter = Base.invokelatest(getfield, sidecar, :get_search_content)
    return Base.invokelatest(getter)
end

"""Read one named JSON-field payload from a canonical content record."""
function content_record_field(record, name::String)
    index = findfirst(field -> first(field) == name, record.fields)
    index === nothing && error("content record is missing field $name")
    return last(record.fields[index])
end

"""Require the schema-3 projection to preserve each schema-2 search input."""
function main()
    descriptors = ProjectionCompatibilityInput.AnimationDescriptors
    manifest = ProjectionCompatibilityInput.AuthoredManifest
    owner = create_projection_content_owner()
    loader = descriptor -> load_projection_content(owner, descriptors, descriptor)
    legacy = EuclidLegacySearchCorpus.build_catalog_corpus(descriptors, loader)
    current = EuclidContentCorpus.build_content_records(
        descriptors, manifest, loader)
    projections = Dict(
        content_record_field(record, "animation_id") => record
        for record in current if record.kind == 11)
    length(projections) == length(legacy) == 138 ||
        error("search projection count changed")
    for source in legacy
        target = get(projections, source.animation_id, nothing)
        target === nothing && error("search projection identity changed")
        content_record_field(target, "source_namespace") == source.source_namespace ||
            error("search projection namespace changed")
        content_record_field(target, "display_name") == source.display_name ||
            error("search projection name changed")
        content_record_field(target, "hierarchy_path") == source.hierarchy_path ||
            error("search projection hierarchy changed")
        content_record_field(target, "semantic_text") == source.semantic_text ||
            error("search projection semantic text changed")
        content_record_field(target, "aliases") == source.aliases ||
            error("search projection aliases changed")
    end
    println("search projection compatibility passed")
    return nothing
end

main()

module AnimationCatalogGeneration

using UUIDs
using ..AnimationCatalog

export AnimationDescriptors, ensure_animation_loaded, register_animation_catalog

include("animation_catalog_data.jl")

const SourceRoot = @__DIR__

"""Register this generation's descriptor tree and eager Terminal implementation."""
function register_animation_catalog(
    state_ptr::Ptr{Cvoid}, terminal_entry::Function)

    return AnimationCatalog.register_animation_catalog(
        state_ptr, terminal_entry, AnimationDescriptors)
end

"""Load one implementation from this generation's packaged source root."""
function ensure_animation_loaded(owner::Module, id::UUID)
    return AnimationCatalog.ensure_animation_loaded(
        SourceRoot, AnimationDescriptors, id; owner)
end

end

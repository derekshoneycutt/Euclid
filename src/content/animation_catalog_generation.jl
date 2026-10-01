module AnimationCatalogGeneration

using UUIDs
using ..AnimationCatalog

export AnimationDescriptors, ensure_animation_loaded

include("animation_catalog_data.jl")

const SourceRoot = @__DIR__

"""Load one implementation from this generation's packaged source root."""
function ensure_animation_loaded(owner::Module, id::UUID)
    return AnimationCatalog.ensure_animation_loaded(
        SourceRoot, AnimationDescriptors, id; owner)
end

end

module AnimationCatalogGeneration

using UUIDs
using ..AnimationCatalog
using ..LocalizedContent

export AnimationDescriptors, AuthoredManifest, ensure_animation_loaded

include("animation_catalog_data.jl")
include("localization/ui_messages.jl")
include("localization/catalog_names.jl")
include("localization/editions.jl")
include("localization/edition_assignments.jl")
include("localization/manifest.jl")

const SourceRoot = @__DIR__

"""Load one implementation from this generation's packaged source root."""
function ensure_animation_loaded(owner::Module, id::UUID)
    return AnimationCatalog.ensure_animation_loaded(
        SourceRoot, AnimationDescriptors, id; owner)
end

end

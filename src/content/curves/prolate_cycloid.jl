module EuclidCurvesProlateCycloid

using UUIDs
using ..AnimationCatalog
using ..OdinJuliaBridge
using ..EuclidGeometry
using ..EuclidLatex

export get_view_content, initialize, clean, loop, animation_entry

const AnimationId = UUID("83f8bc57-b9ad-4956-b6d0-d8483c584e2e")
const TracerDistance = 0.09f0

"""Return explanatory content for a two-revolution prolate Cycloid."""
function get_view_content(_state_ptr::Ptr{Cvoid})
    return tex"""\textbf{Prolate Cycloid}

When the tracing point lies outside the rolling circle, $d>r$, it traces a prolate cycloid with a loop during each wheel revolution."""
end

"""Publish this leaf's prolate-Cycloid explanation."""
function publish_content(state_ptr::Ptr{Cvoid})
    OdinJuliaBridge.publish_view_content(state_ptr, get_view_content)
end

include("cycloid_shared.jl")

end


AnimationCatalog.animation(EuclidCurvesProlateCycloid.AnimationId,
    EuclidCurvesProlateCycloid.animation_entry)
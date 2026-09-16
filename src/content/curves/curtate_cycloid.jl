module EuclidCurvesCurtateCycloid

using UUIDs
using ..AnimationCatalog
using ..OdinJuliaBridge
using ..EuclidGeometry
using ..EuclidLatex

export get_view_content, initialize, clean, loop, animation_entry

const AnimationId = UUID("0a8ada74-d72a-403d-a065-2269c72dfd4b")
const TracerDistance = 0.03f0

"""Return explanatory content for a two-revolution curtate Cycloid."""
function get_view_content(_state_ptr::Ptr{Cvoid})
    return tex"""\textbf{Curtate Cycloid}

When the tracing point lies inside the rolling circle, $d<r$, it traces a curtate cycloid. The curve remains above the fixed line through two wheel revolutions."""
end

"""Publish this leaf's curtate-Cycloid explanation."""
function publish_content(state_ptr::Ptr{Cvoid})
    OdinJuliaBridge.publish_view_content(state_ptr, get_view_content)
end

include("cycloid_shared.jl")

end


AnimationCatalog.animation(EuclidCurvesCurtateCycloid.AnimationId,
    EuclidCurvesCurtateCycloid.animation_entry)
module EuclidCurvesCycloid

using UUIDs
using ..AnimationCatalog
using ..OdinJuliaBridge
using ..EuclidGeometry
using ..EuclidLatex

export get_view_content, initialize, clean, loop, animation_entry

const AnimationId = UUID("31458f6d-bc86-4a98-8629-b3bba8d16f53")
const TracerDistance = 0.06f0

"""Return explanatory content for an ordinary two-revolution Cycloid."""
function get_view_content(_state_ptr::Ptr{Cvoid})
    return tex"""\textbf{Cycloid}

A point at distance $d=r$ from the center of a circle rolling without slipping along a fixed line traces a cycloid. This construction follows two complete wheel revolutions."""
end

"""Publish this leaf's Cycloid explanation."""
function publish_content(state_ptr::Ptr{Cvoid})
    OdinJuliaBridge.publish_view_content(state_ptr, get_view_content)
end

include("cycloid_shared.jl")

end


AnimationCatalog.animation(
    EuclidCurvesCycloid.AnimationId, EuclidCurvesCycloid.animation_entry)
module EuclidCurvesNephroid

using UUIDs
using ..AnimationCatalog
using ..OdinJuliaBridge
using ..EuclidGeometry
using ..EuclidLatex

export get_view_content, initialize, clean, loop, animation_entry

const AnimationId = UUID("5cea3464-3e41-444d-a326-2fbd9b20de7e")
const Mode = OdinJuliaBridge.TROCHOID_EXTERNAL
const FixedRadius = 0.16f0
const RollingRadius = 0.08f0
const TracerDistance = 0.08f0
const FinishParameter = 2f0 * Float32(pi)
const DrawDuration = 5f0

"""Return explanatory content for the two-cusped Nephroid."""
function get_view_content(_state_ptr::Ptr{Cvoid})
    return tex"""\textbf{Nephroid}

A Nephroid is the two-cusped epicycloid traced by a point on a circle rolling around a fixed circle twice its radius."""
end

"""Create this leaf's Nephroid."""
function create_curve(state_ptr::Ptr{Cvoid}, center; kwargs...)
    return OdinJuliaBridge.create_new_nephroid(
        state_ptr, center, FixedRadius; kwargs...)
end

"""Publish this leaf's Nephroid explanation."""
function publish_content(state_ptr::Ptr{Cvoid})
    OdinJuliaBridge.publish_view_content(state_ptr, get_view_content)
end

include("trochoid_examples_shared.jl")

end


AnimationCatalog.animation(EuclidCurvesNephroid.AnimationId,
    EuclidCurvesNephroid.animation_entry)

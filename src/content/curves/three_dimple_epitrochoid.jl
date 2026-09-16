module EuclidCurvesThreeDimpleEpitrochoid

using UUIDs
using ..AnimationCatalog
using ..OdinJuliaBridge
using ..EuclidGeometry
using ..EuclidLatex

export get_view_content, initialize, clean, loop, animation_entry

const AnimationId = UUID("bf196800-9bc6-4612-bf22-00051d3152e6")
const Mode = OdinJuliaBridge.TROCHOID_EXTERNAL
const FixedRadius = 0.18f0
const RollingRadius = 0.06f0
const TracerDistance = 0.03f0
const FinishParameter = 2f0 * Float32(pi)
const DrawDuration = 5f0

"""Return explanatory content for the three-dimple Epitrochoid."""
function get_view_content(_state_ptr::Ptr{Cvoid})
    return tex"""\textbf{3-Dimple Epitrochoid}

With $R:r:d=3:1:1/2$, a point halfway from the rolling circle's center to its rim traces three smooth inward dimples."""
end

"""Create this leaf's three-dimple Epitrochoid."""
function create_curve(state_ptr::Ptr{Cvoid}, center; kwargs...)
    return OdinJuliaBridge.create_new_epitrochoid(state_ptr, center,
        FixedRadius, 3 // 1, TracerDistance; kwargs...)
end

"""Publish this leaf's Epitrochoid explanation."""
function publish_content(state_ptr::Ptr{Cvoid})
    OdinJuliaBridge.publish_view_content(state_ptr, get_view_content)
end

include("trochoid_examples_shared.jl")

end


AnimationCatalog.animation(EuclidCurvesThreeDimpleEpitrochoid.AnimationId,
    EuclidCurvesThreeDimpleEpitrochoid.animation_entry)

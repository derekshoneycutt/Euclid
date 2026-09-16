module EuclidCurvesFivePointHypotrochoid

using UUIDs
using ..AnimationCatalog
using ..OdinJuliaBridge
using ..EuclidGeometry
using ..EuclidLatex

export get_view_content, initialize, clean, loop, animation_entry

const AnimationId = UUID("b0c35f2e-6108-4510-ab0e-cfa3a7269869")
const Mode = OdinJuliaBridge.TROCHOID_INTERNAL
const FixedRadius = 0.25f0
const RollingRadius = 0.15f0
const TracerDistance = 0.25f0
const FinishParameter = 6f0 * Float32(pi)
const DrawDuration = 10f0

"""Return explanatory content for the smooth five-point Hypotrochoid."""
function get_view_content(_state_ptr::Ptr{Cvoid})
    return tex"""\textbf{5-Point Hypotrochoid}

With $R:r:d=5:3:5$, the tracer extends beyond the internally rolling circle. The reduced ratio $R/r=5/3$ closes after three revolutions around the fixed center."""
end

"""Create this leaf's smooth five-point Hypotrochoid."""
function create_curve(state_ptr::Ptr{Cvoid}, center; kwargs...)
    return OdinJuliaBridge.create_new_hypotrochoid(state_ptr, center,
        FixedRadius, 5 // 3, TracerDistance; kwargs...)
end

"""Publish this leaf's Hypotrochoid explanation."""
function publish_content(state_ptr::Ptr{Cvoid})
    OdinJuliaBridge.publish_view_content(state_ptr, get_view_content)
end

include("trochoid_examples_shared.jl")

end


AnimationCatalog.animation(EuclidCurvesFivePointHypotrochoid.AnimationId,
    EuclidCurvesFivePointHypotrochoid.animation_entry)

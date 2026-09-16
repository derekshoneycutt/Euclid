module EuclidCurvesFiveHypocycloid

using UUIDs
using ..AnimationCatalog
using ..OdinJuliaBridge
using ..EuclidGeometry
using ..EuclidLatex

export get_view_content, initialize, clean, loop, animation_entry

const AnimationId = UUID("7d7dbc7a-c360-486d-b727-a9909d4c569e")
const K = 5 // 1

"""Return explanatory content for the five-cusped hypocycloid."""
function get_view_content(_state_ptr::Ptr{Cvoid})
    return tex"""\textbf{5-Hypocycloid}

For $k=R/r=5$, a point on the internally rolling circle traces a five-cusped hypocycloid and closes after one revolution around the fixed center."""
end

"""Create this leaf's five-cusped hypocycloid."""
function create_curve(state_ptr::Ptr{Cvoid}, center, fixed_radius::Real; kwargs...)
    return OdinJuliaBridge.create_new_hypocycloid(
        state_ptr, center, fixed_radius, K; kwargs...)
end

"""Publish this leaf's five-cusped explanation."""
function publish_content(state_ptr::Ptr{Cvoid})
    OdinJuliaBridge.publish_view_content(state_ptr, get_view_content)
end

include("hypocycloid_shared.jl")

end


AnimationCatalog.animation(EuclidCurvesFiveHypocycloid.AnimationId,
    EuclidCurvesFiveHypocycloid.animation_entry)

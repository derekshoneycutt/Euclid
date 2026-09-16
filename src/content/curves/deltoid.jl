module EuclidCurvesDeltoid

using UUIDs
using ..AnimationCatalog
using ..OdinJuliaBridge
using ..EuclidGeometry
using ..EuclidLatex

export get_view_content, initialize, clean, loop, animation_entry

const AnimationId = UUID("ff3a997a-c536-43fa-ba37-9c380c3426fa")
const K = 3 // 1

"""Return explanatory content for the three-cusped hypocycloid."""
function get_view_content(_state_ptr::Ptr{Cvoid})
    return tex"""\textbf{Deltoid}

A deltoid is the three-cusped hypocycloid with $k=R/r=3$. A point on the rolling circle traces one closed curve while that circle rolls inside the fixed circle."""
end

"""Create this leaf's three-cusped hypocycloid."""
function create_curve(state_ptr::Ptr{Cvoid}, center, fixed_radius::Real; kwargs...)
    return OdinJuliaBridge.create_new_deltoid(
        state_ptr, center, fixed_radius; kwargs...)
end

"""Publish this leaf's deltoid explanation."""
function publish_content(state_ptr::Ptr{Cvoid})
    OdinJuliaBridge.publish_view_content(state_ptr, get_view_content)
end

include("hypocycloid_shared.jl")

end


AnimationCatalog.animation(
    EuclidCurvesDeltoid.AnimationId, EuclidCurvesDeltoid.animation_entry)

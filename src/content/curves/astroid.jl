module EuclidCurvesAstroid

using UUIDs
using ..AnimationCatalog
using ..OdinJuliaBridge
using ..EuclidGeometry
using ..EuclidLatex

export get_view_content, initialize, clean, loop, animation_entry

const AnimationId = UUID("80aab994-2fc1-4c62-9adf-6e32cd54aca5")
const K = 4 // 1

"""Return explanatory content for the four-cusped hypocycloid."""
function get_view_content(_state_ptr::Ptr{Cvoid})
    return tex"""\textbf{Astroid}

An astroid is the four-cusped hypocycloid with $k=R/r=4$. Its tracing point lies on a circle whose radius is one quarter of the fixed circle's radius."""
end

"""Create this leaf's four-cusped hypocycloid."""
function create_curve(state_ptr::Ptr{Cvoid}, center, fixed_radius::Real; kwargs...)
    return OdinJuliaBridge.create_new_astroid(
        state_ptr, center, fixed_radius; kwargs...)
end

"""Publish this leaf's astroid explanation."""
function publish_content(state_ptr::Ptr{Cvoid})
    OdinJuliaBridge.publish_view_content(state_ptr, get_view_content)
end

include("hypocycloid_shared.jl")

end


AnimationCatalog.animation(
    EuclidCurvesAstroid.AnimationId, EuclidCurvesAstroid.animation_entry)

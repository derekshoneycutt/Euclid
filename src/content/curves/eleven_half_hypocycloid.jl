module EuclidCurvesElevenHalfHypocycloid

using UUIDs
using ..AnimationCatalog
using ..OdinJuliaBridge
using ..EuclidGeometry
using ..EuclidLatex

include("eleven_half_hypocycloid_content.jl")

export get_view_content, initialize, clean, loop, animation_entry

const AnimationId = UUID("d6fcda98-5195-457d-8154-939930ec00c5")
const K = 11 // 2

"""Return explanatory content for the eleven-cusped rational hypocycloid."""
function get_view_content(_state_ptr::Ptr{Cvoid})
    return EuclidCurvesElevenHalfHypocycloidContent.get_view_content()
end

"""Create this leaf's eleven-cusped rational hypocycloid."""
function create_curve(state_ptr::Ptr{Cvoid}, center, fixed_radius::Real; kwargs...)
    return OdinJuliaBridge.create_new_hypocycloid(
        state_ptr, center, fixed_radius, K; kwargs...)
end

"""Publish this leaf's rational-hypocycloid explanation."""
function publish_content(state_ptr::Ptr{Cvoid})
    OdinJuliaBridge.publish_view_content(state_ptr, get_view_content)
end

include("hypocycloid_shared.jl")

end


AnimationCatalog.animation(EuclidCurvesElevenHalfHypocycloid.AnimationId,
    EuclidCurvesElevenHalfHypocycloid.animation_entry)

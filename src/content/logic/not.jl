module EuclidLogicNot

using UUIDs
using ..AnimationCatalog
using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

export get_view_content, initialize, clean, loop, animation_entry

const AnimationId = UUID("9f6972f7-949b-4290-bfda-11dcbfcab409")
const RegionOperation = :difference

"""Return explanatory content for bounded negation as a Lune difference."""
function get_view_content(_state_ptr::Ptr{Cvoid})
    return tex"""\textbf{Not}

Within $A$, the condition $A \land \neg B$ holds where $A$ holds and $B$ does not. This is the Lune $A \setminus B$: the part of circle $A$ cut away from their overlap."""
end

"""Create this leaf's directional Lune region."""
function create_region(state_ptr::Ptr{Cvoid}, first_center, first_radius,
    second_center, second_radius; color)
    return OdinJuliaBridge.create_new_lune(state_ptr, first_center, first_radius,
        second_center, second_radius; color)
end

"""Publish this leaf's bounded-negation explanation."""
function publish_content(state_ptr::Ptr{Cvoid})
    OdinJuliaBridge.publish_view_content(state_ptr, get_view_content)
end

include("circle_region_shared.jl")

end

AnimationCatalog.animation(EuclidLogicNot.AnimationId,
    EuclidLogicNot.animation_entry)

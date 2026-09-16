module EuclidLogicAnd

using UUIDs
using ..AnimationCatalog
using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

export get_view_content, initialize, clean, loop, animation_entry

const AnimationId = UUID("8785c9e6-53e9-4433-b1ae-7e18cef22c88")
const RegionOperation = :intersection

"""Return explanatory content for conjunction as a Lens intersection."""
function get_view_content(_state_ptr::Ptr{Cvoid})
    return tex"""\textbf{And}

The conjunction $A \land B$ holds where both conditions hold. In the diagram, that is the Lens $A \cap B$: the overlap of the two circles."""
end

"""Create this leaf's Lens region."""
function create_region(state_ptr::Ptr{Cvoid}, first_center, first_radius,
    second_center, second_radius; color)
    return OdinJuliaBridge.create_new_lens(state_ptr, first_center, first_radius,
        second_center, second_radius; color)
end

"""Publish this leaf's conjunction explanation."""
function publish_content(state_ptr::Ptr{Cvoid})
    OdinJuliaBridge.publish_view_content(state_ptr, get_view_content)
end

include("circle_region_shared.jl")

end

AnimationCatalog.animation(EuclidLogicAnd.AnimationId,
    EuclidLogicAnd.animation_entry)

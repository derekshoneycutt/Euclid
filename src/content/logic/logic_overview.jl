module EuclidLogicOverview

using UUIDs
using ..AnimationCatalog
using ..OdinJuliaBridge
using ..EuclidLatex
using ..NullAnimation

export get_view_content, initialize, clean, loop, animation_entry

const AnimationId = UUID("2905c158-007b-4412-be60-20a27decc0b2")

"""Return introductory content for the Logic animation collection."""
function get_view_content(_state_ptr::Ptr{Cvoid})
    return tex"""\textbf{Logic}

Logical operations describe how conditions and sets combine. The diagrams here use bounded regions to make those relationships visible."""
end

"""Initialize the null animation and publish the Logic overview."""
function initialize(state_ptr::Ptr{Cvoid})
    NullAnimation.initialize(state_ptr)
    OdinJuliaBridge.publish_view_content(state_ptr, get_view_content)
end

"""Advance the shared null animation for the Logic overview."""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    NullAnimation.loop(state_ptr, dt)
end

"""Clean the shared null animation for the Logic overview."""
function clean(state_ptr::Ptr{Cvoid})
    NullAnimation.clean(state_ptr)
end

"""Dispatch one lifecycle operation for the Logic overview."""
function animation_entry(
    state_ptr::Ptr{Cvoid}, operation::Int32, dt::Float32)::Bool
    if operation == OdinJuliaBridge.ANIMATION_OPERATION_ENTER
        initialize(state_ptr)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_TICK
        loop(state_ptr, dt)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_EXIT
        clean(state_ptr)
    else
        return false
    end
    return true
end

end

AnimationCatalog.animation(
    EuclidLogicOverview.AnimationId, EuclidLogicOverview.animation_entry)

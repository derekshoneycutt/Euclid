module EuclidCurvesOverview

using UUIDs
using ..OdinJuliaBridge
using ..EuclidLatex
using ..NullAnimation
using ..AnimationCatalog

export get_view_content, initialize, clean, loop, animation_entry

const AnimationId = UUID("13d8650f-98d2-4701-9312-d9b6ce4c46a6")

"""Return the introductory view content for analytic curves."""
function get_view_content(_state_ptr::Ptr{Cvoid})
    return tex"""\textbf{Curves}

Here, we explore various kinds of curves in geometry."""
end

"""Initialize the null animation and publish the Curves overview."""
function initialize(state_ptr::Ptr{Cvoid})
    NullAnimation.initialize(state_ptr)
    OdinJuliaBridge.publish_view_content(state_ptr, get_view_content)
end

"""Advance the shared null animation for the Curves overview."""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    NullAnimation.loop(state_ptr, dt)
end

"""Clean the shared null animation for the Curves overview."""
function clean(state_ptr::Ptr{Cvoid})
    NullAnimation.clean(state_ptr)
end

"""Dispatch one lifecycle operation for the Curves overview."""
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
    EuclidCurvesOverview.AnimationId, EuclidCurvesOverview.animation_entry)

module HilbertOverview

using UUIDs
using ..AnimationCatalog

const AnimationId = UUID("65a8489e-e0bd-535f-bf47-3c5e9c9d70e6")

using ..OdinJuliaBridge
using ..EuclidLatex
using ..NullAnimation

include("hilbert_overview_content.jl")

export get_view_content, initialize, clean, loop, animation_entry

"""Emit the Hilbert Foundations of Geometry overview content."""
function get_view_content(_state_ptr::Ptr{Cvoid})
    return HilbertOverviewContent.get_view_content()
end

"""Initialize the null animation and publish the Hilbert overview."""
function initialize(state_ptr::Ptr{Cvoid})
    NullAnimation.initialize(state_ptr)
    OdinJuliaBridge.publish_view_content(state_ptr, get_view_content)
end

"""Advance the shared null animation for the Hilbert overview."""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    NullAnimation.loop(state_ptr, dt)
end

"""Clean the shared null animation for the Hilbert overview."""
function clean(state_ptr::Ptr{Cvoid})
    NullAnimation.clean(state_ptr)
end

"""Dispatch one lifecycle operation for the Hilbert overview."""
function animation_entry(
    state_ptr::Ptr{Cvoid}, operation::Int32, dt::Float32)::Bool

    if operation == OdinJuliaBridge.ANIMATION_OPERATION_PRESENTATION_SELECTION_CHANGED
        return true
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_ENTER
        OdinJuliaBridge.animation_content_specification(state_ptr)
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
    HilbertOverview.AnimationId, HilbertOverview.animation_entry)

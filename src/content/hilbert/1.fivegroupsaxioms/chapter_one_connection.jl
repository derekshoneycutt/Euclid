module HilbertChapterOneConnection

using UUIDs
using ..AnimationCatalog

const AnimationId = UUID("d58eb2e5-ea05-5a32-9159-616484b0cc42")

using ..OdinJuliaBridge
using ..EuclidLatex
using ..NullAnimation

include("chapter_one_connection_content.jl")

export get_view_content, initialize, clean, loop, animation_entry

"""Emit the Book I connection-axioms view content."""
function get_view_content(_state_ptr::Ptr{Cvoid})
    return HilbertChapterOneConnectionContent.get_view_content()
end

"""Initialize the null animation and publish the connection view."""
function initialize(state_ptr::Ptr{Cvoid})
    NullAnimation.initialize(state_ptr)
    OdinJuliaBridge.publish_view_content(state_ptr, get_view_content)
end

"""Advance the shared null animation for the connection view."""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    NullAnimation.loop(state_ptr, dt)
end

"""Clean the shared null animation for the connection view."""
function clean(state_ptr::Ptr{Cvoid})
    NullAnimation.clean(state_ptr)
end

"""Dispatch one lifecycle operation for the connection animation."""
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
    HilbertChapterOneConnection.AnimationId, HilbertChapterOneConnection.animation_entry)

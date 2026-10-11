module HilbertChapterOneConsequences

using UUIDs
using ..AnimationCatalog

const AnimationId = UUID("2ee7be59-eea9-5903-b552-d3f0c18084ac")

using ..OdinJuliaBridge
using ..EuclidLatex
using ..NullAnimation

include("chapter_one_consequences_content.jl")

export get_view_content, initialize, clean, loop, animation_entry

"""Emit the Book I consequences view content."""
function get_view_content(_state_ptr::Ptr{Cvoid})
    return HilbertChapterOneConsequencesContent.get_view_content()
end

"""Initialize the null animation and publish the consequences view."""
function initialize(state_ptr::Ptr{Cvoid})
    NullAnimation.initialize(state_ptr)
    OdinJuliaBridge.publish_view_content(state_ptr, get_view_content)
end

"""Advance the shared null animation for the consequences view."""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    NullAnimation.loop(state_ptr, dt)
end

"""Clean the shared null animation for the consequences view."""
function clean(state_ptr::Ptr{Cvoid})
    NullAnimation.clean(state_ptr)
end

"""Dispatch one lifecycle operation for the consequences animation."""
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
    HilbertChapterOneConsequences.AnimationId,
    HilbertChapterOneConsequences.animation_entry)

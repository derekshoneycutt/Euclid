module HilbertChapterOneOrder

using UUIDs
using ..AnimationCatalog

const AnimationId = UUID("ccb3afdf-4679-5dc7-9815-a7c3263d01b1")

using ..OdinJuliaBridge
using ..EuclidLatex
using ..NullAnimation

include("chapter_one_order_content.jl")

export get_view_content, initialize, clean, loop, animation_entry

"""Emit the Book I order-axioms view content."""
function get_view_content(_state_ptr::Ptr{Cvoid})
    return HilbertChapterOneOrderContent.get_view_content()
end

"""Initialize the null animation and publish the order view."""
function initialize(state_ptr::Ptr{Cvoid})
    NullAnimation.initialize(state_ptr)
    OdinJuliaBridge.publish_view_content(state_ptr, get_view_content)
end

"""Advance the shared null animation for the order view."""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    NullAnimation.loop(state_ptr, dt)
end

"""Clean the shared null animation for the order view."""
function clean(state_ptr::Ptr{Cvoid})
    NullAnimation.clean(state_ptr)
end

"""Dispatch one lifecycle operation for the order animation."""
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
    HilbertChapterOneOrder.AnimationId, HilbertChapterOneOrder.animation_entry)

module HilbertChapterOneOrder

using UUIDs
using ..AnimationCatalog

const AnimationId = UUID("ccb3afdf-4679-5dc7-9815-a7c3263d01b1")

using ..OdinJuliaBridge
using ..EuclidLatex
using ..NullAnimation

export get_view_text, initialize, clean, loop, animation_entry

"""Emit the Book I order-axioms view text."""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms §3 Group II: Axioms of Order

The axioms of this group define the idea expressed by the word "between," and make possible, upon the basis of this idea, an order of sequence of the points upon a straight line, in a plane, and in space. The points of a straight line have a certain relation to one another which the word "between" serves to describe.

...

Axioms II, 1-4 contain statements concerning the points of a straight line only, and, hence, we will call them the linear axioms of group II. Axiom II, 5 relates to the elements of plane geometry and, consequently, shall be called the plane axiom of group II."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms} \textit{§3 Group II: Axioms of Order}

The axioms of this group define the idea expressed by the word "between," and make possible, upon the basis of this idea, an order of sequence of the points upon a straight line, in a plane, and in space. The points of a straight line have a certain relation to one another which the word "between" serves to describe.

...

Axioms II, 1-4 contain statements concerning the points of a straight line only, and, hence, we will call them the linear axioms of group II. Axiom II, 5 relates to the elements of plane geometry and, consequently, shall be called the plane axiom of group II."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Initialize the null animation and publish the order view."""
function initialize(state_ptr::Ptr{Cvoid})
    NullAnimation.initialize(state_ptr)
    OdinJuliaBridge.publish_view_update(state_ptr, get_view_text)
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

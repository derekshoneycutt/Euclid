module HilbertChapterOneConnection

using UUIDs
using ..AnimationCatalog

const AnimationId = UUID("d58eb2e5-ea05-5a32-9159-616484b0cc42")

using ..OdinJuliaBridge
using ..EuclidLatex
using ..NullAnimation

export get_view_text, initialize, clean, loop, animation_entry

"""Emit the Book I connection-axioms view text."""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms §2 Group I: Axioms of Connection

The axioms of this group establish a connection between the concepts indicated above; namely, points, straight lines, and planes.

...

Axioms I, 1-2 contain statements concerning points and straight lines only; that is, concerning the elements of plane geometry. We will call them, therefore, the plane axioms of group I, in order to distinguish them from the axioms I, 3-7, which we will designate briefly as the space axioms of this group.
Of the theorems which follow from the axioms I, 3-7, we shall mention only 2."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms} \textit{§2 Group I: Axioms of Connection}

The axioms of this group establish a connection between the concepts indicated above; namely, points, straight lines, and planes.

...

Axioms I, 1-2 contain statements concerning points and straight lines only; that is, concerning the elements of plane geometry. We will call them, therefore, the plane axioms of group I, in order to distinguish them from the axioms I, 3-7, which we will designate briefly as the space axioms of this group.
Of the theorems which follow from the axioms I, 3-7, we shall mention only 2."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Initialize the null animation and publish the connection view."""
function initialize(state_ptr::Ptr{Cvoid})
    NullAnimation.initialize(state_ptr)
    OdinJuliaBridge.publish_view_update(state_ptr, get_view_text)
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
    HilbertChapterOneConnection.AnimationId, HilbertChapterOneConnection.animation_entry)

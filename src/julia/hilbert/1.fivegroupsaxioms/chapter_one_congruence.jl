module HilbertChapterOneCongruence

using ..OdinJuliaBridge
using ..EuclidLatex
using ..NullAnimation

export get_view_text, initialize, clean, loop, animation_entry

"""Emit the Book I congruence-axioms view text."""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms §5 Group IV: Axioms of Congruence

The axioms of this group define the idea of congruence or displacement.

Segments stand in a certain relation to one another which is described by the word "congruent."

...

Axioms IV, 1-3 contain statements concerning the congruence of segments of a straight line only. They may, therefore, be called the linear axioms of group IV. Axioms IV, 4, 5 contain statements relating to the congruence of angles. Axiom IV, 6 gives the connection between the congruence of segments and the congruence of angles. Axioms IV, 4-6 contain statements regarding the elements of plane geometry and may be called the plane axioms of group IV."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms} \textit{§5 Group IV: Axioms of Congruence}

The axioms of this group define the idea of congruence or displacement.

Segments stand in a certain relation to one another which is described by the word "congruent."

...

Axioms IV, 1-3 contain statements concerning the congruence of segments of a straight line only. They may, therefore, be called the linear axioms of group IV. Axioms IV, 4, 5 contain statements relating to the congruence of angles. Axiom IV, 6 gives the connection between the congruence of segments and the congruence of angles. Axioms IV, 4-6 contain statements regarding the elements of plane geometry and may be called the plane axioms of group IV."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Initialize the null animation and publish the congruence view."""
function initialize(state_ptr::Ptr{Cvoid})
    NullAnimation.initialize(state_ptr)
    OdinJuliaBridge.publish_view_update(state_ptr, get_view_text)
end

"""Advance the shared null animation for the congruence view."""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    NullAnimation.loop(state_ptr, dt)
end

"""Clean the shared null animation for the congruence view."""
function clean(state_ptr::Ptr{Cvoid})
    NullAnimation.clean(state_ptr)
end

"""Dispatch one lifecycle operation for the congruence animation."""
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

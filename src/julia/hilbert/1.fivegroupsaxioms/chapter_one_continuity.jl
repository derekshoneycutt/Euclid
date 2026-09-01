module HilbertChapterOneContinuity

using ..OdinJuliaBridge
using ..EuclidLatex
using ..NullAnimation

export get_view_text, initialize, clean, loop, animation_entry

"""Emit the Book I continuity-axioms view text."""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms §8 Group V. Axiom of Continuity. (Archimedean Axiom.)

This axiom makes possible the introduction into geometry of the idea of continuity. In order to state this axiom, we must first establish a convention concerning the equality of two segments. For this purpose, we can either base our idea of equality upon the axioms relating to the congruence of segments and define as "equal" the correspondingly congruent segments, or, upon the basis of groups I and II, we may determine how, by suitable constructions (see Chap. V, Section 24), a segment is to be laid off from a point of a given straight line so that a new, definite segment is obtained "equal" to it. In conformity with such a convention, the axiom of Archimedes may be stated as follows.

The axiom of Archimedes is a linear axiom.

...

Remark. To the preceding five groups of axioms, we may add the axiom of completeness, which, although not of a purely geometrical nature, merits particular attention from a theoretical point of view."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms} \textit{§8 Group V. Axiom of Continuity. (Archimedean Axiom.)}

This axiom makes possible the introduction into geometry of the idea of continuity. In order to state this axiom, we must first establish a convention concerning the equality of two segments. For this purpose, we can either base our idea of equality upon the axioms relating to the congruence of segments and define as "equal" the correspondingly congruent segments, or, upon the basis of groups I and II, we may determine how, by suitable constructions (see Chap. V, Section 24), a segment is to be laid off from a point of a given straight line so that a new, definite segment is obtained "equal" to it. In conformity with such a convention, the axiom of Archimedes may be stated as follows.

The axiom of Archimedes is a linear axiom.

...

Remark. To the preceding five groups of axioms, we may add the axiom of completeness, which, although not of a purely geometrical nature, merits particular attention from a theoretical point of view."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Initialize the null animation and publish the continuity view."""
function initialize(state_ptr::Ptr{Cvoid})
    NullAnimation.initialize(state_ptr)
    OdinJuliaBridge.publish_view_update(state_ptr, get_view_text)
end

"""Advance the shared null animation for the continuity view."""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    NullAnimation.loop(state_ptr, dt)
end

"""Clean the shared null animation for the continuity view."""
function clean(state_ptr::Ptr{Cvoid})
    NullAnimation.clean(state_ptr)
end

"""Dispatch one lifecycle operation for the continuity animation."""
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

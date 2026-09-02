module HilbertChapterOneCongruenceConsequences

using UUIDs
using ..AnimationCatalog

const AnimationId = UUID("c80d3bfc-88be-5b70-af19-c7edcc240c23")

using ..OdinJuliaBridge
using ..EuclidLatex
using ..NullAnimation

export get_view_text, initialize, clean, loop, animation_entry

"""Emit the consequences-of-congruence view text."""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms §7 Consequences of the Axioms of Congruence

Suppose the segment AB is congruent to the segment A'B'. Since, according to axiom IV, 1, the segment AB is congruent to itself, it follows from axiom IV, 2 that A'B' is congruent to AB; that is to say, if AB ≡ A'B', then A'B' ≡ AB. We say, then, that the two segments are congruent to one another.

Let A, B, C, D, ..., K, L and A', B', C', D', ..., K', L' be two series of points on the straight lines a and a', respectively, so that all the corresponding segments AB and A'B', AC and A'C', BC and B'C', ..., KL and K'L' are respectively congruent. Then the two series of points are said to be congruent to one another. A and A', B and B', ..., L and L' are called corresponding points of the two congruent series of points.

From the linear axioms IV, 1-3, we can easily deduce several theorems."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms} \textit{§7 Consequences of the Axioms of Congruence}

Suppose the segment $AB$ is congruent to the segment $A'B'$. Since, according to axiom IV, 1, the segment $AB$ is congruent to itself, it follows from axiom IV, 2 that $A'B'$ is congruent to $AB$; that is to say, if $AB \equiv A'B'$, then $A'B' \equiv AB$. We say, then, that the two segments are congruent to one another.

Let $A, B, C, D, ..., K, L$ and $A', B', C', D', ..., K', L'$ be two series of points on the straight lines $a$ and $a'$, respectively, so that all the corresponding segments $AB$ and $A'B'$, $AC$ and $A'C'$, $BC$ and $B'C', ..., KL$ and $K'L'$ are respectively congruent. Then the two series of points are said to be congruent to one another. $A$ and $A', B and B', ..., L and L'$ are called corresponding points of the two congruent series of points.

From the linear axioms IV, 1-3, we can easily deduce several theorems."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Initialize the null animation and publish the congruence consequences view."""
function initialize(state_ptr::Ptr{Cvoid})
    NullAnimation.initialize(state_ptr)
    OdinJuliaBridge.publish_view_update(state_ptr, get_view_text)
end

"""Advance the shared null animation for the congruence consequences view."""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    NullAnimation.loop(state_ptr, dt)
end

"""Clean the shared null animation for the congruence consequences view."""
function clean(state_ptr::Ptr{Cvoid})
    NullAnimation.clean(state_ptr)
end

"""Dispatch one lifecycle operation for the congruence consequences animation."""
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
    HilbertChapterOneCongruenceConsequences.AnimationId,
    HilbertChapterOneCongruenceConsequences.animation_entry)

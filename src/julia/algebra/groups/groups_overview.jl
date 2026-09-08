module EuclidAlgebraGroupsOverview

using UUIDs
using ..AnimationCatalog

const AnimationId = UUID("1c54c525-f85a-55a9-931b-8cfaafabec03")

using ..OdinJuliaBridge
using ..EuclidLatex
using ..NullAnimation

export get_view_content, initialize, clean, loop, animation_entry

const LatexDocument = raw"""\textbf{Algebra - Groups}

For this project, think of a group as a collection of actions taken on a figure. The main questions are: what motions are allowed, how do they compose or behave when you do more than one in sequence, and what happens when you repeat or undo them?

Formally, a group is a set $G$ with a binary operation $\circ: G \times G \to G$ satisfying 4 axioms:

\textbf{1. Closure}: if $a, b \in G$, then $a \circ b \in G$.\newline
\textbf{2. Associativity}: $(a \circ b) \circ c = a \circ (b \circ c)$ for all $a,b,c \in G$.\newline
\textbf{3. Identity}: there is an element $e \in G$ with $e \circ a = a \circ e = a$ for all $a \in G$.\newline
\textbf{4. Inverses}: for each $a \in G$, there is $a^{-1} \in G$ with $a \circ a^{-1} = a^{-1} \circ a = e$.

Some actions commute and some do not. If $a \circ b = b \circ a$ for all $a,b \in G$, then the group is \textit{commutative}, also called \textit{abelian}. Commutativity is not required.

In this sequence, we move from simple discrete symmetries to continuous geometric motions on the Euclidean plane."""

"""Emit the root view content for the group-theory animation sequence."""
function get_view_content(_state_ptr::Ptr{Cvoid})
    return EuclidLatex.TeXDocument(LatexDocument)
end

"""Initialize the null animation and publish the Groups overview."""
function initialize(state_ptr::Ptr{Cvoid})
    NullAnimation.initialize(state_ptr)
    OdinJuliaBridge.publish_view_content(state_ptr, get_view_content)
end

"""Advance the shared null animation for the Groups overview."""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    NullAnimation.loop(state_ptr, dt)
end

"""Clean the shared null animation for the Groups overview."""
function clean(state_ptr::Ptr{Cvoid})
    NullAnimation.clean(state_ptr)
end

"""Dispatch one lifecycle operation for the Groups overview."""
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
    EuclidAlgebraGroupsOverview.AnimationId, EuclidAlgebraGroupsOverview.animation_entry)

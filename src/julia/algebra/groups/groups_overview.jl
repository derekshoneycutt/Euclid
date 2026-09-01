module EuclidAlgebraGroupsOverview

using ..OdinJuliaBridge
using ..EuclidLatex
using ..NullAnimation

export get_view_text, initialize, clean, loop, animation_entry

const Fallback = raw"""Algebra - Groups
    
For this project, think of a group as a collection of actions taken on a figure. The main questions are: what motions are allowed, how do they compose or behave when you do more than one in sequence, and what happens when you repeat or undo them?

Formally, a group is a set G with a binary operation ∘: G × G → G satisfying 4 axioms:

1. Closure: if a, b ∈ G, then a ∘ b ∈ G.
2. Associativity: (a ∘ b) ∘ c = a ∘ (b ∘ c) for all a,b,c ∈ G.
3. Identity: there is an element e ∈ G with e ∘ a = a ∘ e = a for all a ∈ G.
4. Inverses: for each a ∈ G, there is a⁻¹ ∈ G with a ∘ a⁻¹ = a⁻¹ ∘ a = e.

Some actions commute and some do not. If a ∘ b = b ∘ a for all a,b ∈ G, then the group is commutative, also called abelian. Commutativity is not required.

In this sequence, we move from simple discrete symmetries to continuous geometric motions on the Euclidean plane."""

const LatexDocument = raw"""\textbf{Algebra - Groups}

For this project, think of a group as a collection of actions taken on a figure. The main questions are: what motions are allowed, how do they compose or behave when you do more than one in sequence, and what happens when you repeat or undo them?

Formally, a group is a set $G$ with a binary operation $\circ: G \times G \to G$ satisfying 4 axioms:

\textbf{1. Closure}: if $a, b \in G$, then $a \circ b \in G$.\newline
\textbf{2. Associativity}: $(a \circ b) \circ c = a \circ (b \circ c)$ for all $a,b,c \in G$.\newline
\textbf{3. Identity}: there is an element $e \in G$ with $e \circ a = a \circ e = a$ for all $a \in G$.\newline
\textbf{4. Inverses}: for each $a \in G$, there is $a^{-1} \in G$ with $a \circ a^{-1} = a^{-1} \circ a = e$.

Some actions commute and some do not. If $a \circ b = b \circ a$ for all $a,b \in G$, then the group is \textit{commutative}, also called \textit{abelian}. Commutativity is not required.

In this sequence, we move from simple discrete symmetries to continuous geometric motions on the Euclidean plane."""

"""Emit the root view text for the group-theory animation sequence."""
function get_view_text(state_ptr::Ptr{Cvoid})
    EuclidLatex.emit_latex_view_text!(state_ptr, LatexDocument, Fallback)
end

"""Initialize the null animation and publish the Groups overview."""
function initialize(state_ptr::Ptr{Cvoid})
    NullAnimation.initialize(state_ptr)
    OdinJuliaBridge.publish_view_update(state_ptr, get_view_text)
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

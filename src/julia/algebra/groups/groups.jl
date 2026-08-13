module EuclidAlgebraGroups

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidGeometry
using ..EuclidLatex
using ..NullAnimation

include("./z_2.jl")
include("./z_2_closure.jl")
include("./z_2_identity.jl")
include("./z_2_inverse.jl")
include("./C_n.jl")
include("./C_n_associative.jl")

const GroupsRootFallback = raw"""Algebra - Groups
    
For this project, think of a group as a collection of actions taken on a figure. The main questions are: what motions are allowed, how do they compose or behave when you do more than one in sequence, and what happens when you repeat or undo them?

Formally, a group is a set G with a binary operation ∘: G × G → G satisfying 4 axioms:

1. Closure: if a, b ∈ G, then a ∘ b ∈ G.
2. Associativity: (a ∘ b) ∘ c = a ∘ (b ∘ c) for all a,b,c ∈ G.
3. Identity: there is an element e ∈ G with e ∘ a = a ∘ e = a for all a ∈ G.
4. Inverses: for each a ∈ G, there is a⁻¹ ∈ G with a ∘ a⁻¹ = a⁻¹ ∘ a = e.

Some actions commute and some do not. If a ∘ b = b ∘ a for all a,b ∈ G, then the group is commutative, also called abelian. Commutativity is not required.

In this sequence, we move from simple discrete symmetries to continuous geometric motions on the Euclidean plane."""

const GroupsRootLatexDocument = raw"""\textbf{Algebra - Groups}

For this project, think of a group as a collection of actions taken on a figure. The main questions are: what motions are allowed, how do they compose or behave when you do more than one in sequence, and what happens when you repeat or undo them?

Formally, a group is a set $G$ with a binary operation $\circ: G \times G \to G$ satisfying 4 axioms:

\textbf{1. Closure}: if $a, b \in G$, then $a \circ b \in G$.\newline
\textbf{2. Associativity}: $(a \circ b) \circ c = a \circ (b \circ c)$ for all $a,b,c \in G$.\newline
\textbf{3. Identity}: there is an element $e \in G$ with $e \circ a = a \circ e = a$ for all $a \in G$.\newline
\textbf{4. Inverses}: for each $a \in G$, there is $a^{-1} \in G$ with $a \circ a^{-1} = a^{-1} \circ a = e$.

Some actions commute and some do not. If $a \circ b = b \circ a$ for all $a,b \in G$, then the group is \textit{commutative}, also called \textit{abelian}. Commutativity is not required.

In this sequence, we move from simple discrete symmetries to continuous geometric motions on the Euclidean plane."""

function get_view_text_root_groups(state_ptr::Ptr{Cvoid})
    EuclidLatex.emit_latex_view_text!(state_ptr, GroupsRootLatexDocument, GroupsRootFallback)
end

function stable_child_id(parent_stable_id::AbstractString, name::AbstractString)
    OdinJuliaBridge.animation_stable_id_from_key(
        "child:" * String(parent_stable_id) * ":" * String(name))
end

function register_child_animation(
    state_ptr::Ptr{Cvoid}, getViewText, init, loop, clean, name::AbstractString,
    parent_stable_id::AbstractString)

    child_stable_id = stable_child_id(parent_stable_id, name)

    OdinJuliaBridge.add_child_animation_interface(
        state_ptr, getViewText, init, loop, clean, String(name),
        child_stable_id, String(parent_stable_id))

    return child_stable_id
end

function init_euclid_scripts(state_ptr::Ptr{Cvoid}, rootId)
    groupsId = register_child_animation(
        state_ptr, get_view_text_root_groups, NullAnimation.initialize,
        NullAnimation.loop, NullAnimation.clean,
        "Groups", rootId)

        z2_id = register_child_animation(
            state_ptr,
            EuclidAlgebraGroupsZ2.get_view_text,
            EuclidAlgebraGroupsZ2.initialize,
            EuclidAlgebraGroupsZ2.loop,
            EuclidAlgebraGroupsZ2.clean,
            "ℤ₂",
            groupsId)
            register_child_animation(
                state_ptr,
                EuclidAlgebraGroupsZ2Closure.get_view_text,
                EuclidAlgebraGroupsZ2Closure.initialize,
                EuclidAlgebraGroupsZ2Closure.loop,
                EuclidAlgebraGroupsZ2Closure.clean,
                "Closure",
                z2_id)
            register_child_animation(
                state_ptr,
                EuclidAlgebraGroupsZ2Identity.get_view_text,
                EuclidAlgebraGroupsZ2Identity.initialize,
                EuclidAlgebraGroupsZ2Identity.loop,
                EuclidAlgebraGroupsZ2Identity.clean,
                "Identity",
                z2_id)
            register_child_animation(
                state_ptr,
                EuclidAlgebraGroupsZ2Inverse.get_view_text,
                EuclidAlgebraGroupsZ2Inverse.initialize,
                EuclidAlgebraGroupsZ2Inverse.loop,
                EuclidAlgebraGroupsZ2Inverse.clean,
                "Inverse",
                z2_id)
        Cn_id = register_child_animation(
            state_ptr,
            EuclidAlgebraGroupsCn.get_view_text,
            EuclidAlgebraGroupsCn.initialize,
            EuclidAlgebraGroupsCn.loop,
            EuclidAlgebraGroupsCn.clean,
            "Cₙ",
            groupsId)
            register_child_animation(
                state_ptr,
                EuclidAlgebraGroupsCnAssociative.get_view_text,
                EuclidAlgebraGroupsCnAssociative.initialize,
                EuclidAlgebraGroupsCnAssociative.loop,
                EuclidAlgebraGroupsCnAssociative.clean,
                "Associative",
                Cn_id)

end

end

module EuclidAlgebraGroups

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidGeometry
using ..EuclidLatex
using ..NullAnimation

include("./z_2.jl")
include("./z_2_closure.jl")

const DynviewBlockOutput = OdinJuliaBridge.BRIDGE_DYNVIEW_BLOCK_OUTPUT
const DynviewStyleBold = OdinJuliaBridge.BRIDGE_DYNVIEW_STYLE_BOLD
const DynviewStyleOutput = OdinJuliaBridge.BRIDGE_DYNVIEW_STYLE_OUTPUT

const GroupsRootFallback = raw"""Algebra - Groups
    
For this project, think of a group as a collection of actions taken on a figure. The main questions are: what motions are allowed, how do they compose or behave when you do more than one in sequence, and what happens when you repeat or undo them?

Formally, a group is a set G with a binary operation ∘: G × G → G satisfying 4 axioms:

1. Closure: if a, b ∈ G, then a ∘ b ∈ G.
2. Associativity: (a ∘ b) ∘ c = a ∘ (b ∘ c) for all a,b,c ∈ G.
3. Identity: there is an element e ∈ G with e ∘ a = a ∘ e = a for all a ∈ G.
4. Inverses: for each a ∈ G, there is a⁻¹ ∈ G with a ∘ a⁻¹ = a⁻¹ ∘ a = e.

Some actions commute and some do not. If a ∘ b = b ∘ a for all a,b ∈ G, then the group is commutative, also called abelian. Commutativity is not required.

In this sequence, we move from simple discrete symmetries to continuous geometric motions on the Euclidean plane."""

function get_view_text_root_groups(state_ptr::Ptr{Cvoid})
    fallback = GroupsRootFallback

    if OdinJuliaBridge.dynview_reset_stream(state_ptr) != OdinJuliaBridge.BRIDGE_STATUS_OK ||
        OdinJuliaBridge.dynview_begin_block(state_ptr, DynviewBlockOutput, Int32(1)) != OdinJuliaBridge.BRIDGE_STATUS_OK
        return fallback
    end

    if OdinJuliaBridge.dynview_copyable_text_run(state_ptr, GroupsRootFallback) != OdinJuliaBridge.BRIDGE_STATUS_OK
        return fallback
    end

    if OdinJuliaBridge.dynview_text_run(state_ptr, "Algebra - Groups", DynviewStyleBold) != OdinJuliaBridge.BRIDGE_STATUS_OK ||
        OdinJuliaBridge.dynview_line_break(state_ptr) != OdinJuliaBridge.BRIDGE_STATUS_OK ||
        OdinJuliaBridge.dynview_line_break(state_ptr) != OdinJuliaBridge.BRIDGE_STATUS_OK
        return fallback
    end

    if OdinJuliaBridge.dynview_text_run(
        state_ptr,
        "For this project, think of a group as a collection of actions taken on a figure. The main questions are: what motions are allowed, how do they compose or behave when you do more than one in sequence, and what happens when you repeat or undo them?",
        DynviewStyleOutput) != OdinJuliaBridge.BRIDGE_STATUS_OK ||
        OdinJuliaBridge.dynview_line_break(state_ptr) != OdinJuliaBridge.BRIDGE_STATUS_OK ||
        OdinJuliaBridge.dynview_line_break(state_ptr) != OdinJuliaBridge.BRIDGE_STATUS_OK
        return fallback
    end

    if OdinJuliaBridge.dynview_text_run(state_ptr, "Formally, a group is a set ", DynviewStyleOutput) != OdinJuliaBridge.BRIDGE_STATUS_OK ||
        !EuclidLatex.replay_emit_math_block!(state_ptr, "G") ||
        OdinJuliaBridge.dynview_text_run(state_ptr, " with a binary operation ", DynviewStyleOutput) != OdinJuliaBridge.BRIDGE_STATUS_OK ||
        !EuclidLatex.replay_emit_math_block!(state_ptr, "\\circ: G \\times G \\to G") ||
        OdinJuliaBridge.dynview_text_run(state_ptr, " satisfying 4 axioms:", DynviewStyleOutput) != OdinJuliaBridge.BRIDGE_STATUS_OK ||
        OdinJuliaBridge.dynview_line_break(state_ptr) != OdinJuliaBridge.BRIDGE_STATUS_OK ||
        OdinJuliaBridge.dynview_line_break(state_ptr) != OdinJuliaBridge.BRIDGE_STATUS_OK
        return fallback
    end

    if OdinJuliaBridge.dynview_text_run(state_ptr, "1. Closure: if ", DynviewStyleOutput) != OdinJuliaBridge.BRIDGE_STATUS_OK ||
        !EuclidLatex.replay_emit_math_block!(state_ptr, "a, b \\in G") ||
        OdinJuliaBridge.dynview_text_run(state_ptr, ", then ", DynviewStyleOutput) != OdinJuliaBridge.BRIDGE_STATUS_OK ||
        !EuclidLatex.replay_emit_math_block!(state_ptr, "a \\circ b \\in G") ||
        OdinJuliaBridge.dynview_text_run(state_ptr, ".", DynviewStyleOutput) != OdinJuliaBridge.BRIDGE_STATUS_OK ||
        OdinJuliaBridge.dynview_line_break(state_ptr) != OdinJuliaBridge.BRIDGE_STATUS_OK
        return fallback
    end

    if OdinJuliaBridge.dynview_text_run(state_ptr, "2. Associativity: ", DynviewStyleOutput) != OdinJuliaBridge.BRIDGE_STATUS_OK ||
        !EuclidLatex.replay_emit_math_block!(state_ptr, "(a \\circ b) \\circ c = a \\circ (b \\circ c)") ||
        OdinJuliaBridge.dynview_text_run(state_ptr, " for all ", DynviewStyleOutput) != OdinJuliaBridge.BRIDGE_STATUS_OK ||
        !EuclidLatex.replay_emit_math_block!(state_ptr, "a,b,c \\in G") ||
        OdinJuliaBridge.dynview_text_run(state_ptr, ".", DynviewStyleOutput) != OdinJuliaBridge.BRIDGE_STATUS_OK ||
        OdinJuliaBridge.dynview_line_break(state_ptr) != OdinJuliaBridge.BRIDGE_STATUS_OK
        return fallback
    end

    if OdinJuliaBridge.dynview_text_run(state_ptr, "3. Identity: there is an element ", DynviewStyleOutput) != OdinJuliaBridge.BRIDGE_STATUS_OK ||
        !EuclidLatex.replay_emit_math_block!(state_ptr, "e \\in G") ||
        OdinJuliaBridge.dynview_text_run(state_ptr, " with ", DynviewStyleOutput) != OdinJuliaBridge.BRIDGE_STATUS_OK ||
        !EuclidLatex.replay_emit_math_block!(state_ptr, "e \\circ a = a \\circ e = a") ||
        OdinJuliaBridge.dynview_text_run(state_ptr, " for all ", DynviewStyleOutput) != OdinJuliaBridge.BRIDGE_STATUS_OK ||
        !EuclidLatex.replay_emit_math_block!(state_ptr, "a \\in G") ||
        OdinJuliaBridge.dynview_text_run(state_ptr, ".", DynviewStyleOutput) != OdinJuliaBridge.BRIDGE_STATUS_OK ||
        OdinJuliaBridge.dynview_line_break(state_ptr) != OdinJuliaBridge.BRIDGE_STATUS_OK
        return fallback
    end

    if OdinJuliaBridge.dynview_text_run(state_ptr, "4. Inverses: for each ", DynviewStyleOutput) != OdinJuliaBridge.BRIDGE_STATUS_OK ||
        !EuclidLatex.replay_emit_math_block!(state_ptr, "a \\in G") ||
        OdinJuliaBridge.dynview_text_run(state_ptr, ", there is ", DynviewStyleOutput) != OdinJuliaBridge.BRIDGE_STATUS_OK ||
        !EuclidLatex.replay_emit_math_block!(state_ptr, "a^{-1} \\in G") ||
        OdinJuliaBridge.dynview_text_run(state_ptr, " with ", DynviewStyleOutput) != OdinJuliaBridge.BRIDGE_STATUS_OK ||
        !EuclidLatex.replay_emit_math_block!(state_ptr, "a \\circ a^{-1} = a^{-1} \\circ a = e") ||
        OdinJuliaBridge.dynview_text_run(state_ptr, ".", DynviewStyleOutput) != OdinJuliaBridge.BRIDGE_STATUS_OK ||
        OdinJuliaBridge.dynview_line_break(state_ptr) != OdinJuliaBridge.BRIDGE_STATUS_OK ||
        OdinJuliaBridge.dynview_line_break(state_ptr) != OdinJuliaBridge.BRIDGE_STATUS_OK
        return fallback
    end

    if OdinJuliaBridge.dynview_text_run(state_ptr, "Some actions commute and some do not. If ", DynviewStyleOutput) != OdinJuliaBridge.BRIDGE_STATUS_OK ||
        !EuclidLatex.replay_emit_math_block!(state_ptr, "a \\circ b = b \\circ a") ||
        OdinJuliaBridge.dynview_text_run(state_ptr, " for all ", DynviewStyleOutput) != OdinJuliaBridge.BRIDGE_STATUS_OK ||
        !EuclidLatex.replay_emit_math_block!(state_ptr, "a,b \\in G") ||
        OdinJuliaBridge.dynview_text_run(state_ptr, ", then the group is commutative, also called abelian. Commutativity is not required.", DynviewStyleOutput) != OdinJuliaBridge.BRIDGE_STATUS_OK ||
        OdinJuliaBridge.dynview_line_break(state_ptr) != OdinJuliaBridge.BRIDGE_STATUS_OK ||
        OdinJuliaBridge.dynview_line_break(state_ptr) != OdinJuliaBridge.BRIDGE_STATUS_OK
        return fallback
    end

    if OdinJuliaBridge.dynview_text_run(
        state_ptr,
        "In this sequence, we move from simple discrete symmetries to continuous geometric motions on the Euclidean plane.",
        DynviewStyleOutput) != OdinJuliaBridge.BRIDGE_STATUS_OK ||
        OdinJuliaBridge.dynview_end_block(state_ptr) != OdinJuliaBridge.BRIDGE_STATUS_OK
        return fallback
    end

    return fallback
end

function stable_child_id(parent_id::Integer, name::AbstractString)
    OdinJuliaBridge.animation_stable_id_from_key(
        "child:" * string(parent_id) * ":" * String(name))
end

function register_child_animation(
    state_ptr::Ptr{Cvoid}, getViewText, init, loop, clean, name::AbstractString, parent_id::Integer)

    OdinJuliaBridge.add_child_animation_interface(
        state_ptr, getViewText, init, loop, clean, String(name),
        stable_child_id(parent_id, name), parent_id)
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

end

end

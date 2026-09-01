module EuclidAlgebraGroups

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidGeometry
using ..EuclidLatex
using ..NullAnimation

include("./groups_overview.jl")
include("./z_2.jl")
include("./z_2_closure.jl")
include("./z_2_identity.jl")
include("./z_2_inverse.jl")
include("./C_n.jl")
include("./C_n_associative.jl")
include("./C_n_abelian.jl")

"""Derive a stable child animation id from a parent id and child name."""
function stable_child_id(parent_stable_id::AbstractString, name::AbstractString)
    OdinJuliaBridge.animation_stable_id_from_key(
        "child:" * String(parent_stable_id) * ":" * String(name))
end

"""Register a child animation interface under a parent stable id, returning its id."""
function register_child_animation(
    state_ptr::Ptr{Cvoid}, entry, name::AbstractString,
    parent_stable_id::AbstractString)

    child_stable_id = stable_child_id(parent_stable_id, name)
    OdinJuliaBridge.add_child_animation_interface(
        state_ptr, entry, String(name),
        child_stable_id, String(parent_stable_id))

    return child_stable_id
end

"""Register the group-theory animation interfaces under the root id."""
function init_euclid_scripts(state_ptr::Ptr{Cvoid}, root_id)
    groups_id = register_child_animation(
        state_ptr, EuclidAlgebraGroupsOverview.animation_entry,
        "Groups", root_id)

        z2_id = register_child_animation(
            state_ptr,
            EuclidAlgebraGroupsZ2.animation_entry,
            "ℤ₂",
            groups_id)
            register_child_animation(
                state_ptr,
                EuclidAlgebraGroupsZ2Closure.animation_entry,
                "Closure",
                z2_id)
            register_child_animation(
                state_ptr,
                EuclidAlgebraGroupsZ2Identity.animation_entry,
                "Identity",
                z2_id)
            register_child_animation(
                state_ptr,
                EuclidAlgebraGroupsZ2Inverse.animation_entry,
                "Inverse",
                z2_id)
        cn_id = register_child_animation(
            state_ptr,
            EuclidAlgebraGroupsCn.animation_entry,
            "Cₙ",
            groups_id)
            register_child_animation(
                state_ptr,
                EuclidAlgebraGroupsCnAssociative.animation_entry,
                "Associative",
                cn_id)
            register_child_animation(
                state_ptr,
                EuclidAlgebraGroupsCnAbelian.animation_entry,
                "Abelian",
                cn_id)

end

end

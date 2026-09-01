
include("./algebra_overview.jl")
include("./groups/groups.jl")

"""Register the Algebra root animation interface and its group content."""
function init_euclid_scripts_algebra(state_ptr::Ptr{Cvoid})
    root_stable_id = OdinJuliaBridge.animation_stable_id_from_key("root:Algebra")
    OdinJuliaBridge.add_root_animation_interface(
        state_ptr, EuclidAlgebraOverview.animation_entry,
        "Algebra",
        root_stable_id)

    EuclidAlgebraGroups.init_euclid_scripts(state_ptr, root_stable_id)
end

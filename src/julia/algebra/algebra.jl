
include("./groups/groups.jl")

function get_view_text_root_aglera(state_ptr::Ptr{Cvoid})
    """Welcome to Euclid!
    
Here we explore Algebra for ways that are helpful for understanding geometry and animation."""
end

function init_euclid_scripts_algebra(state_ptr::Ptr{Cvoid})
    rootId = OdinJuliaBridge.add_root_animation_interface(
        state_ptr, get_view_text_root_euclid_elements, NullAnimation.initialize,
        NullAnimation.loop, NullAnimation.clean,
        "Algebra",
        OdinJuliaBridge.animation_stable_id_from_key("root:Algebra"))

    EuclidAlgebraGroups.init_euclid_scripts(state_ptr, rootId)
end


include("./groups/groups.jl")

function get_view_text_root_aglebra(state_ptr::Ptr{Cvoid})
    fallback = """Welcome to Euclid!
    
Here we explore Algebra for ways that are helpful for understanding geometry and animation."""
    latex = raw"""\textbf{Welcome to Euclid!}
    
Here we explore Algebra for ways that are helpful for understanding geometry and animation."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

function init_euclid_scripts_algebra(state_ptr::Ptr{Cvoid})
    root_stable_id = OdinJuliaBridge.animation_stable_id_from_key("root:Algebra")
    OdinJuliaBridge.add_root_animation_interface(
        state_ptr, get_view_text_root_aglebra, NullAnimation.initialize,
        NullAnimation.loop, NullAnimation.clean,
        "Algebra",
        root_stable_id)

    EuclidAlgebraGroups.init_euclid_scripts(state_ptr, root_stable_id)
end

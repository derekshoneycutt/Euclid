
include("./groups/groups.jl")

"""Emit the welcome view text for the Algebra root animation."""
function get_view_text_root_aglebra(state_ptr::Ptr{Cvoid})
    fallback = """Welcome to Euclid!
    
Here we explore Algebra for ways that are helpful for understanding geometry and animation."""
    latex = raw"""\textbf{Welcome to Euclid!}
    
Here we explore Algebra for ways that are helpful for understanding geometry and animation."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Publish this category view when its animation node is selected."""
function initialize_view_root_aglebra(state_ptr::Ptr{Cvoid})
    NullAnimation.initialize(state_ptr)
    OdinJuliaBridge.publish_view_update(state_ptr, get_view_text_root_aglebra)
end

"""Dispatch lifecycle operations for the Algebra category animation."""
function animation_entry_root_algebra(
    state_ptr::Ptr{Cvoid}, operation::Int32, dt::Float32)::Bool

    if operation == OdinJuliaBridge.ANIMATION_OPERATION_ENTER
        initialize_view_root_aglebra(state_ptr)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_TICK
        NullAnimation.loop(state_ptr, dt)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_EXIT
        NullAnimation.clean(state_ptr)
    else
        return false
    end
    return true
end

"""Register the Algebra root animation interface and its group content."""
function init_euclid_scripts_algebra(state_ptr::Ptr{Cvoid})
    root_stable_id = OdinJuliaBridge.animation_stable_id_from_key("root:Algebra")
    OdinJuliaBridge.add_root_animation_interface(
        state_ptr, animation_entry_root_algebra,
        "Algebra",
        root_stable_id)

    EuclidAlgebraGroups.init_euclid_scripts(state_ptr, root_stable_id)
end

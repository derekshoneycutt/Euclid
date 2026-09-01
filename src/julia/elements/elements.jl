
include("./book1/book1.jl")

"""Emit the welcome view text for the Euclid's Elements root animation."""
function get_view_text_root_euclid_elements(state_ptr::Ptr{Cvoid})
    latex = raw"""\textbf{Welcome to Euclid's Elements!}"""
    fallback = "Welcome to Euclid's Elements!"

    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Publish this category view when its animation node is selected."""
function initialize_view_root_euclid_elements(state_ptr::Ptr{Cvoid})
    NullAnimation.initialize(state_ptr)
    OdinJuliaBridge.publish_view_update(state_ptr, get_view_text_root_euclid_elements)
end

"""Dispatch lifecycle operations for the Euclid's Elements category animation."""
function animation_entry_root_euclid_elements(
    state_ptr::Ptr{Cvoid}, operation::Int32, dt::Float32)::Bool

    if operation == OdinJuliaBridge.ANIMATION_OPERATION_ENTER
        initialize_view_root_euclid_elements(state_ptr)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_TICK
        NullAnimation.loop(state_ptr, dt)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_EXIT
        NullAnimation.clean(state_ptr)
    else
        return false
    end
    return true
end

"""Register the Euclid's Elements root animation interface and book content."""
function init_euclid_scripts_euclid_elements(state_ptr::Ptr{Cvoid})
    root_stable_id = OdinJuliaBridge.animation_stable_id_from_key("root:Euclid's Elements")
    OdinJuliaBridge.add_root_animation_interface(
        state_ptr, animation_entry_root_euclid_elements,
        "Euclid's Elements",
        root_stable_id)
    ElementsOne.init_euclid_scripts(state_ptr, root_stable_id)

end

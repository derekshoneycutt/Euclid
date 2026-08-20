
include("./book1/book1.jl")

"""Emit the welcome view text for the Euclid's Elements root animation."""
function get_view_text_root_euclid_elements(state_ptr::Ptr{Cvoid})
    latex = raw"""\textbf{Welcome to Euclid's Elements!}"""
    fallback = "Welcome to Euclid's Elements!"

    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Register the Euclid's Elements root animation interface and book content."""
function init_euclid_scripts_euclid_elements(state_ptr::Ptr{Cvoid})
    root_stable_id = OdinJuliaBridge.animation_stable_id_from_key("root:Euclid's Elements")
    OdinJuliaBridge.add_root_animation_interface(
        state_ptr, get_view_text_root_euclid_elements, NullAnimation.initialize,
        NullAnimation.loop, NullAnimation.clean,
        "Euclid's Elements",
        root_stable_id)
    ElementsOne.init_euclid_scripts(state_ptr, root_stable_id)

end

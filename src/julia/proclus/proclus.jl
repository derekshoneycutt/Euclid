
include("./proclus_01_isosceles.jl")
include("./proclus_02_scalene.jl")

"""Emit the Proclus's Commentary root view text."""
function get_view_text_root_proclus(state_ptr::Ptr{Cvoid})
    fallback = """Proclus's Commentary
    
Proclus provided an ancient commentary on Book I of Euclid's Elements, including additional constructions and analyses. Some will be included here."""
    latex = raw"""\textbf{Proclus's Commentary}
    
Proclus provided an ancient commentary on Book I of \textit{Euclid's Elements}, including additional constructions and analyses. Some will be included here."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Publish this category view when its animation node is selected."""
function initialize_view_root_proclus(state_ptr::Ptr{Cvoid})
    NullAnimation.initialize(state_ptr)
    OdinJuliaBridge.publish_view_update(state_ptr, get_view_text_root_proclus)
end

"""Register the Proclus's Commentary root animation interface and its content."""
function init_euclid_scripts_proclus(state_ptr::Ptr{Cvoid})
    root_stable_id = OdinJuliaBridge.animation_stable_id_from_key("root:Proclus's Commentary")
    OdinJuliaBridge.add_root_animation_interface(
        state_ptr, initialize_view_root_proclus,
        NullAnimation.loop, NullAnimation.clean,
        "Proclus's Commentary",
        root_stable_id)
        _ = OdinJuliaBridge.add_child_animation_interface(
            state_ptr, ElementsOneProclusIsosceles.initialize,
            ElementsOneProclusIsosceles.loop, ElementsOneProclusIsosceles.clean,
            "Isosceles Triangle",
            OdinJuliaBridge.animation_stable_id_from_key(
                "child:" * root_stable_id * ":Isosceles Triangle"),
            root_stable_id)
        _ = OdinJuliaBridge.add_child_animation_interface(
            state_ptr, ElementsOneProclusScalene.initialize,
            ElementsOneProclusScalene.loop, ElementsOneProclusScalene.clean,
            "Scalene Triangle",
            OdinJuliaBridge.animation_stable_id_from_key(
                "child:" * root_stable_id * ":Scalene Triangle"),
            root_stable_id)
end

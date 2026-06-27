
include("./proclus_01_isosceles.jl")
include("./proclus_02_scalene.jl")

function get_view_text_root_proclus(state_ptr::Ptr{Cvoid})
    """Proclus's Commentary
    
Proclus provided an ancient commentary on Book I of Euclid's Elements, including additional constructions and analyses. Some will be included here."""
end

function init_euclid_scripts_proclus(state_ptr::Ptr{Cvoid})
    rootId = OdinJuliaBridge.add_root_animation_interface(
        state_ptr, get_view_text_root_proclus, NullAnimation.initialize,
        NullAnimation.loop, NullAnimation.clean,
        "Proclus's Commentary")
        book1ProclusIsoscelesId = OdinJuliaBridge.add_child_animation_interface(
            state_ptr, ElementsOneProclusIsosceles.get_view_text,
            ElementsOneProclusIsosceles.initialize,
            ElementsOneProclusIsosceles.loop, ElementsOneProclusIsosceles.clean,
            "Isosceles Triangle", rootId)
        book1ProclusScaleneId = OdinJuliaBridge.add_child_animation_interface(
            state_ptr, ElementsOneProclusScalene.get_view_text,
            ElementsOneProclusScalene.initialize,
            ElementsOneProclusScalene.loop, ElementsOneProclusScalene.clean,
            "Scalene Triangle", rootId)
end

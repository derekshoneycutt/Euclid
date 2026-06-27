
include("./book1/book1.jl")

function get_view_text_root_euclid_elements(state_ptr::Ptr{Cvoid})
    "Welcome to Euclid's Elements!"
end

function init_euclid_scripts_euclid_elements(state_ptr::Ptr{Cvoid})
    rootId = OdinJuliaBridge.add_root_animation_interface(
        state_ptr, get_view_text_root_euclid_elements, NullAnimation.initialize,
        NullAnimation.loop, NullAnimation.clean,
        "Euclid's Elements")
    ElementsOne.init_euclid_scripts(state_ptr, rootId)

end

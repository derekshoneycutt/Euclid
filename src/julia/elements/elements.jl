
include("./elements_overview.jl")
include("./book1/book1.jl")

"""Register the Euclid's Elements root animation interface and book content."""
function init_euclid_scripts_euclid_elements(state_ptr::Ptr{Cvoid})
    root_stable_id = OdinJuliaBridge.animation_stable_id_from_key("root:Euclid's Elements")
    OdinJuliaBridge.add_root_animation_interface(
        state_ptr, EuclidElementsOverview.animation_entry,
        "Euclid's Elements",
        root_stable_id)
    ElementsOne.init_euclid_scripts(state_ptr, root_stable_id)

end

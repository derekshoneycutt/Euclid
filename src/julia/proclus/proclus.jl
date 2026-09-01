
include("./proclus_01_isosceles.jl")
include("./proclus_02_scalene.jl")
include("./proclus_overview.jl")

"""Register the Proclus's Commentary root animation interface and its content."""
function init_euclid_scripts_proclus(state_ptr::Ptr{Cvoid})
    root_stable_id = OdinJuliaBridge.animation_stable_id_from_key("root:Proclus's Commentary")
    OdinJuliaBridge.add_root_animation_interface(
        state_ptr, ProclusOverview.animation_entry,
        "Proclus's Commentary",
        root_stable_id)
        _ = OdinJuliaBridge.add_child_animation_interface(
            state_ptr, ElementsOneProclusIsosceles.animation_entry,
            "Isosceles Triangle",
            OdinJuliaBridge.animation_stable_id_from_key(
                "child:" * root_stable_id * ":Isosceles Triangle"),
            root_stable_id)
        _ = OdinJuliaBridge.add_child_animation_interface(
            state_ptr, ElementsOneProclusScalene.animation_entry,
            "Scalene Triangle",
            OdinJuliaBridge.animation_stable_id_from_key(
                "child:" * root_stable_id * ":Scalene Triangle"),
            root_stable_id)
end

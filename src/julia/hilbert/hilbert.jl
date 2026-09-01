
include("./hilbert_overview.jl")
include("./1.fivegroupsaxioms/fivegroupsaxioms.jl")

"""Register the Hilbert Foundations root animation interface and chapter content."""
function init_euclid_scripts_hilbert(state_ptr::Ptr{Cvoid})
    root_stable_id = OdinJuliaBridge.animation_stable_id_from_key(
        "root:Hilbert's Foundations of Geometry")
    OdinJuliaBridge.add_root_animation_interface(
        state_ptr, HilbertOverview.animation_entry,
        "Hilbert's Foundations of Geometry",
        root_stable_id)

    HilbertChapterOne.init_euclid_scripts(state_ptr, root_stable_id)
end

# Main Julia script body
# This just loads all the system helpers and animation files, and registers in init for Odin

include("./odin-julia-bridge.jl")
include("./geometry.jl")
include("./animations.jl")

include("./nullanimation.jl")

include("./elements/elements.jl")
include("./proclus/proclus.jl")
include("./hilbert/hilbert.jl")


function init_euclid_scripts(state_ptr::Ptr{Cvoid})
    OdinJuliaBridge.set_null_animations(
        state_ptr, NullAnimation.get_view_text, NullAnimation.initialize,
        NullAnimation.loop, NullAnimation.clean)


    init_euclid_scripts_euclid_elements(state_ptr)
    init_euclid_scripts_proclus(state_ptr)
    init_euclid_scripts_hilbert(state_ptr)

end

function global_euclid_loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    # Nothing to do here, but is required
end

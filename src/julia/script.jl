# Main Julia script body
# This just loads all the system helpers and animation files, and registers in init for Odin

include("./odin-julia-bridge.jl")
include("./geometry.jl")
include("./animations.jl")
include("./scratchpad.jl")
include("./euclidrepl.jl")

include("./nullanimation.jl")

include("./elements/elements.jl")
include("./proclus/proclus.jl")
include("./hilbert/hilbert.jl")


function init_euclid_scripts(state_ptr::Ptr{Cvoid})
    OdinJuliaBridge.set_null_animations(
        state_ptr, NullAnimation.get_view_text, NullAnimation.initialize,
        NullAnimation.loop, NullAnimation.clean)

    Scratchpad.init_euclid_scripts_scratchpad(state_ptr)

    init_euclid_scripts_euclid_elements(state_ptr)
    init_euclid_scripts_proclus(state_ptr)
    init_euclid_scripts_hilbert(state_ptr)

end

function scratchpad_classify_input(state_ptr::Ptr{Cvoid}, text::AbstractString)
    Scratchpad.classify_input(state_ptr, String(text))
end

function scratchpad_queue_input(state_ptr::Ptr{Cvoid}, text::AbstractString)
    Scratchpad.queue_input(state_ptr, String(text))
end

function scratchpad_save_history_to_file(state_ptr::Ptr{Cvoid}, path::AbstractString)
    Scratchpad.save_history_to_file(state_ptr, String(path))
end

function scratchpad_history_previous(state_ptr::Ptr{Cvoid})
    Scratchpad.history_previous(state_ptr)
end

function scratchpad_history_next(state_ptr::Ptr{Cvoid})
    Scratchpad.history_next(state_ptr)
end

function scratchpad_history_reset_cursor(state_ptr::Ptr{Cvoid})
    Scratchpad.history_reset_cursor(state_ptr)
end

function global_euclid_loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    # Nothing to do here, but is required
end

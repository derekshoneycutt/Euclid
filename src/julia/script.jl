# Main Julia script body
# This just loads all the system helpers and animation files, and registers in init for Odin

if !isdefined(Main, :EUCLID_SYSIMAGE_CORE_LOADED)
    using LaTeXStrings

    include("./odin-julia-bridge.jl")
    include("./latex.jl")
    include("./geometry.jl")
    include("./animations.jl")
    include("./scratchpad.jl")
    include("./euclidrepl.jl")
end

include("./nullanimation.jl")
include("./harness_scenarios.jl")

include("./elements/elements.jl")
include("./proclus/proclus.jl")
include("./hilbert/hilbert.jl")
include("./algebra/algebra.jl")

"""Print a callback exception with its live Julia stack, then rethrow it."""
function invoke_with_exception_diagnostics(callback, arguments...)
    try
        return callback(arguments...)
    catch exception
        Base.display_error(stderr, current_exceptions())
        rethrow(exception)
    end
end

"""Register all Euclid content animations and prime LaTeX and scratchpad."""
function init_euclid_scripts(state_ptr::Ptr{Cvoid})
    registration_started = time_ns()
    OdinJuliaBridge.set_null_animations(
        state_ptr, NullAnimation.animation_entry)

    Scratchpad.init_euclid_scripts_scratchpad(state_ptr)

    init_euclid_scripts_euclid_elements(state_ptr)
    init_euclid_scripts_proclus(state_ptr)
    init_euclid_scripts_hilbert(state_ptr)
    init_euclid_scripts_algebra(state_ptr)
    println("Julia startup: content registration completed in ",
        round((time_ns() - registration_started) / 1_000_000; digits=2), " ms")

    latex_started = time_ns()
    EuclidLatex.prime_latex!(state_ptr)
    println("Julia startup: LaTeX priming completed in ",
        round((time_ns() - latex_started) / 1_000_000; digits=2), " ms")

    scratchpad_started = time_ns()
    Scratchpad.prime_repl!(state_ptr)
    println("Julia startup: Scratchpad priming completed in ",
        round((time_ns() - scratchpad_started) / 1_000_000; digits=2), " ms")

end

"""Classify one scratchpad input's parse state for the host."""
function scratchpad_classify_input(
    state_ptr::Ptr{Cvoid}, text::AbstractString, input_mode)
    Scratchpad.classify_input(state_ptr, String(text), Int32(input_mode))
end

"""Complete a LaTeX-style backslash token to its Unicode symbol."""
function scratchpad_complete_backslash(state_ptr::Ptr{Cvoid}, token::AbstractString)
    Scratchpad.complete_backslash(state_ptr, String(token))
end

"""Compute completion candidates for the current scratchpad input."""
function scratchpad_complete_input(
    state_ptr::Ptr{Cvoid}, text::AbstractString, caret_byte, input_mode)

    Scratchpad.complete_input(
        state_ptr, String(text), Int(caret_byte), Int32(input_mode))
end

"""Queue one scratchpad input entry for execution."""
function scratchpad_queue_input(
    state_ptr::Ptr{Cvoid}, text::AbstractString, input_mode, request_id)

    Scratchpad.queue_input(
        state_ptr, String(text), Int32(input_mode), UInt64(request_id))
end

"""Save the scratchpad input history to a file."""
function scratchpad_save_history_to_file(state_ptr::Ptr{Cvoid}, path::AbstractString)
    Scratchpad.save_history_to_file(state_ptr, String(path))
end

"""Move the scratchpad history cursor to the previous entry."""
function scratchpad_history_previous(state_ptr::Ptr{Cvoid}, input_mode)
    Scratchpad.history_previous(state_ptr, Int32(input_mode))
end

"""Move the scratchpad history cursor to the next entry."""
function scratchpad_history_next(state_ptr::Ptr{Cvoid})
    Scratchpad.history_next(state_ptr)
end

"""Reset the scratchpad history cursor to the latest entry."""
function scratchpad_history_reset_cursor(state_ptr::Ptr{Cvoid})
    Scratchpad.history_reset_cursor(state_ptr)
end

"""Run the global per-frame Euclid loop (no-op hook required by the host)."""
function global_euclid_loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    # Nothing to do here, but is required
end

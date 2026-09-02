# Main Julia script body
# This just loads all the system helpers and animation files, and registers in init for Odin

using UUIDs

if !isdefined(Main, :EUCLID_SYSIMAGE_CORE_LOADED)
    using LaTeXStrings

    include("./odin-julia-bridge.jl")
    include("./latex.jl")
    include("./geometry.jl")
    include("./animations.jl")
    include("./scratchpad.jl")
    include("./euclidrepl.jl")
end

if !isdefined(Main, :EuclidRuntimeHost)
    include("./runtime_host.jl")
end

"""Print a callback exception with its live Julia stack, then rethrow it."""
function invoke_with_exception_diagnostics(callback, arguments...)
    try
        return callback(arguments...)
    catch exception
        Base.display_error(stderr, current_exceptions())
        rethrow(exception)
    end
end

"""Register metadata and eager entries from one explicit content generation."""
function register_euclid_generation(
    host::EuclidRuntimeHost,
    generation::EuclidRuntimeGeneration,
    state_ptr::Ptr{Cvoid})

    state_ptr == host.state_ptr || throw(ArgumentError("state_ptr does not match host"))
    registration_started = time_ns()
    OdinJuliaBridge.set_null_animations(
        state_ptr,
        Base.invokelatest(
            getfield, generation.null_animation, :animation_entry))

    register_catalog = Base.invokelatest(
        getfield, generation.animation_catalog, :register_animation_catalog)
    scratchpad_entry = (callback_state_ptr, operation, dt) -> Scratchpad.animation_entry(
        host.scratchpad, host.state_ptr, callback_state_ptr, operation, dt)
    Base.invokelatest(register_catalog, state_ptr, scratchpad_entry)
    println("Julia startup: content registration completed in ",
        round((time_ns() - registration_started) / 1_000_000; digits=2), " ms")
    return true
end

"""Register the active host generation and prime stable startup services."""
function init_euclid_scripts(host::EuclidRuntimeHost, state_ptr::Ptr{Cvoid})
    generation = active_euclid_runtime_generation(host)
    register_euclid_generation(host, generation, state_ptr)
    return true
end

"""Load and bind one catalog implementation selected by permanent UUID."""
function ensure_animation_loaded(
    host::EuclidRuntimeHost, state_ptr::Ptr{Cvoid},
    stable_id::AbstractString)::Bool

    id = UUID(String(stable_id))
    generation = active_euclid_runtime_generation(host)
    implementation = load_generation_animation(generation, id)
    return OdinJuliaBridge.bind_animation_entry(
        state_ptr, implementation.entry, string(id)) == 1
end

"""Load and bind one animation from an explicit uncommitted generation."""
function ensure_generation_animation_loaded(
    generation::EuclidRuntimeGeneration, state_ptr::Ptr{Cvoid},
    stable_id::AbstractString)::Bool

    id = UUID(String(stable_id))
    implementation = load_generation_animation(generation, id)
    return OdinJuliaBridge.bind_animation_entry(
        state_ptr, implementation.entry, string(id)) == 1
end

"""Invoke one scenario owned by the host's committed content generation."""
function invoke_generation_harness_scenario(
    host::EuclidRuntimeHost, scenario_name::AbstractString,
    state_ptr::Ptr{Cvoid}, step_count::Integer)::Bool

    try
        generation = active_euclid_runtime_generation(host)
        scenario = getfield(
            generation.harness_scenarios, Symbol(scenario_name))
        return Base.invokelatest(
            scenario, generation, state_ptr, step_count)
    catch exception
        Base.display_error(stderr, current_exceptions())
        rethrow(exception)
    end
end

"""Classify one scratchpad input's parse state for the host."""
function scratchpad_classify_input(
    host::EuclidRuntimeHost, text::AbstractString, input_mode)

    Scratchpad.classify_input(
        host.scratchpad, host.state_ptr, String(text), Int32(input_mode))
end

"""Complete a LaTeX-style backslash token to its Unicode symbol."""
function scratchpad_complete_backslash(
    host::EuclidRuntimeHost, token::AbstractString)

    Scratchpad.complete_backslash(host.scratchpad, host.state_ptr, String(token))
end

"""Compute completion candidates for the current scratchpad input."""
function scratchpad_complete_input(
    host::EuclidRuntimeHost, text::AbstractString, caret_byte, input_mode)

    Scratchpad.complete_input(
        host.scratchpad, host.state_ptr,
        String(text), Int(caret_byte), Int32(input_mode))
end

"""Queue one scratchpad input entry for execution."""
function scratchpad_queue_input(
    host::EuclidRuntimeHost, text::AbstractString, input_mode, request_id)

    Scratchpad.queue_input(
        host.scratchpad, host.state_ptr,
        String(text), Int32(input_mode), UInt64(request_id))
end

"""Save the scratchpad input history to a file."""
function scratchpad_save_history_to_file(
    host::EuclidRuntimeHost, path::AbstractString)

    Scratchpad.save_history_to_file(host.scratchpad, host.state_ptr, String(path))
end

"""Move the scratchpad history cursor to the previous entry."""
function scratchpad_history_previous(host::EuclidRuntimeHost, input_mode)
    Scratchpad.history_previous(host.scratchpad, host.state_ptr, Int32(input_mode))
end

"""Move the scratchpad history cursor to the next entry."""
function scratchpad_history_next(host::EuclidRuntimeHost)
    Scratchpad.history_next(host.scratchpad, host.state_ptr)
end

"""Reset the scratchpad history cursor to the latest entry."""
function scratchpad_history_reset_cursor(host::EuclidRuntimeHost)
    Scratchpad.history_reset_cursor(host.scratchpad, host.state_ptr)
end

"""Run the global per-frame Euclid loop (no-op hook required by the host)."""
function global_euclid_loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    # Nothing to do here, but is required
end

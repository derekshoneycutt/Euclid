# Main Julia script body
# This just loads all the system helpers and animation files, and registers in init for Odin

using UUIDs

if !isdefined(Main, :EUCLID_SYSIMAGE_CORE_LOADED)
    using LaTeXStrings

    include("./odin-julia-bridge.jl")
    include("./latex.jl")
    include("./geometry.jl")
    include("./animations.jl")
    include("./runtime.jl")
    include("./terminal.jl")
    include("./ticks.jl")
    include("./euclidrepl.jl")
    include("./terminal_container.jl")
    include("./eval.jl")
    include("./interpolation.jl")
    include("./policy.jl")
    include("./host.jl")
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
    Base.invokelatest(
        register_catalog, state_ptr, host.terminal_animation_callback)
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

"""Run the global per-frame Euclid loop (no-op hook required by the host)."""
function global_euclid_loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    # Nothing to do here, but is required
end

"""Request installation of one animation-owned Terminal session."""
function terminal_host_start_session(
    host::EuclidRuntimeHost, animation_generation::UInt64)::Bool
    return start_euclid_terminal_session!(host, animation_generation)
end

"""Return Julia's colorized REPL startup banner to the native host."""
function terminal_host_startup_banner()::String
    return EuclidReplEvaluation.startup_banner_for_host()
end

"""Request retirement of one animation-owned Terminal session."""
function terminal_host_close_session(
    host::EuclidRuntimeHost, animation_generation::UInt64)::Bool
    return close_euclid_terminal_session!(host, animation_generation)
end

"""Submit one correlated Terminal evaluation to the host-owned actor runtime."""
function terminal_host_ingest_evaluation(
    host::EuclidRuntimeHost, request_id::UInt64, source::AbstractString,
    mode::Int32, animation_generation::UInt64)::Bool
    host.pending_terminal_evaluation === nothing || return false
    host.pending_terminal_evaluation = EuclidTerminalEvaluationRequest(
        request_id, String(source), mode, animation_generation)
    return true
end

"""Pump one bounded turn of host-owned Terminal services."""
function terminal_host_pump(host::EuclidRuntimeHost)::Bool
    return pump_euclid_terminal!(host)
end

"""Retire all Terminal actors before the native Julia owner shuts down."""
function terminal_host_shutdown(host::EuclidRuntimeHost)::Bool
    return shutdown_euclid_terminal!(host)
end

"""Take one primitive Terminal evaluation command without blocking."""
function terminal_host_take_evaluation(host::EuclidRuntimeHost)
    return EuclidHost.take_evaluation_for_host(host.terminal)
end

"""Take one primitive Terminal session lifecycle command without blocking."""
function terminal_host_take_session_lifecycle(host::EuclidRuntimeHost)
    return EuclidHost.take_session_lifecycle_for_host(host.terminal)
end

"""Install one native tick-stream configuration result for the active session."""
function terminal_host_ingest_tick_stream_configuration(
    host::EuclidRuntimeHost, session_generation::UInt64,
    stream_generation::UInt64, interval_steps::UInt64, active::Bool)::Bool
    return EuclidHost.ingest_tick_stream_configuration_for_host(
        host.terminal, session_generation, stream_generation,
        interval_steps, active)
end

"""Deliver one coalesced native fixed-step pulse to the active session."""
function terminal_host_ingest_tick_pulse(
    host::EuclidRuntimeHost, session_generation::UInt64,
    stream_generation::UInt64, sequence::UInt64,
    first_simulation_tick::UInt64, last_simulation_tick::UInt64,
    step_count::UInt64)::Bool
    return EuclidHost.ingest_tick_pulse_for_host(
        host.terminal, session_generation, stream_generation, sequence,
        first_simulation_tick, last_simulation_tick, step_count)
end

"""Take one primitive tick-stream configure or stop command without blocking."""
function terminal_host_take_tick_stream(host::EuclidRuntimeHost)
    return EuclidHost.take_tick_stream_for_host(host.terminal)
end

"""Print a callback exception with its live Julia stack, then rethrow it."""
function invoke_with_exception_diagnostics(callback, arguments...)
    try
        return callback(arguments...)
    catch exception
        Base.display_error(stderr, current_exceptions())
        rethrow(exception)
    end
end

"""Install null-animation behavior for one explicit content generation."""
function initialize_euclid_generation(
    host::EuclidRuntimeHost,
    generation::EuclidRuntimeGeneration,
    state_ptr::Ptr{Cvoid})

    state_ptr == host.state_ptr || throw(ArgumentError("state_ptr does not match host"))
    OdinJuliaBridge.set_null_animations(
        state_ptr,
        Base.invokelatest(
            getfield, generation.null_animation, :animation_entry))
    return true
end

"""Register the active host generation and prime stable startup services."""
function init_euclid_scripts(host::EuclidRuntimeHost, state_ptr::Ptr{Cvoid})
    generation = active_euclid_runtime_generation(host)
    initialize_euclid_generation(host, generation, state_ptr)
    return true
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

"""Run the global per-frame Euclid loop required by the native host."""
function global_euclid_loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    _ = state_ptr
    _ = dt
    return nothing
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

"""Pump one bounded turn of host-owned application actor work."""
function terminal_host_pump(host::EuclidRuntimeHost)::Bool
    return pump_euclid_reactor!(host)
end

"""Retire all application actors before the native Julia owner shuts down."""
function terminal_host_shutdown(host::EuclidRuntimeHost)::Bool
    return shutdown_euclid_reactor!(host)
end

"""Take one primitive Terminal evaluation command without blocking."""
function terminal_host_take_evaluation(host::EuclidRuntimeHost)
    return EuclidHost.take_evaluation_for_host(host.reactor)
end

"""Register one automatic completion-preview request with the active Terminal host."""
function terminal_host_ingest_completion_preview(
    host::EuclidRuntimeHost, request_id::UInt64, source::String,
    cursor_byte::Int32, session_generation::UInt64)
    return EuclidHost.ingest_completion_preview_for_host(
        host.reactor, request_id, source, cursor_byte, session_generation)
end

"""Register one explicit completion candidate request with the active Terminal host."""
function terminal_host_ingest_completion_candidates(
    host::EuclidRuntimeHost, request_id::UInt64, source::String,
    cursor_byte::Int32, session_generation::UInt64)
    return EuclidHost.ingest_completion_candidates_for_host(
        host.reactor, request_id, source, cursor_byte, session_generation)
end

"""Take one primitive Terminal completion command without blocking."""
function terminal_host_take_completion(host::EuclidRuntimeHost)
    return EuclidHost.take_completion_for_host(host.reactor)
end

"""Take one primitive Terminal session lifecycle command without blocking."""
function terminal_host_take_session_lifecycle(host::EuclidRuntimeHost)
    return EuclidHost.take_session_lifecycle_for_host(host.reactor)
end

"""Install one native tick-stream configuration result for the active session."""
function terminal_host_ingest_tick_stream_configuration(
    host::EuclidRuntimeHost, session_generation::UInt64,
    stream_generation::UInt64, interval_steps::UInt64, active::Bool)::Bool
    return EuclidHost.ingest_tick_stream_configuration_for_host(
        host.reactor, session_generation, stream_generation,
        interval_steps, active)
end

"""Deliver one coalesced native fixed-step pulse to the active session."""
function terminal_host_ingest_tick_pulse(
    host::EuclidRuntimeHost, session_generation::UInt64,
    stream_generation::UInt64, sequence::UInt64,
    first_simulation_tick::UInt64, last_simulation_tick::UInt64,
    step_count::UInt64)::Bool
    return EuclidHost.ingest_tick_pulse_for_host(
        host.reactor, session_generation, stream_generation, sequence,
        first_simulation_tick, last_simulation_tick, step_count)
end

"""Take one primitive tick-stream configure or stop command without blocking."""
function terminal_host_take_tick_stream(host::EuclidRuntimeHost)
    return EuclidHost.take_tick_stream_for_host(host.reactor)
end

const EUCLID_RUNTIME_API_LOADED = true

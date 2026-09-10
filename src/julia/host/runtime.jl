"""Lifecycle phase of one generation-scoped Julia user session."""
@enum HostSessionPhase begin
    HostSessionActive
    HostSessionClosing
    HostSessionQuiescent
end

"""Generation-scoped module, actors, and mutable user-service state."""
mutable struct HostSessionRuntime
    generation::UInt64
    context_module::Module
    phase::HostSessionPhase
    completion_service::EuclidActorRuntime.ActorId
    evaluator::EuclidActorRuntime.ActorId
    shell_interpolation_service::EuclidActorRuntime.ActorId
    shell_session::EuclidActorRuntime.ActorId
    terminal_process_service::EuclidActorRuntime.ActorId
    tick_service::EuclidActorRuntime.ActorId
    terminal_container_service::EuclidActorRuntime.ActorId
    evaluator_state::Evaluator
    terminal_process_state::TerminalProcessService
    tick_service_state::TickService
    terminal_container_state::TerminalContainerService
    euclid_repl_runtime::EuclidRepl.EuclidReplRuntime
end

"""Combined application and active-session state owned by the Odin reactor thread."""
mutable struct HostRuntime
    state_ptr::Ptr{Cvoid}
    actors::EuclidActorRuntime.ActorRuntime
    terminal_controller::EuclidActorRuntime.ActorId
    hotkey_controller::EuclidActorRuntime.ActorId
    session::HostSessionRuntime
    completion_function::Any
    interpolation_function::Any
    completion_mailbox_capacity::Int
    logger::AbstractLogger
    reported_actor_failures::Int
    shutdown_requested::Bool
end

"""Compact scheduling and lifecycle state returned after one host pump."""
struct HostPumpStatus
    immediately_runnable::Bool
    next_timer_deadline_ns::UInt64
    outgoing_available::Bool
    healthy::Bool
    shutdown_ready::Bool
    output_queue_depth::Int32
    output_queue_high_water::Int32
    output_emitted_bytes::UInt64
    output_truncated_bytes::UInt64
end

const HOST_SESSION_PROPERTIES = (
    :completion_service, :evaluator, :shell_interpolation_service,
    :shell_session, :terminal_process_service, :tick_service,
    :terminal_container_service, :evaluator_state, :terminal_process_state,
    :tick_service_state, :terminal_container_state, :euclid_repl_runtime)

"""Forward legacy host service properties to the active session owner."""
function Base.getproperty(runtime::HostRuntime, name::Symbol)
    if name in HOST_SESSION_PROPERTIES
        return getproperty(getfield(runtime, :session), name)
    end
    return getfield(runtime, name)
end

"""Create a fresh module with the standard imports expected by Julia user code."""
function create_session_module(
    generation::UInt64, state_ptr::Ptr{Cvoid})::Tuple{Module,EuclidRepl.EuclidReplRuntime}
    generation > 0 || throw(ArgumentError("session generation must be nonzero"))
    context_module = Module(
        Symbol("EuclidTerminalSession_$(generation)"), true, true)
    terminal_module = getfield(Main, :Terminal)
    ticks_module = getfield(Main, :Ticks)
    terminal_container_module = getfield(Main, :TerminalContainer)
    Core.eval(context_module, :(const Terminal = $terminal_module))
    Core.eval(context_module, :(const Ticks = $ticks_module))
    Core.eval(context_module,
        :(const TerminalContainer = $terminal_container_module))
    euclid_repl_runtime = EuclidRepl.create_runtime()
    EuclidRepl.install_session_helpers!(
        context_module, euclid_repl_runtime, state_ptr)
    return context_module, euclid_repl_runtime
end

"""Bind completion policy to one Terminal session module when using the default."""
function bind_session_completion(completion_function, context_module::Module)
    completion_function === complete_input || return completion_function
    return (code, cursor_byte; show_candidates=true) -> complete_input(
        code, cursor_byte; show_candidates, context_module)
end

"""Bind interpolation policy to one Terminal session module when using the default."""
function bind_session_interpolation(interpolation_function, context_module::Module)
    interpolation_function === evaluate_shell_interpolation ||
        return interpolation_function
    return source -> evaluate_shell_interpolation(source; context_module)
end

"""Create every user-facing actor for one Julia session generation."""
function create_host_session!(
    actors::EuclidActorRuntime.ActorRuntime, state_ptr::Ptr{Cvoid},
    generation::UInt64,
    completion_function, interpolation_function,
    completion_mailbox_capacity::Int)::HostSessionRuntime
    context_module, euclid_repl_runtime = create_session_module(
        generation, state_ptr)
    bound_completion = bind_session_completion(
        completion_function, context_module)
    completion_service = EuclidActorRuntime.spawn!(
        actors, CompletionService(bound_completion);
        mailbox_capacity=completion_mailbox_capacity)
    evaluator_state = Evaluator(EuclidReplEvaluation.create_eval_runtime(
        context_module; session_generation=generation))
    evaluator = EuclidActorRuntime.spawn!(actors, evaluator_state)
    bound_interpolation = bind_session_interpolation(
        interpolation_function, context_module)
    shell_interpolation_service = EuclidActorRuntime.spawn!(actors,
        ShellInterpolationService(
            bound_interpolation,
            () -> evaluator_state.active_request !== nothing))
    shell_session = EuclidActorRuntime.spawn!(actors, ShellSession())
    terminal_process_state = TerminalProcessService(
        evaluator_state.runtime.process_client)
    terminal_process_service = EuclidActorRuntime.spawn!(
        actors, terminal_process_state)
    tick_service_state = TickService(
        generation, evaluator_state.runtime.tick_client)
    tick_service = EuclidActorRuntime.spawn!(
        actors, tick_service_state)
    terminal_container_state = TerminalContainerService(
        generation, evaluator_state.runtime.terminal_container_client)
    terminal_container_service = EuclidActorRuntime.spawn!(
        actors, terminal_container_state)
    return HostSessionRuntime(
        generation, context_module, HostSessionActive,
        completion_service, evaluator, shell_interpolation_service,
        shell_session, terminal_process_service, tick_service,
        terminal_container_service, evaluator_state, terminal_process_state,
        tick_service_state, terminal_container_state, euclid_repl_runtime)
end

"""Deliver bounded terminal bytes only to their active evaluation owner."""
function ingest_interactive_input_for_host(
    runtime::HostRuntime, request_id::UInt64,
    input::AbstractString)::Bool
    evaluator = runtime.evaluator_state
    evaluator.active_request == request_id || return false
    return EuclidReplEvaluation.interactive_write!(
        evaluator.runtime.terminal, codeunits(input))
end

"""Create the Julia services owned by one Odin reactor thread."""
function create_host_runtime(
    states::Ptr{Cvoid}, window_width::Float32,
    window_height::Float32;
    session_generation::UInt64=UInt64(1),
    completion_function=complete_input,
    interpolation_function=evaluate_shell_interpolation,
    completion_mailbox_capacity::Integer=64,
    logger::AbstractLogger=states == C_NULL ? NullLogger() :
        host_diagnostic_logger(states))::HostRuntime
    actors = EuclidActorRuntime.ActorRuntime()
    rectangle = TerminalRectangle(0.0f0, 0.0f0, window_width, window_height)
    terminal_controller = EuclidActorRuntime.spawn!(
        actors, TerminalController(rectangle, UInt64(0), UInt64(0)))
    hotkey_controller = EuclidActorRuntime.spawn!(actors,
        HotkeyController(UInt64(0), UInt64(0),
            [HotkeyBinding(ToggleTerminal, HotkeyT, UInt8(1), Int32(1))],
            terminal_controller))
    EuclidActorRuntime.send!(actors, hotkey_controller, RegisterHotkeys())
    session = create_host_session!(
        actors, states, session_generation, completion_function,
        interpolation_function, Int(completion_mailbox_capacity))
    runtime = HostRuntime(
        states, actors, terminal_controller, hotkey_controller, session,
        completion_function, interpolation_function,
        Int(completion_mailbox_capacity),
        logger, 0, false)
    @host_log runtime Logging.Debug "host runtime created"
    return runtime
end

"""Create host services after querying Odin's immutable window dimensions."""
function create_host_runtime(states::Ptr{Cvoid}=C_NULL)::HostRuntime
    window_width, window_height = OdinJuliaBridge.get_window_size(states)
    return create_host_runtime(states, window_width, window_height)
end

"""Create and root the host runtime retained by the native reactor."""
function create_host_runtime_for_host(states::Ptr{Cvoid})::HostRuntime
    return create_host_runtime(states)
end
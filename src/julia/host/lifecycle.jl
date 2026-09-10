"""Report successful creation of one complete Julia user session."""
struct JuliaSessionStarted
    generation::UInt64
end

"""Report that no actor can access one closed Julia session generation."""
struct JuliaSessionQuiescent
    generation::UInt64
end

"""Return whether every actor owned by one session generation has stopped."""
function session_actors_stopped(
    runtime::HostRuntime, session::HostSessionRuntime)::Bool
    actor_runtime = runtime.actors
    return !EuclidActorRuntime.is_live(
        actor_runtime, session.completion_service) &&
        !EuclidActorRuntime.is_live(actor_runtime, session.evaluator) &&
        !EuclidActorRuntime.is_live(
            actor_runtime, session.shell_interpolation_service) &&
        !EuclidActorRuntime.is_live(actor_runtime, session.shell_session) &&
        !EuclidActorRuntime.is_live(
            actor_runtime, session.terminal_process_service) &&
        !EuclidActorRuntime.is_live(actor_runtime, session.tick_service) &&
        !EuclidActorRuntime.is_live(
            actor_runtime, session.terminal_container_service)
end

"""Return whether outgoing work still belongs to the closing user session."""
function session_outgoing_pending(runtime::HostRuntime)::Bool
    command_type = Union{
        CompletionResolved,CompletionFailed,ShellInterpolationResolved,
        BeginTerminalSessionRequested,CancelTerminalSessionRequested,
        AbandonTerminalSessionRequested,TerminalProcessLaunchRequested,
        TerminalOutputBatch,EvaluationCompleted,EvaluationIncomplete,
        EvaluationExitRequested,TerminalInputAcquired,TerminalInputReleased,
        TickStreamConfigureRequested,TickStreamStopRequested,
        TerminalContainerConfigureRequested,TerminalContainerChangeObserved}
    return any(command -> command isa command_type, runtime.actors.outgoing)
end

"""Advance a closing session to its single correlated quiescence result."""
function advance_session_lifecycle!(runtime::HostRuntime)::Nothing
    session = runtime.session
    session.phase === HostSessionClosing || return nothing
    if session.evaluator_state.active_request === nothing
        EuclidActorRuntime.stop!(runtime.actors, session.evaluator)
    end
    session_actors_stopped(runtime, session) || return nothing
    session_outgoing_pending(runtime) && return nothing
    EuclidReplEvaluation.close_interactive_terminal!(
        session.evaluator_state.runtime.terminal)
    session.phase = HostSessionQuiescent
    EuclidActorRuntime.emit!(
        runtime.actors, JuliaSessionQuiescent(session.generation))
    return nothing
end

"""Stop admission and cooperatively drain one matching session generation."""
function close_session_for_host(
    runtime::HostRuntime, generation::UInt64)::Bool
    runtime.shutdown_requested && return false
    session = runtime.session
    session.phase === HostSessionActive || return false
    session.generation == generation || return false
    session.phase = HostSessionClosing
    EuclidRepl.reset_session!(session.euclid_repl_runtime, runtime.state_ptr)
    evaluator = session.evaluator_state
    evaluator.discard_output = true
    session.tick_service_state.client.accepting = false
    session.terminal_container_state.client.accepting = false
    if evaluator.runtime.terminal.acquired
        EuclidReplEvaluation.interactive_write!(
            evaluator.runtime.terminal, codeunits("\x03"))
    end
    reject_pending_for_shutdown!(runtime)
    EuclidActorRuntime.stop!(
        runtime.actors, session.completion_service)
    EuclidActorRuntime.stop!(
        runtime.actors, session.shell_interpolation_service)
    EuclidActorRuntime.send!(
        runtime.actors, session.shell_session, StopShellSession())
    EuclidActorRuntime.send!(
        runtime.actors, session.terminal_process_service,
        StopTerminalProcessService())
    EuclidActorRuntime.send!(
        runtime.actors, session.tick_service, StopTickService())
    EuclidActorRuntime.send!(runtime.actors,
        session.terminal_container_service, StopTerminalContainerService())
    advance_session_lifecycle!(runtime)
    return true
end

"""Create a higher Julia session generation after prior quiescence."""
function start_session_for_host(
    runtime::HostRuntime, generation::UInt64)::Bool
    runtime.shutdown_requested && return false
    previous = runtime.session
    previous.phase === HostSessionQuiescent || return false
    generation > previous.generation || return false
    runtime.session = create_host_session!(
        runtime.actors, runtime.state_ptr,
        generation, runtime.completion_function,
        runtime.interpolation_function, runtime.completion_mailbox_capacity)
    EuclidActorRuntime.emit!(
        runtime.actors, JuliaSessionStarted(generation))
    return true
end

"""Run bounded actor work and report when the host should service Julia again."""
function pump_for_host(
    runtime::HostRuntime, max_turns::Int32, budget_ns::UInt64)::HostPumpStatus
    drain_terminal_process_requests!(
        runtime.actors, runtime.terminal_process_service,
        runtime.evaluator_state.runtime.process_client)
    drain_tick_requests!(
        runtime.actors, runtime.tick_service, runtime.tick_service_state)
    drain_terminal_container_requests!(runtime.actors,
        runtime.terminal_container_service, runtime.terminal_container_state)
    deadline_ns = time_ns() + budget_ns
    status = EuclidActorRuntime.pump!(
        runtime.actors; max_turns=Int(max_turns), deadline_ns=deadline_ns)
    advance_session_lifecycle!(runtime)
    report_actor_failures!(runtime)
    ready = status.remaining_ready > 0
    outgoing = !isempty(runtime.actors.outgoing)
    healthy = isempty(runtime.actors.failures)
    output_depth = count(
        command -> command isa TerminalOutputBatch, runtime.actors.outgoing)
    evaluator = runtime.evaluator_state
    shutdown_ready = runtime.shutdown_requested && !ready &&
        isempty(runtime.actors.outgoing) &&
        EuclidActorRuntime.pending_request_count(runtime.actors) == 0
    return HostPumpStatus(
        ready, typemax(UInt64), outgoing, healthy,
        shutdown_ready,
        Int32(output_depth), Int32(evaluator.output_queue_high_water),
        evaluator.emitted_output_bytes, evaluator.truncated_output_bytes)
end

"""Log newly observed actor failures and advance the reporting cursor."""
function report_actor_failures!(runtime::HostRuntime)::Nothing
    failures = runtime.actors.failures
    for index in (runtime.reported_actor_failures + 1):length(failures)
        failure = failures[index]
        supervisor = failure.supervisor
        @host_log(
            runtime, Logging.Error, "actor failed",
            actor_id=failure.actor.index,
            actor_generation=failure.actor.generation,
            supervisor_id=(supervisor === nothing ? 0 : supervisor.index),
            supervisor_generation=(
                supervisor === nothing ? UInt64(0) : supervisor.generation),
            exception_type=typeof(failure.exception),
            message_type=typeof(failure.message))
    end
    runtime.reported_actor_failures = length(failures)
    return nothing
end

"""Reject pending host requests that will not run during shutdown."""
function reject_pending_for_shutdown!(runtime::HostRuntime)::Nothing
    active_request = runtime.evaluator_state.active_request
    for (key, pending) in collect(runtime.actors.pending_requests)
        if pending.owner == runtime.completion_service
            @host_log(
                runtime, Logging.Warn, "completion rejected",
                request_id=UInt64(key), reason="shutdown")
            EuclidActorRuntime.resolve_request!(runtime.actors, key)
            EuclidActorRuntime.emit!(runtime.actors,
                CompletionFailed(UInt64(key), CompletionRuntimeStopped))
        elseif pending.owner == runtime.shell_interpolation_service
            request = pending.value::ShellInterpolationRequested
            @host_log(
                runtime, Logging.Warn, "interpolation rejected",
                request_id=request.request_id, reason="shutdown")
            EuclidActorRuntime.resolve_request!(runtime.actors, key)
            fail_shell_interpolation!(runtime, request.request_id,
                ShellInterpolationRuntimeStopped,
                "interpolation runtime is stopped")
        elseif pending.owner == runtime.evaluator &&
            key != evaluation_request_key(something(active_request, UInt64(0)))
            request = pending.value::EvaluationRequested
            @host_log(
                runtime, Logging.Warn, "evaluation rejected",
                request_id=request.request_id, reason="shutdown_pending")
            EuclidActorRuntime.resolve_request!(runtime.actors, key)
            fail_evaluation_for_host!(runtime, request.request_id,
                "evaluation runtime is stopped")
        end
    end
    return nothing
end

"""Stop every session service after shutdown admission has closed."""
function stop_session_services!(runtime::HostRuntime)::Nothing
    EuclidActorRuntime.stop!(runtime.actors, runtime.terminal_controller)
    EuclidActorRuntime.stop!(runtime.actors, runtime.completion_service)
    EuclidActorRuntime.stop!(
        runtime.actors, runtime.shell_interpolation_service)
    EuclidActorRuntime.send!(
        runtime.actors, runtime.shell_session, StopShellSession())
    EuclidActorRuntime.send!(runtime.actors,
        runtime.terminal_process_service, StopTerminalProcessService())
    EuclidActorRuntime.send!(
        runtime.actors, runtime.tick_service, StopTickService())
    EuclidActorRuntime.send!(runtime.actors,
        runtime.terminal_container_service, StopTerminalContainerService())
    return nothing
end

"""Begin cooperative host shutdown and reject future lifecycle assumptions."""
function request_shutdown_for_host(runtime::HostRuntime)::Nothing
    runtime.shutdown_requested && return nothing
    evaluator = runtime.evaluator_state
    pending_bytes = length(evaluator.pending_output)
    @host_log(
        runtime, Logging.Info, "host shutdown requested",
        pending_requests=EuclidActorRuntime.pending_request_count(runtime.actors),
        active_request=something(evaluator.active_request, UInt64(0)),
        pending_output_bytes=pending_bytes,
        output_emitted_bytes=evaluator.emitted_output_bytes,
        output_truncated_bytes=evaluator.truncated_output_bytes,
        output_queue_high_water=evaluator.output_queue_high_water)
    runtime.shutdown_requested = true
    evaluator.discard_output = true
    runtime.tick_service_state.client.accepting = false
    runtime.terminal_container_state.client.accepting = false
    if evaluator.runtime.terminal.acquired
        EuclidReplEvaluation.interactive_write!(
            evaluator.runtime.terminal, codeunits("\x03"))
    end
    evaluator.truncated_request_bytes += UInt64(pending_bytes)
    evaluator.truncated_output_bytes += UInt64(pending_bytes)
    empty!(evaluator.pending_output)
    reject_pending_for_shutdown!(runtime)
    stop_session_services!(runtime)
    evaluator.active_request === nothing &&
        EuclidActorRuntime.stop!(runtime.actors, runtime.evaluator)
    return nothing
end
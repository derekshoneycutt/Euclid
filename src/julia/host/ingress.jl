"""Install one generation-ordered accepted terminal geometry."""
function ingest_hotkey_registry_result_for_host(
    runtime::HostRuntime, generation::UInt64, accepted::Bool,
    reason::Int32, offending_index::Int32)::Cint
    result = HotkeyRegistryResult(
        generation, accepted, reason, offending_index)
    return Cint(EuclidActorRuntime.send!(
        runtime.actors, runtime.hotkey_controller, result))
end

"""Install one generation-ordered accepted terminal geometry."""
function ingest_terminal_geometry_for_host(
    runtime::HostRuntime, generation::UInt64,
    columns::UInt16, rows::UInt16)::Bool
    return EuclidReplEvaluation.update_terminal_geometry!(
        runtime.evaluator_state.runtime.terminal, rows, columns, generation)
end

"""Install one versioned terminal capability snapshot from the display owner."""
function ingest_terminal_capabilities_for_host(
    runtime::HostRuntime, version::UInt16, encoding::UInt8,
    color::UInt8, modify_other_keys_level::UInt8,
    kitty_keyboard_flags::UInt8, features::UInt32)::Bool
    return EuclidReplEvaluation.update_terminal_capabilities!(
        runtime.evaluator_state.runtime.terminal, version, encoding, color,
        modify_other_keys_level, kitty_keyboard_flags, features)
end

"""Submit one correlated launch intent to the persistent shell-session actor."""
function ingest_shell_session_submit_for_host(
    runtime::HostRuntime, request_id::UInt64)::Cint
    outcome = EuclidActorRuntime.send!(
        runtime.actors, runtime.shell_session, ShellSessionSubmit(request_id))
    return Cint(outcome)
end

"""Deliver one authoritative native acceptance fact to both lifecycle owners."""
function ingest_terminal_session_accepted_for_host(
    runtime::HostRuntime, request_id::UInt64,
    operation_slot::UInt32, operation_generation::UInt64)::Cint
    message = TerminalSessionAccepted(request_id,
        TerminalSessionOperationId(operation_slot, operation_generation))
    outcome = EuclidActorRuntime.send!(
        runtime.actors, runtime.shell_session, message)
    EuclidActorRuntime.send!(
        runtime.actors, runtime.terminal_process_service, message)
    return Cint(outcome)
end

"""Deliver one authoritative native rejection fact to both lifecycle owners."""
function ingest_terminal_session_rejected_for_host(
    runtime::HostRuntime, request_id::UInt64, reason::Int32)::Cint
    message = TerminalSessionRejected(request_id, reason)
    outcome = EuclidActorRuntime.send!(
        runtime.actors, runtime.shell_session, message)
    EuclidActorRuntime.send!(
        runtime.actors, runtime.terminal_process_service, message)
    return Cint(outcome)
end

"""Deliver one authoritative native completion fact to both lifecycle owners."""
function ingest_terminal_session_completed_for_host(
    runtime::HostRuntime, operation_slot::UInt32,
    operation_generation::UInt64, outcome_code::Int32,
    status::Int32)::Cint
    message = TerminalSessionCompleted(
        TerminalSessionOperationId(operation_slot, operation_generation),
        outcome_code, status)
    outcome = EuclidActorRuntime.send!(
        runtime.actors, runtime.shell_session, message)
    EuclidActorRuntime.send!(
        runtime.actors, runtime.terminal_process_service, message)
    return Cint(outcome)
end

"""Emit one terminal shell interpolation lifecycle failure."""
function fail_shell_interpolation!(
    runtime::HostRuntime, request_id::UInt64, status,
    diagnostic::String)::Nothing
    EuclidActorRuntime.emit!(runtime.actors, ShellInterpolationResolved(
        request_id, Int32(status), String[], diagnostic))
    return nothing
end

"""Register one bounded interpolation request with a relative timeout."""
function ingest_shell_interpolation_for_host(
    runtime::HostRuntime, request_id::UInt64, source::AbstractString,
    timeout_ns::UInt64,
    session_generation::UInt64=runtime.session.generation)::Nothing
    if runtime.shutdown_requested ||
        runtime.session.phase !== HostSessionActive ||
        session_generation != runtime.session.generation
        @host_log runtime Logging.Warn "interpolation rejected" request_id reason="session"
        fail_shell_interpolation!(runtime, request_id,
            ShellInterpolationRuntimeStopped, "interpolation runtime is stopped")
        return nothing
    end
    now = EuclidActorRuntime.now_ns(runtime.actors.clock)
    deadline = timeout_ns > typemax(UInt64) - now ? typemax(UInt64) : now + timeout_ns
    request = ShellInterpolationRequested(request_id, String(source), deadline)
    key = shell_interpolation_request_key(request_id)
    registration = EuclidActorRuntime.register_request!(
        runtime.actors, key, runtime.shell_interpolation_service; value=request)
    if registration !== EuclidActorRuntime.RequestRegistered
        @host_log runtime Logging.Warn "interpolation rejected" request_id reason="duplicate"
        fail_shell_interpolation!(runtime, request_id,
            ShellInterpolationDuplicateRequest,
            "interpolation request was rejected as duplicate")
        return nothing
    end
    outcome = EuclidActorRuntime.send!(
        runtime.actors, runtime.shell_interpolation_service, request)
    if outcome !== EuclidActorRuntime.SendAccepted
        EuclidActorRuntime.resolve_request!(runtime.actors, key)
        @host_log runtime Logging.Warn "interpolation rejected" request_id reason="mailbox"
        fail_shell_interpolation!(runtime, request_id,
            ShellInterpolationRuntimeStopped,
            "interpolation owner could not accept the request")
    end
    return nothing
end

"""Cancel one interpolation that has not begun its non-preemptible actor turn."""
function cancel_shell_interpolation_for_host(
    runtime::HostRuntime, request_id::UInt64)::Bool
    key = shell_interpolation_request_key(request_id)
    pending = get(runtime.actors.pending_requests, key, nothing)
    if pending === nothing || pending.owner != runtime.shell_interpolation_service
        return false
    end
    EuclidActorRuntime.resolve_request!(runtime.actors, key)
    fail_shell_interpolation!(runtime, request_id, ShellInterpolationCancelled,
        "interpolation was cancelled before evaluation")
    return true
end

"""Emit a terminal evaluation failure through the host command buffer."""
function fail_evaluation_for_host!(
    runtime::HostRuntime, request_id::UInt64,
    message::AbstractString)::Nothing
    text = String(message)
    record_output_batch!(runtime.evaluator_state, runtime.actors,
        TerminalOutputBatch(request_id, text, ncodeunits(text), UInt64(0)))
    EuclidActorRuntime.emit!(
        runtime.actors, EvaluationCompleted(request_id))
    return nothing
end

"""Register and deliver one validated evaluation request."""
function deliver_evaluation_for_host!(
    runtime::HostRuntime, request::EvaluationRequested)::Nothing
    request_id = request.request_id
    registration = EuclidActorRuntime.register_request!(
        runtime.actors, evaluation_request_key(request_id), runtime.evaluator;
        value=request)
    if registration !== EuclidActorRuntime.RequestRegistered
        @host_log runtime Logging.Warn "evaluation rejected" request_id reason="registration"
        fail_evaluation_for_host!(runtime, request_id, "evaluation request was rejected")
        return nothing
    end
    outcome = EuclidActorRuntime.send!(
        runtime.actors, runtime.evaluator, request)
    if outcome !== EuclidActorRuntime.SendAccepted
        EuclidActorRuntime.resolve_request!(
            runtime.actors, evaluation_request_key(request_id))
        fail_evaluation_for_host!(runtime, request_id, "evaluation request was rejected")
        @host_log runtime Logging.Warn "evaluation rejected" request_id reason="mailbox"
    else
        @host_log runtime Logging.Debug "evaluation accepted" request_id
    end
    return nothing
end

"""Register and deliver one evaluation request without blocking the host."""
function ingest_evaluation_for_host(
    runtime::HostRuntime, request_id::UInt64, source::AbstractString,
    mode::Int32, session_generation::UInt64)::Nothing
    if runtime.shutdown_requested ||
        runtime.session.phase !== HostSessionActive ||
        session_generation != runtime.session.generation
        @host_log runtime Logging.Warn "evaluation rejected" request_id reason="session"
        fail_evaluation_for_host!(
            runtime, request_id, "evaluation runtime is stopped")
        return nothing
    end
    evaluation_mode = try
        EvaluationMode(mode)
    catch error
        error isa ArgumentError || rethrow()
        @host_log runtime Logging.Warn "evaluation rejected" request_id reason="invalid_mode" mode
        fail_evaluation_for_host!(runtime, request_id, "invalid evaluation mode")
        return nothing
    end
    request = EvaluationRequested(
        request_id, session_generation, String(source), evaluation_mode)
    return deliver_evaluation_for_host!(runtime, request)
end

"""Emit one typed completion failure through the host command buffer."""
function fail_completion!(
    runtime::HostRuntime, request_id::UInt64,
    reason::CompletionFailureReason)::Nothing
    EuclidActorRuntime.emit!(
        runtime.actors, CompletionFailed(request_id, reason))
    return nothing
end

"""Register and deliver one correlated completion request without blocking."""
function ingest_completion_for_host(
    runtime::HostRuntime, request_id::UInt64, source::AbstractString,
    cursor_byte::Int32, show_candidates::Bool,
    session_generation::UInt64=runtime.session.generation)::Nothing
    if runtime.shutdown_requested ||
        runtime.session.phase !== HostSessionActive ||
        session_generation != runtime.session.generation
        @host_log runtime Logging.Warn "completion rejected" request_id reason="session"
        fail_completion!(runtime, request_id, CompletionRuntimeStopped)
        return nothing
    end
    request = CompletionRequested(
        request_id, String(source), Int(cursor_byte), show_candidates)
    registration = EuclidActorRuntime.register_request!(
        runtime.actors, request_id, runtime.completion_service; value=request)
    if registration === EuclidActorRuntime.RequestDuplicate
        @host_log runtime Logging.Warn "completion rejected" request_id reason="duplicate"
        fail_completion!(runtime, request_id, CompletionDuplicateRequest)
        return nothing
    elseif registration === EuclidActorRuntime.RequestStaleOwner
        @host_log runtime Logging.Warn "completion rejected" request_id reason="stale_owner"
        fail_completion!(runtime, request_id, CompletionActorStopped)
        return nothing
    end
    outcome = EuclidActorRuntime.send!(
        runtime.actors, runtime.completion_service, request)
    if outcome !== EuclidActorRuntime.SendAccepted
        EuclidActorRuntime.resolve_request!(runtime.actors, request_id)
        reason = outcome === EuclidActorRuntime.SendMailboxFull ?
            CompletionMailboxFull : CompletionActorStopped
        @host_log(
            runtime, Logging.Warn, "completion rejected", request_id,
            reason=string(reason))
        fail_completion!(runtime, request_id, reason)
    end
    return nothing
end

"""Register a completion request that may return a candidate table."""
function ingest_completion_candidates_for_host(
    runtime::HostRuntime, request_id::UInt64, source::AbstractString,
    cursor_byte::Int32,
    session_generation::UInt64=runtime.session.generation)::Nothing
    return ingest_completion_for_host(
        runtime, request_id, source, cursor_byte, true, session_generation)
end

"""Register a completion request intended only for inline preview."""
function ingest_completion_preview_for_host(
    runtime::HostRuntime, request_id::UInt64, source::AbstractString,
    cursor_byte::Int32,
    session_generation::UInt64=runtime.session.generation)::Nothing
    return ingest_completion_for_host(
        runtime, request_id, source, cursor_byte, false, session_generation)
end

"""Deliver one normalized host hotkey event to its Julia policy router."""
function ingest_hotkey_for_host(
    runtime::HostRuntime, action::Int32,
    current_terminal_visibility::Bool,
    decision_id::UInt64=UInt64(0))::Cint
    logical_action = try
        LogicalAction(action)
    catch error
        error isa ArgumentError || rethrow()
        return Cint(EuclidActorRuntime.SendStaleActor)
    end
    outcome = EuclidActorRuntime.send!(
        runtime.actors, runtime.hotkey_controller,
        HotkeyTriggered(logical_action, current_terminal_visibility, decision_id))
    return Cint(outcome)
end

"""Deliver one committed engine fact to Julia policy without direct mutation."""
function ingest_engine_event_for_host(
    runtime::HostRuntime, kind::Int32, tick::UInt64,
    revision::UInt64)::Cint
    event_kind = try
        EngineEventKind(kind)
    catch error
        error isa ArgumentError || rethrow()
        return Cint(EuclidActorRuntime.SendStaleActor)
    end
    outcome = EuclidActorRuntime.send!(
        runtime.actors, runtime.terminal_controller,
        EngineEventCommitted(event_kind, tick, revision))
    return Cint(outcome)
end

"""Install one generation-correlated native tick configuration result."""
function ingest_tick_stream_configuration_for_host(
    runtime::HostRuntime, session_generation::UInt64,
    stream_generation::UInt64, interval_steps::UInt64,
    active::Bool)::Bool
    acknowledgement = TickStreamConfigurationAcknowledged(
        session_generation, stream_generation, interval_steps, active)
    return acknowledge_tick_stream!(
        runtime.tick_service_state, acknowledgement)
end

"""Accumulate one native tick range in the current session service."""
function ingest_tick_pulse_for_host(
    runtime::HostRuntime, session_generation::UInt64,
    stream_generation::UInt64, sequence::UInt64,
    first_simulation_tick::UInt64, last_simulation_tick::UInt64,
    step_count::UInt64)::Bool
    pulse = NativeTickPulse(
        session_generation, stream_generation, sequence,
        first_simulation_tick, last_simulation_tick, step_count)
    return accumulate_tick_pulse!(
        runtime.tick_service_state, runtime.actors, pulse)
end

"""Deliver one native container configuration result to its session service."""
function ingest_terminal_container_configuration_result_for_host(
    runtime::HostRuntime, values::Vararg{Any,8})::Cint
    generation, accepted, reason, x, y, width, height, constrained = values
    rejection = try
        TerminalContainer.ConfigurationRejection(reason)
    catch error
        error isa ArgumentError || rethrow()
        return Cint(EuclidActorRuntime.SendStaleActor)
    end
    result = TerminalContainer.ConfigurationResult(
        generation, accepted, rejection,
        TerminalContainer.Rectangle(x, y, width, height), constrained)
    return Cint(EuclidActorRuntime.send!(runtime.actors,
        runtime.terminal_container_service, result))
end

"""Deliver one native committed container change to its session service."""
function ingest_terminal_container_changed_for_host(
    runtime::HostRuntime, values::Vararg{Any,16})::Cint
    session_generation, bounds_generation, interaction_id, cause,
        resize_edges, previous_x, previous_y, previous_width, previous_height,
        current_x, current_y, current_width, current_height, columns, rows,
        constrained = values
    change_cause = try
        TerminalContainer.ChangeCause(cause)
    catch error
        error isa ArgumentError || rethrow()
        return Cint(EuclidActorRuntime.SendStaleActor)
    end
    change = TerminalContainer.Change(
        session_generation, bounds_generation, interaction_id, change_cause,
        resize_edges,
        TerminalContainer.Rectangle(previous_x, previous_y,
            previous_width, previous_height),
        TerminalContainer.Rectangle(current_x, current_y,
            current_width, current_height),
        TerminalContainer.Dimensions(columns, rows), constrained)
    return Cint(EuclidActorRuntime.send!(runtime.actors,
        runtime.terminal_container_service, change))
end
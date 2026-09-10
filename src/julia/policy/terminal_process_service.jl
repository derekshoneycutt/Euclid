"""Command carrying one bounded direct process request to the display owner."""
struct TerminalProcessLaunchRequested
    request_id::UInt64
    owner_id::UInt64
    owner_generation::UInt64
    arguments::Vector{String}
    working_directory::String
    environment::Vector{Terminal.ProcessEnvironmentChange}
    inherit_environment::Bool
end

"""Explicit lifecycle request for process-service shutdown."""
struct StopTerminalProcessService end

"""Actor owning one Julia-originated terminal process and its waiting handle."""
mutable struct TerminalProcessService
    client::Terminal.ProcessClient
    pending::Union{Nothing,Terminal.ProcessLaunchRequest}
    active::Union{Nothing,Terminal.ProcessLaunchRequest}
    operation_id::Union{Nothing,TerminalSessionOperationId}
end

"""Create an idle process service over one evaluation-scoped broker."""
function TerminalProcessService(client::Terminal.ProcessClient)
    return TerminalProcessService(client, nothing, nothing, nothing)
end

"""Reject one launch and release its broker reservation."""
function reject_terminal_process!(
    service::TerminalProcessService,
    request::Terminal.ProcessLaunchRequest,
    message::String)::Nothing
    service.client.active_request_id == request.request_id &&
        (service.client.active_request_id = 0)
    put!(request.admission, Terminal.TerminalProcessError(message))
    return nothing
end

"""Submit one launch only while the process service is idle."""
function EuclidActorRuntime.receive!(
    service::TerminalProcessService,
    context::EuclidActorRuntime.ActorContext,
    request::Terminal.ProcessLaunchRequest)::Nothing
    if service.pending !== nothing || service.active !== nothing
        reject_terminal_process!(
            service, request, "a terminal process is already active")
        return nothing
    end
    service.pending = request
    owner_id, owner_generation = shell_session_owner(context)
    EuclidActorRuntime.emit!(context, TerminalProcessLaunchRequested(
        request.request_id, owner_id, owner_generation, request.arguments,
        request.working_directory, request.environment,
        request.inherit_environment))
    return nothing
end

"""Publish admission only for the currently pending process request."""
function EuclidActorRuntime.receive!(
    service::TerminalProcessService,
    _context::EuclidActorRuntime.ActorContext,
    message::TerminalSessionAccepted)::Nothing
    request = service.pending
    request === nothing && return nothing
    request.request_id == message.request_id || return nothing
    service.pending = nothing
    service.active = request
    service.operation_id = message.operation_id
    request.handle.operation_slot = message.operation_id.slot
    request.handle.operation_generation = message.operation_id.generation
    request.handle.running = true
    put!(request.admission, nothing)
    return nothing
end

"""Reject only the currently pending process request."""
function EuclidActorRuntime.receive!(
    service::TerminalProcessService,
    _context::EuclidActorRuntime.ActorContext,
    message::TerminalSessionRejected)::Nothing
    request = service.pending
    request === nothing && return nothing
    request.request_id == message.request_id || return nothing
    service.pending = nothing
    reject_terminal_process!(service, request,
        "terminal process launch rejected with reason $(message.reason)")
    return nothing
end

"""Complete only the active operation and wake all future handle waits."""
function EuclidActorRuntime.receive!(
    service::TerminalProcessService,
    _context::EuclidActorRuntime.ActorContext,
    message::TerminalSessionCompleted)::Nothing
    request = service.active
    operation_id = service.operation_id
    request === nothing && return nothing
    operation_id == message.operation_id || return nothing
    result = Terminal.TerminalProcessResult(
        Terminal.ProcessOutcome(message.outcome), message.status)
    request.handle.running = false
    service.client.active_request_id = 0
    service.active = nothing
    service.operation_id = nothing
    put!(request.handle.completion, result)
    return nothing
end

"""Emit graceful cancellation only for the matching active handle."""
function EuclidActorRuntime.receive!(
    service::TerminalProcessService,
    context::EuclidActorRuntime.ActorContext,
    request::Terminal.ProcessCancelRequest)::Nothing
    active = service.active
    operation_id = service.operation_id
    active === nothing && return nothing
    active.handle === request.handle || return nothing
    owner_id, owner_generation = shell_session_owner(context)
    EuclidActorRuntime.emit!(context, CancelTerminalSessionRequested(
        owner_id, owner_generation, operation_id))
    return nothing
end

"""Unblock pending callers and emit owner-bound cleanup before actor shutdown."""
function EuclidActorRuntime.receive!(
    service::TerminalProcessService,
    context::EuclidActorRuntime.ActorContext,
    _message::StopTerminalProcessService)::Nothing
    owner_id, owner_generation = shell_session_owner(context)
    if service.pending !== nothing
        request = service.pending
        EuclidActorRuntime.emit!(context, AbandonTerminalSessionRequested(
            request.request_id, owner_id, owner_generation))
        reject_terminal_process!(
            service, request, "terminal process service is stopping")
    elseif service.active !== nothing
        request = service.active
        EuclidActorRuntime.emit!(context, CancelTerminalSessionRequested(
            owner_id, owner_generation, service.operation_id))
        request.handle.running = false
        service.client.active_request_id = 0
        put!(request.handle.completion,
            Terminal.TerminalProcessResult(
                Terminal.ProcessCancelled, Int32(0)))
    end
    service.pending = nothing
    service.active = nothing
    service.operation_id = nothing
    EuclidActorRuntime.stop!(context)
    return nothing
end

"""Transfer bounded broker requests into the process actor mailbox."""
function drain_terminal_process_requests!(
    runtime::EuclidActorRuntime.ActorRuntime,
    actor::EuclidActorRuntime.ActorId,
    client::Terminal.ProcessClient)::Nothing
    while isready(client.requests)
        request = take!(client.requests)
        outcome = EuclidActorRuntime.send!(runtime, actor, request)
        outcome === EuclidActorRuntime.SendAccepted && continue
        if request isa Terminal.ProcessLaunchRequest
            client.active_request_id = 0
            put!(request.admission, Terminal.TerminalProcessError(
                "terminal process service is unavailable"))
        end
    end
    return nothing
end
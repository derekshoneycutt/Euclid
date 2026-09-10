"""Stable native operation identity accepted for one foreground session."""
struct TerminalSessionOperationId
    slot::UInt32
    generation::UInt64
end

"""User intent submitted to the Julia shell-session policy owner."""
struct ShellSessionSubmit
    request_id::UInt64
end

"""Command asking Odin to validate and begin one already-resolved process plan."""
struct BeginTerminalSessionRequested
    request_id::UInt64
    owner_id::UInt64
    owner_generation::UInt64
end

"""Authoritative acceptance fact returned by Odin after operation registration."""
struct TerminalSessionAccepted
    request_id::UInt64
    operation_id::TerminalSessionOperationId
end

"""Authoritative rejection fact returned before an operation exists."""
struct TerminalSessionRejected
    request_id::UInt64
    reason::Int32
end

"""Authoritative terminal fact returned exactly once by the Odin operation."""
struct TerminalSessionCompleted
    operation_id::TerminalSessionOperationId
    outcome::Int32
    status::Int32
end

"""Owner-bound cancellation command emitted before a shell-session actor stops."""
struct CancelTerminalSessionRequested
    owner_id::UInt64
    owner_generation::UInt64
    operation_id::TerminalSessionOperationId
end

"""Pending-request abandonment emitted when an owner stops before acceptance."""
struct AbandonTerminalSessionRequested
    request_id::UInt64
    owner_id::UInt64
    owner_generation::UInt64
end

"""Explicit lifecycle request allowing the actor to reconcile before stopping."""
struct StopShellSession end

"""Actor owning shell-session correlation without process mechanism state."""
mutable struct ShellSession
    pending_request::Union{Nothing,UInt64}
    operation_id::Union{Nothing,TerminalSessionOperationId}
    completed_count::Int
    rejected_count::Int
end

"""Create an idle shell-session policy actor without process mechanism state."""
ShellSession() = ShellSession(nothing, nothing, 0, 0)

"""Return the stable native owner fields for one actor generation."""
shell_session_owner(context::EuclidActorRuntime.ActorContext) =
    (UInt64(context.self.index), context.self.generation)

"""Submit one request only while the shell-session actor is idle."""
function EuclidActorRuntime.receive!(
    session::ShellSession,
    context::EuclidActorRuntime.ActorContext,
    message::ShellSessionSubmit)::Nothing
    if session.pending_request !== nothing || session.operation_id !== nothing
        return nothing
    end
    session.pending_request = message.request_id
    owner_id, owner_generation = shell_session_owner(context)
    EuclidActorRuntime.emit!(context, BeginTerminalSessionRequested(
        message.request_id, owner_id, owner_generation))
    return nothing
end

"""Accept only the begin fact correlated to the current pending request."""
function EuclidActorRuntime.receive!(
    session::ShellSession,
    _context::EuclidActorRuntime.ActorContext,
    message::TerminalSessionAccepted)::Nothing
    session.pending_request == message.request_id || return nothing
    session.pending_request = nothing
    session.operation_id = message.operation_id
    return nothing
end

"""Resolve only the rejection correlated to the current pending request."""
function EuclidActorRuntime.receive!(
    session::ShellSession,
    _context::EuclidActorRuntime.ActorContext,
    message::TerminalSessionRejected)::Nothing
    session.pending_request == message.request_id || return nothing
    session.pending_request = nothing
    session.rejected_count += 1
    return nothing
end

"""Consume one matching completion and ignore stale or duplicate facts."""
function EuclidActorRuntime.receive!(
    session::ShellSession,
    _context::EuclidActorRuntime.ActorContext,
    message::TerminalSessionCompleted)::Nothing
    session.operation_id == message.operation_id || return nothing
    session.operation_id = nothing
    session.completed_count += 1
    return nothing
end

"""Emit owner-bound cleanup intent before invalidating the actor generation."""
function EuclidActorRuntime.receive!(
    session::ShellSession,
    context::EuclidActorRuntime.ActorContext,
    _message::StopShellSession)::Nothing
    owner_id, owner_generation = shell_session_owner(context)
    if session.operation_id !== nothing
        EuclidActorRuntime.emit!(context, CancelTerminalSessionRequested(
            owner_id, owner_generation, session.operation_id))
    elseif session.pending_request !== nothing
        EuclidActorRuntime.emit!(context, AbandonTerminalSessionRequested(
            session.pending_request, owner_id, owner_generation))
    end
    session.pending_request = nothing
    session.operation_id = nothing
    EuclidActorRuntime.stop!(context)
    return nothing
end
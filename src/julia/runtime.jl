"""Deterministic, reactor-owned actor scheduling without host dependencies."""
module EuclidActorRuntime

export AbstractClock, ActorContext, ActorFailed, ActorFailure, ActorId, ActorRuntime
export ManualClock, PendingRequest, ProductionClock, PumpStatus
export RequestOutcome, RequestDuplicate, RequestRegistered, RequestStaleOwner
export SendOutcome, SendAccepted, SendMailboxFull, SendStaleActor
export StopOutcome, StopAccepted, StopStaleActor
export advance!, emit!, is_live, now_ns, pending_request_count, pump!, receive!
export register_request!, resolve_request!, send!, spawn!, stop!, take_failures!
export take_outgoing!

"""Clock source used to bound actor pumps without coupling tests to wall time."""
abstract type AbstractClock end

"""Stable actor identity tied to one slot generation."""
struct ActorId
    index::Int
    generation::UInt64
end

"""Monotonic production clock backed by Julia's nanosecond timer."""
struct ProductionClock <: AbstractClock end

"""Deterministic clock advanced explicitly by tests or host fixtures."""
mutable struct ManualClock <: AbstractClock
    value_ns::UInt64
end

"""Result of attempting delivery to one bounded actor mailbox."""
@enum SendOutcome begin
    SendAccepted
    SendStaleActor
    SendMailboxFull
end

"""Result of attempting to stop an actor lifetime."""
@enum StopOutcome begin
    StopAccepted
    StopStaleActor
end

"""Result of registering a request owned by an actor lifetime."""
@enum RequestOutcome begin
    RequestRegistered
    RequestDuplicate
    RequestStaleOwner
end

"""One request correlated to the actor lifetime responsible for resolving it."""
struct PendingRequest
    owner::ActorId
    value::Any
end

"""Failure notification delivered to a live supervisor when possible."""
struct ActorFailed
    actor::ActorId
    exception::Any
    message::Any
end

"""Recorded failure retained even when supervisor notification cannot be delivered."""
struct ActorFailure
    actor::ActorId
    supervisor::Union{Nothing,ActorId}
    exception::Any
    message::Any
end

"""Mutable state for one live actor generation."""
mutable struct ActorSlot
    actor::Any
    supervisor::Union{Nothing,ActorId}
    mailbox::Vector{Any}
    mailbox_capacity::Int
    queued::Bool
end

"""Single-thread-owned state for deterministic actor scheduling."""
mutable struct ActorRuntime
    slots::Vector{Union{Nothing,ActorSlot}}
    generations::Vector{UInt64}
    ready_queue::Vector{ActorId}
    ready_head::Int
    pending_requests::Dict{Any,PendingRequest}
    outgoing::Vector{Any}
    failures::Vector{ActorFailure}
    clock::AbstractClock
    default_mailbox_capacity::Int
    owner_thread::Int
end

"""Context passed to one actor turn for runtime operations."""
struct ActorContext
    runtime::ActorRuntime
    self::ActorId
end

"""Summary of bounded work performed by one manual pump."""
struct PumpStatus
    turns::Int
    remaining_ready::Int
    deadline_reached::Bool
end

"""Create an empty actor runtime owned by the constructing Julia thread."""
function ActorRuntime(;
    clock::AbstractClock=ProductionClock(), mailbox_capacity::Integer=64)
    mailbox_capacity > 0 || throw(ArgumentError("mailbox capacity must be positive"))
    return ActorRuntime(
        Union{Nothing,ActorSlot}[], UInt64[], ActorId[], 1,
        Dict{Any,PendingRequest}(), Any[], ActorFailure[], clock,
        Int(mailbox_capacity), Threads.threadid())
end

"""Return the current monotonic production time in nanoseconds."""
function now_ns(_clock::ProductionClock)::UInt64
    return time_ns()
end

"""Return the current deterministic clock value in nanoseconds."""
function now_ns(clock::ManualClock)::UInt64
    return clock.value_ns
end

"""Advance a deterministic clock by a nonnegative nanosecond delta."""
function advance!(clock::ManualClock, delta_ns::Integer)::UInt64
    delta_ns >= 0 || throw(ArgumentError("clock delta must be nonnegative"))
    clock.value_ns += UInt64(delta_ns)
    return clock.value_ns
end

"""Reject runtime mutation from any thread other than its reactor owner."""
function assert_owner(runtime::ActorRuntime)::Nothing
    Threads.threadid() == runtime.owner_thread ||
        throw(ArgumentError("actor runtime mutated outside its owner thread"))
    return nothing
end

"""Return the live slot matching an actor identity, or `nothing` when stale."""
function actor_slot(runtime::ActorRuntime, actor_id::ActorId)
    1 <= actor_id.index <= length(runtime.slots) || return nothing
    runtime.generations[actor_id.index] == actor_id.generation || return nothing
    return runtime.slots[actor_id.index]
end

"""Return whether an actor identity names its currently live slot generation."""
function is_live(runtime::ActorRuntime, actor_id::ActorId)::Bool
    return actor_slot(runtime, actor_id) !== nothing
end

"""Spawn an actor into a fresh generation of an available runtime slot."""
function spawn!(
    runtime::ActorRuntime,
    actor;
    supervisor::Union{Nothing,ActorId}=nothing,
    mailbox_capacity::Integer=runtime.default_mailbox_capacity)::ActorId
    assert_owner(runtime)
    mailbox_capacity > 0 || throw(ArgumentError("mailbox capacity must be positive"))
    supervisor === nothing || is_live(runtime, supervisor) ||
        throw(ArgumentError("supervisor must identify a live actor"))
    index = findfirst(isnothing, runtime.slots)
    if index === nothing
        push!(runtime.slots, nothing)
        push!(runtime.generations, 0)
        index = length(runtime.slots)
    end
    runtime.generations[index] += 1
    actor_id = ActorId(index, runtime.generations[index])
    runtime.slots[index] = ActorSlot(
        actor, supervisor, Any[], Int(mailbox_capacity), false)
    return actor_id
end

"""Queue an actor once when its mailbox transitions into ready work."""
function queue_actor!(runtime::ActorRuntime, actor_id::ActorId, slot::ActorSlot)::Nothing
    if !slot.queued
        push!(runtime.ready_queue, actor_id)
        slot.queued = true
    end
    return nothing
end

"""Attempt bounded message delivery to one actor generation."""
function send!(runtime::ActorRuntime, actor_id::ActorId, message)::SendOutcome
    assert_owner(runtime)
    slot = actor_slot(runtime, actor_id)
    slot === nothing && return SendStaleActor
    length(slot.mailbox) >= slot.mailbox_capacity && return SendMailboxFull
    push!(slot.mailbox, message)
    queue_actor!(runtime, actor_id, slot)
    return SendAccepted
end

"""Attempt message delivery from inside an actor turn."""
function send!(
    context::ActorContext, actor_id::ActorId, message)::SendOutcome
    return send!(context.runtime, actor_id, message)
end

"""Remove all pending requests owned by one actor generation."""
function remove_pending_requests!(runtime::ActorRuntime, owner::ActorId)::Int
    initial_count = length(runtime.pending_requests)
    filter!(entry -> entry.second.owner != owner, runtime.pending_requests)
    return initial_count - length(runtime.pending_requests)
end

"""Stop one actor generation and invalidate its mailbox and pending requests."""
function stop!(runtime::ActorRuntime, actor_id::ActorId)::StopOutcome
    assert_owner(runtime)
    slot = actor_slot(runtime, actor_id)
    slot === nothing && return StopStaleActor
    empty!(slot.mailbox)
    runtime.slots[actor_id.index] = nothing
    remove_pending_requests!(runtime, actor_id)
    return StopAccepted
end

"""Stop the actor currently executing a turn."""
function stop!(context::ActorContext)::StopOutcome
    return stop!(context.runtime, context.self)
end

"""Register request correlation owned by a live actor generation."""
function register_request!(
    runtime::ActorRuntime, request_id, owner::ActorId; value=nothing)::RequestOutcome
    assert_owner(runtime)
    is_live(runtime, owner) || return RequestStaleOwner
    haskey(runtime.pending_requests, request_id) && return RequestDuplicate
    runtime.pending_requests[request_id] = PendingRequest(owner, value)
    return RequestRegistered
end

"""Remove and return one pending request, or `nothing` when absent."""
function resolve_request!(runtime::ActorRuntime, request_id)
    assert_owner(runtime)
    return pop!(runtime.pending_requests, request_id, nothing)
end

"""Return the number of unresolved requests owned by live actors."""
function pending_request_count(runtime::ActorRuntime)::Int
    return length(runtime.pending_requests)
end

"""Append a pure Julia command intended for the host adapter."""
function emit!(runtime::ActorRuntime, command)::Nothing
    assert_owner(runtime)
    push!(runtime.outgoing, command)
    return nothing
end

"""Append a host command from inside an actor turn."""
function emit!(context::ActorContext, command)::Nothing
    return emit!(context.runtime, command)
end

"""Take all outgoing commands in insertion order and clear the runtime buffer."""
function take_outgoing!(runtime::ActorRuntime)::Vector{Any}
    assert_owner(runtime)
    outgoing = copy(runtime.outgoing)
    empty!(runtime.outgoing)
    return outgoing
end

"""Take all recorded actor failures and clear the diagnostic buffer."""
function take_failures!(runtime::ActorRuntime)::Vector{ActorFailure}
    assert_owner(runtime)
    failures = copy(runtime.failures)
    empty!(runtime.failures)
    return failures
end

"""Handle one unescaped actor exception through cleanup and supervision."""
function handle_failure!(
    runtime::ActorRuntime,
    actor_id::ActorId,
    slot::ActorSlot,
    message,
    exception)::Nothing
    failure = ActorFailure(actor_id, slot.supervisor, exception, message)
    push!(runtime.failures, failure)
    stop!(runtime, actor_id)
    if slot.supervisor !== nothing
        send!(runtime, slot.supervisor, ActorFailed(actor_id, exception, message))
    end
    return nothing
end

"""Process one message for a ready actor and restore round-robin readiness."""
function process_turn!(runtime::ActorRuntime, actor_id::ActorId)::Bool
    slot = actor_slot(runtime, actor_id)
    slot === nothing && return false
    slot.queued = false
    isempty(slot.mailbox) && return false
    message = popfirst!(slot.mailbox)
    context = ActorContext(runtime, actor_id)
    try
        receive!(slot.actor, context, message)
    catch exception
        handle_failure!(runtime, actor_id, slot, message, exception)
    end
    current_slot = actor_slot(runtime, actor_id)
    if current_slot !== nothing && !isempty(current_slot.mailbox)
        queue_actor!(runtime, actor_id, current_slot)
    end
    return true
end

"""Discard consumed ready-queue storage while retaining newly queued actors."""
function compact_ready_queue!(runtime::ActorRuntime)::Nothing
    if runtime.ready_head > length(runtime.ready_queue)
        empty!(runtime.ready_queue)
        runtime.ready_head = 1
    elseif runtime.ready_head > 64
        deleteat!(runtime.ready_queue, 1:(runtime.ready_head - 1))
        runtime.ready_head = 1
    end
    return nothing
end

"""Return the number of live actors currently represented in the ready queue."""
function ready_actor_count(runtime::ActorRuntime)::Int
    return count(slot -> slot !== nothing && slot.queued, runtime.slots)
end

"""Run bounded actor turns until work, turn budget, or deadline is exhausted."""
function pump!(
    runtime::ActorRuntime;
    max_turns::Integer,
    deadline_ns::Integer=typemax(UInt64))::PumpStatus
    assert_owner(runtime)
    max_turns >= 0 || throw(ArgumentError("max turns must be nonnegative"))
    deadline_ns >= 0 || throw(ArgumentError("deadline must be nonnegative"))
    turns = 0
    deadline = UInt64(deadline_ns)
    deadline_reached = false
    while turns < max_turns && runtime.ready_head <= length(runtime.ready_queue)
        if now_ns(runtime.clock) >= deadline
            deadline_reached = true
            break
        end
        actor_id = runtime.ready_queue[runtime.ready_head]
        runtime.ready_head += 1
        process_turn!(runtime, actor_id) && (turns += 1)
    end
    compact_ready_queue!(runtime)
    return PumpStatus(turns, ready_actor_count(runtime), deadline_reached)
end

"""Reject an actor message when no concrete handler method is defined."""
function receive!(actor, context::ActorContext, message)
    throw(MethodError(receive!, (actor, context, message)))
end

end

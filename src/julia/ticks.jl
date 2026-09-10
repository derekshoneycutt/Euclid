module Ticks

import ..EuclidActorRuntime: ActorId

export Subscription, Tick, TickError, subscribe, unsubscribe!

const TICK_CONTEXT_KEY = :euclid_tick_client
const TICK_REQUEST_CAPACITY = 64
const NANOSECONDS_PER_SECOND = 1_000_000_000.0

"""One accumulated, contiguous range of executed simulation updates."""
struct Tick
    sequence::UInt64
    first_simulation_tick::UInt64
    last_simulation_tick::UInt64
    step_count::UInt64
    elapsed_seconds::Float64
end

"""Public error raised when a tick operation cannot be admitted."""
struct TickError <: Exception
    message::Base.String
end

"""Generation-safe handle for one session-owned callback subscription."""
mutable struct Subscription
    id::UInt64
    generation::UInt64
    active::Bool
    effective_interval::Float64
    client::Core.Any
end

"""Request to create one callback subscription in the session tick service."""
struct SubscribeRequest
    callback::Core.Any
    requested_period_ns::UInt64
    subscription::Subscription
    admission::Base.Channel{Core.Any}
end

"""Request to attach one existing actor to the session tick service."""
struct ActorSubscribeRequest
    actor::ActorId
    requested_period_ns::UInt64
    subscription::Subscription
    admission::Base.Channel{Core.Any}
end

"""Request idempotent removal of one callback subscription."""
struct UnsubscribeRequest
    subscription::Subscription
end

"""Bounded broker shared by one evaluator and its session tick service."""
mutable struct TickClient
    requests::Base.Channel{Core.Any}
    generation::UInt64
    next_subscription_id::UInt64
    accepting::Bool
end

"""Create an accepting broker for one nonzero Julia session generation."""
function TickClient(generation::UInt64)
    generation > 0 || Base.throw(Base.ArgumentError(
        "tick client generation must be nonzero"))
    return TickClient(Base.Channel{Core.Any}(TICK_REQUEST_CAPACITY),
        generation, UInt64(1), true)
end

"""Render one public tick error without exposing internal service state."""
function Base.showerror(io::Base.IO, error::TickError)
    Base.print(io, error.message)
end

"""Run an operation with tick authority scoped to the current evaluation task."""
function with_tick_client(operation, client::TickClient)
    return task_local_storage(operation, TICK_CONTEXT_KEY, client)
end

"""Return the current evaluation's tick broker or reject unsupported context."""
function current_tick_client()::TickClient
    client = get(task_local_storage(), TICK_CONTEXT_KEY, Core.nothing)
    client isa TickClient || Base.throw(TickError(
        "tick subscriptions require an active Euclid evaluation"))
    client.accepting || Base.throw(TickError("tick service is stopping"))
    return client
end

"""Convert one finite positive interval in seconds to bounded nanoseconds."""
function interval_nanoseconds(interval)::UInt64
    seconds = convert(Float64, interval)
    isfinite(seconds) && seconds > 0 || Base.throw(Base.ArgumentError(
        "tick interval must be finite and positive"))
    nanoseconds = max(1, floor(seconds * NANOSECONDS_PER_SECOND))
    nanoseconds <= Float64(Base.typemax(UInt64)) || Base.throw(
        Base.ArgumentError("tick interval is too large"))
    return UInt64(nanoseconds)
end

"""Subscribe one callback at a period expressed in seconds."""
function subscribe(callback; interval=1 / 60)::Subscription
    callback isa Base.Function || Base.throw(Base.ArgumentError(
        "tick callback must be a function"))
    client = current_tick_client()
    subscription = Subscription(client.next_subscription_id,
        client.generation, true, 0.0, client)
    client.next_subscription_id += 1
    admission = Base.Channel{Core.Any}(1)
    put!(client.requests, SubscribeRequest(
        callback, interval_nanoseconds(interval), subscription, admission))
    result = Base.take!(admission)
    result === Core.nothing || Base.throw(result)
    return subscription
end

"""Subscribe an existing actor without transferring ownership of its lifetime."""
function subscribe(actor::ActorId; interval=1 / 60)::Subscription
    client = current_tick_client()
    subscription = Subscription(client.next_subscription_id,
        client.generation, true, 0.0, client)
    client.next_subscription_id += 1
    admission = Channel{Any}(1)
    put!(client.requests, ActorSubscribeRequest(
        actor, interval_nanoseconds(interval), subscription, admission))
    result = take!(admission)
    result === nothing || throw(result)
    return subscription
end

"""Deactivate one subscription immediately and request idempotent cleanup."""
function unsubscribe!(subscription::Subscription)::Bool
    subscription.active || return false
    subscription.active = false
    client = subscription.client
    client isa TickClient && client.accepting &&
        put!(client.requests, UnsubscribeRequest(subscription))
    return true
end

end

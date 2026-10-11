const TICK_FIXED_RATE_HZ = UInt64(60)
const TICK_NANOSECONDS_PER_SECOND = UInt64(1_000_000_000)

"""Request that Odin configure one generation-scoped native tick stream."""
struct TickStreamConfigureRequested
    session_generation::UInt64
    stream_generation::UInt64
    requested_period_ns::UInt64
end

"""Request that Odin stop one exact native tick stream generation."""
struct TickStreamStopRequested
    session_generation::UInt64
    stream_generation::UInt64
end

"""Configuration result returned by the display-owned tick publisher."""
struct TickStreamConfigurationAcknowledged
    session_generation::UInt64
    stream_generation::UInt64
    interval_steps::UInt64
    active::Bool
end

"""One coalesced contiguous range of executed native simulation updates."""
struct NativeTickPulse
    session_generation::UInt64
    stream_generation::UInt64
    sequence::UInt64
    first_simulation_tick::UInt64
    last_simulation_tick::UInt64
    step_count::UInt64
end

"""Single mailbox token allowing one callback to consume accumulated state."""
struct TickWakeup end

"""Notification that one callback wrapper ended its owned subscription."""
struct TickCallbackEnded
    subscription_id::UInt64
    subscription_generation::UInt64
end

"""Explicit lifecycle request for session tick-service shutdown."""
struct StopTickService end

"""Mutable cadence and delivery state for one callback or actor subscription."""
mutable struct TickSubscriptionState
    handle::Ticks.Subscription
    callback::Any
    destination::EuclidActorRuntime.ActorId
    owns_destination::Bool
    requested_period_ns::UInt64
    interval_steps::UInt64
    accumulated_steps::UInt64
    first_simulation_tick::UInt64
    last_simulation_tick::UInt64
    next_sequence::UInt64
    wakeup_queued::Bool
end

"""Callback actor that consumes the latest coalesced subscription state."""
mutable struct TickCallbackWrapper
    subscription::TickSubscriptionState
    service::EuclidActorRuntime.ActorId
end

"""Session actor owning callback subscriptions and native stream cadence."""
mutable struct TickService
    session_generation::UInt64
    client::Ticks.TickClient
    subscriptions::Dict{UInt64,TickSubscriptionState}
    stream_generation::UInt64
    stream_active::Bool
    stream_acknowledged::Bool
    native_interval_steps::UInt64
    last_native_sequence::UInt64
    last_native_tick::UInt64
    stopping::Bool
end

"""Create an idle tick service for one session generation and broker."""
function TickService(
    session_generation::UInt64, client::Ticks.TickClient)
    return TickService(session_generation, client,
        Dict{UInt64,TickSubscriptionState}(), UInt64(0), false, false,
        UInt64(0), UInt64(0), UInt64(0), false)
end

"""Quantize one nanosecond period upward to fixed simulation steps."""
function tick_interval_steps(requested_period_ns::UInt64)::UInt64
    whole_seconds, remaining_ns = divrem(
        requested_period_ns, TICK_NANOSECONDS_PER_SECOND)
    whole_seconds > typemax(UInt64) ÷ TICK_FIXED_RATE_HZ &&
        return typemax(UInt64)
    steps = whole_seconds * TICK_FIXED_RATE_HZ
    remainder_steps = remaining_ns * TICK_FIXED_RATE_HZ
    steps += remainder_steps ÷ TICK_NANOSECONDS_PER_SECOND
    remainder_steps % TICK_NANOSECONDS_PER_SECOND == 0 || (steps += 1)
    return max(steps, UInt64(1))
end

"""Return the smallest requested period among active subscriptions."""
function minimum_tick_period(service::TickService)::UInt64
    return minimum(
        subscription.requested_period_ns
        for subscription in values(service.subscriptions))
end

"""Emit the native stream change required by the current registry."""
function reconfigure_tick_stream!(
    service::TickService,
    context::EuclidActorRuntime.ActorContext)::Nothing
    previous_generation = service.stream_generation
    if isempty(service.subscriptions)
        if service.stream_active
            EuclidActorRuntime.emit!(context, TickStreamStopRequested(
                service.session_generation, previous_generation))
        end
        service.stream_active = false
        service.stream_acknowledged = false
        service.native_interval_steps = 0
        return nothing
    end
    service.stream_generation += 1
    service.stream_active = true
    service.stream_acknowledged = false
    service.native_interval_steps = 0
    service.last_native_sequence = 0
    service.last_native_tick = 0
    EuclidActorRuntime.emit!(context, TickStreamConfigureRequested(
        service.session_generation, service.stream_generation,
        minimum_tick_period(service)))
    return nothing
end

"""Reject one pending subscription request with a public error."""
function reject_tick_subscription!(
    request::Union{Ticks.SubscribeRequest,Ticks.ActorSubscribeRequest},
    message::String)::Nothing
    request.subscription.active = false
    put!(request.admission, Ticks.TickError(message))
    return nothing
end

"""Create one callback wrapper and reconfigure native cadence."""
function EuclidActorRuntime.receive!(
    service::TickService,
    context::EuclidActorRuntime.ActorContext,
    request::Ticks.SubscribeRequest)::Nothing
    if service.stopping || !service.client.accepting ||
        request.subscription.generation != service.session_generation
        reject_tick_subscription!(request, "tick service is stopping")
        return nothing
    end
    subscription_id = request.subscription.id
    haskey(service.subscriptions, subscription_id) &&
        return reject_tick_subscription!(request, "duplicate tick subscription")
    interval_steps = tick_interval_steps(request.requested_period_ns)
    request.subscription.effective_interval =
        Float64(interval_steps) / Float64(TICK_FIXED_RATE_HZ)
    placeholder = EuclidActorRuntime.ActorId(0, UInt64(0))
    subscription = TickSubscriptionState(
        request.subscription, request.callback, placeholder, true,
        request.requested_period_ns, interval_steps, UInt64(0), UInt64(0),
        UInt64(0), UInt64(0), false)
    wrapper = EuclidActorRuntime.spawn!(context.runtime,
        TickCallbackWrapper(subscription, context.self);
        supervisor=context.self, mailbox_capacity=1)
    subscription.destination = wrapper
    service.subscriptions[subscription_id] = subscription
    reconfigure_tick_stream!(service, context)
    put!(request.admission, nothing)
    return nothing
end

"""Attach one live actor destination and reconfigure native cadence."""
function EuclidActorRuntime.receive!(
    service::TickService,
    context::EuclidActorRuntime.ActorContext,
    request::Ticks.ActorSubscribeRequest)::Nothing
    if service.stopping || !service.client.accepting ||
        request.subscription.generation != service.session_generation
        reject_tick_subscription!(request, "tick service is stopping")
        return nothing
    end
    subscription_id = request.subscription.id
    haskey(service.subscriptions, subscription_id) &&
        return reject_tick_subscription!(request, "duplicate tick subscription")
    EuclidActorRuntime.is_live(context.runtime, request.actor) ||
        return reject_tick_subscription!(request, "tick actor is stale")
    interval_steps = tick_interval_steps(request.requested_period_ns)
    request.subscription.effective_interval =
        Float64(interval_steps) / Float64(TICK_FIXED_RATE_HZ)
    service.subscriptions[subscription_id] = TickSubscriptionState(
        request.subscription, nothing, request.actor, false,
        request.requested_period_ns, interval_steps, UInt64(0), UInt64(0),
        UInt64(0), UInt64(0), false)
    reconfigure_tick_stream!(service, context)
    put!(request.admission, nothing)
    return nothing
end

"""Remove one matching active or already deactivated subscription."""
function remove_tick_subscription!(
    service::TickService,
    context::EuclidActorRuntime.ActorContext,
    subscription_id::UInt64, generation::UInt64;
    stop_wrapper::Bool=true)::Bool
    generation == service.session_generation || return false
    subscription = get(service.subscriptions, subscription_id, nothing)
    subscription === nothing && return false
    subscription.handle.active = false
    delete!(service.subscriptions, subscription_id)
    stop_wrapper && subscription.owns_destination &&
        EuclidActorRuntime.stop!(context.runtime, subscription.destination)
    service.stopping || reconfigure_tick_stream!(service, context)
    return true
end

"""Apply one idempotent public unsubscribe request."""
function EuclidActorRuntime.receive!(
    service::TickService,
    context::EuclidActorRuntime.ActorContext,
    request::Ticks.UnsubscribeRequest)::Nothing
    remove_tick_subscription!(service, context, request.subscription.id,
        request.subscription.generation)
    return nothing
end

"""Remove a callback subscription after its wrapper returns false."""
function EuclidActorRuntime.receive!(
    service::TickService,
    context::EuclidActorRuntime.ActorContext,
    ended::TickCallbackEnded)::Nothing
    remove_tick_subscription!(service, context, ended.subscription_id,
        ended.subscription_generation; stop_wrapper=false)
    return nothing
end

"""Remove a callback subscription whose wrapper raised an exception."""
function EuclidActorRuntime.receive!(
    service::TickService,
    context::EuclidActorRuntime.ActorContext,
    failure::EuclidActorRuntime.ActorFailed)::Nothing
    subscription = findfirst(
        item -> item.owns_destination && item.destination == failure.actor,
        service.subscriptions)
    subscription === nothing && return nothing
    remove_tick_subscription!(service, context, subscription,
        service.session_generation; stop_wrapper=false)
    return nothing
end

"""Consume one accumulated callback delivery through world-age-safe dispatch."""
function EuclidActorRuntime.receive!(
    wrapper::TickCallbackWrapper,
    context::EuclidActorRuntime.ActorContext,
    _wakeup::TickWakeup)::Nothing
    subscription = wrapper.subscription
    subscription.wakeup_queued = false
    if !subscription.handle.active || subscription.accumulated_steps == 0
        return nothing
    end
    subscription.next_sequence += 1
    tick = Ticks.Tick(
        subscription.next_sequence, subscription.first_simulation_tick,
        subscription.last_simulation_tick, subscription.accumulated_steps,
        Float64(subscription.accumulated_steps) / Float64(TICK_FIXED_RATE_HZ))
    subscription.accumulated_steps = 0
    subscription.first_simulation_tick = 0
    subscription.last_simulation_tick = 0
    result = Base.invokelatest(subscription.callback, tick)
    if result === false
        subscription.handle.active = false
        EuclidActorRuntime.send!(context, wrapper.service,
            TickCallbackEnded(subscription.handle.id,
                subscription.handle.generation))
        EuclidActorRuntime.stop!(context)
    end
    return nothing
end

"""Return whether one native pulse extends the current acknowledged stream."""
function tick_pulse_valid(
    service::TickService, pulse::NativeTickPulse)::Bool
    service.stopping && return false
    service.stream_active && service.stream_acknowledged || return false
    pulse.session_generation == service.session_generation || return false
    pulse.stream_generation == service.stream_generation || return false
    tick_pulse_shape_valid(service, pulse) || return false
    service.last_native_tick > 0 &&
        pulse.first_simulation_tick <= service.last_native_tick && return false
    return true
end

"""Return whether one native pulse is newer and describes a contiguous range."""
function tick_pulse_shape_valid(
    service::TickService, pulse::NativeTickPulse)::Bool
    pulse.sequence > service.last_native_sequence || return false
    pulse.step_count > 0 || return false
    pulse.last_simulation_tick >= pulse.first_simulation_tick || return false
    pulse.last_simulation_tick - pulse.first_simulation_tick + 1 ==
        pulse.step_count || return false
    return true
end

"""Clear accumulated delivery state after one accepted delivery."""
function clear_tick_accumulation!(subscription::TickSubscriptionState)::Nothing
    subscription.accumulated_steps = 0
    subscription.first_simulation_tick = 0
    subscription.last_simulation_tick = 0
    return nothing
end

"""Attempt direct delivery while retaining accumulated state under pressure."""
function deliver_tick_to_actor!(
    runtime::EuclidActorRuntime.ActorRuntime,
    subscription::TickSubscriptionState)::Nothing
    subscription.handle.active || return nothing
    subscription.accumulated_steps >= subscription.interval_steps || return nothing
    tick = Ticks.Tick(
        subscription.next_sequence + 1, subscription.first_simulation_tick,
        subscription.last_simulation_tick, subscription.accumulated_steps,
        Float64(subscription.accumulated_steps) / Float64(TICK_FIXED_RATE_HZ))
    outcome = EuclidActorRuntime.send!(
        runtime, subscription.destination, tick)
    if outcome === EuclidActorRuntime.SendAccepted
        subscription.next_sequence += 1
        clear_tick_accumulation!(subscription)
    elseif outcome === EuclidActorRuntime.SendStaleActor
        subscription.handle.active = false
    end
    return nothing
end

"""Extend one subscription accumulation and admit bounded delivery work."""
function accumulate_tick_subscription!(
    runtime::EuclidActorRuntime.ActorRuntime,
    subscription::TickSubscriptionState,
    pulse::NativeTickPulse)::Nothing
    subscription.handle.active || return nothing
    if subscription.accumulated_steps == 0
        subscription.first_simulation_tick = pulse.first_simulation_tick
    end
    subscription.last_simulation_tick = pulse.last_simulation_tick
    subscription.accumulated_steps += pulse.step_count
    subscription.accumulated_steps >= subscription.interval_steps || return nothing
    if !subscription.owns_destination
        deliver_tick_to_actor!(runtime, subscription)
        return nothing
    end
    subscription.wakeup_queued && return nothing
    outcome = EuclidActorRuntime.send!(
        runtime, subscription.destination, TickWakeup())
    if outcome === EuclidActorRuntime.SendAccepted
        subscription.wakeup_queued = true
    elseif outcome === EuclidActorRuntime.SendStaleActor
        subscription.handle.active = false
    end
    return nothing
end

"""Accumulate one native pulse and queue at most one callback wake-up."""
function accumulate_tick_pulse!(
    service::TickService,
    runtime::EuclidActorRuntime.ActorRuntime,
    pulse::NativeTickPulse)::Bool
    tick_pulse_valid(service, pulse) || return false
    service.last_native_sequence = pulse.sequence
    service.last_native_tick = pulse.last_simulation_tick
    for subscription in values(service.subscriptions)
        accumulate_tick_subscription!(runtime, subscription, pulse)
    end
    return true
end

"""Install one current native configuration acknowledgement."""
function acknowledge_tick_stream!(
    service::TickService,
    acknowledgement::TickStreamConfigurationAcknowledged)::Bool
    service.stopping && return false
    acknowledgement.session_generation == service.session_generation ||
        return false
    acknowledgement.stream_generation == service.stream_generation ||
        return false
    acknowledgement.active == service.stream_active || return false
    if acknowledgement.active
        acknowledgement.interval_steps > 0 || return false
        service.native_interval_steps = acknowledgement.interval_steps
        service.stream_acknowledged = true
    else
        service.native_interval_steps = 0
        service.stream_acknowledged = false
    end
    return true
end

"""Stop native publication, callback wrappers, and the service actor."""
function EuclidActorRuntime.receive!(
    service::TickService,
    context::EuclidActorRuntime.ActorContext,
    _message::StopTickService)::Nothing
    service.stopping = true
    service.client.accepting = false
    if service.stream_active
        EuclidActorRuntime.emit!(context, TickStreamStopRequested(
            service.session_generation, service.stream_generation))
    end
    service.stream_active = false
    service.stream_acknowledged = false
    for subscription in values(service.subscriptions)
        subscription.handle.active = false
        subscription.owns_destination && EuclidActorRuntime.stop!(
            context.runtime, subscription.destination)
    end
    empty!(service.subscriptions)
    EuclidActorRuntime.stop!(context)
    return nothing
end

"""Transfer bounded broker requests and prune inactive handles on the host thread."""
function drain_tick_requests!(
    runtime::EuclidActorRuntime.ActorRuntime,
    actor::EuclidActorRuntime.ActorId,
    service::TickService)::Nothing
    for subscription in collect(values(service.subscriptions))
        if subscription.handle.active && !subscription.owns_destination
            deliver_tick_to_actor!(runtime, subscription)
        end
        subscription.handle.active && continue
        EuclidActorRuntime.send!(
            runtime, actor, Ticks.UnsubscribeRequest(subscription.handle))
    end
    while isready(service.client.requests)
        request = take!(service.client.requests)
        outcome = EuclidActorRuntime.send!(runtime, actor, request)
        outcome === EuclidActorRuntime.SendAccepted && continue
        (request isa Ticks.SubscribeRequest ||
            request isa Ticks.ActorSubscribeRequest) &&
            reject_tick_subscription!(request, "tick service is unavailable")
    end
    return nothing
end

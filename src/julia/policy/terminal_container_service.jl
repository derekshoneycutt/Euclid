"""Request emitted to Odin for one complete container configuration."""
struct TerminalContainerConfigureRequested
    config::TerminalContainer.Config
end

"""Acknowledgement emitted after the Julia broker processes one native change."""
struct TerminalContainerChangeObserved
    session_generation::UInt64
    bounds_generation::UInt64
    interaction_id::UInt64
end

"""Explicit lifecycle request for session container-service shutdown."""
struct StopTerminalContainerService end

"""One explicitly registered actor destination."""
mutable struct TerminalContainerSubscriptionState
    handle::TerminalContainer.Subscription
    destination::EuclidActorRuntime.ActorId
end

"""Session actor owning terminal-container subscriptions and correlation state."""
mutable struct TerminalContainerService
    session_generation::UInt64
    client::TerminalContainer.Client
    subscriptions::Dict{UInt64,TerminalContainerSubscriptionState}
    last_bounds_generation::UInt64
    last_configuration_generation::UInt64
    last_configuration_result::Union{Nothing,TerminalContainer.ConfigurationResult}
    configuration_pending::Bool
    pressure_count::UInt64
    stopping::Bool
end

"""Create an idle container service for one session generation and broker."""
function TerminalContainerService(
    session_generation::UInt64, client::TerminalContainer.Client)
    return TerminalContainerService(session_generation, client,
        Dict{UInt64,TerminalContainerSubscriptionState}(), UInt64(0),
        UInt64(0), nothing, false, UInt64(0), false)
end

"""Reject one pending public service request with a stable public error."""
function reject_terminal_container_request!(request, message::String)::Nothing
    request isa TerminalContainer.SubscribeRequest &&
        (request.subscription.active = false)
    put!(request.admission, TerminalContainer.TerminalContainerError(message))
    return nothing
end

"""Attach one live actor destination to the current session service."""
function EuclidActorRuntime.receive!(
    service::TerminalContainerService,
    context::EuclidActorRuntime.ActorContext,
    request::TerminalContainer.SubscribeRequest)::Nothing
    if service.stopping || !service.client.accepting ||
        request.subscription.generation != service.session_generation
        reject_terminal_container_request!(request,
            "terminal container service is stopping")
        return nothing
    end
    id = request.subscription.id
    if haskey(service.subscriptions, id)
        reject_terminal_container_request!(request,
            "duplicate terminal container subscription")
        return nothing
    end
    if !EuclidActorRuntime.is_live(context.runtime, request.actor)
        reject_terminal_container_request!(request,
            "terminal container actor is stale")
        return nothing
    end
    service.subscriptions[id] = TerminalContainerSubscriptionState(
        request.subscription, request.actor)
    put!(request.admission, nothing)
    return nothing
end

"""Apply one idempotent public unsubscribe request."""
function EuclidActorRuntime.receive!(
    service::TerminalContainerService,
    _context::EuclidActorRuntime.ActorContext,
    request::TerminalContainer.UnsubscribeRequest)::Nothing
    request.subscription.generation == service.session_generation || return nothing
    subscription = pop!(service.subscriptions, request.subscription.id, nothing)
    subscription === nothing || (subscription.handle.active = false)
    return nothing
end

"""Emit one validated complete configuration request to native authority."""
function EuclidActorRuntime.receive!(
    service::TerminalContainerService,
    context::EuclidActorRuntime.ActorContext,
    request::TerminalContainer.ConfigureRequest)::Nothing
    if service.stopping || !service.client.accepting ||
        service.configuration_pending
        reject_terminal_container_request!(request,
            "terminal container service is stopping")
        return nothing
    end
    if request.config.generation <= service.last_configuration_generation
        reject_terminal_container_request!(request,
            "terminal container configuration generation is stale")
        return nothing
    end
    service.last_configuration_generation = request.config.generation
    service.configuration_pending = true
    EuclidActorRuntime.emit!(context,
        TerminalContainerConfigureRequested(request.config))
    put!(request.admission, nothing)
    return nothing
end

"""Install one current native configuration result without mutating authority."""
function accept_terminal_container_configuration_result!(
    service::TerminalContainerService,
    result::TerminalContainer.ConfigurationResult)::Bool
    service.stopping && return false
    result.generation == service.last_configuration_generation || return false
    service.last_configuration_result = result
    service.configuration_pending = false
    return true
end

"""Process one current native configuration result in the service actor."""
function EuclidActorRuntime.receive!(
    service::TerminalContainerService,
    _context::EuclidActorRuntime.ActorContext,
    result::TerminalContainer.ConfigurationResult)::Nothing
    accept_terminal_container_configuration_result!(service, result)
    return nothing
end

"""Fan one committed change out independently and remove stale destinations."""
function deliver_terminal_container_change!(
    service::TerminalContainerService,
    runtime::EuclidActorRuntime.ActorRuntime,
    change::TerminalContainer.Change)::Nothing
    stale = UInt64[]
    for (id, subscription) in service.subscriptions
        outcome = EuclidActorRuntime.send!(
            runtime, subscription.destination, change)
        if outcome === EuclidActorRuntime.SendStaleActor
            subscription.handle.active = false
            push!(stale, id)
        elseif outcome === EuclidActorRuntime.SendMailboxFull
            service.pressure_count += 1
        end
    end
    for id in stale
        delete!(service.subscriptions, id)
    end
    return nothing
end

"""Process one newer native fact and emit its broker acknowledgement."""
function EuclidActorRuntime.receive!(
    service::TerminalContainerService,
    context::EuclidActorRuntime.ActorContext,
    change::TerminalContainer.Change)::Nothing
    service.stopping && return nothing
    change.session_generation == service.session_generation || return nothing
    change.bounds_generation > service.last_bounds_generation || return nothing
    change.interaction_id > 0 || return nothing
    service.last_bounds_generation = change.bounds_generation
    deliver_terminal_container_change!(service, context.runtime, change)
    EuclidActorRuntime.emit!(context, TerminalContainerChangeObserved(
        change.session_generation, change.bounds_generation,
        change.interaction_id))
    return nothing
end

"""Stop admission, clear subscriptions, and end the service actor."""
function EuclidActorRuntime.receive!(
    service::TerminalContainerService,
    context::EuclidActorRuntime.ActorContext,
    _message::StopTerminalContainerService)::Nothing
    service.stopping = true
    service.client.accepting = false
    for subscription in values(service.subscriptions)
        subscription.handle.active = false
    end
    empty!(service.subscriptions)
    EuclidActorRuntime.stop!(context)
    return nothing
end

"""Transfer bounded public requests into the session actor mailbox."""
function drain_terminal_container_requests!(
    runtime::EuclidActorRuntime.ActorRuntime,
    actor::EuclidActorRuntime.ActorId,
    service::TerminalContainerService)::Nothing
    while isready(service.client.requests)
        request = take!(service.client.requests)
        outcome = EuclidActorRuntime.send!(runtime, actor, request)
        outcome === EuclidActorRuntime.SendAccepted && continue
        reject_terminal_container_request!(request,
            "terminal container service is unavailable")
    end
    return nothing
end
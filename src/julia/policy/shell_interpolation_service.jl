"""One correlated request to evaluate an explicit shell interpolation leaf."""
struct ShellInterpolationRequested
    request_id::UInt64
    source::String
    deadline_ns::UInt64
end

"""Lifecycle outcomes added by the supervising shell interpolation actor."""
@enum ShellInterpolationLifecycleStatus::Int32 begin
    ShellInterpolationCancelled = 7
    ShellInterpolationTimedOut = 8
    ShellInterpolationRuntimeStopped = 9
    ShellInterpolationDuplicateRequest = 10
    ShellInterpolationEvaluatorBusy = 11
end

"""One terminal interpolation command containing bounded argument data."""
struct ShellInterpolationResolved
    request_id::UInt64
    status::Int32
    elements::Vector{String}
    diagnostic::String
end

"""Actor owning shell interpolation correlation and evaluation policy."""
struct ShellInterpolationService{F,G}
    evaluate::F
    evaluator_busy::G
end

"""Return the actor-runtime correlation key for one interpolation request."""
shell_interpolation_request_key(request_id::UInt64) =
    (:shell_interpolation, request_id)

"""Resolve one supervised shell interpolation request exactly once."""
function EuclidActorRuntime.receive!(
    service::ShellInterpolationService,
    context::EuclidActorRuntime.ActorContext,
    message::ShellInterpolationRequested)::Nothing
    key = shell_interpolation_request_key(message.request_id)
    pending = get(context.runtime.pending_requests, key, nothing)
    if pending === nothing || pending.owner != context.self
        return nothing
    end
    if EuclidActorRuntime.now_ns(context.runtime.clock) >= message.deadline_ns
        EuclidActorRuntime.resolve_request!(context.runtime, key)
        EuclidActorRuntime.emit!(context, ShellInterpolationResolved(
            message.request_id, Int32(ShellInterpolationTimedOut), String[],
            "interpolation timed out before evaluation"))
        return nothing
    end
    if service.evaluator_busy()
        EuclidActorRuntime.resolve_request!(context.runtime, key)
        EuclidActorRuntime.emit!(context, ShellInterpolationResolved(
            message.request_id, Int32(ShellInterpolationEvaluatorBusy), String[],
            "persistent evaluator is busy"))
        return nothing
    end
    result = service.evaluate(message.source)
    status = Int32(result.status)
    elements = result.elements
    diagnostic = result.diagnostic
    if EuclidActorRuntime.now_ns(context.runtime.clock) >= message.deadline_ns
        status = Int32(ShellInterpolationTimedOut)
        elements = String[]
        diagnostic = "interpolation timed out; evaluation is not preemptible"
    end
    EuclidActorRuntime.resolve_request!(context.runtime, key)
    EuclidActorRuntime.emit!(context, ShellInterpolationResolved(
        message.request_id, status, elements, diagnostic))
    return nothing
end
"""One correlated completion request using zero-indexed byte offsets."""
struct CompletionRequested
    request_id::UInt64
    source::String
    cursor_byte::Int
    show_candidates::Bool
end

"""One successful correlated completion result for Odin."""
struct CompletionResolved
    request_id::UInt64
    found::Bool
    replacement_start::Int
    replacement_end::Int
    insertion::String
    show_candidates::Bool
end

"""Reasons a completion request could not produce a normal result."""
@enum CompletionFailureReason::Int32 begin
    CompletionMailboxFull = 1
    CompletionActorStopped = 2
    CompletionRuntimeStopped = 3
    CompletionInternalFailure = 4
    CompletionDuplicateRequest = 5
end

"""One terminal failure for a correlated completion request."""
struct CompletionFailed
    request_id::UInt64
    reason::CompletionFailureReason
end

"""Actor that owns completion correlation and invokes the pure REPL mechanic."""
struct CompletionService{F}
    complete::F
end

"""Resolve one correlated completion request exactly once."""
function EuclidActorRuntime.receive!(
    service::CompletionService,
    context::EuclidActorRuntime.ActorContext,
    message::CompletionRequested)::Nothing
    pending = get(context.runtime.pending_requests, message.request_id, nothing)
    if pending === nothing || pending.owner != context.self
        return nothing
    end
    result = try
        service.complete(
            message.source, message.cursor_byte;
            show_candidates=message.show_candidates)
    catch error
        error isa InterruptException && rethrow()
        EuclidActorRuntime.resolve_request!(
            context.runtime, message.request_id)
        EuclidActorRuntime.emit!(context, CompletionFailed(
            message.request_id, CompletionInternalFailure))
        return nothing
    end
    EuclidActorRuntime.resolve_request!(context.runtime, message.request_id)
    EuclidActorRuntime.emit!(context, CompletionResolved(
        message.request_id, result.found, result.replacement_start,
        result.replacement_end, result.insertion, message.show_candidates))
    return nothing
end
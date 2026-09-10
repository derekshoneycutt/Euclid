"""Evaluation modes mirrored from the native semantic protocol."""
@enum EvaluationMode::Int32 begin
    EvaluationNormal = 0
    EvaluationHelp = 1
    EvaluationPkg = 2
end

"""One correlated request delivered to the evaluator actor."""
struct EvaluationRequested
    request_id::UInt64
    session_generation::UInt64
    source::String
    mode::EvaluationMode
end

"""Internal actor message requesting one bounded stream poll."""
struct PollEvaluation end

const EVALUATION_OUTPUT_BATCH_MAX_BYTES = 8 * 1024
const EVALUATION_OUTPUT_MAX_RETAINED_BYTES = 64 * 1024

"""One bounded correlated output batch for the native host."""
struct TerminalOutputBatch
    request_id::UInt64
    text::String
    byte_count::Int
    truncated_bytes::UInt64
end

"""Terminal command for one completed evaluation request."""
struct EvaluationCompleted
    request_id::UInt64
end

"""Terminal command reporting an incomplete input request."""
struct EvaluationIncomplete
    request_id::UInt64
end

"""Command reporting that one correlated evaluation requested session exit."""
struct EvaluationExitRequested
    request_id::UInt64
    session_generation::UInt64
end

"""Command granting terminal input ownership to one active evaluation."""
struct TerminalInputAcquired
    request_id::UInt64
end

"""Command releasing terminal input ownership from one active evaluation."""
struct TerminalInputReleased
    request_id::UInt64
end

"""Actor owning the sole persistent evaluation session and active stream."""
mutable struct Evaluator
    runtime::EuclidReplEvaluation.EvaluationRuntime
    active_request::Union{Nothing,UInt64}
    pending_output::Vector{UInt8}
    retained_request_bytes::Int
    truncated_request_bytes::UInt64
    outstanding_output_bytes::Int
    output_queue_high_water::Int
    emitted_output_bytes::UInt64
    truncated_output_bytes::UInt64
    discard_output::Bool
end

"""Create an idle evaluator with exactly one persistent REPL session."""
Evaluator() = Evaluator(
    create_eval_runtime(), nothing, UInt8[], 0, UInt64(0), 0, 0,
    UInt64(0), UInt64(0), false)

"""Create an idle evaluator over one explicitly owned evaluation runtime."""
Evaluator(runtime::EuclidReplEvaluation.EvaluationRuntime) = Evaluator(
    runtime, nothing, UInt8[], 0, UInt64(0), 0, 0,
    UInt64(0), UInt64(0), false)

"""Return the actor-runtime correlation key for one evaluation request ID."""
evaluation_request_key(request_id::UInt64) = (:evaluation, request_id)

"""Reset output accounting that is scoped to one evaluation request."""
function reset_evaluation_output!(evaluator::Evaluator)::Nothing
    empty!(evaluator.pending_output)
    evaluator.retained_request_bytes = 0
    evaluator.truncated_request_bytes = 0
    evaluator.discard_output = false
    return nothing
end

"""Emit one batch and update bounded output diagnostics."""
function record_output_batch!(
    evaluator::Evaluator, runtime::EuclidActorRuntime.ActorRuntime,
    batch::TerminalOutputBatch)::Nothing
    EuclidActorRuntime.emit!(runtime, batch)
    evaluator.outstanding_output_bytes += batch.byte_count
    evaluator.emitted_output_bytes += UInt64(batch.byte_count)
    depth = count(command -> command isa TerminalOutputBatch, runtime.outgoing)
    evaluator.output_queue_high_water = max(
        evaluator.output_queue_high_water, depth)
    return nothing
end

"""Emit the pending bounded batch and optionally report request truncation."""
function flush_evaluation_output!(
    evaluator::Evaluator, runtime::EuclidActorRuntime.ActorRuntime,
    request_id::UInt64; include_truncation::Bool=false)::Nothing
    truncated = include_truncation ? evaluator.truncated_request_bytes : UInt64(0)
    isempty(evaluator.pending_output) && truncated == 0 && return nothing
    text = String(copy(evaluator.pending_output))
    batch = TerminalOutputBatch(
        request_id, text, length(evaluator.pending_output), truncated)
    empty!(evaluator.pending_output)
    include_truncation && (evaluator.truncated_request_bytes = 0)
    record_output_batch!(evaluator, runtime, batch)
    return nothing
end

"""Return a valid UTF-8 prefix no larger than the requested byte count."""
function utf8_prefix_bytes(text::String, maximum_bytes::Int)::Int
    retained = min(ncodeunits(text), maximum_bytes)
    while retained > 0 && retained < ncodeunits(text) &&
        !isvalid(String, @view(codeunits(text)[1:retained]))
        retained -= 1
    end
    return retained
end

"""Retain one UTF-8 fragment within per-batch and per-request byte limits."""
function retain_output_fragment!(
    evaluator::Evaluator, runtime::EuclidActorRuntime.ActorRuntime,
    request_id::UInt64, fragment::String)::Nothing
    fragment_bytes = ncodeunits(fragment)
    globally_available = EVALUATION_OUTPUT_MAX_RETAINED_BYTES -
        evaluator.outstanding_output_bytes - length(evaluator.pending_output)
    if evaluator.discard_output ||
        evaluator.retained_request_bytes >= EVALUATION_OUTPUT_MAX_RETAINED_BYTES ||
        globally_available <= 0
        evaluator.truncated_request_bytes += UInt64(fragment_bytes)
        evaluator.truncated_output_bytes += UInt64(fragment_bytes)
        return nothing
    end
    if length(evaluator.pending_output) + fragment_bytes >
        EVALUATION_OUTPUT_BATCH_MAX_BYTES
        flush_evaluation_output!(evaluator, runtime, request_id)
    end
    maximum = EVALUATION_OUTPUT_MAX_RETAINED_BYTES -
        evaluator.retained_request_bytes
    maximum = min(maximum, globally_available)
    retained = utf8_prefix_bytes(fragment, maximum)
    append!(evaluator.pending_output, @view(codeunits(fragment)[1:retained]))
    evaluator.retained_request_bytes += retained
    truncated = fragment_bytes - retained
    evaluator.truncated_request_bytes += UInt64(truncated)
    evaluator.truncated_output_bytes += UInt64(truncated)
    return nothing
end

"""Emit a visible terminal failure for an evaluation request."""
function fail_evaluation!(
    evaluator::Evaluator, context::EuclidActorRuntime.ActorContext,
    request_id::UInt64, message::AbstractString)::Nothing
    EuclidActorRuntime.resolve_request!(
        context.runtime, evaluation_request_key(request_id))
    text = String(message)
    record_output_batch!(evaluator, context.runtime,
        TerminalOutputBatch(request_id, text, ncodeunits(text), UInt64(0)))
    EuclidActorRuntime.emit!(context, EvaluationCompleted(request_id))
    return nothing
end

"""Start one request through the pure evaluator mechanics selected by its mode."""
function begin_evaluation!(
    evaluator::Evaluator, request::EvaluationRequested)::Cint
    if request.mode === EvaluationHelp
        return begin_help_for_host(evaluator.runtime, request.source)
    elseif request.mode === EvaluationPkg
        return begin_pkg_for_host(evaluator.runtime, request.source)
    end
    return begin_input_for_host(evaluator.runtime, request.source)
end

"""Schedule the evaluator's next bounded poll or terminate on scheduler failure."""
function schedule_evaluation_poll!(
    evaluator::Evaluator,
    context::EuclidActorRuntime.ActorContext)::Nothing
    outcome = EuclidActorRuntime.send!(
        context, context.self, PollEvaluation())
    if outcome !== EuclidActorRuntime.SendAccepted
        request_id = evaluator.active_request
        evaluator.active_request = nothing
        request_id === nothing || fail_evaluation!(
            evaluator, context, request_id,
            "internal evaluation scheduling error")
    end
    return nothing
end

"""Translate pending adapter transitions into correlated host commands."""
function emit_interactive_events!(
    evaluator::Evaluator, context::EuclidActorRuntime.ActorContext,
    request_id::UInt64)::Nothing
    while true
        event = EuclidReplEvaluation.take_interactive_event!(
            evaluator.runtime.terminal)
        event === nothing && return nothing
        command = event.kind === EuclidReplEvaluation.InteractiveAcquired ?
            TerminalInputAcquired(request_id) : TerminalInputReleased(request_id)
        EuclidActorRuntime.emit!(context, command)
    end
end

"""Emit terminal commands for an evaluation that completed during startup."""
function complete_immediate_evaluation!(
    context::EuclidActorRuntime.ActorContext,
    request::EvaluationRequested, status::Cint)::Bool
    request_id = request.request_id
    if status == Cint(EuclidReplEvaluation.Evaluation_Incomplete)
        EuclidActorRuntime.resolve_request!(
            context.runtime, evaluation_request_key(request_id))
        EuclidActorRuntime.emit!(
            context, EvaluationIncomplete(request_id))
        return true
    elseif status == Cint(EuclidReplEvaluation.Evaluation_Exit)
        EuclidActorRuntime.resolve_request!(
            context.runtime, evaluation_request_key(request_id))
        EuclidActorRuntime.emit!(context,
            EvaluationExitRequested(request_id, request.session_generation))
        EuclidActorRuntime.emit!(context, EvaluationCompleted(request_id))
        return true
    end
    return false
end

"""Begin one correlated evaluation while enforcing one active stream."""
function EuclidActorRuntime.receive!(
    evaluator::Evaluator,
    context::EuclidActorRuntime.ActorContext,
    request::EvaluationRequested)::Nothing
    pending = get(
        context.runtime.pending_requests,
        evaluation_request_key(request.request_id), nothing)
    if pending === nothing || pending.owner != context.self
        return nothing
    end
    if evaluator.active_request !== nothing
        fail_evaluation!(
            evaluator, context, request.request_id,
            "evaluation already in progress")
        return nothing
    end
    reset_evaluation_output!(evaluator)
    status = try
        begin_evaluation!(evaluator, request)
    catch error
        error isa InterruptException && rethrow()
        fail_evaluation!(
            evaluator, context, request.request_id,
            "internal evaluation error")
        return nothing
    end
    if complete_immediate_evaluation!(context, request, status)
        return nothing
    end
    evaluator.active_request = request.request_id
    schedule_evaluation_poll!(evaluator, context)
    return nothing
end

"""Advance one active evaluation stream by at most one poll result."""
function EuclidActorRuntime.receive!(
    evaluator::Evaluator,
    context::EuclidActorRuntime.ActorContext,
    _message::PollEvaluation)::Nothing
    request_id = evaluator.active_request
    request_id === nothing && return nothing
    poll = try
        poll_evaluation(evaluator.runtime)
    catch error
        error isa InterruptException && rethrow()
        evaluator.active_request = nothing
        fail_evaluation!(
            evaluator, context, request_id, "internal evaluation error")
        return nothing
    end
    emit_interactive_events!(evaluator, context, request_id)
    if poll.status == Int32(1)
        retain_output_fragment!(
            evaluator, context.runtime, request_id, poll.chunk)
        if length(evaluator.pending_output) >= EVALUATION_OUTPUT_BATCH_MAX_BYTES
            flush_evaluation_output!(evaluator, context.runtime, request_id)
        end
    elseif poll.status == Int32(2)
        flush_evaluation_output!(
            evaluator, context.runtime, request_id; include_truncation=true)
        evaluator.active_request = nothing
        EuclidActorRuntime.resolve_request!(
            context.runtime, evaluation_request_key(request_id))
        EuclidActorRuntime.emit!(
            context, EvaluationCompleted(request_id))
        evaluator.discard_output && EuclidActorRuntime.stop!(context)
        return nothing
    elseif !isempty(evaluator.pending_output)
        flush_evaluation_output!(evaluator, context.runtime, request_id)
    end
    schedule_evaluation_poll!(evaluator, context)
    return nothing
end
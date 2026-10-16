"""Primitive-only native run layout, mirrored and layout-tested in Odin."""
struct NativeHighlightRun
    start_byte::UInt32
    end_byte::UInt32
    foreground::UInt32
    background::UInt32
    underline_color::UInt32
    foreground_kind::UInt8
    background_kind::UInt8
    underline_color_kind::UInt8
    weight::UInt8
    italic::UInt8
    underline::UInt8
    strikethrough::UInt8
    inverse::UInt8
end

"""Convert one validated adapter run into a pointer-free native record."""
function NativeHighlightRun(run::EuclidReplEvaluation.SyntaxHighlighting.HighlightRun)
    style = run.style
    return NativeHighlightRun(
        run.start_byte, run.end_byte, style.foreground.value, style.background.value,
        style.underline_color.value, UInt8(style.foreground.kind),
        UInt8(style.background.kind), UInt8(style.underline_color.kind),
        UInt8(style.weight), UInt8(style.italic), UInt8(style.underline),
        UInt8(style.strikethrough), UInt8(style.inverse))
end

"""One optional native command: 0 absent, 1 complete result, or 2 terminal failure."""
struct HostHighlightCommand
    kind::Int32
    identity::HighlightIdentity
    source::String
    source_byte_count::Int32
    runs::Vector{NativeHighlightRun}
    failure_reason::Int32
end

"""Emit an explicit correlated failure and repository-standard host diagnostic."""
function fail_highlight!(
    runtime::HostRuntime, identity::HighlightIdentity,
    reason::HighlightFailureReason)::Nothing
    @host_log(runtime, Logging.Warn, "highlight rejected",
        request_id=identity.request_id, reason=string(reason))
    EuclidActorRuntime.emit!(runtime.actors, HighlightFailed(identity, reason))
    return nothing
end

"""Admit one bounded generation-scoped request without coupling it to completion."""
function ingest_highlight_for_host(
    runtime::HostRuntime, identity::HighlightIdentity, source::String)::Nothing
    request = HighlightRequested(identity, source)
    if runtime.shutdown_requested || runtime.session.phase !== HostSessionActive ||
        identity.session_generation != runtime.session.generation
        return fail_highlight!(runtime, identity, HighlightRuntimeStopped)
    elseif !valid_highlight_request(request)
        return fail_highlight!(runtime, identity, HighlightInvalidRequest)
    end
    key = highlight_request_key(identity)
    registration = EuclidActorRuntime.register_request!(
        runtime.actors, key, runtime.highlight_service; value=request)
    if registration !== EuclidActorRuntime.RequestRegistered
        reason = registration === EuclidActorRuntime.RequestDuplicate ?
            HighlightDuplicateRequest : HighlightActorStopped
        return fail_highlight!(runtime, identity, reason)
    end
    outcome = EuclidActorRuntime.send!(runtime.actors, runtime.highlight_service, request)
    if outcome !== EuclidActorRuntime.SendAccepted
        EuclidActorRuntime.resolve_request!(runtime.actors, key)
        reason = outcome === EuclidActorRuntime.SendMailboxFull ?
            HighlightMailboxFull : HighlightActorStopped
        fail_highlight!(runtime, identity, reason)
    end
    return nothing
end

"""Take one complete result/failure while preserving the request's original generation."""
function take_highlight_for_host(runtime::HostRuntime)::HostHighlightCommand
    command = take_outgoing_command!(runtime, Union{HighlightResolved,HighlightFailed})
    if command === nothing
        identity = HighlightIdentity(0, 0, 0, 0, 0, 0, 0)
        return HostHighlightCommand(0, identity, "", 0, NativeHighlightRun[], 0)
    elseif command isa HighlightFailed
        return HostHighlightCommand(
            2, command.identity, "", 0, NativeHighlightRun[], Int32(command.reason))
    end
    return HostHighlightCommand(
        1, command.identity, command.source, Int32(ncodeunits(command.source)),
        NativeHighlightRun.(command.runs), 0)
end

const HighlightAdapter = EuclidReplEvaluation.SyntaxHighlighting
const HIGHLIGHT_MAILBOX_CAPACITY = 8

"""Exact source/cache identity; target 0 is live, 1 session history, and 2 saved history."""
struct HighlightIdentity
    request_id::UInt64
    session_generation::UInt64
    target_id::UInt64
    source_revision::UInt64
    face_generation::UInt64
    target_kind::Int32
    mode::Int32
end

"""One immutable Julia source snapshot submitted independently of completion."""
struct HighlightRequested
    identity::HighlightIdentity
    source::String
end

"""One complete source-correlated result; the receiver owns no Julia face objects."""
struct HighlightResolved
    identity::HighlightIdentity
    source::String
    runs::Vector{HighlightAdapter.HighlightRun}
end

"""Stable terminal rejection reasons mirrored by the native protocol."""
@enum HighlightFailureReason::Int32 begin
    HighlightMailboxFull = 1
    HighlightActorStopped
    HighlightRuntimeStopped
    HighlightInternalFailure
    HighlightDuplicateRequest
    HighlightInvalidRequest
end

"""One terminal failure preserving every supplied identity field."""
struct HighlightFailed
    identity::HighlightIdentity
    reason::HighlightFailureReason
end

"""Session-owned highlighting mechanic, injectable for bounded failure tests."""
struct HighlightService{F}
    highlight::F
end

"""Generation-scoped correlation key in a namespace separate from other services."""
struct HighlightRequestKey
    generation::UInt64
    request_id::UInt64
end

"""Namespace highlighting correlation separately from completion and evaluation."""
highlight_request_key(identity::HighlightIdentity) =
    HighlightRequestKey(identity.session_generation, identity.request_id)

"""Check whether an identity selects live input or one scoped history source."""
function valid_highlight_target(id::HighlightIdentity)::Bool
    return (id.target_kind == 0 && id.target_id == 0) ||
        ((id.target_kind == 1 || id.target_kind == 2) && id.target_id > 0)
end

"""Check request identity, Normal mode, and source bounds before mailbox admission."""
function valid_highlight_request(request::HighlightRequested)::Bool
    id = request.identity
    return id.request_id > 0 && id.session_generation > 0 &&
        id.source_revision > 0 && id.face_generation > 0 && id.mode == 0 &&
        valid_highlight_target(id) && isvalid(request.source) &&
        ncodeunits(request.source) <= HighlightAdapter.MAX_SOURCE_BYTES
end

"""Check the complete native appearance vocabulary before constructing a success result."""
function highlight_style_valid(style::HighlightAdapter.HighlightStyle)::Bool
    UInt8(style.weight) <= UInt8(HighlightAdapter.DimWeight) || return false
    UInt8(style.underline) <= UInt8(HighlightAdapter.DashedUnderline) || return false
    for color in (style.foreground, style.background, style.underline_color)
        UInt8(color.kind) <= UInt8(HighlightAdapter.RgbColor) || return false
        limit = color.kind == HighlightAdapter.DefaultColor ? 0 :
            color.kind == HighlightAdapter.AnsiColor ? 15 : 0xffffff
        color.value <= limit || return false
    end
    return true
end

"""Reject malformed adapter output atomically before it becomes a successful command."""
function validate_highlight_result(source::String, runs)
    runs isa Vector{HighlightAdapter.HighlightRun} ||
        throw(ArgumentError("highlight adapter returned an invalid run vector"))
    length(runs) <= HighlightAdapter.MAX_STYLE_RUNS ||
        throw(ArgumentError("highlight adapter exceeded run capacity"))
    offset = UInt32(0)
    for run in runs
        run.start_byte == offset && offset < run.end_byte <= ncodeunits(source) ||
            throw(ArgumentError("highlight adapter returned invalid coverage"))
        (run.end_byte == ncodeunits(source) ||
         isvalid(source, Int(run.end_byte) + 1)) ||
            throw(ArgumentError("highlight adapter split UTF-8"))
        highlight_style_valid(run.style) ||
            throw(ArgumentError("highlight adapter returned an invalid style"))
        offset = run.end_byte
    end
    offset == ncodeunits(source) ||
        throw(ArgumentError("highlight adapter returned incomplete coverage"))
    return nothing
end

"""Resolve a still-owned request exactly once, translating adapter errors into failure."""
function EuclidActorRuntime.receive!(
    service::HighlightService, context::EuclidActorRuntime.ActorContext,
    request::HighlightRequested)::Nothing
    key = highlight_request_key(request.identity)
    pending = get(context.runtime.pending_requests, key, nothing)
    (pending === nothing || pending.owner != context.self) && return nothing
    command = try
        runs = service.highlight(request.source)
        validate_highlight_result(request.source, runs)
        HighlightResolved(request.identity, request.source, runs)
    catch error
        error isa InterruptException && rethrow()
        HighlightFailed(request.identity, HighlightInternalFailure)
    end
    EuclidActorRuntime.resolve_request!(context.runtime, key)
    EuclidActorRuntime.emit!(context, command)
    return nothing
end

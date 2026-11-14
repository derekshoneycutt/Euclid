"""C-compatible copy-out row; byte arrays are owned by the querying Julia task."""
struct ExerciseQueryRowABI
    identity::NTuple{36,UInt8}
    animation_id::NTuple{36,UInt8}
    reference::NTuple{16,UInt8}
    title::NTuple{256,UInt8}
    node_kind::UInt32
end

"""C-compatible completion metadata for a bounded exercise query."""
struct ExerciseQueryMetadataABI
    status::UInt32
    count::UInt32
    total::UInt32
    more::UInt32
    text_count::UInt32
end

"""Completed bounded query data copied out of native operation storage."""
struct ExerciseQueryReply
    metadata::ExerciseQueryMetadataABI
    rows::Vector{ExerciseQueryRowABI}
    text::String
end

"""Borrowed admission arguments matching the native query input layout."""
struct ExerciseQueryInputABI
    source::Ptr{UInt8}
    byte_count::UInt32
    kind::UInt32
    offset::UInt32
    limit::UInt16
    load::Bool
end

"""Bounded task-owned copy-out destinations borrowed during a native poll."""
struct ExerciseQueryBuffersABI
    rows::Ptr{ExerciseQueryRowABI}
    text::Ptr{UInt8}
    row_capacity::UInt32
    text_capacity::UInt32
end

"""One stored exercise identity and its associated animation, without instruction text."""
struct ExerciseSummary
    id::UUID
    animation_id::UUID
    reference::String
    title::String
    animation_available::Bool
end

"""Preserve the four-field constructor used by built-in exercise summaries."""
ExerciseSummary(id::UUID, animation_id::UUID, reference::String, title::String) =
    ExerciseSummary(id, animation_id, reference, title, true)

"""One actual animation catalogue child, not an exercise-specific folder."""
struct ExerciseCatalogueNode
    id::UUID
    title::String
end

"""One bounded result window; an empty page is successful and distinct from failure."""
struct ExercisePage{T}
    entries::Vector{T}
    offset::Int
    total::Int
    more::Bool
end

"""Explicit completion failure from the native exercise owner."""
struct ExerciseQueryError <: Exception
    reason::Symbol
end

"""Display the useful title and copyable friendly reference, never an implementation dump."""
function Base.show(io::IO, summary::ExerciseSummary)
    print(io, summary.title, " (", summary.reference, ")")
    summary.animation_available || print(io, " [animation unavailable]")
end

"""Use the same readable exercise description in the standard Julia REPL display."""
Base.show(io::IO, ::MIME"text/plain", summary::ExerciseSummary) = show(io, summary)

"""Display catalogue entries by name rather than UUID-containing constructor syntax."""
Base.show(io::IO, node::ExerciseCatalogueNode) = print(io, node.title)

"""Use catalogue names in standard Julia REPL output."""
Base.show(io::IO, ::MIME"text/plain", node::ExerciseCatalogueNode) = show(io, node)

"""Summarize bounded pages readably in nested Julia values."""
function Base.show(io::IO, page::ExercisePage)
    print(io, length(page.entries), " of ", page.total, " entries")
end

"""Show names, usable references, paging, and empty states through Julia's REPL protocol."""
function Base.show(io::IO, ::MIME"text/plain", page::ExercisePage{T}) where {T}
    heading = T === ExerciseSummary ? "Exercises" : "Animation catalogue"
    println(io, heading)
    if isempty(page.entries)
        print(io, page.total == 0 ? "  No entries found." : "  No entries on this page.")
    else
        for (index, entry) in enumerate(page.entries)
            print(io, "\n  ", page.offset + index, ". ")
            show(io, entry)
        end
        print(io, "\n\nShowing ", page.offset + 1, "-",
            page.offset + length(page.entries), " of ", page.total, ".")
    end
    page.more &&
        print(io, " Next page: use offset=", page.offset + length(page.entries), ".")
    print(io, "\nUse choose_exercise() to browse and select interactively.")
end

"""Explain distinct stored-exercise lookup and lifecycle failures to the REPL."""
function Base.showerror(io::IO, failure::ExerciseQueryError)
    print(io, "exercise query failed: ", failure.reason)
end

"""Validate the public namespaced alias or UUID syntax without title-based lookup."""
function parse_exercise_reference(reference::AbstractString)
    value = String(reference)
    startswith(value, "builtin:") ||
        throw(ArgumentError("exercise references must use the builtin: namespace"))
    identity = value[9:end]
    if occursin(r"^[a-z0-9_-]{1,16}$", identity)
        return UInt32(1), identity
    end
    canonical_exercise_uuid(identity)
    return UInt32(2), identity
end

"""Require a canonical, lowercase, nonzero catalogue or exercise UUID."""
function canonical_exercise_uuid(value)::String
    text = string(value)
    occursin(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", text) ||
        throw(ArgumentError("expected a canonical lowercase UUID"))
    UUID(text) != UUID(UInt128(0)) || throw(ArgumentError("UUID must be nonzero"))
    return text
end

"""Convert one bounded zero-padded ABI field to owned Julia text."""
function exercise_query_text(bytes)::String
    stop = findfirst(iszero, bytes)
    count = isnothing(stop) ? length(bytes) : stop - 1
    return String(UInt8[bytes[index] for index in 1:count])
end

"""Convert one native row into an exercise summary with an explicit namespace."""
function exercise_query_summary(row::ExerciseQueryRowABI)::ExerciseSummary
    return ExerciseSummary(UUID(exercise_query_text(row.identity)),
        UUID(exercise_query_text(row.animation_id)),
        "builtin:" * exercise_query_text(row.reference), exercise_query_text(row.title), true)
end

"""Reject bad paging locally before reserving native operation storage."""
function validate_exercise_page(offset::Integer, limit::Integer)
    0 <= offset <= typemax(Int32) ||
        throw(ArgumentError("offset must fit a nonnegative Int32"))
    1 <= limit <= 16 || throw(ArgumentError("limit must be between 1 and 16"))
    return UInt32(offset), UInt16(limit)
end

"""Await display-owned completion cooperatively, releasing the slot on interruption."""
function query_exercises(
    state_ptr::Ptr{Cvoid}, kind::UInt32, value::String;
    load::Bool=false, offset::Integer=0, limit::Integer=0)
    token = Ref{UInt64}(0)
    status = GC.@preserve value begin
        input = Ref(ExerciseQueryInputABI(pointer(value), UInt32(ncodeunits(value)),
            kind, UInt32(offset), UInt16(limit), load))
        @ccall begin_exercise_query(
            state_ptr::Ptr{Cvoid}, input::Ref{ExerciseQueryInputABI},
            token::Ref{UInt64})::Int32
    end
    status == BRIDGE_STATUS_OK ||
        throw(ExerciseQueryError(status == BRIDGE_STATUS_ILLEGAL_STATE ?
            :busy_or_inactive : :admission_failed))
    try
        return await_exercise_query(state_ptr, token[])
    finally
        @ccall cancel_exercise_query(state_ptr::Ptr{Cvoid}, token[]::UInt64)::Cvoid
    end
end

"""Poll only the correlated operation into bounded task-owned result storage."""
function await_exercise_query(state_ptr::Ptr{Cvoid}, token::UInt64)
    metadata = Ref{ExerciseQueryMetadataABI}()
    rows = Vector{ExerciseQueryRowABI}(undef, 16)
    text = Vector{UInt8}(undef, EXERCISE_HEADER_MAX_TEXT_BYTES)
    deadline = time_ns() + UInt64(30_000_000_000)
    while true
        status = GC.@preserve rows text begin
            buffers = Ref(ExerciseQueryBuffersABI(pointer(rows), pointer(text),
                UInt32(length(rows)), UInt32(length(text))))
            @ccall poll_exercise_query(
                state_ptr::Ptr{Cvoid}, token::UInt64,
                metadata::Ref{ExerciseQueryMetadataABI},
                buffers::Ref{ExerciseQueryBuffersABI})::Int32
        end
        if status == BRIDGE_STATUS_OK
            check_exercise_query_status(metadata[].status)
            resize!(rows, Int(metadata[].count))
            resize!(text, Int(metadata[].text_count))
            return ExerciseQueryReply(metadata[], rows, String(text))
        end
        status == -1 || throw(ExerciseQueryError(:superseded))
        time_ns() < deadline || throw(ExerciseQueryError(:timeout))
        sleep(0.001)
    end
end

"""Keep absence, retirement, unavailable association, and database failure distinct."""
function check_exercise_query_status(status::UInt32)
    status == 1 && return nothing
    reasons = (:unavailable, :ready, :invalid_request, :not_found, :retired,
        :database_failed, :missing_animation, :superseded)
    index = Int(status) + 1
    reason = 1 <= index <= length(reasons) ? reasons[index] : :invalid_native_status
    throw(ExerciseQueryError(reason))
end

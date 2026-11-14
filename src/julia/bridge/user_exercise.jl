"""C-compatible request for one user-store exercise operation."""
struct UserExerciseInputABI
    operation::UInt32
    identity_source::Ptr{UInt8}
    identity_byte_count::UInt32
    animation_source::Ptr{UInt8}
    animation_byte_count::UInt32
    reference_source::Ptr{UInt8}
    reference_byte_count::UInt32
    title_source::Ptr{UInt8}
    title_byte_count::UInt32
    instructions_source::Ptr{UInt8}
    instructions_byte_count::UInt32
    result_offset::UInt32
    page_limit::UInt16
    load::Bool
end

"""Typed failure from one explicit user exercise namespace operation."""
struct UserExerciseError <: Exception
    reason::Symbol
end

const USER_EXERCISE_CREATE = UInt32(1)
const USER_EXERCISE_LIST = UInt32(2)
const USER_EXERCISE_READ_IDENTITY = UInt32(3)
const USER_EXERCISE_READ_REFERENCE = UInt32(4)
const USER_EXERCISE_UPDATE = UInt32(5)
const USER_EXERCISE_DELETE = UInt32(6)

"""Show a concise user exercise persistence failure."""
function Base.showerror(io::IO, failure::UserExerciseError)
    print(io, "user exercise operation failed: ", failure.reason)
end

"""Run one typed request and always release its correlated native result slot."""
function user_exercise_operation(
    state_ptr::Ptr{Cvoid}, operation::UInt32;
    identity::String="", animation_id::String="", reference::String="",
    title::String="", instructions::String="", offset::Integer=0,
    limit::Integer=0, load::Bool=false)
    0 <= offset <= typemax(Int32) ||
        throw(ArgumentError("offset must fit a nonnegative Int32"))
    0 <= limit <= 16 || throw(ArgumentError("limit must be between 0 and 16"))
    input = Ref(UserExerciseInputABI(
        operation, pointer(identity), UInt32(ncodeunits(identity)),
        pointer(animation_id), UInt32(ncodeunits(animation_id)),
        pointer(reference), UInt32(ncodeunits(reference)),
        pointer(title), UInt32(ncodeunits(title)),
        pointer(instructions), UInt32(ncodeunits(instructions)),
        UInt32(offset), UInt16(limit), load))
    token = Ref{UInt64}(0)
    status = GC.@preserve identity animation_id reference title instructions begin
        @ccall begin_user_exercise_operation(
            state_ptr::Ptr{Cvoid}, input::Ref{UserExerciseInputABI},
            token::Ref{UInt64})::Int32
    end
    status == BRIDGE_STATUS_OK ||
        throw(UserExerciseError(status == BRIDGE_STATUS_ILLEGAL_STATE ?
            :busy_or_inactive : :admission_failed))
    try
        return await_user_exercise_operation(state_ptr, token[])
    finally
        @ccall cancel_user_exercise_operation(
            state_ptr::Ptr{Cvoid}, token[]::UInt64)::Cvoid
    end
end

"""Poll only the correlated user operation into bounded Julia-owned storage."""
function await_user_exercise_operation(state_ptr::Ptr{Cvoid}, token::UInt64)
    metadata = Ref{ExerciseQueryMetadataABI}()
    rows = Vector{ExerciseQueryRowABI}(undef, 16)
    text = Vector{UInt8}(undef, EXERCISE_HEADER_MAX_TEXT_BYTES)
    deadline = time_ns() + UInt64(30_000_000_000)
    while true
        status = GC.@preserve rows text begin
            buffers = Ref(ExerciseQueryBuffersABI(pointer(rows), pointer(text),
                UInt32(length(rows)), UInt32(length(text))))
            @ccall poll_user_exercise_operation(
                state_ptr::Ptr{Cvoid}, token::UInt64,
                metadata::Ref{ExerciseQueryMetadataABI},
                buffers::Ref{ExerciseQueryBuffersABI})::Int32
        end
        if status == BRIDGE_STATUS_OK
            check_user_exercise_status(metadata[].status)
            resize!(rows, Int(metadata[].count))
            resize!(text, Int(metadata[].text_count))
            return ExerciseQueryReply(metadata[], rows, String(text))
        end
        status == -1 || throw(UserExerciseError(:superseded))
        time_ns() < deadline || throw(UserExerciseError(:timeout))
        sleep(0.001)
    end
end

"""Keep busy, retired, collision, and missing-animation outcomes distinct."""
function check_user_exercise_status(status::UInt32)
    status == 1 && return nothing
    reasons = (:unavailable, :ready, :invalid_request, :not_found, :retired,
        :database_failed, :missing_animation, :busy, :reference_collision,
        :identity_collision, :read_only, :superseded)
    index = Int(status) + 1
    reason = 1 <= index <= length(reasons) ? reasons[index] : :invalid_native_status
    throw(UserExerciseError(reason))
end

"""Convert one bounded native row to an explicitly namespaced user summary."""
function user_exercise_query_summary(row::ExerciseQueryRowABI)::ExerciseSummary
    return ExerciseSummary(UUID(exercise_query_text(row.identity)),
        UUID(exercise_query_text(row.animation_id)),
        "user:" * exercise_query_text(row.reference),
        exercise_query_text(row.title), row.node_kind != 0)
end

"""Identify a required explicit namespace without resolving by title."""
function exercise_reference_namespace(reference::AbstractString)::Symbol
    startswith(reference, "builtin:") && return :builtin
    startswith(reference, "user:") && return :user
    throw(ArgumentError("exercise references must use builtin: or user:"))
end

"""Parse an exact user alias or canonical UUID into its worker operation."""
function parse_user_exercise_reference(reference::AbstractString)
    startswith(reference, "user:") ||
        throw(ArgumentError("user exercise references must use the user: namespace"))
    identity = String(reference[6:end])
    if occursin(r"^[a-z0-9_-]{1,16}$", identity)
        return USER_EXERCISE_READ_REFERENCE, identity
    end
    return USER_EXERCISE_READ_IDENTITY, canonical_exercise_uuid(identity)
end

"""Validate the exact stored byte bounds before user-write admission."""
function validate_user_exercise_draft(
    reference::AbstractString, title::AbstractString, instructions::AbstractString)
    alias = String(reference)
    occursin(r"^[a-z0-9_-]{1,16}$", alias) ||
        throw(ArgumentError("user exercise aliases use 1-16 lowercase ASCII characters"))
    value = String(title)
    0 < ncodeunits(value) <= 256 &&
        !isempty(strip(value)) && !occursin('\0', value) ||
        throw(ArgumentError(
            "user exercise titles must be nonblank and at most 256 bytes"))
    text = String(instructions)
    0 < ncodeunits(text) <= EXERCISE_HEADER_MAX_TEXT_BYTES &&
        !isempty(strip(text)) && !occursin('\0', text) ||
        throw(ArgumentError(
            "instructions must be nonblank and within the exercise limit"))
    return alias
end

"""Resolve one user record into a namespaced summary, optionally loading its snapshot."""
function user_exercise_summary(
    state_ptr::Ptr{Cvoid}, operation::UInt32, identity::String; load::Bool)
    reply = if operation == USER_EXERCISE_READ_REFERENCE
        user_exercise_operation(
            state_ptr, operation; reference=identity, load=load)
    else
        user_exercise_operation(
            state_ptr, operation; identity=identity, load=load)
    end
    return user_exercise_query_summary(only(reply.rows))
end

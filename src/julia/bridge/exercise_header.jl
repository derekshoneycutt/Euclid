const EXERCISE_HEADER_MAX_TEXT_BYTES = 32 * 1024

"""Return validated, nonblank plain UTF-8 exercise instructions."""
function validate_exercise_header_text(text::AbstractString)::String
    value = String(text)
    isvalid(value) || throw(ArgumentError("exercise instructions must be valid UTF-8"))
    ncodeunits(value) <= EXERCISE_HEADER_MAX_TEXT_BYTES ||
        throw(ArgumentError("exercise instructions exceed 32 KiB"))
    isempty(strip(value)) && throw(ArgumentError("exercise instructions cannot be blank"))
    occursin('\0', value) &&
        throw(ArgumentError("exercise instructions cannot contain NUL"))
    return value
end

"""Enqueue validated instructions for the display-owned exercise header."""
function publish_exercise_header(state_ptr::Ptr{Cvoid}, text::AbstractString)
    value = validate_exercise_header_text(text)
    byte_count = ncodeunits(value)
    status = GC.@preserve value begin
        @ccall publish_exercise_header(
            state_ptr::Ptr{Cvoid},
            pointer(value)::Ptr{UInt8},
            Int32(byte_count)::Int32)::Int32
    end
    status == BRIDGE_STATUS_OK ||
        error("publish_exercise_header failed with bridge status $status")
    return status
end

"""Enqueue the shared dismissal operation for the display-owned exercise header."""
function hide_exercise_header(state_ptr::Ptr{Cvoid})
    status = @ccall hide_exercise_header(state_ptr::Ptr{Cvoid})::Int32
    status == BRIDGE_STATUS_OK ||
        error("hide_exercise_header failed with bridge status $status")
    return status
end

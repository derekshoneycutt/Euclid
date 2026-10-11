const ANIMATION_CONTENT_OK = UInt32(0)
const ANIMATION_CONTENT_MISSING_INVOCATION_CONTEXT = UInt32(1)
const ANIMATION_CONTENT_IDENTITY_MISMATCH = UInt32(2)
const ANIMATION_CONTENT_MISSING_DEFAULT = UInt32(3)
const ANIMATION_CONTENT_STALE_GENERATION = UInt32(4)
const ANIMATION_CONTENT_INVALID_OUTPUT = UInt32(5)

"""Pointer-free 440-byte native copy-out layout, with explicit UTF-8 byte lengths."""
struct AnimationContentSpecificationABI
    application_locale::NTuple{35,UInt8}
    application_locale_length::UInt16
    edition_id::NTuple{64,UInt8}
    edition_id_length::UInt16
    edition_name::NTuple{256,UInt8}
    edition_name_length::UInt16
    edition_text_language::NTuple{35,UInt8}
    edition_text_language_length::UInt16
    selection_revision::UInt64
    animation_identity::NTuple{16,UInt8}
    content_generation_identity::UInt64
    runtime_generation_identity::UInt64
end

"""C-compatible identity of the checked native callback requesting a copy."""
struct AnimationContentInvocationABI
    animation_identity::NTuple{16,UInt8}
    runtime_generation::UInt64
    animation_generation::UInt64
    operation::Int32
end

"""Read-only Julia-owned selection facts for one callback, not its published presentation."""
struct AnimationContentSpecification
    application_locale::String
    edition_id::String
    edition_name::String
    edition_text_language::String
    selection_revision::UInt64
    animation_identity::UUID
    content_generation_identity::UInt64
    runtime_generation_identity::UInt64
end

"""Explicit native query failure; a missing context never supplies fabricated defaults."""
struct AnimationContentQueryError <: Exception
    status::UInt32
end

const AnimationContentContext = Base.ScopedValues.ScopedValue{
    Union{Nothing,Tuple{Ptr{Cvoid},AnimationContentSpecification}}}(nothing)

"""Decode a validated fixed UTF-8 field into Julia-owned string storage."""
function animation_content_string(bytes::NTuple{N,UInt8}, length::UInt16) where {N}
    0 < length <= N || throw(AnimationContentQueryError(ANIMATION_CONTENT_INVALID_OUTPUT))
    value = String(UInt8[bytes[index] for index in 1:Int(length)])
    isvalid(value) && !occursin('\0', value) ||
        throw(AnimationContentQueryError(ANIMATION_CONTENT_INVALID_OUTPUT))
    return value
end

"""Decode native UUID bytes in canonical network order without borrowing their storage."""
function animation_content_uuid(bytes::NTuple{16,UInt8})::UUID
    value = zero(UInt128)
    for byte in bytes
        value = (value << 8) | UInt128(byte)
    end
    return UUID(value)
end

"""Construct one ergonomic owned value from a complete native ABI result."""
function AnimationContentSpecification(value::AnimationContentSpecificationABI)
    value.selection_revision > 0 && value.content_generation_identity > 0 ||
        throw(AnimationContentQueryError(ANIMATION_CONTENT_INVALID_OUTPUT))
    return AnimationContentSpecification(
        animation_content_string(
            value.application_locale, value.application_locale_length),
        animation_content_string(value.edition_id, value.edition_id_length),
        animation_content_string(value.edition_name, value.edition_name_length),
        animation_content_string(
            value.edition_text_language, value.edition_text_language_length),
        value.selection_revision, animation_content_uuid(value.animation_identity),
        value.content_generation_identity, value.runtime_generation_identity)
end

"""Read this callback's immutable selection without consuming its revision."""
function animation_content_specification(
    state_ptr::Ptr{Cvoid})::AnimationContentSpecification
    context = AnimationContentContext[]
    context === nothing &&
        throw(AnimationContentQueryError(ANIMATION_CONTENT_MISSING_INVOCATION_CONTEXT))
    context[1] == state_ptr ||
        throw(AnimationContentQueryError(ANIMATION_CONTENT_IDENTITY_MISMATCH))
    return context[2]
end

"""Copy the checked native lifecycle or tick value before entering authored code."""
function copy_animation_content_value(
    state_ptr::Ptr{Cvoid}, animation_id::UUID, runtime_generation::UInt64,
    animation_generation::UInt64, operation::Int32)::AnimationContentSpecification
    identity = ntuple(
        index -> UInt8((animation_id.value >> (8 * (16 - index))) & 0xff), 16)
    invocation = AnimationContentInvocationABI(
        identity, runtime_generation, animation_generation, operation)
    destination = Ref{AnimationContentSpecificationABI}()
    status = GC.@preserve destination begin
        @ccall copy_animation_content_specification(
            state_ptr::Ptr{Cvoid}, invocation::AnimationContentInvocationABI,
            destination::Ref{AnimationContentSpecificationABI})::UInt32
    end
    status == ANIMATION_CONTENT_OK || throw(AnimationContentQueryError(status))
    return AnimationContentSpecification(destination[])
end

"""Bind an owned specification across the latest-world callback, even on error."""
function invoke_animation_content_entry(entry, state_ptr, command)::Bool
    value = copy_animation_content_value(state_ptr, command.animation_id,
        command.runtime_generation, command.animation_generation, command.operation)
    return Base.ScopedValues.with(AnimationContentContext => (state_ptr, value)) do
        Base.invokelatest(entry, state_ptr, command.operation, command.dt)
    end
end

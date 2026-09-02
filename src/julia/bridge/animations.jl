const ANIMATION_OPERATION_ENTER = Int32(1)
const ANIMATION_OPERATION_TICK = Int32(2)
const ANIMATION_OPERATION_EXIT = Int32(3)

"""Typed non-owning identity for one animation value stored by the native host."""
struct AnimationKey{T}
    value::UInt64
end

"""C-compatible animation key and deterministic schema identity."""
struct AnimationValueIdentityABI
    key::UInt64
    schema_low::UInt64
    schema_high::UInt64
end

"""C-compatible animation catalog ordering and node classification."""
struct AnimationDescriptorABIMetadata
    node_kind::Int32
    sibling_order::Int32
end

const ANIMATION_VALUE_MAX_PAYLOAD_BYTES = 16 * 1024
const ANIMATION_SCHEMA_FNV_OFFSET = UInt128(0x6c62272e07bb014262b821756295c58d)
const ANIMATION_SCHEMA_FNV_PRIME = UInt128(0x0000000001000000000000000000013b)

"""Write one unsigned integer in fixed-width little-endian form."""
function _animation_schema_write_uint(io::IO, value::Unsigned, width::Int)
    for shift in 0:8:(width - 1) * 8
        write(io, UInt8((value >> shift) & 0xff))
    end
end

"""Write one UTF-8 string with an unsigned 32-bit byte length prefix."""
function _animation_schema_write_string(io::IO, value::AbstractString)
    bytes = codeunits(value)
    _animation_schema_write_uint(io, UInt32(length(bytes)), 4)
    write(io, bytes)
end

"""Write one deterministic type-parameter description."""
function _animation_schema_write_parameter(io::IO, parameter)
    if parameter isa Type
        write(io, UInt8(1))
        _animation_schema_write_type(io, parameter)
        return
    end
    write(io, UInt8(2))
    _animation_schema_write_type(io, typeof(parameter))
    _animation_schema_write_string(io, sprint(show, parameter; context=:compact => true))
end

"""Write the recursive canonical identity and memory layout of one concrete type."""
function _animation_schema_write_type(io::IO, type::Type)
    type isa DataType || throw(ArgumentError("animation state type must be concrete"))
    write(io, UInt8(1))
    module_path = Base.fullname(parentmodule(type))
    _animation_schema_write_uint(io, UInt32(length(module_path)), 4)
    for component in module_path
        _animation_schema_write_string(io, String(component))
    end
    _animation_schema_write_string(io, String(nameof(type)))
    has_layout = isbitstype(type)
    write(io, UInt8(has_layout))
    _animation_schema_write_uint(io, has_layout ? UInt64(sizeof(type)) : UInt64(0), 8)
    alignment = has_layout ? UInt64(Base.datatype_alignment(type)) : UInt64(0)
    _animation_schema_write_uint(io, alignment, 8)
    _animation_schema_write_uint(io, UInt32(length(type.parameters)), 4)
    for parameter in type.parameters
        _animation_schema_write_parameter(io, parameter)
    end
    names = has_layout ? fieldnames(type) : ()
    _animation_schema_write_uint(io, UInt32(length(names)), 4)
    for (index, name) in pairs(names)
        _animation_schema_write_string(io, string(name))
        _animation_schema_write_uint(io, UInt64(fieldoffset(type, index)), 8)
        _animation_schema_write_type(io, fieldtype(type, index))
    end
end

"""Return the fixed FNV-1a-128 fingerprint of canonical schema bytes."""
function _animation_schema_fingerprint(bytes)::Tuple{UInt64,UInt64}
    fingerprint = ANIMATION_SCHEMA_FNV_OFFSET
    for byte in bytes
        fingerprint = (fingerprint ⊻ UInt128(byte)) * ANIMATION_SCHEMA_FNV_PRIME
    end
    low = UInt64(fingerprint & UInt128(typemax(UInt64)))
    high = UInt64(fingerprint >> 64)
    return low, high
end

"""Return the deterministic 128-bit schema identity for one concrete isbits type."""
function animation_schema_id(::Type{T})::Tuple{UInt64,UInt64} where {T}
    isbitstype(T) || throw(ArgumentError("animation state type must be isbits"))
    io = IOBuffer()
    _animation_schema_write_string(io, "euclid.animation-state.schema.v1")
    _animation_schema_write_type(io, T)
    return _animation_schema_fingerprint(take!(io))
end

"""Preserve one isbits source value while a synchronous consumer reads its pointer."""
function _with_animation_value_source(consume, value::T) where {T}
    source = Ref{T}(value)
    GC.@preserve source begin
        pointer = Base.unsafe_convert(Ptr{Cvoid}, source)
        return consume(pointer)
    end
end

"""Preserve destination storage and return its value only after a successful copy."""
function _with_animation_value_destination(copy_to, ::Type{T}) where {T}
    destination = Ref{T}()
    status = GC.@preserve destination begin
        pointer = Base.unsafe_convert(Ptr{Cvoid}, destination)
        copy_to(pointer)
    end
    return status == BRIDGE_STATUS_OK ? destination[] : nothing, status
end

"""Copy one typed isbits value synchronously into native animation storage."""
function set_animation_value!(
    state_ptr::Ptr{Cvoid}, key::AnimationKey{T}, value::T) where {T}
    isbitstype(T) || return BRIDGE_STATUS_INVALID_ARGUMENT
    byte_count = sizeof(T)
    0 < byte_count <= ANIMATION_VALUE_MAX_PAYLOAD_BYTES ||
        return BRIDGE_STATUS_INVALID_ARGUMENT
    schema_low, schema_high = animation_schema_id(T)
    identity = AnimationValueIdentityABI(key.value, schema_low, schema_high)
    return _with_animation_value_source(value) do source
        @ccall set_animation_value(
            state_ptr::Ptr{Cvoid}, identity::AnimationValueIdentityABI,
            source::Ptr{Cvoid}, Int32(byte_count)::Int32)::Int32
    end
end

"""Copy one typed value from native animation storage into Julia-owned memory."""
function get_animation_value(
    state_ptr::Ptr{Cvoid}, key::AnimationKey{T}) where {T}
    isbitstype(T) || return nothing, BRIDGE_STATUS_INVALID_ARGUMENT
    byte_count = sizeof(T)
    0 < byte_count <= ANIMATION_VALUE_MAX_PAYLOAD_BYTES ||
        return nothing, BRIDGE_STATUS_INVALID_ARGUMENT
    schema_low, schema_high = animation_schema_id(T)
    identity = AnimationValueIdentityABI(key.value, schema_low, schema_high)
    return _with_animation_value_destination(T) do destination
        @ccall get_animation_value(
            state_ptr::Ptr{Cvoid}, identity::AnimationValueIdentityABI,
            destination::Ptr{Cvoid}, Int32(byte_count)::Int32)::Int32
    end
end

"""
Set the null animation for the application

---------

Parameters:

- `state_ptr` : The state of the Euclid application to pass to the API
- `entry` : The module-owned `(state_ptr, operation, dt) -> Bool` lifecycle entry
"""
function set_null_animations(
    state_ptr::Ptr{Cvoid}, entry)

    GC.@preserve entry begin
    @ccall set_null_animations(state_ptr::Ptr{Cvoid},
        entry::Any)::Cvoid
    end
end

"""
Add a new root animation for the application

---------

Parameters:

- `state_ptr` : The state of the Euclid application to pass to the API
- `entry` : The module-owned `(state_ptr, operation, dt) -> Bool` lifecycle entry
- `name` : The name of the animation to show in the tree
- `stable_id` : Canonical UUID string used as stable animation identity

Returns 1 on success and -1 on failure
"""
function add_root_animation_interface(
    state_ptr::Ptr{Cvoid}, entry, name::String,
    stable_id::String)

    GC.@preserve entry begin
        @ccall add_root_animation_interface(
            state_ptr::Ptr{Cvoid}, entry::Any,
            name::Cstring, stable_id::Cstring)::Int64
    end
end

"""
Add a new child animation for the application

---------

Parameters:

- `state_ptr` : The state of the Euclid application to pass to the API
- `entry` : The module-owned `(state_ptr, operation, dt) -> Bool` lifecycle entry
- `name` : The name of the animation to show in the tree
- `stable_id` : Canonical UUID string used as stable animation identity
- `parent_stable_id` : Canonical UUID string of the parent animation node

Returns 1 on success and -1 on failure
"""
function add_child_animation_interface(
    state_ptr::Ptr{Cvoid}, entry, name::String,
    stable_id::String, parent_stable_id::String)

    GC.@preserve entry begin
        @ccall add_child_animation_interface(
            state_ptr::Ptr{Cvoid}, entry::Any,
            name::Cstring, stable_id::Cstring, parent_stable_id::Cstring)::Int64
    end
end

"""Register one validated catalog descriptor without an implementation entry."""
function add_animation_descriptor(
    state_ptr::Ptr{Cvoid}, name::String, stable_id::String,
    parent_stable_id::String, node_kind::Int32, sibling_order::Int32)

    metadata = AnimationDescriptorABIMetadata(node_kind, sibling_order)
    @ccall add_animation_descriptor(
        state_ptr::Ptr{Cvoid}, name::Cstring, stable_id::Cstring,
        parent_stable_id::Cstring, metadata::AnimationDescriptorABIMetadata)::Int64
end

"""Bind one loader-rooted animation entry to an exact host UUID node."""
function bind_animation_entry(
    state_ptr::Ptr{Cvoid}, entry, stable_id::String)

    GC.@preserve entry begin
        @ccall bind_animation_entry(
            state_ptr::Ptr{Cvoid}, entry::Any, stable_id::Cstring)::Int64
    end
end

"""
Notify the native host that the current animation has reached a cycle boundary.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
"""
function notify_animation_cycle_boundary(state_ptr::Ptr{Cvoid})
    @ccall notify_animation_cycle_boundary(state_ptr::Ptr{Cvoid})::Cvoid
end

"""
Get the native bridge version number.

------

Returns: `Int32` bridge API version
"""
function get_bridge_version()
    @ccall get_bridge_version()::Int32
end

"""
Get the native bridge feature flags bitmask.

------

Returns: `Int32` feature flags
"""
function get_bridge_feature_flags()
    @ccall get_bridge_feature_flags()::Int32
end

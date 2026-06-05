using Colors

struct BridgeColor
    r::UInt8
    g::UInt8
    b::UInt8
    a::UInt8
end

function bridge_color(c::Colorant)
    rgba = RGBA(c)
    BridgeColor(
        UInt8(round(Int, rgba.r * 255.0)),
        UInt8(round(Int, rgba.g * 255.0)),
        UInt8(round(Int, rgba.b * 255.0)),
        UInt8(round(Int, rgba.alpha * 255.0))
    )
end
function bridge_color(name::Symbol)
    bridge_color(parse(Colorant, String(name)))
end
function bridge_color(name::AbstractString)
    bridge_color(parse(Colorant, name))
end

function euclid_set_compass_active(state_ptr::Ptr{Cvoid}, active::Integer, c::BridgeColor)
    @ccall set_compass_active(
        state_ptr::Ptr{Cvoid},
        active::Cint,
        c::BridgeColor
    )::Cvoid
end
function euclid_set_compass_active(state_ptr::Ptr{Cvoid}, active::Integer, c::Colorant)
    euclid_set_compass_active(state_ptr, active, bridge_color(c))
end

function euclid_set_compass_active(state_ptr::Ptr{Cvoid}, active::Integer, name::Symbol)
    euclid_set_compass_active(state_ptr, active, bridge_color(name))
end

function euclid_set_compass_active(state_ptr::Ptr{Cvoid}, active::Integer, name::AbstractString)
    euclid_set_compass_active(state_ptr, active, bridge_color(name))
end

function euclid_clear_compass_active(state_ptr::Ptr{Cvoid})
    @ccall clear_compass_active(state_ptr::Ptr{Cvoid})::Cvoid
end

function euclid_lock_compass_joint1(state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, z::Float32)
    pos = (x, y, z)
    @ccall lock_compass_joint1(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
end

function euclid_unlock_compass_joint1(state_ptr::Ptr{Cvoid})
    @ccall unlock_compass_joint1(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
end

function euclid_lock_compass_joint2(state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, z::Float32)
    pos = (x, y, z)
    @ccall lock_compass_joint2(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
end

function euclid_unlock_compass_joint2(state_ptr::Ptr{Cvoid})
    @ccall unlock_compass_joint2(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
end

function euclid_set_animation_meta(state_ptr::Ptr{Cvoid}, pos::Integer, metadata::Float32)
    @ccall set_animation_meta(state_ptr::Ptr{Cvoid}, pos::Cint, metadata::Cfloat)::Cvoid
end

function euclid_get_animation_meta(state_ptr::Ptr{Cvoid}, pos::Integer)
    ret = @ccall get_animation_meta(state_ptr::Ptr{Cvoid}, pos::Cint)::Cfloat
    return Float32(ret)
end

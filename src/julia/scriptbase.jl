using Colors

struct BridgeColor
    r::UInt8
    g::UInt8
    b::UInt8
    a::UInt8
end

struct BridgePointView
    valid::UInt8
    index::Int64

    pointType::Int64
    doDraw::UInt8
    brushSize::Cfloat

    hasPosition::UInt8
    pos::NTuple{3, Cfloat}

    hasColor::UInt8
    color::BridgeColor

    hasActiveColor::UInt8
    activeColor::BridgeColor

    activeChild::Int64
    childCount::Int64
    childPointHead::Int64
    nextChildPoint::Int64
end

struct BridgeShapeLine
    hostId::Int64
    joint1Id::Int64
    joint2Id::Int64
end

struct BridgeShapeCircle
    hostId::Int64
    startId::Int64
    endId::Int64
end

function bridge_color(c::Colorant)
    rgba = RGBA(c)
    BridgeColor(
        UInt8(round(Int, rgba.r * 255.0)),
        UInt8(round(Int, rgba.g * 255.0)),
        UInt8(round(Int, rgba.b * 255.0)),
        UInt8(round(Int, rgba.alpha * 255.0)))
end
function bridge_color(name::Symbol)
    bridge_color(parse(Colorant, String(name)))
end
function bridge_color(name::AbstractString)
    bridge_color(parse(Colorant, name))
end


function euclid_create_new_point(state_ptr::Ptr{Cvoid},
    x::Float32, y::Float32, z::Float32,
    color::BridgeColor, brushSize::Float32)
    pos = (x, y, z)
    return @ccall create_new_point(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat},
        color::BridgeColor, brushSize::Cfloat)::BridgePointView
end
function euclid_create_new_point(state_ptr::Ptr{Cvoid},
    x::Float32, y::Float32, z::Float32,
    color::Colorant, brushSize::Float32)
    euclid_create_new_point(state_ptr, x, y, z, bridge_color(color), brushSize)
end
function euclid_create_new_point(state_ptr::Ptr{Cvoid},
    x::Float32, y::Float32, z::Float32,
    color::Symbol, brushSize::Float32)
    euclid_create_new_point(state_ptr, x, y, z, bridge_color(color), brushSize)
end
function euclid_create_new_point(state_ptr::Ptr{Cvoid},
    x::Float32, y::Float32, z::Float32,
    color::AbstractString, brushSize::Float32)
    euclid_create_new_point(state_ptr, x, y, z, bridge_color(color), brushSize)
end



function euclid_create_new_line(state_ptr::Ptr{Cvoid},
    x1::Float32, y1::Float32, z1::Float32,
    x2::Float32, y2::Float32, z2::Float32,
    color::BridgeColor, brushSize::Float32)
    pos1 = (x1, y1, z1)
    pos2 = (x2, y2, z2)
    return @ccall create_new_line(state_ptr::Ptr{Cvoid}, pos1::NTuple{3, Cfloat},
        pos2::NTuple{3, Cfloat}, color::BridgeColor, brushSize::Cfloat)::BridgeShapeLine
end
function euclid_create_new_line(state_ptr::Ptr{Cvoid},
    x1::Float32, y1::Float32, z1::Float32,
    x2::Float32, y2::Float32, z2::Float32,
    color::Colorant, brushSize::Float32)
    euclid_create_new_line(state_ptr, x1, y1, z1, x2, y2, z2, bridge_color(color), brushSize)
end
function euclid_create_new_line(state_ptr::Ptr{Cvoid},
    x1::Float32, y1::Float32, z1::Float32,
    x2::Float32, y2::Float32, z2::Float32,
    color::Symbol, brushSize::Float32)
    euclid_create_new_line(state_ptr, x1, y1, z1, x2, y2, z2, bridge_color(color), brushSize)
end
function euclid_create_new_line(state_ptr::Ptr{Cvoid},
    x1::Float32, y1::Float32, z1::Float32,
    x2::Float32, y2::Float32, z2::Float32,
    color::AbstractString, brushSize::Float32)
    euclid_create_new_line(state_ptr, x1, y1, z1, x2, y2, z2, bridge_color(color), brushSize)
end



function euclid_create_new_circle(state_ptr::Ptr{Cvoid},
    x::Float32, y::Float32, z::Float32,
    radius::Float32, startθ::Float32, endθ::Float32,
    color::BridgeColor, brushSize::Float32)
    pos = (x, y, z)
    return @ccall create_new_circle(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat},
        radius::Cfloat, startθ::Cfloat, endθ::Cfloat,
        color::BridgeColor, brushSize::Cfloat)::BridgeShapeCircle
end
function euclid_create_new_circle(state_ptr::Ptr{Cvoid},
    x::Float32, y::Float32, z::Float32,
    radius::Float32, startθ::Float32, endθ::Float32,
    color::Colorant, brushSize::Float32)
    euclid_create_new_circle(state_ptr, x, y, z, radius, startθ, endθ, bridge_color(color), brushSize)
end
function euclid_create_new_circle(state_ptr::Ptr{Cvoid},
    x::Float32, y::Float32, z::Float32,
    radius::Float32, startθ::Float32, endθ::Float32,
    color::Symbol, brushSize::Float32)
    euclid_create_new_circle(state_ptr, x, y, z, radius, startθ, endθ, bridge_color(color), brushSize)
end
function euclid_create_new_circle(state_ptr::Ptr{Cvoid},
    x::Float32, y::Float32, z::Float32,
    radius::Float32, startθ::Float32, endθ::Float32,
    color::AbstractString, brushSize::Float32)
    euclid_create_new_circle(state_ptr, x, y, z, radius, startθ, endθ, bridge_color(color), brushSize)
end




function euclid_get_point(state_ptr::Ptr{Cvoid}, id::Integer)
    @ccall get_point_view(state_ptr::Ptr{Cvoid}, id::Cint)::BridgePointView
end


function euclid_show_point(state_ptr::Ptr{Cvoid}, id::Integer)
    @ccall show_point(state_ptr::Ptr{Cvoid}, id::Cint)::Cvoid
end
function euclid_hide_point(state_ptr::Ptr{Cvoid}, id::Integer)
    @ccall hide_point(state_ptr::Ptr{Cvoid}, id::Cint)::Cvoid
end
function euclid_set_point_position(
    state_ptr::Ptr{Cvoid}, id::Integer, x::Float32, y::Float32, z::Float32)
    pos = (x, y, z)
    @ccall set_point_position(state_ptr::Ptr{Cvoid}, id::Cint, pos::NTuple{3, Cfloat})::Cvoid
end
function euclid_set_point_brush(state_ptr::Ptr{Cvoid}, id::Integer, brushSize::Float32)
    @ccall set_point_brush(state_ptr::Ptr{Cvoid}, id::Cint, brushSize::Cfloat)::Cvoid
end
function euclid_set_point_color(state_ptr::Ptr{Cvoid}, id::Integer, color::BridgeColor)
    @ccall set_point_color(state_ptr::Ptr{Cvoid}, id::Cint, color::BridgeColor)::Cvoid
end
function euclid_set_point_color(state_ptr::Ptr{Cvoid}, id::Integer, color::Colorant)
    euclid_set_point_color(state_ptr, id, bridge_color(color))
end
function euclid_set_point_color(state_ptr::Ptr{Cvoid}, id::Integer, color::Symbol)
    euclid_set_point_color(state_ptr, id, bridge_color(color))
end
function euclid_set_point_color(state_ptr::Ptr{Cvoid}, id::Integer, color::AbstractString)
    euclid_set_point_color(state_ptr, id, bridge_color(color))
end
function euclid_set_point_active_color(state_ptr::Ptr{Cvoid}, id::Integer, color::BridgeColor)
    @ccall set_point_active_color(state_ptr::Ptr{Cvoid}, id::Cint, color::BridgeColor)::Cvoid
end
function euclid_set_point_active_color(state_ptr::Ptr{Cvoid}, id::Integer, color::Colorant)
    euclid_set_point_active_color(state_ptr, id, bridge_color(color))
end
function euclid_set_point_active_color(state_ptr::Ptr{Cvoid}, id::Integer, color::Symbol)
    euclid_set_point_active_color(state_ptr, id, bridge_color(color))
end
function euclid_set_point_active_color(state_ptr::Ptr{Cvoid}, id::Integer, color::AbstractString)
    euclid_set_point_active_color(state_ptr, id, bridge_color(color))
end



function euclid_show_pen(state_ptr::Ptr{Cvoid})
    @ccall show_pen(state_ptr::Ptr{Cvoid})::Cvoid
end

function euclid_hide_pen(state_ptr::Ptr{Cvoid})
    @ccall hide_pen(state_ptr::Ptr{Cvoid})::Cvoid
end

function euclid_set_pen_active(state_ptr::Ptr{Cvoid}, active::Integer, c::BridgeColor)
    @ccall set_pen_active(state_ptr::Ptr{Cvoid}, active::Cint, c::BridgeColor)::Cvoid
end
function euclid_set_pen_active(state_ptr::Ptr{Cvoid}, active::Integer, c::Colorant)
    euclid_set_pen_active(state_ptr, active, bridge_color(c))
end

function euclid_set_pen_active(state_ptr::Ptr{Cvoid}, active::Integer, name::Symbol)
    euclid_set_pen_active(state_ptr, active, bridge_color(name))
end

function euclid_set_pen_active(state_ptr::Ptr{Cvoid}, active::Integer, name::AbstractString)
    euclid_set_pen_active(state_ptr, active, bridge_color(name))
end

function euclid_clear_pen_active(state_ptr::Ptr{Cvoid})
    @ccall clear_pen_active(state_ptr::Ptr{Cvoid})::Cvoid
end

function euclid_lock_pen_joint1(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, z::Float32)
    pos = (x, y, z)
    @ccall lock_pen_joint1(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
end

function euclid_unlock_pen_joint1(state_ptr::Ptr{Cvoid})
    @ccall unlock_pen_joint1(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
end

function euclid_move_pen_joint1(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, z::Float32)
    pos = (x, y, z)
    @ccall move_pen_joint1(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
end

function euclid_get_pen_joint1_position(state_ptr::Ptr{Cvoid})
    return @ccall get_pen_joint1_position(state_ptr::Ptr{Cvoid})::NTuple{3, Cfloat}
end

function euclid_lock_pen_joint2(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, z::Float32)
    pos = (x, y, z)
    @ccall lock_pen_joint2(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
end

function euclid_unlock_pen_joint2(state_ptr::Ptr{Cvoid})
    @ccall unlock_pen_joint2(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
end

function euclid_move_pen_joint2(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, z::Float32)
    pos = (x, y, z)
    @ccall move_pen_joint2(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
end

function euclid_get_pen_joint2_position(state_ptr::Ptr{Cvoid})
    return @ccall get_pen_joint2_position(state_ptr::Ptr{Cvoid})::NTuple{3, Cfloat}
end

function euclid_show_compass(state_ptr::Ptr{Cvoid})
    @ccall show_compass(state_ptr::Ptr{Cvoid})::Cvoid
end

function euclid_hide_compass(state_ptr::Ptr{Cvoid})
    @ccall hide_compass(state_ptr::Ptr{Cvoid})::Cvoid
end

function euclid_set_compass_active(state_ptr::Ptr{Cvoid}, active::Integer, c::BridgeColor)
    @ccall set_compass_active(state_ptr::Ptr{Cvoid}, active::Cint, c::BridgeColor)::Cvoid
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

function euclid_lock_compass_joint1(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, z::Float32)
    pos = (x, y, z)
    @ccall lock_compass_joint1(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
end

function euclid_unlock_compass_joint1(state_ptr::Ptr{Cvoid})
    @ccall unlock_compass_joint1(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
end

function euclid_move_compass_joint1(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, z::Float32)
    pos = (x, y, z)
    @ccall move_compass_joint1(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
end

function euclid_get_compass_joint1_position(state_ptr::Ptr{Cvoid})
    return @ccall get_compass_joint1_position(state_ptr::Ptr{Cvoid})::NTuple{3, Cfloat}
end

function euclid_lock_compass_joint2(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, z::Float32)
    pos = (x, y, z)
    @ccall lock_compass_joint2(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
end

function euclid_unlock_compass_joint2(state_ptr::Ptr{Cvoid})
    @ccall unlock_compass_joint2(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
end

function euclid_move_compass_joint2(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, z::Float32)
    pos = (x, y, z)
    @ccall move_compass_joint2(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
end

function euclid_get_compass_joint2_position(state_ptr::Ptr{Cvoid})
    return @ccall get_compass_joint2_position(state_ptr::Ptr{Cvoid})::NTuple{3, Cfloat}
end

function euclid_set_animation_meta(state_ptr::Ptr{Cvoid}, pos::Integer, metadata::Float32)
    @ccall set_animation_meta(state_ptr::Ptr{Cvoid}, pos::Cint, metadata::Cfloat)::Cvoid
end

function euclid_get_animation_meta(state_ptr::Ptr{Cvoid}, pos::Integer)
    ret = @ccall get_animation_meta(state_ptr::Ptr{Cvoid}, pos::Cint)::Cfloat
    return Float32(ret)
end

function euclid_emit_trailing_particle(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, color::BridgeColor)
    pos = (x, y)
    @ccall emit_trailing_particle(state_ptr::Ptr{Cvoid}, pos::NTuple{2, Cfloat}, color::BridgeColor)::Cvoid
end

function euclid_emit_trailing_particle(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, color::Colorant)
    euclid_emit_trailing_particle(state_ptr, x, y, bridge_color(color))
end

function euclid_emit_trailing_particle(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, color::Symbol)
    euclid_emit_trailing_particle(state_ptr, x, y, bridge_color(color))
end

function euclid_emit_trailing_particle(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, color::AbstractString)
    euclid_emit_trailing_particle(state_ptr, x, y, bridge_color(color))
end

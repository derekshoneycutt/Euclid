"""Copied UTF-8 label source, MIME kind, and bridge status."""
struct ShapeLabelSource
    source::Union{Nothing, String}
    mime::Int32
    status::Int32
end

"""Convert any supported color input to its bridge representation."""
_shape_color(color::BridgeColor) = color
_shape_color(color) = bridge_color(color)

"""Build canonical shape style values for one native constructor."""
_shape_style(color, brush_size::Real) =
    BridgeShapeStyle(_shape_color(color), Cfloat(brush_size))

"""Build a positioned canonical shape input."""
function _positioned_shape_input(position, color, brush_size::Real)
    point = (Cfloat(position[1]), Cfloat(position[2]), Cfloat(position[3]))
    BridgePositionedShapeInput(point, _shape_style(color, brush_size))
end

"""Construct a new label from bounded UTF-8 and return its packed entity handle."""
function create_new_label(state_ptr::Ptr{Cvoid}, source::AbstractString,
    position, color, brush_size::Real)
    input = _positioned_shape_input(position, color, brush_size)
    @ccall shape_create_label(state_ptr::Ptr{Cvoid}, source::Cstring,
        Int32(0)::Int32,
        input::BridgePositionedShapeInput)::BridgeShapeEntityResult
end

"""Create one UTF-8 label from explicit coordinates."""
function create_new_label(state_ptr::Ptr{Cvoid}, source::AbstractString,
    x::Real, y::Real, z::Real, color, brush_size::Real)
    create_new_label(state_ptr, source, (x, y, z), color, brush_size)
end

"""Create one UTF-8 label from a character and vector position."""
function create_new_label(state_ptr::Ptr{Cvoid}, source::Char,
    position, color, brush_size::Real)
    create_new_label(state_ptr, string(source), position, color, brush_size)
end

"""Create one UTF-8 label character from explicit coordinates."""
function create_new_label(state_ptr::Ptr{Cvoid}, source::Char,
    x::Real, y::Real, z::Real, color, brush_size::Real)
    create_new_label(state_ptr, string(source), (x, y, z), color, brush_size)
end

"""Create one UTF-8 label from a Unicode scalar value and vector position."""
function create_new_label(state_ptr::Ptr{Cvoid}, source::UInt32,
    position, color, brush_size::Real)
    create_new_label(state_ptr, Char(source), position, color, brush_size)
end

"""Create one UTF-8 label scalar from explicit coordinates."""
function create_new_label(state_ptr::Ptr{Cvoid}, source::UInt32,
    x::Real, y::Real, z::Real, color, brush_size::Real)
    create_new_label(state_ptr, Char(source), (x, y, z), color, brush_size)
end

"""Create one standalone point and return its packed entity handle."""
function create_new_point(state_ptr::Ptr{Cvoid}, position, color, brush_size::Real)
    input = _positioned_shape_input(position, color, brush_size)
    @ccall shape_create_point(state_ptr::Ptr{Cvoid},
        input::BridgePositionedShapeInput)::BridgeShapeEntityResult
end

"""Create one standalone point from explicit coordinates."""
function create_new_point(state_ptr::Ptr{Cvoid}, x::Real, y::Real, z::Real,
    color, brush_size::Real)
    create_new_point(state_ptr, (x, y, z), color, brush_size)
end

"""Create one line and return its direct packed entity handles."""
function create_new_line(state_ptr::Ptr{Cvoid},
    x1::Real, y1::Real, z1::Real, x2::Real, y2::Real, z2::Real;
    color=BridgeColor(0, 0, 0, 0), brush_size::Real=0f0)
    first = (Cfloat(x1), Cfloat(y1), Cfloat(z1))
    second = (Cfloat(x2), Cfloat(y2), Cfloat(z2))
    style = _shape_style(color, brush_size)
    @ccall shape_create_line(state_ptr::Ptr{Cvoid}, first::NTuple{3, Cfloat},
        second::NTuple{3, Cfloat}, style::BridgeShapeStyle)::BridgeShapeLine
end

"""Create one line from two vector positions."""
function create_new_line(state_ptr::Ptr{Cvoid}, first, second,
    color, brush_size::Real)
    create_new_line(state_ptr, first[1], first[2], first[3],
        second[1], second[2], second[3]; color=color, brush_size=brush_size)
end

"""Create one arc variant through its native packed-handle constructor."""
function _create_arc(filled::Bool, state_ptr::Ptr{Cvoid}, center,
    radius::Real, start_theta::Real, end_theta::Real, color, brush_size::Real)
    position = (Cfloat(center[1]), Cfloat(center[2]), Cfloat(center[3]))
    arc = BridgeArcGeometry(Cfloat(radius), Cfloat(start_theta), Cfloat(end_theta))
    style = _shape_style(color, brush_size)
    if !filled
        return @ccall shape_create_arc(state_ptr::Ptr{Cvoid},
            position::NTuple{3, Cfloat}, arc::BridgeArcGeometry,
            style::BridgeShapeStyle)::BridgeShapeCircle
    end
    @ccall shape_create_filled_arc(state_ptr::Ptr{Cvoid},
        position::NTuple{3, Cfloat}, arc::BridgeArcGeometry,
        style::BridgeShapeStyle)::BridgeShapeFilledCircle
end

"""Create one outlined arc from explicit coordinates."""
function create_new_circle(state_ptr::Ptr{Cvoid}, x::Real, y::Real, z::Real,
    radius::Real, start_theta::Real, end_theta::Real;
    color=BridgeColor(0, 0, 0, 0), brush_size::Real=0f0)
    _create_arc(false, state_ptr, (x, y, z), radius,
        start_theta, end_theta, color, brush_size)
end

"""Create one outlined arc from a center vector."""
function create_new_circle(state_ptr::Ptr{Cvoid}, center,
    radius::Real, start_theta::Real, end_theta::Real, color, brush_size::Real)
    _create_arc(false, state_ptr, center, radius,
        start_theta, end_theta, color, brush_size)
end

"""Create one filled arc from explicit coordinates."""
function create_new_filledcircle(state_ptr::Ptr{Cvoid}, x::Real, y::Real, z::Real,
    radius::Real, start_theta::Real, end_theta::Real;
    color=BridgeColor(0, 0, 0, 0), brush_size::Real=0f0)
    _create_arc(true, state_ptr, (x, y, z), radius,
        start_theta, end_theta, color, brush_size)
end

"""Create one filled arc from a center vector."""
function create_new_filledcircle(state_ptr::Ptr{Cvoid}, center,
    radius::Real, start_theta::Real, end_theta::Real, color, brush_size::Real)
    _create_arc(true, state_ptr, center, radius,
        start_theta, end_theta, color, brush_size)
end

"""Create one triangle from keyword vertex coordinates."""
function create_new_triangle(state_ptr::Ptr{Cvoid};
    x1::Real=0f0, y1::Real=0f0, z1::Real=0f0,
    x2::Real=0f0, y2::Real=0f0, z2::Real=0f0,
    x3::Real=0f0, y3::Real=0f0, z3::Real=0f0,
    color=BridgeColor(0, 0, 0, 0))
    vertices = ((Cfloat(x1), Cfloat(y1), Cfloat(z1)),
        (Cfloat(x2), Cfloat(y2), Cfloat(z2)),
        (Cfloat(x3), Cfloat(y3), Cfloat(z3)))
    style = _shape_style(color, 0f0)
    @ccall shape_create_triangle(state_ptr::Ptr{Cvoid},
        vertices::NTuple{3, NTuple{3, Cfloat}},
        style::BridgeShapeStyle)::BridgeShapeTriangle
end

"""Create one triangle from vector positions."""
function create_new_triangle(state_ptr::Ptr{Cvoid}, first, second, third, color)
    create_new_triangle(state_ptr; x1=first[1], y1=first[2], z1=first[3],
        x2=second[1], y2=second[2], z2=second[3],
        x3=third[1], y3=third[2], z3=third[3], color=color)
end

"""Create one square from keyword vertex coordinates."""
function create_new_square(state_ptr::Ptr{Cvoid};
    x1::Real=0f0, y1::Real=0f0, z1::Real=0f0,
    x2::Real=0f0, y2::Real=0f0, z2::Real=0f0,
    x3::Real=0f0, y3::Real=0f0, z3::Real=0f0,
    x4::Real=0f0, y4::Real=0f0, z4::Real=0f0,
    color=BridgeColor(0, 0, 0, 0))
    vertices = BridgeSquareVertices(((Cfloat(x1), Cfloat(y1), Cfloat(z1)),
        (Cfloat(x2), Cfloat(y2), Cfloat(z2)),
        (Cfloat(x3), Cfloat(y3), Cfloat(z3)),
        (Cfloat(x4), Cfloat(y4), Cfloat(z4))))
    style = _shape_style(color, 0f0)
    @ccall shape_create_square(state_ptr::Ptr{Cvoid},
        vertices::BridgeSquareVertices,
        style::BridgeShapeStyle)::BridgeShapeSquare
end

"""Create one square from vector positions."""
function create_new_square(state_ptr::Ptr{Cvoid}, first, second, third, fourth, color)
    create_new_square(state_ptr; x1=first[1], y1=first[2], z1=first[3],
        x2=second[1], y2=second[2], z2=second[3],
        x3=third[1], y3=third[2], z3=third[3],
        x4=fourth[1], y4=fourth[2], z4=fourth[3], color=color)
end

"""Create one pentagon from keyword vertex coordinates."""
function create_new_pentagon(state_ptr::Ptr{Cvoid};
    x1::Real=0f0, y1::Real=0f0, z1::Real=0f0,
    x2::Real=0f0, y2::Real=0f0, z2::Real=0f0,
    x3::Real=0f0, y3::Real=0f0, z3::Real=0f0,
    x4::Real=0f0, y4::Real=0f0, z4::Real=0f0,
    x5::Real=0f0, y5::Real=0f0, z5::Real=0f0,
    color=BridgeColor(0, 0, 0, 0))
    vertices = BridgePentagonVertices(((Cfloat(x1), Cfloat(y1), Cfloat(z1)),
        (Cfloat(x2), Cfloat(y2), Cfloat(z2)),
        (Cfloat(x3), Cfloat(y3), Cfloat(z3)),
        (Cfloat(x4), Cfloat(y4), Cfloat(z4)),
        (Cfloat(x5), Cfloat(y5), Cfloat(z5))))
    style = _shape_style(color, 0f0)
    @ccall shape_create_pentagon(state_ptr::Ptr{Cvoid},
        vertices::BridgePentagonVertices,
        style::BridgeShapeStyle)::BridgeShapePentagon
end

"""Create one pentagon from vector positions."""
function create_new_pentagon(state_ptr::Ptr{Cvoid}, first, second, third,
    fourth, fifth, color)
    create_new_pentagon(state_ptr; x1=first[1], y1=first[2], z1=first[3],
        x2=second[1], y2=second[2], z2=second[3],
        x3=third[1], y3=third[2], z3=third[3],
        x4=fourth[1], y4=fourth[2], z4=fourth[3],
        x5=fifth[1], y5=fifth[2], z5=fifth[3], color=color)
end

"""Read one packed entity's immutable query projection."""
function get_point(state_ptr::Ptr{Cvoid}, entity::Integer)
    @ccall shape_get_view(state_ptr::Ptr{Cvoid},
        UInt64(entity)::UInt64)::BridgePointView
end

"""Copy one packed label entity's immutable UTF-8 source and MIME."""
function shape_label_source(state_ptr::Ptr{Cvoid}, entity::Integer)
    bytes = Vector{UInt8}(undef, 256)
    result = GC.@preserve bytes begin
        @ccall shape_copy_label_source(state_ptr::Ptr{Cvoid},
            UInt64(entity)::UInt64, pointer(bytes)::Ptr{UInt8},
            length(bytes)::Int32)::BridgeLabelCopyResult
    end
    result.status == BRIDGE_STATUS_OK ||
        return ShapeLabelSource(nothing, result.mime, result.status)
    return ShapeLabelSource(
        String(bytes[1:result.byte_count]), result.mime, result.status)
end

"""Set one packed entity visible."""
function show_point(state_ptr::Ptr{Cvoid}, entity::Integer)
    @ccall shape_set_visible(state_ptr::Ptr{Cvoid}, UInt64(entity)::UInt64,
        UInt8(1)::UInt8)::Int32
end

"""Set one packed entity hidden."""
function hide_point(state_ptr::Ptr{Cvoid}, entity::Integer)
    @ccall shape_set_visible(state_ptr::Ptr{Cvoid}, UInt64(entity)::UInt64,
        UInt8(0)::UInt8)::Int32
end

"""Hide each packed entity in one bounded collection."""
function hide_point_batch(state_ptr::Ptr{Cvoid}, entities)
    for entity in entities
        status = hide_point(state_ptr, entity)
        status == BRIDGE_STATUS_OK || return status
    end
    BRIDGE_STATUS_OK
end

"""Set one packed entity's transform position."""
function set_point_position(state_ptr::Ptr{Cvoid}, entity::Integer,
    x::Real, y::Real, z::Real)
    position = (Cfloat(x), Cfloat(y), Cfloat(z))
    @ccall shape_set_position(state_ptr::Ptr{Cvoid}, UInt64(entity)::UInt64,
        position::NTuple{3, Cfloat})::Int32
end

"""Set one packed entity's transform position from a vector."""
function set_point_position(state_ptr::Ptr{Cvoid}, entity::Integer, position)
    set_point_position(state_ptr, entity, position[1], position[2], position[3])
end

"""Set one packed entity's transform position and return status."""
set_point_position_status(state_ptr::Ptr{Cvoid}, entity::Integer, position) =
    set_point_position(state_ptr, entity, position)

"""Set one packed entity's transform position from coordinates and return status."""
set_point_position_status(state_ptr::Ptr{Cvoid}, entity::Integer,
    x::Real, y::Real, z::Real) = set_point_position(state_ptr, entity, x, y, z)

"""Set one packed entity's render color."""
function set_point_color(state_ptr::Ptr{Cvoid}, entity::Integer, color)
    value = _shape_color(color)
    @ccall shape_set_color(state_ptr::Ptr{Cvoid}, UInt64(entity)::UInt64,
        value::BridgeColor)::Int32
end

"""Set one packed entity's active render color."""
function set_point_active_color(state_ptr::Ptr{Cvoid}, entity::Integer, color)
    value = _shape_color(color)
    @ccall shape_set_active_color(state_ptr::Ptr{Cvoid}, UInt64(entity)::UInt64,
        value::BridgeColor)::Int32
end

"""Set one packed entity's brush size."""
function set_point_brush(state_ptr::Ptr{Cvoid}, entity::Integer, brush_size::Real)
    @ccall shape_set_brush_size(state_ptr::Ptr{Cvoid}, UInt64(entity)::UInt64,
        Cfloat(brush_size)::Cfloat)::Int32
end

"""Set one packed entity's brush size and return status."""
set_point_brush_size(state_ptr::Ptr{Cvoid}, entity::Integer, brush_size::Real) =
    set_point_brush(state_ptr, entity, brush_size)

"""Set one packed entity's render offset."""
function set_point_offset(state_ptr::Ptr{Cvoid}, entity::Integer, offset::Real)
    @ccall shape_set_offset(state_ptr::Ptr{Cvoid}, UInt64(entity)::UInt64,
        Cfloat(offset)::Cfloat)::Int32
end

"""Select one packed entity's active geometry feature."""
function set_point_active_child(state_ptr::Ptr{Cvoid}, entity::Integer, active::Integer)
    @ccall shape_set_active_feature(state_ptr::Ptr{Cvoid}, UInt64(entity)::UInt64,
        UInt16(active)::UInt16)::Int32
end
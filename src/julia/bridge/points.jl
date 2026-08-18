"""
Construct a new label in the Euclid system to be shown at a point on the surface

------

Parameters:

- `state_ptr` : The state of the Euclid application to pass to the API
- `label` : The codepoint of the label rune to display
- `x` : The x value for the position of the point
- `y` : The y value for the position of the point
- `z` : The z value for the position of the point
- `pos` : A vector can be provided in [x, y, z] form instead of individual parameters
- `color` : The color to show the point with
- `brush_size` : The size of the point to show

Returns: a `BridgePointView` describing the newly created point
"""
function create_new_label(state_ptr::Ptr{Cvoid},
    label::UInt32, x::Real, y::Real, z::Real,
    color::BridgeColor, brush_size::Real)
    pos = (Real(x), Real(y), Real(z))
    return @ccall create_new_label(state_ptr::Ptr{Cvoid}, label::UInt32,
        pos::NTuple{3, Cfloat}, color::BridgeColor, brush_size::Cfloat)::BridgePointView
end
function create_new_label(state_ptr::Ptr{Cvoid},
    label::Char, x::Real, y::Real, z::Real,
    color::BridgeColor, brush_size::Real)
    create_new_label(state_ptr, codepoint(label), x, y, z, color, brush_size)
end
function create_new_label(state_ptr::Ptr{Cvoid},
    label::UInt32, pos::AbstractVector{<:Real},
    color::BridgeColor, brush_size::Real)
    create_new_label(state_ptr, label, pos[1], pos[2], pos[3], color, brush_size)
end
function create_new_label(state_ptr::Ptr{Cvoid},
    label::Char, pos::AbstractVector{<:Real},
    color::BridgeColor, brush_size::Real)
    create_new_label(state_ptr, codepoint(label), pos[1], pos[2], pos[3],
        color, brush_size)
end
function create_new_label(state_ptr::Ptr{Cvoid},
    label::UInt32, x::Real, y::Real, z::Real,
    color::Colorant, brush_size::Real)
    create_new_label(state_ptr, label, x, y, z, bridge_color(color), brush_size)
end
function create_new_label(state_ptr::Ptr{Cvoid},
    label::Char, x::Real, y::Real, z::Real,
    color::Colorant, brush_size::Real)
    create_new_label(state_ptr, codepoint(label), x, y, z, bridge_color(color), brush_size)
end
function create_new_label(state_ptr::Ptr{Cvoid},
    label::UInt32, pos::AbstractVector{<:Real},
    color::Colorant, brush_size::Real)
    create_new_label(state_ptr, label, pos[1], pos[2], pos[3],
        bridge_color(color), brush_size)
end
function create_new_label(state_ptr::Ptr{Cvoid},
    label::Char, pos::AbstractVector{<:Real},
    color::Colorant, brush_size::Real)
    create_new_label(state_ptr, codepoint(label), pos[1], pos[2], pos[3],
        bridge_color(color), brush_size)
end
function create_new_label(state_ptr::Ptr{Cvoid},
    label::UInt32, x::Real, y::Real, z::Real,
    color::Symbol, brush_size::Real)
    create_new_label(state_ptr, label, x, y, z, bridge_color(color), brush_size)
end
function create_new_label(state_ptr::Ptr{Cvoid},
    label::Char, x::Real, y::Real, z::Real,
    color::Symbol, brush_size::Real)
    create_new_label(state_ptr, codepoint(label), x, y, z, bridge_color(color), brush_size)
end
function create_new_label(state_ptr::Ptr{Cvoid},
    label::UInt32, pos::AbstractVector{<:Real},
    color::Symbol, brush_size::Real)
    create_new_label(state_ptr, label, pos[1], pos[2], pos[3],
        bridge_color(color), brush_size)
end
function create_new_label(state_ptr::Ptr{Cvoid},
    label::Char, pos::AbstractVector{<:Real},
    color::Symbol, brush_size::Real)
    create_new_label(state_ptr, codepoint(label), pos[1], pos[2], pos[3],
        bridge_color(color), brush_size)
end
function create_new_label(state_ptr::Ptr{Cvoid},
    label::UInt32, x::Real, y::Real, z::Real,
    color::AbstractString, brush_size::Real)
    create_new_label(state_ptr, label, x, y, z, bridge_color(color), brush_size)
end
function create_new_label(state_ptr::Ptr{Cvoid},
    label::Char, x::Real, y::Real, z::Real,
    color::AbstractString, brush_size::Real)
    create_new_label(state_ptr, codepoint(label), x, y, z, bridge_color(color), brush_size)
end
function create_new_label(state_ptr::Ptr{Cvoid},
    label::UInt32, pos::AbstractVector{<:Real},
    color::AbstractString, brush_size::Real)
    create_new_label(state_ptr, label, pos[1], pos[2], pos[3],
        bridge_color(color), brush_size)
end
function create_new_label(state_ptr::Ptr{Cvoid},
    label::Char, pos::AbstractVector{<:Real},
    color::AbstractString, brush_size::Real)
    create_new_label(state_ptr, codepoint(label), pos[1], pos[2], pos[3],
        bridge_color(color), brush_size)
end

"""
Construct a new decorated label in the Euclid system to be shown at a point.

Decorations:
- `LABEL_DECORATION_NONE`
- `LABEL_DECORATION_PRIME`
- `LABEL_DECORATION_DOUBLEPRIME`
- `LABEL_DECORATION_TRIPLEPRIME`
- `LABEL_DECORATION_HAT`
- `LABEL_DECORATION_BAR`
"""
function create_new_label_decorated(state_ptr::Ptr{Cvoid},
    label::UInt32, decoration_kind::Integer, x::Real, y::Real, z::Real,
    color::BridgeColor, brush_size::Real)
    pos = (Float32(x), Float32(y), Float32(z))
    return @ccall create_new_label_decorated(state_ptr::Ptr{Cvoid}, label::UInt32,
        Int32(decoration_kind)::Int32, pos::NTuple{3, Cfloat},
        color::BridgeColor, brush_size::Cfloat)::BridgePointView
end
function create_new_label_decorated(state_ptr::Ptr{Cvoid},
    label::Char, decoration_kind::Integer, x::Real, y::Real, z::Real,
    color::BridgeColor, brush_size::Real)
    create_new_label_decorated(state_ptr, codepoint(label), decoration_kind, x, y, z,
        color, brush_size)
end
function create_new_label_decorated(state_ptr::Ptr{Cvoid},
    label::UInt32, decoration_kind::Integer, pos::AbstractVector{<:Real},
    color::BridgeColor, brush_size::Real)
    create_new_label_decorated(state_ptr, label, decoration_kind, pos[1], pos[2], pos[3],
        color, brush_size)
end
function create_new_label_decorated(state_ptr::Ptr{Cvoid},
    label::Char, decoration_kind::Integer, pos::AbstractVector{<:Real},
    color::BridgeColor, brush_size::Real)
    create_new_label_decorated(state_ptr, codepoint(label), decoration_kind,
        pos[1], pos[2], pos[3], color, brush_size)
end
function create_new_label_decorated(state_ptr::Ptr{Cvoid},
    label::UInt32, decoration_kind::Integer, x::Real, y::Real, z::Real,
    color::Colorant, brush_size::Real)
    create_new_label_decorated(state_ptr, label, decoration_kind, x, y, z,
        bridge_color(color), brush_size)
end
function create_new_label_decorated(state_ptr::Ptr{Cvoid},
    label::Char, decoration_kind::Integer, x::Real, y::Real, z::Real,
    color::Colorant, brush_size::Real)
    create_new_label_decorated(state_ptr, codepoint(label), decoration_kind, x, y, z,
        bridge_color(color), brush_size)
end
function create_new_label_decorated(state_ptr::Ptr{Cvoid},
    label::UInt32, decoration_kind::Integer, pos::AbstractVector{<:Real},
    color::Colorant, brush_size::Real)
    create_new_label_decorated(state_ptr, label, decoration_kind, pos[1], pos[2], pos[3],
        bridge_color(color), brush_size)
end
function create_new_label_decorated(state_ptr::Ptr{Cvoid},
    label::Char, decoration_kind::Integer, pos::AbstractVector{<:Real},
    color::Colorant, brush_size::Real)
    create_new_label_decorated(
        state_ptr, codepoint(label), decoration_kind, pos[1], pos[2], pos[3],
        bridge_color(color), brush_size)
end
function create_new_label_decorated(state_ptr::Ptr{Cvoid},
    label::UInt32, decoration_kind::Integer, x::Real, y::Real, z::Real,
    color::Symbol, brush_size::Real)
    create_new_label_decorated(state_ptr, label, decoration_kind, x, y, z,
        bridge_color(color), brush_size)
end
function create_new_label_decorated(state_ptr::Ptr{Cvoid},
    label::Char, decoration_kind::Integer, x::Real, y::Real, z::Real,
    color::Symbol, brush_size::Real)
    create_new_label_decorated(
        state_ptr, codepoint(label), decoration_kind, x, y, z,
        bridge_color(color), brush_size)
end
function create_new_label_decorated(state_ptr::Ptr{Cvoid},
    label::UInt32, decoration_kind::Integer, pos::AbstractVector{<:Real},
    color::Symbol, brush_size::Real)
    create_new_label_decorated(
        state_ptr, label, decoration_kind, pos[1], pos[2], pos[3],
        bridge_color(color), brush_size)
end
function create_new_label_decorated(state_ptr::Ptr{Cvoid},
    label::Char, decoration_kind::Integer, pos::AbstractVector{<:Real},
    color::Symbol, brush_size::Real)
    create_new_label_decorated(
        state_ptr, codepoint(label), decoration_kind, pos[1], pos[2], pos[3],
        bridge_color(color), brush_size)
end
function create_new_label_decorated(state_ptr::Ptr{Cvoid},
    label::UInt32, decoration_kind::Integer, x::Real, y::Real, z::Real,
    color::AbstractString, brush_size::Real)
    create_new_label_decorated(
        state_ptr, label, decoration_kind, x, y, z, bridge_color(color), brush_size)
end
function create_new_label_decorated(state_ptr::Ptr{Cvoid},
    label::Char, decoration_kind::Integer, x::Real, y::Real, z::Real,
    color::AbstractString, brush_size::Real)
    create_new_label_decorated(
        state_ptr, codepoint(label), decoration_kind, x, y, z,
        bridge_color(color), brush_size)
end
function create_new_label_decorated(state_ptr::Ptr{Cvoid},
    label::UInt32, decoration_kind::Integer, pos::AbstractVector{<:Real},
    color::AbstractString, brush_size::Real)
    create_new_label_decorated(
        state_ptr, label, decoration_kind, pos[1], pos[2], pos[3],
        bridge_color(color), brush_size)
end
function create_new_label_decorated(state_ptr::Ptr{Cvoid},
    label::Char, decoration_kind::Integer, pos::AbstractVector{<:Real},
    color::AbstractString, brush_size::Real)
    create_new_label_decorated(
        state_ptr, codepoint(label), decoration_kind, pos[1], pos[2], pos[3],
        bridge_color(color), brush_size)
end

"""
Construct a new point in the Euclid system to be shown as a point on the surface

------

Parameters:

- `state_ptr` : The state of the Euclid application to pass to the API
- `x` : The x value for the position of the point
- `y` : The y value for the position of the point
- `z` : The z value for the position of the point
- `pos` : A vector can be provided in [x, y, z] form instead of individual parameters
- `color` : The color to show the point with
- `brush_size` : The size of the point to show

Returns: a `BridgePointView` describing the newly created point
"""
function create_new_point(state_ptr::Ptr{Cvoid},
    x::Real, y::Real, z::Real,
    color::BridgeColor, brush_size::Real)
    pos = (Real(x), Real(y), Real(z))
    return @ccall create_new_point(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat},
        color::BridgeColor, brush_size::Cfloat)::BridgePointView
end
function create_new_point(state_ptr::Ptr{Cvoid},
    pos::AbstractVector{<:Real},
    color::BridgeColor, brush_size::Real)
    create_new_point(state_ptr, pos[1], pos[2], pos[3], color, brush_size)
end
function create_new_point(state_ptr::Ptr{Cvoid},
    x::Real, y::Real, z::Real,
    color::Colorant, brush_size::Real)
    create_new_point(state_ptr, x, y, z, bridge_color(color), brush_size)
end
function create_new_point(state_ptr::Ptr{Cvoid},
    pos::AbstractVector{<:Real},
    color::Colorant, brush_size::Real)
    create_new_point(state_ptr, pos[1], pos[2], pos[3], bridge_color(color), brush_size)
end
function create_new_point(state_ptr::Ptr{Cvoid},
    x::Real, y::Real, z::Real,
    color::Symbol, brush_size::Real)
    create_new_point(state_ptr, x, y, z, bridge_color(color), brush_size)
end
function create_new_point(state_ptr::Ptr{Cvoid},
    pos::AbstractVector{<:Real},
    color::Symbol, brush_size::Real)
    create_new_point(state_ptr, pos[1], pos[2], pos[3], bridge_color(color), brush_size)
end
function create_new_point(state_ptr::Ptr{Cvoid},
    x::Real, y::Real, z::Real,
    color::AbstractString, brush_size::Real)
    create_new_point(state_ptr, x, y, z, bridge_color(color), brush_size)
end
function create_new_point(state_ptr::Ptr{Cvoid},
    pos::AbstractVector{<:Real},
    color::AbstractString, brush_size::Real)
    create_new_point(state_ptr, pos[1], pos[2], pos[3], bridge_color(color), brush_size)
end

"""
Construct a new line in the Euclid system to be shown on the surface

------

Parameters:

- `state_ptr` : The state of the Euclid application to pass to the API
- `x1` : The x value for the position of the first point bounding the line
- `y1` : The y value for the position of the first point bounding the line
- `z1` : The z value for the position of the first point bounding the line
- `pos1` : A vector can be provided in [x1, y1, z1] form instead of individual parameters
- `x2` : The x value for the position of the second point bounding the line
- `y2` : The y value for the position of the second point bounding the line
- `z2` : The z value for the position of the second point bounding the line
- `pos2` : A vector can be provided in [x2, y2, z2] form instead of individual parameters
- `color` : The color to show the line with
- `brush_size` : The size of the line to show

Returns: a `BridgeShapeLine` describing the newly created line
"""
function create_new_line(state_ptr::Ptr{Cvoid},
    x1::Real, y1::Real, z1::Real,
    x2::Real, y2::Real, z2::Real,
    color::BridgeColor, brush_size::Real)
    pos1 = (Float32(x1), Float32(y1), Float32(z1))
    pos2 = (Float32(x2), Float32(y2), Float32(z2))
    return @ccall create_new_line(state_ptr::Ptr{Cvoid}, pos1::NTuple{3, Cfloat},
        pos2::NTuple{3, Cfloat}, color::BridgeColor, brush_size::Cfloat)::BridgeShapeLine
end
function create_new_line(state_ptr::Ptr{Cvoid},
    pos1::AbstractVector{<:Real}, pos2::AbstractVector{<:Real},
    color::BridgeColor, brush_size::Real)
    create_new_line(state_ptr, pos1[1], pos1[2], pos1[3], pos2[1], pos2[2], pos2[3],
        color, brush_size)
end
function create_new_line(state_ptr::Ptr{Cvoid},
    x1::Real, y1::Real, z1::Real,
    x2::Real, y2::Real, z2::Real,
    color::Colorant, brush_size::Real)
    create_new_line(state_ptr, x1, y1, z1, x2, y2, z2, bridge_color(color), brush_size)
end
function create_new_line(state_ptr::Ptr{Cvoid},
    pos1::AbstractVector{<:Real}, pos2::AbstractVector{<:Real},
    color::Colorant, brush_size::Real)
    create_new_line(state_ptr, pos1[1], pos1[2], pos1[3], pos2[1], pos2[2], pos2[3],
        bridge_color(color), brush_size)
end
function create_new_line(state_ptr::Ptr{Cvoid},
    x1::Real, y1::Real, z1::Real,
    x2::Real, y2::Real, z2::Real,
    color::Symbol, brush_size::Real)
    create_new_line(state_ptr, x1, y1, z1, x2, y2, z2, bridge_color(color), brush_size)
end
function create_new_line(state_ptr::Ptr{Cvoid},
    pos1::AbstractVector{<:Real}, pos2::AbstractVector{<:Real},
    color::Symbol, brush_size::Real)
    create_new_line(state_ptr, pos1[1], pos1[2], pos1[3], pos2[1], pos2[2], pos2[3],
        bridge_color(color), brush_size)
end
function create_new_line(state_ptr::Ptr{Cvoid},
    x1::Real, y1::Real, z1::Real,
    x2::Real, y2::Real, z2::Real,
    color::AbstractString, brush_size::Real)
    create_new_line(state_ptr, x1, y1, z1, x2, y2, z2, bridge_color(color), brush_size)
end
function create_new_line(state_ptr::Ptr{Cvoid},
    pos1::AbstractVector{<:Real}, pos2::AbstractVector{<:Real},
    color::AbstractString, brush_size::Real)
    create_new_line(state_ptr, pos1[1], pos1[2], pos1[3], pos2[1], pos2[2], pos2[3],
        bridge_color(color), brush_size)
end

"""
Construct a new circle in the Euclid system to be shown on the surface

------

Parameters:

- `state_ptr` : The state of the Euclid application to pass to the API
- `x` : The x value for the position of the center point of the circle
- `y` : The y value for the position of the center point of the circle
- `z` : The z value for the position of the center point of the circle
- `center` : A vector can be provided in [x, y, z] form instead of individual parameters
- `radius` : The radius of the circle to draw
- `start_θ` : The starting angle in radians of the circle to draw
- `end_θ` : The ending angle in radians of the circle to draw
- `color` : The color to show the circle with
- `brush_size` : The size of the circle to show

Returns: a `BridgeShapeCircle` describing the newly created circle
"""
function create_new_circle(state_ptr::Ptr{Cvoid},
    x::Real, y::Real, z::Real,
    radius::Real, start_θ::Real, end_θ::Real,
    color::BridgeColor, brush_size::Real)
    pos = (Float32(x), Float32(y), Float32(z))
    return @ccall create_new_circle(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat},
        radius::Cfloat, start_θ::Cfloat, end_θ::Cfloat,
        color::BridgeColor, brush_size::Cfloat)::BridgeShapeCircle
end
function create_new_circle(state_ptr::Ptr{Cvoid},
    center::AbstractVector{<:Real},
    radius::Real, start_θ::Real, end_θ::Real,
    color::BridgeColor, brush_size::Real)
    create_new_circle(
        state_ptr, center[1], center[2], center[3], radius, start_θ, end_θ,
        color, brush_size)
end
function create_new_circle(state_ptr::Ptr{Cvoid},
    x::Real, y::Real, z::Real,
    radius::Real, start_θ::Real, end_θ::Real,
    color::Colorant, brush_size::Real)
    create_new_circle(state_ptr, x, y, z, radius, start_θ, end_θ,
        bridge_color(color), brush_size)
end
function create_new_circle(state_ptr::Ptr{Cvoid},
    center::AbstractVector{<:Real},
    radius::Real, start_θ::Real, end_θ::Real,
    color::Colorant, brush_size::Real)
    create_new_circle(state_ptr, center[1], center[2], center[3], radius,
        start_θ, end_θ, bridge_color(color), brush_size)
end
function create_new_circle(state_ptr::Ptr{Cvoid},
    x::Real, y::Real, z::Real,
    radius::Real, start_θ::Real, end_θ::Real,
    color::Symbol, brush_size::Real)
    create_new_circle(state_ptr, x, y, z, radius, start_θ, end_θ,
        bridge_color(color), brush_size)
end
function create_new_circle(state_ptr::Ptr{Cvoid},
    center::AbstractVector{<:Real},
    radius::Real, start_θ::Real, end_θ::Real,
    color::Symbol, brush_size::Real)
    create_new_circle(state_ptr, center[1], center[2], center[3], radius, start_θ, end_θ,
        bridge_color(color), brush_size)
end
function create_new_circle(state_ptr::Ptr{Cvoid},
    x::Real, y::Real, z::Real,
    radius::Real, start_θ::Real, end_θ::Real,
    color::AbstractString, brush_size::Real)
    create_new_circle(state_ptr, x, y, z, radius, start_θ, end_θ,
        bridge_color(color), brush_size)
end
function create_new_circle(state_ptr::Ptr{Cvoid},
    center::AbstractVector{<:Real},
    radius::Real, start_θ::Real, end_θ::Real,
    color::AbstractString, brush_size::Real)
    create_new_circle(state_ptr, center[1], center[2], center[3], radius, start_θ, end_θ,
        bridge_color(color), brush_size)
end

"""
Construct a new filled circle in the Euclid system to be shown on the surface

------

Parameters:

- `state_ptr` : The state of the Euclid application to pass to the API
- `x` : The x value for the position of the center point of the circle
- `y` : The y value for the position of the center point of the circle
- `z` : The z value for the position of the center point of the circle
- `center` : A vector can be provided in [x, y, z] form instead of individual parameters
- `radius` : The radius of the circle to draw
- `start_θ` : The starting angle in radians of the circle to draw
- `end_θ` : The ending angle in radians of the circle to draw
- `color` : The color to show the circle with
- `brush_size` : The size of the circle to show

Returns: a `BridgeShapeCircle` describing the newly created circle
"""
function create_new_filledcircle(state_ptr::Ptr{Cvoid},
    x::Real, y::Real, z::Real,
    radius::Real, start_θ::Real, end_θ::Real,
    color::BridgeColor, brush_size::Real)
    pos = (Float32(x), Float32(y), Float32(z))
    return @ccall create_new_filledcircle(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat},
        radius::Cfloat, start_θ::Cfloat, end_θ::Cfloat,
        color::BridgeColor, brush_size::Cfloat)::BridgeShapeFilledCircle
end
function create_new_filledcircle(state_ptr::Ptr{Cvoid},
    center::AbstractVector{<:Real},
    radius::Real, start_θ::Real, end_θ::Real,
    color::BridgeColor, brush_size::Real)
    create_new_filledcircle(state_ptr, center[1], center[2], center[3], radius,
        start_θ, end_θ, color, brush_size)
end
function create_new_filledcircle(state_ptr::Ptr{Cvoid},
    x::Real, y::Real, z::Real,
    radius::Real, start_θ::Real, end_θ::Real,
    color::Colorant, brush_size::Real)
    create_new_filledcircle(state_ptr, x, y, z, radius, start_θ, end_θ,
        bridge_color(color), brush_size)
end
function create_new_filledcircle(state_ptr::Ptr{Cvoid},
    center::AbstractVector{<:Real},
    radius::Real, start_θ::Real, end_θ::Real,
    color::Colorant, brush_size::Real)
    create_new_filledcircle(state_ptr, center[1], center[2], center[3], radius,
        start_θ, end_θ, bridge_color(color), brush_size)
end
function create_new_filledcircle(state_ptr::Ptr{Cvoid},
    x::Real, y::Real, z::Real,
    radius::Real, start_θ::Real, end_θ::Real,
    color::Symbol, brush_size::Real)
    create_new_filledcircle(state_ptr, x, y, z, radius, start_θ, end_θ,
        bridge_color(color), brush_size)
end
function create_new_filledcircle(state_ptr::Ptr{Cvoid},
    center::AbstractVector{<:Real},
    radius::Real, start_θ::Real, end_θ::Real,
    color::Symbol, brush_size::Real)
    create_new_filledcircle(state_ptr, center[1], center[2], center[3], radius,
        start_θ, end_θ, bridge_color(color), brush_size)
end
function create_new_filledcircle(state_ptr::Ptr{Cvoid},
    x::Real, y::Real, z::Real,
    radius::Real, start_θ::Real, end_θ::Real,
    color::AbstractString, brush_size::Real)
    create_new_filledcircle(state_ptr, x, y, z, radius, start_θ, end_θ,
        bridge_color(color), brush_size)
end
function create_new_filledcircle(state_ptr::Ptr{Cvoid},
    center::AbstractVector{<:Real},
    radius::Real, start_θ::Real, end_θ::Real,
    color::Symbol, brush_size::Real)
    create_new_filledcircle(state_ptr, center[1], center[2], center[3], radius,
        start_θ, end_θ, bridge_color(color), brush_size)
end

"""
Construct a new triangle in the Euclid system to be shown on the surface

------

Parameters:

- `state_ptr` : The state of the Euclid application to pass to the API
- `x1` : The x value for the position of the first point bounding the triangle
- `y1` : The y value for the position of the first point bounding the triangle
- `z1` : The z value for the position of the first point bounding the triangle
- `pos1` : A vector can be provided in [x1, y1, z1] form instead of individual parameters
- `x2` : The x value for the position of the second point bounding the triangle
- `y2` : The y value for the position of the second point bounding the triangle
- `z2` : The z value for the position of the second point bounding the triangle
- `pos2` : A vector can be provided in [x2, y2, z2] form instead of individual parameters
- `x3` : The x value for the position of the third point bounding the triangle
- `y3` : The y value for the position of the third point bounding the triangle
- `z3` : The z value for the position of the third point bounding the triangle
- `pos3` : A vector can be provided in [x3, y3, z3] form instead of individual parameters
- `color` : The color to show the triangle with

Returns: a `BridgeShapeTriangle` describing the newly created triangle
"""
function create_new_triangle(state_ptr::Ptr{Cvoid},
    x1::Real, y1::Real, z1::Real,
    x2::Real, y2::Real, z2::Real,
    x3::Real, y3::Real, z3::Real,
    color::BridgeColor)
    pos1 = (Float32(x1), Float32(y1), Float32(z1))
    pos2 = (Float32(x2), Float32(y2), Float32(z2))
    pos3 = (Float32(x3), Float32(y3), Float32(z3))
    return @ccall create_new_triangle(
        state_ptr::Ptr{Cvoid}, pos1::NTuple{3, Cfloat},
        pos2::NTuple{3, Cfloat}, pos3::NTuple{3, Cfloat},
        color::BridgeColor)::BridgeShapeTriangle
end
function create_new_triangle(state_ptr::Ptr{Cvoid},
    pos1::AbstractVector{<:Real}, pos2::AbstractVector{<:Real},
    pos3::AbstractVector{<:Real}, color::BridgeColor)
    create_new_triangle(
        state_ptr, pos1[1], pos1[2], pos1[3],
        pos2[1], pos2[2], pos2[3],
        pos3[1], pos3[2], pos3[3],
        color)
end
function create_new_triangle(state_ptr::Ptr{Cvoid},
    x1::Real, y1::Real, z1::Real,
    x2::Real, y2::Real, z2::Real,
    x3::Real, y3::Real, z3::Real,
    color::Colorant)
    create_new_triangle(state_ptr, x1, y1, z1, x2, y2, z2, x3, y3, z3,
        bridge_color(color))
end
function create_new_triangle(state_ptr::Ptr{Cvoid},
    pos1::AbstractVector{<:Real}, pos2::AbstractVector{<:Real},
    pos3::AbstractVector{<:Real}, color::Colorant)
    create_new_triangle(
        state_ptr, pos1[1], pos1[2], pos1[3],
        pos2[1], pos2[2], pos2[3],
        pos3[1], pos3[2], pos3[3],
        bridge_color(color))
end
function create_new_triangle(state_ptr::Ptr{Cvoid},
    x1::Real, y1::Real, z1::Real,
    x2::Real, y2::Real, z2::Real,
    x3::Real, y3::Real, z3::Real,
    color::Symbol)
    create_new_triangle(state_ptr, x1, y1, z1, x2, y2, z2, x3, y3, z3,
        bridge_color(color))
end
function create_new_triangle(state_ptr::Ptr{Cvoid},
    pos1::AbstractVector{<:Real}, pos2::AbstractVector{<:Real},
    pos3::AbstractVector{<:Real}, color::Symbol)
    create_new_triangle(
        state_ptr, pos1[1], pos1[2], pos1[3],
        pos2[1], pos2[2], pos2[3],
        pos3[1], pos3[2], pos3[3],
        bridge_color(color))
end
function create_new_triangle(state_ptr::Ptr{Cvoid},
    x1::Real, y1::Real, z1::Real,
    x2::Real, y2::Real, z2::Real,
    x3::Real, y3::Real, z3::Real,
    color::AbstractString)
    create_new_triangle(state_ptr, x1, y1, z1, x2, y2, z2, x3, y3, z3,
        bridge_color(color))
end
function create_new_triangle(state_ptr::Ptr{Cvoid},
    pos1::AbstractVector{<:Real}, pos2::AbstractVector{<:Real},
    pos3::AbstractVector{<:Real}, color::AbstractString)
    create_new_triangle(
        state_ptr, pos1[1], pos1[2], pos1[3],
        pos2[1], pos2[2], pos2[3],
        pos3[1], pos3[2], pos3[3],
        bridge_color(color))
end

"""
Construct a new square in the Euclid system to be shown on the surface

------

Parameters:

- `state_ptr` : The state of the Euclid application to pass to the API
- `x1` : The x value for the position of the first point bounding the square
- `y1` : The y value for the position of the first point bounding the square
- `z1` : The z value for the position of the first point bounding the square
- `pos1` : A vector can be provided in [x1, y1, z1] form instead of individual parameters
- `x2` : The x value for the position of the second point bounding the square
- `y2` : The y value for the position of the second point bounding the square
- `z2` : The z value for the position of the second point bounding the square
- `pos2` : A vector can be provided in [x2, y2, z2] form instead of individual parameters
- `x3` : The x value for the position of the third point bounding the square
- `y3` : The y value for the position of the third point bounding the square
- `z3` : The z value for the position of the third point bounding the square
- `pos3` : A vector can be provided in [x3, y3, z3] form instead of individual parameters
- `x4` : The x value for the position of the fourth point bounding the square
- `y4` : The y value for the position of the fourth point bounding the square
- `z4` : The z value for the position of the fourth point bounding the square
- `pos4` : A vector can be provided in [x4, y4, z4] form instead of individual parameters
- `color` : The color to show the square with

Returns: a `BridgeShapeSquare` describing the newly created square
"""
function create_new_square(state_ptr::Ptr{Cvoid},
    x1::Real, y1::Real, z1::Real,
    x2::Real, y2::Real, z2::Real,
    x3::Real, y3::Real, z3::Real,
    x4::Real, y4::Real, z4::Real,
    color::BridgeColor)
    pos1 = (Float32(x1), Float32(y1), Float32(z1))
    pos2 = (Float32(x2), Float32(y2), Float32(z2))
    pos3 = (Float32(x3), Float32(y3), Float32(z3))
    pos4 = (Float32(x4), Float32(y4), Float32(z4))
    return @ccall create_new_square(
        state_ptr::Ptr{Cvoid}, pos1::NTuple{3, Cfloat},
        pos2::NTuple{3, Cfloat}, pos3::NTuple{3, Cfloat}, pos4::NTuple{3, Cfloat},
        color::BridgeColor)::BridgeShapeSquare
end
function create_new_square(state_ptr::Ptr{Cvoid},
    pos1::AbstractVector{<:Real}, pos2::AbstractVector{<:Real},
    pos3::AbstractVector{<:Real}, pos4::AbstractVector{<:Real},
    color::BridgeColor)
    create_new_square(
        state_ptr, pos1[1], pos1[2], pos1[3],
        pos2[1], pos2[2], pos2[3],
        pos3[1], pos3[2], pos3[3],
        pos4[1], pos4[2], pos4[3],
        color)
end
function create_new_square(state_ptr::Ptr{Cvoid},
    x1::Real, y1::Real, z1::Real,
    x2::Real, y2::Real, z2::Real,
    x3::Real, y3::Real, z3::Real,
    x4::Real, y4::Real, z4::Real,
    color::Colorant)
    create_new_square(
        state_ptr, x1, y1, z1,
        x2, y2, z2,
        x3, y3, z3,
        x4, y4, z4,
        bridge_color(color))
end
function create_new_square(state_ptr::Ptr{Cvoid},
    pos1::AbstractVector{<:Real}, pos2::AbstractVector{<:Real},
    pos3::AbstractVector{<:Real}, pos4::AbstractVector{<:Real},
    color::Colorant)
    create_new_square(
        state_ptr, pos1[1], pos1[2], pos1[3],
        pos2[1], pos2[2], pos2[3],
        pos3[1], pos3[2], pos3[3],
        pos4[1], pos4[2], pos4[3],
        bridge_color(color))
end
function create_new_square(state_ptr::Ptr{Cvoid},
    x1::Real, y1::Real, z1::Real,
    x2::Real, y2::Real, z2::Real,
    x3::Real, y3::Real, z3::Real,
    x4::Real, y4::Real, z4::Real,
    color::Symbol)
    create_new_square(
        state_ptr, x1, y1, z1,
        x2, y2, z2,
        x3, y3, z3,
        x4, y4, z4,
        bridge_color(color))
end
function create_new_square(state_ptr::Ptr{Cvoid},
    pos1::AbstractVector{<:Real}, pos2::AbstractVector{<:Real},
    pos3::AbstractVector{<:Real}, pos4::AbstractVector{<:Real},
    color::Symbol)
    create_new_square(
        state_ptr, pos1[1], pos1[2], pos1[3],
        pos2[1], pos2[2], pos2[3],
        pos3[1], pos3[2], pos3[3],
        pos4[1], pos4[2], pos4[3],
        color)
end
function create_new_square(state_ptr::Ptr{Cvoid},
    x1::Real, y1::Real, z1::Real,
    x2::Real, y2::Real, z2::Real,
    x3::Real, y3::Real, z3::Real,
    x4::Real, y4::Real, z4::Real,
    color::AbstractString)
    create_new_square(
        state_ptr, x1, y1, z1,
        x2, y2, z2,
        x3, y3, z3,
        x4, y4, z4,
        bridge_color(color))
end
function create_new_square(state_ptr::Ptr{Cvoid},
    pos1::AbstractVector{<:Real}, pos2::AbstractVector{<:Real},
    pos3::AbstractVector{<:Real}, pos4::AbstractVector{<:Real},
    color::AbstractString)
    create_new_square(
        state_ptr, pos1[1], pos1[2], pos1[3],
        pos2[1], pos2[2], pos2[3],
        pos3[1], pos3[2], pos3[3],
        pos4[1], pos4[2], pos4[3],
        color)
end

"""
Construct a new pentagon in the Euclid system to be shown on the surface

------

Parameters:

- `state_ptr` : The state of the Euclid application to pass to the API
- `x1`..`z5` : Coordinates for the five pentagon vertices
- `pos1`..`pos5` : Vectors can be provided in [x, y, z] form instead of individual parameters
- `color` : The color to show the pentagon with

Returns: a `BridgeShapePentagon` describing the newly created pentagon
"""
function create_new_pentagon(state_ptr::Ptr{Cvoid},
    x1::Real, y1::Real, z1::Real,
    x2::Real, y2::Real, z2::Real,
    x3::Real, y3::Real, z3::Real,
    x4::Real, y4::Real, z4::Real,
    x5::Real, y5::Real, z5::Real,
    color::BridgeColor)
    pos1 = (Float32(x1), Float32(y1), Float32(z1))
    pos2 = (Float32(x2), Float32(y2), Float32(z2))
    pos3 = (Float32(x3), Float32(y3), Float32(z3))
    pos4 = (Float32(x4), Float32(y4), Float32(z4))
    pos5 = (Float32(x5), Float32(y5), Float32(z5))
    return @ccall create_new_pentagon(
        state_ptr::Ptr{Cvoid},
        pos1::NTuple{3, Cfloat}, pos2::NTuple{3, Cfloat}, pos3::NTuple{3, Cfloat},
        pos4::NTuple{3, Cfloat}, pos5::NTuple{3, Cfloat},
        color::BridgeColor)::BridgeShapePentagon
end
function create_new_pentagon(state_ptr::Ptr{Cvoid},
    pos1::AbstractVector{<:Real}, pos2::AbstractVector{<:Real},
    pos3::AbstractVector{<:Real}, pos4::AbstractVector{<:Real},
    pos5::AbstractVector{<:Real}, color::BridgeColor)
    create_new_pentagon(
        state_ptr,
        pos1[1], pos1[2], pos1[3],
        pos2[1], pos2[2], pos2[3],
        pos3[1], pos3[2], pos3[3],
        pos4[1], pos4[2], pos4[3],
        pos5[1], pos5[2], pos5[3],
        color)
end
function create_new_pentagon(state_ptr::Ptr{Cvoid},
    x1::Real, y1::Real, z1::Real,
    x2::Real, y2::Real, z2::Real,
    x3::Real, y3::Real, z3::Real,
    x4::Real, y4::Real, z4::Real,
    x5::Real, y5::Real, z5::Real,
    color::Colorant)
    create_new_pentagon(
        state_ptr,
        x1, y1, z1,
        x2, y2, z2,
        x3, y3, z3,
        x4, y4, z4,
        x5, y5, z5,
        bridge_color(color))
end
function create_new_pentagon(state_ptr::Ptr{Cvoid},
    pos1::AbstractVector{<:Real}, pos2::AbstractVector{<:Real},
    pos3::AbstractVector{<:Real}, pos4::AbstractVector{<:Real},
    pos5::AbstractVector{<:Real}, color::Colorant)
    create_new_pentagon(
        state_ptr,
        pos1[1], pos1[2], pos1[3],
        pos2[1], pos2[2], pos2[3],
        pos3[1], pos3[2], pos3[3],
        pos4[1], pos4[2], pos4[3],
        pos5[1], pos5[2], pos5[3],
        bridge_color(color))
end
function create_new_pentagon(state_ptr::Ptr{Cvoid},
    x1::Real, y1::Real, z1::Real,
    x2::Real, y2::Real, z2::Real,
    x3::Real, y3::Real, z3::Real,
    x4::Real, y4::Real, z4::Real,
    x5::Real, y5::Real, z5::Real,
    color::Symbol)
    create_new_pentagon(
        state_ptr,
        x1, y1, z1,
        x2, y2, z2,
        x3, y3, z3,
        x4, y4, z4,
        x5, y5, z5,
        bridge_color(color))
end
function create_new_pentagon(state_ptr::Ptr{Cvoid},
    pos1::AbstractVector{<:Real}, pos2::AbstractVector{<:Real},
    pos3::AbstractVector{<:Real}, pos4::AbstractVector{<:Real},
    pos5::AbstractVector{<:Real}, color::Symbol)
    create_new_pentagon(
        state_ptr,
        pos1[1], pos1[2], pos1[3],
        pos2[1], pos2[2], pos2[3],
        pos3[1], pos3[2], pos3[3],
        pos4[1], pos4[2], pos4[3],
        pos5[1], pos5[2], pos5[3],
        bridge_color(color))
end
function create_new_pentagon(state_ptr::Ptr{Cvoid},
    x1::Real, y1::Real, z1::Real,
    x2::Real, y2::Real, z2::Real,
    x3::Real, y3::Real, z3::Real,
    x4::Real, y4::Real, z4::Real,
    x5::Real, y5::Real, z5::Real,
    color::AbstractString)
    create_new_pentagon(
        state_ptr,
        x1, y1, z1,
        x2, y2, z2,
        x3, y3, z3,
        x4, y4, z4,
        x5, y5, z5,
        bridge_color(color))
end
function create_new_pentagon(state_ptr::Ptr{Cvoid},
    pos1::AbstractVector{<:Real}, pos2::AbstractVector{<:Real},
    pos3::AbstractVector{<:Real}, pos4::AbstractVector{<:Real},
    pos5::AbstractVector{<:Real}, color::AbstractString)
    create_new_pentagon(
        state_ptr,
        pos1[1], pos1[2], pos1[3],
        pos2[1], pos2[2], pos2[3],
        pos3[1], pos3[2], pos3[3],
        pos4[1], pos4[2], pos4[3],
        pos5[1], pos5[2], pos5[3],
        bridge_color(color))
end

"""
Get a point in the system according to it's id

------

Parameters:

- `state_ptr` : The state of the Euclid application to pass to the API
- `id` : The id of the point to retrieve

Returns: a `BridgePointView` describing the retrieved point; valid=false if could not retrieve 
"""
function get_point(state_ptr::Ptr{Cvoid}, id::Integer)
    @ccall get_point_view(state_ptr::Ptr{Cvoid}, id::Cint)::BridgePointView
end


"""
Show a point on the surface by point id.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `id` : Point id to make visible
"""
function show_point(state_ptr::Ptr{Cvoid}, id::Integer)
    @ccall show_point(state_ptr::Ptr{Cvoid}, id::Cint)::Cvoid
end
"""
Hide a point on the surface by point id.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `id` : Point id to hide
"""
function hide_point(state_ptr::Ptr{Cvoid}, id::Integer)
    @ccall hide_point(state_ptr::Ptr{Cvoid}, id::Cint)::Cvoid
end
"""
Hide multiple points in a single call. Kicks dust once and emits a burst for
each visible point without re-kicking between them.

------

Parameters:
- `state_ptr` : The Euclid application state pointer passed to the native API
- `ids`       : Collection of point ids to hide (any iterable of Integer)
"""
function hide_point_batch(state_ptr::Ptr{Cvoid}, ids)
    arr = Cint[Cint(id) for id in ids]
    @ccall hide_point_batch(
        state_ptr::Ptr{Cvoid}, arr::Ptr{Cint}, length(arr)::Cint)::Cvoid
end
"""
Update a point position by id.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `id` : Point id to move
- `x` : New x world coordinate
- `y` : New y world coordinate
- `z` : New z world coordinate
- `pos` : A vector can be provided in [x, y, z] form instead of individual parameters
"""
function set_point_position(
    state_ptr::Ptr{Cvoid}, id::Integer, x::Real, y::Real, z::Real)
    pos = (Float32(x), Float32(y), Float32(z))
    @ccall set_point_position(
        state_ptr::Ptr{Cvoid}, id::Cint, pos::NTuple{3, Cfloat})::Cvoid
end
function set_point_position(
    state_ptr::Ptr{Cvoid}, id::Integer, pos::AbstractVector{<:Real})
    postupled = (pos[1], pos[2], pos[3])
    @ccall set_point_position(
        state_ptr::Ptr{Cvoid}, id::Cint, postupled::NTuple{3, Cfloat})::Cvoid
end

"""
Set the rendered brush size for a point by id.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `id` : Point id to update
- `brush_size` : New point brush size
"""
function set_point_brush(state_ptr::Ptr{Cvoid}, id::Integer, brush_size::Real)
    @ccall set_point_brush(state_ptr::Ptr{Cvoid}, id::Cint, brush_size::Cfloat)::Cvoid
end

"""
Set the display color for a point by id.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `id` : Point id to recolor
- `color` : New point color

Accepts `BridgeColor` directly; overloads also accept `Colorant`, `Symbol`, and `AbstractString`.
"""
function set_point_color(state_ptr::Ptr{Cvoid}, id::Integer, color::BridgeColor)
    @ccall set_point_color(state_ptr::Ptr{Cvoid}, id::Cint, color::BridgeColor)::Cvoid
end
function set_point_color(state_ptr::Ptr{Cvoid}, id::Integer, color::Colorant)
    set_point_color(state_ptr, id, bridge_color(color))
end
function set_point_color(state_ptr::Ptr{Cvoid}, id::Integer, color::Symbol)
    set_point_color(state_ptr, id, bridge_color(color))
end
function set_point_color(state_ptr::Ptr{Cvoid}, id::Integer, color::AbstractString)
    set_point_color(state_ptr, id, bridge_color(color))
end

"""
Set the active/selected color for a point by id.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `id` : Point id to update
- `color` : Active state color

Accepts `BridgeColor` directly; overloads also accept `Colorant`, `Symbol`, and `AbstractString`.
"""
function set_point_active_color(state_ptr::Ptr{Cvoid}, id::Integer, color::BridgeColor)
    @ccall set_point_active_color(
        state_ptr::Ptr{Cvoid}, id::Cint, color::BridgeColor)::Cvoid
end
function set_point_active_color(state_ptr::Ptr{Cvoid}, id::Integer, color::Colorant)
    set_point_active_color(state_ptr, id, bridge_color(color))
end
function set_point_active_color(state_ptr::Ptr{Cvoid}, id::Integer, color::Symbol)
    set_point_active_color(state_ptr, id, bridge_color(color))
end
function set_point_active_color(state_ptr::Ptr{Cvoid}, id::Integer, color::AbstractString)
    set_point_active_color(state_ptr, id, bridge_color(color))
end

"""
Get the maximum number of shapes points supported by the bridge.

------

Returns: `Int32` point capacity
"""
function get_point_capacity()
    @ccall get_point_capacity()::Int32
end

"""
Get the next point index in the shapes point system.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API

Returns: `Int32` next point index
"""
function get_point_next_index(state_ptr::Ptr{Cvoid})
    @ccall get_point_next_index(state_ptr::Ptr{Cvoid})::Int32
end

"""
Check whether a point index is in the valid bridge range.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `index` : Point index to validate

Returns: `UInt8` where non-zero means valid
"""
function is_point_index_in_range(state_ptr::Ptr{Cvoid}, index::Integer)
    @ccall is_point_index_in_range(state_ptr::Ptr{Cvoid}, index::Int32)::UInt8
end

"""
Enable or disable point drawing for a point id.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `index` : Point id to update
- `enabled` : `true` to draw, `false` to hide

Returns: `Int32` status code
"""
function set_point_draw_enabled(state_ptr::Ptr{Cvoid}, index::Integer, enabled::Bool)
    @ccall set_point_draw_enabled(state_ptr::Ptr{Cvoid}, index::Int32,
        UInt8(enabled)::UInt8)::Int32
end

"""
Set a point position by id and return bridge status.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `index` : Point id to move
- `x` : New x world coordinate
- `y` : New y world coordinate
- `z` : New z world coordinate
- `pos` : A vector can be provided in [x, y, z] form instead of individual parameters

Returns: `Int32` status code
"""
function set_point_position_status(state_ptr::Ptr{Cvoid}, index::Integer,
    x::Real, y::Real, z::Real)
    pos = (Float32(x), Float32(y), Float32(z))
    @ccall set_point_position_status(state_ptr::Ptr{Cvoid}, index::Int32,
        pos::NTuple{3, Cfloat})::Int32
end
function set_point_position_status(state_ptr::Ptr{Cvoid}, index::Integer,
    pos::AbstractVector{<:Real})
    postupled = (pos[1], pos[2], pos[3])
    @ccall set_point_position_status(state_ptr::Ptr{Cvoid}, index::Int32,
        postupled::NTuple{3, Cfloat})::Int32
end

"""
Clear a point position by id.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `index` : Point id to clear position for

Returns: `Int32` status code
"""
function clear_point_position(state_ptr::Ptr{Cvoid}, index::Integer)
    @ccall clear_point_position(state_ptr::Ptr{Cvoid}, index::Int32)::Int32
end

"""
Set the display color for a point by id and return bridge status.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `index` : Point id to recolor
- `color` : New point color

Accepts `BridgeColor` directly; overloads also accept `Colorant`, `Symbol`, and `AbstractString`.

Returns: `Int32` status code
"""
function set_point_color_status(state_ptr::Ptr{Cvoid}, index::Integer, color::BridgeColor)
    @ccall set_point_color_status(
        state_ptr::Ptr{Cvoid}, index::Int32, color::BridgeColor)::Int32
end
function set_point_color_status(state_ptr::Ptr{Cvoid}, index::Integer, color::Colorant)
    set_point_color_status(state_ptr, index, bridge_color(color))
end
function set_point_color_status(state_ptr::Ptr{Cvoid}, index::Integer, color::Symbol)
    set_point_color_status(state_ptr, index, bridge_color(color))
end
function set_point_color_status(
    state_ptr::Ptr{Cvoid}, index::Integer, color::AbstractString)
    set_point_color_status(state_ptr, index, bridge_color(color))
end

"""
Clear the display color for a point by id.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `index` : Point id to clear color for

Returns: `Int32` status code
"""
function clear_point_color(state_ptr::Ptr{Cvoid}, index::Integer)
    @ccall clear_point_color(state_ptr::Ptr{Cvoid}, index::Int32)::Int32
end

"""
Set the active/selected color for a point by id and return bridge status.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `index` : Point id to update
- `color` : Active state color

Accepts `BridgeColor` directly; overloads also accept `Colorant`, `Symbol`, and `AbstractString`.

Returns: `Int32` status code
"""
function set_point_active_color_status(
    state_ptr::Ptr{Cvoid}, index::Integer, color::BridgeColor)
    @ccall set_point_active_color_status(
        state_ptr::Ptr{Cvoid}, index::Int32, color::BridgeColor)::Int32
end
function set_point_active_color_status(
    state_ptr::Ptr{Cvoid}, index::Integer, color::Colorant)
    set_point_active_color_status(state_ptr, index, bridge_color(color))
end
function set_point_active_color_status(
    state_ptr::Ptr{Cvoid}, index::Integer, color::Symbol)
    set_point_active_color_status(state_ptr, index, bridge_color(color))
end
function set_point_active_color_status(
    state_ptr::Ptr{Cvoid}, index::Integer, color::AbstractString)
    set_point_active_color_status(state_ptr, index, bridge_color(color))
end

"""
Clear the active/selected color for a point by id.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `index` : Point id to clear active color for

Returns: `Int32` status code
"""
function clear_point_active_color(state_ptr::Ptr{Cvoid}, index::Integer)
    @ccall clear_point_active_color(state_ptr::Ptr{Cvoid}, index::Int32)::Int32
end

"""
Set brush size for a point by id and return bridge status.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `index` : Point id to update
- `brush` : New brush size

Returns: `Int32` status code
"""
function set_point_brush_size(state_ptr::Ptr{Cvoid}, index::Integer, brush::Real)
    @ccall set_point_brush_size(state_ptr::Ptr{Cvoid}, index::Int32, brush::Cfloat)::Int32
end

"""
Set offset for a point by id and return bridge status.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `index` : Point id to update
- `offset` : New offset

Returns: `Int32` status code
"""
function set_point_offset(state_ptr::Ptr{Cvoid}, index::Integer, offset::Real)
    @ccall set_point_offset(state_ptr::Ptr{Cvoid}, index::Int32, offset::Cfloat)::Int32
end

"""
Attach a child point to a parent point chain.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `parent_index` : Parent point id
- `child_index` : Child point id to append

Returns: `Int32` status code
"""
function attach_child_point(
    state_ptr::Ptr{Cvoid}, parent_index::Integer, child_index::Integer)
    @ccall attach_child_point(
        state_ptr::Ptr{Cvoid}, parent_index::Int32, child_index::Int32)::Int32
end

"""
Detach a child point from a parent point chain.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `parent_index` : Parent point id
- `child_index` : Child point id to remove

Returns: `Int32` status code
"""
function detach_child_point(
    state_ptr::Ptr{Cvoid}, parent_index::Integer, child_index::Integer)
    @ccall detach_child_point(
        state_ptr::Ptr{Cvoid}, parent_index::Int32, child_index::Int32)::Int32
end

"""
Recompute and store child count for a parent point chain.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `parent_index` : Parent point id

Returns: `Int32` status code
"""
function rebuild_child_count(state_ptr::Ptr{Cvoid}, parent_index::Integer)
    @ccall rebuild_child_count(state_ptr::Ptr{Cvoid}, parent_index::Int32)::Int32
end

"""
Validate a parent point child chain for bridge graph consistency.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `parent_index` : Parent point id

Returns: `Int32` status code
"""
function validate_parent_child_chain(state_ptr::Ptr{Cvoid}, parent_index::Integer)
    @ccall validate_parent_child_chain(state_ptr::Ptr{Cvoid}, parent_index::Int32)::Int32
end

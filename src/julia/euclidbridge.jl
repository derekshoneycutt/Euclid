module EuclidBridge

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

struct BridgeConstraintView
    valid::UInt8
    index::Int32

    traits::Int32
    onPoint::Int32
    restriction::NTuple{3, Cfloat}
    bounce::Cfloat
    allowance::Cfloat
    dependOn::Int32
    hasChildOffset::UInt8
    childOffset::Int32
    doApply::UInt8
end

struct BridgeConstraintSpec
    traits::Int32
    onPoint::Int32
    restriction::NTuple{3, Cfloat}
    bounce::Cfloat
    allowance::Cfloat
    dependOn::Int32
    hasChildOffset::UInt8
    childOffset::Int32
    doApply::UInt8
end

struct BridgeSolveResult
    status::Int32
    iterations::Int32
    initialError::Cfloat
    finalError::Cfloat
    converged::UInt8
end

const BRIDGE_STATUS_OK = Int32(0)
const BRIDGE_STATUS_INVALID_INDEX = Int32(1)
const BRIDGE_STATUS_INVALID_ARGUMENT = Int32(2)
const BRIDGE_STATUS_INVALID_GRAPH = Int32(3)
const BRIDGE_STATUS_INVALID_CONSTRAINT = Int32(4)
const BRIDGE_STATUS_OUT_OF_CAPACITY = Int32(5)
const BRIDGE_STATUS_ILLEGAL_STATE = Int32(6)
const BRIDGE_STATUS_NON_CONVERGED = Int32(7)

const CONSTRAINT_SPEC_TRAITS = Int32(1 << 0)
const CONSTRAINT_SPEC_ONPOINT = Int32(1 << 1)
const CONSTRAINT_SPEC_RESTRICTION = Int32(1 << 2)
const CONSTRAINT_SPEC_BOUNCE = Int32(1 << 3)
const CONSTRAINT_SPEC_ALLOWANCE = Int32(1 << 4)
const CONSTRAINT_SPEC_DEPENDON = Int32(1 << 5)
const CONSTRAINT_SPEC_CHILDOFFSET = Int32(1 << 6)
const CONSTRAINT_SPEC_DOAPPLY = Int32(1 << 7)

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

struct BridgeShapeFilledCircle
    hostId::Int64
    startId::Int64
    endId::Int64
end

struct BridgeShapeTriangle
    hostId::Int64
    joint1Id::Int64
    joint2Id::Int64
    joint3Id::Int64
end

struct BridgeShapeSquare
    hostId::Int64
    joint1Id::Int64
    joint2Id::Int64
    joint3Id::Int64
    joint4Id::Int64
end

struct BridgeShapePen
    hostId::Int64
    joint1Id::Int64
    joint2Id::Int64

    lengthConstraintId::Int64
    point1FloorId::Int64
    point2FloorId::Int64
    lockPoint1Id::Int64
    lockPoint2Id::Int64
end

struct BridgeShapeCompass
    hostId::Int64
    joint1Id::Int64
    pivotId::Int64
    joint2Id::Int64

    centerPivotId::Int64
    limb1LengthId::Int64
    limb2LengthId::Int64
    point1FloorId::Int64
    pivotFloorId::Int64
    point2FloorId::Int64
    lockPoint1Id::Int64
    lockPoint2Id::Int64
end

"""
Construct a new BridgeColor from standard Julia color types

--------

Takes in a Julia color and returns `BridgeColor`
"""
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

"""
Set the null animation for the application

---------

Parameters:

- `state_ptr` : The state of the Euclid application to pass to the API
- `getViewText` : A function that should be called to retrieve the view text for the animation
- `init` : A function that should be called when the animation is being initialized
- `loop` : A function that should be called when the animation is processing a frame of the loop
- `clean` : A function that should be called when the animation is being cleaned and ended
"""
function set_null_animations(
    state_ptr::Ptr{Cvoid}, getViewText, init, loop, clean)

    @ccall set_null_animations(state_ptr::Ptr{Cvoid},
        getViewText::Any, init::Any, loop::Any, clean::Any)::Cvoid
end

"""
Add a new root animation for the application

---------

Parameters:

- `state_ptr` : The state of the Euclid application to pass to the API
- `getViewText` : A function that should be called to retrieve the view text for the animation
- `init` : A function that should be called when the animation is being initialized
- `loop` : A function that should be called when the animation is processing a frame of the loop
- `clean` : A function that should be called when the animation is being cleaned and ended
- `name` : The name of the animation to show in the tree

Returns the index of the new root animation
"""
function add_root_animation_interface(
    state_ptr::Ptr{Cvoid}, getViewText, init, loop, clean, name::String)

    @ccall add_root_animation_interface(
        state_ptr::Ptr{Cvoid}, getViewText::Any, init::Any, loop::Any, clean::Any,
        name::Cstring)::Int64
end


"""
Add a new child animation for the application

---------

Parameters:

- `state_ptr` : The state of the Euclid application to pass to the API
- `getViewText` : A function that should be called to retrieve the view text for the animation
- `init` : A function that should be called when the animation is being initialized
- `loop` : A function that should be called when the animation is processing a frame of the loop
- `clean` : A function that should be called when the animation is being cleaned and ended
- `name` : The name of the animation to show in the tree
- `parentId` : The index of the parent animation to place the child under in the tree

Returns the index of the new child animation
"""
function add_child_animation_interface(
    state_ptr::Ptr{Cvoid}, getViewText, init, loop, clean, name::String, parentId::Integer)

    @ccall add_child_animation_interface(
        state_ptr::Ptr{Cvoid}, getViewText::Any, init::Any, loop::Any, clean::Any,
        name::Cstring, parentId::Int64)::Int64
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
- `brushSize` : The size of the point to show

Returns: a `BridgePointView` describing the newly created point
"""
function create_new_point(state_ptr::Ptr{Cvoid},
    x::Float32, y::Float32, z::Float32,
    color::BridgeColor, brushSize::Float32)
    pos = (x, y, z)
    return @ccall create_new_point(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat},
        color::BridgeColor, brushSize::Cfloat)::BridgePointView
end
function create_new_point(state_ptr::Ptr{Cvoid},
    pos::Vector{Float32},
    color::BridgeColor, brushSize::Float32)
    create_new_point(state_ptr, pos[1], pos[2], pos[3], color, brushSize)
end
function create_new_point(state_ptr::Ptr{Cvoid},
    x::Float32, y::Float32, z::Float32,
    color::Colorant, brushSize::Float32)
    create_new_point(state_ptr, x, y, z, bridge_color(color), brushSize)
end
function create_new_point(state_ptr::Ptr{Cvoid},
    pos::Vector{Float32},
    color::Colorant, brushSize::Float32)
    create_new_point(state_ptr, pos[1], pos[2], pos[3], bridge_color(color), brushSize)
end
function create_new_point(state_ptr::Ptr{Cvoid},
    x::Float32, y::Float32, z::Float32,
    color::Symbol, brushSize::Float32)
    create_new_point(state_ptr, x, y, z, bridge_color(color), brushSize)
end
function create_new_point(state_ptr::Ptr{Cvoid},
    pos::Vector{Float32},
    color::Symbol, brushSize::Float32)
    create_new_point(state_ptr, pos[1], pos[2], pos[3], bridge_color(color), brushSize)
end
function create_new_point(state_ptr::Ptr{Cvoid},
    x::Float32, y::Float32, z::Float32,
    color::AbstractString, brushSize::Float32)
    create_new_point(state_ptr, x, y, z, bridge_color(color), brushSize)
end
function create_new_point(state_ptr::Ptr{Cvoid},
    pos::Vector{Float32},
    color::AbstractString, brushSize::Float32)
    create_new_point(state_ptr, pos[1], pos[2], pos[3], bridge_color(color), brushSize)
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
- `brushSize` : The size of the line to show

Returns: a `BridgeShapeLine` describing the newly created line
"""
function create_new_line(state_ptr::Ptr{Cvoid},
    x1::Float32, y1::Float32, z1::Float32,
    x2::Float32, y2::Float32, z2::Float32,
    color::BridgeColor, brushSize::Float32)
    pos1 = (x1, y1, z1)
    pos2 = (x2, y2, z2)
    return @ccall create_new_line(state_ptr::Ptr{Cvoid}, pos1::NTuple{3, Cfloat},
        pos2::NTuple{3, Cfloat}, color::BridgeColor, brushSize::Cfloat)::BridgeShapeLine
end
function create_new_line(state_ptr::Ptr{Cvoid},
    pos1::Vector{Float32}, pos2::Vector{Float32},
    color::BridgeColor, brushSize::Float32)
    create_new_line(state_ptr, pos1[1], pos1[2], pos1[3], pos2[1], pos2[2], pos2[3], color, brushSize)
end
function create_new_line(state_ptr::Ptr{Cvoid},
    x1::Float32, y1::Float32, z1::Float32,
    x2::Float32, y2::Float32, z2::Float32,
    color::Colorant, brushSize::Float32)
    create_new_line(state_ptr, x1, y1, z1, x2, y2, z2, bridge_color(color), brushSize)
end
function create_new_line(state_ptr::Ptr{Cvoid},
    pos1::Vector{Float32}, pos2::Vector{Float32},
    color::Colorant, brushSize::Float32)
    create_new_line(state_ptr, pos1[1], pos1[2], pos1[3], pos2[1], pos2[2], pos2[3], bridge_color(color), brushSize)
end
function create_new_line(state_ptr::Ptr{Cvoid},
    x1::Float32, y1::Float32, z1::Float32,
    x2::Float32, y2::Float32, z2::Float32,
    color::Symbol, brushSize::Float32)
    create_new_line(state_ptr, x1, y1, z1, x2, y2, z2, bridge_color(color), brushSize)
end
function create_new_line(state_ptr::Ptr{Cvoid},
    pos1::Vector{Float32}, pos2::Vector{Float32},
    color::Symbol, brushSize::Float32)
    create_new_line(state_ptr, pos1[1], pos1[2], pos1[3], pos2[1], pos2[2], pos2[3], bridge_color(color), brushSize)
end
function create_new_line(state_ptr::Ptr{Cvoid},
    x1::Float32, y1::Float32, z1::Float32,
    x2::Float32, y2::Float32, z2::Float32,
    color::AbstractString, brushSize::Float32)
    create_new_line(state_ptr, x1, y1, z1, x2, y2, z2, bridge_color(color), brushSize)
end
function create_new_line(state_ptr::Ptr{Cvoid},
    pos1::Vector{Float32}, pos2::Vector{Float32},
    color::AbstractString, brushSize::Float32)
    create_new_line(state_ptr, pos1[1], pos1[2], pos1[3], pos2[1], pos2[2], pos2[3], bridge_color(color), brushSize)
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
- `startθ` : The starting angle in radians of the circle to draw
- `endθ` : The ending angle in radians of the circle to draw
- `color` : The color to show the circle with
- `brushSize` : The size of the circle to show

Returns: a `BridgeShapeCircle` describing the newly created circle
"""
function create_new_circle(state_ptr::Ptr{Cvoid},
    x::Float32, y::Float32, z::Float32,
    radius::Float32, startθ::Float32, endθ::Float32,
    color::BridgeColor, brushSize::Float32)
    pos = (x, y, z)
    return @ccall create_new_circle(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat},
        radius::Cfloat, startθ::Cfloat, endθ::Cfloat,
        color::BridgeColor, brushSize::Cfloat)::BridgeShapeCircle
end
function create_new_circle(state_ptr::Ptr{Cvoid},
    center::Vector{Float32},
    radius::Float32, startθ::Float32, endθ::Float32,
    color::BridgeColor, brushSize::Float32)
    create_new_circle(state_ptr, center[1], center[2], center[3], radius, startθ, endθ, color, brushSize)
end
function create_new_circle(state_ptr::Ptr{Cvoid},
    x::Float32, y::Float32, z::Float32,
    radius::Float32, startθ::Float32, endθ::Float32,
    color::Colorant, brushSize::Float32)
    create_new_circle(state_ptr, x, y, z, radius, startθ, endθ, bridge_color(color), brushSize)
end
function create_new_circle(state_ptr::Ptr{Cvoid},
    center::Vector{Float32},
    radius::Float32, startθ::Float32, endθ::Float32,
    color::Colorant, brushSize::Float32)
    create_new_circle(state_ptr, center[1], center[2], center[3], radius, startθ, endθ, bridge_color(color), brushSize)
end
function create_new_circle(state_ptr::Ptr{Cvoid},
    x::Float32, y::Float32, z::Float32,
    radius::Float32, startθ::Float32, endθ::Float32,
    color::Symbol, brushSize::Float32)
    create_new_circle(state_ptr, x, y, z, radius, startθ, endθ, bridge_color(color), brushSize)
end
function create_new_circle(state_ptr::Ptr{Cvoid},
    center::Vector{Float32},
    radius::Float32, startθ::Float32, endθ::Float32,
    color::Symbol, brushSize::Float32)
    create_new_circle(state_ptr, center[1], center[2], center[3], radius, startθ, endθ, bridge_color(color), brushSize)
end
function create_new_circle(state_ptr::Ptr{Cvoid},
    x::Float32, y::Float32, z::Float32,
    radius::Float32, startθ::Float32, endθ::Float32,
    color::AbstractString, brushSize::Float32)
    create_new_circle(state_ptr, x, y, z, radius, startθ, endθ, bridge_color(color), brushSize)
end
function create_new_circle(state_ptr::Ptr{Cvoid},
    center::Vector{Float32},
    radius::Float32, startθ::Float32, endθ::Float32,
    color::AbstractString, brushSize::Float32)
    create_new_circle(state_ptr, center[1], center[2], center[3], radius, startθ, endθ, bridge_color(color), brushSize)
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
- `startθ` : The starting angle in radians of the circle to draw
- `endθ` : The ending angle in radians of the circle to draw
- `color` : The color to show the circle with
- `brushSize` : The size of the circle to show

Returns: a `BridgeShapeCircle` describing the newly created circle
"""
function create_new_filledcircle(state_ptr::Ptr{Cvoid},
    x::Float32, y::Float32, z::Float32,
    radius::Float32, startθ::Float32, endθ::Float32,
    color::BridgeColor, brushSize::Float32)
    pos = (x, y, z)
    return @ccall create_new_filledcircle(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat},
        radius::Cfloat, startθ::Cfloat, endθ::Cfloat,
        color::BridgeColor, brushSize::Cfloat)::BridgeShapeFilledCircle
end
function create_new_filledcircle(state_ptr::Ptr{Cvoid},
    center::Vector{Float32},
    radius::Float32, startθ::Float32, endθ::Float32,
    color::BridgeColor, brushSize::Float32)
    create_new_filledcircle(state_ptr, center[1], center[2], center[3], radius, startθ, endθ, color, brushSize)
end
function create_new_filledcircle(state_ptr::Ptr{Cvoid},
    x::Float32, y::Float32, z::Float32,
    radius::Float32, startθ::Float32, endθ::Float32,
    color::Colorant, brushSize::Float32)
    create_new_filledcircle(state_ptr, x, y, z, radius, startθ, endθ, bridge_color(color), brushSize)
end
function create_new_filledcircle(state_ptr::Ptr{Cvoid},
    center::Vector{Float32},
    radius::Float32, startθ::Float32, endθ::Float32,
    color::Colorant, brushSize::Float32)
    create_new_filledcircle(state_ptr, center[1], center[2], center[3], radius,
        startθ, endθ, bridge_color(color), brushSize)
end
function create_new_filledcircle(state_ptr::Ptr{Cvoid},
    x::Float32, y::Float32, z::Float32,
    radius::Float32, startθ::Float32, endθ::Float32,
    color::Symbol, brushSize::Float32)
    create_new_filledcircle(state_ptr, x, y, z, radius, startθ, endθ, bridge_color(color), brushSize)
end
function create_new_filledcircle(state_ptr::Ptr{Cvoid},
    center::Vector{Float32},
    radius::Float32, startθ::Float32, endθ::Float32,
    color::Symbol, brushSize::Float32)
    create_new_filledcircle(state_ptr, center[1], center[2], center[3], radius,
        startθ, endθ, bridge_color(color), brushSize)
end
function create_new_filledcircle(state_ptr::Ptr{Cvoid},
    x::Float32, y::Float32, z::Float32,
    radius::Float32, startθ::Float32, endθ::Float32,
    color::AbstractString, brushSize::Float32)
    create_new_filledcircle(state_ptr, x, y, z, radius, startθ, endθ, bridge_color(color), brushSize)
end
function create_new_filledcircle(state_ptr::Ptr{Cvoid},
    center::Vector{Float32},
    radius::Float32, startθ::Float32, endθ::Float32,
    color::Symbol, brushSize::Float32)
    create_new_filledcircle(state_ptr, center[1], center[2], center[3], radius,
        startθ, endθ, bridge_color(color), brushSize)
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
    x1::Float32, y1::Float32, z1::Float32,
    x2::Float32, y2::Float32, z2::Float32,
    x3::Float32, y3::Float32, z3::Float32,
    color::BridgeColor)
    pos1 = (x1, y1, z1)
    pos2 = (x2, y2, z2)
    pos3 = (x3, y3, z3)
    return @ccall create_new_triangle(
        state_ptr::Ptr{Cvoid}, pos1::NTuple{3, Cfloat},
        pos2::NTuple{3, Cfloat}, pos3::NTuple{3, Cfloat},
        color::BridgeColor)::BridgeShapeTriangle
end
function create_new_triangle(state_ptr::Ptr{Cvoid},
    pos1::Vector{Float32}, pos2::Vector{Float32}, pos3::Vector{Float32},
    color::BridgeColor)
    create_new_triangle(
        state_ptr, pos1[1], pos1[2], pos1[3],
        pos2[1], pos2[2], pos2[3],
        pos3[1], pos3[2], pos3[3],
        color)
end
function create_new_triangle(state_ptr::Ptr{Cvoid},
    x1::Float32, y1::Float32, z1::Float32,
    x2::Float32, y2::Float32, z2::Float32,
    x3::Float32, y3::Float32, z3::Float32,
    color::Colorant)
    create_new_triangle(state_ptr, x1, y1, z1, x2, y2, z2, x3, y3, z3, bridge_color(color))
end
function create_new_triangle(state_ptr::Ptr{Cvoid},
    pos1::Vector{Float32}, pos2::Vector{Float32}, pos3::Vector{Float32},
    color::Colorant)
    create_new_triangle(
        state_ptr, pos1[1], pos1[2], pos1[3],
        pos2[1], pos2[2], pos2[3],
        pos3[1], pos3[2], pos3[3],
        bridge_color(color))
end
function create_new_triangle(state_ptr::Ptr{Cvoid},
    x1::Float32, y1::Float32, z1::Float32,
    x2::Float32, y2::Float32, z2::Float32,
    x3::Float32, y3::Float32, z3::Float32,
    color::Symbol)
    create_new_triangle(state_ptr, x1, y1, z1, x2, y2, z2, x3, y3, z3, bridge_color(color))
end
function create_new_triangle(state_ptr::Ptr{Cvoid},
    pos1::Vector{Float32}, pos2::Vector{Float32}, pos3::Vector{Float32},
    color::Symbol)
    create_new_triangle(
        state_ptr, pos1[1], pos1[2], pos1[3],
        pos2[1], pos2[2], pos2[3],
        pos3[1], pos3[2], pos3[3],
        bridge_color(color))
end
function create_new_triangle(state_ptr::Ptr{Cvoid},
    x1::Float32, y1::Float32, z1::Float32,
    x2::Float32, y2::Float32, z2::Float32,
    x3::Float32, y3::Float32, z3::Float32,
    color::AbstractString)
    create_new_triangle(state_ptr, x1, y1, z1, x2, y2, z2, x3, y3, z3, bridge_color(color))
end
function create_new_triangle(state_ptr::Ptr{Cvoid},
    pos1::Vector{Float32}, pos2::Vector{Float32}, pos3::Vector{Float32},
    color::AbstractString)
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
    x1::Float32, y1::Float32, z1::Float32,
    x2::Float32, y2::Float32, z2::Float32,
    x3::Float32, y3::Float32, z3::Float32,
    x4::Float32, y4::Float32, z4::Float32,
    color::BridgeColor)
    pos1 = (x1, y1, z1)
    pos2 = (x2, y2, z2)
    pos3 = (x3, y3, z3)
    pos4 = (x4, y4, z4)
    return @ccall create_new_square(
        state_ptr::Ptr{Cvoid}, pos1::NTuple{3, Cfloat},
        pos2::NTuple{3, Cfloat}, pos3::NTuple{3, Cfloat}, pos4::NTuple{3, Cfloat},
        color::BridgeColor)::BridgeShapeSquare
end
function create_new_square(state_ptr::Ptr{Cvoid},
    pos1::Vector{Float32}, pos2::Vector{Float32}, pos3::Vector{Float32}, pos4::Vector{Float32},
    color::BridgeColor)
    create_new_square(
        state_ptr, pos1[1], pos1[2], pos1[3],
        pos2[1], pos2[2], pos2[3],
        pos3[1], pos3[2], pos3[3],
        pos4[1], pos4[2], pos4[3],
        color)
end
function create_new_square(state_ptr::Ptr{Cvoid},
    x1::Float32, y1::Float32, z1::Float32,
    x2::Float32, y2::Float32, z2::Float32,
    x3::Float32, y3::Float32, z3::Float32,
    x4::Float32, y4::Float32, z4::Float32,
    color::Colorant)
    create_new_square(
        state_ptr, x1, y1, z1,
        x2, y2, z2,
        x3, y3, z3,
        x4, y4, z4,
        bridge_color(color))
end
function create_new_square(state_ptr::Ptr{Cvoid},
    pos1::Vector{Float32}, pos2::Vector{Float32}, pos3::Vector{Float32}, pos4::Vector{Float32},
    color::Colorant)
    create_new_square(
        state_ptr, pos1[1], pos1[2], pos1[3],
        pos2[1], pos2[2], pos2[3],
        pos3[1], pos3[2], pos3[3],
        pos4[1], pos4[2], pos4[3],
        bridge_color(color))
end
function create_new_square(state_ptr::Ptr{Cvoid},
    x1::Float32, y1::Float32, z1::Float32,
    x2::Float32, y2::Float32, z2::Float32,
    x3::Float32, y3::Float32, z3::Float32,
    x4::Float32, y4::Float32, z4::Float32,
    color::Symbol)
    create_new_square(
        state_ptr, x1, y1, z1,
        x2, y2, z2,
        x3, y3, z3,
        x4, y4, z4,
        bridge_color(color))
end
function create_new_square(state_ptr::Ptr{Cvoid},
    pos1::Vector{Float32}, pos2::Vector{Float32}, pos3::Vector{Float32}, pos4::Vector{Float32},
    color::Symbol)
    create_new_square(
        state_ptr, pos1[1], pos1[2], pos1[3],
        pos2[1], pos2[2], pos2[3],
        pos3[1], pos3[2], pos3[3],
        pos4[1], pos4[2], pos4[3],
        color)
end
function create_new_square(state_ptr::Ptr{Cvoid},
    x1::Float32, y1::Float32, z1::Float32,
    x2::Float32, y2::Float32, z2::Float32,
    x3::Float32, y3::Float32, z3::Float32,
    x4::Float32, y4::Float32, z4::Float32,
    color::AbstractString)
    create_new_square(
        state_ptr, x1, y1, z1,
        x2, y2, z2,
        x3, y3, z3,
        x4, y4, z4,
        bridge_color(color))
end
function create_new_square(state_ptr::Ptr{Cvoid},
    pos1::Vector{Float32}, pos2::Vector{Float32}, pos3::Vector{Float32}, pos4::Vector{Float32},
    color::AbstractString)
    create_new_square(
        state_ptr, pos1[1], pos1[2], pos1[3],
        pos2[1], pos2[2], pos2[3],
        pos3[1], pos3[2], pos3[3],
        pos4[1], pos4[2], pos4[3],
        color)
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
    state_ptr::Ptr{Cvoid}, id::Integer, x::Float32, y::Float32, z::Float32)
    pos = (x, y, z)
    @ccall set_point_position(state_ptr::Ptr{Cvoid}, id::Cint, pos::NTuple{3, Cfloat})::Cvoid
end
function set_point_position(
    state_ptr::Ptr{Cvoid}, id::Integer, pos::Vector{Float32})
    postupled = (pos[1], pos[2], pos[3])
    @ccall set_point_position(state_ptr::Ptr{Cvoid}, id::Cint, postupled::NTuple{3, Cfloat})::Cvoid
end

"""
Set the rendered brush size for a point by id.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `id` : Point id to update
- `brushSize` : New point brush size
"""
function set_point_brush(state_ptr::Ptr{Cvoid}, id::Integer, brushSize::Float32)
    @ccall set_point_brush(state_ptr::Ptr{Cvoid}, id::Cint, brushSize::Cfloat)::Cvoid
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
    @ccall set_point_active_color(state_ptr::Ptr{Cvoid}, id::Cint, color::BridgeColor)::Cvoid
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

"""
Get the maximum number of kine points supported by the bridge.

------

Returns: `Int32` point capacity
"""
function get_point_capacity()
    @ccall get_point_capacity()::Int32
end

"""
Get the next point index in the kine point system.

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
    @ccall set_point_draw_enabled(state_ptr::Ptr{Cvoid}, index::Int32, UInt8(enabled)::UInt8)::Int32
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
    x::Float32, y::Float32, z::Float32)
    pos = (x, y, z)
    @ccall set_point_position_status(state_ptr::Ptr{Cvoid}, index::Int32, pos::NTuple{3, Cfloat})::Int32
end
function set_point_position_status(state_ptr::Ptr{Cvoid}, index::Integer, pos::Vector{Float32})
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
    @ccall set_point_color_status(state_ptr::Ptr{Cvoid}, index::Int32, color::BridgeColor)::Int32
end
function set_point_color_status(state_ptr::Ptr{Cvoid}, index::Integer, color::Colorant)
    set_point_color_status(state_ptr, index, bridge_color(color))
end
function set_point_color_status(state_ptr::Ptr{Cvoid}, index::Integer, color::Symbol)
    set_point_color_status(state_ptr, index, bridge_color(color))
end
function set_point_color_status(state_ptr::Ptr{Cvoid}, index::Integer, color::AbstractString)
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
function set_point_active_color_status(state_ptr::Ptr{Cvoid}, index::Integer, color::BridgeColor)
    @ccall set_point_active_color_status(state_ptr::Ptr{Cvoid}, index::Int32, color::BridgeColor)::Int32
end
function set_point_active_color_status(state_ptr::Ptr{Cvoid}, index::Integer, color::Colorant)
    set_point_active_color_status(state_ptr, index, bridge_color(color))
end
function set_point_active_color_status(state_ptr::Ptr{Cvoid}, index::Integer, color::Symbol)
    set_point_active_color_status(state_ptr, index, bridge_color(color))
end
function set_point_active_color_status(state_ptr::Ptr{Cvoid}, index::Integer, color::AbstractString)
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
function set_point_brush_size(state_ptr::Ptr{Cvoid}, index::Integer, brush::Float32)
    @ccall set_point_brush_size(state_ptr::Ptr{Cvoid}, index::Int32, brush::Cfloat)::Int32
end

"""
Attach a child point to a parent point chain.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `parentIndex` : Parent point id
- `childIndex` : Child point id to append

Returns: `Int32` status code
"""
function attach_child_point(state_ptr::Ptr{Cvoid}, parentIndex::Integer, childIndex::Integer)
    @ccall attach_child_point(state_ptr::Ptr{Cvoid}, parentIndex::Int32, childIndex::Int32)::Int32
end

"""
Detach a child point from a parent point chain.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `parentIndex` : Parent point id
- `childIndex` : Child point id to remove

Returns: `Int32` status code
"""
function detach_child_point(state_ptr::Ptr{Cvoid}, parentIndex::Integer, childIndex::Integer)
    @ccall detach_child_point(state_ptr::Ptr{Cvoid}, parentIndex::Int32, childIndex::Int32)::Int32
end

"""
Recompute and store child count for a parent point chain.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `parentIndex` : Parent point id

Returns: `Int32` status code
"""
function rebuild_child_count(state_ptr::Ptr{Cvoid}, parentIndex::Integer)
    @ccall rebuild_child_count(state_ptr::Ptr{Cvoid}, parentIndex::Int32)::Int32
end

"""
Validate a parent point child chain for bridge graph consistency.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `parentIndex` : Parent point id

Returns: `Int32` status code
"""
function validate_parent_child_chain(state_ptr::Ptr{Cvoid}, parentIndex::Integer)
    @ccall validate_parent_child_chain(state_ptr::Ptr{Cvoid}, parentIndex::Int32)::Int32
end

"""
Get the maximum number of kine constraints supported by the bridge.

------

Returns: `Int32` constraint capacity
"""
function get_constraint_capacity()
    @ccall get_constraint_capacity()::Int32
end

"""
Get the next constraint index in the kine constraint system.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API

Returns: `Int32` next constraint index
"""
function get_constraint_next_index(state_ptr::Ptr{Cvoid})
    @ccall get_constraint_next_index(state_ptr::Ptr{Cvoid})::Int32
end

"""
Check whether a constraint index is in the valid bridge range.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `index` : Constraint index to validate

Returns: `UInt8` where non-zero means valid
"""
function is_constraint_index_in_range(state_ptr::Ptr{Cvoid}, index::Integer)
    @ccall is_constraint_index_in_range(state_ptr::Ptr{Cvoid}, index::Int32)::UInt8
end

"""
Get one constraint view by id.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `index` : Constraint id to retrieve

Returns: `BridgeConstraintView`
"""
function get_constraint_view(state_ptr::Ptr{Cvoid}, index::Integer)
    @ccall get_constraint_view(state_ptr::Ptr{Cvoid}, index::Int32)::BridgeConstraintView
end

"""
Create a new constraint from a bridge constraint spec.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `spec` : Constraint specification payload

Returns: `(status::Int32, index::Int32)` where index is -1 on failure
"""
function create_constraint(state_ptr::Ptr{Cvoid}, spec::BridgeConstraintSpec)
    outIndex = Ref{Int32}(-1)
    status = @ccall create_constraint(state_ptr::Ptr{Cvoid}, spec::BridgeConstraintSpec,
        outIndex::Ref{Int32})::Int32
    return status, outIndex[]
end

"""
Update selected fields on an existing constraint.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `index` : Constraint id to update
- `specMask` : Field selection mask using `CONSTRAINT_SPEC_*` constants
- `spec` : Source values for fields selected in `specMask`

Returns: `Int32` status code
"""
function update_constraint(state_ptr::Ptr{Cvoid}, index::Integer,
    specMask::Integer, spec::BridgeConstraintSpec)
    @ccall update_constraint(state_ptr::Ptr{Cvoid}, index::Int32,
        Int32(specMask)::Int32, spec::BridgeConstraintSpec)::Int32
end

"""
Enable or disable a constraint by id.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `index` : Constraint id to update
- `enabled` : `true` to apply constraint, `false` to disable

Returns: `Int32` status code
"""
function set_constraint_enabled(state_ptr::Ptr{Cvoid}, index::Integer, enabled::Bool)
    @ccall set_constraint_enabled(state_ptr::Ptr{Cvoid}, index::Int32, UInt8(enabled)::UInt8)::Int32
end

"""
Clear one constraint slot by id.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `index` : Constraint id to clear

Returns: `Int32` status code
"""
function clear_constraint(state_ptr::Ptr{Cvoid}, index::Integer)
    @ccall clear_constraint(state_ptr::Ptr{Cvoid}, index::Int32)::Int32
end

"""
Get total current constraint error across the point system.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API

Returns: `Cfloat` total error
"""
function get_total_constraint_error_bridge(state_ptr::Ptr{Cvoid})
    @ccall get_total_constraint_error_bridge(state_ptr::Ptr{Cvoid})::Cfloat
end

"""
Get the current error value for one constraint.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `constraintIndex` : Constraint id to inspect

Returns: `(status::Int32, error::Cfloat)`
"""
function get_constraint_error_bridge(state_ptr::Ptr{Cvoid}, constraintIndex::Integer)
    outError = Ref{Cfloat}(0)
    status = @ccall get_constraint_error_bridge(state_ptr::Ptr{Cvoid},
        Int32(constraintIndex)::Int32, outError::Ref{Cfloat})::Int32
    return status, outError[]
end

"""
Apply one constraint by id.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `constraintIndex` : Constraint id to apply

Returns: `Int32` status code
"""
function apply_constraint_bridge(state_ptr::Ptr{Cvoid}, constraintIndex::Integer)
    @ccall apply_constraint_bridge(state_ptr::Ptr{Cvoid}, Int32(constraintIndex)::Int32)::Int32
end

"""
Apply all constraints once in forward or reverse order.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `reverse` : `true` to apply in reverse order, `false` for forward order

Returns: `Int32` status code
"""
function apply_all_constraints_bridge(state_ptr::Ptr{Cvoid}, reverse::Bool=false)
    @ccall apply_all_constraints_bridge(state_ptr::Ptr{Cvoid}, UInt8(reverse)::UInt8)::Int32
end

"""
Solve constraints until total error is below threshold or iteration budget is exhausted.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `allowableError` : Error threshold target
- `maxIterations` : Maximum solve iterations (native side clamps and defaults)

Returns: `BridgeSolveResult`
"""
function solve_constraints_to_error(state_ptr::Ptr{Cvoid}, allowableError::Float32,
    maxIterations::Integer)
    @ccall solve_constraints_to_error(state_ptr::Ptr{Cvoid}, allowableError::Cfloat,
        Int32(maxIterations)::Int32)::BridgeSolveResult
end

"""
Get a `BridgeShapeLine` view by host point id.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `hostId` : Host point id for a line shape

Returns: `BridgeShapeLine`
"""
function get_shape_line_view(state_ptr::Ptr{Cvoid}, hostId::Integer)
    @ccall get_shape_line_view(state_ptr::Ptr{Cvoid}, Int32(hostId)::Int32)::BridgeShapeLine
end

"""
Get a `BridgeShapeCircle` view by host point id.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `hostId` : Host point id for a circle shape

Returns: `BridgeShapeCircle`
"""
function get_shape_circle_view(state_ptr::Ptr{Cvoid}, hostId::Integer)
    @ccall get_shape_circle_view(state_ptr::Ptr{Cvoid}, Int32(hostId)::Int32)::BridgeShapeCircle
end

"""
Get a `BridgeShapeFilledCircle` view by host point id.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `hostId` : Host point id for a filled circle shape

Returns: `BridgeShapeFilledCircle`
"""
function get_shape_filledcircle_view(state_ptr::Ptr{Cvoid}, hostId::Integer)
    @ccall get_shape_filledcircle_view(state_ptr::Ptr{Cvoid}, Int32(hostId)::Int32)::BridgeShapeFilledCircle
end

"""
Get a `BridgeShapeTriangle` view by host point id.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `hostId` : Host point id for a triangle shape

Returns: `BridgeShapeTriangle`
"""
function get_shape_triangle_view(state_ptr::Ptr{Cvoid}, hostId::Integer)
    @ccall get_shape_triangle_view(state_ptr::Ptr{Cvoid}, Int32(hostId)::Int32)::BridgeShapeTriangle
end

"""
Get a `BridgeShapeSquare` view by host point id.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `hostId` : Host point id for a square shape

Returns: `BridgeShapeSquare`
"""
function get_shape_square_view(state_ptr::Ptr{Cvoid}, hostId::Integer)
    @ccall get_shape_square_view(state_ptr::Ptr{Cvoid}, Int32(hostId)::Int32)::BridgeShapeSquare
end

"""
Get the current pen shape view.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API

Returns: `BridgeShapePen`
"""
function get_pen_view(state_ptr::Ptr{Cvoid})
    @ccall get_pen_view(state_ptr::Ptr{Cvoid})::BridgeShapePen
end

"""
Get the current compass shape view.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API

Returns: `BridgeShapeCompass`
"""
function get_compass_view(state_ptr::Ptr{Cvoid})
    @ccall get_compass_view(state_ptr::Ptr{Cvoid})::BridgeShapeCompass
end

"""
Get the point start index for animation-owned point allocations.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API

Returns: `Int32` animation point start index
"""
function get_kine_anim_points_start(state_ptr::Ptr{Cvoid})
    @ccall get_kine_anim_points_start(state_ptr::Ptr{Cvoid})::Int32
end

"""
Get the constraint start index for animation-owned constraint allocations.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API

Returns: `Int32` animation constraint start index
"""
function get_kine_anim_constraints_start(state_ptr::Ptr{Cvoid})
    @ccall get_kine_anim_constraints_start(state_ptr::Ptr{Cvoid})::Int32
end

"""
Freeze current point and constraint indices as animation boundaries.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API

Returns: `Int32` status code
"""
function freeze_kine_animation_boundary(state_ptr::Ptr{Cvoid})
    @ccall freeze_kine_animation_boundary(state_ptr::Ptr{Cvoid})::Int32
end

"""
Clear animation-owned kine points and constraints.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API

Returns: `Int32` status code
"""
function clear_kine_animation_data(state_ptr::Ptr{Cvoid})
    @ccall clear_kine_animation_data(state_ptr::Ptr{Cvoid})::Int32
end

"""
Get the maximum number of kine points.

------

Returns: `Int32` max point count
"""
function get_max_kine_points()
    @ccall get_max_kine_points()::Int32
end

"""
Get the maximum number of kine constraints.

------

Returns: `Int32` max constraint count
"""
function get_max_kine_constraints()
    @ccall get_max_kine_constraints()::Int32
end

"""
Run native kine graph validation.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API

Returns: `Int32` status code
"""
function validate_kine_graph(state_ptr::Ptr{Cvoid})
    @ccall validate_kine_graph(state_ptr::Ptr{Cvoid})::Int32
end



"""
Show the pen tool in the surface view.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
"""
function show_pen(state_ptr::Ptr{Cvoid})
    @ccall show_pen(state_ptr::Ptr{Cvoid})::Cvoid
end

"""
Hide the pen tool in the surface view.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
"""
function hide_pen(state_ptr::Ptr{Cvoid})
    @ccall hide_pen(state_ptr::Ptr{Cvoid})::Cvoid
end

"""
Set pen active state and active color.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `active` : Non-zero enables active state, zero disables it
- `c` : Active state color

Accepts `BridgeColor` directly; overloads also accept `Colorant`, `Symbol`, and `AbstractString`.
"""
function set_pen_active(state_ptr::Ptr{Cvoid}, active::Integer, c::BridgeColor)
    @ccall set_pen_active(state_ptr::Ptr{Cvoid}, active::Cint, c::BridgeColor)::Cvoid
end
function set_pen_active(state_ptr::Ptr{Cvoid}, active::Integer, c::Colorant)
    set_pen_active(state_ptr, active, bridge_color(c))
end

function set_pen_active(state_ptr::Ptr{Cvoid}, active::Integer, name::Symbol)
    set_pen_active(state_ptr, active, bridge_color(name))
end

function set_pen_active(state_ptr::Ptr{Cvoid}, active::Integer, name::AbstractString)
    set_pen_active(state_ptr, active, bridge_color(name))
end

"""
Clear any pen active override state.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
"""
function clear_pen_active(state_ptr::Ptr{Cvoid})
    @ccall clear_pen_active(state_ptr::Ptr{Cvoid})::Cvoid
end

"""
Lock pen joint 1 at a world position.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `x` : Lock x world coordinate
- `y` : Lock y world coordinate
- `z` : Lock z world coordinate
- `pos` : A vector can be provided in [x, y, z] form instead of individual parameters
"""
function lock_pen_joint1(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, z::Float32)
    pos = (x, y, z)
    @ccall lock_pen_joint1(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
end
function lock_pen_joint1(
    state_ptr::Ptr{Cvoid}, pos::Vector{Float32})
    postupled = (pos[1], pos[2], pos[3])
    @ccall lock_pen_joint1(state_ptr::Ptr{Cvoid}, postupled::NTuple{3, Cfloat})::Cvoid
end

"""
Unlock pen joint 1 so it can move freely.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
"""
function unlock_pen_joint1(state_ptr::Ptr{Cvoid})
    @ccall unlock_pen_joint1(state_ptr::Ptr{Cvoid})::Cvoid
end

"""
Move pen joint 1 to a world position.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `x` : Target x world coordinate
- `y` : Target y world coordinate
- `z` : Target z world coordinate
- `pos` : A vector can be provided in [x, y, z] form instead of individual parameters
"""
function move_pen_joint1(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, z::Float32)
    pos = (x, y, z)
    @ccall move_pen_joint1(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
end
function move_pen_joint1(
    state_ptr::Ptr{Cvoid}, pos::Vector{Float32})
    postupled = (pos[1], pos[2], pos[3])
    @ccall move_pen_joint1(state_ptr::Ptr{Cvoid}, postupled::NTuple{3, Cfloat})::Cvoid
end

"""
Get the current world position of pen joint 1.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API

Returns: `NTuple{3, Cfloat}` as `(x, y, z)`
"""
function get_pen_joint1_position(state_ptr::Ptr{Cvoid})
    return @ccall get_pen_joint1_position(state_ptr::Ptr{Cvoid})::NTuple{3, Cfloat}
end

"""
Lock pen joint 2 at a world position.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `x` : Lock x world coordinate
- `y` : Lock y world coordinate
- `z` : Lock z world coordinate
- `pos` : A vector can be provided in [x, y, z] form instead of individual parameters
"""
function lock_pen_joint2(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, z::Float32)
    pos = (x, y, z)
    @ccall lock_pen_joint2(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
end
function lock_pen_joint2(
    state_ptr::Ptr{Cvoid}, pos::Vector{Float32})
    postupled = (pos[1], pos[2], pos[3])
    @ccall lock_pen_joint2(state_ptr::Ptr{Cvoid}, postupled::NTuple{3, Cfloat})::Cvoid
end

"""
Unlock pen joint 2 so it can move freely.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
"""
function unlock_pen_joint2(state_ptr::Ptr{Cvoid})
    @ccall unlock_pen_joint2(state_ptr::Ptr{Cvoid})::Cvoid
end

"""
Move pen joint 2 to a world position.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `x` : Target x world coordinate
- `y` : Target y world coordinate
- `z` : Target z world coordinate
- `pos` : A vector can be provided in [x, y, z] form instead of individual parameters
"""
function move_pen_joint2(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, z::Float32)
    pos = (x, y, z)
    @ccall move_pen_joint2(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
end
function move_pen_joint2(
    state_ptr::Ptr{Cvoid}, pos::Vector{Float32})
    postupled = (pos[1], pos[2], pos[3])
    @ccall move_pen_joint2(state_ptr::Ptr{Cvoid}, postupled::NTuple{3, Cfloat})::Cvoid
end

"""
Get the current world position of pen joint 2.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API

Returns: `NTuple{3, Cfloat}` as `(x, y, z)`
"""
function get_pen_joint2_position(state_ptr::Ptr{Cvoid})
    return @ccall get_pen_joint2_position(state_ptr::Ptr{Cvoid})::NTuple{3, Cfloat}
end

"""
Show the compass tool in the surface view.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
"""
function show_compass(state_ptr::Ptr{Cvoid})
    @ccall show_compass(state_ptr::Ptr{Cvoid})::Cvoid
end

"""
Hide the compass tool in the surface view.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
"""
function hide_compass(state_ptr::Ptr{Cvoid})
    @ccall hide_compass(state_ptr::Ptr{Cvoid})::Cvoid
end

"""
Set compass active state and active color.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `active` : Non-zero enables active state, zero disables it
- `c` : Active state color

Accepts `BridgeColor` directly; overloads also accept `Colorant`, `Symbol`, and `AbstractString`.
"""
function set_compass_active(state_ptr::Ptr{Cvoid}, active::Integer, c::BridgeColor)
    @ccall set_compass_active(state_ptr::Ptr{Cvoid}, active::Cint, c::BridgeColor)::Cvoid
end
function set_compass_active(state_ptr::Ptr{Cvoid}, active::Integer, c::Colorant)
    set_compass_active(state_ptr, active, bridge_color(c))
end

function set_compass_active(state_ptr::Ptr{Cvoid}, active::Integer, name::Symbol)
    set_compass_active(state_ptr, active, bridge_color(name))
end

function set_compass_active(state_ptr::Ptr{Cvoid}, active::Integer, name::AbstractString)
    set_compass_active(state_ptr, active, bridge_color(name))
end

"""
Clear any compass active override state.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
"""
function clear_compass_active(state_ptr::Ptr{Cvoid})
    @ccall clear_compass_active(state_ptr::Ptr{Cvoid})::Cvoid
end

"""
Lock compass joint 1 at a world position.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `x` : Lock x world coordinate
- `y` : Lock y world coordinate
- `z` : Lock z world coordinate
- `pos` : A vector can be provided in [x, y, z] form instead of individual parameters
"""
function lock_compass_joint1(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, z::Float32)
    pos = (x, y, z)
    @ccall lock_compass_joint1(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
end
function lock_compass_joint1(
    state_ptr::Ptr{Cvoid}, pos::Vector{Float32})
    postupled = (pos[1], pos[2], pos[3])
    @ccall lock_compass_joint1(state_ptr::Ptr{Cvoid}, postupled::NTuple{3, Cfloat})::Cvoid
end

"""
Unlock compass joint 1 so it can move freely.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
"""
function unlock_compass_joint1(state_ptr::Ptr{Cvoid})
    @ccall unlock_compass_joint1(state_ptr::Ptr{Cvoid})::Cvoid
end

"""
Move compass joint 1 to a world position.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `x` : Target x world coordinate
- `y` : Target y world coordinate
- `z` : Target z world coordinate
- `pos` : A vector can be provided in [x, y, z] form instead of individual parameters
"""
function move_compass_joint1(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, z::Float32)
    pos = (x, y, z)
    @ccall move_compass_joint1(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
end
function move_compass_joint1(
    state_ptr::Ptr{Cvoid}, pos::Vector{Float32})
    postupled = (pos[1], pos[2], pos[3])
    @ccall move_compass_joint1(state_ptr::Ptr{Cvoid}, postupled::NTuple{3, Cfloat})::Cvoid
end

"""
Get the current world position of compass joint 1.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API

Returns: `NTuple{3, Cfloat}` as `(x, y, z)`
"""
function get_compass_joint1_position(state_ptr::Ptr{Cvoid})
    return @ccall get_compass_joint1_position(state_ptr::Ptr{Cvoid})::NTuple{3, Cfloat}
end

"""
Lock compass joint 2 at a world position.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `x` : Lock x world coordinate
- `y` : Lock y world coordinate
- `z` : Lock z world coordinate
- `pos` : A vector can be provided in [x, y, z] form instead of individual parameters
"""
function lock_compass_joint2(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, z::Float32)
    pos = (x, y, z)
    @ccall lock_compass_joint2(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
end
function lock_compass_joint2(
    state_ptr::Ptr{Cvoid}, pos::Vector{Float32})
    postupled = (pos[1], pos[2], pos[3])
    @ccall lock_compass_joint2(state_ptr::Ptr{Cvoid}, postupled::NTuple{3, Cfloat})::Cvoid
end

"""
Unlock compass joint 2 so it can move freely.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
"""
function unlock_compass_joint2(state_ptr::Ptr{Cvoid})
    @ccall unlock_compass_joint2(state_ptr::Ptr{Cvoid})::Cvoid
end

"""
Move compass joint 2 to a world position.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `x` : Target x world coordinate
- `y` : Target y world coordinate
- `z` : Target z world coordinate
- `pos` : A vector can be provided in [x, y, z] form instead of individual parameters
"""
function move_compass_joint2(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, z::Float32)
    pos = (x, y, z)
    @ccall move_compass_joint2(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
end
function move_compass_joint2(
    state_ptr::Ptr{Cvoid}, pos::Vector{Float32})
    postupled = (pos[1], pos[2], pos[3])
    @ccall move_compass_joint2(state_ptr::Ptr{Cvoid}, postupled::NTuple{3, Cfloat})::Cvoid
end

"""
Get the current world position of compass joint 2.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API

Returns: `NTuple{3, Cfloat}` as `(x, y, z)`
"""
function get_compass_joint2_position(state_ptr::Ptr{Cvoid})
    return @ccall get_compass_joint2_position(state_ptr::Ptr{Cvoid})::NTuple{3, Cfloat}
end

"""
Set one animation metadata slot by index.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `pos` : Metadata slot index
- `metadata` : Value to store in the slot
"""
function set_animation_meta(state_ptr::Ptr{Cvoid}, pos::Integer, metadata::Float32)
    @ccall set_animation_meta(state_ptr::Ptr{Cvoid}, pos::Cint, metadata::Cfloat)::Cvoid
end

"""
Read one animation metadata slot by index.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `pos` : Metadata slot index

Returns: slot value as `Float32`
"""
function get_animation_meta(state_ptr::Ptr{Cvoid}, pos::Integer)
    ret = @ccall get_animation_meta(state_ptr::Ptr{Cvoid}, pos::Cint)::Cfloat
    return Float32(ret)
end

"""
Emit a trailing particle at a 2D position.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `x` : Particle x coordinate
- `y` : Particle y coordinate
- `pos` : A vector can be provided in [x, y] form instead of individual parameters
- `color` : Particle color

Accepts `BridgeColor` directly; overloads also accept `Colorant`, `Symbol`, and `AbstractString`.
"""
function emit_trailing_particle(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, color::BridgeColor)
    pos = (x, y)
    @ccall emit_trailing_particle(state_ptr::Ptr{Cvoid}, pos::NTuple{2, Cfloat}, color::BridgeColor)::Cvoid
end

function emit_trailing_particle(
    state_ptr::Ptr{Cvoid}, pos::Vector{Float32}, color::BridgeColor)
    emit_trailing_particle(state_ptr, pos[1], pos[2], color)
end

function emit_trailing_particle(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, color::Colorant)
    emit_trailing_particle(state_ptr, x, y, bridge_color(color))
end

function emit_trailing_particle(
    state_ptr::Ptr{Cvoid}, pos::Vector{Float32}, color::Colorant)
    emit_trailing_particle(state_ptr, pos[1], pos[2], bridge_color(color))
end

function emit_trailing_particle(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, color::Symbol)
    emit_trailing_particle(state_ptr, x, y, bridge_color(color))
end

function emit_trailing_particle(
    state_ptr::Ptr{Cvoid}, pos::Vector{Float32}, color::Symbol)
    emit_trailing_particle(state_ptr, pos[1], pos[2], bridge_color(color))
end

function emit_trailing_particle(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, color::AbstractString)
    emit_trailing_particle(state_ptr, x, y, bridge_color(color))
end

function emit_trailing_particle(
    state_ptr::Ptr{Cvoid}, pos::Vector{Float32}, color::AbstractString)
    emit_trailing_particle(state_ptr, pos[1], pos[2], bridge_color(color))
end

"""
Emit a flicker-only particle at a 2D position.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `x` : Particle x coordinate
- `y` : Particle y coordinate
- `pos` : A vector can be provided in [x, y] form instead of individual parameters
- `color` : Particle color

Accepts `BridgeColor` directly; overloads also accept `Colorant`, `Symbol`, and `AbstractString`.
"""
function emit_flicker_particle(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, color::BridgeColor)
    pos = (x, y)
    @ccall emit_flicker_particle(state_ptr::Ptr{Cvoid}, pos::NTuple{2, Cfloat}, color::BridgeColor)::Cvoid
end

function emit_flicker_particle(
    state_ptr::Ptr{Cvoid}, pos::Vector{Float32}, color::BridgeColor)
    emit_flicker_particle(state_ptr, pos[1], pos[2], color)
end

function emit_flicker_particle(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, color::Colorant)
    emit_flicker_particle(state_ptr, x, y, bridge_color(color))
end

function emit_flicker_particle(
    state_ptr::Ptr{Cvoid}, pos::Vector{Float32}, color::Colorant)
    emit_flicker_particle(state_ptr, pos[1], pos[2], bridge_color(color))
end

function emit_flicker_particle(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, color::Symbol)
    emit_flicker_particle(state_ptr, x, y, bridge_color(color))
end

function emit_flicker_particle(
    state_ptr::Ptr{Cvoid}, pos::Vector{Float32}, color::Symbol)
    emit_flicker_particle(state_ptr, pos[1], pos[2], bridge_color(color))
end

function emit_flicker_particle(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, color::AbstractString)
    emit_flicker_particle(state_ptr, x, y, bridge_color(color))
end

function emit_flicker_particle(
    state_ptr::Ptr{Cvoid}, pos::Vector{Float32}, color::AbstractString)
    emit_flicker_particle(state_ptr, pos[1], pos[2], bridge_color(color))
end

end


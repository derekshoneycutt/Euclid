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
    x::Float32, y::Float32, z::Float32,
    color::Colorant, brushSize::Float32)
    create_new_point(state_ptr, x, y, z, bridge_color(color), brushSize)
end
function create_new_point(state_ptr::Ptr{Cvoid},
    x::Float32, y::Float32, z::Float32,
    color::Symbol, brushSize::Float32)
    create_new_point(state_ptr, x, y, z, bridge_color(color), brushSize)
end
function create_new_point(state_ptr::Ptr{Cvoid},
    x::Float32, y::Float32, z::Float32,
    color::AbstractString, brushSize::Float32)
    create_new_point(state_ptr, x, y, z, bridge_color(color), brushSize)
end

"""
Construct a new line in the Euclid system to be shown on the surface

------

Parameters:

- `state_ptr` : The state of the Euclid application to pass to the API
- `x1` : The x value for the position of the first point bounding the line
- `y1` : The y value for the position of the first point bounding the line
- `z1` : The z value for the position of the first point bounding the line
- `x2` : The x value for the position of the second point bounding the line
- `y2` : The y value for the position of the second point bounding the line
- `z2` : The z value for the position of the second point bounding the line
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
    x1::Float32, y1::Float32, z1::Float32,
    x2::Float32, y2::Float32, z2::Float32,
    color::Colorant, brushSize::Float32)
    create_new_line(state_ptr, x1, y1, z1, x2, y2, z2, bridge_color(color), brushSize)
end
function create_new_line(state_ptr::Ptr{Cvoid},
    x1::Float32, y1::Float32, z1::Float32,
    x2::Float32, y2::Float32, z2::Float32,
    color::Symbol, brushSize::Float32)
    create_new_line(state_ptr, x1, y1, z1, x2, y2, z2, bridge_color(color), brushSize)
end
function create_new_line(state_ptr::Ptr{Cvoid},
    x1::Float32, y1::Float32, z1::Float32,
    x2::Float32, y2::Float32, z2::Float32,
    color::AbstractString, brushSize::Float32)
    create_new_line(state_ptr, x1, y1, z1, x2, y2, z2, bridge_color(color), brushSize)
end

"""
Construct a new circle in the Euclid system to be shown on the surface

------

Parameters:

- `state_ptr` : The state of the Euclid application to pass to the API
- `x` : The x value for the position of the center point of the circle
- `y` : The y value for the position of the center point of the circle
- `z` : The z value for the position of the center point of the circle
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
    x::Float32, y::Float32, z::Float32,
    radius::Float32, startθ::Float32, endθ::Float32,
    color::Colorant, brushSize::Float32)
    create_new_circle(state_ptr, x, y, z, radius, startθ, endθ, bridge_color(color), brushSize)
end
function create_new_circle(state_ptr::Ptr{Cvoid},
    x::Float32, y::Float32, z::Float32,
    radius::Float32, startθ::Float32, endθ::Float32,
    color::Symbol, brushSize::Float32)
    create_new_circle(state_ptr, x, y, z, radius, startθ, endθ, bridge_color(color), brushSize)
end
function create_new_circle(state_ptr::Ptr{Cvoid},
    x::Float32, y::Float32, z::Float32,
    radius::Float32, startθ::Float32, endθ::Float32,
    color::AbstractString, brushSize::Float32)
    create_new_circle(state_ptr, x, y, z, radius, startθ, endθ, bridge_color(color), brushSize)
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
"""
function set_point_position(
    state_ptr::Ptr{Cvoid}, id::Integer, x::Float32, y::Float32, z::Float32)
    pos = (x, y, z)
    @ccall set_point_position(state_ptr::Ptr{Cvoid}, id::Cint, pos::NTuple{3, Cfloat})::Cvoid
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
"""
function lock_pen_joint1(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, z::Float32)
    pos = (x, y, z)
    @ccall lock_pen_joint1(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
end

"""
Unlock pen joint 1 so it can move freely.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
"""
function unlock_pen_joint1(state_ptr::Ptr{Cvoid})
    @ccall unlock_pen_joint1(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
end

"""
Move pen joint 1 to a world position.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `x` : Target x world coordinate
- `y` : Target y world coordinate
- `z` : Target z world coordinate
"""
function move_pen_joint1(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, z::Float32)
    pos = (x, y, z)
    @ccall move_pen_joint1(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
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
"""
function lock_pen_joint2(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, z::Float32)
    pos = (x, y, z)
    @ccall lock_pen_joint2(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
end

"""
Unlock pen joint 2 so it can move freely.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
"""
function unlock_pen_joint2(state_ptr::Ptr{Cvoid})
    @ccall unlock_pen_joint2(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
end

"""
Move pen joint 2 to a world position.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `x` : Target x world coordinate
- `y` : Target y world coordinate
- `z` : Target z world coordinate
"""
function move_pen_joint2(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, z::Float32)
    pos = (x, y, z)
    @ccall move_pen_joint2(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
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
"""
function lock_compass_joint1(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, z::Float32)
    pos = (x, y, z)
    @ccall lock_compass_joint1(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
end

"""
Unlock compass joint 1 so it can move freely.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
"""
function unlock_compass_joint1(state_ptr::Ptr{Cvoid})
    @ccall unlock_compass_joint1(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
end

"""
Move compass joint 1 to a world position.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `x` : Target x world coordinate
- `y` : Target y world coordinate
- `z` : Target z world coordinate
"""
function move_compass_joint1(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, z::Float32)
    pos = (x, y, z)
    @ccall move_compass_joint1(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
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
"""
function lock_compass_joint2(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, z::Float32)
    pos = (x, y, z)
    @ccall lock_compass_joint2(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
end

"""
Unlock compass joint 2 so it can move freely.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
"""
function unlock_compass_joint2(state_ptr::Ptr{Cvoid})
    @ccall unlock_compass_joint2(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
end

"""
Move compass joint 2 to a world position.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `x` : Target x world coordinate
- `y` : Target y world coordinate
- `z` : Target z world coordinate
"""
function move_compass_joint2(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, z::Float32)
    pos = (x, y, z)
    @ccall move_compass_joint2(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
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
- `color` : Particle color

Accepts `BridgeColor` directly; overloads also accept `Colorant`, `Symbol`, and `AbstractString`.
"""
function emit_trailing_particle(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, color::BridgeColor)
    pos = (x, y)
    @ccall emit_trailing_particle(state_ptr::Ptr{Cvoid}, pos::NTuple{2, Cfloat}, color::BridgeColor)::Cvoid
end

function emit_trailing_particle(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, color::Colorant)
    emit_trailing_particle(state_ptr, x, y, bridge_color(color))
end

function emit_trailing_particle(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, color::Symbol)
    emit_trailing_particle(state_ptr, x, y, bridge_color(color))
end

function emit_trailing_particle(
    state_ptr::Ptr{Cvoid}, x::Float32, y::Float32, color::AbstractString)
    emit_trailing_particle(state_ptr, x, y, bridge_color(color))
end

end



"""
Get a `BridgeShapeLine` view by host point id.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `host_id` : Host point id for a line shape

Returns: `BridgeShapeLine`
"""
function get_shape_line_view(state_ptr::Ptr{Cvoid}, host_id::Integer)
    @ccall get_shape_line_view(
        state_ptr::Ptr{Cvoid}, Int32(host_id)::Int32)::BridgeShapeLine
end

"""
Get a `BridgeShapeCircle` view by host point id.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `host_id` : Host point id for a circle shape

Returns: `BridgeShapeCircle`
"""
function get_shape_circle_view(state_ptr::Ptr{Cvoid}, host_id::Integer)
    @ccall get_shape_circle_view(
        state_ptr::Ptr{Cvoid}, Int32(host_id)::Int32)::BridgeShapeCircle
end

"""
Get a `BridgeShapeFilledCircle` view by host point id.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `host_id` : Host point id for a filled circle shape

Returns: `BridgeShapeFilledCircle`
"""
function get_shape_filledcircle_view(state_ptr::Ptr{Cvoid}, host_id::Integer)
    @ccall get_shape_filledcircle_view(
        state_ptr::Ptr{Cvoid}, Int32(host_id)::Int32)::BridgeShapeFilledCircle
end

"""
Get a `BridgeShapeTriangle` view by host point id.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `host_id` : Host point id for a triangle shape

Returns: `BridgeShapeTriangle`
"""
function get_shape_triangle_view(state_ptr::Ptr{Cvoid}, host_id::Integer)
    @ccall get_shape_triangle_view(state_ptr::Ptr{Cvoid},
        Int32(host_id)::Int32)::BridgeShapeTriangle
end

"""
Get a `BridgeShapeSquare` view by host point id.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `host_id` : Host point id for a square shape

Returns: `BridgeShapeSquare`
"""
function get_shape_square_view(state_ptr::Ptr{Cvoid}, host_id::Integer)
    @ccall get_shape_square_view(
        state_ptr::Ptr{Cvoid}, Int32(host_id)::Int32)::BridgeShapeSquare
end

"""
Get a `BridgeShapePentagon` view by host point id.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `host_id` : Host point id for a pentagon shape

Returns: `BridgeShapePentagon`
"""
function get_shape_pentagon_view(state_ptr::Ptr{Cvoid}, host_id::Integer)
    @ccall get_shape_pentagon_view(state_ptr::Ptr{Cvoid},
        Int32(host_id)::Int32)::BridgeShapePentagon
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
function get_shapes_anim_points_start(state_ptr::Ptr{Cvoid})
    @ccall get_shapes_anim_points_start(state_ptr::Ptr{Cvoid})::Int32
end

"""
Get the constraint start index for animation-owned constraint allocations.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API

Returns: `Int32` animation constraint start index
"""
function get_shapes_anim_constraints_start(state_ptr::Ptr{Cvoid})
    @ccall get_shapes_anim_constraints_start(state_ptr::Ptr{Cvoid})::Int32
end

"""
Freeze current point and constraint indices as animation boundaries.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API

Returns: `Int32` status code
"""
function freeze_shapes_animation_boundary(state_ptr::Ptr{Cvoid})
    @ccall freeze_shapes_animation_boundary(state_ptr::Ptr{Cvoid})::Int32
end

"""
Clear animation-owned shapes points and constraints.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API

Returns: `Int32` status code
"""
function clear_shapes_animation_data(state_ptr::Ptr{Cvoid})
    @ccall clear_shapes_animation_data(state_ptr::Ptr{Cvoid})::Int32
end

"""
Get the maximum number of shapes points.

------

Returns: `Int32` max point count
"""
function get_max_shapes_points()
    @ccall get_max_shapes_points()::Int32
end

"""
Get the maximum number of shapes constraints.

------

Returns: `Int32` max constraint count
"""
function get_max_shapes_constraints()
    @ccall get_max_shapes_constraints()::Int32
end

"""
Run native shapes graph validation.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API

Returns: `Int32` status code
"""
function validate_shapes_graph(state_ptr::Ptr{Cvoid})
    @ccall validate_shapes_graph(state_ptr::Ptr{Cvoid})::Int32
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
    state_ptr::Ptr{Cvoid}, x::Real, y::Real, z::Real)
    pos = (Float32(x), Float32(y), Float32(z))
    @ccall lock_pen_joint1(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
end
function lock_pen_joint1(
    state_ptr::Ptr{Cvoid}, pos::AbstractVector{<:Real})
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
    state_ptr::Ptr{Cvoid}, x::Real, y::Real, z::Real)
    pos = (Float32(x), Float32(y), Float32(z))
    @ccall move_pen_joint1(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
end
function move_pen_joint1(
    state_ptr::Ptr{Cvoid}, pos::AbstractVector{<:Real})
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
    state_ptr::Ptr{Cvoid}, x::Real, y::Real, z::Real)
    pos = (Float32(x), Float32(y), Float32(z))
    @ccall lock_pen_joint2(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
end
function lock_pen_joint2(
    state_ptr::Ptr{Cvoid}, pos::AbstractVector{<:Real})
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
    state_ptr::Ptr{Cvoid}, x::Real, y::Real, z::Real)
    pos = (Float32(x), Float32(y), Float32(z))
    @ccall move_pen_joint2(state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat})::Cvoid
end
function move_pen_joint2(
    state_ptr::Ptr{Cvoid}, pos::AbstractVector{<:Real})
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
- `sweep` : (Default true) When true, will sweep dust through the full arc of the compass on ground contact
"""
function lock_compass_joint1(
    state_ptr::Ptr{Cvoid}, x::Real, y::Real, z::Real; sweep::Bool = true)
    pos = (Float32(x), Float32(y), Float32(z))
    @ccall lock_compass_joint1(
        state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat}, sweep::Bool)::Cvoid
end
function lock_compass_joint1(
    state_ptr::Ptr{Cvoid}, pos::AbstractVector{<:Real}; sweep::Bool = true)
    postupled = (pos[1], pos[2], pos[3])
    @ccall lock_compass_joint1(
        state_ptr::Ptr{Cvoid}, postupled::NTuple{3, Cfloat}, sweep::Bool)::Cvoid
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
- `sweep` : (Default true) When true, will sweep dust through the full arc of the compass on ground contact
"""
function move_compass_joint1(
    state_ptr::Ptr{Cvoid}, x::Real, y::Real, z::Real; sweep::Bool = true)
    pos = (Float32(x), Float32(y), Float32(z))
    @ccall move_compass_joint1(
        state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat}, sweep::Bool)::Cvoid
end
function move_compass_joint1(
    state_ptr::Ptr{Cvoid}, pos::AbstractVector{<:Real}; sweep::Bool = true)
    postupled = (pos[1], pos[2], pos[3])
    @ccall move_compass_joint1(state_ptr::Ptr{Cvoid},
        postupled::NTuple{3, Cfloat}, sweep::Bool)::Cvoid
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
- `sweep` : (Default true) When true, will sweep dust through the full arc of the compass on ground contact
"""
function lock_compass_joint2(
    state_ptr::Ptr{Cvoid}, x::Real, y::Real, z::Real; sweep::Bool = true)
    pos = (Float32(x), Float32(y), Float32(z))
    @ccall lock_compass_joint2(
        state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat}, sweep::Bool)::Cvoid
end
function lock_compass_joint2(
    state_ptr::Ptr{Cvoid}, pos::AbstractVector{<:Real}; sweep::Bool = true)
    postupled = (pos[1], pos[2], pos[3])
    @ccall lock_compass_joint2(
        state_ptr::Ptr{Cvoid}, postupled::NTuple{3, Cfloat}, sweep::Bool)::Cvoid
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
- `sweep` : (Default true) When true, will sweep dust through the full arc of the compass on ground contact
"""
function move_compass_joint2(
    state_ptr::Ptr{Cvoid}, x::Real, y::Real, z::Real; sweep::Bool = true)
    pos = (Float32(x), Float32(y), Float32(z))
    @ccall move_compass_joint2(
        state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat}, sweep::Bool)::Cvoid
end
function move_compass_joint2(
    state_ptr::Ptr{Cvoid}, pos::AbstractVector{<:Real}; sweep::Bool = true)
    postupled = (pos[1], pos[2], pos[3])
    @ccall move_compass_joint2(state_ptr::Ptr{Cvoid},
        postupled::NTuple{3, Cfloat}, sweep::Bool)::Cvoid
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
function set_animation_meta(state_ptr::Ptr{Cvoid}, pos::Integer, metadata::Real)
    @ccall set_animation_meta(state_ptr::Ptr{Cvoid}, pos::Cint, metadata::Cfloat)::Cvoid
end

"""
Read one animation metadata slot by index.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `pos` : Metadata slot index

Returns: slot value as `Real`
"""
function get_animation_meta(state_ptr::Ptr{Cvoid}, pos::Integer)
    ret = @ccall get_animation_meta(state_ptr::Ptr{Cvoid}, pos::Cint)::Cfloat
    return Real(ret)
end

"""
Enable or disable drawing sound emission for the active animation.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `enabled` : `true` to allow drawing sound, `false` to mute it
"""
function set_drawing_sound_enabled(state_ptr::Ptr{Cvoid}, enabled::Bool)
    @ccall set_drawing_sound_enabled(state_ptr::Ptr{Cvoid}, enabled::Bool)::Cvoid
end

"""
Inject drawing sound activity at a specific speed for scripted phases.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `speed` : Drawing speed scalar in the same units used by the host chalk runtime
"""
function simulate_drawing_sound(state_ptr::Ptr{Cvoid}, speed::Real)
    @ccall simulate_drawing_sound(state_ptr::Ptr{Cvoid}, speed::Cfloat)::Cvoid
end

"""
Emit a trailing particle at a 2D position.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `x` : Particle x coordinate
- `y` : Particle y coordinate
- `z` : Particle z coordinate
- `pos` : A vector can be provided in [x, y, z] form instead of individual parameters
- `color` : Particle color

Accepts `BridgeColor` directly; overloads also accept `Colorant`, `Symbol`, and `AbstractString`.
"""
function emit_trailing_particle(
    state_ptr::Ptr{Cvoid}, x::Real, y::Real, z::Real, color::BridgeColor)
    pos = (Float32(x), Float32(y), Float32(z))
    @ccall emit_trailing_particle(
        state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat}, color::BridgeColor)::Cvoid
end

function emit_trailing_particle(
    state_ptr::Ptr{Cvoid}, pos::AbstractVector{<:Real}, color::BridgeColor)
    emit_trailing_particle(state_ptr, pos[1], pos[2], pos[3], color)
end

function emit_trailing_particle(
    state_ptr::Ptr{Cvoid}, x::Real, y::Real, z::Real, color::Colorant)
    emit_trailing_particle(state_ptr, x, y, z, bridge_color(color))
end

function emit_trailing_particle(
    state_ptr::Ptr{Cvoid}, pos::AbstractVector{<:Real}, color::Colorant)
    emit_trailing_particle(state_ptr, pos[1], pos[2], pos[3], bridge_color(color))
end

function emit_trailing_particle(
    state_ptr::Ptr{Cvoid}, x::Real, y::Real, z::Real, color::Symbol)
    emit_trailing_particle(state_ptr, x, y, z, bridge_color(color))
end

function emit_trailing_particle(
    state_ptr::Ptr{Cvoid}, pos::AbstractVector{<:Real}, color::Symbol)
    emit_trailing_particle(state_ptr, pos[1], pos[2], pos[3], bridge_color(color))
end

function emit_trailing_particle(
    state_ptr::Ptr{Cvoid}, x::Real, y::Real, z::Real, color::AbstractString)
    emit_trailing_particle(state_ptr, x, y, z, bridge_color(color))
end

function emit_trailing_particle(
    state_ptr::Ptr{Cvoid}, pos::AbstractVector{<:Real}, color::AbstractString)
    emit_trailing_particle(state_ptr, pos[1], pos[2], pos[3], bridge_color(color))
end

"""
Emit a flicker-only particle at a 3D position.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
- `x` : Particle x coordinate
- `y` : Particle y coordinate
- `z` : Particle z coordinate
- `pos` : A vector can be provided in [x, y, z] form instead of individual parameters
- `color` : Particle color

Accepts `BridgeColor` directly; overloads also accept `Colorant`, `Symbol`, and `AbstractString`.
"""
function emit_flicker_particle(
    state_ptr::Ptr{Cvoid}, x::Real, y::Real, z::Real, color::BridgeColor)
    pos = (Float32(x), Float32(y), Float32(z))
    @ccall emit_flicker_particle(
        state_ptr::Ptr{Cvoid}, pos::NTuple{3, Cfloat}, color::BridgeColor)::Cvoid
end

function emit_flicker_particle(
    state_ptr::Ptr{Cvoid}, pos::AbstractVector{<:Real}, color::BridgeColor)
    emit_flicker_particle(state_ptr, pos[1], pos[2], pos[3], color)
end

function emit_flicker_particle(
    state_ptr::Ptr{Cvoid}, x::Real, y::Real, z::Real, color::Colorant)
    emit_flicker_particle(state_ptr, x, y, z, bridge_color(color))
end

function emit_flicker_particle(
    state_ptr::Ptr{Cvoid}, pos::AbstractVector{<:Real}, color::Colorant)
    emit_flicker_particle(state_ptr, pos[1], pos[2], pos[3], bridge_color(color))
end

function emit_flicker_particle(
    state_ptr::Ptr{Cvoid}, x::Real, y::Real, z::Real, color::Symbol)
    emit_flicker_particle(state_ptr, x, y, z, bridge_color(color))
end

function emit_flicker_particle(
    state_ptr::Ptr{Cvoid}, pos::AbstractVector{<:Real}, color::Symbol)
    emit_flicker_particle(state_ptr, pos[1], pos[2], pos[3], bridge_color(color))
end

function emit_flicker_particle(
    state_ptr::Ptr{Cvoid}, x::Real, y::Real, z::Real, color::AbstractString)
    emit_flicker_particle(state_ptr, x, y, z, bridge_color(color))
end

function emit_flicker_particle(
    state_ptr::Ptr{Cvoid}, pos::AbstractVector{<:Real}, color::AbstractString)
    emit_flicker_particle(state_ptr, pos[1], pos[2], pos[3], bridge_color(color))
end


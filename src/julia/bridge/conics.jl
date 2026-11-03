"""Build a native parabola description without allocating intermediate arrays."""
function _parabola_geometry(; focal_distance::Real, rotation::Real,
    parameter_start::Real, parameter_finish::Real, draw_parameter::Real)
    return BridgeParabolaGeometry(Cfloat(focal_distance), Cfloat(rotation),
        Cfloat(parameter_start), Cfloat(parameter_finish), Cfloat(draw_parameter))
end

"""Build one complete hyperbola description for the native boundary."""
function _hyperbola_geometry(; semimajor::Real, semiminor::Real,
    rotation::Real, parameter_start::Real, parameter_finish::Real,
    draw_parameter::Real)
    return BridgeHyperbolaGeometry(Cfloat(semimajor),
        Cfloat(semiminor), Cfloat(rotation), Cfloat(parameter_start),
        Cfloat(parameter_finish), Cfloat(draw_parameter))
end

"""Create a finite, open parabola with an independently controlled reveal frontier."""
function create_new_parabola(state_ptr::Ptr{Cvoid}, vertex;
    focal_distance::Real, rotation::Real=0f0, parameter_start::Real=-1f0,
    parameter_finish::Real=1f0, draw_parameter::Real=parameter_finish,
    color=BridgeColor(0, 0, 0, 0), brush_size::Real=0f0)
    position = (Cfloat(vertex[1]), Cfloat(vertex[2]), Cfloat(vertex[3]))
    geometry = _parabola_geometry(; focal_distance, rotation, parameter_start,
        parameter_finish, draw_parameter)
    style = _shape_style(color, brush_size)
    return @ccall shape_create_parabola(state_ptr::Ptr{Cvoid},
        position::NTuple{3,Cfloat}, geometry::BridgeParabolaGeometry,
        style::BridgeShapeStyle)::BridgeShapeConicResult
end

"""Validate constructor/contact selection in the hyperbola's intrinsic axes."""
function hyperbola_branches(branches::Symbol)
    branches === :both && return HYPERBOLA_BOTH
    branches === :positive && return HYPERBOLA_POSITIVE
    branches === :negative && return HYPERBOLA_NEGATIVE
    throw(ArgumentError("hyperbola branches must be :both, :positive, or :negative"))
end

"""Decode immutable native branch selection without allocating a geometry cache."""
function hyperbola_branch_mode(selection::Int32)
    selection == HYPERBOLA_BOTH && return :both
    selection == HYPERBOLA_POSITIVE && return :positive
    selection == HYPERBOLA_NEGATIVE && return :negative
    throw(ArgumentError("invalid native hyperbola branch selection: $selection"))
end

"""Create one hyperbola with immutable ink selection and one common frontier."""
function create_new_hyperbola(state_ptr::Ptr{Cvoid}, center;
    semimajor::Real, semiminor::Real, rotation::Real=0f0,
    parameter_start::Real=-1f0, parameter_finish::Real=1f0,
    draw_parameter::Real=parameter_finish,
    color=BridgeColor(0, 0, 0, 0), brush_size::Real=0f0, branches::Symbol=:both)
    selection = hyperbola_branches(branches)
    position = (Cfloat(center[1]), Cfloat(center[2]), Cfloat(center[3]))
    geometry = _hyperbola_geometry(; semimajor, semiminor, rotation,
        parameter_start, parameter_finish, draw_parameter)
    style = _shape_style(color, brush_size)
    return @ccall shape_create_hyperbola(state_ptr::Ptr{Cvoid},
        position::NTuple{3,Cfloat}, geometry::BridgeHyperbolaGeometry,
        style::BridgeShapeStyle, selection::Int32)::BridgeShapeConicResult
end

"""Query a parabola from the current owner-controlled native query source."""
function get_parabola_geometry(state_ptr::Ptr{Cvoid}, entity::Integer)
    return @ccall shape_get_parabola(state_ptr::Ptr{Cvoid},
        UInt64(entity)::UInt64)::BridgeShapeParabolaQueryResult
end

"""Query mutable geometry and immutable ink selection from the native owner."""
function get_hyperbola_geometry(state_ptr::Ptr{Cvoid}, entity::Integer)
    return @ccall shape_get_hyperbola(state_ptr::Ptr{Cvoid},
        UInt64(entity)::UInt64)::BridgeShapeHyperbolaQueryResult
end

"""Atomically replace a parabola's finite analytic domain and frontier."""
function set_parabola_geometry(state_ptr::Ptr{Cvoid}, entity::Integer;
    focal_distance::Real, rotation::Real=0f0, parameter_start::Real,
    parameter_finish::Real, draw_parameter::Real)
    geometry = _parabola_geometry(; focal_distance, rotation, parameter_start,
        parameter_finish, draw_parameter)
    return @ccall shape_set_parabola(state_ptr::Ptr{Cvoid},
        UInt64(entity)::UInt64, geometry::BridgeParabolaGeometry)::Int32
end

"""Replace analytic geometry while preserving the host's immutable branch selection."""
function set_hyperbola_geometry(state_ptr::Ptr{Cvoid}, entity::Integer;
    semimajor::Real, semiminor::Real, rotation::Real=0f0,
    parameter_start::Real, parameter_finish::Real, draw_parameter::Real)
    geometry = _hyperbola_geometry(; semimajor, semiminor, rotation,
        parameter_start, parameter_finish, draw_parameter)
    return @ccall shape_set_hyperbola(state_ptr::Ptr{Cvoid},
        UInt64(entity)::UInt64, geometry::BridgeHyperbolaGeometry)::Int32
end

"""Advance the parabola's reveal frontier within its directed finite domain."""
function set_parabola_frontier(
    state_ptr::Ptr{Cvoid}, entity::Integer, parameter::Real)
    return @ccall shape_set_parabola_frontier(state_ptr::Ptr{Cvoid},
        UInt64(entity)::UInt64, Cfloat(parameter)::Cfloat)::Int32
end

"""Advance the common reveal frontier, retaining immutable branch selection."""
function set_hyperbola_frontier(
    state_ptr::Ptr{Cvoid}, entity::Integer, parameter::Real)
    return @ccall shape_set_hyperbola_frontier(state_ptr::Ptr{Cvoid},
        UInt64(entity)::UInt64, Cfloat(parameter)::Cfloat)::Int32
end

"""Show the permanent Inwards-inspired parabola instrument."""
function show_parabola_tool(state_ptr::Ptr{Cvoid})
    return @ccall show_parabola_tool(state_ptr::Ptr{Cvoid})::Int32
end

"""Hide the parabola apparatus without treating its material as drawn ink."""
function hide_parabola_tool(state_ptr::Ptr{Cvoid})
    return @ccall hide_parabola_tool(state_ptr::Ptr{Cvoid})::Int32
end

"""Translate the parabola instrument's vertex and common elevation."""
function set_parabola_tool_position(state_ptr::Ptr{Cvoid}, position)
    value = (Cfloat(position[1]), Cfloat(position[2]), Cfloat(position[3]))
    return @ccall set_parabola_tool_position(state_ptr::Ptr{Cvoid},
        value::NTuple{3,Cfloat})::Int32
end

"""Configure the complete finite Inwards-inspired assembly atomically."""
function set_parabola_tool_geometry(state_ptr::Ptr{Cvoid};
    focal_distance::Real, link_length::Real, rotation::Real=0f0,
    parameter_start::Real, parameter_finish::Real,
    parameter::Real=parameter_start)
    geometry = BridgeParabolaToolGeometry(Cfloat(focal_distance),
        Cfloat(link_length), Cfloat(rotation), Cfloat(parameter_start),
        Cfloat(parameter_finish), Cfloat(parameter))
    return @ccall set_parabola_tool_geometry(state_ptr::Ptr{Cvoid},
        geometry::BridgeParabolaToolGeometry)::Int32
end

"""Move the parabola carriage and diamond to one native analytic parameter."""
function set_parabola_tool_parameter(state_ptr::Ptr{Cvoid}, parameter::Real)
    return @ccall set_parabola_tool_parameter(state_ptr::Ptr{Cvoid},
        Cfloat(parameter)::Cfloat)::Int32
end

"""Set the integrated parabola tip's authored-ink contact indicator."""
function set_parabola_tool_active(
    state_ptr::Ptr{Cvoid}, active::Integer, color)
    value = _shape_color(color)
    return @ccall set_parabola_tool_active(state_ptr::Ptr{Cvoid},
        Int32(active)::Int32, value::BridgeColor)::Int32
end

"""Show the permanent asymptote-rail and paired-tracer instrument."""
function show_hyperbola_tool(state_ptr::Ptr{Cvoid})
    return @ccall show_hyperbola_tool(state_ptr::Ptr{Cvoid})::Int32
end

"""Hide the hyperbola apparatus without departing construction ink."""
function hide_hyperbola_tool(state_ptr::Ptr{Cvoid})
    return @ccall hide_hyperbola_tool(state_ptr::Ptr{Cvoid})::Int32
end

"""Translate the hyperbola instrument's shared center and elevation."""
function set_hyperbola_tool_position(state_ptr::Ptr{Cvoid}, position)
    value = (Cfloat(position[1]), Cfloat(position[2]), Cfloat(position[3]))
    return @ccall set_hyperbola_tool_position(state_ptr::Ptr{Cvoid},
        value::NTuple{3,Cfloat})::Int32
end

"""Configure the finite three-rail instrument and paired tracing parameter."""
function set_hyperbola_tool_geometry(state_ptr::Ptr{Cvoid};
    semimajor::Real, semiminor::Real, rotation::Real=0f0,
    parameter_start::Real, parameter_finish::Real,
    parameter::Real=parameter_start, rail_half_length::Real)
    geometry = BridgeHyperbolaToolGeometry(Cfloat(semimajor),
        Cfloat(semiminor), Cfloat(rotation), Cfloat(parameter_start),
        Cfloat(parameter_finish), Cfloat(parameter), Cfloat(rail_half_length))
    return @ccall set_hyperbola_tool_geometry(state_ptr::Ptr{Cvoid},
        geometry::BridgeHyperbolaToolGeometry)::Int32
end

"""Advance both sliding pen carriages at equal distances from the center."""
function set_hyperbola_tool_parameter(state_ptr::Ptr{Cvoid}, parameter::Real)
    return @ccall set_hyperbola_tool_parameter(state_ptr::Ptr{Cvoid},
        Cfloat(parameter)::Cfloat)::Int32
end

"""Activate selected ink contacts while both hyperbola pen bodies keep moving."""
function set_hyperbola_tool_active(
    state_ptr::Ptr{Cvoid}, active::Integer, color; branches::Symbol=:both)
    selection = hyperbola_branches(branches)
    value = _shape_color(color)
    return @ccall set_hyperbola_tool_active(state_ptr::Ptr{Cvoid},
        Int32(active)::Int32, value::BridgeColor, selection::Int32)::Int32
end

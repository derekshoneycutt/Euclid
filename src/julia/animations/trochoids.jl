"""Place a rolling ring guide and compass using the canonical trochoid geometry."""
function place_trochoid_tools(state_ptr::Ptr{Cvoid}, center, mode,
    fixed_radius::Real, rolling_radius::Real, tracer_distance::Real,
    parameter::Real, elevation::Real; rotation::Real=0f0, tracer_phase::Real=0f0)
    mode in (OdinJuliaBridge.TROCHOID_EXTERNAL, OdinJuliaBridge.TROCHOID_INTERNAL) ||
        throw(ArgumentError("trochoid animation mode must be external or internal"))
    geometry_mode = mode == OdinJuliaBridge.TROCHOID_EXTERNAL ?
        EuclidGeometry.TrochoidExternal : EuclidGeometry.TrochoidInternal
    raised_center = (center[1], center[2], center[3] + elevation)
    pose = EuclidGeometry.trochoid_tool_pose(raised_center, geometry_mode,
        fixed_radius, rolling_radius, parameter; rotation)
    tracer = EuclidGeometry.trochoid_point(raised_center, geometry_mode,
        fixed_radius, rolling_radius, tracer_distance, parameter; rotation, tracer_phase)
    checked_curve_status(
        OdinJuliaBridge.set_trochoid_tool_position(state_ptr, raised_center))
    checked_curve_status(
        OdinJuliaBridge.set_trochoid_tool_parameter(state_ptr, parameter))
    OdinJuliaBridge.lock_compass_joint1(state_ptr, pose.rolling_center; sweep=false)
    OdinJuliaBridge.lock_compass_joint2(state_ptr, tracer; sweep=false)
    return tracer
end

"""Lower the ring guide and inactive compass to a trochoid's starting parameter."""
function animate_trochoid_descend(state_ptr::Ptr{Cvoid}, timer::Real,
    duration::Real, topz::Real, center, parameter_start::Real;
    mode, fixed_radius::Real, rolling_radius::Real, tracer_distance::Real,
    rotation::Real=0f0, tracer_phase::Real=0f0)
    OdinJuliaBridge.set_compass_active(state_ptr, 0, :white)
    place_trochoid_tools(state_ptr, center, mode, fixed_radius, rolling_radius,
        tracer_distance, parameter_start,
        topz * (1f0 - normalized_progress(timer, duration)); rotation, tracer_phase)
    checked_curve_status(OdinJuliaBridge.show_trochoid_tool(state_ptr))
    OdinJuliaBridge.show_compass(state_ptr)
end

"""Draw a trochoid with one synchronized ring guide, compass, frontier and trail."""
function animate_draw_trochoid(state_ptr::Ptr{Cvoid}, timer::Real,
    duration::Real, center, parameter_start::Real, parameter_finish::Real;
    mode, fixed_radius::Real, rolling_radius::Real, tracer_distance::Real,
    curve_id::Integer, color, brush::Real, rotation::Real=0f0, tracer_phase::Real=0f0,
    draw_parameter::Real=parameter_finish)
    parameter = curve_parameter(timer, duration, parameter_start, draw_parameter)
    tracer = place_trochoid_tools(state_ptr, center, mode, fixed_radius,
        rolling_radius, tracer_distance, parameter, 0f0; rotation, tracer_phase)
    OdinJuliaBridge.set_compass_active(state_ptr, 3, color)
    checked_curve_status(OdinJuliaBridge.set_point_color(state_ptr, curve_id, color))
    checked_curve_status(OdinJuliaBridge.set_point_brush(state_ptr, curve_id, brush))
    checked_curve_status(
        OdinJuliaBridge.set_trochoid_frontier(state_ptr, curve_id, parameter))
    checked_curve_status(OdinJuliaBridge.show_point(state_ptr, curve_id))
    OdinJuliaBridge.emit_trailing_particle(state_ptr, tracer, color)
end

"""Lift the inactive ring guide and compass from the final trochoid parameter."""
function animate_trochoid_rise(state_ptr::Ptr{Cvoid}, timer::Real,
    duration::Real, topz::Real, center, parameter_finish::Real;
    mode, fixed_radius::Real, rolling_radius::Real, tracer_distance::Real,
    rotation::Real=0f0, tracer_phase::Real=0f0)
    OdinJuliaBridge.set_compass_active(state_ptr, 0, :white)
    place_trochoid_tools(state_ptr, center, mode, fixed_radius, rolling_radius,
        tracer_distance, parameter_finish, topz * normalized_progress(timer, duration);
        rotation, tracer_phase)
end

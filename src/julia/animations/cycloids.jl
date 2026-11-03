"""Place the literal rail, rolling guide, and compass at one parameter and height."""
function place_cycloid_tools(state_ptr::Ptr{Cvoid}, first, second,
    radius::Real, tracer_distance::Real, parameter::Real,
    elevation::Real; parameter_start::Real, parameter_finish::Real,
    tracer_phase::Real=0f0)
    raised_first = (first[1], first[2], first[3] + elevation)
    raised_second = (second[1], second[2], second[3] + elevation)
    pose = EuclidGeometry.cycloid_tool_pose(raised_first, raised_second,
        radius, parameter; parameter_start, parameter_finish)
    tracer = EuclidGeometry.cycloid_point(raised_first, raised_second,
        radius, tracer_distance, parameter;
        parameter_start, parameter_finish, tracer_phase)
    checked_curve_status(OdinJuliaBridge.set_cycloid_tool_line(
        state_ptr, raised_first, raised_second))
    checked_curve_status(
        OdinJuliaBridge.set_cycloid_tool_parameter(state_ptr, parameter))
    OdinJuliaBridge.lock_compass_joint1(state_ptr, pose.rolling_center; sweep=false)
    OdinJuliaBridge.lock_compass_joint2(state_ptr, tracer; sweep=false)
    return tracer
end

"""Lower the guide and inactive compass onto the curve's exact starting pose."""
function animate_cycloid_descend(state_ptr::Ptr{Cvoid}, timer::Real,
    duration::Real, topz::Real, first, second, radius::Real;
    tracer_distance::Real, parameter_start::Real, parameter_finish::Real,
    tracer_phase::Real=0f0)
    OdinJuliaBridge.set_compass_active(state_ptr, 0, :white)
    place_cycloid_tools(state_ptr, first, second, radius, tracer_distance,
        parameter_start, topz * (1f0 - normalized_progress(timer, duration));
        parameter_start, parameter_finish, tracer_phase)
    checked_curve_status(OdinJuliaBridge.show_cycloid_tool(state_ptr))
    OdinJuliaBridge.show_compass(state_ptr)
end

"""Draw a literal-rail cycloid with one synchronized guide, frontier and tracer."""
function animate_draw_cycloid(state_ptr::Ptr{Cvoid}, timer::Real,
    duration::Real, first, second, radius::Real;
    tracer_distance::Real, parameter_start::Real, parameter_finish::Real,
    curve_id::Integer, color, brush::Real, tracer_phase::Real=0f0)
    parameter = curve_parameter(timer, duration, parameter_start, parameter_finish)
    tracer = place_cycloid_tools(state_ptr, first, second, radius, tracer_distance,
        parameter, 0f0; parameter_start, parameter_finish, tracer_phase)
    OdinJuliaBridge.set_compass_active(state_ptr, 3, color)
    checked_curve_status(OdinJuliaBridge.set_point_color(state_ptr, curve_id, color))
    checked_curve_status(OdinJuliaBridge.set_point_brush(state_ptr, curve_id, brush))
    checked_curve_status(
        OdinJuliaBridge.set_cycloid_frontier(state_ptr, curve_id, parameter))
    checked_curve_status(OdinJuliaBridge.show_point(state_ptr, curve_id))
    OdinJuliaBridge.emit_trailing_particle(state_ptr, tracer, color)
end

"""Lift inactive instruments from the final cycloid parameter without drawing."""
function animate_cycloid_rise(state_ptr::Ptr{Cvoid}, timer::Real,
    duration::Real, topz::Real, first, second, radius::Real;
    tracer_distance::Real, parameter_start::Real, parameter_finish::Real,
    tracer_phase::Real=0f0)
    OdinJuliaBridge.set_compass_active(state_ptr, 0, :white)
    place_cycloid_tools(state_ptr, first, second, radius, tracer_distance,
        parameter_finish, topz * normalized_progress(timer, duration);
        parameter_start, parameter_finish, tracer_phase)
end

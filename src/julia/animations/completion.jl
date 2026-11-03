"""Establish a point's final ink directly, without tools, trails, or authored time."""
function complete_point(state_ptr::Ptr{Cvoid}, position, brush, color, entity)
    OdinJuliaBridge.set_point_position(state_ptr, entity, position)
    OdinJuliaBridge.set_point_brush(state_ptr, entity, brush)
    OdinJuliaBridge.set_point_color(state_ptr, entity, color)
    OdinJuliaBridge.show_point(state_ptr, entity)
end
"""Establish both endpoints and final line ink without replaying drawing motion."""
function complete_line(state_ptr::Ptr{Cvoid}, first, second;
    penbrush, pencolor, line_host_id, line_joint1_id, line_joint2_id)
    OdinJuliaBridge.set_point_position(state_ptr, line_joint1_id, first)
    OdinJuliaBridge.set_point_position(state_ptr, line_joint2_id, second)
    OdinJuliaBridge.set_point_brush(state_ptr, line_host_id, penbrush)
    OdinJuliaBridge.set_point_color(state_ptr, line_host_id, pencolor)
    OdinJuliaBridge.show_point(state_ptr, line_host_id)
end
"""Establish a full authored arc or sector directly without sweep contacts or formation."""
function complete_circle(state_ptr::Ptr{Cvoid}, center, start, sweep, radius;
    brush=0f0, color=:black, marker_host_id=0)
    angle = Float32(atan(start[2] - center[2], start[1] - center[1]))
    OdinJuliaBridge.set_point_position(state_ptr, marker_host_id, center)
    OdinJuliaBridge.set_arc_geometry(state_ptr, marker_host_id, radius, angle, sweep)
    OdinJuliaBridge.set_point_brush(state_ptr, marker_host_id, brush)
    OdinJuliaBridge.set_point_color(state_ptr, marker_host_id, color)
    OdinJuliaBridge.show_point(state_ptr, marker_host_id)
end
"""Start an animation-owned reveal interval for one label."""
function reveal_label(state_ptr::Ptr{Cvoid}, label_id::Integer; duration::Real)
    return OdinJuliaBridge.reveal_label!(state_ptr, label_id, duration)
end
"""Start an animation-owned reveal interval for one filled region."""
function reveal_region(state_ptr::Ptr{Cvoid}, region_id::Integer; duration::Real)
    return OdinJuliaBridge.reveal_region!(state_ptr, region_id, duration)
end

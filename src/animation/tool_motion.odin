package modifier

import geometry "../core/geometry"
import math "core:math"

RADIAL_TRAIL_SAMPLES :: 9

// Reject nonfinite geometry before expansion can publish invalid native state.
modifier_fields_finite :: proc(request: Modifier_Request) -> bool {
    vectors: [6]geometry.Vector3 = {
        request.start_position, request.second_position, request.third_position,
        request.displacement, request.axis_a, request.axis_b,
    }
    for vector in vectors {
        for component in vector {
            if math.is_nan(component) || math.is_inf(component) {
                return false
            }
        }
    }
    scalars: [4]f32 = {request.angle, request.radius, request.brush, request.scalar}
    for scalar in scalars {
        if math.is_nan(scalar) || math.is_inf(scalar) {
            return false
        }
    }
    return true
}

// Append visible tool material and the current contact feature.
append_tool_style :: proc(
    output: ^Modifier_Output_Buffer, entity: u64,
    color: u32, active: int) -> Modifier_Status {
    return modifier_output_append(output, {
        kind = .Set_Tool_Style,
        entity = entity,
        color_packed = color,
        integer = active,
        flag = true,
    })
}

// Append a bounded ordinary trail at one sampled position.
append_trail :: proc(
    output: ^Modifier_Output_Buffer,
    position: geometry.Vector3, color: u32) -> Modifier_Status {
    return modifier_output_append(output, {
        kind = .Emit_Trailing_Particle,
        position = position,
        color_packed = color,
    })
}

// Resolve explicit-time pen motion into the shared fixed-length pose request.
pen_motion_pose :: proc(request: Modifier_Request) -> Modifier_Request {
    pose := request
    pose.kind = .Pen_Pose
    progress := modifier_progress(request.elapsed, request.duration)
    #partial switch request.kind {
    case .Pen_Tilt:
        pose.angle += (request.brush - request.angle) * progress
    case .Pen_Cone:
        pose.scalar = request.elapsed * request.scalar
    case .Pen_Drag:
        pose.start_position +=
            (request.second_position - request.start_position) * progress
    case .Pen_Transfer:
        pose.start_position +=
            (request.second_position - request.start_position) * progress
        pose.start_position.z += math.abs(clamp(
            math.sin(progress * f32(request.integer) * f32(math.PI)) *
                request.scalar, -1, 1))
        pose.angle = f32(math.PI / 2)
        pose.scalar = 0
    }
    return pose
}

// Evaluate pen travel, tilt, cone, and drag without a native clock.
evaluate_pen_motion :: proc(
    request: Modifier_Request,
    output: ^Modifier_Output_Buffer) -> Modifier_Status {
    pose := pen_motion_pose(request)
    status := evaluate_pen_pose(pose, output)
    if status != .Ok {
        return status
    }
    active := 0
    color := u32(0xffffffff)
    if request.kind == .Pen_Drag {
        active = 1
        color = request.color_packed
    } else if request.kind == .Pen_Cone {
        return modifier_output_append(output, {
            kind = .Set_Tool_Visible,
            entity = request.entity,
            flag = true,
        })
    }
    status = append_tool_style(output, request.entity, color, active)
    if status != .Ok {
        return status
    }
    if request.kind == .Pen_Transfer {
        output.outputs[output.count - 1].kind = .Set_Tool_Active
    }
    if request.kind == .Pen_Drag {
        return append_trail(output, pose.start_position, request.color_packed)
    }
    if request.kind == .Pen_Transfer && request.flag && pose.start_position.z < 0.05 {
        pose.start_position.z = 0
        return append_trail(output, pose.start_position, request.color_packed)
    }
    return .Ok
}

// Return the signed XY orientation of a point relative to a segment.
xy_orientation :: proc(a, b, point: geometry.Vector3) -> f32 {
    return (b.x - a.x) * (point.y - a.y) -
        (b.y - a.y) * (point.x - a.x)
}

// Include collinear endpoint overlap when testing transfer path intersections.
xy_collinear_segment :: proc(a, b, point: geometry.Vector3, orientation: f32) -> bool {
    return math.abs(orientation) <= 1e-5 &&
        point.x >= min(a.x, b.x) - 1e-5 && point.x <= max(a.x, b.x) + 1e-5 &&
        point.y >= min(a.y, b.y) - 1e-5 && point.y <= max(a.y, b.y) + 1e-5
}

// Match the legacy inclusive crossing test for the two compass joint paths.
xy_segments_intersect :: proc(a, b, c, d: geometry.Vector3) -> bool {
    o1 := xy_orientation(a, b, c)
    o2 := xy_orientation(a, b, d)
    o3 := xy_orientation(c, d, a)
    o4 := xy_orientation(c, d, b)
    first_straddles := (o1 > 1e-5 && o2 < -1e-5) || (o1 < -1e-5 && o2 > 1e-5)
    second_straddles := (o3 > 1e-5 && o4 < -1e-5) || (o3 < -1e-5 && o4 > 1e-5)
    return first_straddles && second_straddles ||
        xy_collinear_segment(a, b, c, o1) || xy_collinear_segment(a, b, d, o2) ||
        xy_collinear_segment(c, d, a, o3) || xy_collinear_segment(c, d, b, o4)
}

// Return XY distance without including the authored travel height.
xy_distance :: proc(a, b: geometry.Vector3) -> f32 {
    return math.hypot(a.x - b.x, a.y - b.y)
}

// Route the outside joint around the inside path with the legacy bounded bow.
compass_detour :: proc(
    position: ^geometry.Vector3, path, other_path: [2]geometry.Vector3, progress: f32) {
    a, b := path[0], path[1]
    c, d := other_path[0], other_path[1]
    direction := b - a
    length := xy_distance(a, b)
    if length <= 1e-6 {
        return
    }
    side := math.sign(xy_orientation(a, b, a + (a - c)))
    if side == 0 {
        side = 1
    }
    span := (xy_distance(a, c) + xy_distance(b, d)) * 0.5
    offset := math.sin(progress * f32(math.PI)) * clamp(span * 0.15, 0.01, 0.05) * side
    position.x -= direction.y / length * offset
    position.y += direction.x / length * offset
}

// Preserve crossing-path detours and the original start-height transfer semantics.
compass_transfer_positions :: proc(
    request: Modifier_Request) -> (geometry.Vector3, geometry.Vector3) {
    progress := modifier_progress(request.elapsed, request.duration)
    a := request.start_position
    b := request.second_position
    c := request.third_position
    d := request.displacement
    first := a + (b - a) * progress
    second := c + (d - c) * progress
    z := math.sin(progress * f32(request.integer) * f32(math.PI)) * request.scalar
    first.z = a.z + z
    second.z = c.z + z
    if xy_segments_intersect(a, b, c, d) {
        center := (a + b + c + d) * 0.25
        first_radius := (xy_distance(a, center) + xy_distance(b, center)) * 0.5
        second_radius := (xy_distance(c, center) + xy_distance(d, center)) * 0.5
        if first_radius >= second_radius {
            compass_detour(&first, {a, b}, {c, d}, progress)
        } else {
            compass_detour(&second, {c, d}, {a, b}, progress)
        }
    }
    first.z = math.abs(clamp(first.z, -1, 1))
    second.z = math.abs(clamp(second.z, -1, 1))
    return first, second
}

// Emit both compass locks, visible inactive material, and optional paired strikes.
evaluate_compass_transfer :: proc(
    request: Modifier_Request, output: ^Modifier_Output_Buffer) -> Modifier_Status {
    first, second := compass_transfer_positions(request)
    status := evaluate_tool_vertical_outputs(request, first, second, output)
    if status != .Ok {
        return status
    }
    if request.flag && first.z < 0.05 {
        status = append_trail(output, first, request.color_packed)
        if status != .Ok {
            return status
        }
        return append_trail(output, second, request.color_packed)
    }
    return .Ok
}

// Evaluate marker-free compass highlights with ordinary or jittered radial trails.
evaluate_compass_highlight :: proc(
    request: Modifier_Request, output: ^Modifier_Output_Buffer) -> Modifier_Status {
    progress := modifier_progress(request.elapsed, request.duration)
    start := math.atan2(request.second_position.y - request.start_position.y,
        request.second_position.x - request.start_position.x)
    theta := start + request.angle * progress
    end_point: geometry.Vector3 = {
        request.start_position.x + request.radius * math.cos(theta),
        request.start_position.y + request.radius * math.sin(theta),
        0,
    }
    circle := request
    circle.kind = .Draw_Circle
    circle.third_entity = request.second_entity
    circle.second_entity = request.entity
    status := evaluate_circle_tools(circle, end_point, output)
    if status != .Ok {
        return status
    }
    if request.flag {
        return modifier_output_append(output, {
            kind = .Emit_Radial_Trail,
            position = request.start_position,
            second_position = end_point,
            color_packed = request.color_packed,
        })
    }
    return append_trail(output, end_point, request.color_packed)
}

// Set a segment's sampled endpoints and style without introducing a second trail.
evaluate_line_segment :: proc(
    request: Modifier_Request, output: ^Modifier_Output_Buffer) -> Modifier_Status {
    line := request
    line.kind = .Complete_Line
    status := evaluate_line(line, output)
    if status == .Ok {
        output.outputs[output.count - 1].flag = request.flag
    }
    return status
}

// Return the CCW projected sweep, including collapsed projected boundaries.
marker_ccw_sweep :: proc(center, start, end: geometry.Vector3) -> f32 {
    a := start - center
    b := end - center
    if xy_distance(start, center) <= 1e-6 || xy_distance(end, center) <= 1e-6 {
        return 0
    }
    sweep := math.atan2(a.x * b.y - a.y * b.x, a.x * b.x + a.y * b.y)
    if sweep < 0 {
        sweep += f32(2 * math.PI)
    }
    return sweep
}

// Evaluate one reflected boundary using the ordinary native half-turn evaluator.
reflected_marker_point :: proc(
    request: Modifier_Request,
    point: geometry.Vector3) -> (geometry.Vector3, Modifier_Status) {
    sample := request
    sample.kind = .Reflect_Point_Xy_Above
    sample.start_position = point
    output: Modifier_Output_Buffer
    status := evaluate_point_reflection(sample, &output)
    return output.outputs[0].position, status
}

// Preserve projected interior ordering throughout a reflected filled-angle sample.
evaluate_reflected_angle_marker :: proc(
    request: Modifier_Request, output: ^Modifier_Output_Buffer) -> Modifier_Status {
    if math.abs(request.axis_a.z) > 1e-6 || math.abs(request.axis_b.z) > 1e-6 {
        return .Invalid_Argument
    }
    center, status := reflected_marker_point(request, request.start_position)
    if status != .Ok {
        return status
    }
    start, _ := reflected_marker_point(request, request.second_position)
    end, _ := reflected_marker_point(request, request.third_position)
    if request.flag && marker_ccw_sweep(center, start, end) > f32(math.PI) {
        start, end = end, start
    }
    status = modifier_output_append(output, {
        kind = .Set_Point_Position,
        entity = request.entity,
        position = center,
    })
    if status != .Ok {
        return status
    }
    return modifier_output_append(output, {
        kind = .Set_Shape_Arc,
        entity = request.entity,
        arc_radius = xy_distance(start, center),
        arc_start = math.atan2(start.y - center.y, start.x - center.x),
        arc_sweep = marker_ccw_sweep(center, start, end),
    })
}

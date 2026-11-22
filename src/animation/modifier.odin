package modifier

import geometry "../core/geometry"
import math "core:math"
import linalg "core:math/linalg"
import shapemodel "../shapes/model"

MODIFIER_OUTPUT_CAPACITY :: 16

Modifier_Kind :: enum u8 {
    Identity,
    Set_Point_Position,
    Pen_Descend,
    Pen_Rise,
    Pen_Pose,
    Compass_Descend,
    Compass_Rise,
    Draw_Point,
    Draw_Line,
    Draw_Circle,
    Draw_Filled_Circle,
    Complete_Point,
    Complete_Line,
    Complete_Circle,
    Translate_Point,
    Rotate_Point,
    Reflect_Point_Xy_Above,
    Reflect_Point_Xy_Below,
    Pen_Tilt,
    Pen_Cone,
    Pen_Drag,
    Pen_Transfer,
    Compass_Transfer,
    Compass_Highlight,
    Line_Segment,
    Reflect_Angle_Marker,
    Pen_Highlight_Point,
    Pen_Stroke,
    Extend_Line,
    Two_Segment_Stroke,
    Cycloid_Place,
    Cycloid_Descend,
    Cycloid_Draw,
    Cycloid_Rise,
    Trochoid_Place,
    Trochoid_Descend,
    Trochoid_Draw,
    Trochoid_Rise,
    Parabola_Place,
    Parabola_Descend,
    Parabola_Draw,
    Parabola_Rise,
    Hyperbola_Place,
    Hyperbola_Descend,
    Hyperbola_Draw,
    Hyperbola_Rise,
    Rotate_Shape_Orientation,
}

Modifier_Status :: enum u8 {
    Ok,
    Invalid_Argument,
    Out_Of_Capacity,
}

Modifier_Request :: struct {
    kind: Modifier_Kind,
    entity: u64,
    second_entity: u64,
    third_entity: u64,
    elapsed: f32,
    duration: f32,
    start_position: geometry.Vector3,
    second_position: geometry.Vector3,
    third_position: geometry.Vector3,
    displacement: geometry.Vector3,
    axis_a: geometry.Vector3,
    axis_b: geometry.Vector3,
    angle: f32,
    radius: f32,
    brush: f32,
    color_packed: u32,
    scalar: f32,
    integer: int,
    flag: bool,
}

Modifier_Output_Kind :: enum u8 {
    Set_Point_Position,
    Set_Point_Color,
    Set_Point_Brush,
    Set_Point_Visible,
    Set_Point_Active_Color,
    Set_Point_Active_Feature,
    Set_Shape_Arc,
    Set_Tool_Position,
    Set_Tool_Lock,
    Set_Tool_Style,
    Emit_Trailing_Particle,
    Reveal_Sweep,
    Emit_Radial_Trail,
    Set_Tool_Visible,
    Set_Tool_Active,
    Set_Cycloid_Guide_Sample,
    Set_Trochoid_Guide_Sample,
    Set_Rolling_Guide_Visible,
    Set_Cycloid_Frontier,
    Set_Trochoid_Frontier,
    Set_Conic_Sample,
    Set_Conic_Active,
    Set_Conic_Visible,
    Set_Conic_Frontier,
    Set_Shape_Orientation,
    Queue_Tool_Contact,
}

Modifier_Output :: struct {
    kind: Modifier_Output_Kind,
    entity: u64,
    position: geometry.Vector3,
    second_position: geometry.Vector3,
    arc_radius: f32,
    arc_start: f32,
    arc_sweep: f32,
    color_packed: u32,
    scalar: f32,
    integer: int,
    flag: bool,
    cycloid_tool: shapemodel.Shape_Cycloid_Tool,
    trochoid_tool: shapemodel.Shape_Trochoid_Tool,
    orientation: quaternion128,
}

Modifier_Output_Buffer :: struct {
    count: int,
    overflowed: bool,
    outputs: [MODIFIER_OUTPUT_CAPACITY]Modifier_Output,
}

// Return whether one explicit-time modifier request is finite and well formed.
modifier_request_valid :: proc(request: Modifier_Request) -> bool {
    if math.is_nan(request.elapsed) || math.is_inf(request.elapsed) ||
        request.elapsed < 0 ||
        math.is_nan(request.duration) || math.is_inf(request.duration) ||
        request.duration < 0 || !modifier_fields_finite(request) {
        return false
    }
    #partial switch request.kind {
    case .Identity:
        return true
    case .Set_Point_Position, .Translate_Point, .Rotate_Point,
        .Reflect_Point_Xy_Above, .Reflect_Point_Xy_Below,
        .Draw_Point, .Complete_Point, .Complete_Circle,
        .Reflect_Angle_Marker:
        return request.entity != 0
    case .Pen_Descend, .Pen_Rise, .Pen_Pose,
        .Compass_Descend, .Compass_Rise, .Pen_Tilt, .Pen_Cone,
        .Pen_Drag, .Pen_Transfer, .Compass_Transfer, .Compass_Highlight:
        return request.second_entity != 0
    case .Pen_Highlight_Point, .Pen_Stroke:
        return request.radius > 0
    case .Draw_Line, .Complete_Line, .Draw_Circle,
        .Draw_Filled_Circle, .Line_Segment, .Extend_Line, .Two_Segment_Stroke:
        return request.entity != 0 && request.second_entity != 0 &&
            request.third_entity != 0
    case .Cycloid_Place, .Cycloid_Descend, .Cycloid_Draw, .Cycloid_Rise,
        .Trochoid_Place, .Trochoid_Descend, .Trochoid_Draw, .Trochoid_Rise:
        return rolling_request_valid(request)
    case .Parabola_Place, .Parabola_Descend, .Parabola_Draw, .Parabola_Rise,
        .Hyperbola_Place, .Hyperbola_Descend, .Hyperbola_Draw, .Hyperbola_Rise:
        return conic_request_valid(request)
    case .Rotate_Shape_Orientation:
        return orientation_request_valid(request)
    }
    return false
}

// Append one bounded modifier output and report overflow explicitly.
modifier_output_append :: proc(
    output: ^Modifier_Output_Buffer,
    value: Modifier_Output) -> Modifier_Status {
    if output.count >= len(output.outputs) {
        output.overflowed = true
        return .Out_Of_Capacity
    }
    output.outputs[output.count] = value
    output.count += 1
    return .Ok
}

// Return explicit progress clamped to the operation domain.
modifier_progress :: proc(elapsed: f32, duration: f32) -> f32 {
    if duration <= 0 {
        return 1
    }
    return clamp(elapsed / duration, 0, 1)
}

// Evaluate a direct or translated point sample.
evaluate_point_position :: proc(
    request: Modifier_Request,
    output: ^Modifier_Output_Buffer) -> Modifier_Status {
    progress := modifier_progress(request.elapsed, request.duration)
    position: geometry.Vector3 = request.start_position +
        request.displacement * progress
    value: Modifier_Output = {
        kind = .Set_Point_Position,
        entity = request.entity,
        position = position,
    }
    return modifier_output_append(output, value)
}

// Evaluate arbitrary-axis rotation.
evaluate_point_rotation :: proc(
    request: Modifier_Request,
    output: ^Modifier_Output_Buffer) -> Modifier_Status {
    progress := modifier_progress(request.elapsed, request.duration)
    axis := request.axis_b - request.axis_a
    axis_length := linalg.length(axis)
    if axis_length <= 0.000001 {
        return .Invalid_Argument
    }
    unit_axis := axis / axis_length
    relative := request.start_position - request.axis_a
    angle := request.angle * progress
    c := math.cos(angle)
    s := math.sin(angle)
    rotated_relative :=
        relative * c +
        linalg.cross(unit_axis, relative) * s +
        unit_axis * linalg.dot(unit_axis, relative) * (1 - c)
    position := request.axis_a + rotated_relative
    value: Modifier_Output = {
        kind = .Set_Point_Position,
        entity = request.entity,
        position = position,
    }
    return modifier_output_append(output, value)
}

// Evaluate above-surface or below-surface XY reflection.
evaluate_point_reflection :: proc(
    request: Modifier_Request,
    output: ^Modifier_Output_Buffer) -> Modifier_Status {
    progress := modifier_progress(request.elapsed, request.duration)
    axis := request.axis_b - request.axis_a
    axis_length := linalg.length(axis)
    if axis_length <= 0.000001 {
        return .Invalid_Argument
    }
    unit_axis: geometry.Vector3 = {
        axis.x / axis_length,
        axis.y / axis_length,
        0,
    }
    relative := request.start_position - request.axis_a
    relative.z = 0
    angle := f32(math.PI) * progress
    c := math.cos(angle)
    s := math.sin(angle)
    rotated_relative :=
        relative * c +
        linalg.cross(unit_axis, relative) * s +
        unit_axis * linalg.dot(unit_axis, relative) * (1 - c)
    rotated := request.axis_a + rotated_relative
    if request.kind == .Reflect_Point_Xy_Below {
        rotated.z = -rotated.z
    }
    position: geometry.Vector3 = {
        rotated.x,
        rotated.y,
        request.start_position.z + rotated.z,
    }
    value: Modifier_Output = {
        kind = .Set_Point_Position,
        entity = request.entity,
        position = position,
    }
    return modifier_output_append(output, value)
}

// Dispatch transform evaluation by operation kind.
evaluate_point_transform :: proc(
    request: Modifier_Request,
    output: ^Modifier_Output_Buffer) -> Modifier_Status {
    #partial switch request.kind {
    case .Rotate_Point:
        return evaluate_point_rotation(request, output)
    case .Reflect_Point_Xy_Above, .Reflect_Point_Xy_Below:
        return evaluate_point_reflection(request, output)
    case:
        return .Invalid_Argument
    }
}

// Evaluate the pen's fixed-length upper joint around its locked base.
evaluate_pen_pose :: proc(
    request: Modifier_Request,
    output: ^Modifier_Output_Buffer) -> Modifier_Status {
    horizontal_length := request.radius * math.cos(request.angle)
    tip: geometry.Vector3 = {
        request.start_position.x + horizontal_length * math.cos(request.scalar),
        request.start_position.y + horizontal_length * math.sin(request.scalar),
        request.start_position.z + request.radius * math.sin(request.angle),
    }
    first: Modifier_Output = {
        kind = .Set_Tool_Lock,
        entity = request.entity,
        position = request.start_position,
        flag = true,
    }
    second: Modifier_Output = {
        kind = .Set_Tool_Position,
        entity = request.second_entity,
        position = tip,
    }
    status := modifier_output_append(output, first)
    if status != .Ok {
        return status
    }
    return modifier_output_append(output, second)
}

// Emit tool joints and inactive visible material for a vertical motion sample.
evaluate_tool_vertical_outputs :: proc(
    request: Modifier_Request, first_position, second_position: geometry.Vector3,
    output: ^Modifier_Output_Buffer) -> Modifier_Status {
    first: Modifier_Output = {
        kind = .Set_Tool_Lock,
        entity = request.entity,
        position = first_position,
        flag = true,
    }
    second: Modifier_Output = {
        kind = .Set_Tool_Lock,
        entity = request.second_entity,
        position = second_position,
        flag = true,
    }
    if request.kind == .Pen_Descend || request.kind == .Pen_Rise {
        second.kind = .Set_Tool_Position
    }
    status := modifier_output_append(output, first)
    if status != .Ok {
        return status
    }
    status = modifier_output_append(output, second)
    if status != .Ok {
        return status
    }
    style: Modifier_Output = {
        kind = .Set_Tool_Style,
        entity = request.entity,
        color_packed = 0xffffffff,
        integer = 0,
        flag = true,
    }
    return modifier_output_append(output, style)
}

// Evaluate explicit-time descent and rise, retaining the pen's free upper joint.
evaluate_tool_position :: proc(
    request: Modifier_Request,
    output: ^Modifier_Output_Buffer) -> Modifier_Status {
    if request.kind == .Pen_Pose {
        return evaluate_pen_pose(request, output)
    }
    progress := modifier_progress(request.elapsed, request.duration)
    penz := request.scalar * (1 - progress)
    if request.kind == .Pen_Rise || request.kind == .Compass_Rise {
        penz = request.start_position.z +
            (request.scalar - request.start_position.z) * progress
    }
    first := request.start_position
    second := request.second_position
    first.z = penz
    second.z = penz
    if request.kind == .Pen_Descend || request.kind == .Pen_Rise {
        second.z += request.brush
    }
    return evaluate_tool_vertical_outputs(request, first, second, output)
}

// Establish one completed point directly without tools or particles.
evaluate_complete_point :: proc(
    request: Modifier_Request,
    output: ^Modifier_Output_Buffer) -> Modifier_Status {
    position: Modifier_Output = {
        kind = .Set_Point_Position,
        entity = request.entity,
        position = request.start_position,
    }
    status := modifier_output_append(output, position)
    if status != .Ok {
        return status
    }
    return append_visible_point_style(request, output)
}

// Append the shared brush, color, and visibility of established point-backed ink.
append_visible_point_style :: proc(
    request: Modifier_Request,
    output: ^Modifier_Output_Buffer) -> Modifier_Status {
    brush: Modifier_Output = {
        kind = .Set_Point_Brush,
        entity = request.entity,
        scalar = request.brush,
    }
    status := modifier_output_append(output, brush)
    if status != .Ok {
        return status
    }
    color: Modifier_Output = {
        kind = .Set_Point_Color,
        entity = request.entity,
        color_packed = request.color_packed,
    }
    status = modifier_output_append(output, color)
    if status != .Ok {
        return status
    }
    visible: Modifier_Output = {
        kind = .Set_Point_Visible,
        entity = request.entity,
        flag = true,
    }
    return modifier_output_append(output, visible)
}

// Establish sampled point color, brush, visibility, and optional trail output.
evaluate_draw_point :: proc(
    request: Modifier_Request,
    output: ^Modifier_Output_Buffer) -> Modifier_Status {
    progress := modifier_progress(request.elapsed, request.duration)
    position: geometry.Vector3 =
        request.start_position + request.displacement * progress
    status: Modifier_Status
    position_output: Modifier_Output = {
        kind = .Set_Point_Position,
        entity = request.entity,
        position = position,
    }
    status = modifier_output_append(output, position_output)
    if status != .Ok {
        return status
    }
    status = append_visible_point_style(request, output)
    if status != .Ok {
        return status
    }
    particle: Modifier_Output = {
        kind = .Emit_Trailing_Particle,
        position = position,
        color_packed = request.color_packed,
    }
    status = modifier_output_append(output, particle)
    if status != .Ok {
        return status
    }
    active: Modifier_Output = {
        kind = .Set_Tool_Style,
        entity = 0,
        integer = 1,
        color_packed = request.color_packed,
        flag = true,
    }
    return modifier_output_append(output, active)
}

// Establish point/line endpoints, brush, visibility, and optional trail.
evaluate_line :: proc(
    request: Modifier_Request,
    output: ^Modifier_Output_Buffer) -> Modifier_Status {
    progress := modifier_progress(request.elapsed, request.duration)
    tip := request.second_position
    if request.kind == .Draw_Line {
        tip = request.start_position +
            (request.second_position - request.start_position) * progress
    }
    status: Modifier_Status
    first: Modifier_Output = {
        kind = .Set_Point_Position,
        entity = request.second_entity,
        position = request.start_position,
    }
    status = modifier_output_append(output, first)
    if status != .Ok {
        return status
    }
    second: Modifier_Output = {
        kind = .Set_Point_Position,
        entity = request.third_entity,
        position = tip,
    }
    status = modifier_output_append(output, second)
    if status != .Ok {
        return status
    }
    status = append_visible_point_style(request, output)
    if status != .Ok {
        return status
    }
    if request.kind == .Complete_Line {
        return .Ok
    }
    particle: Modifier_Output = {
        kind = .Emit_Trailing_Particle,
        position = tip,
        color_packed = request.color_packed,
    }
    return modifier_output_append(output, particle)
}

// Evaluate circle or filled-sector mechanics and optional sweep reveal.
evaluate_circle_tools :: proc(
    request: Modifier_Request,
    end_point: geometry.Vector3,
    output: ^Modifier_Output_Buffer) -> Modifier_Status {
    pivot: Modifier_Output = {
        kind = .Set_Tool_Lock,
        entity = request.second_entity,
        position = request.start_position,
        flag = true,
    }
    status := modifier_output_append(output, pivot)
    if status != .Ok {
        return status
    }
    tracer: Modifier_Output = {
        kind = .Set_Tool_Lock,
        entity = request.third_entity,
        position = end_point,
        flag = true,
        integer = int(request.kind == .Draw_Filled_Circle),
    }
    status = modifier_output_append(output, tracer)
    if status != .Ok {
        return status
    }
    style: Modifier_Output = {
        kind = .Set_Tool_Style,
        entity = request.second_entity,
        color_packed = request.color_packed,
        integer = 3,
        flag = true,
    }
    return modifier_output_append(output, style)
}

// Publish sampled circle geometry, brush, visibility, trail, and reveal.
evaluate_circle_outputs :: proc(
    request: Modifier_Request,
    start_theta: f32,
    sweep: f32,
    end_point: geometry.Vector3,
    output: ^Modifier_Output_Buffer) -> Modifier_Status {
    arc: Modifier_Output = {
        kind = .Set_Shape_Arc,
        entity = request.entity,
        arc_radius = request.radius,
        arc_start = start_theta,
        arc_sweep = sweep,
    }
    status := modifier_output_append(output, arc)
    if status != .Ok {
        return status
    }
    brush: Modifier_Output = {
        kind = .Set_Point_Brush,
        entity = request.entity,
        scalar = request.brush,
    }
    status = modifier_output_append(output, brush)
    if status != .Ok {
        return status
    }
    color: Modifier_Output = {
        kind = .Set_Point_Color,
        entity = request.entity,
        color_packed = request.color_packed,
    }
    status = modifier_output_append(output, color)
    if status != .Ok {
        return status
    }
    visible: Modifier_Output = {
        kind = .Set_Point_Visible,
        entity = request.entity,
        flag = true,
    }
    status = modifier_output_append(output, visible)
    if status != .Ok {
        return status
    }
    return evaluate_circle_effects(request, end_point, output)
}

// Emit a circle's ordinary trail, radial highlight, or once-only sweep reveal.
evaluate_circle_effects :: proc(
    request: Modifier_Request, end_point: geometry.Vector3,
    output: ^Modifier_Output_Buffer) -> Modifier_Status {
    if request.kind == .Complete_Circle {
        return .Ok
    }
    if request.kind == .Draw_Filled_Circle && !request.flag {
        return modifier_output_append(output, {
            kind = .Emit_Radial_Trail,
            position = request.start_position,
            second_position = end_point,
            color_packed = request.color_packed,
        })
    }
    particle: Modifier_Output = {
        kind = .Emit_Trailing_Particle,
        position = end_point,
        color_packed = request.color_packed,
    }
    status := modifier_output_append(output, particle)
    if status != .Ok {
        return status
    }
    if request.kind == .Draw_Filled_Circle &&
        request.flag && request.elapsed <= 0 {
        reveal: Modifier_Output = {
            kind = .Reveal_Sweep,
            entity = request.entity,
            scalar = request.duration,
        }
        return modifier_output_append(output, reveal)
    }
    return .Ok
}

// Compose one sampled circle or filled-sector transaction.
evaluate_circle :: proc(
    request: Modifier_Request,
    output: ^Modifier_Output_Buffer) -> Modifier_Status {
    progress := modifier_progress(request.elapsed, request.duration)
    start_theta := math.atan2(
        request.second_position.y - request.start_position.y,
        request.second_position.x - request.start_position.x)
    sweep := request.angle
    if request.kind != .Complete_Circle {
        sweep *= progress
    }
    theta := start_theta + sweep
    end_point: geometry.Vector3 = {
        request.start_position.x + request.radius * math.cos(theta),
        request.start_position.y + request.radius * math.sin(theta),
        0,
    }
    if request.kind != .Complete_Circle {
        status := evaluate_circle_tools(request, end_point, output)
        if status != .Ok {
            return status
        }
    }
    return evaluate_circle_outputs(
        request, start_theta, sweep, end_point, output)
}

// Dispatch construction mechanics by operation kind.
evaluate_construction :: proc(
    request: Modifier_Request,
    output: ^Modifier_Output_Buffer) -> Modifier_Status {
    #partial switch request.kind {
    case .Draw_Point:
        return evaluate_draw_point(request, output)
    case .Draw_Line, .Complete_Line:
        return evaluate_line(request, output)
    case .Draw_Circle, .Draw_Filled_Circle, .Complete_Circle:
        return evaluate_circle(request, output)
    case .Complete_Point:
        return evaluate_complete_point(request, output)
    case:
        return .Invalid_Argument
    }
}

// Evaluate one bounded explicit-time native modifier without retained state.
evaluate_modifier :: proc(
    request: Modifier_Request,
    output: ^Modifier_Output_Buffer) -> Modifier_Status {
    if output == nil {
        return .Invalid_Argument
    }
    output^ = {}
    if !modifier_request_valid(request) {
        return .Invalid_Argument
    }
    return evaluate_valid_modifier(request, output)
}

// Dispatch one validated explicit-time sample through a single flat switch.
evaluate_valid_modifier :: proc(
    request: Modifier_Request,
    output: ^Modifier_Output_Buffer) -> Modifier_Status {
    #partial switch request.kind {
    case .Identity:
        return .Ok
    case .Set_Point_Position, .Translate_Point:
        return evaluate_point_position(request, output)
    case .Rotate_Point, .Reflect_Point_Xy_Above,
        .Reflect_Point_Xy_Below:
        return evaluate_point_transform(request, output)
    case .Pen_Descend, .Pen_Rise, .Pen_Pose,
        .Compass_Descend, .Compass_Rise:
        return evaluate_tool_position(request, output)
    case .Draw_Point, .Draw_Line, .Draw_Circle,
        .Draw_Filled_Circle, .Complete_Point, .Complete_Line,
        .Complete_Circle:
        return evaluate_construction(request, output)
    case .Pen_Tilt, .Pen_Cone, .Pen_Drag, .Pen_Transfer:
        return evaluate_pen_motion(request, output)
    case .Compass_Transfer:
        return evaluate_compass_transfer(request, output)
    case .Compass_Highlight:
        return evaluate_compass_highlight(request, output)
    case .Line_Segment:
        return evaluate_line_segment(request, output)
    case .Reflect_Angle_Marker:
        return evaluate_reflected_angle_marker(request, output)
    case .Pen_Highlight_Point, .Pen_Stroke, .Extend_Line:
        return evaluate_pen_stroke(request, output)
    case .Two_Segment_Stroke:
        return evaluate_two_segment_stroke(request, output)
    case .Cycloid_Place, .Cycloid_Descend, .Cycloid_Draw, .Cycloid_Rise:
        return evaluate_cycloid_motion(request, output)
    case .Trochoid_Place, .Trochoid_Descend, .Trochoid_Draw, .Trochoid_Rise:
        return evaluate_trochoid_motion(request, output)
    case .Parabola_Place, .Parabola_Descend, .Parabola_Draw, .Parabola_Rise,
        .Hyperbola_Place, .Hyperbola_Descend, .Hyperbola_Draw, .Hyperbola_Rise:
        return evaluate_conic_motion(request, output)
    case .Rotate_Shape_Orientation:
        return evaluate_shape_orientation(request, output)
    }
    return .Invalid_Argument
}

package modifier

import geometry "../core/geometry"
import math "core:math"

REPL_TOOL_TRAVEL_TOP_Z :: 1.4
REPL_DESCEND_SHARE :: 0.2
REPL_DRAW_SHARE :: 0.6
REPL_DRAW_END :: REPL_DESCEND_SHARE + REPL_DRAW_SHARE
RECIPE_PEN_STRAIGHT_ANGLE :: f32(math.PI / 2)
RECIPE_PEN_LINE_ANGLE :: f32(math.PI / 3)
RECIPE_PEN_CONE_RADIUS :: 0.02
RECIPE_PEN_CONE_SPIN_SPEED :: 6

Construction_Pen_Tilt :: struct {
    position: geometry.Vector3,
    elapsed: f32,
    duration: f32,
    start_angle: f32,
    end_angle: f32,
    azimuth: f32,
}

// Derive the cone angle from the authored fixed pen length and tip radius.
recipe_pen_cone_angle :: proc() -> f32 {
    length := f32(0.35)
    radius := f32(RECIPE_PEN_CONE_RADIUS)
    return math.atan2(math.sqrt(length * length - radius * radius), radius)
}

// Mark phase crossings only after the preceding sample committed successfully.
construction_transition_flags :: proc(
    kind: Modifier_Kind, previous, current, duration: f64) -> int {
    if !construction_recipe_kind(kind) {
        return 0
    }
    if duration <= 0 {
        return CONSTRUCTION_DRAW_ENTRY_FLAG
    }
    draw_start := duration * REPL_DESCEND_SHARE
    if previous < draw_start && current >= draw_start {
        return CONSTRUCTION_DRAW_ENTRY_FLAG
    }
    return 0
}

// Identify recipe modifiers that own a full REPL construction lifecycle.
construction_recipe_kind :: proc(kind: Modifier_Kind) -> bool {
    return kind == .Construct_Point || kind == .Construct_Line ||
        kind == .Construct_Circle || kind == .Construct_Filled_Circle
}

// Recipe requests use entity for the host, positions for geometry, and second/
// third entities for line endpoints or the compass joints used by circle recipes.
// Dispatch one native point, line, or circle construction sample.
evaluate_construction_recipe :: proc(
    request: Modifier_Request, output: ^Modifier_Output_Buffer) -> Modifier_Status {
    status := Modifier_Status.Invalid_Argument
    #partial switch request.kind {
    case .Construct_Point:
        status = evaluate_point_recipe(request, output)
    case .Construct_Line:
        status = evaluate_line_recipe(request, output)
    case .Construct_Circle, .Construct_Filled_Circle:
        status = evaluate_circle_recipe(request, output)
    }
    if status != .Ok || request.elapsed < request.duration {
        return status
    }
    tool_entity := u64(0)
    if request.kind == .Construct_Circle ||
        request.kind == .Construct_Filled_Circle {
        tool_entity = 2
    }
    return modifier_output_append(output, {
        kind = .Set_Tool_Visible,
        entity = tool_entity,
        flag = false,
    })
}

// Evaluate REPL descent, nested pen stroke, and rise for one point primitive.
evaluate_point_recipe :: proc(
    request: Modifier_Request, output: ^Modifier_Output_Buffer) -> Modifier_Status {
    draw_start := request.duration * REPL_DESCEND_SHARE
    draw_end := request.duration * REPL_DRAW_END
    elapsed := min(request.elapsed, request.duration)
    if request.duration <= 0 {
        status := evaluate_point_geometry(request, output)
        if status != .Ok {
            return status
        }
        return evaluate_pen_vertical(request, .Pen_Rise, 0, 0, output)
    }
    if elapsed < draw_start {
        return evaluate_pen_vertical(
            request, .Pen_Descend, elapsed, draw_start, output)
    }
    if elapsed < draw_end {
        return evaluate_point_stroke(request, elapsed - draw_start,
            request.duration * REPL_DRAW_SHARE, output)
    }
    status := evaluate_point_geometry(request, output)
    if status != .Ok {
        return status
    }
    return evaluate_pen_vertical(request, .Pen_Rise,
        elapsed - draw_end, request.duration - draw_end, output)
}

// Evaluate nested straight-to-cone point contact within the REPL draw phase.
evaluate_point_stroke :: proc(
    request: Modifier_Request, elapsed, duration: f32,
    output: ^Modifier_Output_Buffer) -> Modifier_Status {
    tilt_end := duration * 0.15
    cone_end := duration * 0.85
    if elapsed < tilt_end {
        return evaluate_pen_tilt(request, {
            position = request.start_position,
            elapsed = elapsed,
            duration = tilt_end,
            start_angle = RECIPE_PEN_STRAIGHT_ANGLE,
            end_angle = recipe_pen_cone_angle(),
        }, output)
    }
    if elapsed < cone_end {
        return evaluate_point_contact(request, elapsed, duration, output)
    }
    status := evaluate_point_geometry(request, output)
    if status != .Ok {
        return status
    }
    spin := duration * 0.7 * RECIPE_PEN_CONE_SPIN_SPEED
    return evaluate_pen_tilt(request, {
        position = request.start_position,
        elapsed = elapsed - cone_end,
        duration = duration * 0.15,
        start_angle = recipe_pen_cone_angle(),
        end_angle = RECIPE_PEN_STRAIGHT_ANGLE,
        azimuth = spin,
    }, output)
}

// Commit point geometry and tool contact during the nested cone phase.
evaluate_point_contact :: proc(
    request: Modifier_Request, elapsed, duration: f32,
    output: ^Modifier_Output_Buffer) -> Modifier_Status {
    tilt_end := duration * 0.15
    status := evaluate_pen_cone(request, elapsed - tilt_end,
        duration * 0.7, output)
    if status != .Ok {
        return status
    }
    draw := request
    draw.kind = .Draw_Point
    draw.elapsed = elapsed - tilt_end
    draw.duration = duration * 0.7
    return evaluate_draw_point(draw, output)
}

// Evaluate REPL descent, nested pen drag, and rise for one line primitive.
evaluate_line_recipe :: proc(
    request: Modifier_Request, output: ^Modifier_Output_Buffer) -> Modifier_Status {
    draw_start := request.duration * REPL_DESCEND_SHARE
    draw_end := request.duration * REPL_DRAW_END
    elapsed := min(request.elapsed, request.duration)
    if request.duration <= 0 {
        status := evaluate_line_geometry(request, output)
        if status != .Ok {
            return status
        }
        rise := request
        rise.start_position = request.second_position
        return evaluate_pen_vertical(rise, .Pen_Rise, 0, 0, output)
    }
    if elapsed < draw_start {
        return evaluate_pen_vertical(
            request, .Pen_Descend, elapsed, draw_start, output)
    }
    if elapsed < draw_end {
        return evaluate_line_stroke(request, elapsed - draw_start,
            request.duration * REPL_DRAW_SHARE, output)
    }
    status := evaluate_line_geometry(request, output)
    if status != .Ok {
        return status
    }
    rise := request
    rise.start_position = request.second_position
    return evaluate_pen_vertical(rise, .Pen_Rise,
        elapsed - draw_end, request.duration - draw_end, output)
}

// Evaluate nested tilt, drag, and tilt samples for a native line.
evaluate_line_stroke :: proc(
    request: Modifier_Request, elapsed, duration: f32,
    output: ^Modifier_Output_Buffer) -> Modifier_Status {
    tilt_end := duration * 0.15
    drag_end := duration * 0.85
    azimuth := math.atan2(
        request.second_position.y - request.start_position.y,
        request.second_position.x - request.start_position.x)
    if elapsed < tilt_end {
        return evaluate_pen_tilt(request, {
            position = request.start_position,
            elapsed = elapsed,
            duration = tilt_end,
            start_angle = RECIPE_PEN_STRAIGHT_ANGLE,
            end_angle = RECIPE_PEN_LINE_ANGLE,
            azimuth = azimuth,
        }, output)
    }
    if elapsed < drag_end {
        return evaluate_line_contact(request, elapsed, duration, output)
    }
    status := evaluate_line_geometry(request, output)
    if status != .Ok {
        return status
    }
    return evaluate_pen_tilt(request, {
        position = request.second_position,
        elapsed = elapsed - drag_end,
        duration = duration * 0.15,
        start_angle = RECIPE_PEN_LINE_ANGLE,
        end_angle = RECIPE_PEN_STRAIGHT_ANGLE,
        azimuth = azimuth,
    }, output)
}

// Commit line geometry and pen drag in one ordered sample.
evaluate_line_contact :: proc(
    request: Modifier_Request, elapsed, duration: f32,
    output: ^Modifier_Output_Buffer) -> Modifier_Status {
    tilt_end := duration * 0.15
    status := evaluate_pen_drag(request, elapsed - tilt_end,
        duration * 0.7, output)
    if status != .Ok {
        return status
    }
    draw := request
    draw.kind = .Draw_Line
    draw.elapsed = elapsed - tilt_end
    draw.duration = duration * 0.7
    return evaluate_line(draw, output)
}

// Evaluate compass descent, circle geometry, and rise for a circle or sector.
evaluate_circle_recipe :: proc(
    request: Modifier_Request, output: ^Modifier_Output_Buffer) -> Modifier_Status {
    draw_start := request.duration * REPL_DESCEND_SHARE
    draw_end := request.duration * REPL_DRAW_END
    elapsed := min(request.elapsed, request.duration)
    if request.duration <= 0 {
        status := evaluate_circle_draw(request, 0, 0, true, output)
        if status != .Ok {
            return status
        }
        return evaluate_compass_vertical(request, .Compass_Rise, 0, 0, output)
    }
    if elapsed < draw_start {
        return evaluate_compass_vertical(
            request, .Compass_Descend, elapsed, draw_start, output)
    }
    if elapsed < draw_end {
        return evaluate_circle_draw(
            request, elapsed - draw_start,
            request.duration * REPL_DRAW_SHARE,
            request.integer & CONSTRUCTION_DRAW_ENTRY_FLAG != 0 ||
                elapsed == draw_start, output)
    }
    status: Modifier_Status
    if request.integer & CONSTRUCTION_DRAW_ENTRY_FLAG != 0 {
        status = evaluate_circle_draw(request, request.duration*REPL_DRAW_SHARE,
            request.duration*REPL_DRAW_SHARE, true, output)
    } else {
        status = evaluate_circle_geometry(request, output)
    }
    if status != .Ok {
        return status
    }
    return evaluate_compass_vertical(request, .Compass_Rise,
        elapsed - draw_end, request.duration - draw_end, output)
}

// Convert one sampled circle phase into the existing native circle modifier.
evaluate_circle_draw :: proc(
    request: Modifier_Request, elapsed, duration: f32, draw_entry: bool,
    output: ^Modifier_Output_Buffer) -> Modifier_Status {
    draw := request
    draw.kind = .Draw_Circle
    if request.kind == .Construct_Filled_Circle {
        draw.kind = .Draw_Filled_Circle
    }
    draw.elapsed = elapsed
    draw.duration = duration
    draw.integer = 0
    if draw_entry {
        draw.integer = CONSTRUCTION_DRAW_ENTRY_FLAG
    }
    return evaluate_circle(draw, output)
}

// Establish the completed point geometry without repeating drawing effects.
evaluate_point_geometry :: proc(
    request: Modifier_Request, output: ^Modifier_Output_Buffer) -> Modifier_Status {
    complete := request
    complete.kind = .Complete_Point
    complete.elapsed = 0
    complete.duration = 0
    return evaluate_complete_point(complete, output)
}

// Establish the completed line geometry without repeating drawing effects.
evaluate_line_geometry :: proc(
    request: Modifier_Request, output: ^Modifier_Output_Buffer) -> Modifier_Status {
    complete := request
    complete.kind = .Complete_Line
    complete.elapsed = 0
    complete.duration = 0
    return evaluate_line(complete, output)
}

// Establish the completed arc or sector without repeating drawing effects.
evaluate_circle_geometry :: proc(
    request: Modifier_Request, output: ^Modifier_Output_Buffer) -> Modifier_Status {
    complete := request
    complete.kind = .Complete_Circle
    complete.elapsed = 0
    complete.duration = 0
    return evaluate_circle(complete, output)
}

// Compose one fixed-length pen vertical phase from the REPL recipe input.
evaluate_pen_vertical :: proc(
    request: Modifier_Request, kind: Modifier_Kind,
    elapsed, duration: f32, output: ^Modifier_Output_Buffer) -> Modifier_Status {
    position := request.start_position
    if kind == .Pen_Rise {
        position.z = 0
    } else {
        position.z = REPL_TOOL_TRAVEL_TOP_Z
    }
    pen: Modifier_Request = {
        kind = kind,
        entity = 0,
        second_entity = 1,
        elapsed = elapsed,
        duration = duration,
        start_position = position,
        second_position = position,
        scalar = REPL_TOOL_TRAVEL_TOP_Z,
        brush = request.radius,
    }
    return evaluate_tool_position(pen, output)
}

// Compose one compass vertical phase with its pivot and tracer endpoints.
evaluate_compass_vertical :: proc(
    request: Modifier_Request, kind: Modifier_Kind,
    elapsed, duration: f32, output: ^Modifier_Output_Buffer) -> Modifier_Status {
    first := request.start_position
    second := request.second_position
    first.z = 0
    second.z = 0
    if kind == .Compass_Descend {
        first.z = REPL_TOOL_TRAVEL_TOP_Z
        second.z = REPL_TOOL_TRAVEL_TOP_Z
    } else {
        start_theta := math.atan2(
            request.second_position.y - request.start_position.y,
            request.second_position.x - request.start_position.x)
        end_theta := start_theta + request.angle
        second.x = request.start_position.x + request.radius * math.cos(end_theta)
        second.y = request.start_position.y + request.radius * math.sin(end_theta)
    }
    compass: Modifier_Request = {
        kind = kind,
        entity = request.second_entity,
        second_entity = request.third_entity,
        elapsed = elapsed,
        duration = duration,
        start_position = first,
        second_position = second,
        scalar = REPL_TOOL_TRAVEL_TOP_Z,
    }
    return evaluate_tool_position(compass, output)
}

// Compose one pen tilt at an explicit base position and azimuth.
evaluate_pen_tilt :: proc(
    request: Modifier_Request, tilt: Construction_Pen_Tilt,
    output: ^Modifier_Output_Buffer) -> Modifier_Status {
    pen: Modifier_Request = {
        kind = .Pen_Tilt,
        entity = 0,
        second_entity = 1,
        elapsed = tilt.elapsed,
        duration = tilt.duration,
        start_position = tilt.position,
        radius = request.radius,
        angle = tilt.start_angle,
        brush = tilt.end_angle,
        scalar = tilt.azimuth,
    }
    return evaluate_pen_motion(pen, output)
}

// Compose one cone-contact sample using the request's pen length.
evaluate_pen_cone :: proc(
    request: Modifier_Request, elapsed, duration: f32,
    output: ^Modifier_Output_Buffer) -> Modifier_Status {
    pen: Modifier_Request = {
        kind = .Pen_Cone,
        entity = 0,
        second_entity = 1,
        elapsed = elapsed,
        duration = duration,
        start_position = request.start_position,
        radius = request.radius,
        angle = recipe_pen_cone_angle(),
        scalar = RECIPE_PEN_CONE_SPIN_SPEED,
    }
    return evaluate_pen_motion(pen, output)
}

// Compose one pen-drag sample along the recipe's directed line segment.
evaluate_pen_drag :: proc(
    request: Modifier_Request, elapsed, duration: f32,
    output: ^Modifier_Output_Buffer) -> Modifier_Status {
    azimuth := math.atan2(
        request.second_position.y - request.start_position.y,
        request.second_position.x - request.start_position.x)
    pen: Modifier_Request = {
        kind = .Pen_Drag,
        entity = 0,
        second_entity = 1,
        elapsed = elapsed,
        duration = duration,
        start_position = request.start_position,
        second_position = request.second_position,
        radius = request.radius,
        angle = RECIPE_PEN_LINE_ANGLE,
        scalar = azimuth,
        color_packed = request.color_packed,
    }
    return evaluate_pen_motion(pen, output)
}

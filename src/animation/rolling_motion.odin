package modifier

import curve "../shapes/curve"
import geometry "../core/geometry"
import shapemodel "../shapes/model"

ROLLING_SEQUENCE_DESCEND_SHARE :: 0.2
ROLLING_SEQUENCE_DRAW_SHARE :: 0.6

Rolling_Sequence_Samples :: struct {
    count: int,
    requests: [3]Modifier_Request,
}

// Retain one explicit-time rolling sample on the stack, never across callbacks.
Rolling_Sample :: struct {
    parameter: f32,
    elevation: f32,
    drawing: bool,
    descending: bool,
    placing: bool,
}

// Resolve the parameter and elevation without introducing a native phase clock.
rolling_sample :: proc(request: Modifier_Request) -> Rolling_Sample {
    sample: Rolling_Sample = {
        parameter = request.third_position.x,
        elevation = request.scalar,
    }
    progress := modifier_progress(request.elapsed, request.duration)
    #partial switch request.kind {
    case .Cycloid_Place, .Trochoid_Place:
        sample.placing = true
        sample.parameter = request.third_position.z
    case .Cycloid_Descend, .Trochoid_Descend:
        sample.elevation *= 1 - progress
        sample.descending = true
    case .Cycloid_Draw, .Trochoid_Draw:
        sample.drawing = true
        sample.elevation = 0
        sample.parameter +=
            (request.third_position.z - request.third_position.x) * progress
        if progress == 1 {
            sample.parameter = request.third_position.z
        }
    case .Cycloid_Rise, .Trochoid_Rise:
        sample.parameter = request.third_position.z
        sample.elevation *= progress
    }
    return sample
}

// Build the canonical Cycloid geometry from the copied compatibility payload.
rolling_cycloid_value :: proc(request: Modifier_Request) -> shapemodel.Shape_Cycloid {
    return {
        rolling_radius = request.radius,
        tracer_distance = request.displacement.x,
        tracer_phase = request.displacement.y,
        parameter_start = request.third_position.x,
        parameter_finish = request.third_position.y,
        draw_parameter = request.third_position.z,
    }
}

// Build canonical Trochoid geometry without changing intrinsic axes or rotation.
rolling_trochoid_value :: proc(request: Modifier_Request) -> shapemodel.Shape_Trochoid {
    return {
        mode = shapemodel.Shape_Trochoid_Mode(request.integer),
        fixed_radius = request.displacement.x,
        rolling_radius = request.radius,
        tracer_distance = request.displacement.y,
        tracer_phase = request.displacement.z,
        rotation = request.angle,
        parameter_start = request.third_position.x,
        parameter_finish = request.third_position.y,
        draw_parameter = request.third_position.z,
    }
}

// Validate rolling inputs before calling canonical geometry with degenerate scales.
rolling_request_valid :: proc(request: Modifier_Request) -> bool {
    #partial switch request.kind {
    case .Cycloid_Place, .Cycloid_Descend, .Cycloid_Draw, .Cycloid_Rise:
        value := rolling_cycloid_value(request)
        return shapemodel.shape_cycloid_is_valid(value) &&
            shapemodel.shape_cycloid_line_is_valid(
                request.start_position, request.second_position, request.radius,
                value.parameter_start, value.parameter_finish) &&
            (request.kind != .Cycloid_Draw || request.entity != 0)
    case .Cycloid_Sequence:
        value := rolling_cycloid_value(request)
        return request.duration > 0 && request.entity != 0 &&
            request.second_entity != 0 && request.third_entity != 0 &&
            shapemodel.shape_cycloid_is_valid(value) &&
            shapemodel.shape_cycloid_line_is_valid(
                request.start_position, request.second_position, request.radius,
                value.parameter_start, value.parameter_finish)
    case .Trochoid_Place, .Trochoid_Descend, .Trochoid_Draw, .Trochoid_Rise:
        return request.integer >= 0 && request.integer <= 1 &&
            shapemodel.shape_trochoid_tool_is_valid({
                mode = shapemodel.Shape_Trochoid_Mode(request.integer),
                fixed_radius = request.displacement.x,
                rolling_radius = request.radius,
                parameter = request.third_position.x,
                rotation = request.angle,
            }) && request.displacement.y >= 0 &&
            (request.kind != .Trochoid_Draw ||
                (request.entity != 0 &&
                    shapemodel.shape_trochoid_is_valid(rolling_trochoid_value(request))))
    case .Trochoid_Sequence:
        return request.duration > 0 && request.entity != 0 &&
            request.integer >= 0 && request.integer <= 1 &&
            shapemodel.shape_trochoid_tool_is_valid({
                mode = shapemodel.Shape_Trochoid_Mode(request.integer),
                fixed_radius = request.displacement.x,
                rolling_radius = request.radius,
                parameter = request.third_position.x,
                rotation = request.angle,
            }) && request.displacement.y >= 0 &&
            shapemodel.shape_trochoid_is_valid(rolling_trochoid_value(request))
    }
    return false
}

// Sample every phase boundary skipped by one accepted full-duration clock step.
rolling_sequence_samples :: proc(
    template: Modifier_Request,
    previous_elapsed, current_elapsed: f32) -> Rolling_Sequence_Samples {
    samples: Rolling_Sequence_Samples
    descend_end := template.duration * ROLLING_SEQUENCE_DESCEND_SHARE
    draw_end := template.duration *
        (ROLLING_SEQUENCE_DESCEND_SHARE + ROLLING_SEQUENCE_DRAW_SHARE)
    boundary_is_current := false
    if previous_elapsed < descend_end && current_elapsed >= descend_end {
        rolling_sequence_append(&samples,
            rolling_sequence_phase_request(template, descend_end))
        boundary_is_current = current_elapsed == descend_end
    }
    if previous_elapsed < draw_end && current_elapsed >= draw_end {
        rolling_sequence_append(&samples,
            rolling_sequence_phase_request(template, draw_end))
        boundary_is_current = current_elapsed == draw_end
    }
    if !boundary_is_current {
        rolling_sequence_append(&samples,
            rolling_sequence_phase_request(template, current_elapsed))
    }
    return samples
}

// Resolve one full-duration clock value to its underlying explicit-time phase.
rolling_sequence_phase_request :: proc(
    template: Modifier_Request, elapsed: f32) -> Modifier_Request {
    descend_end := template.duration * ROLLING_SEQUENCE_DESCEND_SHARE
    draw_end := template.duration *
        (ROLLING_SEQUENCE_DESCEND_SHARE + ROLLING_SEQUENCE_DRAW_SHARE)
    phase := template
    if template.kind == .Cycloid_Sequence {
        phase.kind = .Cycloid_Descend
    } else {
        phase.kind = .Trochoid_Descend
    }
    phase.duration = descend_end
    phase.elapsed = min(elapsed, descend_end)
    if elapsed > descend_end && elapsed <= draw_end {
        phase.kind = rolling_sequence_kind(template.kind, true)
        phase.duration = template.duration * ROLLING_SEQUENCE_DRAW_SHARE
        phase.elapsed = elapsed - descend_end
    } else if elapsed > draw_end {
        phase.kind = rolling_sequence_kind(template.kind, false)
        phase.duration = template.duration *
            (1 - ROLLING_SEQUENCE_DESCEND_SHARE - ROLLING_SEQUENCE_DRAW_SHARE)
        phase.elapsed = elapsed - draw_end
    }
    return phase
}

// Select draw or rise while retaining the sequence family.
rolling_sequence_kind :: proc(kind: Modifier_Kind, drawing: bool) -> Modifier_Kind {
    if kind == .Cycloid_Sequence {
        if drawing {
            return .Cycloid_Draw
        }
        return .Cycloid_Rise
    }
    if drawing {
        return .Trochoid_Draw
    }
    return .Trochoid_Rise
}

// Append one bounded phase request to the fixed sequence sample.
rolling_sequence_append :: proc(
    samples: ^Rolling_Sequence_Samples, request: Modifier_Request) {
    assert(samples != nil && samples^.count < len(samples^.requests))
    samples^.requests[samples^.count] = request
    samples^.count += 1
}

// Evaluate one sequence request at its current phase for direct modifier callers.
evaluate_rolling_sequence_sample :: proc(
    request: Modifier_Request, output: ^Modifier_Output_Buffer) -> Modifier_Status {
    phase := rolling_sequence_phase_request(request, request.elapsed)
    return evaluate_modifier(phase, output)
}

// Emit both compass locks with sweep disabled for rolling-curve contact.
append_rolling_compass :: proc(
    output: ^Modifier_Output_Buffer,
    center, tracer: geometry.Vector3) -> Modifier_Status {
    status := modifier_output_append(output, {
        kind = .Set_Tool_Lock,
        entity = 2,
        position = center,
        flag = true,
    })
    if status != .Ok {
        return status
    }
    return modifier_output_append(output, {
        kind = .Set_Tool_Lock,
        entity = 3,
        position = tracer,
        flag = true,
    })
}

// Publish curve style and exact frontier without touching its analytic orientation.
append_rolling_ink :: proc(
    request: Modifier_Request, sample: Rolling_Sample,
    output: ^Modifier_Output_Buffer, cycloid: bool) -> Modifier_Status {
    values: [4]Modifier_Output = {
        {
            kind = .Set_Point_Color,
            entity = request.entity,
            color_packed = request.color_packed,
        },
        {
            kind = .Set_Point_Brush,
            entity = request.entity,
            scalar = request.brush,
        },
        {
            kind = .Set_Trochoid_Frontier,
            entity = request.entity,
            scalar = sample.parameter,
        },
        {
            kind = .Set_Point_Visible,
            entity = request.entity,
            flag = true,
        },
    }
    if cycloid {
        values[2].kind = .Set_Cycloid_Frontier
    }
    for value in values {
        status := modifier_output_append(output, value)
        if status != .Ok {
            return status
        }
    }
    return .Ok
}

// Preserve descent visibility, drawing contact, rise inactivity, and ordinary trails.
append_rolling_effects :: proc(
    request: Modifier_Request, sample: Rolling_Sample,
    tracer: geometry.Vector3, output: ^Modifier_Output_Buffer,
    cycloid: bool) -> Modifier_Status {
    if sample.placing {
        return .Ok
    }
    style: Modifier_Output = {
        kind = .Set_Tool_Active,
        entity = 2,
        color_packed = 0xffffffff,
    }
    if sample.descending {
        style.kind = .Set_Tool_Style
        style.flag = true
    } else if sample.drawing {
        style.color_packed = request.color_packed
        style.integer = 3
    }
    status := modifier_output_append(output, style)
    if status != .Ok {
        return status
    }
    if sample.descending {
        return modifier_output_append(output, {
            kind = .Set_Rolling_Guide_Visible,
            integer = int(!cycloid),
            flag = true,
        })
    }
    if !sample.drawing {
        return .Ok
    }
    status = append_rolling_ink(request, sample, output, cycloid)
    if status != .Ok {
        return status
    }
    return append_trail(output, tracer, request.color_packed)
}

// Evaluate the literal rail and tracer through canonical native Cycloid geometry.
evaluate_cycloid_motion :: proc(
    request: Modifier_Request, output: ^Modifier_Output_Buffer) -> Modifier_Status {
    sample := rolling_sample(request)
    first := request.start_position
    second := request.second_position
    first.z += sample.elevation
    second.z += sample.elevation
    value := rolling_cycloid_value(request)
    pose := curve.cycloid_tool_pose(first, second, {
        rolling_radius = value.rolling_radius,
        parameter_start = value.parameter_start,
        parameter_finish = value.parameter_finish,
        parameter = sample.parameter,
    })
    tracer := curve.cycloid_point(first, second, value, sample.parameter)
    status := modifier_output_append(output, {
        kind = .Set_Cycloid_Guide_Sample,
        position = first,
        second_position = second,
        cycloid_tool = {
            rolling_radius = value.rolling_radius,
            parameter_start = value.parameter_start,
            parameter_finish = value.parameter_finish,
            parameter = sample.parameter,
            orientation_phase = value.tracer_phase,
        },
    })
    if status != .Ok {
        return status
    }
    status = append_rolling_compass(output, pose.rolling_center, tracer)
    if status != .Ok {
        return status
    }
    return append_rolling_effects(request, sample, tracer, output, true)
}

// Evaluate rolling rings and tracer through canonical native Trochoid geometry.
evaluate_trochoid_motion :: proc(
    request: Modifier_Request, output: ^Modifier_Output_Buffer) -> Modifier_Status {
    sample := rolling_sample(request)
    center := request.start_position
    center.z += sample.elevation
    value := rolling_trochoid_value(request)
    pose := curve.trochoid_tool_pose(center, {
        mode = value.mode,
        fixed_radius = value.fixed_radius,
        rolling_radius = value.rolling_radius,
        parameter = sample.parameter,
        rotation = value.rotation,
    })
    tracer := curve.trochoid_point(center, value, sample.parameter)
    status := modifier_output_append(output, {
        kind = .Set_Trochoid_Guide_Sample,
        position = center,
        trochoid_tool = {
            mode = value.mode,
            fixed_radius = value.fixed_radius,
            rolling_radius = value.rolling_radius,
            parameter = sample.parameter,
            rotation = value.rotation,
            orientation_phase = value.tracer_phase,
        },
    })
    if status != .Ok {
        return status
    }
    status = append_rolling_compass(output, pose.rolling_center, tracer)
    if status != .Ok {
        return status
    }
    return append_rolling_effects(request, sample, tracer, output, false)
}

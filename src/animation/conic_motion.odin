package modifier

import curve "../shapes/curve"
import shapemodel "../shapes/model"
import geometry "../core/geometry"

// Keep one conic sample in callback-local storage, never across ticks.
Conic_Sample :: struct {
    parameter: f32,
    elevation: f32,
    drawing: bool,
    descending: bool,
    placing: bool,
}

// Pair tracer ink with ordinary floor-contact intent at the same canonical nib position.
append_conic_contact_trail :: proc(
    output: ^Modifier_Output_Buffer, position: geometry.Vector3,
    color: u32) -> Modifier_Status {
    status := modifier_output_append(output, {
        kind = .Queue_Tool_Contact,
        position = position,
    })
    if status != .Ok {
        return status
    }
    return append_trail(output, position, color)
}

// Reject invalid drawing scales and branch selections before analytic evaluation.
conic_request_valid :: proc(request: Modifier_Request) -> bool {
    if request.integer < 0 || request.integer > 2 {
        return false
    }
    if request.kind == .Parabola_Draw {
        return request.entity != 0 && shapemodel.shape_parabola_is_valid({
            focal_distance = request.radius,
            rotation = request.angle,
            parameter_start = request.third_position.x,
            parameter_finish = request.third_position.z,
            draw_parameter = request.third_position.x,
        })
    }
    if request.kind == .Hyperbola_Draw {
        return request.entity != 0 && shapemodel.shape_hyperbola_is_valid({
            semimajor = request.radius,
            semiminor = request.displacement.x,
            rotation = request.angle,
            parameter_start = request.third_position.x,
            parameter_finish = request.third_position.z,
            draw_parameter = request.third_position.x,
        })
    }
    return true
}

// Resolve explicit phase time without retaining a native clock or apparatus state.
conic_sample :: proc(request: Modifier_Request) -> Conic_Sample {
    sample: Conic_Sample = {
        parameter = request.third_position.x,
        elevation = request.scalar,
    }
    progress := modifier_progress(request.elapsed, request.duration)
    #partial switch request.kind {
    case .Parabola_Place, .Hyperbola_Place:
        sample.placing = true
    case .Parabola_Descend, .Hyperbola_Descend:
        sample.descending = true
        sample.elevation *= 1 - progress
    case .Parabola_Draw, .Hyperbola_Draw:
        sample.drawing = true
        sample.elevation = 0
        sample.parameter +=
            (request.third_position.z - request.third_position.x) * progress
        if progress == 1 {
            sample.parameter = request.third_position.z
        }
    case .Parabola_Rise, .Hyperbola_Rise:
        sample.elevation *= progress
    }
    return sample
}

// Emit canonical rotated tracer positions only for the selected ink branches.
append_conic_trails :: proc(
    request: Modifier_Request, parameter: f32,
    output: ^Modifier_Output_Buffer, hyperbola: bool) -> Modifier_Status {
    if !hyperbola {
        return append_conic_contact_trail(
            output, curve.parabola_point(request.start_position, {
                focal_distance = request.radius,
                rotation = request.angle,
            }, parameter), request.color_packed)
    }
    value: shapemodel.Shape_Hyperbola = {
        semimajor = request.radius,
        semiminor = request.displacement.x,
        rotation = request.angle,
    }
    branches := [?]i32{1, -1}
    for branch in branches {
        selection := 1
        if branch == -1 {
            selection = 2
        }
        if request.integer != 0 && request.integer != selection {
            continue
        }
        status := append_conic_contact_trail(output, curve.hyperbola_point(
            request.start_position, value, parameter, branch), request.color_packed)
        if status != .Ok {
            return status
        }
    }
    return .Ok
}

// Preserve inactive travel, descent visibility, exact ink frontiers and paired trails.
append_conic_effects :: proc(
    request: Modifier_Request, sample: Conic_Sample,
    output: ^Modifier_Output_Buffer, hyperbola: bool) -> Modifier_Status {
    if sample.placing {
        return .Ok
    }
    status := modifier_output_append(output, {
        kind = .Set_Conic_Active,
        integer = int(hyperbola),
        scalar = f32(request.integer),
        flag = sample.drawing,
        color_packed = request.color_packed,
    })
    if status != .Ok {
        return status
    }
    if sample.descending {
        return modifier_output_append(output, {
            kind = .Set_Conic_Visible,
            integer = int(hyperbola),
            flag = true,
        })
    }
    if !sample.drawing {
        return .Ok
    }
    status = modifier_output_append(output, {
        kind = .Set_Conic_Frontier,
        entity = request.entity,
        integer = int(hyperbola),
        scalar = sample.parameter,
    })
    if status != .Ok {
        return status
    }
    return append_conic_trails(request, sample.parameter, output, hyperbola)
}

// Move the configured native apparatus and its analytic frontier in one transaction.
evaluate_conic_motion :: proc(
    request: Modifier_Request, output: ^Modifier_Output_Buffer) -> Modifier_Status {
    sample := conic_sample(request)
    hyperbola := request.kind >= .Hyperbola_Place
    position := request.start_position
    position.z += sample.elevation
    status := modifier_output_append(output, {
        kind = .Set_Conic_Sample,
        position = position,
        scalar = sample.parameter,
        integer = int(hyperbola),
    })
    if status != .Ok {
        return status
    }
    return append_conic_effects(request, sample, output, hyperbola)
}

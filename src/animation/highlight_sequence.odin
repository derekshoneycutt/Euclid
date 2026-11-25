package modifier

import geometry "../core/geometry"
import math "core:math"

HIGHLIGHT_TOOL_TOP_Z :: 1.4
HIGHLIGHT_DESCEND_SHARE :: 0.2
HIGHLIGHT_PASS_SHARE :: 0.3

// Evaluate one pen highlight phase from the full-operation elapsed time.
evaluate_pen_highlight_sequence :: proc(
    request: Modifier_Request, output: ^Modifier_Output_Buffer) -> Modifier_Status {
    phase := pen_highlight_phase_request(request)
    status := evaluate_modifier(phase, output)
    if status != .Ok || request.elapsed < request.duration {
        return status
    }
    return append_highlight_retirement(request.entity, output)
}

// Resolve descend, two directed strokes, or rise for one pen highlight sample.
pen_highlight_phase_request :: proc(request: Modifier_Request) -> Modifier_Request {
    descend := request.duration * HIGHLIGHT_DESCEND_SHARE
    pass_duration := request.duration * HIGHLIGHT_PASS_SHARE
    second_start := descend + pass_duration
    rise_start := second_start + pass_duration
    phase := request
    phase.entity = 0
    phase.second_entity = 1
    if request.elapsed < descend {
        return pen_highlight_vertical_request(phase, .Pen_Descend,
            request.elapsed, descend, true)
    }
    if request.elapsed < second_start {
        phase = pen_highlight_stroke_request(
            phase, request.elapsed - descend, pass_duration,
            request.start_position, request.second_position)
        return phase
    }
    if request.elapsed < rise_start {
        return pen_highlight_stroke_request(
            phase, request.elapsed - second_start, pass_duration,
            request.second_position, request.start_position)
    }
    return pen_highlight_vertical_request(phase, .Pen_Rise,
        request.elapsed - rise_start, max(request.duration - rise_start, 1e-5), false)
}

// Build one native pen stroke using the supplied directed endpoints.
pen_highlight_stroke_request :: proc(
    request: Modifier_Request, elapsed, duration: f32,
    start, finish: geometry.Vector3) -> Modifier_Request {
    phase := request
    phase.kind = .Pen_Stroke
    phase.elapsed = elapsed
    phase.duration = duration
    phase.start_position = start
    phase.second_position = finish
    return phase
}

// Build the bounded native pen descent or rise subrequest.
pen_highlight_vertical_request :: proc(
    request: Modifier_Request, kind: Modifier_Kind,
    elapsed, duration: f32, descending: bool) -> Modifier_Request {
    phase := request
    phase.kind = kind
    phase.elapsed = elapsed
    phase.duration = duration
    phase.start_position.z = 0
    phase.second_position = phase.start_position
    phase.scalar = HIGHLIGHT_TOOL_TOP_Z
    phase.brush = phase.radius
    if descending {
        phase.start_position.z = HIGHLIGHT_TOOL_TOP_Z
        phase.second_position.z = HIGHLIGHT_TOOL_TOP_Z
    }
    return phase
}

// Evaluate one compass highlight phase from the full-operation elapsed time.
evaluate_compass_highlight_sequence :: proc(
    request: Modifier_Request, output: ^Modifier_Output_Buffer) -> Modifier_Status {
    phase := compass_highlight_phase_request(request)
    status := evaluate_modifier(phase, output)
    if status != .Ok || request.elapsed < request.duration {
        return status
    }
    return append_highlight_retirement(request.entity, output)
}

// Hide a completed highlight instrument in the same terminal scene sample.
append_highlight_retirement :: proc(
    entity: u64, output: ^Modifier_Output_Buffer) -> Modifier_Status {
    return modifier_output_append(output, {
        kind = .Set_Tool_Visible,
        entity = entity,
        flag = false,
    })
}

// Resolve compass descent, two directed sweeps, or rise for one sample.
compass_highlight_phase_request :: proc(request: Modifier_Request) -> Modifier_Request {
    descend := request.duration * HIGHLIGHT_DESCEND_SHARE
    pass_duration := request.duration * HIGHLIGHT_PASS_SHARE
    second_start := descend + pass_duration
    rise_start := second_start + pass_duration
    phase := request
    if request.elapsed < descend {
        return compass_highlight_vertical_request(
            phase, .Compass_Descend, request.elapsed, descend, true)
    }
    if request.elapsed < second_start {
        return compass_highlight_pass_request(
            phase, request.elapsed - descend, pass_duration,
            request.second_position, request.angle)
    }
    if request.elapsed < rise_start {
        endpoint := compass_highlight_endpoint(request)
        return compass_highlight_pass_request(
            phase, request.elapsed - second_start, pass_duration,
            endpoint, -request.angle)
    }
    return compass_highlight_vertical_request(
        phase, .Compass_Rise, request.elapsed - rise_start,
        max(request.duration - rise_start, 1e-5), false)
}

// Build one native compass highlight pass from a directed start point and angle.
compass_highlight_pass_request :: proc(
    request: Modifier_Request, elapsed, duration: f32,
    start: geometry.Vector3, angle: f32) -> Modifier_Request {
    phase := request
    phase.kind = .Compass_Highlight
    phase.elapsed = elapsed
    phase.duration = duration
    phase.second_position = start
    phase.angle = angle
    return phase
}

// Build the bounded native compass descent or rise subrequest.
compass_highlight_vertical_request :: proc(
    request: Modifier_Request, kind: Modifier_Kind,
    elapsed, duration: f32, descending: bool) -> Modifier_Request {
    phase := request
    phase.kind = kind
    phase.elapsed = elapsed
    phase.duration = duration
    phase.start_position.z = 0
    phase.second_position.z = 0
    phase.scalar = HIGHLIGHT_TOOL_TOP_Z
    if descending {
        phase.start_position.z = HIGHLIGHT_TOOL_TOP_Z
        phase.second_position.z = HIGHLIGHT_TOOL_TOP_Z
    }
    return phase
}

// Find the authored endpoint for the highlight's reverse compass sweep.
compass_highlight_endpoint :: proc(request: Modifier_Request) -> geometry.Vector3 {
    start := math.atan2(
        request.second_position.y - request.start_position.y,
        request.second_position.x - request.start_position.x)
    theta := start + request.angle
    return {
        request.start_position.x + request.radius * math.cos(theta),
        request.start_position.y + request.radius * math.sin(theta),
        0,
    }
}

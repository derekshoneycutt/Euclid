package modifier

import geometry "../core/geometry"
import math "core:math"

POLYGON_TRACE_DESCEND_SHARE :: 0.15
POLYGON_TRACE_DRAW_SHARE :: 0.55
POLYGON_TRACE_REVEAL_SHARE :: 0.15
POLYGON_TRACE_TOOL_TOP_Z :: 1.4

// Resolve one full-duration polygon trace into its current pen motion sample.
polygon_trace_motion_request :: proc(
    template: Modifier_Request, trace: Polygon_Trace, elapsed: f32) -> Modifier_Request {
    descend := template.duration * POLYGON_TRACE_DESCEND_SHARE
    draw_duration := template.duration * POLYGON_TRACE_DRAW_SHARE
    draw_end := descend + draw_duration
    rise_start := draw_end + template.duration * POLYGON_TRACE_REVEAL_SHARE
    if elapsed < descend {
        return polygon_trace_vertical_request(
            template, trace.vertices[0].position, .Pen_Descend, elapsed, descend)
    }
    if elapsed < draw_end {
        return polygon_trace_edge_request(
            template, trace, elapsed - descend, draw_duration)
    }
    last := trace.vertices[trace.count - 1].position
    if elapsed < rise_start {
        return polygon_trace_edge_request(template, trace, draw_duration, draw_duration)
    }
    return polygon_trace_vertical_request(
        template, last, .Pen_Rise, elapsed - rise_start,
        max(template.duration - rise_start, 1e-5))
}

// Build one ordered edge's interpolated pen-drag request.
polygon_trace_edge_request :: proc(
    template: Modifier_Request, trace: Polygon_Trace,
    elapsed, duration: f32) -> Modifier_Request {
    edge_duration := duration / f32(trace.count)
    edge_index := min(int(math.floor(elapsed / edge_duration)), trace.count - 1)
    edge_elapsed := min(elapsed - f32(edge_index) * edge_duration, edge_duration)
    start := trace.vertices[edge_index].position
    finish := trace.vertices[(edge_index + 1) % trace.count].position
    return {
        kind = .Pen_Drag,
        second_entity = 1,
        elapsed = edge_elapsed,
        duration = edge_duration,
        start_position = start,
        second_position = finish,
        angle = f32(math.PI / 3),
        radius = template.radius,
        color_packed = template.color_packed,
        scalar = math.atan2(finish.y - start.y, finish.x - start.x),
    }
}

// Build one bounded descent or rise subrequest at a polygon endpoint.
polygon_trace_vertical_request :: proc(
    template: Modifier_Request, position: geometry.Vector3,
    kind: Modifier_Kind, elapsed, duration: f32) -> Modifier_Request {
    return {
        kind = kind,
        second_entity = 1,
        elapsed = elapsed,
        duration = duration,
        start_position = position,
        second_position = position,
        radius = template.radius,
        scalar = POLYGON_TRACE_TOOL_TOP_Z,
    }
}

// Admit the fill reveal only on the accepted sample that crosses its boundary.
polygon_trace_reveal_due :: proc(
    previous, current, duration: f64) -> bool {
    boundary := duration * 0.70
    return previous < boundary && current >= boundary
}

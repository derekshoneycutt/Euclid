package modifier

import geometry "../core/geometry"
import math "core:math"
import linalg "core:math/linalg"

STROKE_TILT_SHARE :: 0.15
STROKE_DRAW_SHARE :: 0.7
STROKE_DRAW_END :: 0.85

// Resolve the ordinary tilt/drag/tilt sample, preserving boundary azimuths.
stroke_pose_request :: proc(
    request: Modifier_Request, start, end: geometry.Vector3) -> Modifier_Request {
    pose := request
    pose.entity = 0
    pose.second_entity = 1
    pose.start_position = start
    pose.second_position = end
    pose.scalar = math.atan2(end.y - start.y, end.x - start.x)
    progress := modifier_progress(request.elapsed, request.duration)
    if progress < STROKE_TILT_SHARE {
        pose.kind = .Pen_Tilt
        pose.angle = f32(math.PI / 2)
        pose.brush = request.angle
        pose.duration *= STROKE_TILT_SHARE
    } else if progress < STROKE_DRAW_END {
        pose.kind = .Pen_Drag
        pose.elapsed -= request.duration * STROKE_TILT_SHARE
        pose.duration *= STROKE_DRAW_SHARE
    } else {
        pose.kind = .Pen_Tilt
        pose.start_position = end
        pose.elapsed -= request.duration * STROKE_DRAW_END
        pose.duration *= STROKE_TILT_SHARE
        pose.brush = f32(math.PI / 2)
    }
    return pose
}

// Resolve point-highlight cone timing without resetting its active contact.
highlight_pose_request :: proc(request: Modifier_Request) -> Modifier_Request {
    pose := stroke_pose_request(request, request.start_position, request.start_position)
    if pose.kind == .Pen_Drag {
        pose.kind = .Pen_Cone
        pose.scalar = request.scalar
    } else if modifier_progress(request.elapsed, request.duration) >= STROKE_DRAW_END {
        pose.scalar = request.duration * STROKE_DRAW_SHARE * request.scalar
    }
    return pose
}

// Evaluate highlight, trail-only stroke, or extension with legacy duplicate trails.
evaluate_pen_stroke :: proc(
    request: Modifier_Request, output: ^Modifier_Output_Buffer) -> Modifier_Status {
    pose := stroke_pose_request(request, request.start_position, request.second_position)
    if request.kind == .Extend_Line {
        pose.scalar = math.atan2(request.second_position.y - request.third_position.y,
            request.second_position.x - request.third_position.x)
    }
    if request.kind == .Pen_Highlight_Point {
        pose = highlight_pose_request(request)
    }
    status := evaluate_pen_motion(pose, output)
    if status != .Ok || pose.kind == .Pen_Tilt {
        return status
    }
    position := pen_motion_pose(pose).start_position
    status = append_trail(output, position, request.color_packed)
    if status != .Ok {
        return status
    }
    active := 1
    if request.kind == .Pen_Stroke {
        active = 0
    }
    status = append_tool_style(output, 0, request.color_packed, active)
    if status != .Ok || request.kind != .Extend_Line {
        return status
    }
    line := request
    line.kind = .Line_Segment
    line.start_position = request.third_position
    line.second_position = position
    line.flag = true
    return evaluate_line_segment(line, output)
}

// Return native arc-length timing for the active leg of a connected stroke.
two_segment_pose_request :: proc(request: Modifier_Request) -> (Modifier_Request, bool) {
    a := request.start_position
    b := request.second_position
    c := request.third_position
    first_length := max(linalg.length(b - a), 1e-6)
    second_length := max(linalg.length(c - b), 1e-6)
    draw_duration := request.duration * STROKE_DRAW_SHARE
    first_duration := draw_duration * first_length / (first_length + second_length)
    drag_time := request.elapsed - request.duration * STROKE_TILT_SHARE
    second_active := drag_time > first_duration
    pose := stroke_pose_request(request, a, b)
    if modifier_progress(request.elapsed, request.duration) >= STROKE_DRAW_END {
        pose = stroke_pose_request(request, b, c)
    } else if pose.kind == .Pen_Drag {
        pose.duration = first_duration
        if second_active {
            pose = stroke_pose_request(request, b, c)
            pose.elapsed = drag_time - first_duration
            pose.duration = draw_duration - first_duration
            pose.kind = .Pen_Drag
        }
    }
    return pose, second_active
}

// Resolve one host's crossed-segment geometry, including hidden future geometry.
two_segment_line_request :: proc(
    request, pose: Modifier_Request, second_active: bool) -> Modifier_Request {
    line := request
    line.kind = .Line_Segment
    line.flag = true
    if request.flag {
        line.start_position = request.second_position
        line.second_position = request.third_position
        if pose.kind == .Pen_Drag && !second_active {
            line.second_position = line.start_position
            line.flag = false
        } else if pose.kind == .Pen_Drag {
            line.second_position = pen_motion_pose(pose).start_position
        }
    } else if pose.kind == .Pen_Drag && !second_active {
        line.second_position = pen_motion_pose(pose).start_position
    }
    return line
}

// Expand each host separately; the first marker exclusively emits the shared pen.
evaluate_two_segment_stroke :: proc(
    request: Modifier_Request, output: ^Modifier_Output_Buffer) -> Modifier_Status {
    pose, second_active := two_segment_pose_request(request)
    status: Modifier_Status = .Ok
    if !request.flag {
        status = evaluate_pen_motion(pose, output)
    }
    if status != .Ok {
        return status
    }
    if modifier_progress(request.elapsed, request.duration) < STROKE_TILT_SHARE {
        return .Ok
    }
    line := two_segment_line_request(request, pose, second_active)
    return evaluate_line_segment(line, output)
}

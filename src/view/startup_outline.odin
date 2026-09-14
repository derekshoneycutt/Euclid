package view

import viewmodel "model"

import "ui"

import "core:math"

import rl "vendor:raylib"

STARTUP_OUTLINE_SEGMENT_CAP :: 32
STARTUP_OUTLINE_SECONDS :: f32(5.0)
STARTUP_OUTLINE_STROKE_WIDTH :: f32(2.0)
STARTUP_OUTLINE_TIP_RADIUS :: f32(3.5)

// One ordered line segment in the startup UI silhouette.
Startup_Outline_Segment :: struct {
    first: rl.Vector2,
    second: rl.Vector2,
    length: f32,
}

// Own fixed startup silhouette geometry and its progressive reveal distance.
Startup_Outline :: struct {
    segments: [STARTUP_OUTLINE_SEGMENT_CAP]Startup_Outline_Segment,
    segment_count: int,
    total_length: f32,
    reveal_distance: f32,
    target_distance: f32,
}

// Append one nonempty segment to bounded startup outline storage.
startup_outline_append_segment :: proc(
    outline: ^Startup_Outline, first, second: rl.Vector2) {
    assert(outline^.segment_count < STARTUP_OUTLINE_SEGMENT_CAP)
    delta := second - first
    length := f32(math.sqrt(f64(delta.x * delta.x + delta.y * delta.y)))
    if length <= 0 {return}
    outline^.segments[outline^.segment_count] = {first, second, length}
    outline^.segment_count += 1
    outline^.total_length += length
}

// Append one clockwise rectangular path to the startup silhouette.
startup_outline_append_rect :: proc(
    outline: ^Startup_Outline, rect: rl.Rectangle) {
    top_left := rl.Vector2{rect.x, rect.y}
    top_right := rl.Vector2{rect.x + rect.width, rect.y}
    bottom_right := rl.Vector2{rect.x + rect.width, rect.y + rect.height}
    bottom_left := rl.Vector2{rect.x, rect.y + rect.height}
    startup_outline_append_segment(outline, top_left, top_right)
    startup_outline_append_segment(outline, top_right, bottom_right)
    startup_outline_append_segment(outline, bottom_right, bottom_left)
    startup_outline_append_segment(outline, bottom_left, top_left)
}

// Build the default landscape UI silhouette from authoritative layout helpers.
startup_outline_create :: proc() -> Startup_Outline {
    outline: Startup_Outline
    regions := ui.compute_ui_regions(.Baseline, VIEW_WIDTH, VIEW_HEIGHT)
    accordion := ui.accordion_layout(
        regions.accordion_rect, viewmodel.Ui_Accordion_Section.Library)
    controls := ui.animation_control_layout_slots(regions.world_rect)

    startup_outline_append_rect(&outline, regions.world_rect)
    startup_outline_append_rect(&outline, regions.text_rect)
    startup_outline_append_rect(&outline, regions.accordion_rect)
    for header in accordion.headers {
        startup_outline_append_rect(&outline, header)
    }
    startup_outline_append_rect(&outline, controls.refresh)
    startup_outline_append_rect(&outline, controls.pause)
    return outline
}

// Set the bounded loading milestone that the outline may reveal toward.
startup_outline_set_target :: proc(outline: ^Startup_Outline, progress: f32) {
    outline^.target_distance = outline^.total_length * clamp(progress, f32(0), f32(1))
}

// Advance the outline at a stable full-trace rate without passing its milestone.
startup_outline_advance :: proc(outline: ^Startup_Outline, dt: f32) {
    distance := outline^.total_length / STARTUP_OUTLINE_SECONDS * max(dt, f32(0))
    outline^.reveal_distance = min(
        outline^.reveal_distance + distance, outline^.target_distance)
}

// Draw the revealed prefix and a brighter moving endpoint.
startup_outline_draw :: proc(
    outline: ^Startup_Outline, line_color, tip_color: rl.Color) {
    remaining := outline^.reveal_distance
    for index in 0..<outline^.segment_count {
        segment := outline^.segments[index]
        if remaining <= 0 {break}
        visible_length := min(remaining, segment.length)
        ratio := visible_length / segment.length
        endpoint := segment.first + (segment.second - segment.first) * ratio
        rl.DrawLineEx(segment.first, endpoint, STARTUP_OUTLINE_STROKE_WIDTH,
            line_color)
        remaining -= segment.length
        if visible_length < segment.length {
            rl.DrawCircleV(endpoint, STARTUP_OUTLINE_TIP_RADIUS, tip_color)
            break
        }
    }
}
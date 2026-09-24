package view

import viewmodel "model"

import "ui"
import native "native"

import color "../core/color"
import geometry "../core/geometry"

import "core:math"

STARTUP_OUTLINE_SEGMENT_CAP :: 36
STARTUP_OUTLINE_SECONDS :: f32(5.0)
STARTUP_OUTLINE_STROKE_WIDTH :: f32(2.0)
STARTUP_OUTLINE_TIP_RADIUS :: f32(3.5)

// One ordered line segment in the startup UI silhouette.
Startup_Outline_Segment :: struct {
    first: geometry.Vector2,
    second: geometry.Vector2,
    length: f32,
}

// Own fixed startup silhouette geometry and its progressive reveal distance.
Startup_Outline :: struct {
    segments: [STARTUP_OUTLINE_SEGMENT_CAP]Startup_Outline_Segment,
    segment_count: int,
    total_length: f32,
    reveal_distance: f32,
    target_distance: f32,
    metrics: viewmodel.Ui_Window_Metrics,
    layout: viewmodel.Ui_Layout_Mode,
    layout_preference: viewmodel.Layout_Preference,
}

// Append one nonempty segment to bounded startup outline storage.
startup_outline_append_segment :: proc(
    outline: ^Startup_Outline, first, second: geometry.Vector2) {
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
    outline: ^Startup_Outline, rect: geometry.Rectangle) {
    top_left := geometry.Vector2{rect.x, rect.y}
    top_right := geometry.Vector2{rect.x + rect.width, rect.y}
    bottom_right := geometry.Vector2{rect.x + rect.width, rect.y + rect.height}
    bottom_left := geometry.Vector2{rect.x, rect.y + rect.height}
    startup_outline_append_segment(outline, top_left, top_right)
    startup_outline_append_segment(outline, top_right, bottom_right)
    startup_outline_append_segment(outline, bottom_right, bottom_left)
    startup_outline_append_segment(outline, bottom_left, top_left)
}

// Build one startup silhouette from authoritative live-layout helpers.
startup_outline_create :: proc(
    metrics: viewmodel.Ui_Window_Metrics = {WINDOW_WIDTH, WINDOW_HEIGHT},
    layout: viewmodel.Ui_Layout_Mode = .Landscape,
    preference: viewmodel.Layout_Preference = .Auto) -> Startup_Outline {
    outline: Startup_Outline
    outline.metrics = metrics
    outline.layout = layout
    outline.layout_preference = preference
    vertical := f32(metrics.width) * f32(VIEW_WIDTH) / f32(WINDOW_WIDTH)
    horizontal := f32(metrics.height) * f32(VIEW_HEIGHT) / f32(WINDOW_HEIGHT)
    if layout == .Portrait {
        vertical = f32(metrics.width)
        horizontal = f32(metrics.height) * 0.5
    }
    regions := ui.compute_ui_regions(
        layout, f32(metrics.width), f32(metrics.height), vertical, horizontal)
    sections := ui.accordion_sections_for_layout(layout, "Animation")
    accordion := ui.accordion_layout(
        geometry.Rectangle(regions.accordion_rect), sections,
        layout == .Portrait ? .View : .Library)
    controls := ui.animation_control_layout_slots(
        geometry.Rectangle(regions.world_rect))

    startup_outline_append_rect(&outline, geometry.Rectangle(regions.world_rect))
    startup_outline_append_rect(&outline, geometry.Rectangle(regions.text_rect))
    startup_outline_append_rect(&outline, geometry.Rectangle(regions.accordion_rect))
    for index in 0..<sections.count {
        startup_outline_append_rect(
            &outline, geometry.Rectangle(accordion.headers[index]))
    }
    startup_outline_append_rect(&outline, geometry.Rectangle(controls.refresh))
    startup_outline_append_rect(&outline, geometry.Rectangle(controls.pause))
    return outline
}

// Rebuild changed startup geometry while preserving reveal and milestone fractions.
startup_outline_rebuild :: proc(
    outline: ^Startup_Outline, metrics: viewmodel.Ui_Window_Metrics,
    layout: viewmodel.Ui_Layout_Mode) -> bool {
    if outline^.metrics == metrics && outline^.layout == layout { return false }
    reveal_ratio: f32
    target_ratio: f32
    if outline^.total_length > 0 {
        reveal_ratio = outline^.reveal_distance / outline^.total_length
        target_ratio = outline^.target_distance / outline^.total_length
    }
    rebuilt := startup_outline_create(metrics, layout, outline^.layout_preference)
    rebuilt.reveal_distance = rebuilt.total_length * clamp(reveal_ratio, f32(0), f32(1))
    rebuilt.target_distance = rebuilt.total_length * clamp(target_ratio, f32(0), f32(1))
    outline^ = rebuilt
    return true
}

// Reconcile startup geometry against one live logical window sample.
startup_outline_reconcile :: proc(
    outline: ^Startup_Outline, metrics: viewmodel.Ui_Window_Metrics) -> bool {
    layout := ui.resolve_layout_mode(outline^.layout_preference, outline^.layout,
        f32(metrics.width), f32(metrics.height))
    return startup_outline_rebuild(outline, metrics, layout)
}

// Center one startup warning extent within the live logical window.
startup_warning_position :: proc(
    metrics: viewmodel.Ui_Window_Metrics,
    text_width, text_height: f32) -> geometry.Vector2 {
    return {
        f32(metrics.width) / 2 - text_width / 2,
        f32(metrics.height) / 2 - text_height / 2,
    }
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

// Encode the revealed prefix and a brighter moving endpoint.
startup_outline_draw :: proc(
    outline: ^Startup_Outline, encoder: ^native.Draw_Encoder,
    line_color, tip_color: color.Color_RGBA8) -> bool {
    remaining := outline^.reveal_distance
    accepted := true
    for index in 0..<outline^.segment_count {
        segment := outline^.segments[index]
        if remaining <= 0 {break}
        visible_length := min(remaining, segment.length)
        ratio := visible_length / segment.length
        endpoint := segment.first + (segment.second - segment.first) * ratio
        accepted = native.draw_encoder_line(encoder, segment.first, endpoint,
            STARTUP_OUTLINE_STROKE_WIDTH, line_color) && accepted
        remaining -= segment.length
        if visible_length < segment.length {
            accepted = native.draw_encoder_circle(
                encoder, endpoint, STARTUP_OUTLINE_TIP_RADIUS, tip_color) && accepted
            break
        }
    }
    return accepted
}
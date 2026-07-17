package ui

import rl "vendor:raylib"

//   Clamp scroll offset to [0, max_scroll] range.
clamp_scroll_position :: proc(scroll_y: ^f32, max_scroll: f32) {
    if scroll_y^ < 0 {
        scroll_y^ = 0
    }
    if scroll_y^ > max_scroll {
        scroll_y^ = max_scroll
    }
}

//   Apply mouse-wheel scrolling when cursor is over target panel.
apply_wheel_scroll :: proc(
    mouse: rl.Vector2,
    panel: rl.Rectangle,
    row_height: f32,
    scroll_y: ^f32,
    max_scroll: f32,
    wheel_multiplier: f32) {

    if !rl.CheckCollisionPointRec(mouse, panel) {
        return
    }

    wheel := rl.GetMouseWheelMove()
    if wheel != 0 {
        scroll_y^ -= wheel * (row_height * wheel_multiplier)
        clamp_scroll_position(scroll_y, max_scroll)
    }
}

//   Compute scrollbar thumb height from content-to-panel ratio.
scrollbar_thumb_height :: #force_inline proc(
    panel_height: f32,
    content_h: f32,
    thumb_min_height: f32) -> f32 {

    if panel_height <= 0 || content_h <= 0 {
        return 0
    }

    thumb_h := max(thumb_min_height, panel_height * (panel_height / content_h))
    return clamp(thumb_h, 0.0, panel_height)
}

//   Compute scrollbar thumb y-position from scroll offset.
scrollbar_thumb_y :: #force_inline proc(
    panel_y,
    panel_height,
    thumb_h,
    scroll_y,
    max_scroll: f32) -> f32 {

    if max_scroll <= 0 || panel_height <= thumb_h {
        return panel_y
    }
    return panel_y + (scroll_y / max_scroll) * (panel_height - thumb_h)
}

//   Build scrollbar track/thumb geometry for current scroll state.
build_vertical_scrollbar :: proc(
    panel: rl.Rectangle,
    content_h: f32,
    scroll_y: f32,
    max_scroll: f32,
    scrollbar_width: f32,
    thumb_min_height: f32) -> (rl.Rectangle, rl.Rectangle, f32, bool) {

    if max_scroll <= 0 {
        return rl.Rectangle{}, rl.Rectangle{}, 0, false
    }

    track := rl.Rectangle{
        panel.x + panel.width - scrollbar_width,
        panel.y,
        scrollbar_width,
        panel.height,
    }

    thumb_h := scrollbar_thumb_height(panel.height, content_h, thumb_min_height)
    thumb_y := scrollbar_thumb_y(panel.y, panel.height, thumb_h, scroll_y, max_scroll)
    thumb := rl.Rectangle{track.x, thumb_y, scrollbar_width, thumb_h}
    return track, thumb, thumb_h, true
}

//   Handle drag lifecycle and update scroll offset from thumb drag.
handle_scrollbar_drag :: proc(
    mouse: rl.Vector2,
    thumb: rl.Rectangle,
    panel_y,
    panel_height: f32,
    thumb_h,
    max_scroll: f32,
    scroll_y: ^f32,
    dragging: ^bool,
    drag_off: ^f32,
    drag_epsilon: f32) {

    if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mouse, thumb) {
        dragging^ = true
        drag_off^ = mouse.y - thumb.y
    }

    if !dragging^ {
        return
    }

    if !rl.IsMouseButtonDown(.LEFT) {
        dragging^ = false
        return
    }

    thumb_range := panel_height - thumb_h
    if thumb_range <= drag_epsilon || max_scroll <= 0 {
        scroll_y^ = 0
        return
    }

    new_thumb_y := mouse.y - drag_off^
    t := (new_thumb_y - panel_y) / thumb_range
    scroll_y^ = clamp(t, 0, 1) * max_scroll
}

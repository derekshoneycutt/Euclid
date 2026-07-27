package ui

import rl "vendor:raylib"

Scroll_Container_State :: struct {
    is_dragging_thumb: bool,
    drag_offset_y: f32,
}

Scroll_Container_Ref :: struct {
    id: int,
    view_rect: rl.Rectangle,
    wheel_step: f32,
    had_overflow_hint: bool,
    is_hovered_view: bool,
    is_hovered_thumb: bool,
    is_dragging_thumb: bool,
    drag_offset_y: f32,
    track_rect: rl.Rectangle,
    thumb_rect: rl.Rectangle,
}

Scroll_Container_Begin_Result :: struct {
    scroll_ref: Scroll_Container_Ref,
    view_rect: rl.Rectangle,
    scroll_y_out: f32,
}

Scroll_Container_End_Result :: struct {
    scroll_y_out: f32,
    state_out: Scroll_Container_State,
    has_scrollbar: bool,
    track_rect: rl.Rectangle,
    thumb_rect: rl.Rectangle,
}

//   Convert screen-space pointer position to local interaction space.
scroll_container_local_mouse :: #force_inline proc(
    mouse_input: Mouse_Input_State,
    scroll_offset: rl.Vector2) -> rl.Vector2 {

    return rl.Vector2{
        mouse_input.position.x - scroll_offset.x,
        mouse_input.position.y - scroll_offset.y,
    }
}

//   Clamp rectangle dimensions so width and height are never negative.
scroll_container_clamp_rect :: #force_inline proc(rect: rl.Rectangle) -> rl.Rectangle {
    clamped := rect
    if clamped.width < 0 {
        clamped.width = 0
    }
    if clamped.height < 0 {
        clamped.height = 0
    }
    return clamped
}

//   Return whether local pointer input is inside the active interaction space.
scroll_container_in_interaction_space :: #force_inline proc(
    local_mouse: rl.Vector2,
    interaction_space_rect: rl.Rectangle) -> bool {

    return rl.CheckCollisionPointRec(local_mouse, interaction_space_rect)
}

//   Create scroll-container frame state and apply wheel scrolling from hint data.
scroll_container_begin :: proc(
    id: int,
    rect: rl.Rectangle,
    scroll_y_in: f32,
    content_height_hint: f32,
    mouse_input: Mouse_Input_State,
    scroll_offset: rl.Vector2,
    interaction_space_rect: rl.Rectangle,
    wheel_step: f32,
    state_in: Scroll_Container_State) -> Scroll_Container_Begin_Result {

    view_rect := scroll_container_clamp_rect(rect)
    local_mouse := scroll_container_local_mouse(mouse_input, scroll_offset)
    in_interaction := scroll_container_in_interaction_space(local_mouse, interaction_space_rect)
    hovered_view := in_interaction && rl.CheckCollisionPointRec(local_mouse, view_rect)

    use_wheel_step := max(0.0, wheel_step)
    scroll_y_out := max(0.0, scroll_y_in)

    max_scroll_hint: f32 = 0
    had_overflow_hint := false
    track_hint := rl.Rectangle{}
    thumb_hint := rl.Rectangle{}
    hovered_thumb := false

    if content_height_hint > view_rect.height {
        max_scroll_hint = max(0.0, content_height_hint - view_rect.height)
        had_overflow_hint = max_scroll_hint > 0
    }

    if had_overflow_hint {
        if hovered_view && mouse_input.wheel_delta != 0 && use_wheel_step > 0 {
            scroll_y_out -= mouse_input.wheel_delta * use_wheel_step
        }
        clamp_scroll_position(&scroll_y_out, max_scroll_hint)

        track_hint, thumb_hint, _, _ = build_vertical_scrollbar(
            view_rect,
            content_height_hint,
            scroll_y_out,
            max_scroll_hint,
            SCROLLBAR_WIDTH,
            SCROLLBAR_THUMB_MIN_HEIGHT)
        hovered_thumb = in_interaction && rl.CheckCollisionPointRec(local_mouse, thumb_hint)
    }

    is_dragging_thumb := state_in.is_dragging_thumb
    drag_offset_y := state_in.drag_offset_y
    if had_overflow_hint && !is_dragging_thumb && mouse_input.left_pressed && hovered_thumb {
        is_dragging_thumb = true
        drag_offset_y = local_mouse.y - thumb_hint.y
    }

    scroll_ref := Scroll_Container_Ref{
        id = id,
        view_rect = view_rect,
        wheel_step = use_wheel_step,
        had_overflow_hint = had_overflow_hint,
        is_hovered_view = hovered_view,
        is_hovered_thumb = hovered_thumb,
        is_dragging_thumb = is_dragging_thumb,
        drag_offset_y = drag_offset_y,
        track_rect = track_hint,
        thumb_rect = thumb_hint,
    }

    rl.BeginScissorMode(
        i32(view_rect.x),
        i32(view_rect.y),
        i32(view_rect.width),
        i32(view_rect.height))

    return Scroll_Container_Begin_Result{
        scroll_ref = scroll_ref,
        view_rect = view_rect,
        scroll_y_out = scroll_y_out,
    }
}

//   Finalize scrollbar state, drag lifecycle, and clamped scroll output.
scroll_container_end :: proc(
    scroll_ref: Scroll_Container_Ref,
    content_height_final: f32,
    scroll_y_in: f32,
    mouse_input: Mouse_Input_State,
    scroll_offset: rl.Vector2,
    interaction_space_rect: rl.Rectangle) -> Scroll_Container_End_Result {

    defer rl.EndScissorMode()

    view_rect := scroll_ref.view_rect
    local_mouse := scroll_container_local_mouse(mouse_input, scroll_offset)
    _ = interaction_space_rect

    scroll_y_out := max(0.0, scroll_y_in)
    state_out := Scroll_Container_State{
        is_dragging_thumb = scroll_ref.is_dragging_thumb,
        drag_offset_y = scroll_ref.drag_offset_y,
    }

    max_scroll := max(0.0, content_height_final - view_rect.height)
    if max_scroll <= 0 {
        scroll_y_out = 0
        state_out.is_dragging_thumb = false
        state_out.drag_offset_y = 0
        return Scroll_Container_End_Result{
            scroll_y_out = scroll_y_out,
            state_out = state_out,
            has_scrollbar = false,
            track_rect = rl.Rectangle{},
            thumb_rect = rl.Rectangle{},
        }
    }

    clamp_scroll_position(&scroll_y_out, max_scroll)

    track_rect, thumb_rect, thumb_h, has_scrollbar := build_vertical_scrollbar(
        view_rect,
        content_height_final,
        scroll_y_out,
        max_scroll,
        SCROLLBAR_WIDTH,
        SCROLLBAR_THUMB_MIN_HEIGHT)
    if !has_scrollbar {
        state_out.is_dragging_thumb = false
        state_out.drag_offset_y = 0
        return Scroll_Container_End_Result{
            scroll_y_out = scroll_y_out,
            state_out = state_out,
            has_scrollbar = false,
            track_rect = rl.Rectangle{},
            thumb_rect = rl.Rectangle{},
        }
    }

    if !state_out.is_dragging_thumb && mouse_input.left_pressed &&
        rl.CheckCollisionPointRec(local_mouse, thumb_rect) {

        state_out.is_dragging_thumb = true
        state_out.drag_offset_y = local_mouse.y - thumb_rect.y
    }

    if state_out.is_dragging_thumb {
        if !mouse_input.left_down {
            state_out.is_dragging_thumb = false
            state_out.drag_offset_y = 0
        } else {
            thumb_range := view_rect.height - thumb_h
            if thumb_range <= SCROLLBAR_DRAG_EPSILON {
                scroll_y_out = 0
            } else {
                new_thumb_y := local_mouse.y - state_out.drag_offset_y
                t := (new_thumb_y - view_rect.y) / thumb_range
                scroll_y_out = clamp(t, 0, 1) * max_scroll
            }
            clamp_scroll_position(&scroll_y_out, max_scroll)

            track_rect, thumb_rect, _, _ = build_vertical_scrollbar(
                view_rect,
                content_height_final,
                scroll_y_out,
                max_scroll,
                SCROLLBAR_WIDTH,
                SCROLLBAR_THUMB_MIN_HEIGHT)
        }
    }

    if has_scrollbar {
        rl.DrawRectangleRec(track_rect, BACKGROUND_COLOR)
        rl.DrawRectangleRec(thumb_rect, UI_BORDER_COLOR)
    }

    return Scroll_Container_End_Result{
        scroll_y_out = scroll_y_out,
        state_out = state_out,
        has_scrollbar = has_scrollbar,
        track_rect = track_rect,
        thumb_rect = thumb_rect,
    }
}

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
    mouse_input: Mouse_Input_State,
    panel: rl.Rectangle,
    row_height: f32,
    scroll_y: ^f32,
    max_scroll: f32,
    wheel_multiplier: f32) {

    if !rl.CheckCollisionPointRec(mouse_input.position, panel) {
        return
    }

    wheel := mouse_input.wheel_delta
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
    mouse_input: Mouse_Input_State,
    thumb: rl.Rectangle,
    panel_y,
    panel_height: f32,
    thumb_h,
    max_scroll: f32,
    scroll_y: ^f32,
    dragging: ^bool,
    drag_off: ^f32,
    drag_epsilon: f32) {

    if mouse_input.left_pressed && rl.CheckCollisionPointRec(mouse_input.position, thumb) {
        dragging^ = true
        drag_off^ = mouse_input.position.y - thumb.y
    }

    if !dragging^ {
        return
    }

    if !mouse_input.left_down {
        dragging^ = false
        return
    }

    thumb_range := panel_height - thumb_h
    if thumb_range <= drag_epsilon || max_scroll <= 0 {
        scroll_y^ = 0
        return
    }

    new_thumb_y := mouse_input.position.y - drag_off^
    t := (new_thumb_y - panel_y) / thumb_range
    scroll_y^ = clamp(t, 0, 1) * max_scroll
}

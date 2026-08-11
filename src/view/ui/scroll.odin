package ui

import "../../core"

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

//   Return whether local pointer input is inside the active interaction space.
scroll_container_in_interaction_space :: #force_inline proc(
    local_mouse: rl.Vector2,
    interaction_space_rect: rl.Rectangle) -> bool {

    return rl.CheckCollisionPointRec(local_mouse, interaction_space_rect)
}

//   Return whether the shared press owner currently belongs to this scrollbar.
scroll_container_owns_press :: #force_inline proc(
    press_owner: ^core.Ui_Press_Owner_State,
    id: int) -> bool {

    return press_owner^.active &&
        press_owner^.kind == .Scrollbar &&
        press_owner^.id == id
}

//   Capture shared press ownership for a scrollbar thumb when available.
scroll_container_try_capture_press :: proc(
    press_owner: ^core.Ui_Press_Owner_State,
    id: int,
    mouse_input: Mouse_Input_State,
    hovered_thumb: bool,
    local_mouse: rl.Vector2,
    thumb_rect: rl.Rectangle,
    is_dragging_thumb: ^bool,
    drag_offset_y: ^f32) {

    if press_owner^.active || !mouse_input.left_pressed || !hovered_thumb {
        return
    }

    press_owner^.active = true
    press_owner^.kind = .Scrollbar
    press_owner^.id = id
    is_dragging_thumb^ = true
    drag_offset_y^ = local_mouse.y - thumb_rect.y
}

//   Release shared press ownership when a scrollbar thumb drag ends.
scroll_container_release_press :: proc(
    press_owner: ^core.Ui_Press_Owner_State,
    id: int,
    is_dragging_thumb: ^bool,
    drag_offset_y: ^f32) {

    if scroll_container_owns_press(press_owner, id) {
        press_owner^.active = false
        press_owner^.kind = .None
        press_owner^.id = -1
    }

    is_dragging_thumb^ = false
    drag_offset_y^ = 0
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
    press_owner: ^core.Ui_Press_Owner_State,
    state_in: Scroll_Container_State) -> Scroll_Container_Begin_Result {

    view_rect := clamp_non_negative_rect(rect)
    local_mouse := scroll_container_local_mouse(mouse_input, scroll_offset)
    in_interaction :=
        scroll_container_in_interaction_space(local_mouse, interaction_space_rect)
    hovered_view := in_interaction && rl.CheckCollisionPointRec(local_mouse, view_rect)

    use_wheel_step := max(0.0, wheel_step)
    scroll_y_out := max(0.0, scroll_y_in)

    hint := scroll_overflow_hint(view_rect, content_height_hint, scroll_offset,
        interaction_space_rect, local_mouse, mouse_input, &scroll_y_out,
        use_wheel_step)

    is_dragging_thumb := state_in.is_dragging_thumb
    drag_offset_y := state_in.drag_offset_y
    owns_press := scroll_container_owns_press(press_owner, id)
    if hint.had_overflow && is_dragging_thumb && !owns_press {
        is_dragging_thumb = false
        drag_offset_y = 0
    }

    if hint.had_overflow && !is_dragging_thumb {
        scroll_container_try_capture_press(
            press_owner,
            id,
            mouse_input,
            hint.hovered_thumb,
            local_mouse,
            hint.thumb_rect,
            &is_dragging_thumb,
            &drag_offset_y)
    }

    scroll_ref := Scroll_Container_Ref{
        id = id,
        view_rect = view_rect,
        wheel_step = use_wheel_step,
        had_overflow_hint = hint.had_overflow,
        is_hovered_view = hovered_view,
        is_hovered_thumb = hint.hovered_thumb,
        is_dragging_thumb = is_dragging_thumb,
        drag_offset_y = drag_offset_y,
        track_rect = hint.track_rect,
        thumb_rect = hint.thumb_rect,
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

//   Overflow geometry hint computed before drag lifecycle in scroll begin.
Scroll_Overflow_Hint :: struct {
    had_overflow:   bool,
    track_rect:     rl.Rectangle,
    thumb_rect:     rl.Rectangle,
    hovered_thumb:  bool,
}

//   Compute scrollbar geometry and apply wheel scroll when content overflows.
scroll_overflow_hint :: proc(
    view_rect: rl.Rectangle,
    content_height_hint: f32,
    scroll_offset: rl.Vector2,
    interaction_space_rect: rl.Rectangle,
    local_mouse: rl.Vector2,
    mouse_input: Mouse_Input_State,
    scroll_y_out: ^f32,
    use_wheel_step: f32) -> Scroll_Overflow_Hint {

    hint := Scroll_Overflow_Hint{}
    if content_height_hint <= view_rect.height {
        return hint
    }

    max_scroll_hint := max(0.0, content_height_hint - view_rect.height)
    hint.had_overflow = max_scroll_hint > 0
    if !hint.had_overflow {
        return hint
    }

    in_interaction :=
        scroll_container_in_interaction_space(local_mouse, interaction_space_rect)
    hovered_view := in_interaction && rl.CheckCollisionPointRec(local_mouse, view_rect)
    if hovered_view && mouse_input.wheel_delta != 0 && use_wheel_step > 0 {
        scroll_y_out^ -= mouse_input.wheel_delta * use_wheel_step
    }
    clamp_scroll_position(scroll_y_out, max_scroll_hint)

    track_rect, thumb_rect, _, _ := build_vertical_scrollbar(
        view_rect,
        content_height_hint,
        scroll_y_out^,
        max_scroll_hint,
        SCROLLBAR_WIDTH,
        SCROLLBAR_THUMB_MIN_HEIGHT)
    hint.track_rect = track_rect
    hint.thumb_rect = thumb_rect
    hint.hovered_thumb = in_interaction &&
        rl.CheckCollisionPointRec(local_mouse, thumb_rect)
    return hint
}

//   Finalize scrollbar state, drag lifecycle, and clamped scroll output.
scroll_container_end :: proc(
    scroll_ref: Scroll_Container_Ref,
    content_height_final: f32,
    scroll_y_in: f32,
    mouse_input: Mouse_Input_State,
    scroll_offset: rl.Vector2,
    interaction_space_rect: rl.Rectangle,
    press_owner: ^core.Ui_Press_Owner_State) -> Scroll_Container_End_Result {

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
        scroll_container_release_press(
            press_owner,
            scroll_ref.id,
            &state_out.is_dragging_thumb,
            &state_out.drag_offset_y)
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
        scroll_container_release_press(
            press_owner,
            scroll_ref.id,
            &state_out.is_dragging_thumb,
            &state_out.drag_offset_y)
        return Scroll_Container_End_Result{
            scroll_y_out = scroll_y_out,
            state_out = state_out,
            has_scrollbar = false,
            track_rect = rl.Rectangle{},
            thumb_rect = rl.Rectangle{},
        }
    }

    if !state_out.is_dragging_thumb {
        scroll_container_try_capture_press(
            press_owner,
            scroll_ref.id,
            mouse_input,
            rl.CheckCollisionPointRec(local_mouse, thumb_rect),
            local_mouse,
            thumb_rect,
            &state_out.is_dragging_thumb,
            &state_out.drag_offset_y)
    }

    if state_out.is_dragging_thumb {
        if !mouse_input.left_down {
            scroll_container_release_press(
                press_owner,
                scroll_ref.id,
                &state_out.is_dragging_thumb,
                &state_out.drag_offset_y)
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

    if mouse_input.left_pressed &&
        rl.CheckCollisionPointRec(mouse_input.position, thumb) {
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

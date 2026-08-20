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

//   Inputs for starting a scroll-container frame: identity, geometry, current
//   scroll position, content extent, pointer input, and shared press/drag
//   ownership, grouped so the begin call passes one coherent value.
Scroll_Container_Begin_Params :: struct {
    id:                     int,
    rect:                   rl.Rectangle,
    scroll_y_in:            f32,
    content_height_hint:    f32,
    mouse_input:            Mouse_Input_State,
    scroll_offset:          rl.Vector2,
    interaction_space_rect: rl.Rectangle,
    wheel_step:             f32,
    press_owner:            ^core.Ui_Press_Owner_State,
    state_in:               Scroll_Container_State,
}

//   Mutable drag state for one scrollbar thumb interaction, grouped with the
//   panel geometry and scroll limits it operates against.
Scrollbar_Drag_Context :: struct {
    mouse_input:  Mouse_Input_State,
    thumb:        rl.Rectangle,
    panel_y:      f32,
    panel_height: f32,
    thumb_h:      f32,
    max_scroll:   f32,
    scroll_y:     ^f32,
    dragging:     ^bool,
    drag_off:     ^f32,
    drag_epsilon: f32,
}

//   Overflow geometry hint computed before drag lifecycle in scroll begin.
Scroll_Overflow_Hint :: struct {
    had_overflow:   bool,
    track_rect:     rl.Rectangle,
    thumb_rect:     rl.Rectangle,
    hovered_thumb:  bool,
}

Vertical_Scrollbar_Geometry :: struct {
    track_rect:    rl.Rectangle,
    thumb_rect:    rl.Rectangle,
    thumb_height:  f32,
    has_scrollbar: bool,
}

//   Pointer/drag inputs for one scrollbar thumb capture attempt.
Scrollbar_Capture_Input :: struct {
    mouse_input:   Mouse_Input_State,
    hovered_thumb: bool,
    local_mouse:   rl.Vector2,
    thumb_rect:    rl.Rectangle,
}

//   Panel geometry and scroll range for one vertical scrollbar.
Vertical_Scrollbar_Input :: struct {
    panel:      rl.Rectangle,
    content_h:  f32,
    scroll_y:   f32,
    max_scroll: f32,
}

//   Interaction geometry for one overflow-hint computation.
Scroll_Overflow_Geometry :: struct {
    view_rect:              rl.Rectangle,
    content_height_hint:    f32,
    scroll_offset:          rl.Vector2,
    interaction_space_rect: rl.Rectangle,
    local_mouse:            rl.Vector2,
}

//   Inputs for finalizing one scroll-container frame, grouped so the end call
//   passes one coherent value.
Scroll_Container_End_Params :: struct {
    scroll_ref:             Scroll_Container_Ref,
    content_height_final:   f32,
    scroll_y_in:            f32,
    mouse_input:            Mouse_Input_State,
    scroll_offset:          rl.Vector2,
    interaction_space_rect: rl.Rectangle,
    press_owner:            ^core.Ui_Press_Owner_State,
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
    input: Scrollbar_Capture_Input,
    is_dragging_thumb: ^bool,
    drag_offset_y: ^f32) {

    if press_owner^.active || !input.mouse_input.left_pressed || !input.hovered_thumb {
        return
    }

    press_owner^.active = true
    press_owner^.kind = .Scrollbar
    press_owner^.id = id
    is_dragging_thumb^ = true
    drag_offset_y^ = input.local_mouse.y - input.thumb_rect.y
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

//   Advance the thumb-drag lifecycle for one scroll-container begin frame.
scroll_container_begin_drag :: proc(
    params: Scroll_Container_Begin_Params,
    hint: Scroll_Overflow_Hint,
    local_mouse: rl.Vector2,
    is_dragging_thumb: ^bool,
    drag_offset_y: ^f32) {

    id := params.id
    press_owner := params.press_owner
    owns_press := scroll_container_owns_press(press_owner, id)
    if hint.had_overflow && is_dragging_thumb^ && !owns_press {
        is_dragging_thumb^ = false
        drag_offset_y^ = 0
    }

    if hint.had_overflow && !is_dragging_thumb^ {
        scroll_container_try_capture_press(
            press_owner,
            id,
            Scrollbar_Capture_Input{params.mouse_input, hint.hovered_thumb,
                local_mouse, hint.thumb_rect},
            is_dragging_thumb,
            drag_offset_y)
    }
}

//   Build the scroll-container frame reference from the begin-frame results.
scroll_container_build_ref :: #force_inline proc(
    params: Scroll_Container_Begin_Params,
    hint: Scroll_Overflow_Hint,
    view_rect: rl.Rectangle,
    hovered_view: bool,
    state: Scroll_Container_State) -> Scroll_Container_Ref {

    return Scroll_Container_Ref{
        id = params.id,
        view_rect = view_rect,
        wheel_step = max(0.0, params.wheel_step),
        had_overflow_hint = hint.had_overflow,
        is_hovered_view = hovered_view,
        is_hovered_thumb = hint.hovered_thumb,
        is_dragging_thumb = state.is_dragging_thumb,
        drag_offset_y = state.drag_offset_y,
        track_rect = hint.track_rect,
        thumb_rect = hint.thumb_rect,
    }
}

//   Create scroll-container frame state and apply wheel scrolling from hint data.
scroll_container_begin :: proc(
    params: Scroll_Container_Begin_Params) -> Scroll_Container_Begin_Result {

    mouse_input := params.mouse_input

    view_rect := clamp_non_negative_rect(params.rect)
    local_mouse := scroll_container_local_mouse(mouse_input, params.scroll_offset)
    in_interaction :=
        scroll_container_in_interaction_space(local_mouse,
            params.interaction_space_rect)
    hovered_view := in_interaction && rl.CheckCollisionPointRec(local_mouse, view_rect)

    use_wheel_step := max(0.0, params.wheel_step)
    scroll_y_out := max(0.0, params.scroll_y_in)

    hint := scroll_overflow_hint(
        Scroll_Overflow_Geometry{view_rect, params.content_height_hint,
            params.scroll_offset, params.interaction_space_rect, local_mouse},
        mouse_input, &scroll_y_out, use_wheel_step)

    is_dragging_thumb := params.state_in.is_dragging_thumb
    drag_offset_y := params.state_in.drag_offset_y
    scroll_container_begin_drag(params, hint, local_mouse,
        &is_dragging_thumb, &drag_offset_y)

    scroll_ref := scroll_container_build_ref(params, hint, view_rect, hovered_view,
        Scroll_Container_State{is_dragging_thumb, drag_offset_y})

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

//   Compute scrollbar geometry and apply wheel scroll when content overflows.
//   Compute scrollbar geometry and apply wheel scroll when content overflows.
scroll_overflow_hint :: proc(
    geom: Scroll_Overflow_Geometry,
    mouse_input: Mouse_Input_State,
    scroll_y_out: ^f32,
    use_wheel_step: f32) -> Scroll_Overflow_Hint {

    view_rect := geom.view_rect
    hint := Scroll_Overflow_Hint{}
    if geom.content_height_hint <= view_rect.height {
        return hint
    }

    max_scroll_hint := max(0.0, geom.content_height_hint - view_rect.height)
    hint.had_overflow = max_scroll_hint > 0
    if !hint.had_overflow {
        return hint
    }

    in_interaction :=
        scroll_container_in_interaction_space(geom.local_mouse,
            geom.interaction_space_rect)
    hovered_view := in_interaction &&
        rl.CheckCollisionPointRec(geom.local_mouse, view_rect)
    if hovered_view && mouse_input.wheel_delta != 0 && use_wheel_step > 0 {
        scroll_y_out^ -= mouse_input.wheel_delta * use_wheel_step
    }
    clamp_scroll_position(scroll_y_out, max_scroll_hint)

    scrollbar := build_vertical_scrollbar(
        Vertical_Scrollbar_Input{view_rect, geom.content_height_hint,
            scroll_y_out^, max_scroll_hint},
        SCROLLBAR_WIDTH,
        SCROLLBAR_THUMB_MIN_HEIGHT)
    hint.track_rect = scrollbar.track_rect
    hint.thumb_rect = scrollbar.thumb_rect
    hint.hovered_thumb = in_interaction &&
        rl.CheckCollisionPointRec(geom.local_mouse, scrollbar.thumb_rect)
    return hint
}

//   Build the no-scrollbar end result, releasing any owned press.
scroll_container_end_no_scrollbar :: proc(
    press_owner: ^core.Ui_Press_Owner_State,
    id: int,
    scroll_y_out: f32,
    state_out: ^Scroll_Container_State) -> Scroll_Container_End_Result {

    scroll_container_release_press(
        press_owner,
        id,
        &state_out.is_dragging_thumb,
        &state_out.drag_offset_y)
    return Scroll_Container_End_Result{
        scroll_y_out = scroll_y_out,
        state_out = state_out^,
        has_scrollbar = false,
        track_rect = rl.Rectangle{},
        thumb_rect = rl.Rectangle{},
    }
}

//   Update scroll position from an active thumb drag, or end the drag.
scroll_container_apply_drag :: proc(
    params: Scroll_Container_End_Params,
    local_mouse: rl.Vector2,
    scrollbar: Vertical_Scrollbar_Geometry,
    scroll_y_out: ^f32,
    state_out: ^Scroll_Container_State) {

    if !params.mouse_input.left_down {
        scroll_container_release_press(
            params.press_owner,
            params.scroll_ref.id,
            &state_out.is_dragging_thumb,
            &state_out.drag_offset_y)
        return
    }

    view_rect := params.scroll_ref.view_rect
    max_scroll := max(0.0, params.content_height_final - view_rect.height)
    thumb_range := view_rect.height - scrollbar.thumb_height
    if thumb_range <= SCROLLBAR_DRAG_EPSILON {
        scroll_y_out^ = 0
    } else {
        new_thumb_y := local_mouse.y - state_out.drag_offset_y
        t := (new_thumb_y - view_rect.y) / thumb_range
        scroll_y_out^ = clamp(t, 0, 1) * max_scroll
    }
    clamp_scroll_position(scroll_y_out, max_scroll)
}

//   Capture the thumb press when the drag has not started yet.
scroll_container_end_try_capture :: proc(
    params: Scroll_Container_End_Params,
    local_mouse: rl.Vector2,
    scrollbar: Vertical_Scrollbar_Geometry,
    state_out: ^Scroll_Container_State) {

    if state_out.is_dragging_thumb {
        return
    }
    scroll_container_try_capture_press(
        params.press_owner,
        params.scroll_ref.id,
        Scrollbar_Capture_Input{params.mouse_input,
            rl.CheckCollisionPointRec(local_mouse, scrollbar.thumb_rect),
            local_mouse, scrollbar.thumb_rect},
        &state_out.is_dragging_thumb,
        &state_out.drag_offset_y)
}

//   Draw the scrollbar track and thumb when a scrollbar is present.
scroll_container_draw_scrollbar :: #force_inline proc(
    scrollbar: Vertical_Scrollbar_Geometry) {

    if !scrollbar.has_scrollbar {
        return
    }
    rl.DrawRectangleRec(scrollbar.track_rect, BACKGROUND_COLOR)
    rl.DrawRectangleRec(scrollbar.thumb_rect, UI_BORDER_COLOR)
}

//   Apply an active thumb drag and rebuild the scrollbar at the new position.
scroll_container_end_apply_drag :: proc(
    params: Scroll_Container_End_Params,
    local_mouse: rl.Vector2,
    scrollbar: Vertical_Scrollbar_Geometry,
    scroll_y_out: ^f32,
    state_out: ^Scroll_Container_State) -> Vertical_Scrollbar_Geometry {

    if !state_out.is_dragging_thumb {
        return scrollbar
    }
    scroll_container_apply_drag(params, local_mouse, scrollbar, scroll_y_out, state_out)
    view_rect := params.scroll_ref.view_rect
    max_scroll := max(0.0, params.content_height_final - view_rect.height)
    return build_vertical_scrollbar(
        Vertical_Scrollbar_Input{view_rect, params.content_height_final,
            scroll_y_out^, max_scroll},
        SCROLLBAR_WIDTH,
        SCROLLBAR_THUMB_MIN_HEIGHT)
}

//   Resolve the initial scrollbar for one end frame, or none when content fits.
//
// Returns:
//   - scrollbar: The scrollbar geometry when present.
//   - ok: true when a scrollbar should be processed this frame.
scroll_container_end_initial_scrollbar :: proc(
    params: Scroll_Container_End_Params,
    scroll_y_out: ^f32) -> (Vertical_Scrollbar_Geometry, bool) {

    view_rect := params.scroll_ref.view_rect
    max_scroll := max(0.0, params.content_height_final - view_rect.height)
    clamp_scroll_position(scroll_y_out, max_scroll)
    scrollbar := build_vertical_scrollbar(
        Vertical_Scrollbar_Input{view_rect, params.content_height_final,
            scroll_y_out^, max_scroll},
        SCROLLBAR_WIDTH,
        SCROLLBAR_THUMB_MIN_HEIGHT)
    return scrollbar, max_scroll > 0 && scrollbar.has_scrollbar
}

//   Finalize scrollbar state, drag lifecycle, and clamped scroll output.
scroll_container_end :: proc(
    params: Scroll_Container_End_Params) -> Scroll_Container_End_Result {

    defer rl.EndScissorMode()

    press_owner := params.press_owner
    local_mouse := scroll_container_local_mouse(params.mouse_input, params.scroll_offset)

    scroll_y_out := max(0.0, params.scroll_y_in)
    state_out := Scroll_Container_State{
        is_dragging_thumb = params.scroll_ref.is_dragging_thumb,
        drag_offset_y = params.scroll_ref.drag_offset_y,
    }

    scrollbar, has_scrollbar :=
        scroll_container_end_initial_scrollbar(params, &scroll_y_out)
    if !has_scrollbar {
        return scroll_container_end_no_scrollbar(press_owner, params.scroll_ref.id,
            scroll_y_out, &state_out)
    }

    scroll_container_end_try_capture(params, local_mouse, scrollbar, &state_out)

    scrollbar = scroll_container_end_apply_drag(params, local_mouse, scrollbar,
        &scroll_y_out, &state_out)

    scroll_container_draw_scrollbar(scrollbar)

    return Scroll_Container_End_Result{
        scroll_y_out = scroll_y_out,
        state_out = state_out,
        has_scrollbar = scrollbar.has_scrollbar,
        track_rect = scrollbar.track_rect,
        thumb_rect = scrollbar.thumb_rect,
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
    input: Vertical_Scrollbar_Input,
    scrollbar_width: f32,
    thumb_min_height: f32) -> Vertical_Scrollbar_Geometry {

    panel := input.panel
    if input.max_scroll <= 0 {
        return Vertical_Scrollbar_Geometry{rl.Rectangle{}, rl.Rectangle{}, 0, false}
    }

    track := rl.Rectangle{
        panel.x + panel.width - scrollbar_width,
        panel.y,
        scrollbar_width,
        panel.height,
    }

    thumb_h := scrollbar_thumb_height(panel.height, input.content_h, thumb_min_height)
    thumb_y := scrollbar_thumb_y(panel.y, panel.height, thumb_h, input.scroll_y,
        input.max_scroll)
    thumb := rl.Rectangle{track.x, thumb_y, scrollbar_width, thumb_h}
    return Vertical_Scrollbar_Geometry{track, thumb, thumb_h, true}
}

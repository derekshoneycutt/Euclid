package ui

import viewmodel "../model"
import geometry "../../core/geometry"

Scroll_Container_State :: struct {
    is_dragging_thumb: bool,
    drag_offset_y: f32,
}

// Complete scroll state prepared before rendering for one container frame.
Scroll_Container_Update_Result :: struct {
    view_rect: geometry.Rectangle,
    scroll_y_out: f32,
    state_out: Scroll_Container_State,
    scrollbar: Vertical_Scrollbar_Geometry,
    pointer_reserved: bool,
    wheel_consumed: bool,
}

// Mutable scrollbar interaction values returned to the frame preparation owner.
Scroll_Container_Interaction_Result :: struct {
    state: Scroll_Container_State,
    scrollbar: Vertical_Scrollbar_Geometry,
    owned_for_frame: bool,
}

// Geometry and range inputs used while advancing scrollbar interaction.
Scroll_Container_Interaction_Input :: struct {
    params: Scroll_Container_Update_Params,
    local_mouse: geometry.Vector2,
    hovered_thumb: bool,
    max_scroll: f32,
    initial: Vertical_Scrollbar_Geometry,
}

Vertical_Scrollbar_Geometry :: struct {
    track_rect: geometry.Rectangle,
    thumb_rect: geometry.Rectangle,
    thumb_height: f32,
    has_scrollbar: bool,
}

//   Pointer/drag inputs for one scrollbar thumb capture attempt.
Scrollbar_Capture_Input :: struct {
    mouse_input: Input_Frame,
    hovered_thumb: bool,
    local_mouse: geometry.Vector2,
    thumb_rect: geometry.Rectangle,
}

//   Panel geometry and scroll range for one vertical scrollbar.
Vertical_Scrollbar_Input :: struct {
    panel: geometry.Rectangle,
    content_h: f32,
    scroll_y: f32,
    max_scroll: f32,
}

// Inputs for resolving scrolling and capture before rendering.
Scroll_Container_Update_Params :: struct {
    id: int,
    rect: geometry.Rectangle,
    scroll_y_in: f32,
    content_height: f32,
    mouse_input: Input_Frame,
    scroll_offset: geometry.Vector2,
    interaction_space_rect: geometry.Rectangle,
    wheel_step: f32,
    press_owner: ^viewmodel.Ui_Press_Owner_State,
    state_in: Scroll_Container_State,
}

// Apply one eligible wheel delta and report whether it was consumed.
scroll_container_update_wheel :: proc(
    params: Scroll_Container_Update_Params,
    hovered_view: bool,
    max_scroll: f32,
    scroll_y: ^f32) -> bool {
    consumed := max_scroll > 0 && hovered_view &&
        params.mouse_input.mouse_wheel_delta != 0 && params.wheel_step > 0
    if consumed {
        scroll_y^ -= params.mouse_input.mouse_wheel_delta * params.wheel_step
        clamp_scroll_position(scroll_y, max_scroll)
    }
    return consumed
}

// Advance capture, drag, and release state against prepared scrollbar geometry.
scroll_container_update_interaction :: proc(
    input: Scroll_Container_Interaction_Input,
    scroll_y: ^f32) -> Scroll_Container_Interaction_Result {
    params := input.params
    state := params.state_in
    owns_press := scroll_container_owns_press(params.press_owner, params.id)
    owned_for_frame := owns_press
    if state.is_dragging_thumb && !owns_press { state = {} }
    if input.initial.has_scrollbar && !state.is_dragging_thumb {
        scroll_container_try_capture_press(params.press_owner, params.id,
            {params.mouse_input, input.hovered_thumb, input.local_mouse,
                input.initial.thumb_rect},
            &state.is_dragging_thumb, &state.drag_offset_y)
    }
    owns_press = scroll_container_owns_press(params.press_owner, params.id)
    owned_for_frame = owned_for_frame || owns_press
    scrollbar := input.initial
    if state.is_dragging_thumb && owns_press &&
        input_frame_left_down(params.mouse_input) {
        thumb_range := params.rect.height - scrollbar.thumb_height
        if thumb_range <= SCROLLBAR_DRAG_EPSILON {
            scroll_y^ = 0
        } else {
            thumb_y := input.local_mouse.y - state.drag_offset_y
            scroll_y^ = clamp((thumb_y - params.rect.y) / thumb_range, 0, 1) *
                input.max_scroll
        }
        scrollbar = build_vertical_scrollbar(
            {params.rect, params.content_height, scroll_y^, input.max_scroll},
            SCROLLBAR_WIDTH, SCROLLBAR_THUMB_MIN_HEIGHT)
    } else if state.is_dragging_thumb && owns_press || !input.initial.has_scrollbar {
        scroll_container_release_press(params.press_owner, params.id,
            &state.is_dragging_thumb, &state.drag_offset_y)
    }
    return {state, scrollbar, owned_for_frame}
}

// Resolve one scrollbar's wheel, capture, drag, and release before drawing.
scroll_container_update :: proc(
    params: Scroll_Container_Update_Params) -> Scroll_Container_Update_Result {
    view_rect := params.rect
    view_rect.width = max(f32(0), view_rect.width)
    view_rect.height = max(f32(0), view_rect.height)
    local_mouse := scroll_container_local_mouse(
        params.mouse_input, params.scroll_offset)
    in_interaction := scroll_container_in_interaction_space(
        local_mouse, params.interaction_space_rect)
    max_scroll := max(0.0, params.content_height - view_rect.height)
    scroll_y := max(0.0, params.scroll_y_in)
    clamp_scroll_position(&scroll_y, max_scroll)
    hovered_view := in_interaction && geometry.rectangle_contains(
        view_rect, local_mouse)
    wheel_consumed := scroll_container_update_wheel(
        params, hovered_view, max_scroll, &scroll_y)
    scrollbar := build_vertical_scrollbar(
        {view_rect, params.content_height, scroll_y, max_scroll},
        SCROLLBAR_WIDTH, SCROLLBAR_THUMB_MIN_HEIGHT)
    hovered_thumb := scrollbar.has_scrollbar && in_interaction &&
        geometry.rectangle_contains(scrollbar.thumb_rect, local_mouse)
    interaction := scroll_container_update_interaction(
        {params, local_mouse, hovered_thumb, max_scroll, scrollbar}, &scroll_y)
    scrollbar = interaction.scrollbar
    pointer_reserved := scrollbar.has_scrollbar &&
        (interaction.owned_for_frame || in_interaction &&
            geometry.rectangle_contains(scrollbar.track_rect, local_mouse))
    return {view_rect, scroll_y, interaction.state, scrollbar,
        pointer_reserved, wheel_consumed}
}

//   Convert screen-space pointer position to local interaction space.
scroll_container_local_mouse :: #force_inline proc(
    mouse_input: Input_Frame,
    scroll_offset: geometry.Vector2) -> geometry.Vector2 {

    return geometry.Vector2{
        mouse_input.mouse_position.x - scroll_offset.x,
        mouse_input.mouse_position.y - scroll_offset.y,
    }
}

//   Return whether local pointer input is inside the active interaction space.
scroll_container_in_interaction_space :: #force_inline proc(
    local_mouse: geometry.Vector2,
    interaction_space_rect: geometry.Rectangle) -> bool {

    return geometry.rectangle_contains(interaction_space_rect, local_mouse)
}

//   Return whether the shared press owner currently belongs to this scrollbar.
scroll_container_owns_press :: #force_inline proc(
    press_owner: ^viewmodel.Ui_Press_Owner_State,
    id: int) -> bool {

    return press_owner^.active &&
        press_owner^.kind == .Scrollbar &&
        press_owner^.id == id
}

//   Capture shared press ownership for a scrollbar thumb when available.
scroll_container_try_capture_press :: proc(
    press_owner: ^viewmodel.Ui_Press_Owner_State,
    id: int,
    input: Scrollbar_Capture_Input,
    is_dragging_thumb: ^bool,
    drag_offset_y: ^f32) {

    if press_owner^.active ||
        !input_frame_left_pressed(input.mouse_input) || !input.hovered_thumb {
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
    press_owner: ^viewmodel.Ui_Press_Owner_State,
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
        return Vertical_Scrollbar_Geometry{
            geometry.Rectangle{}, geometry.Rectangle{}, 0, false}
    }

    track := geometry.Rectangle{
        panel.x + panel.width - scrollbar_width,
        panel.y,
        scrollbar_width,
        panel.height,
    }

    thumb_h := scrollbar_thumb_height(panel.height, input.content_h, thumb_min_height)
    thumb_y := scrollbar_thumb_y(panel.y, panel.height, thumb_h, input.scroll_y,
        input.max_scroll)
    thumb := geometry.Rectangle{track.x, thumb_y, scrollbar_width, thumb_h}
    return Vertical_Scrollbar_Geometry{track, thumb, thumb_h, true}
}

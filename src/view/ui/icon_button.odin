package ui

import viewmodel "../model"
import geometry "../../core/geometry"

ICON_BUTTON_DEFAULT_INSET_SCALE :: 0.86
ICON_BUTTON_HOVER_SCALE_ADD :: 0.08
ICON_BUTTON_PRESS_SCALE_SUB :: 0.16
ICON_BUTTON_PRESS_DARKEN :: 0.45

Icon_Button_Id :: enum {
    Refresh,
    Pause,
    Play,
    Gear,
    Gif,
    Books,
    Copy,
    None,
}

Icon_Button_Params :: struct {
    id: int,
    rect: geometry.Rectangle,
    icon_id: Icon_Button_Id,
    toggle: bool,
    mouse: Input_Frame,
    scroll_offset: geometry.Vector2,
    interaction_space_rect: geometry.Rectangle,
    interaction_enabled: bool,
    inset_scale: f32,
}

Icon_Button_Result :: struct {
    icon_drawn_rect: geometry.Rectangle,
    hovered: bool,
    pressed: bool,
    clicked: bool,
}

//   Return whether this icon button owns the shared press state.
icon_button_owns_press :: #force_inline proc(
    press_owner: ^viewmodel.Ui_Press_Owner_State,
    id: int) -> bool {

    return press_owner^.active &&
        press_owner^.kind == .Icon_Button &&
        press_owner^.id == id
}

//   Capture shared press ownership for an icon button on initial click.
icon_button_try_capture_press :: proc(
    press_owner: ^viewmodel.Ui_Press_Owner_State,
    params: Icon_Button_Params,
    hovered: bool,
    owns_press: ^bool) {

    if press_owner^.active || !params.interaction_enabled ||
        !input_frame_left_pressed(params.mouse) || !hovered {
        return
    }

    press_owner^.active = true
    press_owner^.kind = .Icon_Button
    press_owner^.id = params.id
    owns_press^ = true
}

//   Release shared press ownership for an icon button when the mouse hold ends.
icon_button_release_press :: proc(
    press_owner: ^viewmodel.Ui_Press_Owner_State,
    owns_press: ^bool,
    mouse: Input_Frame) {

    if !owns_press^ || input_frame_left_down(mouse) {
        return
    }

    press_owner^.active = false
    press_owner^.kind = .None
    press_owner^.id = -1
    owns_press^ = false
}

//   Resolve local mouse position from screen-space plus scroll offset.
icon_button_local_mouse :: #force_inline proc(
    mouse: Input_Frame,
    scroll_offset: geometry.Vector2) -> geometry.Vector2 {

    return geometry.Vector2{mouse.mouse_position.x - scroll_offset.x,
        mouse.mouse_position.y - scroll_offset.y}
}

//   Resolve icon draw rectangle centered in slot using min-dimension sizing.
icon_button_icon_draw_rect :: #force_inline proc(
    rect: geometry.Rectangle,
    inset_scale: f32) -> geometry.Rectangle {

    draw_rect := rect
    draw_rect.width = max(f32(0), draw_rect.width)
    draw_rect.height = max(f32(0), draw_rect.height)
    base_size := min(draw_rect.width, draw_rect.height)
    use_scale := max(inset_scale, 0.0)
    if use_scale <= 0 {
        use_scale = ICON_BUTTON_DEFAULT_INSET_SCALE
    }
    icon_size := base_size * use_scale

    center_x := draw_rect.x + draw_rect.width * 0.5
    center_y := draw_rect.y + draw_rect.height * 0.5
    return geometry.Rectangle{
        center_x - icon_size * 0.5,
        center_y - icon_size * 0.5,
        icon_size,
        icon_size,
    }
}

//   Resolve one icon button interaction without issuing drawing commands.
update_icon_button :: proc(
    params: Icon_Button_Params,
    press_owner: ^viewmodel.Ui_Press_Owner_State) -> Icon_Button_Result {
    slot_rect := params.rect
    slot_rect.width = max(f32(0), slot_rect.width)
    slot_rect.height = max(f32(0), slot_rect.height)
    local_mouse := icon_button_local_mouse(params.mouse, params.scroll_offset)

    hovered := params.interaction_enabled &&
        geometry.rectangle_contains(slot_rect, local_mouse) &&
        geometry.rectangle_contains(params.interaction_space_rect, local_mouse)
    owns_press := icon_button_owns_press(press_owner, params.id)
    icon_button_try_capture_press(press_owner, params, hovered, &owns_press)
    pressed := owns_press && input_frame_left_down(params.mouse)

    hover_t: f32 = 0
    if hovered {
        hover_t = 1
    }

    press_t: f32 = 0
    if pressed {
        press_t = 1
    }

    result := Icon_Button_Result{
        icon_drawn_rect = icon_button_icon_draw_rect(
            slot_rect, params.inset_scale * (1.0 +
                ICON_BUTTON_HOVER_SCALE_ADD * hover_t -
                ICON_BUTTON_PRESS_SCALE_SUB * press_t)),
        hovered = hovered,
        pressed = pressed,
        clicked = owns_press && input_frame_left_pressed(params.mouse),
    }
    icon_button_release_press(press_owner, &owns_press, params.mouse)
    return result
}

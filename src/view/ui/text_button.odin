package ui

import viewmodel "../model"

import view_font "../font"
import color "../../core/color"
import geometry "../../core/geometry"

Text_Button_Params :: struct {
    id : int,
    rect : geometry.Rectangle,
    label : string,
    enabled : bool,
    mouse : Input_Frame,
    scroll_offset : geometry.Vector2,
    interaction_space_rect : geometry.Rectangle,
    interaction_enabled : bool,
    font : view_font.Font_Face,
    has_font_color_override : bool,
    font_color_override : color.Color_RGBA8,
    font_resolver : view_font.Font_Resolver,
}

Text_Button_Result :: struct {
    button_drawn_rect : geometry.Rectangle,
    clicked : bool,
    hovered : bool,
    pressed : bool,
}

//   Resolve whether this text button currently owns the shared press state.
text_button_owns_press :: #force_inline proc(
    press_owner: ^viewmodel.Ui_Press_Owner_State,
    id: int) -> bool {

    return press_owner^.active &&
        press_owner^.kind == .Text_Button &&
        press_owner^.id == id
}

//   Capture shared press ownership for a text button when it is newly pressed.
text_button_try_capture_press :: proc(
    press_owner: ^viewmodel.Ui_Press_Owner_State,
    params: Text_Button_Params,
    hovered: bool,
    can_interact: bool,
    owns_press: ^bool) {

    if !can_interact || press_owner^.active ||
        !input_frame_left_pressed(params.mouse) || !hovered {
        return
    }

    press_owner^.active = true
    press_owner^.kind = .Text_Button
    press_owner^.id = params.id
    owns_press^ = true
}

//   Release shared press ownership and resolve whether the button was clicked.
text_button_release_press :: proc(
    press_owner: ^viewmodel.Ui_Press_Owner_State,
    mouse: Input_Frame,
    can_interact: bool,
    hovered_item: bool,
    owns_press: ^bool) -> bool {

    if !owns_press^ || !input_frame_left_released(mouse) {
        return false
    }

    clicked := can_interact && hovered_item
    press_owner^.active = false
    press_owner^.kind = .None
    press_owner^.id = -1
    owns_press^ = false
    return clicked
}

//   Convert screen-space mouse position into local interaction space.
text_button_local_mouse :: #force_inline proc(
    mouse_input: Input_Frame,
    scroll_offset: geometry.Vector2) -> geometry.Vector2 {

    return geometry.Vector2{
        mouse_input.mouse_position.x - scroll_offset.x,
        mouse_input.mouse_position.y - scroll_offset.y,
    }
}

//   Resolve one text button interaction without issuing drawing commands.
update_text_button :: proc(
    params: Text_Button_Params,
    press_owner: ^viewmodel.Ui_Press_Owner_State) -> Text_Button_Result {

    button_rect := params.rect
    button_rect.width = max(f32(0), button_rect.width)
    button_rect.height = max(f32(0), button_rect.height)
    local_mouse := text_button_local_mouse(params.mouse, params.scroll_offset)

    hovered_item := geometry.rectangle_contains(button_rect, local_mouse)
    hovered_space := geometry.rectangle_contains(
        params.interaction_space_rect, local_mouse)
    hovered := hovered_item && hovered_space

    owns_press := text_button_owns_press(press_owner, params.id)
    can_interact := params.enabled && params.interaction_enabled
    text_button_try_capture_press(press_owner, params, hovered, can_interact, &owns_press)

    clicked := text_button_release_press(
        press_owner,
        params.mouse,
        can_interact,
        hovered_item,
        &owns_press)

    return Text_Button_Result{
        button_drawn_rect = button_rect,
        clicked = clicked,
        hovered = hovered,
        pressed = owns_press && input_frame_left_down(params.mouse),
    }
}

package ui

import "../../core"
import view_core "../core"
import "core:strings"

import rl "vendor:raylib"

Text_Button_Params :: struct {
    id: int,
    rect: rl.Rectangle,
    label: string,
    enabled: bool,
    mouse: Mouse_Input_State,
    scroll_offset: rl.Vector2,
    interaction_space_rect: rl.Rectangle,
    interaction_enabled: bool,
    font: rl.Font,
    has_font_color_override: bool,
    font_color_override: rl.Color,
}

Text_Button_Result :: struct {
    button_drawn_rect: rl.Rectangle,
    clicked: bool,
    hovered: bool,
    pressed: bool,
}

//   Resolve whether this text button currently owns the shared press state.
text_button_owns_press :: #force_inline proc(
    press_owner: ^core.Ui_Press_Owner_State,
    id: int) -> bool {

    return press_owner^.active &&
        press_owner^.kind == .Text_Button &&
        press_owner^.id == id
}

//   Capture shared press ownership for a text button when it is newly pressed.
text_button_try_capture_press :: proc(
    press_owner: ^core.Ui_Press_Owner_State,
    params: Text_Button_Params,
    hovered: bool,
    can_interact: bool,
    owns_press: ^bool) {

    if !can_interact || press_owner^.active || !params.mouse.left_pressed || !hovered {
        return
    }

    press_owner^.active = true
    press_owner^.kind = .Text_Button
    press_owner^.id = params.id
    owns_press^ = true
}

//   Release shared press ownership and resolve whether the button was clicked.
text_button_release_press :: proc(
    press_owner: ^core.Ui_Press_Owner_State,
    mouse: Mouse_Input_State,
    can_interact: bool,
    hovered_item: bool,
    owns_press: ^bool) -> bool {

    if !owns_press^ || !mouse.left_released {
        return false
    }

    clicked := can_interact && hovered_item
    press_owner^.active = false
    press_owner^.kind = .None
    press_owner^.id = -1
    owns_press^ = false
    return clicked
}

//   Resolve text button background, foreground, and border colors from state.
text_button_colors :: proc(
    params: Text_Button_Params,
    hovered: bool,
    pressed: bool) -> (rl.Color, rl.Color, rl.Color) {

    bg := BACKGROUND_COLOR
    fg := UI_TEXT_COLOR
    border := UI_BORDER_COLOR
    if !params.enabled {
        bg = rl.Color{48, 48, 48, 255}
        fg = rl.Color{110, 110, 110, 255}
        border = rl.Color{78, 78, 78, 255}
    } else if pressed {
        bg = UI_BORDER_COLOR
        fg = BACKGROUND_COLOR
    } else if hovered && params.interaction_enabled {
        bg = UI_COMPONENT_BACKGROUND_COLOR
    }

    if params.has_font_color_override {
        fg = params.font_color_override
    }
    return bg, fg, border
}

//   Convert screen-space mouse position into local interaction space.
text_button_local_mouse :: #force_inline proc(
    mouse_input: Mouse_Input_State,
    scroll_offset: rl.Vector2) -> rl.Vector2 {

    return rl.Vector2{
        mouse_input.position.x - scroll_offset.x,
        mouse_input.position.y - scroll_offset.y,
    }
}

//   Draw one text button and resolve release-confirmed click interaction.
draw_text_button :: proc(
    params: Text_Button_Params,
    press_owner: ^core.Ui_Press_Owner_State) -> Text_Button_Result {

    button_rect := clamp_non_negative_rect(params.rect)
    local_mouse := text_button_local_mouse(params.mouse, params.scroll_offset)

    hovered_item := rl.CheckCollisionPointRec(local_mouse, button_rect)
    hovered_space := rl.CheckCollisionPointRec(local_mouse, params.interaction_space_rect)
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

    pressed := owns_press && params.mouse.left_down
    bg, fg, border := text_button_colors(params, hovered, pressed)

    rl.DrawRectangleRec(button_rect, bg)
    rl.DrawRectangleLinesEx(button_rect, 1, border)

    label_cstr := strings.clone_to_cstring(params.label, context.temp_allocator)
    measured := rl.MeasureTextEx(params.font, label_cstr, TREE_FONT_SIZE, 0)
    text_x := int(button_rect.x + (button_rect.width - measured.x) * 0.5)
    text_y := int(button_rect.y + (button_rect.height - measured.y) * 0.5)
    view_core.ui_text(params.label, text_x, text_y, fg, params.font)

    return Text_Button_Result{
        button_drawn_rect = button_rect,
        clicked = clicked,
        hovered = hovered,
        pressed = pressed,
    }
}
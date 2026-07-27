package ui

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

//   Clamp a rectangle so width and height are never negative.
text_button_clamp_rect :: #force_inline proc(rect: rl.Rectangle) -> rl.Rectangle {
    clamped := rect
    if clamped.width < 0 {
        clamped.width = 0
    }
    if clamped.height < 0 {
        clamped.height = 0
    }
    return clamped
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
    press_active: ^bool,
    press_id: ^int) -> Text_Button_Result {

    button_rect := text_button_clamp_rect(params.rect)
    local_mouse := text_button_local_mouse(params.mouse, params.scroll_offset)

    hovered_item := rl.CheckCollisionPointRec(local_mouse, button_rect)
    hovered_space := rl.CheckCollisionPointRec(local_mouse, params.interaction_space_rect)
    hovered := hovered_item && hovered_space

    owns_press := press_active^ && press_id^ == params.id
    can_interact := params.enabled && params.interaction_enabled
    if can_interact && !owns_press && params.mouse.left_pressed && hovered {
        press_active^ = true
        press_id^ = params.id
        owns_press = true
    }

    clicked := false
    if owns_press && params.mouse.left_released {
        clicked = can_interact && hovered_item
        press_active^ = false
        press_id^ = -1
        owns_press = false
    }

    pressed := owns_press && params.mouse.left_down

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

    rl.DrawRectangleRec(button_rect, bg)
    rl.DrawRectangleLinesEx(button_rect, 1, border)

    label_cstr := strings.clone_to_cstring(params.label, context.temp_allocator)
    measured := rl.MeasureTextEx(params.font, label_cstr, TREE_FONT_SIZE, 0)
    text_x := int(button_rect.x + (button_rect.width - measured.x) * 0.5)
    text_y := int(button_rect.y + (button_rect.height - measured.y) * 0.5)
    ui_text(params.label, text_x, text_y, fg, params.font)

    return Text_Button_Result{
        button_drawn_rect = button_rect,
        clicked = clicked,
        hovered = hovered,
        pressed = pressed,
    }
}
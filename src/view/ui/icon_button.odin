package ui

import "../../core"
import view_core "../core"

import rl "vendor:raylib"

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
    rect: rl.Rectangle,
    icon_id: Icon_Button_Id,
    toggle: bool,
    mouse: Mouse_Input_State,
    scroll_offset: rl.Vector2,
    interaction_space_rect: rl.Rectangle,
    interaction_enabled: bool,
    inset_scale: f32,
}

Icon_Button_Result :: struct {
    icon_drawn_rect: rl.Rectangle,
    hovered: bool,
    pressed: bool,
    clicked: bool,
}

//   Return whether this icon button owns the shared press state.
icon_button_owns_press :: #force_inline proc(
    press_owner: ^core.Ui_Press_Owner_State,
    id: int) -> bool {

    return press_owner^.active &&
        press_owner^.kind == .Icon_Button &&
        press_owner^.id == id
}

//   Capture shared press ownership for an icon button on initial click.
icon_button_try_capture_press :: proc(
    press_owner: ^core.Ui_Press_Owner_State,
    params: Icon_Button_Params,
    hovered: bool,
    owns_press: ^bool) {

    if press_owner^.active || !params.interaction_enabled ||
        !params.mouse.left_pressed || !hovered {
        return
    }

    press_owner^.active = true
    press_owner^.kind = .Icon_Button
    press_owner^.id = params.id
    owns_press^ = true
}

//   Release shared press ownership for an icon button when the mouse hold ends.
icon_button_release_press :: proc(
    press_owner: ^core.Ui_Press_Owner_State,
    owns_press: ^bool,
    mouse: Mouse_Input_State) {

    if !owns_press^ || mouse.left_down {
        return
    }

    press_owner^.active = false
    press_owner^.kind = .None
    press_owner^.id = -1
    owns_press^ = false
}

icon_button_darken :: #force_inline proc(color: rl.Color, amount: f32) -> rl.Color {
    t :=  clamp(amount, 0.0, 1.0)
    factor := 1.0 - (ICON_BUTTON_PRESS_DARKEN * t)
    return rl.Color{
        u8(f32(color.r) * factor),
        u8(f32(color.g) * factor),
        u8(f32(color.b) * factor),
        color.a,
    }
}

//   Resolve local mouse position from screen-space plus scroll offset.
icon_button_local_mouse :: #force_inline proc(
    mouse: Mouse_Input_State,
    scroll_offset: rl.Vector2) -> rl.Vector2 {

    return rl.Vector2{mouse.position.x - scroll_offset.x,
        mouse.position.y - scroll_offset.y}
}

//   Resolve icon draw rectangle centered in slot using min-dimension sizing.
icon_button_icon_draw_rect :: #force_inline proc(
    rect: rl.Rectangle,
    inset_scale: f32) -> rl.Rectangle {

    draw_rect := clamp_non_negative_rect(rect)
    base_size := min(draw_rect.width, draw_rect.height)
    use_scale := max(inset_scale, 0.0)
    if use_scale <= 0 {
        use_scale = ICON_BUTTON_DEFAULT_INSET_SCALE
    }
    icon_size := base_size * use_scale

    center_x := draw_rect.x + draw_rect.width * 0.5
    center_y := draw_rect.y + draw_rect.height * 0.5
    return rl.Rectangle{
        center_x - icon_size * 0.5,
        center_y - icon_size * 0.5,
        icon_size,
        icon_size,
    }
}

//   Draw icon glyph for a known icon-button id.
draw_icon_button_glyph :: proc(
    icon_id: Icon_Button_Id, rect: rl.Rectangle, color: rl.Color) {
    switch icon_id {
    case .Refresh:
        view_core.draw_refresh_icon(rect, color)
    case .Pause:
        view_core.draw_pause_icon(rect, color)
    case .Play:
        view_core.draw_play_icon(rect, color)
    case .Gear:
        view_core.draw_gear_icon(rect, color)
    case .Gif:
        view_core.draw_gif_icon(rect, color)
    case .Books:
        view_core.draw_books_icon(rect, color)
    case .Copy:
        view_core.draw_copy_icon(rect, color)
    case .None:
        // Intentional no-op for external/custom icon draw paths.
    }
}

//   Draw and resolve one icon button interaction result.
draw_icon_button :: proc(
    params: Icon_Button_Params,
    press_owner: ^core.Ui_Press_Owner_State) -> Icon_Button_Result {
    slot_rect := clamp_non_negative_rect(params.rect)
    local_mouse := icon_button_local_mouse(params.mouse, params.scroll_offset)

    hovered := params.interaction_enabled &&
        rl.CheckCollisionPointRec(local_mouse, slot_rect) &&
        rl.CheckCollisionPointRec(local_mouse, params.interaction_space_rect)
    owns_press := icon_button_owns_press(press_owner, params.id)
    icon_button_try_capture_press(press_owner, params, hovered, &owns_press)
    pressed := owns_press && params.mouse.left_down

    hover_t: f32 = 0
    if hovered {
        hover_t = 1
    }

    press_t: f32 = 0
    if pressed {
        press_t = 1
    }

    result := draw_icon_button_with_visual_state(params, hover_t, press_t, true)
    result.pressed = pressed
    result.clicked = owns_press && params.mouse.left_pressed
    icon_button_release_press(press_owner, &owns_press, params.mouse)
    return result
}

//   Draw icon button using externally supplied visual hover/press intensities.
draw_icon_button_with_visual_state :: proc(
    params: Icon_Button_Params,
    hover_t: f32,
    press_t: f32,
    draw_slot_fill: bool) -> Icon_Button_Result {

    slot_rect := clamp_non_negative_rect(params.rect)
    local_mouse := icon_button_local_mouse(params.mouse, params.scroll_offset)

    hovered := params.interaction_enabled &&
        rl.CheckCollisionPointRec(local_mouse, slot_rect) &&
        rl.CheckCollisionPointRec(local_mouse, params.interaction_space_rect)
    clicked := hovered && params.mouse.left_pressed

    use_hover_t :=  clamp(hover_t, 0.0, 1.0)
    use_press_t :=  clamp(press_t, 0.0, 1.0)
    visual_pressed := use_press_t > 0

    icon_color := UI_TEXT_COLOR
    if (params.toggle || visual_pressed) && draw_slot_fill {
        rl.DrawRectangleRec(slot_rect, UI_BORDER_COLOR)
        icon_color = BACKGROUND_COLOR
    }

    if use_press_t > 0 {
        icon_color = icon_button_darken(icon_color, use_press_t)
    }

    scale := 1.0 + ICON_BUTTON_HOVER_SCALE_ADD * use_hover_t -
        ICON_BUTTON_PRESS_SCALE_SUB * use_press_t
    icon_drawn_rect := icon_button_icon_draw_rect(slot_rect, params.inset_scale * scale)
    if visual_pressed {
        icon_drawn_rect.x += 0.5
        icon_drawn_rect.y += 0.5
    }

    draw_icon_button_glyph(params.icon_id, icon_drawn_rect, icon_color)

    return Icon_Button_Result{
        icon_drawn_rect = icon_drawn_rect,
        hovered = hovered,
        pressed = visual_pressed,
        clicked = clicked,
    }
}
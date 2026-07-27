package ui

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

icon_button_clamp01 :: #force_inline proc(v: f32) -> f32 {
    return max(0.0, min(1.0, v))
}

icon_button_darken :: #force_inline proc(color: rl.Color, amount: f32) -> rl.Color {
    t := icon_button_clamp01(amount)
    factor := 1.0 - (ICON_BUTTON_PRESS_DARKEN * t)
    return rl.Color{
        u8(f32(color.r) * factor),
        u8(f32(color.g) * factor),
        u8(f32(color.b) * factor),
        color.a,
    }
}

//   Clamp a rectangle so width and height are never negative.
icon_button_clamp_rect :: #force_inline proc(rect: rl.Rectangle) -> rl.Rectangle {
    clamped := rect
    if clamped.width < 0 {
        clamped.width = 0
    }
    if clamped.height < 0 {
        clamped.height = 0
    }
    return clamped
}

//   Resolve local mouse position from screen-space plus scroll offset.
icon_button_local_mouse :: #force_inline proc(
    mouse: Mouse_Input_State,
    scroll_offset: rl.Vector2) -> rl.Vector2 {

    return rl.Vector2{mouse.position.x - scroll_offset.x, mouse.position.y - scroll_offset.y}
}

//   Resolve icon draw rectangle centered in slot using min-dimension sizing.
icon_button_icon_draw_rect :: #force_inline proc(
    rect: rl.Rectangle,
    inset_scale: f32) -> rl.Rectangle {

    draw_rect := icon_button_clamp_rect(rect)
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
draw_icon_button_glyph :: proc(icon_id: Icon_Button_Id, rect: rl.Rectangle, color: rl.Color) {
    switch icon_id {
    case .Refresh:
        draw_refresh_icon(rect, color)
    case .Pause:
        draw_pause_icon(rect, color)
    case .Play:
        draw_play_icon(rect, color)
    case .Gear:
        draw_gear_icon(rect, color)
    case .Gif:
        draw_gif_icon(rect, color)
    case .Copy:
        draw_copy_icon(rect, color)
    case .None:
        // Intentional no-op for external/custom icon draw paths.
    }
}

//   Draw and resolve one icon button interaction result.
draw_icon_button :: proc(params: Icon_Button_Params) -> Icon_Button_Result {
    slot_rect := icon_button_clamp_rect(params.rect)
    local_mouse := icon_button_local_mouse(params.mouse, params.scroll_offset)

    hovered := params.interaction_enabled &&
        rl.CheckCollisionPointRec(local_mouse, slot_rect) &&
        rl.CheckCollisionPointRec(local_mouse, params.interaction_space_rect)
    pressed := hovered && params.mouse.left_down

    hover_t: f32 = 0
    if hovered {
        hover_t = 1
    }

    press_t: f32 = 0
    if pressed {
        press_t = 1
    }

    return draw_icon_button_with_visual_state(params, hover_t, press_t, true)
}

//   Draw icon button using externally supplied visual hover/press intensities.
draw_icon_button_with_visual_state :: proc(
    params: Icon_Button_Params,
    hover_t: f32,
    press_t: f32,
    draw_slot_fill: bool) -> Icon_Button_Result {

    slot_rect := icon_button_clamp_rect(params.rect)
    local_mouse := icon_button_local_mouse(params.mouse, params.scroll_offset)

    hovered := params.interaction_enabled &&
        rl.CheckCollisionPointRec(local_mouse, slot_rect) &&
        rl.CheckCollisionPointRec(local_mouse, params.interaction_space_rect)
    pressed := hovered && params.mouse.left_down
    clicked := hovered && params.mouse.left_pressed

    use_hover_t := icon_button_clamp01(hover_t)
    use_press_t := icon_button_clamp01(press_t)

    icon_color := UI_TEXT_COLOR
    if (params.toggle || pressed) && draw_slot_fill {
        rl.DrawRectangleRec(slot_rect, UI_BORDER_COLOR)
        icon_color = BACKGROUND_COLOR
    }

    if use_press_t > 0 {
        icon_color = icon_button_darken(icon_color, use_press_t)
    }

    scale := 1.0 + ICON_BUTTON_HOVER_SCALE_ADD * use_hover_t -
        ICON_BUTTON_PRESS_SCALE_SUB * use_press_t
    icon_drawn_rect := icon_button_icon_draw_rect(slot_rect, params.inset_scale * scale)
    if pressed {
        icon_drawn_rect.x += 0.5
        icon_drawn_rect.y += 0.5
    }

    draw_icon_button_glyph(params.icon_id, icon_drawn_rect, icon_color)

    return Icon_Button_Result{
        icon_drawn_rect = icon_drawn_rect,
        hovered = hovered,
        pressed = pressed,
        clicked = clicked,
    }
}
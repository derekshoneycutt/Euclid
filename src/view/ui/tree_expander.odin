package ui

import rl "vendor:raylib"

TREE_EXPANDER_HOVER_SCALE_ADD :: 0.095
TREE_EXPANDER_PRESS_SCALE_SUB :: 0.16
TREE_EXPANDER_PRESS_DARKEN :: 0.45

Tree_Expander_Params :: struct {
    rect: rl.Rectangle,
    expanded: bool,
    mouse: Mouse_Input_State,
    scroll_offset: rl.Vector2,
    interaction_space_rect: rl.Rectangle,
    interaction_enabled: bool,
    toggle_triggered: bool,
    color: rl.Color,
}

Tree_Expander_Result :: struct {
    hovered: bool,
    pressed: bool,
    clicked: bool,
}

//   Convert screen-space mouse position into local expander coordinates.
tree_expander_local_mouse :: #force_inline proc(
    mouse: Mouse_Input_State,
    scroll_offset: rl.Vector2) -> rl.Vector2 {

    return rl.Vector2{
        mouse.position.x - scroll_offset.x,
        mouse.position.y - scroll_offset.y,
    }
}

//   Darken icon color for pressed-state feedback.
tree_expander_darken :: #force_inline proc(color: rl.Color, amount: f32) -> rl.Color {
    t := clamp(amount, 0.0, 1.0)
    factor := 1.0 - (TREE_EXPANDER_PRESS_DARKEN * t)
    return rl.Color{
        u8(f32(color.r) * factor),
        u8(f32(color.g) * factor),
        u8(f32(color.b) * factor),
        color.a,
    }
}

//   Scale around center for hover/press emphasis while preserving anchor behavior.
tree_expander_scaled_rect :: #force_inline proc(rect: rl.Rectangle, scale: f32) -> rl.Rectangle {
    cx := rect.x + rect.width * 0.5
    cy := rect.y + rect.height * 0.5
    use_scale := max(0.4, scale)
    width := rect.width * use_scale
    height := rect.height * use_scale
    return rl.Rectangle{
        cx - width * 0.5,
        cy - height * 0.5,
        width,
        height,
    }
}

//   Draw one tree expander chevron and report hover/click hit state.
//   Click is gated by caller-provided toggle_triggered to preserve row click semantics.
draw_tree_expander :: proc(params: Tree_Expander_Params) -> Tree_Expander_Result {
    expander_rect := clamp_non_negative_rect(params.rect)

    local_mouse := tree_expander_local_mouse(params.mouse, params.scroll_offset)
    hovered := params.interaction_enabled &&
        rl.CheckCollisionPointRec(local_mouse, expander_rect) &&
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

    scale := 1.0 + TREE_EXPANDER_HOVER_SCALE_ADD * hover_t -
        TREE_EXPANDER_PRESS_SCALE_SUB * press_t
    icon_rect := tree_expander_scaled_rect(expander_rect, scale)

    icon_color := params.color
    if press_t > 0 {
        icon_color = tree_expander_darken(icon_color, press_t)
    }

    draw_tree_disclosure_icon(icon_rect, params.expanded, icon_color)

    return Tree_Expander_Result{
        hovered = hovered,
        pressed = pressed,
        clicked = hovered && params.toggle_triggered,
    }
}
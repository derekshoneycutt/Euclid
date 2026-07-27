package ui

import rl "vendor:raylib"

LIST_ITEM_ACTIVE_PRESS_ALPHA :: 96

List_Item_Params :: struct {
    id: int,
    rect: rl.Rectangle,
    can_expand_pos_y: bool,
    selected: bool,
    mouse: Mouse_Input_State,
    scroll_offset: rl.Vector2,
    interaction_space_rect: rl.Rectangle,
    interaction_enabled: bool,
}

List_Item_Result :: struct {
    drawn_rect: rl.Rectangle,
    inner_rect: rl.Rectangle,
    hovered: bool,
    clicked: bool,
}

//   Clamp a rectangle so width and height are never negative.
list_item_clamp_rect :: #force_inline proc(rect: rl.Rectangle) -> rl.Rectangle {
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
list_item_local_mouse :: #force_inline proc(
    mouse_input: Mouse_Input_State,
    scroll_offset: rl.Vector2) -> rl.Vector2 {

    return rl.Vector2{
        mouse_input.position.x - scroll_offset.x,
        mouse_input.position.y - scroll_offset.y,
    }
}

//   Resolve one list-row interaction and draw visual state.
draw_list_item :: proc(
    params: List_Item_Params,
    press_active: ^bool,
    press_id: ^int) -> List_Item_Result {

    drawn_rect := list_item_clamp_rect(params.rect)
    inner_rect := drawn_rect

    local_mouse := list_item_local_mouse(params.mouse, params.scroll_offset)
    hovered_item := rl.CheckCollisionPointRec(local_mouse, drawn_rect)
    hovered_space := rl.CheckCollisionPointRec(local_mouse, params.interaction_space_rect)
    hovered := hovered_item && hovered_space

    owns_press := press_active^ && press_id^ == params.id
    if params.interaction_enabled && !owns_press && params.mouse.left_pressed && hovered {
        press_active^ = true
        press_id^ = params.id
        owns_press = true
    }

    clicked := false
    if owns_press && params.mouse.left_released {
        clicked = hovered_item
        press_active^ = false
        press_id^ = -1
        owns_press = false
    }

    if owns_press && params.mouse.left_down {
        rl.DrawRectangleRec(drawn_rect, rl.Color{
            UI_BORDER_COLOR.r,
            UI_BORDER_COLOR.g,
            UI_BORDER_COLOR.b,
            LIST_ITEM_ACTIVE_PRESS_ALPHA,
        })
    } else if params.selected {
        rl.DrawRectangleRec(drawn_rect, UI_BORDER_COLOR)
    }

    return List_Item_Result{
        drawn_rect = drawn_rect,
        inner_rect = inner_rect,
        hovered = hovered,
        clicked = clicked,
    }
}
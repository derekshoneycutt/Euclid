package ui

import viewmodel "../model"


import rl "vendor:raylib"

LIST_ITEM_ACTIVE_PRESS_ALPHA :: 96

List_Item_Params :: struct {
    id: int,
    rect: rl.Rectangle,
    can_expand_pos_y: bool,
    selected: bool,
    mouse: Input_Frame,
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

//   Convert screen-space mouse position into local interaction space.
list_item_local_mouse :: #force_inline proc(
    mouse_input: Input_Frame,
    scroll_offset: rl.Vector2) -> rl.Vector2 {

    return rl.Vector2{
        mouse_input.mouse_position.x - scroll_offset.x,
        mouse_input.mouse_position.y - scroll_offset.y,
    }
}

//   Resolve one list-row interaction without issuing drawing commands.
update_list_item :: proc(
    params: List_Item_Params,
    press_owner: ^viewmodel.Ui_Press_Owner_State) -> List_Item_Result {

    drawn_rect := clamp_non_negative_rect(params.rect)
    inner_rect := drawn_rect

    local_mouse := list_item_local_mouse(params.mouse, params.scroll_offset)
    hovered_item := rl.CheckCollisionPointRec(local_mouse, drawn_rect)
    hovered_space := rl.CheckCollisionPointRec(local_mouse, params.interaction_space_rect)
    hovered := hovered_item && hovered_space

    clicked := list_item_run_press(params, press_owner, drawn_rect,
        hovered, hovered_item)
    return {
        drawn_rect = drawn_rect,
        inner_rect = inner_rect,
        hovered = hovered,
        clicked = clicked,
    }
}

//   Draw one list row from prepared hover and shared capture state.
draw_list_item_prepared :: proc(
    params: List_Item_Params,
    result: List_Item_Result,
    press_owner: viewmodel.Ui_Press_Owner_State) {
    if press_owner.active && press_owner.kind == .List_Item &&
        press_owner.id == params.id && input_frame_left_down(params.mouse) {
        rl.DrawRectangleRec(result.drawn_rect, rl.Color{
            UI_BORDER_COLOR.red,
            UI_BORDER_COLOR.green,
            UI_BORDER_COLOR.blue,
            LIST_ITEM_ACTIVE_PRESS_ALPHA,
        })
    } else if params.selected {
        rl.DrawRectangleRec(result.drawn_rect, ui_raylib_color(UI_BORDER_COLOR))
    }
}

//   Run the press acquire/release lifecycle for one list item; returns clicked.
list_item_run_press :: proc(
    params: List_Item_Params,
    press_owner: ^viewmodel.Ui_Press_Owner_State,
    drawn_rect: rl.Rectangle,
    hovered, hovered_item: bool) -> bool {

    owns_press := press_owner^.active &&
        press_owner^.kind == .List_Item &&
        press_owner^.id == params.id
    if params.interaction_enabled && !press_owner^.active &&
        input_frame_left_pressed(params.mouse) && hovered {
        press_owner^.active = true
        press_owner^.kind = .List_Item
        press_owner^.id = params.id
        owns_press = true
    }

    if owns_press && input_frame_left_released(params.mouse) {
        clicked := hovered_item
        press_owner^.active = false
        press_owner^.kind = .None
        press_owner^.id = -1
        return clicked
    }
    return false
}
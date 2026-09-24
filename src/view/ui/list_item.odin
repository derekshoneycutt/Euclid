package ui

import viewmodel "../model"
import geometry "../../core/geometry"

List_Item_Params :: struct {
    id: int,
    rect: geometry.Rectangle,
    can_expand_pos_y: bool,
    selected: bool,
    mouse: Input_Frame,
    scroll_offset: geometry.Vector2,
    interaction_space_rect: geometry.Rectangle,
    interaction_enabled: bool,
}

List_Item_Result :: struct {
    hovered: bool,
    clicked: bool,
}

//   Convert screen-space mouse position into local interaction space.
list_item_local_mouse :: #force_inline proc(
    mouse_input: Input_Frame,
    scroll_offset: geometry.Vector2) -> geometry.Vector2 {

    return geometry.Vector2{
        mouse_input.mouse_position.x - scroll_offset.x,
        mouse_input.mouse_position.y - scroll_offset.y,
    }
}

//   Resolve one list-row interaction without issuing drawing commands.
update_list_item :: proc(
    params: List_Item_Params,
    press_owner: ^viewmodel.Ui_Press_Owner_State) -> List_Item_Result {

    drawn_rect := params.rect
    drawn_rect.width = max(f32(0), drawn_rect.width)
    drawn_rect.height = max(f32(0), drawn_rect.height)
    local_mouse := list_item_local_mouse(params.mouse, params.scroll_offset)
    hovered_item := geometry.rectangle_contains(drawn_rect, local_mouse)
    hovered_space := geometry.rectangle_contains(
        params.interaction_space_rect, local_mouse)
    hovered := hovered_item && hovered_space

    clicked := list_item_run_press(params, press_owner, hovered, hovered_item)
    return {
        hovered = hovered,
        clicked = clicked,
    }
}

//   Run the press acquire/release lifecycle for one list item; returns clicked.
list_item_run_press :: proc(
    params: List_Item_Params,
    press_owner: ^viewmodel.Ui_Press_Owner_State,
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
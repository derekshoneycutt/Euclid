package ui

import geometry "../../core/geometry"

Tree_Expander_Params :: struct {
    rect: geometry.Rectangle,
    mouse: Input_Frame,
    scroll_offset: geometry.Vector2,
    interaction_space_rect: geometry.Rectangle,
    interaction_enabled: bool,
    toggle_triggered: bool,
}

Tree_Expander_Result :: struct {
    hovered: bool,
    pressed: bool,
    clicked: bool,
}

//   Convert screen-space mouse position into local expander coordinates.
tree_expander_local_mouse :: #force_inline proc(
    mouse: Input_Frame,
    scroll_offset: geometry.Vector2) -> geometry.Vector2 {

    return geometry.Vector2{
        mouse.mouse_position.x - scroll_offset.x,
        mouse.mouse_position.y - scroll_offset.y,
    }
}

//   Resolve one tree expander interaction without issuing drawing commands.
//   Click is gated by caller-provided toggle_triggered to preserve row semantics.
update_tree_expander :: proc(params: Tree_Expander_Params) -> Tree_Expander_Result {
    expander_rect := params.rect
    expander_rect.width = max(expander_rect.width, 0)
    expander_rect.height = max(expander_rect.height, 0)

    local_mouse := tree_expander_local_mouse(params.mouse, params.scroll_offset)
    hovered := params.interaction_enabled &&
        geometry.rectangle_contains(expander_rect, local_mouse) &&
        geometry.rectangle_contains(params.interaction_space_rect, local_mouse)
    pressed := hovered && input_frame_left_down(params.mouse)

    return {hovered, pressed, hovered && params.toggle_triggered}
}


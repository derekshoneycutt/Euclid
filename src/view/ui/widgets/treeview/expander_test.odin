#+test
package treeview

import testing "core:testing"

// Verify scrolling and row activation preserve disclosure hover, press, and click.
@(test)
expander_uses_local_geometry_and_row_activation :: proc(t: ^testing.T) {
    params := Tree_Expander_Params{
        rect = {10, 20, 12, 12}, scroll_offset = {0, -10},
        interaction_space_rect = {0, 0, 100, 100}, interaction_enabled = true,
        mouse = {mouse_position = {15, 15}, mouse_down = {.Left}},
    }
    result := update_tree_expander(params)
    testing.expect(t, result.hovered && result.pressed && !result.clicked)
    params.toggle_triggered = true
    result = update_tree_expander(params)
    testing.expect(t, result.hovered && result.pressed && result.clicked)
    params.mouse.mouse_down = {}
    result = update_tree_expander(params)
    testing.expect(t, result.hovered && !result.pressed && result.clicked)
}

// Verify clipped or disabled disclosure controls cannot activate a branch.
@(test)
expander_rejects_clipped_and_disabled_interaction :: proc(t: ^testing.T) {
    params := Tree_Expander_Params{
        rect = {10, 20, 12, 12}, interaction_space_rect = {0, 0, 100, 10},
        interaction_enabled = true, toggle_triggered = true,
        mouse = {mouse_position = {15, 25}, mouse_down = {.Left}},
    }
    result := update_tree_expander(params)
    testing.expect(t, !result.hovered && !result.pressed && !result.clicked)
    params.interaction_space_rect.height = 100
    params.interaction_enabled = false
    result = update_tree_expander(params)
    testing.expect(t, !result.hovered && !result.pressed && !result.clicked)
}

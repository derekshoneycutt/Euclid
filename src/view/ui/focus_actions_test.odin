#+test
package ui

import input "../input"
import testing "core:testing"
import viewmodel "model"
import uisemantics "semantics"
import uilibrary "library"
import bridgemodel "../../bridge/model"
import geometry "../../core/geometry"

// Verify tree activity stays separate from selection while actions follow the tree stop.
@(test)
semantic_favorites_actions_tab_activation_and_escape :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    state^.ui_runtime.semantic_focus = semantic
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_actions_test_fixture(state, &ji, &nodes)
    _ = tree_actions_test_semantic_frame(t, &params)
    selected := state^.ui_runtime.selected_tree_item_id
    toggle := uilibrary.tree_actions_semantic_id(params,
        selected, uilibrary.TREE_ACTION_TOGGLE)
    semantic^.logical_focus = uilibrary.tree_semantic_id()
    tree_actions_test_key(t, &params, .Down)
    testing.expect_value(t, state^.ui_runtime.selected_tree_item_id, selected)
    tree_actions_test_key(t, &params, .Tab)
    testing.expect_value(t, semantic^.logical_focus, toggle)
    tree_actions_test_key(t, &params, .Enter)
    testing.expect(t, state^.ui_runtime.tree_actions_motion.open)
    testing.expect_value(t, semantic^.logical_focus, toggle)
    tree_actions_test_key(t, &params, .Tab)
    testing.expect_value(t, semantic^.logical_focus.local_id, uilibrary.TREE_ACTION_DOWN)
    tree_actions_test_key(t, &params, .Tab, true)
    testing.expect_value(t, semantic^.logical_focus, toggle)
    tree_actions_test_key(t, &params, .Tab)
    tree_actions_test_key(t, &params, .Escape)
    testing.expect(t, !state^.ui_runtime.tree_actions_motion.open)
    testing.expect_value(t, semantic^.logical_focus, toggle)
    tree_actions_test_key(t, &params, .Space)
    testing.expect(t, state^.ui_runtime.tree_actions_motion.open)
}

// Verify interior moves retain action focus and an endpoint returns focus to disclosure.
@(test)
semantic_favorites_actions_move_focus_and_boundary :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    state^.ui_runtime.semantic_focus = semantic
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_actions_test_fixture(state, &ji, &nodes)
    _ = tree_actions_test_semantic_frame(t, &params)
    selected := state^.ui_runtime.selected_tree_item_id
    semantic^.logical_focus = uilibrary.tree_actions_semantic_id(params,
        selected, uilibrary.TREE_ACTION_TOGGLE)
    tree_actions_test_key(t, &params, .Space)
    tree_actions_test_key(t, &params, .Tab)
    down := semantic^.logical_focus
    tree_actions_test_key(t, &params, .Enter)
    testing.expect_value(t, semantic^.logical_focus, down)
    testing.expect_value(t, ji.selected_animation, &nodes[1])
    tree_actions_test_key(t, &params, .Space)
    testing.expect_value(t,
        semantic^.logical_focus.local_id, uilibrary.TREE_ACTION_TOGGLE)
    testing.expect(t, state^.ui_runtime.tree_actions_motion.open)
    tree_actions_test_key(t, &params, .Tab)
    testing.expect_value(t, semantic^.logical_focus.local_id, uilibrary.TREE_ACTION_UP)
    testing.expect_value(t, state^.ui_runtime.selected_tree_item_id, selected)
}

// Verify Escape is not globally claimed and context retirement does not steal new focus.
@(test)
semantic_favorites_actions_context_focus_repair :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    state^.ui_runtime.semantic_focus = semantic
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_actions_test_fixture(state, &ji, &nodes)
    _ = tree_actions_test_semantic_frame(t, &params)
    selected := state^.ui_runtime.selected_tree_item_id
    semantic^.logical_focus = uilibrary.tree_semantic_id()
    events := [1]input.Input_Event{{kind = .Press, key = .Escape}}
    claims := uisemantics.semantic_route_keyboard(semantic, {events = events[:]})
    testing.expect(t, !claims.claimed[0])
    semantic^.logical_focus = uilibrary.tree_actions_semantic_id(params,
        selected, uilibrary.TREE_ACTION_TOGGLE)
    tree_actions_test_key(t, &params, .Enter)
    state^.ui_runtime.library_search.active = true
    _ = tree_actions_test_semantic_frame(t, &params)
    testing.expect_value(t, semantic^.logical_focus, uilibrary.tree_semantic_id())
    state^.ui_runtime.library_search.active = false
    _ = tree_actions_test_semantic_frame(t, &params)
    semantic^.logical_focus = uilibrary.tree_actions_semantic_id(params,
        selected, uilibrary.TREE_ACTION_TOGGLE)
    tree_actions_test_key(t, &params, .Enter)
    semantic^.logical_focus = uilibrary.tree_semantic_id()
    state^.ui_runtime.selected_tree_item_id = nodes[0].stable_id
    _ = tree_actions_test_semantic_frame(t, &params)
    testing.expect_value(t, semantic^.logical_focus, uilibrary.tree_semantic_id())
}

// Verify pointer disclosure owns focus without falling through to tree selection.
@(test)
semantic_favorites_pointer_focus_and_visible_drawer_tail :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    state^.ui_runtime.semantic_focus = semantic
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_actions_test_fixture(state, &ji, &nodes)
    selected := state^.ui_runtime.selected_tree_item_id
    prepared := tree_actions_test_semantic_frame(t, &params)
    row := tree_actions_test_row(&prepared.layout, selected)
    prepared = tree_actions_test_semantic_click(t, &params,
        uilibrary.tree_actions_screen_rect(
            row^.actions.toggle_rect, params.list_panel, 0))
    testing.expect_value(t,
        semantic^.logical_focus.local_id, uilibrary.TREE_ACTION_TOGGLE)
    testing.expect_value(t,
        semantic^.logical_focus.domain, viewmodel.Ui_Node_Domain.Library_Action)
    testing.expect_value(t, semantic^.focus_origin, viewmodel.Ui_Focus_Origin.Pointer)
    row = tree_actions_test_row(&prepared.layout, selected)
    params.list_panel.height = 36
    params.scroll_y^ = row^.actions.move_down_rect.y - 4
    semantic^.logical_focus = uilibrary.tree_semantic_id()
    state^.ui_runtime.tree_actions_reveal_pending = false
    prepared = tree_actions_test_semantic_frame(t, &params)
    row = tree_actions_test_row(&prepared.layout, selected)
    bounds := uilibrary.tree_actions_screen_rect(row^.actions.move_down_rect,
        params.list_panel, prepared.scroll.scroll_y_out)
    testing.expect(t, geometry.rectangles_intersect(bounds, params.list_panel))
    _ = tree_actions_test_semantic_click(t, &params, bounds)
    testing.expect_value(t, state^.ui_runtime.selected_tree_item_id, selected)
    testing.expect_value(t, semantic^.logical_focus.local_id, uilibrary.TREE_ACTION_DOWN)
    testing.expect_value(t, ji.selected_animation, &nodes[1])
    testing.expect_value(t, state^.preferences_runtime.collection_revision, u64(2))
}

// Verify addressed focus reveals an action after resizing without undoing ordinary scrolling.
@(test)
semantic_favorites_actions_reveal_and_scroll_clipping :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    state^.ui_runtime.semantic_focus = semantic
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_actions_test_fixture(state, &ji, &nodes)
    selected := state^.ui_runtime.selected_tree_item_id
    uilibrary.tree_actions_toggle(params, selected)
    _ = tree_actions_test_semantic_frame(t, &params)
    down := uilibrary.tree_actions_semantic_id(
        params, selected, uilibrary.TREE_ACTION_DOWN)
    testing.expect(t,
        uisemantics.semantic_apply_external_action(semantic, down, .Focus))
    params.list_panel.height = 36
    prepared := tree_actions_test_semantic_frame(t, &params)
    row := tree_actions_test_row(&prepared.layout, selected)
    bounds := uilibrary.tree_actions_screen_rect(row^.actions.move_down_rect,
        params.list_panel, prepared.scroll.scroll_y_out)
    testing.expect(t, bounds.y >= params.list_panel.y)
    testing.expect(t,
        bounds.y + bounds.height <= params.list_panel.y + params.list_panel.height)
    params.scroll_y^ = 0
    _ = tree_actions_test_semantic_frame(t, &params)
    testing.expect_value(t, params.scroll_y^, f32(0))
    testing.expect(t, state^.ui_runtime.tree_actions_motion.open)
    snapshot := uisemantics.semantic_snapshot(semantic)
    node := snapshot^.nodes[uisemantics.semantic_node_index(snapshot, down)]
    testing.expect(t, .Tab_Stop not_in node.states && .Enabled not_in node.states)
    testing.expect(t,
        !uisemantics.semantic_apply_external_action(semantic, down, .Activate))
}

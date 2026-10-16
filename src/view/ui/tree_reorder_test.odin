#+test
package ui

import bridgemodel "../../bridge/model"
import collections "../../collections"
import testing "core:testing"
import uilibrary "library"
import uiaccordion "layout/accordion"
import viewmodel "model"
import uisemantics "semantics"
import theme "theme"
import log "core:log"
import mem "core:mem"

// tree_reorder_test_open enables position motion only after the drawer reaches its full extent.
tree_reorder_test_open :: proc(
    t: ^testing.T,
    params: ^uilibrary.Tree_List_Params) -> uilibrary.Tree_List_Preparation {
    prepared := tree_actions_test_open_drawer(t, params)
    params^.ui_runtime^.platform_reduce_motion = false
    params^.reduce_motion = false
    return prepared
}

// tree_reorder_test_move exercises the common owner and updates the caller's projection revision.
tree_reorder_test_move :: proc(
    t: ^testing.T, params: ^uilibrary.Tree_List_Params,
    direction: collections.Move_Direction) -> uilibrary.Tree_Prepared_Layout {
    testing.expect(t, uilibrary.tree_actions_move(params^,
        params^.ui_runtime^.library.tree.selected_item_id, direction))
    params^.collections_revision =
        params^.general_state^.preferences_runtime.collection_revision
    layout: uilibrary.Tree_Prepared_Layout
    uilibrary.tree_prepare_layout(params^, &layout)
    return layout
}

// tree_reorder_test_expect_positions compares sampled positions across a retarget boundary.
tree_reorder_test_expect_positions :: proc(
    t: ^testing.T, before: viewmodel.Ui_Tree_Reorder_Motion,
    after: ^uilibrary.Tree_Prepared_Layout) {
    for index in 0..<before.count {
        row := before.rows[index]
        other := tree_actions_test_row(after, row.id)
        testing.expect(t, other != nil)
        if other != nil {
            testing.expect_value(t, other^.content_y, row.from_y)
        }
    }
}

// Verify immediate logical order, unequal-distance midpoint motion, and exact final geometry.
@(test)
tree_reorder_samples_attached_drawer_and_commits_immediately :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_actions_test_fixture(state, &ji, &nodes)
    initial := tree_reorder_test_open(t, &params)
    owner := state^.ui_runtime.library.tree.selected_item_id
    before := tree_actions_test_row(&initial.layout, owner)^
    sampled: viewmodel.Ui_Tree_Reorder_Motion
    uilibrary.tree_reorder_capture(params, &sampled)
    start := tree_reorder_test_move(t, &params, .Down)
    tree_actions_test_expect_order(t, params.collections)
    testing.expect_value(t, ji.selected_animation, &nodes[1])
    tree_reorder_test_expect_positions(t, sampled, &start)
    params.mouse_input.sample_time_seconds +=
        uiaccordion.INTERFACE_TRANSITION_SECONDS * 0.5
    middle: uilibrary.Tree_Prepared_Layout
    uilibrary.tree_prepare_layout(params, &middle)
    row := tree_actions_test_row(&middle, owner)
    testing.expect(t,
        row^.content_y > before.content_y && row^.content_y < row^.canonical_y)
    testing.expect_value(t,
        row^.actions.drawer_rect.y - row^.content_y, theme.TREE_ROW_HEIGHT)
    testing.expect_value(t, row^.actions.move_up_rect.y - row^.actions.drawer_rect.y,
        uilibrary.TREE_ACTION_DRAWER_PADDING)
    testing.expect_value(t, middle.content_height, initial.layout.content_height)
    params.mouse_input.sample_time_seconds += uiaccordion.INTERFACE_TRANSITION_SECONDS
    final: uilibrary.Tree_Prepared_Layout
    uilibrary.tree_prepare_layout(params, &final)
    testing.expect(t, !state^.ui_runtime.library.actions.reorder.active)
    for settled in final.rows[:final.count] {
        testing.expect_value(t, settled.content_y, settled.canonical_y)
    }
}

// Verify repeated moves include earlier displaced neighbors and reversals never snap.
@(test)
tree_reorder_retargets_three_placements_and_reverses :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_actions_test_fixture(state, &ji, &nodes)
    _ = tree_reorder_test_open(t, &params)
    _ = tree_reorder_test_move(t, &params, .Down)
    params.mouse_input.sample_time_seconds += 0.04
    before: viewmodel.Ui_Tree_Reorder_Motion
    uilibrary.tree_reorder_capture(params, &before)
    second := tree_reorder_test_move(t, &params, .Down)
    tree_reorder_test_expect_positions(t, before, &second)
    testing.expect_value(t, state^.ui_runtime.library.actions.reorder.count, 3)
    uilibrary.tree_reorder_capture(params, &before)
    reverse := tree_reorder_test_move(t, &params, .Up)
    tree_reorder_test_expect_positions(t, before, &reverse)
    tree_actions_test_expect_order(t, params.collections)
    params.mouse_input.sample_time_seconds += 0.03
    uilibrary.tree_reorder_capture(params, &before)
    reverse = tree_reorder_test_move(t, &params, .Up)
    tree_reorder_test_expect_positions(t, before, &reverse)
}

// Verify endpoint rejection leaves a running exchange untouched and reduced motion snaps it.
@(test)
tree_reorder_rejection_and_reduce_motion_preserve_model :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_actions_test_fixture(state, &ji, &nodes)
    _ = tree_reorder_test_open(t, &params)
    _ = tree_reorder_test_move(t, &params, .Down)
    _ = tree_reorder_test_move(t, &params, .Down)
    before := state^.ui_runtime.library.actions.reorder
    prior_logger := context.logger
    context.logger = log.nil_logger()
    testing.expect(t, !uilibrary.tree_actions_move(params,
        state^.ui_runtime.library.tree.selected_item_id, .Down))
    context.logger = prior_logger
    testing.expect_value(t, state^.ui_runtime.library.actions.reorder, before)
    state^.ui_runtime.platform_reduce_motion = true
    params.reduce_motion = true
    layout: uilibrary.Tree_Prepared_Layout
    uilibrary.tree_prepare_layout(params, &layout)
    testing.expect(t, !state^.ui_runtime.library.actions.reorder.active)
    for row in layout.rows[:layout.count] {
        testing.expect_value(t, row.content_y, row.canonical_y)
    }
    _ = tree_reorder_test_move(t, &params, .Up)
    testing.expect(t, !state^.ui_runtime.library.actions.reorder.active)
}

// Verify interruption boundaries discard only visual offsets, not committed order.
@(test)
tree_reorder_context_changes_settle_without_undo :: proc(t: ^testing.T) {
    for boundary in 0..<8 {
        state := make_shell_test_state(t)
        ji: bridgemodel.Euclid_Julia_Interface
        nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
        params := tree_actions_test_fixture(state, &ji, &nodes)
        prepared: uilibrary.Tree_List_Preparation
        _ = tree_reorder_test_open(t, &params)
        _ = tree_reorder_test_move(t, &params, .Down)
        switch boundary {
        case 0:
            uilibrary.tree_actions_toggle(
                params, state^.ui_runtime.library.tree.selected_item_id)
        case 1:
            state^.ui_runtime.library.tree.selected_item_id =
                params.collections^.entries[0].id
        case 2:
            state^.ui_runtime.layout.active_accordion_section = .Settings
        case 3:
            state^.ui_runtime.library.search.active = true
        case 4:
            ji.content_generation += 1
        case 5:
            params.list_panel.width += 10
        case 6:
            parent := uilibrary.tree_projection_find(
                &state^.ui_runtime.library.tree.projection,
                collections.FAVORITES_COLLECTION_ID)
            state^.ui_runtime.library.tree.projection.items[parent].expanded = false
        case 7: params.collections_revision += 1
        }
        uilibrary.prepare_tree_list_panel(params, &prepared)
        testing.expect(t, !state^.ui_runtime.library.actions.reorder.active)
        tree_actions_test_expect_order(t, params.collections)
        destroy_shell_test_state(state)
    }
}

// Verify a passing neighbor cannot steal pointer focus beneath the selected drawer.
@(test)
tree_reorder_foreground_owns_overlapping_pointer :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_actions_test_fixture(state, &ji, &nodes)
    _ = tree_reorder_test_open(t, &params)
    layout := tree_reorder_test_move(t, &params, .Down)
    owner := state^.ui_runtime.library.tree.selected_item_id
    row := tree_actions_test_row(&layout, owner)
    block := uilibrary.tree_reorder_block_clip(row^, params.list_panel, 0)
    params.mouse_input.mouse_position = {block.x + 1, block.y + block.height * 0.5}
    params.mouse_input.mouse_pressed = {.Left}
    params.mouse_input.mouse_down = {.Left}
    prepared: uilibrary.Tree_List_Preparation
    uilibrary.prepare_tree_list_panel(params, &prepared)
    testing.expect_value(t, state^.ui_runtime.library.tree.selected_item_id, owner)
    testing.expect(t,
        prepared.hovered_node == nil || prepared.hovered_node^.key == owner)
    testing.expect(t, !state^.ui_runtime.input.press_owner.active)
}

// Verify keyboard moves retain focus and publish sampled bounds with committed sibling order.
@(test)
tree_reorder_keyboard_uses_sampled_semantic_geometry :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    state^.ui_runtime.semantic_focus = semantic
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_actions_test_fixture(state, &ji, &nodes)
    _ = tree_reorder_test_open(t, &params)
    _ = tree_actions_test_semantic_frame(t, &params)
    owner := state^.ui_runtime.library.tree.selected_item_id
    semantic^.logical_focus = uilibrary.tree_actions_semantic_id(
        params, owner, uilibrary.TREE_ACTION_DOWN)
    tree_actions_test_key(t, &params, .Enter)
    testing.expect(t, state^.ui_runtime.library.actions.reorder.active)
    params.mouse_input.sample_time_seconds += 0.05
    prepared := tree_actions_test_semantic_frame(t, &params)
    row := tree_actions_test_row(&prepared.layout, owner)
    snapshot := uisemantics.semantic_snapshot(semantic)
    index := uisemantics.semantic_node_index(snapshot, semantic^.logical_focus)
    testing.expect(t, index >= 0)
    testing.expect_value(t, snapshot^.nodes[index].bounds,
        uilibrary.tree_actions_screen_rect(
            row^.actions.move_down_rect, params.list_panel,
            prepared.scroll.scroll_y_out))
    testing.expect_value(t,
        semantic^.logical_focus.local_id, uilibrary.TREE_ACTION_DOWN)
    tree_actions_test_expect_order(t, params.collections)
}

// Verify ordinary scrolling clips shared moving geometry without canceling or allocating.
@(test)
tree_reorder_sampling_does_not_allocate_or_override_scrolling :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_actions_test_fixture(state, &ji, &nodes)
    _ = tree_reorder_test_open(t, &params)
    _ = tree_reorder_test_move(t, &params, .Down)
    tracker: mem.Tracking_Allocator
    mem.tracking_allocator_init(&tracker, context.allocator, context.allocator)
    defer mem.tracking_allocator_destroy(&tracker)
    prior_allocator := context.allocator
    context.allocator = mem.tracking_allocator(&tracker)
    layout: uilibrary.Tree_Prepared_Layout
    for frame in 0..<16 {
        params.mouse_input.sample_time_seconds += 0.005
        params.scroll_y^ = f32(frame)
        uilibrary.tree_prepare_layout(params, &layout)
    }
    context.allocator = prior_allocator
    testing.expect_value(t, tracker.total_allocation_count, i64(0))
    testing.expect_value(t, params.scroll_y^, f32(15))
    testing.expect(t, state^.ui_runtime.library.actions.reorder.active)
}

// Verify native requests queued in the same frame each observe the preceding accepted move.
@(test)
tree_reorder_multiple_native_commands_keep_continuity :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    state^.ui_runtime.semantic_focus = semantic
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_actions_test_fixture(state, &ji, &nodes)
    _ = tree_reorder_test_open(t, &params)
    before: viewmodel.Ui_Tree_Reorder_Motion
    uilibrary.tree_reorder_capture(params, &before)
    target := uilibrary.tree_actions_semantic_id(params,
        state^.ui_runtime.library.tree.selected_item_id, uilibrary.TREE_ACTION_DOWN)
    semantic^.commands[0] = {target = target, kind = .Activate}
    semantic^.commands[1] = {target = target, kind = .Activate}
    semantic^.command_count = 2
    uilibrary.tree_actions_apply_commands(params)
    params.collections_revision = state^.preferences_runtime.collection_revision
    layout: uilibrary.Tree_Prepared_Layout
    uilibrary.tree_prepare_layout(params, &layout)
    tree_reorder_test_expect_positions(t, before, &layout)
    testing.expect(t, !uilibrary.tree_actions_neighbor_exists(
        params.collections, target.stable_id, .Down))
    testing.expect(t, state^.ui_runtime.library.actions.reorder.active)
}

// Verify pointer releases start motion through the same durable owner while controls travel.
@(test)
tree_reorder_pointer_moves_follow_animated_controls :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_actions_test_fixture(state, &ji, &nodes)
    prepared := tree_reorder_test_open(t, &params)
    prepared = tree_actions_test_click_move(&params, &prepared, .Down)
    testing.expect(t, state^.ui_runtime.library.actions.reorder.active)
    tree_actions_test_expect_order(t, params.collections)
    params.mouse_input.sample_time_seconds += 0.04
    uilibrary.prepare_tree_list_panel(params, &prepared)
    prepared = tree_actions_test_click_move(&params, &prepared, .Down)
    testing.expect(t, state^.ui_runtime.library.actions.reorder.active)
    testing.expect(t, !uilibrary.tree_actions_neighbor_exists(
        params.collections, state^.ui_runtime.library.tree.selected_item_id, .Down))
    testing.expect_value(t, ji.selected_animation, &nodes[1])
}

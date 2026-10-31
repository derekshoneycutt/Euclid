#+test
package ui

import collections "../../collections"
import bridgemodel "../../bridge/model"
import testing "core:testing"
import uilibrary "library"
import viewmodel "model"
import uisemantics "semantics"
import userdata "../../persistence/userdata"
import geometry "../../core/geometry"
import viewpreferences "../preferences"
import uuid "core:encoding/uuid"
import math "core:math"

// Every input origin shares an exact quiet-interval boundary and resets it on repeat attempts.
@(test)
tree_collection_delete_requires_deliberate_confirmation :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_collections_fixture(t, state, &ji, &nodes)
    _ = tree_actions_test_semantic_frame(t, &params)
    testing.expect(t, uilibrary.tree_collection_create(params))
    id := state.ui_runtime.library.tree.selected_item_id
    projection := &state.ui_runtime.library.tree.projection
    builds := projection.build_count
    testing.expect(t, uilibrary.tree_collection_delete(params, id))
    testing.expect_value(t, params.collections.collection_count, 2)
    params.mouse_input.sample_time_seconds += uilibrary.TREE_DELETE_GUARD_SECONDS
    testing.expect(t, uilibrary.tree_collection_delete(params, id))
    testing.expect_value(t, params.collections.collection_count, 2)
    params.mouse_input.sample_time_seconds += 0.501
    testing.expect(t, uilibrary.tree_collection_delete(params, id, true))
    testing.expect_value(t, params.collections.collection_count, 2)
    params.mouse_input.sample_time_seconds += 0.5
    testing.expect(t, uilibrary.tree_collection_delete(params, id))
    testing.expect_value(t, params.collections.collection_count, 2)
    params.mouse_input.sample_time_seconds += 0.501
    testing.expect(t, uilibrary.tree_collection_delete(params, id))
    testing.expect_value(t, params.collections.collection_count, 1)
    testing.expect_value(t, projection.build_count, builds)
    testing.expect_value(t, state.ui_runtime.library.tree.selected_item_id,
        viewmodel.TREE_COLLECTIONS_ROOT_ID)
    testing.expect(t, !state.ui_runtime.library.actions.delete_confirmation.armed)
    testing.expect(t, !state.ui_runtime.library.entry_name.active)
    testing.expect_value(t, ji.selected_animation, &nodes[1])
}

// The armed row uses one prepared translation for rendering, hit testing, editor and semantics.
@(test)
tree_collection_delete_warning_motion_and_context_are_session_only :: proc(
    t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_collections_fixture(t, state, &ji, &nodes)
    _ = tree_actions_test_semantic_frame(t, &params)
    testing.expect(t, uilibrary.tree_collection_create(params))
    id := state.ui_runtime.library.tree.selected_item_id
    ordinary := tree_actions_test_semantic_frame(t, &params)
    before := tree_actions_test_row(&ordinary.layout, id)^
    testing.expect(t, uilibrary.tree_collection_delete(params, id))
    params.reduce_motion = false
    params.mouse_input.sample_time_seconds += 0.025
    armed := tree_actions_test_semantic_frame(t, &params)
    row := tree_actions_test_row(&armed.layout, id)^
    testing.expect(t, row.offset_x != 0)
    testing.expect(t, math.abs(row.actions.delete_rect.x -
        before.actions.delete_rect.x - row.offset_x) < 0.00001)
    tree_collection_expect_delete_geometry(t, params, row)
    params.reduce_motion = true
    still := tree_actions_test_semantic_frame(t, &params)
    testing.expect_value(t, tree_actions_test_row(&still.layout, id).offset_x, f32(0))
    testing.expect(t, state.ui_runtime.library.actions.delete_confirmation.armed)
    ji.content_generation += 1
    _ = tree_actions_test_semantic_frame(t, &params)
    testing.expect(t, !state.ui_runtime.library.actions.delete_confirmation.armed)
}

// Match published action bounds against the exact shared prepared delete rectangle.
tree_collection_expect_delete_geometry :: proc(
    t: ^testing.T, params: uilibrary.Tree_List_Params,
    row: viewmodel.Ui_Tree_Prepared_Row) {
    snapshot := uisemantics.semantic_snapshot(params.ui_runtime.semantic_focus)
    target := uilibrary.tree_actions_semantic_id(
        params, row.item.key, uilibrary.TREE_COLLECTION_DELETE)
    index := uisemantics.semantic_node_index(snapshot, target)
    testing.expect(t, index >= 0)
    if index < 0 {
        return
    }
    expected := uilibrary.tree_actions_screen_rect(
        row.actions.delete_rect, params.list_panel, params.scroll_y^)
    testing.expect_value(t, snapshot.nodes[index].bounds, geometry.Rectangle(expected))
}

// Queue rejection preserves the armed owner and dirty editor, then retry flushes before delete.
@(test)
tree_collection_delete_rejection_preserves_editor_and_retry_order :: proc(
    t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_collections_fixture(t, state, &ji, &nodes)
    _ = tree_actions_test_semantic_frame(t, &params)
    testing.expect(t, uilibrary.tree_collection_create(params))
    id := state.ui_runtime.library.tree.selected_item_id
    testing.expect(t, uilibrary.library_entry_name_edit(state, id, "Before deletion"))
    testing.expect(t, uilibrary.tree_collection_delete(params, id))
    store: userdata.Store
    state.preferences_runtime.settings_store = &store
    defer state.preferences_runtime.settings_store = nil
    state.preferences_runtime.collection_mutation_count = collections.MUTATION_CAPACITY
    params.mouse_input.sample_time_seconds += 1
    testing.expect(t, !uilibrary.tree_collection_delete(params, id))
    testing.expect(t, state.ui_runtime.library.actions.delete_confirmation.armed)
    testing.expect(t, state.ui_runtime.library.entry_name.dirty)
    state.preferences_runtime.collection_mutation_count = 0
    params.mouse_input.sample_time_seconds += 1
    testing.expect(t, uilibrary.tree_collection_delete(params, id))
    testing.expect_value(t, state.preferences_runtime.collection_mutation_count, 2)
    testing.expect_value(t, state.preferences_runtime.collection_mutations[0].kind,
        collections.Mutation_Kind.Set_Collection_Name)
    testing.expect_value(t, state.preferences_runtime.collection_mutations[1].kind,
        collections.Mutation_Kind.Delete_Collection)
}

// Pointer arm, native repeat and keyboard confirmation use the same timing and identity guard.
@(test)
tree_collection_delete_input_origins_share_guard :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_collections_fixture(t, state, &ji, &nodes)
    _ = tree_actions_test_semantic_frame(t, &params)
    testing.expect(t, uilibrary.tree_collection_create(params))
    id := state.ui_runtime.library.tree.selected_item_id
    frame := tree_actions_test_semantic_frame(t, &params)
    row := tree_actions_test_row(&frame.layout, id)^
    _ = tree_actions_test_semantic_click(t, &params,
        uilibrary.tree_actions_screen_rect(row.actions.delete_rect,
            params.list_panel, params.scroll_y^))
    testing.expect(t, state.ui_runtime.library.actions.delete_confirmation.armed)
    target := uilibrary.tree_actions_semantic_id(
        params, id, uilibrary.TREE_COLLECTION_DELETE)
    params.mouse_input.sample_time_seconds += uilibrary.TREE_DELETE_GUARD_SECONDS
    testing.expect(t, uisemantics.semantic_apply_external_action(
        &state.semantic_focus, target, .Activate))
    _ = tree_actions_test_semantic_frame(t, &params)
    testing.expect_value(t, params.collections.collection_count, 2)
    params.mouse_input.sample_time_seconds += uilibrary.TREE_DELETE_GUARD_SECONDS
    tree_actions_test_key(t, &params, .Enter)
    testing.expect_value(t, params.collections.collection_count, 2)
    params.mouse_input.sample_time_seconds += 0.501
    tree_actions_test_key(t, &params, .Space)
    testing.expect_value(t, params.collections.collection_count, 1)
    uilibrary.tree_actions_apply_command(params, {
        target = target,
        kind = .Activate,
    })
    testing.expect_value(t, params.collections.collection_count, 1)
}

// Closing/reopening or selecting another owner discards armed intent without changing UUIDs.
@(test)
tree_collection_delete_disarms_on_close_and_selection :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_collections_fixture(t, state, &ji, &nodes)
    _ = tree_actions_test_semantic_frame(t, &params)
    testing.expect(t, uilibrary.tree_collection_create(params))
    id := state.ui_runtime.library.tree.selected_item_id
    testing.expect(t, uilibrary.tree_collection_delete(params, id))
    testing.expect(t, uilibrary.tree_actions_close_context(&state.ui_runtime, state))
    testing.expect(t, !state.ui_runtime.library.actions.delete_confirmation.armed)
    uilibrary.tree_actions_toggle(params, id)
    params.mouse_input.sample_time_seconds += 1
    testing.expect(t, uilibrary.tree_collection_delete(params, id))
    testing.expect_value(t, params.collections.collection_count, 2)
    state.ui_runtime.library.tree.selected_item_id = viewmodel.TREE_COLLECTIONS_ROOT_ID
    _ = tree_actions_test_semantic_frame(t, &params)
    testing.expect(t, !state.ui_runtime.library.actions.delete_confirmation.armed)
    state.ui_runtime.library.tree.selected_item_id = id
    uilibrary.tree_actions_toggle(params, id)
    testing.expect(t, uilibrary.tree_collection_delete(params, id))
    index := collections.find_collection(params.collections, id)
    params.collections.collections[index].is_read_only = true
    _ = tree_actions_test_semantic_frame(t, &params)
    testing.expect(t, !state.ui_runtime.library.actions.delete_confirmation.armed)
    snapshot := uisemantics.semantic_snapshot(&state.semantic_focus)
    control := uisemantics.semantic_node_index(snapshot,
        uilibrary.tree_actions_semantic_id(params, id, uilibrary.TREE_COLLECTION_DELETE))
    testing.expect(t, control >= 0 && .Enabled not_in snapshot.nodes[control].states)
}

// Retiring a head preserves survivor addresses and repairs next, previous and permanent root.
@(test)
tree_collection_delete_repairs_neighbors_without_rebuild :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_collections_fixture(t, state, &ji, &nodes)
    _ = tree_actions_test_semantic_frame(t, &params)
    ids: [3]uuid.Identifier
    projection := &state.ui_runtime.library.tree.projection
    for &id in ids {
        state.ui_runtime.library.tree.selected_item_id =
            viewmodel.TREE_COLLECTIONS_ROOT_ID
        _ = tree_actions_test_semantic_frame(t, &params)
        testing.expect(t, uilibrary.tree_collection_create(params))
        id = state.ui_runtime.library.tree.selected_item_id
    }

    survivor := projection.items[uilibrary.tree_projection_find(projection, ids[1])]
    builds := projection.build_count
    for removed, index in ([]uuid.Identifier{ids[0], ids[2], ids[1]}) {
        state.ui_runtime.library.tree.selected_item_id = removed
        mutation, _ := collections.make_collection_delete_mutation(
            params.collections, removed)
        testing.expect_value(t, viewpreferences.settings_save_collection_mutation(
            state, mutation), collections.Mutation_Error.None)
        expected := ids[1] if index < 2 else viewmodel.TREE_COLLECTIONS_ROOT_ID
        testing.expect_value(t, state.ui_runtime.library.tree.selected_item_id, expected)
        if index < 2 {
            testing.expect_value(t, projection.items[uilibrary.tree_projection_find(
                projection, ids[1])], survivor)
        }
    }
    testing.expect_value(t, projection.build_count, builds)
    testing.expect_value(t, ji.selected_animation, &nodes[1])
}

// SDL multi-click metadata survives press/release separation beyond the quiet interval.
@(test)
tree_collection_delete_pointer_multiclick_cannot_confirm :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_collections_fixture(t, state, &ji, &nodes)
    _ = tree_actions_test_semantic_frame(t, &params)
    testing.expect(t, uilibrary.tree_collection_create(params))
    id := state.ui_runtime.library.tree.selected_item_id
    testing.expect(t, uilibrary.tree_collection_delete(params, id))
    params.mouse_input.sample_time_seconds += 1
    frame := tree_actions_test_semantic_frame(t, &params)
    row := tree_actions_test_row(&frame.layout, id)^
    bounds := uilibrary.tree_actions_screen_rect(
        row.actions.delete_rect, params.list_panel, params.scroll_y^)
    params.mouse_input.mouse_position = {bounds.x + 10, bounds.y + 10}
    params.mouse_input.mouse_pressed = {.Left}
    params.mouse_input.mouse_down = {.Left}
    params.mouse_input.mouse_left_clicks = 2
    _ = tree_actions_test_semantic_frame(t, &params)
    params.mouse_input.sample_time_seconds += 1
    params.mouse_input.mouse_pressed, params.mouse_input.mouse_down = {}, {}
    params.mouse_input.mouse_released = {.Left}
    params.mouse_input.mouse_left_clicks = 0
    _ = tree_actions_test_semantic_frame(t, &params)
    testing.expect_value(t, params.collections.collection_count, 2)
    params.mouse_input.sample_time_seconds += 1
    _ = tree_actions_test_semantic_click(t, &params, bounds)
    testing.expect_value(t, params.collections.collection_count, 1)
}

// Leaf-first retirement clears descendant borrowers without replacing Favorites.
@(test)
tree_collection_delete_subtree_retires_all_borrowers :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    state.ui_runtime.semantic_focus = &state.semantic_focus
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_actions_test_fixture(state, &ji, &nodes)
    _ = tree_actions_test_semantic_frame(t, &params)
    projection := &state.ui_runtime.library.tree.projection
    state.ui_runtime.library.tree.selected_item_id = viewmodel.TREE_COLLECTIONS_ROOT_ID
    testing.expect(t, uilibrary.tree_collection_create(params))
    id := state.ui_runtime.library.tree.selected_item_id
    head := uilibrary.tree_projection_find(projection, id)
    descendant: uuid.Identifier
    descendant[0] = 211
    child := uilibrary.tree_projection_add(projection, projection, {
        key = descendant,
        kind = .Placement,
        parent = head,
        selectable = true,
    })
    testing.expect(t, child >= 0)
    favorite := projection.items[uilibrary.tree_projection_find(
        projection, collections.FAVORITES_COLLECTION_ID)]
    state.ui_runtime.library.tree.selected_item_id = descendant
    state.semantic_focus.logical_focus = {
        domain = .Library_Action,
        stable_id = descendant,
        local_id = 5,
    }
    state.semantic_focus.active_tree_item = descendant
    state.ui_runtime.library.entry_name.entry_id = descendant
    state.ui_runtime.library.entry_name.active = true
    testing.expect(t, viewmodel.ui_tree_projection_delete_collection(
        &state.ui_runtime, id))
    testing.expect_value(t, uilibrary.tree_projection_find(projection, descendant), -1)
    testing.expect_value(t, state.ui_runtime.library.tree.selected_item_id, favorite.key)
    testing.expect_value(t, state.semantic_focus.active_tree_item, favorite.key)
    testing.expect_value(t, state.ui_runtime.library.tree.reveal_stable_id, favorite.key)
    testing.expect_value(t, projection.items[uilibrary.tree_projection_find(
        projection, favorite.key)], favorite)
    testing.expect(t, !state.ui_runtime.library.entry_name.active)
}

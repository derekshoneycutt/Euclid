#+test
package ui

import collections "../../collections"
import bridgemodel "../../bridge/model"
import testing "core:testing"
import uilibrary "library"
import viewmodel "model"
import userdata "../../persistence/userdata"
import uuid "core:encoding/uuid"

// Head naming shares debounce/flush while empty input preserves accepted text and draft.
@(test)
tree_collection_name_editor_debounce_and_rejection :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_collections_fixture(t, state, &ji, &nodes)
    _ = tree_actions_test_semantic_frame(t, &params)
    testing.expect(t, uilibrary.tree_collection_create(params))
    id := state^.ui_runtime.library.tree.selected_item_id
    testing.expect(t, uilibrary.library_entry_name_edit(state, id, "  Teaching  "))
    uilibrary.library_entry_name_service(state, 0.2)
    testing.expect_value(t,
        string(params.collections^.collections[1].name), "New Collection")
    uilibrary.library_entry_name_service(state, 0.2)
    testing.expect_value(t, string(params.collections^.collections[1].name), "Teaching")
    testing.expect(t, uilibrary.library_entry_name_edit(state, id, " \t "))
    testing.expect(t, !uilibrary.library_entry_name_flush(state))
    testing.expect(t, state^.ui_runtime.library.entry_name.admission_failed)
    testing.expect_value(t, string(params.collections^.collections[1].name), "Teaching")
    testing.expect(t, uilibrary.library_entry_name_edit(state, id, "Revised"))
    testing.expect(t, uilibrary.tree_actions_close_context(&state^.ui_runtime, state))
    testing.expect_value(t, string(params.collections^.collections[1].name), "Revised")
    testing.expect(t, !state^.ui_runtime.library.entry_name.active)
}

// Head moves preserve stable nodes and build counts through reversal and narrow layouts.
@(test)
tree_collection_move_is_local_and_retargets_motion :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_collections_fixture(t, state, &ji, &nodes)
    _ = tree_actions_test_semantic_frame(t, &params)
    testing.expect(t, uilibrary.tree_collection_create(params))
    projection := &state^.ui_runtime.library.tree.projection
    root := projection^.items[uilibrary.tree_projection_find(
        projection, viewmodel.TREE_COLLECTIONS_ROOT_ID)]
    uilibrary.tree_select_item(params, root)
    _ = tree_actions_test_semantic_frame(t, &params)
    testing.expect(t, uilibrary.tree_collection_create(params))
    id := state^.ui_runtime.library.tree.selected_item_id
    node := projection^.items[uilibrary.tree_projection_find(projection, id)]
    builds := projection^.build_count
    _ = tree_actions_test_semantic_frame(t, &params)
    params.reduce_motion = false
    testing.expect(t, uilibrary.tree_actions_move(params, id, .Up))
    testing.expect(t, state^.ui_runtime.library.actions.reorder.active)
    tree_collection_expect_continuous_reversal(t, &params, id)
    testing.expect_value(t, projection^.build_count, builds)
    testing.expect_value(t, projection^.items[uilibrary.tree_projection_find(
        projection, id)], node)
    testing.expect_value(t, params.collections^.collections[2].order, i64(2))
    testing.expect_value(t, ji.selected_animation, &nodes[1])
}

// Reversal starts at the sampled on-screen position rather than jumping to canonical order.
tree_collection_expect_continuous_reversal :: proc(
    t: ^testing.T, params: ^uilibrary.Tree_List_Params,
    id: uuid.Identifier) {
    params^.mouse_input.sample_time_seconds += 0.05
    prepared := tree_actions_test_semantic_frame(t, params)
    row := tree_actions_test_row(&prepared.layout, id)
    testing.expect(t, row != nil)
    y := row^.content_y
    testing.expect(t, uilibrary.tree_actions_move(params^, id, .Down))
    prepared = tree_actions_test_semantic_frame(t, params)
    row = tree_actions_test_row(&prepared.layout, id)
    testing.expect(t, row != nil)
    testing.expect_value(t, row^.content_y, y)
}

// Queue rejection leaves accepted head text, order and retained editor unchanged.
@(test)
tree_collection_rename_rejection_retains_dirty_draft :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_collections_fixture(t, state, &ji, &nodes)
    _ = tree_actions_test_semantic_frame(t, &params)
    testing.expect(t, uilibrary.tree_collection_create(params))
    id := state^.ui_runtime.library.tree.selected_item_id
    store: userdata.Store
    state^.preferences_runtime.settings_store = &store
    defer state^.preferences_runtime.settings_store = nil
    state^.preferences_runtime.collection_mutation_count = collections.MUTATION_CAPACITY
    testing.expect(t, uilibrary.library_entry_name_edit(state, id, "Rejected"))
    testing.expect(t, !uilibrary.library_entry_name_flush(state))
    testing.expect_value(t,
        string(params.collections^.collections[1].name), "New Collection")
    testing.expect_value(t,
        state^.ui_runtime.library.entry_name.value_length, len("Rejected"))
    testing.expect(t, state^.ui_runtime.library.entry_name.dirty)
}

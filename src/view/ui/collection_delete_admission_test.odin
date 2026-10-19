#+test
package ui

import collections "../../collections"
import bridgemodel "../../bridge/model"
import testing "core:testing"
import uilibrary "library"
import userdata "../../userdata"

// A last-slot rename may commit before delete rejects; retry must not duplicate the rename.
@(test)
tree_collection_delete_retries_after_partial_queue_admission :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_collections_fixture(t, state, &ji, &nodes)
    _ = tree_actions_test_semantic_frame(t, &params)
    testing.expect(t, uilibrary.tree_collection_create(params))
    id := state.ui_runtime.library.tree.selected_item_id
    testing.expect(t, uilibrary.library_entry_name_edit(state, id, "Accepted rename"))
    testing.expect(t, uilibrary.tree_collection_delete(params, id))
    store: userdata.Store
    state.preferences_runtime.settings_store = &store
    defer state.preferences_runtime.settings_store = nil
    state.preferences_runtime.collection_mutation_count =
        collections.MUTATION_CAPACITY - 1
    params.mouse_input.sample_time_seconds += 1
    testing.expect(t, !uilibrary.tree_collection_delete(params, id))
    testing.expect(t, !state.ui_runtime.library.entry_name.dirty)
    testing.expect(t, state.ui_runtime.library.actions.delete_confirmation.armed)
    testing.expect_value(t,
        string(params.collections.collections[1].name), "Accepted rename")
    testing.expect_value(t, state.preferences_runtime.collection_mutations[
        collections.MUTATION_CAPACITY - 1].kind,
        collections.Mutation_Kind.Set_Collection_Name)
    state.preferences_runtime.collection_mutation_count = 0
    params.mouse_input.sample_time_seconds += 1
    testing.expect(t, uilibrary.tree_collection_delete(params, id))
    testing.expect_value(t, state.preferences_runtime.collection_mutation_count, 1)
    testing.expect_value(t, state.preferences_runtime.collection_mutations[0].kind,
        collections.Mutation_Kind.Delete_Collection)
}

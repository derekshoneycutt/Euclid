#+test
package ui

import testing "core:testing"
import viewmodel "model"
import uisemantics "semantics"

// Failed owner growth preserves its node/index tables and the committed slot.
@(test)
semantic_failed_growth_preserves_accepted_publication :: proc(t: ^testing.T) {
    state: viewmodel.Ui_Semantic_Focus_State
    defer viewmodel.ui_semantic_focus_destroy(&state)
    semantic_test_publish_scaled(t, &state)
    accepted := uisemantics.semantic_snapshot(&state)
    testing.expect(t, uisemantics.semantic_begin(&state))
    staging := uisemantics.semantic_staging_snapshot(&state)
    testing.expect(t, viewmodel.ui_semantic_snapshot_init(staging))
    testing.expect(t, viewmodel.ui_semantic_snapshot_reserve_nodes(staging, 32))
    failure: Tree_Projection_Test_Allocator_State = {
        backing_allocator = staging.allocator.backing_allocator,
    }
    staging.allocator.backing_allocator = {
        procedure = tree_projection_test_failing_allocator,
        data = &failure,
    }
    defer {
        staging.allocator.backing_allocator = failure.backing_allocator
    }
    semantic_test_expect_storage_failure(t, staging)
    label := make([]u8, 2 * 1024 * 1024, context.allocator)
    defer delete(label, context.allocator)
    for &byte in label {
        byte = 'a'
    }
    testing.expect_value(t, uisemantics.semantic_register_node(&state, {
        node = semantic_test_node(semantic_test_id(.Application, 1)),
        label = string(label),
    }), viewmodel.Ui_Semantic_Status.Allocation_Failed)
    testing.expect_value(t, staging.node_count, 0)
    testing.expect_value(t, uisemantics.semantic_publish(&state),
        viewmodel.Ui_Semantic_Status.Allocation_Failed)
    testing.expect_value(t, uisemantics.semantic_snapshot(&state), accepted)
}

// Admission of replacement tables and text is failure-atomic before publication.
semantic_test_expect_storage_failure :: proc(
    t: ^testing.T, snapshot: ^viewmodel.Ui_Semantic_Snapshot) {
    nodes := raw_data(snapshot.nodes)
    identities := raw_data(snapshot.identity_index)
    traversal := raw_data(snapshot.traversal_index)
    testing.expect(t, !viewmodel.ui_semantic_snapshot_reserve_nodes(snapshot, 65536))
    testing.expect_value(t, raw_data(snapshot.nodes), nodes)
    testing.expect_value(t, raw_data(snapshot.identity_index), identities)
    testing.expect_value(t, raw_data(snapshot.traversal_index), traversal)
    testing.expect_value(t, len(snapshot.nodes), 32)
}

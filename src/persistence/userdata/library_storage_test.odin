#+test
package userdata

import collections "../../collections"
import storage "../../core/storage"
import "core:os"
import "core:testing"
import "base:runtime"

// Joined transactional replay reuses the same Store owner across two warmed batches.
@(test)
userdata_replay_two_thousand_edits_reuse_backing :: proc(t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)
    store: Store
    snapshot := userdata_test_collection_snapshot(t)
    defer userdata_test_free_collection_set(snapshot)
    testing.expect_value(t,
        store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    defer store_close(&store)
    testing.expect_value(t,
        store_replace_collections(&store, snapshot).kind, Store_Error_Kind.None)
    userdata_replay_edit_batch(t, &store, snapshot)
    before := storage.tlsf_owner_diagnostics(
        &store.collection_replay_workspace.allocator)
    userdata_replay_edit_batch(t, &store, snapshot)
    after := storage.tlsf_owner_diagnostics(
        &store.collection_replay_workspace.allocator)
    testing.expect_value(t, after.retained_bytes, before.retained_bytes)
    testing.expect_value(t, after.current_live_bytes, before.current_live_bytes)
    testing.expect_value(t, after.live_allocation_count, before.live_allocation_count)
    testing.expect_value(t, after.peak_live_bytes, before.peak_live_bytes)
    testing.expect_value(t, after.peak_allocation_count, before.peak_allocation_count)
    testing.expect_value(t, after.growth_failure_count, uint(0))
}

// Alternate equal-size names through real SQL replay rather than cloning a test Set.
userdata_replay_edit_batch :: proc(
    t: ^testing.T, store: ^Store, snapshot: ^collections.Set) {
    entry := snapshot^.entries[collections.find_entry(snapshot, userdata_test_id(45))]
    identity, policy := collections.placement_identity_for_entry(snapshot, entry.id)
    testing.expect_value(t, policy, collections.Policy_Error.None)
    for index in 0..<1000 {
        name := "Replay name one" if index % 2 == 0 else "Replay name two"
        mutation, failure := collections.make_placement_name_mutation(identity, name)
        testing.expect_value(t, failure, collections.Mutation_Error.None)
        testing.expect_value(t,
            store_commit_user_data(store, {}, []collections.Mutation{mutation}).outcome,
            Commit_Outcome.Committed)
    }
}

// Inject backing failure before replay grows beyond its admitted launch-sized tables.
@(test)
userdata_replay_allocation_failure_retains_durable_snapshot_and_can_retry :: proc(
    t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)
    snapshot := new(collections.Set, context.allocator)
    defer userdata_test_free_collection_set(snapshot)
    testing.expect(t, collections.initialize(snapshot))
    userdata_test_fill_large_favorites(t, snapshot)
    store: Store
    testing.expect_value(t,
        store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    defer store_close(&store)
    testing.expect_value(t,
        store_replace_collections(&store, snapshot).kind, Store_Error_Kind.None)
    userdata_replay_reject_then_retry(t, &store, snapshot)
}

// A failed replay does not commit partial rows or make the next transaction unusable.
userdata_replay_reject_then_retry :: proc(
    t: ^testing.T, store: ^Store, snapshot: ^collections.Set) {
    identity, policy := collections.placement_identity_for_entry(
        snapshot, snapshot^.entries[0].id)
    testing.expect_value(t, policy, collections.Policy_Error.None)
    rename, failure := collections.make_placement_name_mutation(
        identity, "Retry after allocation failure")
    testing.expect_value(t, failure, collections.Mutation_Error.None)
    backing := store^.collection_replay_workspace.allocator.backing_allocator
    store^.collection_replay_workspace.allocator.backing_allocator = {
        procedure = userdata_replay_reject_backing,
    }
    rejected := store_commit_user_data(store, {}, []collections.Mutation{rename})
    store^.collection_replay_workspace.allocator.backing_allocator = backing
    testing.expect_value(t, rejected.outcome, Commit_Outcome.Not_Committed)
    testing.expect_value(t, rejected.failure.kind, Store_Error_Kind.Allocation)
    testing.expect_value(t,
        store_load_collections(store, snapshot).kind, Store_Error_Kind.None)
    userdata_test_expect_large_collection_round_trip(t, snapshot)
    testing.expect_value(t, store_commit_user_data(
        store, {}, []collections.Mutation{rename}).outcome, Commit_Outcome.Committed)
    testing.expect_value(t,
        store_load_collections(store, snapshot).kind, Store_Error_Kind.None)
    testing.expect_value(t,
        string(snapshot^.entries[0].custom_name), "Retry after allocation failure")
}

// Reject every request to the injected backing allocator; admitted TLSF frees are independent.
userdata_replay_reject_backing :: proc(
    _: rawptr, _: runtime.Allocator_Mode, _: int, _: int, _: rawptr, _: int,
    _: runtime.Source_Code_Location = #caller_location) -> (
        []byte, runtime.Allocator_Error) {
    return nil, .Out_Of_Memory
}

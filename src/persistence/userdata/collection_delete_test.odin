#+test
package userdata

import collections "../../collections"
import "core:os"
import "core:testing"

// Ordered rename/delete replay commits atomically and stale deletion rolls back preceding edits.
@(test)
userdata_collection_delete_replay_is_durable_and_atomic :: proc(t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)
    snapshot := new(collections.Set, context.allocator)
    defer userdata_test_free_collection_set(snapshot)
    testing.expect(t, collections.initialize(snapshot))
    first, _ := collections.make_collection_create_mutation(
        snapshot, userdata_test_id(91), "Same")
    _ = collections.apply_mutation(snapshot, first)
    second, _ := collections.make_collection_create_mutation(
        snapshot, userdata_test_id(92), "Same")
    _ = collections.apply_mutation(snapshot, second)
    rename, _ := collections.make_collection_name_mutation(
        snapshot, userdata_test_id(91), "Final label")
    remove, _ := collections.make_collection_delete_mutation(
        snapshot, userdata_test_id(91))
    store: Store
    testing.expect_value(t,
        store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    testing.expect_value(t, store_commit_user_data(
        &store, {}, []collections.Mutation{first, second, rename, remove}).outcome,
        Commit_Outcome.Committed)
    store_close(&store)
    testing.expect_value(t, store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    defer store_close(&store)
    testing.expect_value(t, store_load_collections(&store, snapshot).kind,
        Store_Error_Kind.None)
    testing.expect_value(t, snapshot.collection_count, 2)
    testing.expect_value(t,
        collections.find_collection(snapshot, userdata_test_id(91)), -1)
    userdata_test_collection_delete_rollback(t, &store, snapshot, remove)
}

// A stale delete must roll back the preceding survivor rename as one transaction.
userdata_test_collection_delete_rollback :: proc(
    t: ^testing.T, store: ^Store, snapshot: ^collections.Set,
    remove: collections.Mutation) {
    rename, _ := collections.make_collection_name_mutation(
        snapshot, userdata_test_id(92), "Must roll back")
    testing.expect_value(t, store_commit_user_data(
        store, {}, []collections.Mutation{rename, remove}).outcome,
        Commit_Outcome.Not_Committed)
    testing.expect_value(t, store_load_collections(store, snapshot).kind,
        Store_Error_Kind.None)
    index := collections.find_collection(snapshot, userdata_test_id(92))
    testing.expect_value(t, string(snapshot.collections[index].name), "Same")
}

// A complete owned subtree disappears transactionally while shared-animation Favorites survive.
@(test)
userdata_collection_delete_subtree_preserves_other_memberships :: proc(t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)
    snapshot := userdata_test_collection_snapshot(t)
    defer userdata_test_free_collection_set(snapshot)
    snapshot.collections[1].is_read_only = false
    identity, _ := collections.placement_identity_for_entry(
        snapshot, userdata_test_id(43))
    rename, _ := collections.make_placement_name_mutation(identity, "Deleted alias")
    testing.expect_value(t, collections.apply_mutation(snapshot, rename),
        collections.Mutation_Error.None)
    store: Store
    testing.expect_value(t, store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    testing.expect_value(t, store_replace_collections(&store, snapshot).kind,
        Store_Error_Kind.None)
    remove, _ := collections.make_collection_delete_mutation(
        snapshot, userdata_test_id(41))
    testing.expect_value(t, store_commit_user_data(
        &store, {}, []collections.Mutation{remove}).outcome, Commit_Outcome.Committed)
    store_close(&store)
    testing.expect_value(t, store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    defer store_close(&store)
    testing.expect_value(t, store_load_collections(&store, snapshot).kind,
        Store_Error_Kind.None)
    testing.expect_value(t, snapshot.collection_count, 1)
    testing.expect_value(t, snapshot.entry_count, 1)
    testing.expect_value(t, snapshot.entries[0].id, userdata_test_id(45))
    testing.expect_value(t, snapshot.entries[0].animation_id, userdata_test_id(44))
    testing.expect_value(t,
        collections.validate(snapshot), collections.Validation_Error.None)
}

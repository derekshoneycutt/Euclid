#+test
package userdata

import collections "../../collections"
import "core:os"
import "core:testing"

// Replay names and exact adjacent order swaps in one transaction and reopen independently.
@(test)
userdata_collection_head_edits_survive_restart :: proc(t: ^testing.T) {
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
    second, _ := collections.make_collection_create_mutation(
        snapshot, userdata_test_id(92), "Same")
    testing.expect_value(t, collections.apply_mutation(snapshot, first),
        collections.Mutation_Error.None)
    testing.expect_value(t, collections.apply_mutation(snapshot, second),
        collections.Mutation_Error.None)
    rename, _ := collections.make_collection_name_mutation(
        snapshot, userdata_test_id(92), "Teaching")
    move, _ := collections.make_collection_move(snapshot, userdata_test_id(92), .Up)
    store: Store
    testing.expect_value(t, store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    testing.expect_value(t, store_commit_user_data(
        &store, {}, []collections.Mutation{first, second, rename, move}).outcome,
        Commit_Outcome.Committed)
    store_close(&store)
    testing.expect_value(t, store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    defer store_close(&store)
    testing.expect_value(t, store_load_collections(
        &store, snapshot).kind, Store_Error_Kind.None)
    userdata_test_expect_head_edits(t, snapshot)
}

// Durable rows preserve UUIDs and the exchanged positive positions with no entries.
userdata_test_expect_head_edits :: proc(t: ^testing.T, snapshot: ^collections.Set) {
    first := snapshot^.collections[collections.find_collection(
        snapshot, userdata_test_id(91))]
    second := snapshot^.collections[collections.find_collection(
        snapshot, userdata_test_id(92))]
    testing.expect_value(t, first.order, i64(2))
    testing.expect_value(t, second.order, i64(1))
    testing.expect_value(t, string(first.name), "Same")
    testing.expect_value(t, string(second.name), "Teaching")
    testing.expect_value(t, snapshot^.entry_count, 0)
}

// A repeated exact-neighbor move rejects replay atomically, including the preceding rename.
@(test)
userdata_collection_head_replay_failure_rolls_back :: proc(t: ^testing.T) {
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
    second, _ := collections.make_collection_create_mutation(
        snapshot, userdata_test_id(92), "Same")
    _ = collections.apply_mutation(snapshot, first)
    _ = collections.apply_mutation(snapshot, second)
    rename, _ := collections.make_collection_name_mutation(
        snapshot, userdata_test_id(92), "Rejected")
    move, _ := collections.make_collection_move(snapshot, userdata_test_id(92), .Up)
    store: Store
    testing.expect_value(t, store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    defer store_close(&store)
    testing.expect_value(t,
        store_commit_user_data(&store, {}, []collections.Mutation{first, second}).outcome,
        Commit_Outcome.Committed)
    testing.expect_value(t, store_commit_user_data(
        &store, {}, []collections.Mutation{rename, move, move}).outcome,
        Commit_Outcome.Not_Committed)
    testing.expect_value(t, store_load_collections(
        &store, snapshot).kind, Store_Error_Kind.None)
    userdata_test_expect_empty_custom_collections_same(t, snapshot)
}

// The original equal labels and append order survive a rejected replay transaction.
userdata_test_expect_empty_custom_collections_same :: proc(
    t: ^testing.T, snapshot: ^collections.Set) {
    for index in 1..<3 {
        testing.expect_value(t, string(snapshot^.collections[index].name), "Same")
        testing.expect_value(t, snapshot^.collections[index].order, i64(index))
    }
}

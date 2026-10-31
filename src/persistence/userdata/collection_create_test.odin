#+test
package userdata

import collections "../../collections"
import sqlite "../../sqlite"
import "core:os"
import "core:testing"

// Empty equal-label custom collections survive joined replay, close and reopening.
@(test)
userdata_collection_create_empty_duplicates_save_and_reopen :: proc(t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)
    snapshot := new(collections.Set, context.allocator)
    defer userdata_test_free_collection_set(snapshot)
    testing.expect(t, collections.initialize(snapshot))
    first, first_error := collections.make_collection_create_mutation(
        snapshot, userdata_test_id(91), "New Collection")
    second, second_error := collections.make_collection_create_mutation(
        snapshot, userdata_test_id(92), "New Collection")
    testing.expect_value(t, first_error, collections.Policy_Error.None)
    testing.expect_value(t, second_error, collections.Policy_Error.None)
    store: Store
    testing.expect_value(t, store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    testing.expect_value(t, store_commit_user_data(
        &store, {}, []collections.Mutation{first, second}).outcome,
        Commit_Outcome.Committed)
    store_close(&store)
    testing.expect_value(t, store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    defer store_close(&store)
    testing.expect_value(t, store_load_collections(
        &store, snapshot).kind, Store_Error_Kind.None)
    userdata_test_expect_empty_custom_collections(t, snapshot)
}

// Verify UUID identity, duplicate labels and stable positive order after durable reload.
userdata_test_expect_empty_custom_collections :: proc(
    t: ^testing.T, snapshot: ^collections.Set) {
    testing.expect_value(t, snapshot^.collection_count, 3)
    testing.expect_value(t, snapshot^.entry_count, 0)
    testing.expect_value(t,
        collections.validate(snapshot), collections.Validation_Error.None)
    for index in 1..<3 {
        collection := snapshot^.collections[index]
        testing.expect_value(t, collection.id, userdata_test_id(u8(90 + index)))
        testing.expect_value(t, collection.role, collections.Role.User)
        testing.expect_value(t, string(collection.name), "New Collection")
        testing.expect_value(t, collection.order, i64(index))
        testing.expect(t, !collection.is_read_only)
    }
}

// A duplicate-ID replay rejects the entire batch and leaves an empty durable store.
@(test)
userdata_collection_create_replay_failure_rolls_back_and_retries :: proc(
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
    mutation, failure := collections.make_collection_create_mutation(
        snapshot, userdata_test_id(91), "New Collection")
    testing.expect_value(t, failure, collections.Policy_Error.None)
    store: Store
    testing.expect_value(t, store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    defer store_close(&store)
    result := store_commit_user_data(
        &store, {}, []collections.Mutation{mutation, mutation})
    testing.expect_value(t, result.outcome, Commit_Outcome.Not_Committed)
    testing.expect_value(t,
        store_load_collections(&store, snapshot).kind, Store_Error_Kind.None)
    testing.expect_value(t, snapshot^.collection_count, 1)
    testing.expect_value(t, store_commit_user_data(
        &store, {}, []collections.Mutation{mutation}).outcome, Commit_Outcome.Committed)
    testing.expect_value(t,
        store_load_collections(&store, snapshot).kind, Store_Error_Kind.None)
    testing.expect_value(t, snapshot^.collection_count, 2)
}

// SQLite rejects reserved/duplicate order and malformed reserved identities in-place.
@(test)
userdata_collection_schema_rejects_reserved_and_duplicate_orders :: proc(t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)
    store: Store
    testing.expect_value(t, store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    defer store_close(&store)
    statements: []cstring = {
        "INSERT INTO user_collection VALUES (X'00000000000000000000000000000001',NULL,'Name',0,0)",
        "INSERT INTO user_collection VALUES (X'00000000000000000000000000000000',NULL,'Name',1,0)",
        "UPDATE user_collection SET collection_order=1 WHERE system_role='favorites'",
        "UPDATE user_collection SET system_role=NULL,display_name='Name' WHERE system_role='favorites'",
        "UPDATE user_collection SET collection_id=X'00000000000000000000000000000001'",
    }
    for sql in statements {
        failure := sqlite.connection_exec(&store.connection, sql)
        testing.expect(t, !store_sqlite_error_is_clear(failure))
    }
    testing.expect(t, store_sqlite_error_is_clear(
        sqlite.connection_exec(&store.connection,
        "INSERT INTO user_collection VALUES (X'00000000000000000000000000000001',NULL,'Name',1,0)")))
    testing.expect(t, !store_sqlite_error_is_clear(
        sqlite.connection_exec(&store.connection,
        "INSERT INTO user_collection VALUES (X'00000000000000000000000000000002',NULL,'Name',1,0)")))
}

// Invalid UTF-8 cannot enter the model when decoding externally edited collection rows.
@(test)
userdata_collection_create_rejects_invalid_stored_utf8 :: proc(t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)
    store: Store
    testing.expect_value(t, store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    defer store_close(&store)
    testing.expect(t, store_sqlite_error_is_clear(
        sqlite.connection_exec(&store.connection,
        "INSERT INTO user_collection VALUES (X'00000000000000000000000000000001',NULL,CAST(X'FF' AS TEXT),1,0)")))
    snapshot := new(collections.Set, context.allocator)
    defer userdata_test_free_collection_set(snapshot)
    testing.expect(t, collections.initialize(snapshot))
    testing.expect_value(t,
        store_load_collections(&store, snapshot).kind, Store_Error_Kind.Invalid_Schema)
    testing.expect_value(t, snapshot^.collection_count, 1)
}

// Collection creation retries the original immutable identity after replay storage failure.
@(test)
userdata_collection_create_replay_allocation_failure_retries :: proc(t: ^testing.T) {
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
    mutation, failure := collections.make_collection_create_mutation(
        snapshot, userdata_test_id(91), "New Collection")
    testing.expect_value(t, failure, collections.Policy_Error.None)
    store: Store
    testing.expect_value(t, store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    defer store_close(&store)
    testing.expect_value(t,
        store_replace_collections(&store, snapshot).kind, Store_Error_Kind.None)
    backing := store.collection_replay_workspace.allocator.backing_allocator
    store.collection_replay_workspace.allocator.backing_allocator = {
        procedure = userdata_replay_reject_backing,
    }
    rejected := store_commit_user_data(&store, {}, []collections.Mutation{mutation})
    store.collection_replay_workspace.allocator.backing_allocator = backing
    testing.expect_value(t, rejected.outcome, Commit_Outcome.Not_Committed)
    testing.expect_value(t, rejected.failure.kind, Store_Error_Kind.Allocation)
    testing.expect_value(t,
        store_load_collections(&store, snapshot).kind, Store_Error_Kind.None)
    testing.expect_value(t, snapshot^.collection_count, 1)
    testing.expect_value(t, store_commit_user_data(
        &store, {}, []collections.Mutation{mutation}).outcome, Commit_Outcome.Committed)
    testing.expect_value(t,
        store_load_collections(&store, snapshot).kind, Store_Error_Kind.None)
    testing.expect_value(t,
        collections.find_collection(snapshot, mutation.collection_id), 1)
}

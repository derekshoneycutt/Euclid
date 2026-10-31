#+test
package userdata

import collections "../../collections"
import uuid "core:encoding/uuid"
import "core:os"
import "core:testing"

// Persisted nested membership is unique collection-wide while the same animation may be favorited.
@(test)
userdata_collection_membership_sql_rejects_duplicate_animation :: proc(t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)
    snapshot := userdata_test_collection_snapshot(t)
    defer userdata_test_free_collection_set(snapshot)
    store: Store
    testing.expect_value(t, store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    defer store_close(&store)
    testing.expect_value(t,
        store_replace_collections(&store, snapshot).kind, Store_Error_Kind.None)
    userdata_expect_constraint(t, &store,
        "INSERT INTO user_collection_entry VALUES (" +
        "X'00000000000000000000000000000063'," +
        "X'00000000000000000000000000000029',NULL,1,'animation'," +
        "X'0000000000000000000000000000002C',NULL)")
    testing.expect_value(t,
        store_load_collections(&store, snapshot).kind, Store_Error_Kind.None)
    testing.expect_value(t, snapshot.entry_count, 3)
}

// Loading still rejects duplicate persisted membership if a damaged database loses its SQL index.
@(test)
userdata_collection_membership_load_rejects_duplicate_rows :: proc(t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)
    snapshot := userdata_test_collection_snapshot(t)
    defer userdata_test_free_collection_set(snapshot)
    store: Store
    testing.expect_value(t, store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    defer store_close(&store)
    testing.expect_value(t,
        store_replace_collections(&store, snapshot).kind, Store_Error_Kind.None)
    testing.expect(t,
        store_sqlite_error_is_clear(
            store_exec(&store, "DROP INDEX user_collection_membership")))
    testing.expect(t, store_sqlite_error_is_clear(store_exec(&store,
        "INSERT INTO user_collection_entry VALUES (" +
        "X'00000000000000000000000000000063'," +
        "X'00000000000000000000000000000029',NULL,1,'animation'," +
        "X'0000000000000000000000000000002C',NULL)")))
    testing.expect_value(t,
        store_load_collections(&store, snapshot).kind, Store_Error_Kind.Invalid_Schema)
}

// Ordered nested removal and root re-add survive reopen without retaining an old alias.
@(test)
userdata_collection_membership_replay_readd_is_durable :: proc(t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)
    snapshot := userdata_test_collection_snapshot(t)
    defer userdata_test_free_collection_set(snapshot)
    mutations := userdata_test_membership_readd_mutations(t, snapshot)
    store: Store
    testing.expect_value(t,
        store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    testing.expect_value(t,
        store_replace_collections(&store, snapshot).kind, Store_Error_Kind.None)
    testing.expect_value(t,
        store_commit_user_data(&store, {}, mutations[:]).outcome,
        Commit_Outcome.Committed)
    store_close(&store)
    testing.expect_value(t, store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    defer store_close(&store)
    testing.expect_value(t,
        store_load_collections(&store, snapshot).kind, Store_Error_Kind.None)
    userdata_test_membership_readd_snapshot(t, &store, snapshot, mutations[1])
}

// Prepare ordered alias/removal/re-add replay while preserving the stored initial occurrence.
userdata_test_membership_readd_mutations :: proc(
    t: ^testing.T, snapshot: ^collections.Set) -> [3]collections.Mutation {
    snapshot.collections[1].is_read_only = false
    identity, _ := collections.collection_animation_identity(
        snapshot, userdata_test_id(41), userdata_test_id(44))
    rename, _ := collections.make_placement_name_mutation(identity, "Discarded")
    remove, _ := collections.make_collection_animation_remove_mutation(
        snapshot, identity)
    _ = collections.apply_mutation(snapshot, remove)
    add, _ := collections.make_collection_animation_add_mutation(
        snapshot, userdata_test_id(41), userdata_test_id(46), userdata_test_id(44))
    testing.expect_value(t, collections.append_entry(snapshot, {
        id = userdata_test_id(43),
        collection_id = userdata_test_id(41),
        parent_entry_id = userdata_test_id(42),
        kind = .Animation,
        animation_id = userdata_test_id(44),
    }), collections.Policy_Error.None)
    return {rename, remove, add}
}

// A stale removal rolls back preceding mutations and leaves the new occurrence and group intact.
userdata_test_membership_readd_snapshot :: proc(
    t: ^testing.T, store: ^Store,
    snapshot: ^collections.Set, stale: collections.Mutation) {
    identity, policy := collections.collection_animation_identity(
        snapshot, userdata_test_id(41), userdata_test_id(44))
    testing.expect_value(t, policy, collections.Policy_Error.None)
    testing.expect_value(t, identity.entry_id, userdata_test_id(46))
    testing.expect_value(t, identity.parent_entry_id, uuid.Identifier{})
    placement, _ := collections.placement_resolve(snapshot, identity)
    testing.expect_value(t, placement.custom_name_length, 0)
    testing.expect_value(t, placement.sibling_order, i64(1))
    testing.expect(t, collections.find_entry(snapshot, userdata_test_id(42)) >= 0)
    testing.expect(t, collections.find_entry(snapshot, userdata_test_id(45)) >= 0)
    rename, _ := collections.make_placement_name_mutation(identity, "Must roll back")
    testing.expect_value(t,
        store_commit_user_data(store, {}, []collections.Mutation{rename, stale}).outcome,
        Commit_Outcome.Not_Committed)
    testing.expect_value(t,
        store_load_collections(store, snapshot).kind, Store_Error_Kind.None)
    placement, _ = collections.placement_resolve(snapshot, identity)
    testing.expect_value(t, placement.custom_name_length, 0)
}

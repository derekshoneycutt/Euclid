#+test
package userdata

import collections "../../collections"
import "core:os"
import "core:testing"

// Create two writable collection placements for one animation.
userdata_note_test_snapshot :: proc(t: ^testing.T) -> ^collections.Set {
    snapshot := userdata_test_collection_snapshot(t)
    snapshot^.collections[1].is_read_only = false
    name: [5]u8 = {'S', 't', 'u', 'd', 'y'}
    testing.expect_value(t, collections.append_collection(snapshot, {
        id = userdata_test_id(46),
        role = .User,
        name = name[:],
        name_length = len(name),
        order = 2,
    }), collections.Policy_Error.None)
    testing.expect_value(t, collections.append_entry(snapshot, {
        id = userdata_test_id(47),
        collection_id = userdata_test_id(46),
        kind = .Animation,
        animation_id = userdata_test_id(44),
    }), collections.Policy_Error.None)
    return snapshot
}

// Verify placement-scoped Unicode notes and reading order survive reopen and replay.
@(test)
userdata_collection_notes_round_trip_per_placement :: proc(t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)
    snapshot := userdata_note_test_snapshot(t)
    defer userdata_test_free_collection_set(snapshot)
    store: Store
    testing.expect_value(t, store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    defer store_close(&store)
    testing.expect_value(t,
        store_replace_collections(&store, snapshot).kind, Store_Error_Kind.None)
    first, first_policy := collections.placement_identity_for_entry(
        snapshot, userdata_test_id(43))
    second, second_policy := collections.placement_identity_for_entry(
        snapshot, userdata_test_id(47))
    testing.expect_value(t, first_policy, collections.Policy_Error.None)
    testing.expect_value(t, second_policy, collections.Policy_Error.None)
    testing.expect_value(t,
        store_write_collection_note(&store, first, "Observe π", true).kind,
        Store_Error_Kind.None)
    testing.expect_value(t,
        store_write_collection_note(&store, second, "", true).kind,
        Store_Error_Kind.None)
    userdata_note_test_expect_read(t, &store, first, "Observe π", true)
    userdata_note_test_expect_read(t, &store, second, "", true)
    userdata_note_test_rename_placement(t, &store, first)
    testing.expect_value(t, store_close(&store).kind, Store_Error_Kind.None)
    testing.expect_value(t, store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    userdata_note_test_expect_read(t, &store, first, "Observe π", true)
    userdata_note_test_expect_read(t, &store, second, "", true)
}

// Replay a placement rename without replacing its note-owning identity.
userdata_note_test_rename_placement :: proc(
    t: ^testing.T, store: ^Store, identity: collections.Placement_Identity) {
    rename, failure := collections.make_placement_name_mutation(identity, "Lesson")
    testing.expect_value(t, failure, collections.Mutation_Error.None)
    testing.expect_value(t,
        store_commit_user_data(store, {}, []collections.Mutation{rename}).outcome,
        Commit_Outcome.Committed)
}

// Check note decoding through caller-owned bounded storage.
userdata_note_test_expect_read :: proc(
    t: ^testing.T,
    store: ^Store,
    identity: collections.Placement_Identity,
    expected: string,
    notes_on_top: bool) {
    buffer: [COLLECTION_NOTE_MAX_BYTES]u8
    result, failure := store_read_collection_note(store, identity, buffer[:])
    testing.expect_value(t, failure.kind, Store_Error_Kind.None)
    testing.expect(t, result.found)
    testing.expect_value(t, result.text_length, len(expected))
    testing.expect_value(t, string(buffer[:result.text_length]), expected)
    testing.expect_value(t, result.notes_on_top, notes_on_top)
}

// Reject ineligible writes and ensure failed topology replay preserves note rows.
@(test)
userdata_collection_notes_validate_owner_and_cleanup_transactionally :: proc(
    t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)
    snapshot := userdata_note_test_snapshot(t)
    defer userdata_test_free_collection_set(snapshot)
    store: Store
    testing.expect_value(t, store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    defer store_close(&store)
    testing.expect_value(t,
        store_replace_collections(&store, snapshot).kind, Store_Error_Kind.None)
    userdata_note_test_reject_ineligible_writes(t, snapshot, &store)
    userdata_note_test_replay_cleanup(t, snapshot, &store)
}

// Verify note writes reject non-animation and read-only placements.
userdata_note_test_reject_ineligible_writes :: proc(
    t: ^testing.T, snapshot: ^collections.Set, store: ^Store) {
    animation, animation_policy := collections.placement_identity_for_entry(
        snapshot, userdata_test_id(43))
    group, group_policy := collections.placement_identity_for_entry(
        snapshot, userdata_test_id(42))
    favorite, favorite_policy := collections.placement_identity_for_entry(
        snapshot, userdata_test_id(45))
    testing.expect_value(t, animation_policy, collections.Policy_Error.None)
    testing.expect_value(t, group_policy, collections.Policy_Error.None)
    testing.expect_value(t, favorite_policy, collections.Policy_Error.None)
    snapshot^.collections[1].is_read_only = true
    testing.expect_value(t,
        store_replace_collections(store, snapshot).kind, Store_Error_Kind.None)
    testing.expect_value(t,
        store_write_collection_note(store, animation, "read only", false).kind,
        Store_Error_Kind.Not_Writable)
    snapshot^.collections[1].is_read_only = false
    testing.expect_value(t,
        store_replace_collections(store, snapshot).kind, Store_Error_Kind.None)
    testing.expect_value(t,
        store_write_collection_note(store, group, "not eligible", false).kind,
        Store_Error_Kind.Invalid_Batch)
    testing.expect_value(t,
        store_write_collection_note(store, favorite, "not eligible", false).kind,
        Store_Error_Kind.Invalid_Batch)
}

// Preserve note rows when mutation replay fails and remove them after valid deletion.
userdata_note_test_replay_cleanup :: proc(
    t: ^testing.T, snapshot: ^collections.Set, store: ^Store) {
    animation, animation_policy := collections.placement_identity_for_entry(
        snapshot, userdata_test_id(43))
    testing.expect_value(t, animation_policy, collections.Policy_Error.None)
    testing.expect_value(t,
        store_write_collection_note(store, animation, "keep me", false).kind,
        Store_Error_Kind.None)
    removal, remove_error := collections.make_collection_animation_remove_mutation(
        snapshot, animation)
    rename, rename_error := collections.make_placement_name_mutation(animation, "Stale")
    testing.expect_value(t, remove_error, collections.Policy_Error.None)
    testing.expect_value(t, rename_error, collections.Mutation_Error.None)
    failed := store_commit_user_data(
        store, {}, []collections.Mutation{removal, rename})
    testing.expect_value(t, failed.outcome, Commit_Outcome.Not_Committed)
    note_count, count_valid := userdata_test_integer_query(
        &store^.connection, "SELECT COUNT(*) FROM user_collection_note")
    testing.expect(t, count_valid)
    testing.expect_value(t, note_count, i64(1))
    userdata_note_test_expect_read(t, store, animation, "keep me", false)
    testing.expect_value(t,
        store_commit_user_data(store, {}, []collections.Mutation{removal}).outcome,
        Commit_Outcome.Committed)
    note_count, count_valid = userdata_test_integer_query(
        &store^.connection, "SELECT COUNT(*) FROM user_collection_note")
    testing.expect(t, count_valid)
    testing.expect_value(t, note_count, i64(0))
}

// Reject invalid note payloads before they can overwrite a durable valid note.
@(test)
userdata_collection_notes_reject_invalid_payloads_atomically :: proc(
    t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)
    snapshot := userdata_note_test_snapshot(t)
    defer userdata_test_free_collection_set(snapshot)
    store: Store
    testing.expect_value(t, store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    defer store_close(&store)
    testing.expect_value(t,
        store_replace_collections(&store, snapshot).kind, Store_Error_Kind.None)
    identity, policy := collections.placement_identity_for_entry(
        snapshot, userdata_test_id(43))
    testing.expect_value(t, policy, collections.Policy_Error.None)
    userdata_note_test_reject_invalid_writes(t, &store, identity)
    userdata_note_test_reject_malformed_rows(t, &store, identity)
}

// Reject over-limit, NUL, and invalid UTF-8 payloads without replacing valid text.
userdata_note_test_reject_invalid_writes :: proc(
    t: ^testing.T, store: ^Store, identity: collections.Placement_Identity) {
    testing.expect_value(t,
        store_write_collection_note(store, identity, "valid", false).kind,
        Store_Error_Kind.None)
    oversized := make([]u8, COLLECTION_NOTE_MAX_BYTES + 1, context.allocator)
    testing.expect_value(t,
        store_write_collection_note(store, identity, string(oversized), true).kind,
        Store_Error_Kind.Invalid_Batch)
    nul_text := "bad\x00note"
    testing.expect_value(t,
        store_write_collection_note(store, identity, nul_text, true).kind,
        Store_Error_Kind.Invalid_Batch)
    invalid_utf8: [2]u8 = {0xC0, 0x80}
    testing.expect_value(t,
        store_write_collection_note(
            store, identity, string(invalid_utf8[:]), true).kind,
        Store_Error_Kind.Invalid_Batch)
    userdata_note_test_expect_read(t, store, identity, "valid", false)
}

// Verify malformed persisted rows fail decoding instead of being accepted.
userdata_note_test_reject_malformed_rows :: proc(
    t: ^testing.T, store: ^Store, identity: collections.Placement_Identity) {
    testing.expect(t, store_sqlite_error_is_clear(store_exec(
        store, "PRAGMA ignore_check_constraints=ON; UPDATE user_collection_note " +
        "SET note_text=CAST(X'C080' AS TEXT) WHERE collection_id=" +
        "X'00000000000000000000000000000029' AND " +
        "entry_id=X'0000000000000000000000000000002B'")))
    buffer: [COLLECTION_NOTE_MAX_BYTES]u8
    _, malformed := store_read_collection_note(store, identity, buffer[:])
    testing.expect_value(t, malformed.kind, Store_Error_Kind.Read)
    testing.expect(t, store_sqlite_error_is_clear(store_exec(
        store, "UPDATE user_collection_note " +
        "SET note_text=CAST(zeroblob(4097) AS TEXT) WHERE collection_id=" +
        "X'00000000000000000000000000000029' AND " +
        "entry_id=X'0000000000000000000000000000002B'")))
    _, oversized_row := store_read_collection_note(store, identity, buffer[:])
    testing.expect_value(t, oversized_row.kind, Store_Error_Kind.Read)
}

package userdata

import sqlite "../../sqlite"
import collections "../../collections"
import uuid "core:encoding/uuid"
import "core:unicode/utf8"

COLLECTION_NOTE_MAX_BYTES :: 4096

// Read one eligible user-collection animation note in a consistent snapshot.
store_read_collection_note :: proc(
    store: ^Store,
    identity: collections.Placement_Identity,
    destination: []u8) -> (Collection_Note_Read_Result, Store_Error) {
    if store == nil ||
        (store^.status != .Ready && store^.status != .Read_Only) {
        return {}, {
            kind = .Closed,
        }
    }
    if len(destination) < COLLECTION_NOTE_MAX_BYTES {
        return {}, {
            kind = .Invalid_Batch,
        }
    }
    begin_error := store_exec(store, "BEGIN")
    if !store_sqlite_error_is_clear(begin_error) {
        return {}, {
            kind = .Read,
            sqlite_error = begin_error,
        }
    }
    failure := store_read_collection_snapshot(
        store, &store^.collection_replay_workspace)
    if !store_error_is_clear(failure) {
        return {}, store_rollback_failure(store, failure.kind, failure.sqlite_error)
    }
    failure = store_validate_note_placement(
        &store^.collection_replay_workspace, identity, false)
    if !store_error_is_clear(failure) {
        return {}, store_rollback_failure(store, failure.kind, failure.sqlite_error)
    }
    result, read_error := store_read_collection_note_row(
        store, identity, destination)
    if !store_sqlite_error_is_clear(read_error) {
        return {}, store_rollback_failure(store, .Read, read_error)
    }
    commit_error := store_exec(store, "COMMIT")
    if !store_sqlite_error_is_clear(commit_error) {
        return {}, store_rollback_failure(store, .Read, commit_error)
    }
    return result, {}
}

// Persist one bounded note only while its placement remains writable and eligible.
store_write_collection_note :: proc(
    store: ^Store,
    identity: collections.Placement_Identity,
    text: string,
    notes_on_top: bool) -> Store_Error {
    preflight := store_collection_note_write_preflight(store, text)
    if !store_error_is_clear(preflight) {
        return preflight
    }
    begin_error := store_exec(store, "BEGIN IMMEDIATE")
    if !store_sqlite_error_is_clear(begin_error) {
        return {
            kind = .Write,
            sqlite_error = begin_error,
        }
    }
    failure := store_read_collection_snapshot(
        store, &store^.collection_replay_workspace)
    if store_error_is_clear(failure) {
        failure = store_validate_note_placement(
            &store^.collection_replay_workspace, identity, true)
    }
    if !store_error_is_clear(failure) {
        return store_rollback_failure(store, failure.kind, failure.sqlite_error)
    }
    write_error := store_write_collection_note_row(
        store, identity, text, notes_on_top)
    if !store_sqlite_error_is_clear(write_error) {
        return store_rollback_failure(store, .Write, write_error)
    }
    commit_error := store_exec(store, "COMMIT")
    if !store_sqlite_error_is_clear(commit_error) {
        return store_rollback_failure(store, .Write, commit_error)
    }
    return {}
}

// Reject invalid stores and payloads before opening a write transaction.
store_collection_note_write_preflight :: proc(
    store: ^Store, text: string) -> Store_Error {
    if store == nil || store^.status == .Closed {
        return {
            kind = .Closed,
        }
    }
    if store^.status == .Unusable {
        return {
            kind = .Unusable,
        }
    }
    if store^.status == .Read_Only {
        return {
            kind = .Not_Writable,
        }
    }
    if !store_note_text_is_valid(text) {
        return {
            kind = .Invalid_Batch,
        }
    }
    return {}
}

// Verify user ownership, animation kind, placement identity, and write policy.
store_validate_note_placement :: proc(
    snapshot: ^collections.Set,
    identity: collections.Placement_Identity,
    writing: bool) -> Store_Error {
    placement, policy := collections.placement_resolve(snapshot, identity)
    if policy != .None || placement.kind != .Animation ||
        placement.animation_id == (uuid.Identifier{}) {
        return {
            kind = .Invalid_Batch,
        }
    }
    collection_index := collections.find_collection(snapshot, identity.collection_id)
    if collection_index < 0 ||
        snapshot^.collections[collection_index].role != .User {
        return {
            kind = .Invalid_Batch,
        }
    }
    if writing && snapshot^.collections[collection_index].is_read_only {
        return {
            kind = .Not_Writable,
        }
    }
    return {}
}

// Read and exactly decode one placement's stored note row.
store_read_collection_note_row :: proc(
    store: ^Store,
    identity: collections.Placement_Identity,
    destination: []u8) -> (Collection_Note_Read_Result, sqlite.Error) {
    statement := &store^.read_collection_note
    collection_id := identity.collection_id
    entry_id := identity.entry_id
    failure := sqlite.statement_reset(statement)
    if store_sqlite_error_is_clear(failure) {
        failure = sqlite.statement_bind_blob(statement, 1, collection_id[:])
    }
    if store_sqlite_error_is_clear(failure) {
        failure = sqlite.statement_bind_blob(statement, 2, entry_id[:])
    }
    if !store_sqlite_error_is_clear(failure) {
        return {}, store_reset_preserving(statement, failure)
    }
    status, step_error := sqlite.statement_step(statement)
    failure = step_error
    if !store_sqlite_error_is_clear(failure) {
        return {}, store_reset_preserving(statement, failure)
    }
    if status == .Done {
        return {}, sqlite.statement_reset(statement)
    }
    if status != .Row {
        failure = sqlite.sqlite_make_validation_error(.Step, .Invalid_State)
        return {}, store_reset_preserving(statement, failure)
    }
    return store_read_collection_note_finish(statement, destination)
}

// Decode the sole row and reset the reusable statement after enforcing uniqueness.
store_read_collection_note_finish :: proc(
    statement: ^sqlite.Statement,
    destination: []u8) -> (Collection_Note_Read_Result, sqlite.Error) {
    result, failure := store_decode_collection_note(statement, destination)
    if store_sqlite_error_is_clear(failure) {
        status, step_error := sqlite.statement_step(statement)
        failure = step_error
        if store_sqlite_error_is_clear(failure) && status != .Done {
            failure = sqlite.sqlite_make_validation_error(.Step, .Invalid_State)
        }
    }
    failure = store_reset_preserving(statement, failure)
    return result, failure
}

// Reject malformed or oversized note rows without publishing partial text.
store_decode_collection_note :: proc(
    statement: ^sqlite.Statement,
    destination: []u8) -> (Collection_Note_Read_Result, sqlite.Error) {
    if sqlite.column_type(statement, 0) != .Text {
        return {}, sqlite.sqlite_make_validation_error(.Column, .Type_Mismatch)
    }
    text_length, failure := sqlite.column_text_copy(statement, 0, destination)
    if !store_sqlite_error_is_clear(failure) {
        return {}, failure
    }
    if !utf8.valid_string(string(destination[:text_length])) ||
        store_note_text_has_nul(destination[:text_length]) {
        return {}, sqlite.sqlite_make_validation_error(.Column, .Type_Mismatch)
    }
    if sqlite.column_type(statement, 1) != .Integer {
        return {}, sqlite.sqlite_make_validation_error(.Column, .Type_Mismatch)
    }
    order, column_failure := sqlite.column_i64(statement, 1)
    failure = column_failure
    if !store_sqlite_error_is_clear(failure) {
        return {}, failure
    }
    if order != 0 && order != 1 {
        return {}, sqlite.sqlite_make_validation_error(.Column, .Range)
    }
    return {
        found = true,
        text_length = text_length,
        notes_on_top = order == 1,
    }, {}
}

// Upsert note text and reading order using transient, SQLite-owned copies.
store_write_collection_note_row :: proc(
    store: ^Store,
    identity: collections.Placement_Identity,
    text: string,
    notes_on_top: bool) -> sqlite.Error {
    statement := &store^.upsert_collection_note
    collection_id := identity.collection_id
    entry_id := identity.entry_id
    failure := sqlite.statement_reset(statement)
    if store_sqlite_error_is_clear(failure) {
        failure = sqlite.statement_bind_blob(statement, 1, collection_id[:])
    }
    if store_sqlite_error_is_clear(failure) {
        failure = sqlite.statement_bind_blob(statement, 2, entry_id[:])
    }
    if store_sqlite_error_is_clear(failure) {
        failure = sqlite.statement_bind_text(statement, 3, text)
    }
    if store_sqlite_error_is_clear(failure) {
        failure = sqlite.statement_bind_i64(statement, 4, i64(notes_on_top ? 1 : 0))
    }
    if store_sqlite_error_is_clear(failure) {
        _, failure = sqlite.statement_step(statement)
    }
    return store_reset_preserving(statement, failure)
}

// Validate note bytes before any database transaction or mutation begins.
store_note_text_is_valid :: proc(text: string) -> bool {
    return len(text) <= COLLECTION_NOTE_MAX_BYTES &&
        utf8.valid_string(text) && !store_note_text_has_nul(transmute([]u8)text)
}

// Detect embedded NUL without relying on SQLite's text terminator behavior.
store_note_text_has_nul :: proc(text: []u8) -> bool {
    for value in text {
        if value == 0 {
            return true
        }
    }
    return false
}

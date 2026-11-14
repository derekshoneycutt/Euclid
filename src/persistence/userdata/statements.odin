package userdata

import sqlite "../../sqlite"
import "core:strings"

READ_SETTING_SQL :: #load("sql/read_setting.sql", string)
UPSERT_SETTING_SQL :: #load("sql/upsert_setting.sql", string)
DELETE_SETTING_SQL :: #load("sql/delete_setting.sql", string)
READ_COLLECTIONS_SQL :: #load("sql/read_collections.sql", string)
READ_COLLECTION_ENTRIES_SQL :: #load("sql/read_collection_entries.sql", string)
INSERT_COLLECTION_SQL :: #load("sql/insert_collection.sql", string)
INSERT_COLLECTION_ENTRY_SQL :: #load("sql/insert_collection_entry.sql", string)
DELETE_COLLECTION_ENTRIES_SQL :: #load("sql/delete_collection_entries.sql", string)
DELETE_COLLECTIONS_SQL :: #load("sql/delete_collections.sql", string)
READ_COLLECTION_NOTE_SQL :: #load("sql/read_collection_note.sql", string)
UPSERT_COLLECTION_NOTE_SQL :: #load("sql/upsert_collection_note.sql", string)
DELETE_ORPHAN_COLLECTION_NOTES_SQL :: #load("sql/delete_orphan_collection_notes.sql", string)
EXERCISE_BY_IDENTITY_SQL :: #load("sql/exercise_by_identity.sql", string)
EXERCISE_BY_ALIAS_SQL :: #load("sql/exercise_by_alias.sql", string)
EXERCISE_LIST_COUNT_SQL :: #load("sql/exercise_list_count.sql", string)
EXERCISE_LIST_ROWS_SQL :: #load("sql/exercise_list_rows.sql", string)
RETIRED_EXERCISE_ALIAS_SQL :: #load("sql/retired_exercise_alias.sql", string)
EXERCISE_ALIAS_STATE_SQL :: #load("sql/exercise_alias_state.sql", string)
EXERCISE_IDENTITY_TAKEN_SQL :: #load("sql/exercise_identity_taken.sql", string)
EXERCISE_ROWS_FOR_ADMISSION_SQL :: #load("sql/exercise_rows_for_admission.sql", string)
RETIRED_EXERCISE_ROWS_FOR_ADMISSION_SQL :: #load(
    "sql/retired_exercise_rows_for_admission.sql", string)
EXERCISE_INSERT_SQL :: #load("sql/exercise_insert.sql", string)
EXERCISE_UPDATE_SQL :: #load("sql/exercise_update.sql", string)
EXERCISE_DELETE_SQL :: #load("sql/exercise_delete.sql", string)
EXERCISE_RETIRE_ALIAS_SQL :: #load("sql/exercise_retire_alias.sql", string)
EXERCISE_RETIRE_IDENTITY_SQL :: #load("sql/exercise_retire_identity.sql", string)

// Prepare only the known-key statements needed by admitted stores.
store_prepare_statements :: proc(
    store: ^Store, read_only: bool) -> Store_Error {
    failure := store_prepare_read_statements(store)
    if !store_error_is_clear(failure) || read_only {
        return failure
    }
    return store_prepare_write_statements(store)
}

// Prepare all statements required for reads and schema admission.
store_prepare_read_statements :: proc(store: ^Store) -> Store_Error {
    failure := store_prepare_statement(store, &store^.read_setting, READ_SETTING_SQL)
    if !store_error_is_clear(failure) {
        return failure
    }
    failure = store_prepare_statement(
        store, &store^.read_collections, READ_COLLECTIONS_SQL)
    if !store_error_is_clear(failure) {
        return failure
    }
    failure = store_prepare_statement(
        store, &store^.read_collection_entries, READ_COLLECTION_ENTRIES_SQL)
    if !store_error_is_clear(failure) {
        return failure
    }
    failure = store_prepare_statement(
        store, &store^.read_collection_note, READ_COLLECTION_NOTE_SQL)
    if !store_error_is_clear(failure) {
        return failure
    }
    failure = store_prepare_user_exercise_read_statements(store)
    if !store_error_is_clear(failure) {
        return failure
    }
    return {}
}

// Prepare all mutation statements for a writable admitted connection.
store_prepare_write_statements :: proc(store: ^Store) -> Store_Error {
    failure := store_prepare_setting_write_statements(store)
    if !store_error_is_clear(failure) {
        return failure
    }
    failure = store_prepare_collection_write_statements(store)
    if !store_error_is_clear(failure) {
        return failure
    }
    failure = store_prepare_note_write_statements(store)
    if !store_error_is_clear(failure) {
        return failure
    }
    return store_prepare_user_exercise_write_statements(store)
}

// Prepare exercise lookup and schema-admission statements on either connection.
store_prepare_user_exercise_read_statements :: proc(store: ^Store) -> Store_Error {
    statements: [9]^sqlite.Statement = {
        &store^.exercise_by_identity,
        &store^.exercise_by_alias,
        &store^.exercise_list_count,
        &store^.exercise_list_rows,
        &store^.retired_exercise_alias,
        &store^.exercise_alias_state,
        &store^.exercise_identity_taken,
        &store^.exercise_rows_for_admission,
        &store^.retired_exercise_rows_for_admission,
    }
    queries: [9]string = {
        EXERCISE_BY_IDENTITY_SQL,
        EXERCISE_BY_ALIAS_SQL,
        EXERCISE_LIST_COUNT_SQL,
        EXERCISE_LIST_ROWS_SQL,
        RETIRED_EXERCISE_ALIAS_SQL,
        EXERCISE_ALIAS_STATE_SQL,
        EXERCISE_IDENTITY_TAKEN_SQL,
        EXERCISE_ROWS_FOR_ADMISSION_SQL,
        RETIRED_EXERCISE_ROWS_FOR_ADMISSION_SQL,
    }
    for index in 0..<len(statements) {
        failure := store_prepare_statement(store, statements[index], queries[index])
        if !store_error_is_clear(failure) {
            return failure
        }
    }
    return {}
}

// Prepare transactional exercise changes on writable connections only.
store_prepare_user_exercise_write_statements :: proc(store: ^Store) -> Store_Error {
    statements: [5]^sqlite.Statement = {
        &store^.exercise_insert,
        &store^.exercise_update,
        &store^.exercise_delete,
        &store^.exercise_retire_alias,
        &store^.exercise_retire_identity,
    }
    queries: [5]string = {
        EXERCISE_INSERT_SQL,
        EXERCISE_UPDATE_SQL,
        EXERCISE_DELETE_SQL,
        EXERCISE_RETIRE_ALIAS_SQL,
        EXERCISE_RETIRE_IDENTITY_SQL,
    }
    for index in 0..<len(statements) {
        failure := store_prepare_statement(store, statements[index], queries[index])
        if !store_error_is_clear(failure) {
            return failure
        }
    }
    return {}
}

// Prepare placement-note writes and orphan cleanup for the writable connection.
store_prepare_note_write_statements :: proc(store: ^Store) -> Store_Error {
    failure := store_prepare_statement(
        store, &store^.upsert_collection_note, UPSERT_COLLECTION_NOTE_SQL)
    if !store_error_is_clear(failure) {
        return failure
    }
    return store_prepare_statement(
        store, &store^.delete_orphan_collection_notes,
        DELETE_ORPHAN_COLLECTION_NOTES_SQL)
}

// Prepare the settings mutation statements for one writable connection.
store_prepare_setting_write_statements :: proc(store: ^Store) -> Store_Error {
    failure := store_prepare_statement(
        store, &store^.upsert_setting, UPSERT_SETTING_SQL)
    if !store_error_is_clear(failure) {
        return failure
    }
    return store_prepare_statement(store, &store^.delete_setting, DELETE_SETTING_SQL)
}

// Prepare collection snapshot mutations for one writable connection.
store_prepare_collection_write_statements :: proc(store: ^Store) -> Store_Error {
    failure := store_prepare_statement(
        store, &store^.insert_collection, INSERT_COLLECTION_SQL)
    if !store_error_is_clear(failure) {
        return failure
    }
    failure = store_prepare_statement(
        store, &store^.insert_collection_entry, INSERT_COLLECTION_ENTRY_SQL)
    if !store_error_is_clear(failure) {
        return failure
    }
    failure = store_prepare_statement(
        store, &store^.delete_collection_entries, DELETE_COLLECTION_ENTRIES_SQL)
    if !store_error_is_clear(failure) {
        return failure
    }
    return store_prepare_statement(
        store, &store^.delete_collections, DELETE_COLLECTIONS_SQL)
}

// Prepare one bounded static query and map schema failures consistently.
store_prepare_statement :: proc(
    store: ^Store, statement: ^sqlite.Statement, sql: string) -> Store_Error {
    failure := sqlite.statement_prepare(
        &store^.connection, statement,
        strings.clone_to_cstring(sql, context.temp_allocator))
    if !store_sqlite_error_is_clear(failure) {
        return {
            kind = .Invalid_Schema,
            sqlite_error = failure,
        }
    }
    return {}
}

// Reset a reusable statement while preserving the first operation failure.
store_reset_preserving :: proc(
    statement: ^sqlite.Statement,
    failure: sqlite.Error) -> sqlite.Error {
    reset_error := sqlite.statement_reset(statement)
    if !store_sqlite_error_is_clear(failure) {
        return failure
    }
    return reset_error
}

// Finalize a temporary statement while retaining its query failure.
store_finalize_preserving :: proc(
    statement: ^sqlite.Statement,
    failure: sqlite.Error) -> sqlite.Error {
    finalize_error := sqlite.statement_finalize(statement)
    if !store_sqlite_error_is_clear(failure) {
        return failure
    }
    return finalize_error
}

// Finalize one owned statement and retain its first teardown error.
store_finalize_owned :: proc(
    store: ^Store, statement: ^sqlite.Statement, failure: ^Store_Error) {
    if statement^.handle == nil {
        return
    }
    finalize_error := sqlite.statement_finalize(statement)
    if !store_sqlite_error_is_clear(finalize_error) && store_error_is_clear(failure^) {
        failure^ = {
            kind = .Finalize,
            sqlite_error = finalize_error,
        }
    }
}

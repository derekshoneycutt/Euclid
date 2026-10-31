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

// Prepare only the known-key statements needed by admitted stores.
store_prepare_statements :: proc(
    store: ^Store, read_only: bool) -> Store_Error {
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
    if read_only {
        return {}
    }
    failure = store_prepare_setting_write_statements(store)
    if !store_error_is_clear(failure) {
        return failure
    }
    return store_prepare_collection_write_statements(store)
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


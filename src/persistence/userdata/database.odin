package userdata

import raw "../../../libs/sqlite3"
import sqlite "../../sqlite"
import collections "../../collections"

import "core:os"
import "core:path/filepath"
import "core:strings"

USER_SETTING_SCHEMA_SQL :: #load("sql/user_setting.sql", string)
USER_COLLECTION_SCHEMA_SQL :: #load("sql/user_collection_schema.sql", string)
USER_TERMINAL_HISTORY_SCHEMA_SQL :: #load("history/sql/user_terminal_history.sql", string)

// Open or safely admit one database at an explicit durable path.
store_open :: proc(store: ^Store, path: string) -> Store_Error {
    return store_open_internal(store, path, false, false)
}

// Open a store with deterministic admission options used only by substrate tests.
store_open_internal :: proc(
    store: ^Store,
    path: string,
    fail_migration_after_schema: bool,
    force_read_only: bool) -> Store_Error {
    if !store_can_open(store) {
        return {
            kind = .Invalid_State,
        }
    }
    absolute_path, path_error := resolve_database_path(path, context.temp_allocator)
    if path_error != .None {
        return {
            kind = .Invalid_Path,
        }
    }
    defer delete(absolute_path, context.temp_allocator)
    if !collections.initialize(&store^.collection_replay_workspace) {
        return {
            kind = .Allocation,
        }
    }
    copy(store^.path[:len(absolute_path)], transmute([]u8)absolute_path)
    store^.path_length = len(absolute_path)
    if !sqlite.threading_supported() {
        return store_abort_open(store, {
            kind = .Sqlite_Threading,
        })
    }
    open_error, read_only := store_open_connection(
        store, absolute_path, force_read_only)
    if !store_error_is_clear(open_error) {
        return store_abort_open(store, open_error)
    }
    store^.status = read_only ? .Read_Only : .Ready
    finalize_error := store_finish_open(
        store, read_only, fail_migration_after_schema)
    if !store_error_is_clear(finalize_error) {
        return store_abort_open(store, finalize_error)
    }
    return {}
}

// Complete schema, statement, and collection admission before publishing the store.
store_finish_open :: proc(
    store: ^Store, read_only, fail_migration_after_schema: bool) -> Store_Error {
    failure := store_admit_database(
        store, read_only, fail_migration_after_schema)
    if !store_error_is_clear(failure) {
        return failure
    }
    failure = store_prepare_statements(store, read_only)
    if !store_error_is_clear(failure) {
        return failure
    }
    return store_verify_collection_admission(store)
}

// Validate that no native resources remain before opening another database.
store_can_open :: proc(store: ^Store) -> bool {
    return store != nil && store^.connection.handle == nil &&
        store^.read_setting.handle == nil && store^.upsert_setting.handle == nil &&
        store^.delete_setting.handle == nil && store^.read_collections.handle == nil &&
        store^.read_collection_entries.handle == nil &&
        store^.insert_collection.handle == nil &&
        store^.insert_collection_entry.handle == nil &&
        store^.delete_collection_entries.handle == nil &&
        store^.delete_collections.handle == nil &&
        !store^.collection_replay_workspace.initialized
}

// Open an explicitly read-only connection and retain the native failure details.
store_open_read_only_connection :: proc(
    store: ^Store, path: string) -> (Store_Error, bool) {
    failure := sqlite.connection_open(
        &store^.connection, path, .Readonly, context.temp_allocator)
    if store_sqlite_error_is_clear(failure) {
        return {}, true
    }
    return {
        kind = .Open,
        sqlite_error = failure,
    }, false
}

// Select read/write access, falling back to read-only only for an existing file.
store_open_connection :: proc(
    store: ^Store, path: string,
    force_read_only: bool) -> (Store_Error, bool) {
    if force_read_only {
        return store_open_read_only_connection(store, path)
    }
    failure := sqlite.connection_open(
        &store^.connection, path, .Readwrite, context.temp_allocator)
    if store_sqlite_error_is_clear(failure) {
        return {}, false
    }
    if store^.connection.handle != nil {
        return {
            kind = .Open,
            sqlite_error = failure,
        }, false
    }
    if os.exists(path) {
        return store_open_read_only_connection(store, path)
    }
    if !store_ensure_parent_directory(path) {
        return {
            kind = .Directory,
        }, false
    }
    failure = sqlite.connection_open(
        &store^.connection, path, .Readwrite_Create, context.temp_allocator)
    if !store_sqlite_error_is_clear(failure) {
        return {
            kind = .Open,
            sqlite_error = failure,
        }, false
    }
    return {}, false
}

// Create the containing directory only after ordinary database admission fails.
store_ensure_parent_directory :: proc(path: string) -> bool {
    parent := filepath.dir(path)
    return len(parent) == 0 || os.is_directory(parent) ||
        os.make_directory_all(parent) == nil
}

// Admit an empty database or verify the stable identity of an existing store.
store_admit_database :: proc(
    store: ^Store, read_only, fail_migration_after_schema: bool) -> Store_Error {
    failure := store_set_busy_timeout(store)
    if !store_sqlite_error_is_clear(failure) {
        return {
            kind = .Open,
            sqlite_error = failure,
        }
    }
    failure = store_enable_foreign_keys(store)
    if !store_sqlite_error_is_clear(failure) {
        return {
            kind = .Open,
            sqlite_error = failure,
        }
    }
    header := store_read_header(store)
    if !store_error_is_clear(header.failure) {
        return header.failure
    }
    if header.application_id == 0 && header.schema_version == 0 &&
        header.user_object_count == 0 {
        return store_initialize_empty_database(
            store, read_only, fail_migration_after_schema, header)
    }
    return store_admit_existing_database(
        store, read_only, fail_migration_after_schema, header)
}

// Admit a known store, applying a transactional migration when the schema is v1.
store_admit_existing_database :: proc(
    store: ^Store,
    read_only, fail_migration_after_schema: bool,
    header: Store_Header) -> Store_Error {
    final_header := header
    identity_error := store_validate_pre_migration_identity(header)
    if !store_error_is_clear(identity_error) {
        return identity_error
    }
    if !read_only {
        pragma_error := store_configure_writable(store)
        if !store_sqlite_error_is_clear(pragma_error) {
            return {
                kind = .Open,
                sqlite_error = pragma_error,
            }
        }
    }
    if final_header.schema_version == 1 {
        migration_error := store_upgrade_legacy_database(
            store, read_only, fail_migration_after_schema, final_header)
        if !store_error_is_clear(migration_error) {
            return migration_error
        }
        final_header = store_read_header(store)
        if !store_error_is_clear(final_header.failure) {
            return final_header.failure
        }
    }
    return store_validate_database_identity(final_header)
}

// Reject unrelated and unsupported schemas before changing connection policy.
store_validate_pre_migration_identity :: proc(
    header: Store_Header) -> Store_Error {
    if header.application_id != DATABASE_APPLICATION_ID {
        return {
            kind = .Wrong_Application,
            application_id = header.application_id,
            schema_version = header.schema_version,
        }
    }
    if header.schema_version > DATABASE_SCHEMA_VERSION {
        return {
            kind = .Future_Schema,
            application_id = header.application_id,
            schema_version = header.schema_version,
        }
    }
    if header.schema_version < 1 {
        return {
            kind = .Unsupported_Schema,
            application_id = header.application_id,
            schema_version = header.schema_version,
        }
    }
    return {}
}

// Upgrade only schema v1, rejecting read-only legacy stores without mutation.
store_upgrade_legacy_database :: proc(
    store: ^Store,
    read_only, fail_migration_after_schema: bool,
    header: Store_Header) -> Store_Error {
    if read_only {
        return {
            kind = .Not_Writable,
            application_id = header.application_id,
            schema_version = header.schema_version,
        }
    }
    return store_migrate_v1_to_v2(store, fail_migration_after_schema)
}

// Initialize only a completely empty writable database.
store_initialize_empty_database :: proc(
    store: ^Store,
    read_only, fail_migration_after_schema: bool,
    header: Store_Header) -> Store_Error {
    if read_only {
        return {
            kind = .Wrong_Application,
            application_id = header.application_id,
            schema_version = header.schema_version,
        }
    }
    pragma_error := store_configure_writable(store)
    if !store_sqlite_error_is_clear(pragma_error) {
        return {
            kind = .Migration,
            sqlite_error = pragma_error,
        }
    }
    return store_initialize_schema(store, fail_migration_after_schema)
}

// Reject database ownership and schema versions without altering the file.
store_validate_database_identity :: proc(header: Store_Header) -> Store_Error {
    if header.application_id != DATABASE_APPLICATION_ID {
        return {
            kind = .Wrong_Application,
            application_id = header.application_id,
            schema_version = header.schema_version,
        }
    }
    if header.schema_version > DATABASE_SCHEMA_VERSION {
        return {
            kind = .Future_Schema,
            application_id = header.application_id,
            schema_version = header.schema_version,
        }
    }
    if header.schema_version != DATABASE_SCHEMA_VERSION {
        return {
            kind = .Unsupported_Schema,
            application_id = header.application_id,
            schema_version = header.schema_version,
        }
    }
    return {}
}

// Enable and verify referential checks on this exclusively owned connection.
store_enable_foreign_keys :: proc(store: ^Store) -> sqlite.Error {
    failure := store_exec(store, "PRAGMA foreign_keys=ON")
    if !store_sqlite_error_is_clear(failure) {
        return failure
    }
    enabled, query_error := store_read_integer_query(
        &store^.connection, "PRAGMA foreign_keys")
    if !store_sqlite_error_is_clear(query_error) {
        return query_error
    }
    if enabled != 1 {
        return sqlite.sqlite_make_validation_error(.Exec, .Invalid_State)
    }
    return {}
}

// Read and validate the database identity, version, and initial emptiness.
store_read_header :: proc(store: ^Store) -> Store_Header {
    application_id, application_error := store_read_integer_query(
        &store^.connection, "PRAGMA application_id")
    if !store_sqlite_error_is_clear(application_error) {
        return {
            failure = {
                kind = .Invalid_Schema,
                sqlite_error = application_error,
            },
        }
    }
    schema_version, version_error := store_read_integer_query(
        &store^.connection, "PRAGMA user_version")
    if !store_sqlite_error_is_clear(version_error) {
        return {
            failure = {
                kind = .Invalid_Schema,
                sqlite_error = version_error,
            },
        }
    }
    object_count, count_error := store_read_integer_query(
        &store^.connection,
        "SELECT COUNT(*) FROM sqlite_schema WHERE name NOT LIKE 'sqlite_%'")
    if !store_sqlite_error_is_clear(count_error) {
        return {
            failure = {
                kind = .Invalid_Schema,
                sqlite_error = count_error,
            },
        }
    }
    return {
        application_id = application_id,
        schema_version = schema_version,
        user_object_count = object_count,
    }
}

// Query exactly one integer row and finalize the temporary statement.
store_read_integer_query :: proc(
    connection: ^sqlite.Connection, sql: string) -> (i64, sqlite.Error) {
    statement: sqlite.Statement
    failure := sqlite.statement_prepare(
        connection, &statement, strings.clone_to_cstring(sql, context.temp_allocator))
    if !store_sqlite_error_is_clear(failure) {
        return 0, failure
    }
    status, step_error := sqlite.statement_step(&statement)
    failure = step_error
    if failure.validation != .None || failure.result != raw.Result.Ok ||
        status != .Row {
        if store_sqlite_error_is_clear(failure) {
            failure = sqlite.sqlite_make_validation_error(.Step, .Invalid_State)
        }
        return 0, store_finalize_preserving(&statement, failure)
    }
    value, column_error := sqlite.column_i64(&statement, 0)
    failure = column_error
    if !store_sqlite_error_is_clear(failure) {
        return 0, store_finalize_preserving(&statement, failure)
    }
    status, failure = sqlite.statement_step(&statement)
    if !store_sqlite_error_is_clear(failure) || status != .Done {
        if store_sqlite_error_is_clear(failure) {
            failure = sqlite.sqlite_make_validation_error(.Step, .Invalid_State)
        }
        return 0, store_finalize_preserving(&statement, failure)
    }
    failure = sqlite.statement_finalize(&statement)
    return value, failure
}

// Apply per-connection zero-wait, rollback-journal, and full-sync policy.
store_configure_writable :: proc(store: ^Store) -> sqlite.Error {
    return store_exec(store,
        "PRAGMA journal_mode=DELETE; PRAGMA synchronous=FULL; PRAGMA busy_timeout=0")
}

// Set zero busy timeout on either admitted connection.
store_set_busy_timeout :: proc(store: ^Store) -> sqlite.Error {
    return store_exec(store, "PRAGMA busy_timeout=0")
}

// Initialize schema and identity atomically for a genuinely empty database.
store_initialize_schema :: proc(
    store: ^Store, fail_after_schema: bool) -> Store_Error {
    begin_error := store_exec(store, "BEGIN IMMEDIATE")
    if !store_sqlite_error_is_clear(begin_error) {
        return {
            kind = .Migration,
            sqlite_error = begin_error,
        }
    }
    failure := store_create_schema_tables(store)
    if store_sqlite_error_is_clear(failure) && fail_after_schema {
        failure = store_exec(store, "CREATE TABLE user_setting(value INTEGER)")
    }
    if store_sqlite_error_is_clear(failure) {
        failure = store_exec(store, "PRAGMA application_id=1163215701")
    }
    if store_sqlite_error_is_clear(failure) {
        failure = store_exec(store, "PRAGMA user_version=2")
    }
    if store_sqlite_error_is_clear(failure) {
        failure = store_exec(store, "COMMIT")
        if store_sqlite_error_is_clear(failure) {
            return {}
        }
    }
    return store_rollback_failure(store, .Migration, failure)
}

// Create the settings, collection, and optional terminal-history tables in order.
store_create_schema_tables :: proc(store: ^Store) -> sqlite.Error {
    statements: [3]string = {
        USER_SETTING_SCHEMA_SQL,
        USER_COLLECTION_SCHEMA_SQL,
        USER_TERMINAL_HISTORY_SCHEMA_SQL,
    }
    for sql in statements {
        failure := sqlite.connection_exec(
            &store^.connection,
            strings.clone_to_cstring(sql, context.temp_allocator))
        if !store_sqlite_error_is_clear(failure) {
            return failure
        }
    }
    return {}
}

// Upgrade settings-only schema v1 atomically without rewriting user preferences.
store_migrate_v1_to_v2 :: proc(
    store: ^Store, fail_after_schema: bool) -> Store_Error {
    begin_error := store_exec(store, "BEGIN IMMEDIATE")
    if !store_sqlite_error_is_clear(begin_error) {
        return {
            kind = .Migration,
            sqlite_error = begin_error,
        }
    }
    failure := sqlite.connection_exec(
        &store^.connection,
        strings.clone_to_cstring(
            USER_COLLECTION_SCHEMA_SQL, context.temp_allocator))
    if store_sqlite_error_is_clear(failure) {
        failure = sqlite.connection_exec(
            &store^.connection,
            strings.clone_to_cstring(
                USER_TERMINAL_HISTORY_SCHEMA_SQL, context.temp_allocator))
    }
    if store_sqlite_error_is_clear(failure) && fail_after_schema {
        failure = store_exec(store, "CREATE TABLE user_setting(value INTEGER)")
    }
    if store_sqlite_error_is_clear(failure) {
        failure = store_exec(store, "PRAGMA user_version=2")
    }
    if store_sqlite_error_is_clear(failure) {
        failure = store_exec(store, "COMMIT")
        if store_sqlite_error_is_clear(failure) {
            return {}
        }
    }
    return store_rollback_failure(store, .Migration, failure)
}

// Execute fixed store-owned SQL and return its structured SQLite failure.
store_exec :: proc(store: ^Store, sql: string) -> sqlite.Error {
    return sqlite.connection_exec(
        &store^.connection, strings.clone_to_cstring(sql, context.temp_allocator))
}

// Roll back one failed transaction and mark the connection unusable on rollback failure.
store_rollback_failure :: proc(
    store: ^Store, kind: Store_Error_Kind, failure: sqlite.Error) -> Store_Error {
    rollback_error := store_exec(store, "ROLLBACK")
    if !store_sqlite_error_is_clear(rollback_error) {
        store^.status = .Unusable
        return {
            kind = kind,
            sqlite_error = failure,
            cleanup_error = rollback_error,
        }
    }
    return {
        kind = kind,
        sqlite_error = failure,
    }
}

// Close all prepared statements and the connection, preserving first cleanup error.
store_close :: proc(store: ^Store) -> Store_Error {
    if store == nil {
        return {
            kind = .Closed,
        }
    }
    failure: Store_Error
    store_finalize_owned(store, &store^.delete_collections, &failure)
    store_finalize_owned(store, &store^.delete_collection_entries, &failure)
    store_finalize_owned(store, &store^.insert_collection_entry, &failure)
    store_finalize_owned(store, &store^.insert_collection, &failure)
    store_finalize_owned(store, &store^.read_collection_entries, &failure)
    store_finalize_owned(store, &store^.read_collections, &failure)
    store_finalize_owned(store, &store^.delete_setting, &failure)
    store_finalize_owned(store, &store^.upsert_setting, &failure)
    store_finalize_owned(store, &store^.read_setting, &failure)
    if store^.connection.handle != nil {
        close_error := sqlite.connection_close(&store^.connection)
        if !store_sqlite_error_is_clear(close_error) && store_error_is_clear(failure) {
            failure = {
                kind = .Close,
                sqlite_error = close_error,
            }
        }
    }
    if store^.connection.handle == nil {
        store^.status = .Closed
    } else {
        store^.status = .Unusable
    }
    collections.destroy(&store^.collection_replay_workspace)
    return failure
}

// Close a rejected open path and preserve both admission and cleanup failures.
store_abort_open :: proc(store: ^Store, failure: Store_Error) -> Store_Error {
    cleanup := store_close(store)
    if store_error_is_clear(failure) {
        return cleanup
    }
    reported := failure
    reported.cleanup_error = cleanup.sqlite_error
    return reported
}

// Distinguish a successful zero-valued SQLite error from a native failure.
store_sqlite_error_is_clear :: proc(failure: sqlite.Error) -> bool {
    return failure.operation == .None && failure.result == raw.Result.Ok &&
        failure.validation == .None
}

// Distinguish a successful store operation from a structured store failure.
store_error_is_clear :: proc(failure: Store_Error) -> bool {
    return failure.kind == .None
}

package userdata

import raw "../../libs/sqlite3"
import sqlite "../sqlite"
import settings "../settings"
import collections "../collections"

import "core:os"
import "core:path/filepath"
import "core:strings"

USER_SETTING_SCHEMA_SQL :: #load("sql/user_setting.sql", string)
USER_COLLECTION_SCHEMA_SQL :: #load("sql/user_collection_schema.sql", string)
READ_SETTING_SQL :: #load("sql/read_setting.sql", string)
UPSERT_SETTING_SQL :: #load("sql/upsert_setting.sql", string)
DELETE_SETTING_SQL :: #load("sql/delete_setting.sql", string)
READ_COLLECTIONS_SQL :: #load("sql/read_collections.sql", string)
READ_COLLECTION_ENTRIES_SQL :: #load("sql/read_collection_entries.sql", string)
INSERT_COLLECTION_SQL :: #load("sql/insert_collection.sql", string)
INSERT_COLLECTION_ENTRY_SQL :: #load("sql/insert_collection_entry.sql", string)
DELETE_COLLECTION_ENTRIES_SQL :: #load("sql/delete_collection_entries.sql", string)
DELETE_COLLECTIONS_SQL :: #load("sql/delete_collections.sql", string)

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
        return {kind = .Invalid_State}
    }
    absolute_path, path_error := resolve_database_path(path, context.temp_allocator)
    if path_error != .None {
        return {kind = .Invalid_Path}
    }
    defer delete(absolute_path, context.temp_allocator)
    copy(store^.path[:len(absolute_path)], transmute([]u8)absolute_path)
    store^.path_length = len(absolute_path)
    if !sqlite.threading_supported() {
        return store_abort_open(store, {kind = .Sqlite_Threading})
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
        store^.delete_collections.handle == nil
}

// Select read/write access, falling back to read-only only for an existing file.
store_open_connection :: proc(
    store: ^Store, path: string, force_read_only: bool) -> (Store_Error, bool) {
    if force_read_only {
        failure := sqlite.connection_open(
            &store^.connection, path, .Readonly, context.temp_allocator)
        if store_sqlite_error_is_clear(failure) {
            return {}, true
        }
        return {kind = .Open, sqlite_error = failure}, false
    }
    failure := sqlite.connection_open(
        &store^.connection, path, .Readwrite, context.temp_allocator)
    if store_sqlite_error_is_clear(failure) {
        return {}, false
    }
    if store^.connection.handle != nil {
        return {kind = .Open, sqlite_error = failure}, false
    }
    if os.exists(path) {
        failure = sqlite.connection_open(
            &store^.connection, path, .Readonly, context.temp_allocator)
        if store_sqlite_error_is_clear(failure) {
            return {}, true
        }
        return {kind = .Open, sqlite_error = failure}, false
    }
    if !store_ensure_parent_directory(path) {
        return {kind = .Directory}, false
    }
    failure = sqlite.connection_open(
        &store^.connection, path, .Readwrite_Create, context.temp_allocator)
    if !store_sqlite_error_is_clear(failure) {
        return {kind = .Open, sqlite_error = failure}, false
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
        return {kind = .Open, sqlite_error = failure}
    }
    failure = store_enable_foreign_keys(store)
    if !store_sqlite_error_is_clear(failure) {
        return {kind = .Open, sqlite_error = failure}
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
            return {kind = .Open, sqlite_error = pragma_error}
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
        return {kind = .Migration, sqlite_error = pragma_error}
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
        return {failure = {kind = .Invalid_Schema, sqlite_error = application_error}}
    }
    schema_version, version_error := store_read_integer_query(
        &store^.connection, "PRAGMA user_version")
    if !store_sqlite_error_is_clear(version_error) {
        return {failure = {kind = .Invalid_Schema, sqlite_error = version_error}}
    }
    object_count, count_error := store_read_integer_query(
        &store^.connection,
        "SELECT COUNT(*) FROM sqlite_schema WHERE name NOT LIKE 'sqlite_%'")
    if !store_sqlite_error_is_clear(count_error) {
        return {failure = {kind = .Invalid_Schema, sqlite_error = count_error}}
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
        return {kind = .Migration, sqlite_error = begin_error}
    }
    failure := sqlite.connection_exec(
        &store^.connection,
        strings.clone_to_cstring(USER_SETTING_SCHEMA_SQL, context.temp_allocator))
    if store_sqlite_error_is_clear(failure) {
        failure = sqlite.connection_exec(
            &store^.connection,
            strings.clone_to_cstring(
                USER_COLLECTION_SCHEMA_SQL, context.temp_allocator))
    }
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

// Upgrade settings-only schema v1 atomically without rewriting user preferences.
store_migrate_v1_to_v2 :: proc(
    store: ^Store, fail_after_schema: bool) -> Store_Error {
    begin_error := store_exec(store, "BEGIN IMMEDIATE")
    if !store_sqlite_error_is_clear(begin_error) {
        return {kind = .Migration, sqlite_error = begin_error}
    }
    failure := sqlite.connection_exec(
        &store^.connection,
        strings.clone_to_cstring(
            USER_COLLECTION_SCHEMA_SQL, context.temp_allocator))
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
        return {kind = .Invalid_Schema, sqlite_error = failure}
    }
    return {}
}

// Load the bounded known settings from one consistent SQLite read snapshot.
store_load_settings :: proc(
    store: ^Store, preferences: ^settings.Preferences) -> Load_Result {
    if store == nil || preferences == nil ||
        (store^.status != .Ready && store^.status != .Read_Only) {
        failure_kind := Store_Error_Kind.Closed
        if store != nil && store^.status == .Unusable {
            failure_kind = .Unusable
        }
        return {failure = {kind = failure_kind}}
    }
    begin_error := store_exec(store, "BEGIN")
    if !store_sqlite_error_is_clear(begin_error) {
        return {failure = {kind = .Read, sqlite_error = begin_error}}
    }
    staged := preferences^
    result := store_collect_known_settings(store, &staged)
    if !store_error_is_clear(result.failure) {
        result.failure = store_rollback_failure(
            store, .Read, result.failure.sqlite_error)
        return result
    }
    commit_error := store_exec(store, "COMMIT")
    if !store_sqlite_error_is_clear(commit_error) {
        result.failure = store_rollback_failure(store, .Read, commit_error)
        return result
    }
    preferences^ = staged
    return result
}

// Read every catalog key into a staged preference snapshot.
store_collect_known_settings :: proc(
    store: ^Store, staged: ^settings.Preferences) -> Load_Result {
    result: Load_Result
    for id in settings.ALL_SETTING_IDS {
        read := store_read_known_setting(store, id)
        if !store_sqlite_error_is_clear(read.failure) {
            result.failure = {kind = .Read, sqlite_error = read.failure}
            return result
        }
        if !read.found {
            continue
        }
        if read.reason != .None ||
            !settings.valid_setting_value(id, read.value) {
            if read.reason == .None {
                read.reason = .Value_Range
            }
            result.invalid_values[result.invalid_count] = {id, read.reason}
            result.invalid_count += 1
            continue
        }
        if !settings.apply_setting_value(staged, id, read.value, .Saved) {
            result.invalid_values[result.invalid_count] = {id, .Value_Range}
            result.invalid_count += 1
        }
    }
    return result
}

// Find one known row and decode its value without retaining SQLite column memory.
store_read_known_setting :: proc(
    store: ^Store,
    id: settings.Setting_Id) -> Setting_Read_Result {
    definition, valid := settings.setting_definition(id)
    if !valid {
        return {
            reason = .Storage_Type,
            failure = sqlite.sqlite_make_validation_error(.Bind, .Invalid_Argument),
        }
    }
    statement := &store^.read_setting
    failure := sqlite.statement_reset(statement)
    if store_sqlite_error_is_clear(failure) {
        failure = sqlite.statement_bind_text(statement, 1, definition.namespace)
    }
    if store_sqlite_error_is_clear(failure) {
        failure = sqlite.statement_bind_text(statement, 2, definition.key)
    }
    if !store_sqlite_error_is_clear(failure) {
        return {
            reason = .Storage_Type,
            failure = store_reset_preserving(statement, failure),
        }
    }
    result := store_fetch_known_row(statement, id)
    result.failure = store_reset_preserving(statement, result.failure)
    return result
}

// Decode one result row and verify the query returns no duplicate match.
store_fetch_known_row :: proc(
    statement: ^sqlite.Statement,
    id: settings.Setting_Id) -> Setting_Read_Result {
    status, failure := sqlite.statement_step(statement)
    if !store_sqlite_error_is_clear(failure) {
        return {reason = .Storage_Type, failure = failure}
    }
    if status == .Done {
        return {reason = .Storage_Type}
    }
    if status != .Row {
        failure = sqlite.sqlite_make_validation_error(.Step, .Invalid_State)
        return {reason = .Storage_Type, failure = failure}
    }
    decoded := store_decode_setting_row(statement, id)
    if !store_sqlite_error_is_clear(decoded.failure) {
        return {reason = decoded.reason, failure = decoded.failure}
    }
    status, failure = sqlite.statement_step(statement)
    if !store_sqlite_error_is_clear(failure) || status != .Done {
        if store_sqlite_error_is_clear(failure) {
            failure = sqlite.sqlite_make_validation_error(.Step, .Invalid_State)
        }
        return {reason = decoded.reason, failure = failure}
    }
    return {
        value = decoded.value,
        found = true,
        reason = decoded.reason,
    }
}

// Decode generic columns into a known setting type, copying text before reset.
store_decode_setting_row :: proc(
    statement: ^sqlite.Statement,
    id: settings.Setting_Id) -> Setting_Value_Read_Result {
    definition, valid := settings.setting_definition(id)
    if !valid {
        return {
            reason = .Storage_Type,
            failure = sqlite.sqlite_make_validation_error(.Column, .Invalid_Argument),
        }
    }
    stored_type := store_read_type_name(statement)
    if !store_sqlite_error_is_clear(stored_type.failure) {
        return {reason = stored_type.reason, failure = stored_type.failure}
    }
    if stored_type.reason != .None {
        return {reason = stored_type.reason}
    }
    if stored_type.kind != definition.storage_kind {
        return {reason = .Storage_Type}
    }
    result := store_read_stored_value(
        statement, id, definition.storage_kind)
    return result
}

// Read the bounded discriminator string from its statement-owned column.
store_read_type_name :: proc(
    statement: ^sqlite.Statement) -> Setting_Storage_Type_Result {
    column_kind := sqlite.column_type(statement, 0)
    if column_kind == .Invalid {
        return {
            kind = .Boolean,
            reason = .Column_Type,
            failure = sqlite.sqlite_make_validation_error(.Column, .Invalid_State),
        }
    }
    if column_kind != .Text {
        return {kind = .Boolean, reason = .Column_Type}
    }
    buffer: [8]u8
    count, failure := sqlite.column_text_copy(statement, 0, buffer[:])
    if !store_sqlite_error_is_clear(failure) {
        if failure.validation == .Capacity {
            return {kind = .Boolean, reason = .Text_Capacity}
        }
        return {kind = .Boolean, reason = .Column_Type, failure = failure}
    }
    switch string(buffer[:count]) {
    case "boolean":
        return {kind = .Boolean}
    case "integer":
        return {kind = .Integer}
    case "text":
        return {kind = .Text}
    }
    return {kind = .Boolean, reason = .Storage_Type}
}

// Map one storage discriminator to its canonical database spelling.
store_value_type_name :: proc(kind: settings.Setting_Storage_Kind) -> string {
    switch kind {
    case .Boolean: return "boolean"
    case .Integer: return "integer"
    case .Text: return "text"
    }
    return ""
}

// Read the exact scalar columns required by a setting's storage definition.
store_read_stored_value :: proc(
    statement: ^sqlite.Statement,
    id: settings.Setting_Id,
    kind: settings.Setting_Storage_Kind) -> Setting_Value_Read_Result {
    switch kind {
    case .Boolean:
        return store_read_boolean(statement)
    case .Integer:
        return store_read_integer(statement)
    case .Text:
        return store_read_enum_text(statement, id)
    }
    return {
        reason = .Storage_Type,
        failure = sqlite.sqlite_make_validation_error(.Column, .Invalid_Argument),
    }
}

// Require an exact boolean integer and a NULL text column.
store_read_boolean :: proc(
    statement: ^sqlite.Statement) -> Setting_Value_Read_Result {
    text_column := sqlite.column_type(statement, 2)
    if text_column == .Invalid {
        return {
            reason = .Column_Type,
            failure = sqlite.sqlite_make_validation_error(.Column, .Invalid_State),
        }
    }
    if text_column != .Null {
        return {reason = .Null_Column}
    }
    value, failure := sqlite.column_i64(statement, 1)
    if !store_sqlite_error_is_clear(failure) {
        return store_column_read_failure(failure)
    }
    if value != 0 && value != 1 {
        return {reason = .Value_Range}
    }
    return {value = settings.boolean_value(value == 1)}
}

// Require an exact integer value and a NULL text column.
store_read_integer :: proc(
    statement: ^sqlite.Statement) -> Setting_Value_Read_Result {
    text_column := sqlite.column_type(statement, 2)
    if text_column == .Invalid {
        return {
            reason = .Column_Type,
            failure = sqlite.sqlite_make_validation_error(.Column, .Invalid_State),
        }
    }
    if text_column != .Null {
        return {reason = .Null_Column}
    }
    value, failure := sqlite.column_i64(statement, 1)
    if !store_sqlite_error_is_clear(failure) {
        return store_column_read_failure(failure)
    }
    converted := int(value)
    if i64(converted) != value {
        return {reason = .Value_Range}
    }
    return {value = settings.integer_value(converted)}
}

// Treat stored-class mismatches as corrupt values and propagate SQLite failures.
store_column_read_failure :: proc(failure: sqlite.Error) -> Setting_Value_Read_Result {
    result := Setting_Value_Read_Result{reason = .Column_Type}
    if failure.validation != .Type_Mismatch {
        result.failure = failure
    }
    return result
}

// Require a bounded text enum and a NULL integer column.
store_read_enum_text :: proc(
    statement: ^sqlite.Statement,
    id: settings.Setting_Id) -> Setting_Value_Read_Result {
    integer_column := sqlite.column_type(statement, 1)
    text_column := sqlite.column_type(statement, 2)
    if integer_column == .Invalid || text_column == .Invalid {
        return {
            reason = .Column_Type,
            failure = sqlite.sqlite_make_validation_error(.Column, .Invalid_State),
        }
    }
    if integer_column != .Null || text_column != .Text {
        return {reason = .Null_Column}
    }
    buffer: [DATABASE_TEXT_MAX_BYTES]u8
    count, failure := sqlite.column_text_copy(statement, 2, buffer[:])
    if !store_sqlite_error_is_clear(failure) {
        if failure.validation == .Capacity {
            return {reason = .Text_Capacity}
        }
        return {reason = .Column_Type, failure = failure}
    }
    return store_decode_enum_text(id, string(buffer[:count]))
}

// Decode one persisted spelling for the application's closed text enums.
store_decode_enum_text :: proc(
    id: settings.Setting_Id, value: string) -> Setting_Value_Read_Result {
    #partial switch id {
    case .Window_Mode:
        switch value {
        case "fixed":
            return {value = settings.window_mode_value(.Fixed)}
        case "resizable":
            return {value = settings.window_mode_value(.Resizable)}
        }
    case .Window_Layout:
        switch value {
        case "auto":
            return {value = settings.layout_preference_value(.Auto)}
        case "landscape":
            return {value = settings.layout_preference_value(.Landscape)}
        case "portrait":
            return {value = settings.layout_preference_value(.Portrait)}
        }
    }
    return {reason = .Unknown_Enum}
}

// Commit a coalesced settings batch in one transaction.
store_commit_batch :: proc(store: ^Store, changes: settings.Change_Set) -> Commit_Result {
    return store_commit_batch_internal(store, changes, -1)
}

// Commit a batch with a deterministic write failure point available to tests.
store_commit_batch_internal :: proc(
    store: ^Store,
    changes: settings.Change_Set,
    fail_after_changes: int) -> Commit_Result {
    return store_commit_user_data_internal(
        store, changes, []collections.Mutation{}, fail_after_changes)
}

// Commit settings and ordered collection mutations on the same store transaction.
store_commit_user_data :: proc(
    store: ^Store,
    changes: settings.Change_Set,
    mutations: []collections.Mutation) -> Commit_Result {
    return store_commit_user_data_internal(store, changes, mutations, -1)
}

// Validate and commit one bounded immutable user-data task payload.
store_commit_user_data_internal :: proc(
    store: ^Store,
    changes: settings.Change_Set,
    mutations: []collections.Mutation,
    fail_after_changes: int) -> Commit_Result {
    if store == nil || store^.status == .Closed {
        return {outcome = .Not_Committed, failure = {kind = .Closed}}
    }
    if store^.status == .Unusable {
        return {outcome = .Store_Unusable, failure = {kind = .Unusable}}
    }
    if !settings.valid_change_set(changes) {
        return {outcome = .Not_Committed, failure = {kind = .Invalid_Batch}}
    }
    if len(mutations) > collections.MUTATION_CAPACITY {
        return {outcome = .Not_Committed, failure = {kind = .Invalid_Batch}}
    }
    if store^.status == .Read_Only {
        return {outcome = .Not_Committed, failure = {kind = .Not_Writable}}
    }
    if changes.count == 0 && len(mutations) == 0 {
        return {outcome = .Committed}
    }
    return store_commit_transaction(store, changes, mutations, fail_after_changes)
}

// Apply and commit one nonempty transaction, rolling back every failed outcome.
store_commit_transaction :: proc(
    store: ^Store,
    changes: settings.Change_Set,
    mutations: []collections.Mutation,
    fail_after_changes: int) -> Commit_Result {
    begin_error := store_exec(store, "BEGIN IMMEDIATE")
    if !store_sqlite_error_is_clear(begin_error) {
        return {
            outcome = .Not_Committed,
            failure = {kind = .Write, sqlite_error = begin_error},
        }
    }
    applied := store_apply_batch_changes(
        store, changes, fail_after_changes)
    if !store_sqlite_error_is_clear(applied.failure) {
        return store_commit_rollback_result(
            store, applied.failure, applied.failed_id, applied.has_failed_id)
    }
    collection_error := store_apply_collection_mutations(store, mutations)
    if !store_sqlite_error_is_clear(collection_error) {
        return store_commit_rollback_result(store, collection_error, {}, false)
    }
    commit_error := store_exec(store, "COMMIT")
    if !store_sqlite_error_is_clear(commit_error) {
        return store_commit_rollback_result(store, commit_error, {}, false)
    }
    return {outcome = .Committed}
}

// Apply each bounded change and preserve the first failing setting identity.
store_apply_batch_changes :: proc(
    store: ^Store,
    changes: settings.Change_Set,
    fail_after_changes: int) -> Batch_Apply_Result {
    for index in 0..<changes.count {
        change := changes.changes[index]
        failure := store_apply_change(store, change)
        if store_sqlite_error_is_clear(failure) &&
            fail_after_changes == index + 1 {
            failure = store_exec(
                store,
                "INSERT INTO user_setting VALUES ('', '', 'boolean', 0, NULL)")
        }
        if !store_sqlite_error_is_clear(failure) {
            return {failure = failure, failed_id = change.id, has_failed_id = true}
        }
    }
    return {}
}

// Apply one prepared Set or Reset operation inside the active transaction.
store_apply_change :: proc(store: ^Store, change: settings.Change) -> sqlite.Error {
    definition, valid := settings.setting_definition(change.id)
    if !valid {
        return sqlite.sqlite_make_validation_error(.Bind, .Invalid_Argument)
    }
    if change.kind == .Reset {
        return store_delete_setting(store, definition)
    }
    if !settings.valid_setting_value(change.id, change.value) {
        return sqlite.sqlite_make_validation_error(.Bind, .Invalid_Argument)
    }
    return store_upsert_setting(store, definition, change.value)
}

// Delete one known preference so its current application default applies.
store_delete_setting :: proc(
    store: ^Store,
    definition: settings.Setting_Definition) -> sqlite.Error {
    statement := &store^.delete_setting
    failure := sqlite.statement_reset(statement)
    if store_sqlite_error_is_clear(failure) {
        failure = sqlite.statement_bind_text(statement, 1, definition.namespace)
    }
    if store_sqlite_error_is_clear(failure) {
        failure = sqlite.statement_bind_text(statement, 2, definition.key)
    }
    if store_sqlite_error_is_clear(failure) {
        status, step_error := sqlite.statement_step(statement)
        failure = step_error
        if store_sqlite_error_is_clear(failure) && status != .Done {
            failure = sqlite.sqlite_make_validation_error(.Step, .Invalid_State)
        }
    }
    return store_reset_preserving(statement, failure)
}

// Upsert one validated typed setting with exact scalar storage columns.
store_upsert_setting :: proc(
    store: ^Store,
    definition: settings.Setting_Definition,
    value: settings.Setting_Value) -> sqlite.Error {
    statement := &store^.upsert_setting
    failure := sqlite.statement_reset(statement)
    if store_sqlite_error_is_clear(failure) {
        failure = sqlite.statement_bind_text(statement, 1, definition.namespace)
    }
    if store_sqlite_error_is_clear(failure) {
        failure = sqlite.statement_bind_text(statement, 2, definition.key)
    }
    if store_sqlite_error_is_clear(failure) {
        failure = sqlite.statement_bind_text(
            statement, 3, store_value_type_name(definition.storage_kind))
    }
    if store_sqlite_error_is_clear(failure) {
        failure = store_bind_setting_value(statement, definition.storage_kind, value)
    }
    if store_sqlite_error_is_clear(failure) {
        status, step_error := sqlite.statement_step(statement)
        failure = step_error
        if store_sqlite_error_is_clear(failure) && status != .Done {
            failure = sqlite.sqlite_make_validation_error(.Step, .Invalid_State)
        }
    }
    return store_reset_preserving(statement, failure)
}

// Bind both value columns according to the catalog's scalar storage kind.
store_bind_setting_value :: proc(
    statement: ^sqlite.Statement,
    kind: settings.Setting_Storage_Kind,
    value: settings.Setting_Value) -> sqlite.Error {
    switch kind {
    case .Boolean:
        integer := i64(0)
        if value.boolean {
            integer = 1
        }
        failure := sqlite.statement_bind_i64(statement, 4, integer)
        if !store_sqlite_error_is_clear(failure) {
            return failure
        }
        return sqlite.statement_bind_null(statement, 5)
    case .Integer:
        failure := sqlite.statement_bind_i64(statement, 4, i64(value.integer))
        if !store_sqlite_error_is_clear(failure) {
            return failure
        }
        return sqlite.statement_bind_null(statement, 5)
    case .Text:
        text := store_enum_text(value)
        failure := sqlite.statement_bind_null(statement, 4)
        if !store_sqlite_error_is_clear(failure) {
            return failure
        }
        return sqlite.statement_bind_text(statement, 5, text)
    }
    return sqlite.sqlite_make_validation_error(.Bind, .Invalid_Argument)
}

// Serialize one closed application enum to its stable durable spelling.
store_enum_text :: proc(value: settings.Setting_Value) -> string {
    switch value.kind {
    case .Boolean, .Integer:
        return ""
    case .Window_Mode:
        if value.window_mode == .Fixed {
            return "fixed"
        }
        if value.window_mode == .Resizable {
            return "resizable"
        }
    case .Layout_Preference:
        switch value.layout {
        case .Auto: return "auto"
        case .Landscape: return "landscape"
        case .Portrait: return "portrait"
        }
    }
    return ""
}

// Preserve the failed write result and report a rollback failure as unusable.
store_commit_rollback_result :: proc(
    store: ^Store,
    failure: sqlite.Error,
    id: settings.Setting_Id,
    has_id: bool) -> Commit_Result {
    store_failure := store_rollback_failure(store, .Write, failure)
    outcome := Commit_Outcome.Not_Committed
    if store^.status == .Unusable {
        outcome = .Store_Unusable
    }
    return {
        outcome = outcome,
        failure = store_failure,
        failed_id = id,
        has_failed_id = has_id,
    }
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
    return {kind = kind, sqlite_error = failure}
}

// Close all prepared statements and the connection, preserving first cleanup error.
store_close :: proc(store: ^Store) -> Store_Error {
    if store == nil {
        return {kind = .Closed}
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
            failure = {kind = .Close, sqlite_error = close_error}
        }
    }
    if store^.connection.handle == nil {
        store^.status = .Closed
    } else {
        store^.status = .Unusable
    }
    return failure
}

// Finalize one owned statement and retain its first teardown error.
store_finalize_owned :: proc(
    store: ^Store, statement: ^sqlite.Statement, failure: ^Store_Error) {
    if statement^.handle == nil {
        return
    }
    finalize_error := sqlite.statement_finalize(statement)
    if !store_sqlite_error_is_clear(finalize_error) && store_error_is_clear(failure^) {
        failure^ = {kind = .Finalize, sqlite_error = finalize_error}
    }
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

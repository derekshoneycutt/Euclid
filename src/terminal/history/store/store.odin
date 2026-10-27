package termhiststore

import protocol "../../../core/protocol"
import sqlite "../../../sqlite"

TERMINAL_HISTORY_SCHEMA_SQL :: #load("sql/schema.sql", string)
TERMINAL_HISTORY_INDEX_SQL :: #load("sql/index.sql", string)
TERMINAL_HISTORY_DURABLE_TABLE_EXISTS_SQL :: #load(
    "sql/durable_table_exists.sql", string)
TERMINAL_HISTORY_INSERT_SQL :: #load("sql/insert.sql", string)
TERMINAL_HISTORY_INSERT_PERSISTENT_SQL :: #load("sql/insert_persistent.sql", string)
TERMINAL_HISTORY_INSERT_LINKED_SESSION_SQL :: #load("sql/insert_linked_session.sql", string)
TERMINAL_HISTORY_UPDATE_SQL :: #load("sql/update.sql", string)
TERMINAL_HISTORY_UPDATE_PERSISTENT_SQL :: #load("sql/update_persistent.sql", string)
TERMINAL_HISTORY_GET_BY_ID_SQL :: #load("sql/get_by_id.sql", string)
TERMINAL_HISTORY_GET_PERSISTENT_BY_ID_SQL :: #load("sql/get_persistent_by_id.sql", string)
TERMINAL_HISTORY_OLDER_SQL :: #load("sql/older.sql", string)
TERMINAL_HISTORY_NEWER_SQL :: #load("sql/newer.sql", string)
TERMINAL_HISTORY_COMBINED_OLDER_SQL :: #load("sql/combined_older.sql", string)
TERMINAL_HISTORY_COMBINED_NEWER_SQL :: #load("sql/combined_newer.sql", string)
TERMINAL_HISTORY_COMBINED_LATEST_SQL :: #load("sql/combined_latest.sql", string)
TERMINAL_HISTORY_DELETE_PERSISTENT_SQL :: #load("sql/delete_persistent.sql", string)
TERMINAL_HISTORY_DELETE_SESSION_SQL :: #load("sql/delete_session.sql", string)

// Initialize the connection-local TEMP table and prepare all store-owned statements.
history_store_init :: proc(
    store: ^History_Store, connection: ^sqlite.Connection) -> History_Store_Error {
    if store == nil || connection == nil || connection.handle == nil ||
       store^.connection != nil || store^.initialized {
        return {
            kind = .Invalid_State,
        }
    }
    store^ = {
        connection = connection,
    }
    failure := history_store_execute_sql(connection, TERMINAL_HISTORY_SCHEMA_SQL)
    if failure.kind != .None {
        store^.connection = nil
        return failure
    }
    failure = history_store_execute_sql(connection, TERMINAL_HISTORY_INDEX_SQL)
    if failure.kind != .None {
        _ = history_store_execute_sql(connection, "DROP TABLE temp.terminal_history;")
        store^.connection = nil
        return failure
    }
    prepare_result := history_store_prepare_all(store)
    if prepare_result.kind == .None {
        store^.initialized = true
        return {}
    }
    prepare_result.cleanup_error = history_store_finalize_statements(store)
    drop_failure := history_store_execute_sql(
        connection, "DROP TABLE temp.terminal_history;")
    if drop_failure.kind != .None &&
       history_store_sqlite_error_is_clear(prepare_result.cleanup_error) {
        prepare_result.cleanup_error = drop_failure.sqlite_error
    }
    store^.connection = nil
    store^.durable_available = false
    return prepare_result
}

// Prepare and execute one fixed SQL string through typed substrate calls.
history_store_execute_sql :: proc(
    connection: ^sqlite.Connection, sql: string) -> History_Store_Error {
    statement: sqlite.Statement
    failure := sqlite.statement_prepare_text(connection, &statement, sql)
    if !history_store_sqlite_error_is_clear(failure) {
        return history_store_error_from_sqlite(failure)
    }
    status, step_failure := sqlite.statement_step(&statement)
    if history_store_sqlite_error_is_clear(step_failure) && status != .Done {
        step_failure = sqlite.sqlite_make_validation_error(.Step, .Invalid_State)
    }
    finalize_failure := sqlite.statement_finalize(&statement)
    result := history_store_error_from_sqlite(step_failure)
    if !history_store_sqlite_error_is_clear(finalize_failure) {
        if result.kind == .None {
            return history_store_error_from_sqlite(finalize_failure)
        }
        result.cleanup_error = finalize_failure
    }
    return result
}

// Prepare each fixed query, stopping at the first failure for ordered cleanup.
history_store_prepare_all :: proc(store: ^History_Store) -> History_Store_Error {
    failure := history_store_prepare_session_statements(store)
    if failure.kind != .None {
        return failure
    }
    return history_store_prepare_persistent_statements(store)
}

// Prepare session-only statements before probing for the optional durable schema.
history_store_prepare_session_statements :: proc(
    store: ^History_Store) -> History_Store_Error {
    failure := history_store_prepare(store, &store^.insert, TERMINAL_HISTORY_INSERT_SQL)
    if failure.kind != .None {
        return failure
    }
    failure = history_store_prepare(store, &store^.update, TERMINAL_HISTORY_UPDATE_SQL)
    if failure.kind != .None {
        return failure
    }
    failure = history_store_prepare(
        store, &store^.get_by_id, TERMINAL_HISTORY_GET_BY_ID_SQL)
    if failure.kind != .None {
        return failure
    }
    failure = history_store_prepare(store, &store^.older, TERMINAL_HISTORY_OLDER_SQL)
    if failure.kind != .None {
        return failure
    }
    failure = history_store_prepare(store, &store^.newer, TERMINAL_HISTORY_NEWER_SQL)
    if failure.kind != .None {
        return failure
    }
    return {}
}

// Prepare durable operations only when the admitted main database owns the table.
history_store_prepare_persistent_statements :: proc(
    store: ^History_Store) -> History_Store_Error {
    exists, exists_failure := history_store_durable_table_exists(store^.connection)
    if exists_failure.kind != .None {
        return exists_failure
    }
    if !exists {
        return {}
    }
    store^.durable_available = true
    failure := history_store_prepare_persistent_row_statements(store)
    if failure.kind != .None {
        return failure
    }
    failure = history_store_prepare_combined_browse_statements(store)
    if failure.kind != .None {
        return failure
    }
    return history_store_prepare_delete_statements(store)
}

// Prepare durable insert, continuation, and identity-read statements.
history_store_prepare_persistent_row_statements :: proc(
    store: ^History_Store) -> History_Store_Error {
    failure := history_store_prepare(
        store, &store^.insert_persistent, TERMINAL_HISTORY_INSERT_PERSISTENT_SQL)
    if failure.kind != .None {
        return failure
    }
    failure = history_store_prepare(
        store, &store^.insert_linked_session, TERMINAL_HISTORY_INSERT_LINKED_SESSION_SQL)
    if failure.kind != .None {
        return failure
    }
    failure = history_store_prepare(
        store, &store^.update_persistent, TERMINAL_HISTORY_UPDATE_PERSISTENT_SQL)
    if failure.kind != .None {
        return failure
    }
    return history_store_prepare(
        store, &store^.get_persistent_by_id, TERMINAL_HISTORY_GET_PERSISTENT_BY_ID_SQL)
}

// Prepare cross-scope browsing statements, which require both schemas.
history_store_prepare_combined_browse_statements :: proc(
    store: ^History_Store) -> History_Store_Error {
    failure := history_store_prepare(
        store, &store^.combined_older, TERMINAL_HISTORY_COMBINED_OLDER_SQL)
    if failure.kind != .None {
        return failure
    }
    failure = history_store_prepare(
        store, &store^.combined_newer, TERMINAL_HISTORY_COMBINED_NEWER_SQL)
    if failure.kind != .None {
        return failure
    }
    return history_store_prepare(
        store, &store^.combined_latest, TERMINAL_HISTORY_COMBINED_LATEST_SQL)
}

// Prepare transactional clear statements for both database scopes.
history_store_prepare_delete_statements :: proc(
    store: ^History_Store) -> History_Store_Error {
    failure := history_store_prepare(
        store, &store^.delete_persistent, TERMINAL_HISTORY_DELETE_PERSISTENT_SQL)
    if failure.kind != .None {
        return failure
    }
    return history_store_prepare(
        store, &store^.delete_session, TERMINAL_HISTORY_DELETE_SESSION_SQL)
}

// Detect the durable user-data table without requiring a writable main database.
history_store_durable_table_exists :: proc(
    connection: ^sqlite.Connection) -> (bool, History_Store_Error) {
    statement: sqlite.Statement
    failure := sqlite.statement_prepare_text(
        connection, &statement, TERMINAL_HISTORY_DURABLE_TABLE_EXISTS_SQL)
    if !history_store_sqlite_error_is_clear(failure) {
        return false, history_store_error_from_sqlite(failure)
    }
    status, step_failure := history_store_step(&statement)
    if step_failure.kind != .None || status != .Row {
        _ = sqlite.statement_finalize(&statement)
        if step_failure.kind != .None {
            return false, step_failure
        }
        return false, {
            kind = .Invalid_Data,
        }
    }
    value, column_failure := sqlite.column_i64(&statement, 0)
    if !history_store_sqlite_error_is_clear(column_failure) {
        _ = sqlite.statement_finalize(&statement)
        return false, history_store_column_error(column_failure)
    }
    finalize_failure := sqlite.statement_finalize(&statement)
    if !history_store_sqlite_error_is_clear(finalize_failure) {
        return false, history_store_error_from_sqlite(finalize_failure)
    }
    if value != 0 && value != 1 {
        return false, {
            kind = .Invalid_Data,
        }
    }
    return value == 1, {}
}

// Prepare one static SQL file through the shared typed SQLite substrate.
history_store_prepare :: proc(
    store: ^History_Store,
    statement: ^sqlite.Statement, sql: string) -> History_Store_Error {
    failure := sqlite.statement_prepare_text(store^.connection, statement, sql)
    if !history_store_sqlite_error_is_clear(failure) {
        return history_store_error_from_sqlite(failure)
    }
    return {}
}

// Finalize every prepared statement without closing or clearing the borrowed connection.
history_store_destroy :: proc(store: ^History_Store) -> History_Store_Error {
    if store == nil {
        return {
            kind = .Invalid_State,
        }
    }
    if store^.connection == nil {
        if !history_store_has_statements(store) {
            return {}
        }
        return {
            kind = .Invalid_State,
        }
    }
    failure := history_store_finalize_statements(store)
    store^.connection = nil
    store^.durable_available = false
    store^.initialized = false
    if !history_store_sqlite_error_is_clear(failure) {
        return history_store_error_from_sqlite(failure)
    }
    return {}
}

// Finalize each live statement and retain the first cleanup failure.
history_store_finalize_statements :: proc(store: ^History_Store) -> sqlite.Error {
    first_failure: sqlite.Error
    history_store_finalize_one(&store^.insert, &first_failure)
    history_store_finalize_one(&store^.insert_persistent, &first_failure)
    history_store_finalize_one(&store^.insert_linked_session, &first_failure)
    history_store_finalize_one(&store^.update, &first_failure)
    history_store_finalize_one(&store^.update_persistent, &first_failure)
    history_store_finalize_one(&store^.get_by_id, &first_failure)
    history_store_finalize_one(&store^.get_persistent_by_id, &first_failure)
    history_store_finalize_one(&store^.older, &first_failure)
    history_store_finalize_one(&store^.newer, &first_failure)
    history_store_finalize_one(&store^.combined_older, &first_failure)
    history_store_finalize_one(&store^.combined_newer, &first_failure)
    history_store_finalize_one(&store^.combined_latest, &first_failure)
    history_store_finalize_one(&store^.delete_persistent, &first_failure)
    history_store_finalize_one(&store^.delete_session, &first_failure)
    return first_failure
}

// Finalize one live statement while preserving the first error from cleanup.
history_store_finalize_one :: proc(
    statement: ^sqlite.Statement, first_failure: ^sqlite.Error) {
    if statement.handle == nil {
        return
    }
    failure := sqlite.statement_finalize(statement)
    if history_store_sqlite_error_is_clear(first_failure^) &&
       !history_store_sqlite_error_is_clear(failure) {
        first_failure^ = failure
    }
}

// Check whether a failed initialization left any native statements to finalize.
history_store_has_statements :: proc(store: ^History_Store) -> bool {
    return store^.insert.handle != nil || store^.update.handle != nil ||
        store^.insert_persistent.handle != nil ||
        store^.insert_linked_session.handle != nil ||
        store^.update_persistent.handle != nil ||
        store^.get_by_id.handle != nil ||
        store^.get_persistent_by_id.handle != nil ||
        store^.older.handle != nil || store^.newer.handle != nil ||
        store^.combined_older.handle != nil ||
        store^.combined_newer.handle != nil ||
        store^.combined_latest.handle != nil ||
        store^.delete_persistent.handle != nil ||
        store^.delete_session.handle != nil
}

// Insert one exact source record without taking ownership of its input bytes.
history_store_insert :: proc(
    store: ^History_Store,
    record: History_Record, source: string) -> History_Write_Result {
    invalid := history_store_validate_record(record)
    if invalid.kind != .None {
        return {
            outcome = .Failed,
            failure = invalid,
        }
    }
    if len(source) > protocol.TERMINAL_RETAINED_TEXT_MAX_BYTES {
        return {
            outcome = .Failed,
            failure = {
                kind = .Capacity,
            },
        }
    }
    if !history_store_ready(store) {
        return history_store_write_failure({
            kind = .Invalid_State,
        })
    }
    statement := &store^.insert
    failure := history_store_begin_statement(statement)
    if failure.kind == .None {
        failure = history_store_bind_record(statement, record, source)
    }
    status := sqlite.Step_Status.Failed
    if failure.kind == .None {
        status, failure = history_store_step(statement)
    }
    if failure.kind == .None && status != .Done {
        failure = {
            kind = .Invalid_Data,
        }
    }
    failure = history_store_reset_after(statement, failure)
    if failure.kind != .None {
        return history_store_write_failure(failure)
    }
    return {
        outcome = .Stored,
    }
}

// Insert a durable record and its linked session row as one connection transaction.
history_store_insert_persistent :: proc(
    store: ^History_Store,
    record: History_Record, source: string) -> History_Write_Result {
    invalid := history_store_validate_record(record)
    if invalid.kind != .None {
        return history_store_write_failure(invalid)
    }
    if len(source) > protocol.TERMINAL_RETAINED_TEXT_MAX_BYTES {
        return history_store_write_failure({
            kind = .Capacity,
        })
    }
    if !history_store_ready(store) || !store^.durable_available {
        return history_store_write_failure({
            kind = .Invalid_State,
        })
    }
    failure := history_store_execute_sql(store^.connection, "BEGIN IMMEDIATE")
    if failure.kind != .None {
        return history_store_write_failure(failure)
    }
    persistent_id: u64
    persistent_id, failure = history_store_insert_persistent_row(
        store, record, source)
    if failure.kind == .None {
        failure = history_store_insert_linked_session_row(
            store, record, persistent_id, source)
    }
    if failure.kind == .None {
        failure = history_store_execute_sql(store^.connection, "COMMIT")
    }
    if failure.kind != .None {
        failure = history_store_rollback(store, failure)
        return history_store_write_failure(failure)
    }
    return {
        outcome = .Stored,
        persistent_entry_id = persistent_id,
    }
}

// Insert one durable source and copy its stable database identity before reset.
history_store_insert_persistent_row :: proc(
    store: ^History_Store,
    record: History_Record, source: string) -> (u64, History_Store_Error) {
    statement := &store^.insert_persistent
    failure := history_store_begin_statement(statement)
    if failure.kind == .None {
        failure = history_store_bind_persistent_record(statement, record, source)
    }
    if failure.kind != .None {
        return 0, history_store_reset_after(statement, failure)
    }
    return history_store_step_returned_identity(statement)
}

// Bind durable row fields with the stable explicit evaluation-mode mapping.
history_store_bind_persistent_record :: proc(
    statement: ^sqlite.Statement,
    record: History_Record, source: string) -> History_Store_Error {
    failure := sqlite_bind_text(statement, 1, source)
    if failure.kind == .None {
        failure = sqlite_bind_i64(statement, 2, history_store_mode_to_i64(record.mode))
    }
    if failure.kind == .None {
        failure = sqlite_bind_i64(statement, 3, record.submitted_at_unix_ms)
    }
    if failure.kind == .None {
        failure = sqlite_bind_i64(statement, 4, i64(record.terminal_generation))
    }
    if failure.kind == .None {
        failure = sqlite_bind_i64(statement, 5, i64(record.source_revision))
    }
    return failure
}

// Copy one RETURNING identity before advancing and resetting its statement.
history_store_step_returned_identity :: proc(
    statement: ^sqlite.Statement) -> (u64, History_Store_Error) {
    failure: History_Store_Error
    status: sqlite.Step_Status
    status, failure = history_store_step(statement)
    if failure.kind == .None && status != .Row {
        failure = {
            kind = .Invalid_Data,
        }
    }
    persistent_id: i64
    if failure.kind == .None {
        persistent_id_value, column_failure := sqlite.column_i64(statement, 0)
        persistent_id = persistent_id_value
        failure = history_store_error_from_sqlite(column_failure)
    }
    if failure.kind == .None && persistent_id <= 0 {
        failure = {
            kind = .Invalid_Data,
        }
    }
    if failure.kind == .None {
        status, failure = history_store_step(statement)
    }
    if failure.kind == .None && status != .Done {
        failure = {
            kind = .Invalid_Data,
        }
    }
    failure = history_store_reset_after(statement, failure)
    if failure.kind != .None {
        return 0, failure
    }
    return u64(persistent_id), {}
}

// Insert the TEMP representation with its durable duplicate-suppression identity.
history_store_insert_linked_session_row :: proc(
    store: ^History_Store, record: History_Record,
    persistent_id: u64, source: string) -> History_Store_Error {
    statement := &store^.insert_linked_session
    failure := history_store_begin_statement(statement)
    values: [7]i64 = {
        i64(record.submission_id),
        i64(persistent_id),
        0,
        history_store_mode_to_i64(record.mode),
        record.submitted_at_unix_ms,
        i64(record.terminal_generation),
        i64(record.source_revision),
    }
    for index in 0..<len(values) {
        if failure.kind != .None {
            break
        }
        if index == 2 {
            failure = sqlite_bind_text(statement, index + 1, source)
        } else {
            failure = sqlite_bind_i64(statement, index + 1, values[index])
        }
    }
    status := sqlite.Step_Status.Failed
    if failure.kind == .None {
        status, failure = history_store_step(statement)
    }
    if failure.kind == .None && status != .Done {
        failure = {
            kind = .Invalid_Data,
        }
    }
    return history_store_reset_after(statement, failure)
}

// Update source and mode only when the stored revision matches the caller's expectation.
history_store_update_expected :: proc(
    store: ^History_Store, request: History_Update_Request) -> History_Write_Result {
    invalid := history_store_validate_update_request(request)
    if invalid.kind != .None {
        return history_store_write_failure(invalid)
    }
    if len(request.source) > protocol.TERMINAL_RETAINED_TEXT_MAX_BYTES {
        return history_store_write_failure({
            kind = .Capacity,
        })
    }
    if !history_store_ready(store) {
        return history_store_write_failure({
            kind = .Invalid_State,
        })
    }
    if request.persistent_entry_id == 0 {
        return history_store_update_row(store, request)
    }
    if !store^.durable_available {
        return history_store_write_failure({
            kind = .Invalid_State,
        })
    }
    return history_store_update_persistent_pair(store, request)
}

// Validate the stable session and durable identities plus the revision transition.
history_store_validate_update_request :: proc(
    request: History_Update_Request) -> History_Store_Error {
    invalid := history_store_validate_identity(request.submission_id)
    if invalid.kind == .None {
        invalid = history_store_validate_revision(request.expected_revision)
    }
    if invalid.kind == .None {
        invalid = history_store_validate_revision(request.new_revision)
    }
    if invalid.kind == .None && request.new_revision <= request.expected_revision {
        invalid = {
            kind = .Invalid_Argument,
        }
    }
    if invalid.kind == .None && !history_store_mode_valid(request.mode) {
        invalid = {
            kind = .Invalid_Argument,
        }
    }
    if invalid.kind == .None &&
       request.persistent_entry_id > u64(max(i64)) {
        invalid = {
            kind = .Integer_Range,
        }
    }
    return invalid
}

// Commit a linked continuation only after both expected-revision writes succeed.
history_store_update_persistent_pair :: proc(
    store: ^History_Store, request: History_Update_Request) -> History_Write_Result {
    failure := history_store_execute_sql(store^.connection, "BEGIN IMMEDIATE")
    if failure.kind != .None {
        return history_store_write_failure(failure)
    }
    session_result := history_store_update_row(store, request)
    failure = history_store_update_result_failure(session_result)
    if failure.kind == .None {
        persistent_result := history_store_update_persistent_row(store, request)
        failure = history_store_update_result_failure(persistent_result)
    }
    if failure.kind == .None {
        failure = history_store_execute_sql(store^.connection, "COMMIT")
    }
    if failure.kind != .None {
        return history_store_write_failure(history_store_rollback(store, failure))
    }
    return {
        outcome = .Updated,
        persistent_entry_id = request.persistent_entry_id,
    }
}

// Convert a conditional update outcome to the transaction's error contract.
history_store_update_result_failure :: proc(
    result: History_Write_Result) -> History_Store_Error {
    if result.outcome == .Conflict {
        return {
            kind = .Conflict,
        }
    }
    if result.outcome != .Updated {
        return result.failure
    }
    return {}
}

// Update the durable continuation only when its expected revision still matches.
history_store_update_persistent_row :: proc(
    store: ^History_Store, request: History_Update_Request) -> History_Write_Result {
    statement := &store^.update_persistent
    failure := history_store_begin_statement(statement)
    if failure.kind == .None {
        failure = sqlite_bind_text(statement, 1, request.source)
    }
    if failure.kind == .None {
        failure = sqlite_bind_i64(statement, 2, history_store_mode_to_i64(request.mode))
    }
    if failure.kind == .None {
        failure = sqlite_bind_i64(statement, 3, i64(request.new_revision))
    }
    if failure.kind == .None {
        failure = sqlite_bind_i64(statement, 4, i64(request.persistent_entry_id))
    }
    if failure.kind == .None {
        failure = sqlite_bind_i64(statement, 5, i64(request.expected_revision))
    }
    status := sqlite.Step_Status.Failed
    if failure.kind == .None {
        status, failure = history_store_step(statement)
    }
    return history_store_complete_update(statement, status, failure)
}

// Execute the conditional update and distinguish a revision conflict from SQLite failure.
history_store_update_row :: proc(
    store: ^History_Store, request: History_Update_Request) -> History_Write_Result {
    statement := &store^.update
    failure := history_store_begin_statement(statement)
    if failure.kind == .None {
        failure = sqlite_bind_text(statement, 1, request.source)
    }
    if failure.kind == .None {
        failure = sqlite_bind_i64(statement, 2, history_store_mode_to_i64(request.mode))
    }
    if failure.kind == .None {
        failure = sqlite_bind_i64(statement, 3, i64(request.new_revision))
    }
    if failure.kind == .None {
        failure = sqlite_bind_i64(statement, 4, i64(request.submission_id))
    }
    if failure.kind == .None {
        failure = sqlite_bind_i64(statement, 5, i64(request.expected_revision))
    }
    status := sqlite.Step_Status.Failed
    if failure.kind == .None {
        status, failure = history_store_step(statement)
    }
    return history_store_complete_update(statement, status, failure)
}

// Finish one expected-revision update and require exactly one returned identity.
history_store_complete_update :: proc(
    statement: ^sqlite.Statement, status: sqlite.Step_Status,
    failure: History_Store_Error) -> History_Write_Result {
    outcome := History_Write_Outcome.Updated
    completed_failure := failure
    if failure.kind == .None && status == .Done {
        outcome = .Conflict
    } else if failure.kind == .None && status == .Row {
        next_status, next_failure := history_store_step(statement)
        if next_failure.kind != .None {
            completed_failure = next_failure
        } else if next_status != .Done {
            completed_failure = {
                kind = .Invalid_Data,
            }
        }
    } else if failure.kind == .None {
        completed_failure = {
            kind = .Invalid_Data,
        }
    }
    completed_failure = history_store_reset_after(statement, completed_failure)
    if completed_failure.kind != .None {
        return history_store_write_failure(completed_failure)
    }
    return {
        outcome = outcome,
    }
}

// Read one row by identity, returning a copied source and metadata.
history_store_get_by_id :: proc(
    store: ^History_Store,
    submission_id: u64, destination: []u8) -> History_Read_Result {
    if store == nil {
        return history_store_read_failure({
            kind = .Invalid_State,
        })
    }
    return history_store_read_one(
        store, &store^.get_by_id, submission_id, destination, .Not_Found)
}

// Read one durable row by stable database identity.
history_store_get_persistent_by_id :: proc(
    store: ^History_Store,
    persistent_entry_id: u64, destination: []u8) -> History_Read_Result {
    if store == nil || !store^.durable_available {
        return history_store_read_failure({
            kind = .Invalid_State,
        })
    }
    result := history_store_read_one(
        store, &store^.get_persistent_by_id, persistent_entry_id,
        destination, .Not_Found)
    if result.outcome == .Found {
        result.record.submission_id = 0
    }
    return result
}

// Read the closest older record using the submission sequence as order.
history_store_older :: proc(
    store: ^History_Store,
    submission_id: u64, destination: []u8) -> History_Read_Result {
    if store == nil {
        return history_store_read_failure({
            kind = .Invalid_State,
        })
    }
    return history_store_read_one(
        store, &store^.older, submission_id, destination, .Boundary)
}

// Read the closest newer record using the submission sequence as order.
history_store_newer :: proc(
    store: ^History_Store,
    submission_id: u64, destination: []u8) -> History_Read_Result {
    if store == nil {
        return history_store_read_failure({
            kind = .Invalid_State,
        })
    }
    return history_store_read_one(
        store, &store^.newer, submission_id, destination, .Boundary)
}

// Read the closest older record from the ordered union of session and saved rows.
history_store_combined_older :: proc(
    store: ^History_Store,
    cursor: History_Browse_Cursor, destination: []u8) -> History_Read_Result {
    return history_store_read_combined(
        store, &store^.combined_older, cursor, destination)
}

// Read the closest newer record from the ordered union of session and saved rows.
history_store_combined_newer :: proc(
    store: ^History_Store,
    cursor: History_Browse_Cursor, destination: []u8) -> History_Read_Result {
    return history_store_read_combined(
        store, &store^.combined_newer, cursor, destination)
}

// Read the newest row from the ordered union without loading either source list.
history_store_combined_latest :: proc(
    store: ^History_Store, destination: []u8) -> History_Read_Result {
    if store == nil || !store^.durable_available || !history_store_ready(store) {
        return history_store_read_failure({
            kind = .Invalid_State,
        })
    }
    statement := &store^.combined_latest
    failure := history_store_begin_statement(statement)
    result: History_Read_Result
    if failure.kind == .None {
        result = history_store_read_statement_row(statement, destination, .Not_Found)
        failure = result.failure
    }
    failure = history_store_reset_after(statement, failure)
    if failure.kind != .None {
        return history_store_read_failure(failure)
    }
    return result
}

// Bind one tuple cursor and decode the next unique combined record.
history_store_read_combined :: proc(
    store: ^History_Store, statement: ^sqlite.Statement,
    cursor: History_Browse_Cursor, destination: []u8) -> History_Read_Result {
    if store == nil || !store^.durable_available ||
       cursor.submitted_at_unix_ms < 0 ||
       cursor.source_id == 0 || cursor.source_id > u64(max(i64)) ||
       history_store_scope_to_i64(cursor.scope) < 0 {
        return history_store_read_failure({
            kind = .Invalid_Argument,
        })
    }
    if !history_store_ready(store) {
        return history_store_read_failure({
            kind = .Invalid_State,
        })
    }
    failure := history_store_begin_statement(statement)
    if failure.kind == .None {
        failure = sqlite_bind_i64(statement, 1, cursor.submitted_at_unix_ms)
    }
    if failure.kind == .None {
        failure = sqlite_bind_i64(statement, 2, history_store_scope_to_i64(cursor.scope))
    }
    if failure.kind == .None {
        failure = sqlite_bind_i64(statement, 3, i64(cursor.source_id))
    }
    result: History_Read_Result
    if failure.kind == .None {
        result = history_store_read_statement_row(statement, destination, .Boundary)
        failure = result.failure
    }
    failure = history_store_reset_after(statement, failure)
    if failure.kind != .None {
        return history_store_read_failure(failure)
    }
    return result
}

// Delete all durable and session rows without changing prompt state.
history_store_clear :: proc(store: ^History_Store) -> History_Clear_Result {
    if !history_store_ready(store) || !store^.durable_available {
        return {
            outcome = .Failed,
            failure = {
                kind = .Invalid_State,
            },
        }
    }
    failure := history_store_execute_sql(store^.connection, "BEGIN IMMEDIATE")
    if failure.kind == .None {
        failure = history_store_execute_statement(&store^.delete_persistent)
    }
    if failure.kind == .None {
        failure = history_store_execute_statement(&store^.delete_session)
    }
    if failure.kind == .None {
        failure = history_store_execute_sql(store^.connection, "COMMIT")
    }
    if failure.kind != .None {
        return {
            outcome = .Failed,
            failure = history_store_rollback(store, failure),
        }
    }
    return {
        outcome = .Cleared,
    }
}

// Execute one prepared no-parameter mutation and reset it for reuse.
history_store_execute_statement :: proc(
    statement: ^sqlite.Statement) -> History_Store_Error {
    failure := history_store_begin_statement(statement)
    status := sqlite.Step_Status.Failed
    if failure.kind == .None {
        status, failure = history_store_step(statement)
    }
    if failure.kind == .None && status != .Done {
        failure = {
            kind = .Invalid_Data,
        }
    }
    return history_store_reset_after(statement, failure)
}

// Roll back an active mutation while preserving its original failure.
history_store_rollback :: proc(
    store: ^History_Store, failure: History_Store_Error) -> History_Store_Error {
    rollback_failure := history_store_execute_sql(store^.connection, "ROLLBACK")
    if rollback_failure.kind == .None {
        return failure
    }
    result := failure
    result.cleanup_error = rollback_failure.sqlite_error
    return result
}

// Bind an identity, copy a single row, and reset its prepared query.
history_store_read_one :: proc(
    store: ^History_Store, statement: ^sqlite.Statement, submission_id: u64,
    destination: []u8, empty_outcome: History_Read_Outcome) -> History_Read_Result {
    invalid := history_store_validate_identity(submission_id)
    if invalid.kind != .None {
        return history_store_read_failure(invalid)
    }
    if !history_store_ready(store) {
        return history_store_read_failure({
            kind = .Invalid_State,
        })
    }
    failure := history_store_begin_statement(statement)
    if failure.kind == .None {
        failure = history_store_error_from_sqlite(
            sqlite.statement_bind_i64(statement, 1, i64(submission_id)))
    }
    result: History_Read_Result = {
        outcome = empty_outcome,
    }
    if failure.kind == .None {
        result = history_store_read_statement_row(statement, destination, empty_outcome)
        failure = result.failure
    }
    failure = history_store_reset_after(statement, failure)
    if failure.kind != .None {
        result.outcome = .Failed
        result.failure = failure
        return result
    }
    return result
}

// Decode an optional single row and require the query to finish after that row.
history_store_read_statement_row :: proc(
    statement: ^sqlite.Statement, destination: []u8,
    empty_outcome: History_Read_Outcome) -> History_Read_Result {
    status, failure := history_store_step(statement)
    if failure.kind != .None {
        return history_store_read_failure(failure)
    }
    if status == .Done {
        return {
            outcome = empty_outcome,
        }
    }
    if status != .Row {
        return history_store_read_failure({
            kind = .Invalid_Data,
        })
    }
    result := history_store_decode_row(statement, destination)
    if result.failure.kind != .None {
        return result
    }
    status, failure = history_store_step(statement)
    if failure.kind != .None {
        return history_store_read_failure(failure)
    }
    if status != .Done {
        return history_store_read_failure({
            kind = .Invalid_Data,
        })
    }
    return result
}

// Decode one SQLite row and copy source bytes before the statement is reset.
history_store_decode_row :: proc(
    statement: ^sqlite.Statement, destination: []u8) -> History_Read_Result {
    result := history_store_decode_row_metadata(statement)
    if result.outcome != .Found {
        return result
    }
    copied_length, copy_failure := sqlite.column_text_copy(
        statement, 1, destination)
    if !history_store_sqlite_error_is_clear(copy_failure) {
        result.outcome = .Failed
        result.failure = history_store_column_error(copy_failure)
        return result
    }
    if copied_length != result.source_length {
        return history_store_read_failure({
            kind = .Invalid_Data,
        })
    }
    return result
}

// Decode and validate all non-source columns for one history row.
history_store_decode_row_metadata :: proc(
    statement: ^sqlite.Statement) -> History_Read_Result {
    values: [9]i64
    column_indices: [8]int = {0, 2, 3, 4, 5, 6, 7, 8}
    for value_index in 0..<len(column_indices) {
        column_index := column_indices[value_index]
        value, column_failure := sqlite.column_i64(statement, column_index)
        if !history_store_sqlite_error_is_clear(column_failure) {
            return history_store_read_failure(
                history_store_column_error(column_failure))
        }
        values[column_index] = value
    }
    source_length_value, length_failure := sqlite.column_i64(statement, 9)
    if !history_store_sqlite_error_is_clear(length_failure) ||
       source_length_value < 0 || source_length_value > i64(max(int)) {
        return history_store_read_failure({
            kind = .Invalid_Data,
        })
    }
    mode, mode_valid := history_store_mode_from_i64(values[3])
    scope, scope_valid := history_store_scope_from_i64(values[7])
    if values[0] < 0 || values[2] < 0 || values[4] < 0 ||
       values[5] <= 0 || values[6] <= 0 || values[8] <= 0 ||
       !scope_valid || !mode_valid {
        return history_store_read_failure({
            kind = .Invalid_Data,
        })
    }
    return {
        outcome = .Found,
        record = history_store_record_from_values(values, mode, scope),
        source_length = int(source_length_value),
    }
}

// Convert the nine validated SQL integer columns into a typed record.
history_store_record_from_values :: proc(
    values: [9]i64, mode: protocol.Evaluation_Mode,
    scope: History_Record_Scope) -> History_Record {
    return {
        submission_id = u64(values[0]),
        persistent_entry_id = u64(values[2]),
        scope = scope,
        source_id = u64(values[8]),
        mode = mode,
        submitted_at_unix_ms = values[4],
        terminal_generation = u64(values[5]),
        source_revision = u64(values[6]),
    }
}

// Encode the fixed scope tie-break order used by combined browsing.
history_store_scope_to_i64 :: proc(scope: History_Record_Scope) -> i64 {
    switch scope {
    case .Session:
        return 0
    case .Persistent:
        return 1
    }
    return -1
}

// Decode only the two scopes represented by the combined store query.
history_store_scope_from_i64 :: proc(
    value: i64) -> (History_Record_Scope, bool) {
    switch value {
    case 0:
        return .Session, true
    case 1:
        return .Persistent, true
    }
    return .Session, false
}

// Validate an insert record before narrowing its unsigned fields to SQLite integers.
history_store_validate_record :: proc(record: History_Record) -> History_Store_Error {
    failure := history_store_validate_identity(record.submission_id)
    if failure.kind == .None {
        failure = history_store_validate_generation(record.terminal_generation)
    }
    if failure.kind == .None {
        failure = history_store_validate_revision(record.source_revision)
    }
    if failure.kind == .None && record.submitted_at_unix_ms < 0 {
        failure = {
            kind = .Invalid_Argument,
        }
    }
    if failure.kind == .None && !history_store_mode_valid(record.mode) {
        failure = {
            kind = .Invalid_Argument,
        }
    }
    return failure
}

// Reject zero or out-of-range launch-local identifiers.
history_store_validate_identity :: proc(value: u64) -> History_Store_Error {
    if value == 0 {
        return {
            kind = .Invalid_Argument,
        }
    }
    if value > u64(max(i64)) {
        return {
            kind = .Integer_Range,
        }
    }
    return {}
}

// Reject zero or out-of-range terminal generations.
history_store_validate_generation :: proc(value: u64) -> History_Store_Error {
    if value == 0 {
        return {
            kind = .Invalid_Argument,
        }
    }
    if value > u64(max(i64)) {
        return {
            kind = .Integer_Range,
        }
    }
    return {}
}

// Reject zero or out-of-range source revisions.
history_store_validate_revision :: proc(value: u64) -> History_Store_Error {
    if value == 0 {
        return {
            kind = .Invalid_Argument,
        }
    }
    if value > u64(max(i64)) {
        return {
            kind = .Integer_Range,
        }
    }
    return {}
}

// Accept only protocol modes with defined Terminal history semantics.
history_store_mode_valid :: proc(mode: protocol.Evaluation_Mode) -> bool {
    switch mode {
    case .Normal, .Help, .Pkg, .Shell:
        return true
    }
    return false
}

// Encode the stable database contract independently from enum declaration order.
history_store_mode_to_i64 :: proc(mode: protocol.Evaluation_Mode) -> i64 {
    switch mode {
    case .Normal:
        return 0
    case .Help:
        return 1
    case .Pkg:
        return 2
    case .Shell:
        return 3
    }
    return -1
}

// Decode an SQLite mode integer without accepting unknown enum values.
history_store_mode_from_i64 :: proc(
    value: i64) -> (protocol.Evaluation_Mode, bool) {
    switch value {
    case 0:
        return .Normal, true
    case 1:
        return .Help, true
    case 2:
        return .Pkg, true
    case 3:
        return .Shell, true
    }
    return .Normal, false
}

// Bind one validated record and its exact source bytes.
history_store_bind_record :: proc(
    statement: ^sqlite.Statement,
    record: History_Record, source: string) -> History_Store_Error {
    failure := sqlite_bind_i64(statement, 1, i64(record.submission_id))
    if failure.kind == .None {
        failure = sqlite_bind_text(statement, 2, source)
    }
    if failure.kind == .None {
        failure = sqlite_bind_i64(statement, 3, history_store_mode_to_i64(record.mode))
    }
    if failure.kind == .None {
        failure = sqlite_bind_i64(statement, 4, record.submitted_at_unix_ms)
    }
    if failure.kind == .None {
        failure = sqlite_bind_i64(statement, 5, i64(record.terminal_generation))
    }
    if failure.kind == .None {
        failure = sqlite_bind_i64(statement, 6, i64(record.source_revision))
    }
    return failure
}

// Reset a statement before binding the next operation's parameters.
history_store_begin_statement :: proc(
    statement: ^sqlite.Statement) -> History_Store_Error {
    failure := sqlite.statement_reset(statement)
    if !history_store_sqlite_error_is_clear(failure) {
        return history_store_error_from_sqlite(failure)
    }
    return {}
}

// Reset an operation statement while preserving its primary failure.
history_store_reset_after :: proc(
    statement: ^sqlite.Statement, failure: History_Store_Error) -> History_Store_Error {
    reset_failure := sqlite.statement_reset(statement)
    if history_store_sqlite_error_is_clear(reset_failure) {
        return failure
    }
    if failure.kind == .None {
        return history_store_error_from_sqlite(reset_failure)
    }
    result := failure
    result.cleanup_error = reset_failure
    return result
}

// Advance a statement and translate substrate outcomes into store errors.
history_store_step :: proc(
    statement: ^sqlite.Statement) -> (sqlite.Step_Status, History_Store_Error) {
    status, failure := sqlite.statement_step(statement)
    if !history_store_sqlite_error_is_clear(failure) {
        return status, history_store_error_from_sqlite(failure)
    }
    if status == .Failed {
        return status, {
            kind = .Invalid_Data,
        }
    }
    return status, {}
}

// Convert a statement binding error into the store's typed error contract.
sqlite_bind_i64 :: proc(
    statement: ^sqlite.Statement, index: int, value: i64) -> History_Store_Error {
    return history_store_error_from_sqlite(
        sqlite.statement_bind_i64(statement, index, value))
}

// Bind exact UTF-8 source bytes and translate any substrate failure.
sqlite_bind_text :: proc(
    statement: ^sqlite.Statement, index: int, value: string) -> History_Store_Error {
    return history_store_error_from_sqlite(
        sqlite.statement_bind_text(statement, index, value))
}

// Map column capacity and malformed typed data to explicit store errors.
history_store_column_error :: proc(failure: sqlite.Error) -> History_Store_Error {
    if failure.validation == .Capacity {
        return {
            kind = .Capacity,
            sqlite_error = failure,
        }
    }
    if failure.validation != .None {
        return {
            kind = .Invalid_Data,
            sqlite_error = failure,
        }
    }
    return history_store_error_from_sqlite(failure)
}

// Translate one SQLite substrate error without discarding its native details.
history_store_error_from_sqlite :: proc(failure: sqlite.Error) -> History_Store_Error {
    if history_store_sqlite_error_is_clear(failure) {
        return {}
    }
    if failure.validation == .Invalid_State {
        return {
            kind = .Invalid_State,
            sqlite_error = failure,
        }
    }
    if failure.validation != .None {
        return {
            kind = .Invalid_Argument,
            sqlite_error = failure,
        }
    }
    return {
        kind = .Sqlite,
        sqlite_error = failure,
    }
}

// Return whether one substrate error represents success.
history_store_sqlite_error_is_clear :: proc(failure: sqlite.Error) -> bool {
    return failure.validation == .None && failure.result == .Ok
}

// Verify a store is initialized and still borrows a live connection.
history_store_ready :: proc(store: ^History_Store) -> bool {
    return store != nil && store^.initialized && store^.connection != nil &&
        store^.connection.handle != nil
}

// Wrap a failed write in its typed outcome.
history_store_write_failure :: proc(
    failure: History_Store_Error) -> History_Write_Result {
    outcome := History_Write_Outcome.Failed
    if failure.kind == .Conflict {
        outcome = .Conflict
    }
    return {
        outcome = outcome,
        failure = failure,
    }
}

// Wrap a failed read without returning success-shaped metadata.
history_store_read_failure :: proc(
    failure: History_Store_Error) -> History_Read_Result {
    return {
        outcome = .Failed,
        failure = failure,
    }
}

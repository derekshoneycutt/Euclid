package termhiststore

import protocol "../../../core/protocol"
import sqlite "../../../sqlite"

TERMINAL_HISTORY_SCHEMA_SQL :: #load("sql/schema.sql", string)
TERMINAL_HISTORY_INSERT_SQL :: #load("sql/insert.sql", string)
TERMINAL_HISTORY_UPDATE_SQL :: #load("sql/update.sql", string)
TERMINAL_HISTORY_GET_BY_ID_SQL :: #load("sql/get_by_id.sql", string)
TERMINAL_HISTORY_OLDER_SQL :: #load("sql/older.sql", string)
TERMINAL_HISTORY_NEWER_SQL :: #load("sql/newer.sql", string)

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
    return history_store_prepare(store, &store^.newer, TERMINAL_HISTORY_NEWER_SQL)
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
    history_store_finalize_one(&store^.update, &first_failure)
    history_store_finalize_one(&store^.get_by_id, &first_failure)
    history_store_finalize_one(&store^.older, &first_failure)
    history_store_finalize_one(&store^.newer, &first_failure)
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
        store^.get_by_id.handle != nil || store^.older.handle != nil ||
        store^.newer.handle != nil
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

// Update source and mode only when the stored revision matches the caller's expectation.
history_store_update_expected :: proc(
    store: ^History_Store, request: History_Update_Request) -> History_Write_Result {
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
    return history_store_update_row(store, request)
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
        failure = sqlite_bind_i64(statement, 2, i64(request.mode))
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
    values: [6]i64
    column_indices: [5]int = {0, 2, 3, 4, 5}
    for value_index in 0..<len(column_indices) {
        column_index := column_indices[value_index]
        value, column_failure := sqlite.column_i64(statement, column_index)
        if !history_store_sqlite_error_is_clear(column_failure) {
            return history_store_read_failure(
                history_store_column_error(column_failure))
        }
        values[column_index] = value
    }
    source_length_value, length_failure := sqlite.column_i64(statement, 6)
    if !history_store_sqlite_error_is_clear(length_failure) ||
       source_length_value < 0 || source_length_value > i64(max(int)) {
        return history_store_read_failure({
            kind = .Invalid_Data,
        })
    }
    mode, mode_valid := history_store_mode_from_i64(values[2])
    if values[0] <= 0 || values[4] <= 0 || values[5] <= 0 || !mode_valid {
        return history_store_read_failure({
            kind = .Invalid_Data,
        })
    }
    return {
        outcome = .Found,
        record = history_store_record_from_values(values, mode),
        source_length = int(source_length_value),
    }
}

// Convert the six validated SQL integer columns into a typed record.
history_store_record_from_values :: proc(
    values: [6]i64, mode: protocol.Evaluation_Mode) -> History_Record {
    return {
        submission_id = u64(values[0]),
        mode = mode,
        submitted_at_unix_ms = values[3],
        terminal_generation = u64(values[4]),
        source_revision = u64(values[5]),
    }
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

// Decode an SQLite mode integer without accepting unknown enum values.
history_store_mode_from_i64 :: proc(
    value: i64) -> (protocol.Evaluation_Mode, bool) {
    if value < 0 || value > i64(protocol.Evaluation_Mode.Shell) {
        return .Normal, false
    }
    mode := protocol.Evaluation_Mode(value)
    return mode, history_store_mode_valid(mode)
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
        failure = sqlite_bind_i64(statement, 3, i64(record.mode))
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

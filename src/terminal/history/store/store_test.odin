#+test
package termhiststore

import protocol "../../../core/protocol"
import sqlite "../../../sqlite"
import raw "../../../../libs/sqlite3"

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:testing"

History_Store_Test_Path :: struct {
    directory: string,
    path: string,
    valid: bool,
}

// Create a reusable record with explicit test metadata.
history_store_test_record :: proc(
    id: u64, mode: protocol.Evaluation_Mode, timestamp: i64,
    generation, revision: u64) -> History_Record {
    return {
        submission_id = id,
        mode = mode,
        submitted_at_unix_ms = timestamp,
        terminal_generation = generation,
        source_revision = revision,
    }
}

// Create one connection-local store in SQLite's in-memory database.
history_store_test_open_memory :: proc(
    t: ^testing.T, connection: ^sqlite.Connection, store: ^History_Store) -> bool {
    failure := sqlite.connection_open(
        connection, ":memory:", .Readwrite_Create, context.temp_allocator)
    testing.expect_value(t, failure.validation, sqlite.Validation_Error.None)
    testing.expect_value(t, failure.result, raw.Result.Ok)
    if connection.handle == nil {
        return false
    }
    store_failure := history_store_init(store, connection)
    testing.expect_value(t, store_failure.kind, History_Store_Error_Kind.None)
    return store_failure.kind == .None
}

// Create an isolated file path for read-only-main and connection-lifetime tests.
history_store_test_path :: proc(t: ^testing.T) -> History_Store_Test_Path {
    result: History_Store_Test_Path
    temporary_directory, directory_error := os.temp_directory(context.temp_allocator)
    if directory_error != nil {
        return result
    }
    directory_name := fmt.tprintf("euclid-termhist-%x", uintptr(t))
    result.directory, _ = filepath.join(
        []string{temporary_directory, directory_name}, context.temp_allocator)
    if len(result.directory) == 0 ||
       os.make_directory_all(result.directory) != nil {
        return result
    }
    result.path, _ = filepath.join(
        []string{result.directory, "fixture.sqlite3"}, context.temp_allocator)
    result.valid = len(result.path) > 0
    return result
}

// Read one scalar integer through the typed SQLite helpers.
history_store_test_integer_query :: proc(
    t: ^testing.T, connection: ^sqlite.Connection, sql: string) -> (i64, bool) {
    statement: sqlite.Statement
    failure := sqlite.statement_prepare_text(connection, &statement, sql)
    testing.expect_value(t, failure.validation, sqlite.Validation_Error.None)
    if failure.validation != .None || failure.result != .Ok {
        return 0, false
    }
    status: sqlite.Step_Status
    status, failure = sqlite.statement_step(&statement)
    if failure.validation != .None || status != .Row {
        _ = sqlite.statement_finalize(&statement)
        return 0, false
    }
    value: i64
    value, failure = sqlite.column_i64(&statement, 0)
    if failure.validation != .None {
        _ = sqlite.statement_finalize(&statement)
        return 0, false
    }
    status, failure = sqlite.statement_step(&statement)
    if failure.validation != .None || status != .Done {
        _ = sqlite.statement_finalize(&statement)
        return 0, false
    }
    failure = sqlite.statement_finalize(&statement)
    return value, failure.validation == .None && failure.result == .Ok
}

// Execute one fixed test statement using no SQL-string allocation.
history_store_test_exec :: proc(
    connection: ^sqlite.Connection, sql: string) -> bool {
    statement: sqlite.Statement
    failure := sqlite.statement_prepare_text(connection, &statement, sql)
    if failure.validation != .None || failure.result != raw.Result.Ok {
        return false
    }
    status: sqlite.Step_Status
    status, failure = sqlite.statement_step(&statement)
    if failure.validation == .None && status != .Done {
        failure = sqlite.sqlite_make_validation_error(
            .Step, sqlite.Validation_Error.Invalid_State)
    }
    finalize_failure := sqlite.statement_finalize(&statement)
    if failure.validation == .None && failure.result == raw.Result.Ok {
        failure = finalize_failure
    }
    return failure.validation == .None && failure.result == raw.Result.Ok
}

// Verify duplicate source identities, chronological ordering, and navigation bounds.
@(test)
history_store_distinguishes_duplicate_sources_and_orders_by_identity :: proc(
    t: ^testing.T) {
    connection: sqlite.Connection
    store: History_Store
    if !history_store_test_open_memory(t, &connection, &store) {
        return
    }
    defer _ = sqlite.connection_close(&connection)
    defer _ = history_store_destroy(&store)

    source := "x += 1\nα"
    first := history_store_test_record(4, .Normal, 900, 2, 1)
    second := history_store_test_record(9, .Shell, 100, 3, 1)
    testing.expect_value(t, history_store_insert(&store, first, source).outcome,
        History_Write_Outcome.Stored)
    testing.expect_value(t, history_store_insert(&store, second, source).outcome,
        History_Write_Outcome.Stored)

    destination: [32]u8
    older := history_store_older(&store, 9, destination[:])
    testing.expect_value(t, older.outcome, History_Read_Outcome.Found)
    testing.expect_value(t, older.record.submission_id, u64(4))
    testing.expect_value(t, older.record.submitted_at_unix_ms, i64(900))
    testing.expect_value(t, older.source_length, len(source))
    testing.expect_value(t, string(destination[:older.source_length]), source)
    newer := history_store_newer(&store, 4, destination[:])
    testing.expect_value(t, newer.outcome, History_Read_Outcome.Found)
    testing.expect_value(t, newer.record.submission_id, u64(9))
    testing.expect_value(t, newer.record.mode, protocol.Evaluation_Mode.Shell)
    testing.expect_value(t, history_store_older(&store, 4, destination[:]).outcome,
        History_Read_Outcome.Boundary)
    testing.expect_value(t, history_store_newer(&store, 9, destination[:]).outcome,
        History_Read_Outcome.Boundary)
    testing.expect_value(t, history_store_get_by_id(&store, 77, destination[:]).outcome,
        History_Read_Outcome.Not_Found)
}

// Verify expected-revision updates preserve identity metadata and reject stale writers.
@(test)
history_store_updates_only_the_expected_revision :: proc(t: ^testing.T) {
    connection: sqlite.Connection
    store: History_Store
    if !history_store_test_open_memory(t, &connection, &store) {
        return
    }
    defer _ = sqlite.connection_close(&connection)
    defer _ = history_store_destroy(&store)

    record := history_store_test_record(1, .Normal, 4321, 7, 1)
    testing.expect_value(t, history_store_insert(&store, record, "start").outcome,
        History_Write_Outcome.Stored)
    update_request: History_Update_Request = {
        submission_id = 1,
        expected_revision = 1,
        new_revision = 3,
        mode = .Pkg,
        source = "begin\nfinish",
    }
    update := history_store_update_expected(&store, update_request)
    testing.expect_value(t, update.outcome, History_Write_Outcome.Updated)
    history_store_expect_revision_conflicts(t, &store)
    history_store_expect_updated_record(t, &store)
}

// Verify stale revisions and unknown identities are reported as conflicts.
history_store_expect_revision_conflicts :: proc(
    t: ^testing.T, store: ^History_Store) {
    stale_request: History_Update_Request = {
        submission_id = 1,
        expected_revision = 1,
        new_revision = 4,
        mode = .Shell,
        source = "stale",
    }
    missing_request: History_Update_Request = {
        submission_id = 99,
        expected_revision = 1,
        new_revision = 2,
        mode = .Shell,
        source = "missing",
    }
    testing.expect_value(t,
        history_store_update_expected(store, stale_request).outcome,
        History_Write_Outcome.Conflict)
    testing.expect_value(t,
        history_store_update_expected(store, missing_request).outcome,
        History_Write_Outcome.Conflict)
}

// Check that a stale update left the committed continuation metadata and source intact.
history_store_expect_updated_record :: proc(
    t: ^testing.T, store: ^History_Store) {
    destination: [32]u8
    read := history_store_get_by_id(store, 1, destination[:])
    testing.expect_value(t, read.outcome, History_Read_Outcome.Found)
    testing.expect_value(t, read.record.mode, protocol.Evaluation_Mode.Pkg)
    testing.expect_value(t, read.record.submitted_at_unix_ms, i64(4321))
    testing.expect_value(t, read.record.terminal_generation, u64(7))
    testing.expect_value(t, read.record.source_revision, u64(3))
    testing.expect_value(t, string(destination[:read.source_length]), "begin\nfinish")
}

// Verify exact-capacity copies, oversized destinations, and no partial truncation.
@(test)
history_store_copies_exact_capacity_without_truncation :: proc(t: ^testing.T) {
    connection: sqlite.Connection
    store: History_Store
    if !history_store_test_open_memory(t, &connection, &store) {
        return
    }
    defer _ = sqlite.connection_close(&connection)
    defer _ = history_store_destroy(&store)

    source: [protocol.TERMINAL_RETAINED_TEXT_MAX_BYTES]u8
    for index in 0..<len(source) {
        source[index] = u8('x')
    }
    record := history_store_test_record(1, .Help, 0, 1, 1)
    testing.expect_value(t,
        history_store_insert(&store, record, string(source[:])).outcome,
        History_Write_Outcome.Stored)

    destination: [protocol.TERMINAL_RETAINED_TEXT_MAX_BYTES]u8
    exact := history_store_get_by_id(&store, 1, destination[:])
    testing.expect_value(t, exact.outcome, History_Read_Outcome.Found)
    testing.expect_value(t, exact.source_length, len(source))
    testing.expect_value(t, destination, source)

    small: [8]u8
    small = [8]u8{'u', 'n', 't', 'o', 'u', 'c', 'h', 'e'}
    too_small := history_store_get_by_id(&store, 1, small[:])
    testing.expect_value(t, too_small.outcome, History_Read_Outcome.Failed)
    testing.expect_value(t, too_small.failure.kind, History_Store_Error_Kind.Capacity)
    testing.expect_value(t, too_small.source_length, len(source))
    testing.expect_value(t, small, [8]u8{'u', 'n', 't', 'o', 'u', 'c', 'h', 'e'})
    testing.expect_value(t, history_store_get_by_id(&store, 1, destination[:]).outcome,
        History_Read_Outcome.Found)
}

// Verify explicit validation of IDs, mode values, source capacity, and bad stored data.
@(test)
history_store_rejects_invalid_records_and_modes :: proc(t: ^testing.T) {
    connection: sqlite.Connection
    store: History_Store
    if !history_store_test_open_memory(t, &connection, &store) {
        return
    }
    defer _ = sqlite.connection_close(&connection)
    defer _ = history_store_destroy(&store)

    zero_id := history_store_test_record(0, .Normal, 0, 1, 1)
    zero_result := history_store_insert(&store, zero_id, "zero")
    testing.expect_value(t,
        zero_result.failure.kind, History_Store_Error_Kind.Invalid_Argument)
    invalid_mode := history_store_test_record(
        1, protocol.Evaluation_Mode(99), 0, 1, 1)
    mode_result := history_store_insert(&store, invalid_mode, "bad mode")
    testing.expect_value(t,
        mode_result.failure.kind, History_Store_Error_Kind.Invalid_Argument)

    record := history_store_test_record(1, .Normal, 0, 1, 1)
    testing.expect_value(t, history_store_insert(&store, record, "source").outcome,
        History_Write_Outcome.Stored)
    testing.expect(t, history_store_test_exec(
        &connection, "UPDATE temp.terminal_history SET mode=99 WHERE submission_id=1;"))
    destination: [16]u8
    invalid_read := history_store_get_by_id(&store, 1, destination[:])
    testing.expect_value(t, invalid_read.outcome, History_Read_Outcome.Failed)
    testing.expect_value(t,
        invalid_read.failure.kind, History_Store_Error_Kind.Invalid_Data)
}

// Verify TEMP writes work on a read-only main database and vanish when its connection closes.
@(test)
history_store_temp_lifetime_is_the_connection :: proc(t: ^testing.T) {
    fixture := history_store_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)

    history_store_temp_lifetime_readonly_case(t, fixture.path)
    history_store_temp_lifetime_reopen_case(t, fixture.path)
}

// Prove a read-only main database can host writable TEMP history without closing the borrow.
history_store_temp_lifetime_readonly_case :: proc(
    t: ^testing.T, path: string) {
    created: sqlite.Connection
    failure := sqlite.connection_open(
        &created, path, .Readwrite_Create, context.temp_allocator)
    testing.expect_value(t, failure.result, raw.Result.Ok)
    testing.expect_value(t, sqlite.connection_close(&created).result, raw.Result.Ok)

    readonly: sqlite.Connection
    failure = sqlite.connection_open(
        &readonly, path, .Readonly, context.temp_allocator)
    testing.expect_value(t, failure.result, raw.Result.Ok)
    if failure.result != raw.Result.Ok {
        return
    }
    store: History_Store
    store_failure := history_store_init(&store, &readonly)
    testing.expect_value(t, store_failure.kind, History_Store_Error_Kind.None)
    if store_failure.kind != .None {
        _ = sqlite.connection_close(&readonly)
        return
    }
    record := history_store_test_record(1, .Shell, 99, 1, 1)
    testing.expect_value(t, history_store_insert(&store, record, "echo hi").outcome,
        History_Write_Outcome.Stored)
    object_count, count_valid := history_store_test_integer_query(
        t, &readonly,
        "SELECT count(*) FROM main.sqlite_schema WHERE name='terminal_history';")
    testing.expect(t, count_valid)
    testing.expect_value(t, object_count, i64(0))
    testing.expect(t, readonly.handle != nil)
    testing.expect_value(t, history_store_destroy(&store).kind,
        History_Store_Error_Kind.None)
    testing.expect_value(t, sqlite.connection_close(&readonly).result, raw.Result.Ok)
}

// Reopen the file and verify records vanished with their original connection.
history_store_temp_lifetime_reopen_case :: proc(
    t: ^testing.T, path: string) {
    reopened: sqlite.Connection
    failure := sqlite.connection_open(
        &reopened, path, .Readonly, context.temp_allocator)
    testing.expect_value(t, failure.result, raw.Result.Ok)
    if failure.result != raw.Result.Ok {
        return
    }
    reopened_store: History_Store
    store_failure := history_store_init(&reopened_store, &reopened)
    testing.expect_value(t, store_failure.kind, History_Store_Error_Kind.None)
    if store_failure.kind != .None {
        _ = sqlite.connection_close(&reopened)
        return
    }
    destination: [16]u8
    testing.expect_value(t,
        history_store_get_by_id(&reopened_store, 1, destination[:]).outcome,
        History_Read_Outcome.Not_Found)
    testing.expect_value(t, history_store_destroy(&reopened_store).kind,
        History_Store_Error_Kind.None)
    testing.expect_value(t, sqlite.connection_close(&reopened).result, raw.Result.Ok)
}

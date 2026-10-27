#+test
package termhiststore

import protocol "../../../core/protocol"
import sqlite "../../../sqlite"
import raw "../../../../libs/sqlite3"

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:testing"

HISTORY_STORE_TEST_DURABLE_SCHEMA_SQL :: #load(
    "../../../userdata/sql/user_terminal_history.sql", string)

History_Store_Test_Path :: struct {
    directory: string,
    path: string,
    valid: bool,
}

// The clear's ordinary rollback is verified with the production main journal policy.
@(test)
history_store_clear_rolls_back_under_delete_journal :: proc(t: ^testing.T) {
    fixture := history_store_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)

    connection: sqlite.Connection
    open_failure := sqlite.connection_open(
        &connection, fixture.path, .Readwrite_Create, context.temp_allocator)
    testing.expect(t, history_store_sqlite_error_is_clear(open_failure))
    if !history_store_sqlite_error_is_clear(open_failure) {
        return
    }
    defer _ = sqlite.connection_close(&connection)
    history_store_test_prepare_durable_main(t, &connection)

    store: History_Store
    testing.expect_value(t, history_store_init(&store, &connection).kind,
        History_Store_Error_Kind.None)
    defer _ = history_store_destroy(&store)
    inserted := history_store_insert_persistent(
        &store, history_store_test_record(8, .Help, 88, 1, 1), "retained")
    testing.expect_value(t, inserted.outcome, History_Write_Outcome.Stored)

    journal_mode: [16]u8
    journal_length, journal_valid := history_store_test_text_query(
        t, &connection, "PRAGMA main.journal_mode", journal_mode[:])
    testing.expect(t, journal_valid)
    testing.expect_value(t, string(journal_mode[:journal_length]), "delete")
    testing.expect(t, history_store_test_exec(&connection,
        "CREATE TEMP TRIGGER reject_terminal_history_clear "+
        "BEFORE DELETE ON terminal_history BEGIN "+
        "SELECT RAISE(ABORT, 'injected clear failure'); END;"))
    testing.expect_value(t, history_store_clear(&store).outcome,
        History_Clear_Outcome.Failed)

    history_store_test_expect_both_rows(
        t, &store, 8, inserted.persistent_entry_id, History_Read_Outcome.Found)
}

// Assert the session and durable row survive one failed clear transaction.
history_store_test_expect_both_rows :: proc(
    t: ^testing.T, store: ^History_Store, submission_id, persistent_id: u64,
    expected: History_Read_Outcome) {
    destination: [16]u8
    testing.expect_value(t,
        history_store_get_by_id(store, submission_id, destination[:]).outcome, expected)
    testing.expect_value(t,
        history_store_get_persistent_by_id(
            store, persistent_id, destination[:]).outcome, expected)
}

// Configure the durable fixture using the production DELETE journal policy.
history_store_test_prepare_durable_main :: proc(
    t: ^testing.T, connection: ^sqlite.Connection) {
    testing.expect(t, history_store_sqlite_error_is_clear(sqlite.connection_exec(
        connection, "PRAGMA journal_mode=DELETE; PRAGMA synchronous=FULL")))
    testing.expect_value(t,
        history_store_execute_sql(
            connection, HISTORY_STORE_TEST_DURABLE_SCHEMA_SQL).kind,
        History_Store_Error_Kind.None)
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
    schema_failure := history_store_execute_sql(
        connection, HISTORY_STORE_TEST_DURABLE_SCHEMA_SQL)
    testing.expect_value(t, schema_failure.kind, History_Store_Error_Kind.None)
    if schema_failure.kind != .None {
        return false
    }
    store_failure := history_store_init(store, connection)
    testing.expect_value(t, store_failure.kind, History_Store_Error_Kind.None)
    return store_failure.kind == .None
}

// Durable insert, linked continuation update, and persistent read preserve identity.
@(test)
history_store_persistent_rows_link_to_session_and_update_together :: proc(
    t: ^testing.T) {
    connection: sqlite.Connection
    store: History_Store
    if !history_store_test_open_memory(t, &connection, &store) {
        return
    }
    defer _ = sqlite.connection_close(&connection)
    defer _ = history_store_destroy(&store)

    record := history_store_test_record(11, .Shell, 5678, 4, 1)
    inserted := history_store_insert_persistent(&store, record, "echo α")
    testing.expect_value(t, inserted.outcome, History_Write_Outcome.Stored)
    testing.expect(t, inserted.persistent_entry_id > 0)
    history_store_test_expect_linked_identity(
        t, &store, inserted.persistent_entry_id)
    history_store_test_expect_linked_update(
        t, &store, inserted.persistent_entry_id)
}

// Verify both representations retain the same inserted durable identity and data.
history_store_test_expect_linked_identity :: proc(
    t: ^testing.T, store: ^History_Store, persistent_id: u64) {
    destination: [32]u8
    session := history_store_get_by_id(store, 11, destination[:])
    testing.expect_value(t, session.outcome, History_Read_Outcome.Found)
    testing.expect_value(t, session.record.persistent_entry_id, persistent_id)
    testing.expect_value(t, session.record.scope, History_Record_Scope.Session)
    testing.expect_value(t, string(destination[:session.source_length]), "echo α")
    durable := history_store_get_persistent_by_id(store, persistent_id, destination[:])
    testing.expect_value(t, durable.outcome, History_Read_Outcome.Found)
    testing.expect_value(t, durable.record.submission_id, u64(0))
    testing.expect_value(t, durable.record.scope, History_Record_Scope.Persistent)
    testing.expect_value(t, durable.record.mode, protocol.Evaluation_Mode.Shell)
    testing.expect_value(t, durable.record.submitted_at_unix_ms, i64(5678))
    testing.expect_value(t, string(destination[:durable.source_length]), "echo α")
}

// Verify a paired continuation updates both rows to the same mode and revision.
history_store_test_expect_linked_update :: proc(
    t: ^testing.T, store: ^History_Store, persistent_id: u64) {
    update: History_Update_Request = {
        submission_id = 11,
        persistent_entry_id = persistent_id,
        expected_revision = 1,
        new_revision = 2,
        mode = .Pkg,
        source = "begin\nfinish",
    }
    testing.expect_value(t,
        history_store_update_expected(store, update).outcome,
        History_Write_Outcome.Updated)
    destination: [32]u8
    session := history_store_get_by_id(store, 11, destination[:])
    durable := history_store_get_persistent_by_id(store, persistent_id, destination[:])
    testing.expect_value(t, session.record.source_revision, u64(2))
    testing.expect_value(t, durable.record.source_revision, u64(2))
    testing.expect_value(t, durable.record.mode, protocol.Evaluation_Mode.Pkg)
    testing.expect_value(t, string(destination[:durable.source_length]), "begin\nfinish")
}

// A TEMP-side insert failure does not leave an orphan durable submission.
@(test)
history_store_persistent_insert_rolls_back_without_session_pair :: proc(
    t: ^testing.T) {
    connection: sqlite.Connection
    store: History_Store
    if !history_store_test_open_memory(t, &connection, &store) {
        return
    }
    defer _ = sqlite.connection_close(&connection)
    defer _ = history_store_destroy(&store)

    testing.expect(t, history_store_test_exec(&connection,
        "CREATE TEMP TRIGGER reject_terminal_history_insert "+
        "BEFORE INSERT ON terminal_history BEGIN "+
        "SELECT RAISE(ABORT, 'injected insert failure'); END;"))
    result := history_store_insert_persistent(
        &store, history_store_test_record(5, .Normal, 55, 1, 1), "atomic")
    testing.expect_value(t, result.outcome, History_Write_Outcome.Failed)
    durable_count, durable_valid := history_store_test_integer_query(
        t, &connection, "SELECT COUNT(*) FROM main.user_terminal_history")
    session_count, session_valid := history_store_test_integer_query(
        t, &connection, "SELECT COUNT(*) FROM temp.terminal_history")
    testing.expect(t, durable_valid && session_valid)
    testing.expect_value(t, durable_count, i64(0))
    testing.expect_value(t, session_count, i64(0))
}

// A durable revision conflict rolls back the preceding TEMP continuation update.
@(test)
history_store_linked_update_conflict_rolls_back_session_revision :: proc(
    t: ^testing.T) {
    connection: sqlite.Connection
    store: History_Store
    if !history_store_test_open_memory(t, &connection, &store) {
        return
    }
    defer _ = sqlite.connection_close(&connection)
    defer _ = history_store_destroy(&store)

    inserted := history_store_insert_persistent(
        &store, history_store_test_record(5, .Normal, 55, 1, 1), "before")
    testing.expect_value(t, inserted.outcome, History_Write_Outcome.Stored)
    testing.expect(t, history_store_test_exec(&connection,
        "UPDATE main.user_terminal_history SET source='external', source_revision=2;"))
    update: History_Update_Request = {
        submission_id = 5,
        persistent_entry_id = inserted.persistent_entry_id,
        expected_revision = 1,
        new_revision = 3,
        mode = .Shell,
        source = "after",
    }
    testing.expect_value(t,
        history_store_update_expected(&store, update).outcome,
        History_Write_Outcome.Conflict)
    destination: [16]u8
    session := history_store_get_by_id(&store, 5, destination[:])
    testing.expect_value(t, session.record.source_revision, u64(1))
    testing.expect_value(t, string(destination[:session.source_length]), "before")
}

// Keep all four stored modes independent from protocol enum declaration order.
@(test)
history_store_persistent_mode_ordinals_are_explicit :: proc(t: ^testing.T) {
    connection: sqlite.Connection
    store: History_Store
    if !history_store_test_open_memory(t, &connection, &store) {
        return
    }
    defer _ = sqlite.connection_close(&connection)
    defer _ = history_store_destroy(&store)

    modes: [4]protocol.Evaluation_Mode = {
        .Normal,
        .Help,
        .Pkg,
        .Shell,
    }
    for index in 0..<len(modes) {
        record := history_store_test_record(
            u64(index + 1), modes[index], i64(index), 1, 1)
        inserted := history_store_insert_persistent(
            &store, record, "mode")
        testing.expect_value(t, inserted.outcome, History_Write_Outcome.Stored)
        destination: [8]u8
        read := history_store_get_persistent_by_id(
            &store, inserted.persistent_entry_id, destination[:])
        testing.expect_value(t, read.outcome, History_Read_Outcome.Found)
        testing.expect_value(t, read.record.mode, modes[index])
        stored_mode, valid := history_store_test_integer_query(
            t, &connection,
            fmt.tprintf("SELECT mode FROM main.user_terminal_history WHERE entry_id=%d",
                i64(index + 1)))
        testing.expect(t, valid)
        testing.expect_value(t, stored_mode, i64(index))
    }
}

// Combined navigation orders unique session and durable-only rows by stable tuples.
@(test)
history_store_combined_browse_suppresses_linked_rows_and_orders_ties :: proc(
    t: ^testing.T) {
    connection: sqlite.Connection
    store: History_Store
    if !history_store_test_open_memory(t, &connection, &store) {
        return
    }
    defer _ = sqlite.connection_close(&connection)
    defer _ = history_store_destroy(&store)

    linked := history_store_insert_persistent(
        &store, history_store_test_record(1, .Normal, 100, 1, 1), "linked")
    testing.expect_value(t, linked.outcome, History_Write_Outcome.Stored)
    testing.expect(t, history_store_test_exec(&connection,
        "INSERT INTO main.user_terminal_history "+
        "(source, mode, submitted_at_unix_ms, terminal_generation, source_revision) "+
        "VALUES ('saved tie', 1, 100, 2, 1), ('saved older', 2, 90, 3, 1);"))
    testing.expect_value(t,
        history_store_insert(
            &store, history_store_test_record(2, .Help, 80, 4, 1), "session").
            outcome,
        History_Write_Outcome.Stored)

    destination: [32]u8
    older_cursor := history_store_test_expect_combined_head(
        t, &store, destination[:])
    history_store_test_expect_combined_round_trip(
        t, &store, older_cursor, destination[:])
}

// Verify the initial row and tied session-before-persistent ordering.
history_store_test_expect_combined_head :: proc(
    t: ^testing.T, store: ^History_Store, destination: []u8) ->
        History_Browse_Cursor {
    latest := history_store_combined_latest(store, destination)
    testing.expect_value(t, latest.outcome, History_Read_Outcome.Found)
    testing.expect_value(t, latest.record.scope, History_Record_Scope.Session)
    testing.expect_value(t, latest.record.submission_id, u64(1))
    cursor := history_store_test_cursor(latest.record)
    first_older := history_store_combined_older(store, cursor, destination)
    testing.expect_value(t, first_older.outcome, History_Read_Outcome.Found)
    testing.expect_value(t, first_older.record.scope, History_Record_Scope.Persistent)
    testing.expect_value(t, first_older.record.persistent_entry_id, u64(2))
    testing.expect_value(t, string(destination[:first_older.source_length]), "saved tie")
    return history_store_test_cursor(first_older.record)
}

// Verify older traversal and its inverse skip the linked durable duplicate.
history_store_test_expect_combined_round_trip :: proc(
    t: ^testing.T, store: ^History_Store,
    cursor: History_Browse_Cursor, destination: []u8) {
    browse_cursor := cursor
    second_older := history_store_combined_older(store, browse_cursor, destination)
    testing.expect_value(t, second_older.outcome, History_Read_Outcome.Found)
    testing.expect_value(t, second_older.record.persistent_entry_id, u64(3))
    testing.expect_value(t, string(destination[:second_older.source_length]), "saved older")

    browse_cursor = history_store_test_cursor(second_older.record)
    nearest_newer := history_store_combined_newer(store, browse_cursor, destination)
    testing.expect_value(t, nearest_newer.outcome, History_Read_Outcome.Found)
    testing.expect_value(t, nearest_newer.record.persistent_entry_id, u64(2))
    browse_cursor = history_store_test_cursor(nearest_newer.record)
    nearest_newer = history_store_combined_newer(store, browse_cursor, destination)
    testing.expect_value(t, nearest_newer.outcome, History_Read_Outcome.Found)
    testing.expect_value(t, nearest_newer.record.submission_id, u64(1))
}

// Capture the tuple needed to continue cross-scope browsing.
history_store_test_cursor :: proc(record: History_Record) -> History_Browse_Cursor {
    return {
        submitted_at_unix_ms = record.submitted_at_unix_ms,
        scope = record.scope,
        source_id = record.source_id,
    }
}

// A failure after the durable delete rolls the whole clear back across both scopes.
@(test)
history_store_clear_rolls_back_both_scopes_on_session_failure :: proc(
    t: ^testing.T) {
    connection: sqlite.Connection
    store: History_Store
    if !history_store_test_open_memory(t, &connection, &store) {
        return
    }
    defer _ = sqlite.connection_close(&connection)
    defer _ = history_store_destroy(&store)

    inserted := history_store_insert_persistent(
        &store, history_store_test_record(7, .Normal, 77, 1, 1), "kept")
    testing.expect_value(t, inserted.outcome, History_Write_Outcome.Stored)
    testing.expect(t, history_store_test_exec(&connection,
        "CREATE TEMP TRIGGER reject_terminal_history_clear "+
        "BEFORE DELETE ON terminal_history BEGIN "+
        "SELECT RAISE(ABORT, 'injected clear failure'); END;"))
    cleared := history_store_clear(&store)
    testing.expect_value(t, cleared.outcome, History_Clear_Outcome.Failed)
    testing.expect_value(t, cleared.failure.kind, History_Store_Error_Kind.Sqlite)
    history_store_test_expect_both_rows(
        t, &store, 7, inserted.persistent_entry_id, History_Read_Outcome.Found)
    history_store_test_allow_clear(t, &connection, &store)
    history_store_test_expect_record_ids(
        t, &store, 7, inserted.persistent_entry_id,
        History_Read_Outcome.Not_Found)
}

// Remove the injected blocker and verify a later transactional clear succeeds.
history_store_test_allow_clear :: proc(
    t: ^testing.T, connection: ^sqlite.Connection, store: ^History_Store) {
    testing.expect(t, history_store_test_exec(connection,
        "DROP TRIGGER temp.reject_terminal_history_clear;"))
    testing.expect_value(t, history_store_clear(store).outcome,
        History_Clear_Outcome.Cleared)
}

// Assert exact session and durable identities after a clear or rollback.
history_store_test_expect_record_ids :: proc(
    t: ^testing.T, store: ^History_Store, submission_id, persistent_id: u64,
    expected: History_Read_Outcome) {
    destination: [16]u8
    testing.expect_value(t,
        history_store_get_by_id(store, submission_id, destination[:]).outcome,
        expected)
    testing.expect_value(t,
        history_store_get_persistent_by_id(store, persistent_id, destination[:]).outcome,
        expected)
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

// Copy a single text column before finalizing its SQLite statement.
history_store_test_text_query :: proc(
    t: ^testing.T, connection: ^sqlite.Connection,
    sql: string, destination: []u8) -> (int, bool) {
    statement: sqlite.Statement
    failure := sqlite.statement_prepare_text(connection, &statement, sql)
    if !history_store_sqlite_error_is_clear(failure) {
        return 0, false
    }
    status: sqlite.Step_Status
    status, failure = sqlite.statement_step(&statement)
    if !history_store_sqlite_error_is_clear(failure) || status != .Row {
        _ = sqlite.statement_finalize(&statement)
        return 0, false
    }
    count: int
    count, failure = sqlite.column_text_copy(&statement, 0, destination)
    if !history_store_sqlite_error_is_clear(failure) {
        _ = sqlite.statement_finalize(&statement)
        return 0, false
    }
    failure = sqlite.statement_finalize(&statement)
    testing.expect(t, history_store_sqlite_error_is_clear(failure))
    return count, history_store_sqlite_error_is_clear(failure)
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

#+test
package sqlite

import raw "../../libs/sqlite3"

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

Sqlite_Test_Path :: struct {
    directory: string,
    path: string,
    valid: bool,
}

// Create one in-memory connection for an isolated substrate test.
sqlite_test_open_memory :: proc(t: ^testing.T, connection: ^Connection) -> bool {
    failure := connection_open(connection, ":memory:", .Readwrite_Create,
        context.temp_allocator)
    testing.expect_value(t, failure.validation, Validation_Error.None)
    testing.expect_value(t, failure.result, raw.Result.Ok)
    return connection.handle != nil
}

// Create a unique temporary directory and database path for filesystem open tests.
sqlite_test_path :: proc(t: ^testing.T) -> Sqlite_Test_Path {
    result: Sqlite_Test_Path
    temporary_directory, directory_error := os.temp_directory(context.temp_allocator)
    if directory_error != nil {
        return result
    }
    directory_name := fmt.tprintf("euclid-sqlite-%x", uintptr(t))
    result.directory, _ = filepath.join(
        []string{temporary_directory, directory_name}, context.allocator)
    if len(result.directory) == 0 || os.make_directory_all(result.directory) != nil {
        return result
    }
    result.path, _ = filepath.join(
        []string{result.directory, "fixture.sqlite3"}, context.allocator)
    result.valid = len(result.path) > 0
    return result
}

// Assert exact bound values from a live row before the statement is reset.
sqlite_test_expect_bound_values :: proc(t: ^testing.T, statement: ^Statement) {
    text: [8]u8
    text_count, text_error := column_text_copy(statement, 0, text[:])
    testing.expect_value(t, text_error.validation, Validation_Error.None)
    testing.expect_value(t, string(text[:text_count]), "angle")
    integer32, integer32_error := column_i32(statement, 1)
    testing.expect_value(t, integer32_error.validation, Validation_Error.None)
    testing.expect_value(t, integer32, i32(-17))
    integer64, integer64_error := column_i64(statement, 2)
    testing.expect_value(t, integer64_error.validation, Validation_Error.None)
    testing.expect_value(t, integer64, i64(4_000_000_000))
    floating, floating_error := column_f64(statement, 3)
    testing.expect_value(t, floating_error.validation, Validation_Error.None)
    testing.expect_value(t, floating, 2.5)
    testing.expect_value(t, column_type(statement, 4), Column_Type.Null)
}

// Verify transient BLOB binding and exact bounded BLOB copying.
sqlite_test_expect_blob_value :: proc(
    t: ^testing.T, statement: ^Statement, expected: [16]u8) {
    destination: [16]u8
    count, failure := column_blob_copy(statement, 0, destination[:])
    testing.expect_value(t, failure.validation, Validation_Error.None)
    testing.expect_value(t, count, 16)
    testing.expect_value(t, destination, expected)
    _, capacity_error := column_blob_copy(statement, 0, destination[:8])
    testing.expect_value(t, capacity_error.validation, Validation_Error.Capacity)
}

// Verify that an empty input remains an empty SQLite BLOB rather than SQL NULL.
sqlite_test_expect_empty_blob :: proc(t: ^testing.T, statement: ^Statement) {
    testing.expect_value(t, column_type(statement, 0), Column_Type.Blob)
    destination: [1]u8
    count, failure := column_blob_copy(statement, 0, destination[:0])
    testing.expect_value(t, failure.validation, Validation_Error.None)
    testing.expect_value(t, count, 0)
}

// Verify transient BLOB binding and exact bounded BLOB copying.
@(test)
sqlite_blob_binding_and_copy_preserve_all_bytes :: proc(t: ^testing.T) {
    connection: Connection
    if !sqlite_test_open_memory(t, &connection) {
        return
    }
    defer _ = connection_close(&connection)
    statement: Statement
    failure := statement_prepare(
        &connection, &statement,
        strings.clone_to_cstring("SELECT ?1", context.temp_allocator))
    testing.expect_value(t, failure.validation, Validation_Error.None)
    identifier: [16]u8
    identifier[0] = 0x45
    identifier[15] = 0xA5
    failure = statement_bind_blob(&statement, 1, identifier[:])
    testing.expect_value(t, failure.validation, Validation_Error.None)
    status, step_error := statement_step(&statement)
    testing.expect_value(t, step_error.validation, Validation_Error.None)
    testing.expect_value(t, status, Step_Status.Row)
    sqlite_test_expect_blob_value(t, &statement, identifier)
    testing.expect_value(t, statement_reset(&statement).validation,
        Validation_Error.None)
    empty_destination: [1]u8
    failure = statement_bind_blob(&statement, 1, empty_destination[:0])
    testing.expect_value(t, failure.validation, Validation_Error.None)
    status, step_error = statement_step(&statement)
    testing.expect_value(t, step_error.validation, Validation_Error.None)
    testing.expect_value(t, status, Step_Status.Row)
    sqlite_test_expect_empty_blob(t, &statement)
    testing.expect_value(t, statement_reset(&statement).validation,
        Validation_Error.None)
    testing.expect_value(t, statement_finalize(&statement).validation,
        Validation_Error.None)
}

// Verify immutable URI admission and read-only enforcement on an existing fixture.
@(test)
sqlite_opens_immutable_readonly_fixture :: proc(t: ^testing.T) {
    fixture := sqlite_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)

    created: Connection
    opened := connection_open(
        &created, fixture.path, .Readwrite_Create, context.temp_allocator)
    testing.expect_value(t, opened.result, raw.Result.Ok)
    testing.expect_value(t,
        connection_exec(&created, "CREATE TABLE fixture(value TEXT)").result,
        raw.Result.Ok)
    testing.expect_value(t, connection_close(&created).result, raw.Result.Ok)

    readonly: Connection
    failure := connection_open(
        &readonly, fixture.path, .Immutable_Readonly, context.temp_allocator)
    testing.expect_value(t, failure.result, raw.Result.Ok)
    testing.expect(t, readonly.handle != nil)
    testing.expect_value(t,
        connection_exec(&readonly, "INSERT INTO fixture VALUES ('x')").result,
        raw.Result.Readonly)
    testing.expect_value(t, connection_close(&readonly).result, raw.Result.Ok)
    testing.expect(t, readonly.handle == nil)
}

// Verify that failed opens clean up any partially created SQLite handle.
@(test)
sqlite_open_failure_cleans_partial_connection :: proc(t: ^testing.T) {
    fixture := sqlite_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)

    connection: Connection
    missing_path := strings.concatenate(
        {fixture.path, "/missing.db"}, context.temp_allocator)
    failure := connection_open(&connection, missing_path,
        .Immutable_Readonly, context.temp_allocator)
    testing.expect(t, failure.result != .Ok)
    testing.expect(t, connection.handle == nil)
}

// Verify transient text binding, exact readers, reset clearance, and statement reuse.
@(test)
sqlite_statement_binds_steps_resets_and_reuses :: proc(t: ^testing.T) {
    connection: Connection
    if !sqlite_test_open_memory(t, &connection) {
        return
    }
    defer testing.expect_value(t, connection_close(&connection).result, raw.Result.Ok)

    statement: Statement
    testing.expect_value(t,
        statement_prepare(&connection, &statement,
            "SELECT ?1, ?2, ?3, ?4, ?5").result,
        raw.Result.Ok)
    testing.expect_value(t, statement_bind_text(&statement, 1, "angle").result,
        raw.Result.Ok)
    testing.expect_value(t, statement_bind_i32(&statement, 2, -17).result,
        raw.Result.Ok)
    testing.expect_value(t, statement_bind_i64(&statement, 3, 4_000_000_000).result,
        raw.Result.Ok)
    testing.expect_value(t, statement_bind_f64(&statement, 4, 2.5).result,
        raw.Result.Ok)
    testing.expect_value(t, statement_bind_null(&statement, 5).result, raw.Result.Ok)

    status, failure := statement_step(&statement)
    testing.expect_value(t, status, Step_Status.Row)
    testing.expect_value(t, failure.validation, Validation_Error.None)
    sqlite_test_expect_bound_values(t, &statement)

    testing.expect_value(t, statement_reset(&statement).result, raw.Result.Ok)
    status, _ = statement_step(&statement)
    testing.expect_value(t, status, Step_Status.Row)
    testing.expect_value(t, column_type(&statement, 0), Column_Type.Null)
    testing.expect_value(t, statement_reset(&statement).result, raw.Result.Ok)
    testing.expect_value(t, statement_finalize(&statement).result, raw.Result.Ok)
    testing.expect(t, statement.handle == nil && statement.database == nil)
}

// Verify row/done distinction, exact storage classes, range checks, and capacity bounds.
@(test)
sqlite_columns_reject_type_range_and_capacity_mismatches :: proc(t: ^testing.T) {
    connection: Connection
    if !sqlite_test_open_memory(t, &connection) {
        return
    }
    defer testing.expect_value(t, connection_close(&connection).result, raw.Result.Ok)

    statement: Statement
    testing.expect_value(t,
        statement_prepare(&connection, &statement,
            "SELECT 'long text', 2147483648, 1.5, 7 WHERE 1").result,
        raw.Result.Ok)
    status, _ := statement_step(&statement)
    testing.expect_value(t, status, Step_Status.Row)
    small: [3]u8
    _, capacity_error := column_text_copy(&statement, 0, small[:])
    testing.expect_value(t, capacity_error.validation, Validation_Error.Capacity)
    _, type_error := column_i32(&statement, 0)
    testing.expect_value(t, type_error.validation, Validation_Error.Type_Mismatch)
    _, range_error := column_i32(&statement, 1)
    testing.expect_value(t, range_error.validation, Validation_Error.Range)
    testing.expect_value(t, column_type(&statement, 2), Column_Type.Float)
    _, float_type_error := column_i64(&statement, 2)
    testing.expect_value(t, float_type_error.validation, Validation_Error.Type_Mismatch)
    testing.expect_value(t, statement_reset(&statement).result, raw.Result.Ok)
    testing.expect_value(t, statement_finalize(&statement).result, raw.Result.Ok)

    testing.expect_value(t,
        statement_prepare(&connection, &statement,
            "SELECT 1 WHERE 0").result,
        raw.Result.Ok)
    status, _ = statement_step(&statement)
    testing.expect_value(t, status, Step_Status.Done)
    testing.expect_value(t, statement_finalize(&statement).result, raw.Result.Ok)
}

// Verify spellfix setup and that close stays recoverable while a statement is live.
@(test)
sqlite_spellfix_and_close_lifecycle_are_explicit :: proc(t: ^testing.T) {
    connection: Connection
    if !sqlite_test_open_memory(t, &connection) {
        return
    }
    testing.expect_value(t, connection_register_spellfix(&connection).result,
        raw.Result.Ok)
    testing.expect_value(t,
        connection_exec(&connection, "CREATE VIRTUAL TABLE terms USING spellfix1").result,
        raw.Result.Ok)

    statement: Statement
    testing.expect_value(t,
        statement_prepare(&connection, &statement, "SELECT 1").result,
        raw.Result.Ok)
    busy := connection_close(&connection)
    testing.expect_value(t, busy.result, raw.Result.Busy)
    testing.expect(t, connection.handle != nil)
    testing.expect_value(t, statement_finalize(&statement).result, raw.Result.Ok)
    testing.expect_value(t, connection_close(&connection).result, raw.Result.Ok)
    testing.expect(t, connection.handle == nil)
}
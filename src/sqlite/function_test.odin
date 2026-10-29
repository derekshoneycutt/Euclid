#+test
package sqlite

import raw "../../libs/sqlite3"
import "core:c"
import "core:testing"

// Destructor evidence lives longer than registration and never replaces SQLite allocation.
Sqlite_Function_Test_Owner :: struct {
    destroyed: int,
}

// Count SQLite's destructor notification without assuming an Odin caller context.
sqlite_function_test_destroy :: proc "c" (user_data: rawptr) {
    owner := cast(^Sqlite_Function_Test_Owner)user_data
    owner.destroyed += 1
}

// Publish OOM through SQLite's dedicated result API.
sqlite_function_test_nomem :: proc "c" (
    call: ^Function_Context, count: c.int, values: [^]^Value) {
    raw.sqlite3_result_error_nomem(call)
}

// Success, replacement, unregister, native failure, and close each transfer one notification.
@(test)
sqlite_scalar_registration_owns_destructor_notification :: proc(t: ^testing.T) {
    connection: Connection
    if !sqlite_test_open_memory(t, &connection) {
        return
    }
    defer _ = connection_close(&connection)
    first, second, rejected: Sqlite_Function_Test_Owner
    function: Scalar_Function = {
        name = "fixture",
        argument_count = 0,
        callback = sqlite_function_test_nomem,
        destroy = sqlite_function_test_destroy,
        user_data = &first,
    }
    testing.expect_value(t, connection_register_scalar(&connection, function).result,
        raw.Result.Ok)
    function.user_data = &second
    testing.expect_value(t, connection_register_scalar(&connection, function).result,
        raw.Result.Ok)
    testing.expect_value(t, first.destroyed, 1)
    testing.expect_value(t,
        connection_unregister_scalar(&connection, "fixture", 0).result, raw.Result.Ok)
    testing.expect_value(t, second.destroyed, 1)
    function.argument_count = 100_000
    function.user_data = &rejected
    testing.expect(t, connection_register_scalar(&connection, function).result != .Ok)
    testing.expect_value(t, rejected.destroyed, 1)
    function.argument_count = 0
    testing.expect_value(t, connection_register_scalar(&connection, function).result,
        raw.Result.Ok)
    testing.expect_value(t, connection_close(&connection).result, raw.Result.Ok)
    testing.expect_value(t, rejected.destroyed, 2)
}

// OOM and DIRECTONLY authorization are errors, never boolean no-match results.
@(test)
sqlite_scalar_reports_oom_and_rejects_schema_use :: proc(t: ^testing.T) {
    connection: Connection
    if !sqlite_test_open_memory(t, &connection) {
        return
    }
    defer _ = connection_close(&connection)
    function: Scalar_Function = {
        name = "fixture",
        argument_count = 0,
        callback = sqlite_function_test_nomem,
    }
    testing.expect_value(t, connection_register_scalar(&connection, function).result,
        raw.Result.Ok)
    statement: Statement
    testing.expect_value(t, statement_prepare(
        &connection, &statement, "SELECT fixture();").result, raw.Result.Ok)
    status, failure := statement_step(&statement)
    testing.expect_value(t, status, Step_Status.Failed)
    testing.expect_value(t, failure.result, raw.Result.No_Memory)
    _ = statement_finalize(&statement)
    testing.expect_value(t, connection_exec(
        &connection, "CREATE VIEW fixture_view AS SELECT fixture();").result,
        raw.Result.Ok)
    failure = statement_prepare(&connection, &statement, "SELECT * FROM fixture_view;")
    testing.expect(t, failure.result != .Ok)
}

// An active statement makes replacement fail and destroys only the rejected owner.
@(test)
sqlite_scalar_busy_replacement_preserves_live_owner :: proc(t: ^testing.T) {
    connection: Connection
    if !sqlite_test_open_memory(t, &connection) {
        return
    }
    defer _ = connection_close(&connection)
    first, rejected: Sqlite_Function_Test_Owner
    function: Scalar_Function = {
        name = "fixture",
        argument_count = 0,
        callback = sqlite_function_test_nomem,
        destroy = sqlite_function_test_destroy,
        user_data = &first,
    }
    testing.expect_value(t, connection_register_scalar(&connection, function).result,
        raw.Result.Ok)
    statement: Statement
    testing.expect_value(t, statement_prepare(
        &connection, &statement, "SELECT 1;").result, raw.Result.Ok)
    _, _ = statement_step(&statement)
    function.user_data = &rejected
    testing.expect_value(t, connection_register_scalar(&connection, function).result,
        raw.Result.Busy)
    testing.expect_value(t, rejected.destroyed, 1)
    testing.expect_value(t, first.destroyed, 0)
    _ = statement_finalize(&statement)
    testing.expect_value(t,
        connection_unregister_scalar(&connection, "fixture", 0).result, raw.Result.Ok)
    testing.expect_value(t, first.destroyed, 1)
}

#+test
package main

import sqlite3 "../libs/sqlite3"

import "core:c"
import "core:strings"
import "core:testing"

// open_sqlite3_test_database creates one isolated writable in-memory database.
open_sqlite3_test_database :: proc(t: ^testing.T) -> ^sqlite3.Database {
    database: ^sqlite3.Database
    flags := c.int(sqlite3.Open_Flag.Readwrite) |
        c.int(sqlite3.Open_Flag.Create)
    status := sqlite3.sqlite3_open_v2(
        cstring(":memory:"), &database, flags, nil)
    testing.expect_value(t, status, sqlite3.Result.Ok)
    testing.expect(t, database != nil)
    return database
}

// execute_sqlite3_test_sql executes repository-owned fixture SQL and frees errors.
execute_sqlite3_test_sql :: proc(
    t: ^testing.T, database: ^sqlite3.Database, sql: cstring) -> bool {
    error_message: cstring
    status := sqlite3.sqlite3_exec(database, sql, nil, nil, &error_message)
    if error_message != nil {
        sqlite3.sqlite3_free(rawptr(error_message))
    }
    testing.expect_value(t, status, sqlite3.Result.Ok)
    return status == .Ok
}

// Verify the linked archive is the pinned repository SQLite release.
@(test)
sqlite3_substrate_reports_pinned_version :: proc(t: ^testing.T) {
    testing.expect_value(t, sqlite3.sqlite3_libversion_number(), 3_053_004)
    testing.expect_value(t, string(sqlite3.sqlite3_libversion()), "3.53.4")
}

// Verify FTS5 and statically registered spellfix are available together.
@(test)
sqlite3_substrate_provides_fts5_and_spellfix :: proc(t: ^testing.T) {
    database := open_sqlite3_test_database(t)
    defer testing.expect_value(t,
        sqlite3.sqlite3_close(database), sqlite3.Result.Ok)

    testing.expect_value(t,
        sqlite3.euclid_sqlite_register_spellfix(database), sqlite3.Result.Ok)
    testing.expect(t, execute_sqlite3_test_sql(t, database,
        "CREATE VIRTUAL TABLE documents USING fts5(content)"))
    testing.expect(t, execute_sqlite3_test_sql(t, database,
        "CREATE VIRTUAL TABLE terms USING spellfix1"))
    testing.expect(t, execute_sqlite3_test_sql(t, database,
        "INSERT INTO documents(content) VALUES ('perpendicular geometry')"))

    statement: ^sqlite3.Statement
    status := sqlite3.sqlite3_prepare_v3(database,
        "SELECT rowid FROM documents WHERE documents MATCH 'perpend*'",
        -1, 0, &statement, nil)
    testing.expect_value(t, status, sqlite3.Result.Ok)
    defer testing.expect_value(t,
        sqlite3.sqlite3_finalize(statement), sqlite3.Result.Ok)
    testing.expect_value(t, sqlite3.sqlite3_step(statement), sqlite3.Result.Row)
}

// Verify transient binding copies temporary bytes and statement reuse clears state.
@(test)
sqlite3_substrate_copies_transient_bound_text :: proc(t: ^testing.T) {
    database := open_sqlite3_test_database(t)
    defer testing.expect_value(t,
        sqlite3.sqlite3_close(database), sqlite3.Result.Ok)
    statement: ^sqlite3.Statement
    status := sqlite3.sqlite3_prepare_v3(
        database, "SELECT ?1", -1,
        c.uint(sqlite3.Prepare_Flag.Persistent), &statement, nil)
    testing.expect_value(t, status, sqlite3.Result.Ok)
    defer testing.expect_value(t,
        sqlite3.sqlite3_finalize(statement), sqlite3.Result.Ok)

    temporary := strings.clone_to_cstring("right angle", context.allocator)
    testing.expect_value(t, sqlite3.sqlite3_bind_text(
        statement, 1, temporary, -1, sqlite3.transient_destructor()),
        sqlite3.Result.Ok)
    delete(temporary)
    testing.expect_value(t, sqlite3.sqlite3_step(statement), sqlite3.Result.Row)
    testing.expect_value(t,
        string(sqlite3.sqlite3_column_text(statement, 0)), "right angle")
    testing.expect_value(t,
        sqlite3.sqlite3_reset(statement), sqlite3.Result.Ok)
    testing.expect_value(t,
        sqlite3.sqlite3_clear_bindings(statement), sqlite3.Result.Ok)
    testing.expect_value(t, sqlite3.sqlite3_step(statement), sqlite3.Result.Row)
    testing.expect_value(t, sqlite3.sqlite3_column_type(statement, 0),
        sqlite3.Column_Type.Null)
}

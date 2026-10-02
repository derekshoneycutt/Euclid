package sqlite

import raw "../../libs/sqlite3"

import "core:c"

// Prepare one persistent statement owned by the supplied connection.
statement_prepare :: proc(
    connection: ^Connection, statement: ^Statement, sql: cstring) -> Error {
    if connection == nil || connection.handle == nil || statement == nil ||
       statement.handle != nil || sql == nil {
        return sqlite_make_validation_error(.Prepare, .Invalid_State)
    }
    result := raw.sqlite3_prepare_v3(connection.handle, sql, -1,
        c.uint(raw.Prepare_Flag.Persistent), &statement.handle, nil)
    if result != .Ok {
        if statement.handle != nil {
            _ = raw.sqlite3_finalize(statement.handle)
        }
        statement^ = {}
        return sqlite_make_error(.Prepare, connection.handle, result)
    }
    statement.database = connection.handle
    return {}
}

// Advance one statement and distinguish a row, completion, and SQLite failure.
statement_step :: proc(statement: ^Statement) -> (Step_Status, Error) {
    if statement == nil || statement.handle == nil || statement.database == nil {
        return .Failed, sqlite_make_validation_error(.Step, .Invalid_State)
    }
    result := raw.sqlite3_step(statement.handle)
    if result == .Row {
        return .Row, {}
    }
    if result == .Done {
        return .Done, {}
    }
    return .Failed, sqlite_make_error(.Step, statement.database, result)
}

// Reset execution and clear all previous parameter bindings.
statement_reset :: proc(statement: ^Statement) -> Error {
    if statement == nil || statement.handle == nil || statement.database == nil {
        return sqlite_make_validation_error(.Reset, .Invalid_State)
    }
    reset_result := raw.sqlite3_reset(statement.handle)
    clear_result := raw.sqlite3_clear_bindings(statement.handle)
    if reset_result != .Ok {
        return sqlite_make_error(.Reset, statement.database, reset_result)
    }
    if clear_result != .Ok {
        return sqlite_make_error(.Reset, statement.database, clear_result)
    }
    return {}
}

// Finalize a statement and zero its wrapper even when SQLite reports prior execution failure.
statement_finalize :: proc(statement: ^Statement) -> Error {
    if statement == nil || statement.handle == nil {
        return sqlite_make_validation_error(.Finalize, .Invalid_State)
    }
    database := statement.database
    result := raw.sqlite3_finalize(statement.handle)
    statement^ = {}
    if result != .Ok {
        return sqlite_make_error(.Finalize, database, result)
    }
    return {}
}

// Validate a live statement and a positive SQLite parameter index.
sqlite_validate_binding :: proc(statement: ^Statement, index: int) -> Error {
    if statement == nil || statement.handle == nil || statement.database == nil {
        return sqlite_make_validation_error(.Bind, .Invalid_State)
    }
    if index <= 0 || index > int(max(c.int)) {
        return sqlite_make_validation_error(.Bind, .Range)
    }
    return {}
}
package sqlite

import raw "../../libs/sqlite3"

import "core:c"

// Bind copied UTF-8 bytes without a temporary string allocation.
statement_bind_text :: proc(
    statement: ^Statement, index: int, value: string) -> Error {
    validation := sqlite_validate_binding(statement, index)
    if validation.validation != .None {
        return validation
    }
    if len(value) > int(max(c.int)) {
        return sqlite_make_validation_error(.Bind, .Range)
    }
    empty_text: [1]u8
    value_pointer := cstring(raw_data(value))
    if len(value) == 0 {
        value_pointer = cstring(raw_data(empty_text[:]))
    }
    result := raw.sqlite3_bind_text(statement.handle, c.int(index), value_pointer,
        c.int(len(value)), raw.transient_destructor())
    return sqlite_binding_result(statement, result)
}

// Bind one 32-bit signed integer.
statement_bind_i32 :: proc(statement: ^Statement, index: int, value: i32) -> Error {
    validation := sqlite_validate_binding(statement, index)
    if validation.validation != .None {
        return validation
    }
    result := raw.sqlite3_bind_int(statement.handle, c.int(index), c.int(value))
    return sqlite_binding_result(statement, result)
}

// Bind one 64-bit signed integer.
statement_bind_i64 :: proc(statement: ^Statement, index: int, value: i64) -> Error {
    validation := sqlite_validate_binding(statement, index)
    if validation.validation != .None {
        return validation
    }
    result := raw.sqlite3_bind_int64(statement.handle, c.int(index), c.longlong(value))
    return sqlite_binding_result(statement, result)
}

// Bind one double-precision floating-point value.
statement_bind_f64 :: proc(statement: ^Statement, index: int, value: f64) -> Error {
    validation := sqlite_validate_binding(statement, index)
    if validation.validation != .None {
        return validation
    }
    result := raw.sqlite3_bind_double(statement.handle, c.int(index), value)
    return sqlite_binding_result(statement, result)
}

// Bind SQL NULL at one positive parameter index.
statement_bind_null :: proc(statement: ^Statement, index: int) -> Error {
    validation := sqlite_validate_binding(statement, index)
    if validation.validation != .None {
        return validation
    }
    result := raw.sqlite3_bind_null(statement.handle, c.int(index))
    return sqlite_binding_result(statement, result)
}

// Convert one bind result into the shared structured error form.
sqlite_binding_result :: proc(statement: ^Statement, result: raw.Result) -> Error {
    if result != .Ok {
        return sqlite_make_error(.Bind, statement.database, result)
    }
    return {}
}
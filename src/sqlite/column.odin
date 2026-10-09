package sqlite

import raw "../../libs/sqlite3"

import "core:c"

// Return the exact SQLite storage class, or Invalid for an invalid wrapper/index.
column_type :: proc(statement: ^Statement, column: int) -> Column_Type {
    if sqlite_validate_column(statement, column).validation != .None {
        return .Invalid
    }
    switch raw.sqlite3_column_type(statement.handle, c.int(column)) {
    case .Integer: return .Integer
    case .Float: return .Float
    case .Text: return .Text
    case .Blob: return .Blob
    case .Null: return .Null
    }
    return .Invalid
}

// Copy one exact TEXT value into caller-owned bounded bytes and return its byte length.
column_text_copy :: proc(
    statement: ^Statement, column: int, destination: []u8) -> (int, Error) {
    validation := sqlite_validate_column(statement, column)
    if validation.validation != .None {
        return 0, validation
    }
    if raw.sqlite3_column_type(statement.handle, c.int(column)) != .Text {
        return 0, sqlite_make_validation_error(.Column, .Type_Mismatch)
    }
    byte_count := int(raw.sqlite3_column_bytes(statement.handle, c.int(column)))
    if byte_count < 0 {
        return 0, sqlite_make_validation_error(.Column, .Range)
    }
    if byte_count > len(destination) {
        return 0, sqlite_make_validation_error(.Column, .Capacity)
    }
    source := cast(^u8)raw.sqlite3_column_text(statement.handle, c.int(column))
    if byte_count > 0 && source == nil {
        return 0, sqlite_make_validation_error(.Column, .Invalid_State)
    }
    if byte_count > 0 {
        for index in 0..<byte_count {
            byte_address := uintptr(source) + uintptr(index)
            destination[index] = (cast(^u8)byte_address)^
        }
    }
    return byte_count, {}
}

// Copy one exact BLOB value into caller-owned bounded bytes.
column_blob_copy :: proc(
    statement: ^Statement, column: int, destination: []u8) -> (int, Error) {
    validation := sqlite_validate_column(statement, column)
    if validation.validation != .None {
        return 0, validation
    }
    if raw.sqlite3_column_type(statement.handle, c.int(column)) != .Blob {
        return 0, sqlite_make_validation_error(.Column, .Type_Mismatch)
    }
    byte_count := int(raw.sqlite3_column_bytes(statement.handle, c.int(column)))
    if byte_count < 0 {
        return 0, sqlite_make_validation_error(.Column, .Range)
    }
    if byte_count > len(destination) {
        return 0, sqlite_make_validation_error(.Column, .Capacity)
    }
    source := cast(^u8)raw.sqlite3_column_blob(statement.handle, c.int(column))
    if byte_count > 0 && source == nil {
        return 0, sqlite_make_validation_error(.Column, .Invalid_State)
    }
    if byte_count > 0 {
        for index in 0..<byte_count {
            byte_address := uintptr(source) + uintptr(index)
            destination[index] = (cast(^u8)byte_address)^
        }
    }
    return byte_count, {}
}

// Read one exact INTEGER value if it is representable as i32.
column_i32 :: proc(statement: ^Statement, column: int) -> (i32, Error) {
    value, failure := sqlite_column_integer(statement, column)
    if failure.validation != .None || failure.result != .Ok {
        return 0, failure
    }
    if value < i64(min(i32)) || value > i64(max(i32)) {
        return 0, sqlite_make_validation_error(.Column, .Range)
    }
    return i32(value), {}
}

// Read one exact INTEGER value as i64.
column_i64 :: proc(statement: ^Statement, column: int) -> (i64, Error) {
    return sqlite_column_integer(statement, column)
}

// Read one exact FLOAT value as f64.
column_f64 :: proc(statement: ^Statement, column: int) -> (f64, Error) {
    validation := sqlite_validate_column(statement, column)
    if validation.validation != .None {
        return 0, validation
    }
    if raw.sqlite3_column_type(statement.handle, c.int(column)) != .Float {
        return 0, sqlite_make_validation_error(.Column, .Type_Mismatch)
    }
    return raw.sqlite3_column_double(statement.handle, c.int(column)), {}
}

// Read one exact INTEGER column without SQLite's lossy coercions.
sqlite_column_integer :: proc(statement: ^Statement, column: int) -> (i64, Error) {
    validation := sqlite_validate_column(statement, column)
    if validation.validation != .None {
        return 0, validation
    }
    if raw.sqlite3_column_type(statement.handle, c.int(column)) != .Integer {
        return 0, sqlite_make_validation_error(.Column, .Type_Mismatch)
    }
    return i64(raw.sqlite3_column_int64(statement.handle, c.int(column))), {}
}

// Validate a live statement and a nonnegative column index.
sqlite_validate_column :: proc(statement: ^Statement, column: int) -> Error {
    if statement == nil || statement.handle == nil || statement.database == nil {
        return sqlite_make_validation_error(.Column, .Invalid_State)
    }
    if column < 0 || column > int(max(c.int)) {
        return sqlite_make_validation_error(.Column, .Range)
    }
    return {}
}
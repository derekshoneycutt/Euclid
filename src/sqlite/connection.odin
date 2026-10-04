package sqlite

import raw "../../libs/sqlite3"

import "core:c"
import "core:mem"
import "core:strings"

SQLITE_HEX_DIGITS :: "0123456789ABCDEF"

// Open one nonconcurrent connection; thread changes require exclusive ownership.
connection_open :: proc(
    connection: ^Connection, path: string, mode: Open_Mode,
    scratch_allocator: mem.Allocator) -> Error {
    if connection == nil || connection.handle != nil {
        return sqlite_make_validation_error(.Open, .Invalid_State)
    }
    if len(path) == 0 || sqlite_path_has_nul(path) {
        return sqlite_make_validation_error(.Open, .Invalid_Argument)
    }
    flags, valid_mode := sqlite_open_flags(mode)
    if !valid_mode {
        return sqlite_make_validation_error(.Open, .Invalid_Argument)
    }
    filename := sqlite_open_filename(path, mode, scratch_allocator)
    result := raw.sqlite3_open_v2(filename, &connection.handle, flags, nil)
    if result == .Ok {
        return {}
    }
    failure := sqlite_make_error(.Open, connection.handle, result)
    if connection.handle != nil && raw.sqlite3_close(connection.handle) == .Ok {
        connection.handle = nil
    }
    return failure
}

// Close a connection after all of its statements have been finalized.
connection_close :: proc(connection: ^Connection) -> Error {
    if connection == nil || connection.handle == nil {
        return sqlite_make_validation_error(.Close, .Invalid_State)
    }
    database := connection.handle
    result := raw.sqlite3_close(database)
    if result != .Ok {
        return sqlite_make_error(.Close, database, result)
    }
    connection.handle = nil
    return {}
}

// Execute fixed store-owned SQL and release SQLite's optional error buffer.
connection_exec :: proc(connection: ^Connection, sql: cstring) -> Error {
    if connection == nil || connection.handle == nil || sql == nil {
        return sqlite_make_validation_error(.Exec, .Invalid_State)
    }
    error_message: cstring
    result := raw.sqlite3_exec(connection.handle, sql, nil, nil, &error_message)
    if error_message != nil {
        raw.sqlite3_free(rawptr(error_message))
    }
    if result != .Ok {
        return sqlite_make_error(.Exec, connection.handle, result)
    }
    return {}
}

// Register the repository-built spellfix module on this connection.
connection_register_spellfix :: proc(connection: ^Connection) -> Error {
    if connection == nil || connection.handle == nil {
        return sqlite_make_validation_error(.Register_Spellfix, .Invalid_State)
    }
    result := raw.euclid_sqlite_register_spellfix(connection.handle)
    if result != .Ok {
        return sqlite_make_error(.Register_Spellfix, connection.handle, result)
    }
    return {}
}

// Return SQLite's connection-owned diagnostic text, valid until the next database call.
connection_error_message :: proc(connection: ^Connection) -> cstring {
    if connection == nil || connection.handle == nil {
        return nil
    }
    return raw.sqlite3_errmsg(connection.handle)
}

// Reject embedded NUL bytes that would truncate a filename at the C boundary.
sqlite_path_has_nul :: proc(path: string) -> bool {
    for byte in transmute([]u8)path {
        if byte == 0 {
            return true
        }
    }
    return false
}

// Translate open modes while deliberately disabling per-connection mutexes.
sqlite_open_flags :: proc(mode: Open_Mode) -> (c.int, bool) {
    switch mode {
    case .Immutable_Readonly:
        return c.int(raw.Open_Flag.Readonly) | c.int(raw.Open_Flag.Uri) |
            c.int(raw.Open_Flag.No_Mutex), true
    case .Readonly:
        return c.int(raw.Open_Flag.Readonly) | c.int(raw.Open_Flag.No_Mutex), true
    case .Readwrite:
        return c.int(raw.Open_Flag.Readwrite) | c.int(raw.Open_Flag.No_Mutex), true
    case .Readwrite_Create:
        return c.int(raw.Open_Flag.Readwrite) | c.int(raw.Open_Flag.Create) |
            c.int(raw.Open_Flag.No_Mutex), true
    }
    return 0, false
}

// Build a NUL-terminated filename or escaped immutable URI from caller-owned scratch.
sqlite_open_filename :: proc(
    path: string, mode: Open_Mode, allocator: mem.Allocator) -> cstring {
    if mode != .Immutable_Readonly {
        return strings.clone_to_cstring(path, allocator)
    }
    buffer := make([]u8, 5 + len(path) * 3 + 12 + 1, allocator)
    prefix := "file:"
    hex_digits := SQLITE_HEX_DIGITS
    copy(buffer[:len(prefix)], transmute([]u8)prefix)
    offset := len(prefix)
    for byte in transmute([]u8)path {
        if sqlite_uri_byte_is_unescaped(byte) {
            buffer[offset] = byte
            offset += 1
        } else {
            buffer[offset] = '%'
            buffer[offset + 1] = hex_digits[byte >> 4]
            buffer[offset + 2] = hex_digits[byte & 0x0F]
            offset += 3
        }
    }
    suffix := "?immutable=1"
    copy(buffer[offset:offset + len(suffix)], transmute([]u8)suffix)
    offset += len(suffix)
    buffer[offset] = 0
    return cstring(raw_data(buffer))
}

// Keep URI path separators and portable filename bytes literal while escaping delimiters.
sqlite_uri_byte_is_unescaped :: proc(byte: u8) -> bool {
    return (byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z') ||
        (byte >= '0' && byte <= '9') || byte == '/' || byte == '.' ||
        byte == '_' || byte == '-' || byte == ':'
}
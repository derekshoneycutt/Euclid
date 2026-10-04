package sqlite3

import "core:c"

when ODIN_OS == .Windows {
    foreign import sqlite3_library "system:sqlite3.lib"
} else {
    foreign import sqlite3_library "system:sqlite3"
}

// Opaque SQLite connection storage owned by one native caller.
Database :: struct {}

// Opaque compiled SQLite statement storage owned by its connection.
Statement :: struct {}

Result :: enum c.int {
    Ok = 0,
    Error = 1,
    Internal = 2,
    Permission = 3,
    Abort = 4,
    Busy = 5,
    Locked = 6,
    No_Memory = 7,
    Readonly = 8,
    Interrupt = 9,
    Io_Error = 10,
    Corrupt = 11,
    Not_Found = 12,
    Full = 13,
    Cannot_Open = 14,
    Protocol = 15,
    Empty = 16,
    Schema = 17,
    Too_Big = 18,
    Constraint = 19,
    Mismatch = 20,
    Misuse = 21,
    No_Lfs = 22,
    Authorization = 23,
    Format = 24,
    Range = 25,
    Not_A_Database = 26,
    Notice = 27,
    Warning = 28,
    Row = 100,
    Done = 101,
}

Open_Flag :: enum c.int {
    Readonly = 0x00000001,
    Readwrite = 0x00000002,
    Create = 0x00000004,
    Uri = 0x00000040,
    No_Mutex = 0x00008000,
}

Prepare_Flag :: enum c.uint {
    Persistent = 0x01,
    Normalize = 0x02,
    No_Vtab = 0x04,
}

Column_Type :: enum c.int {
    Integer = 1,
    Float = 2,
    Text = 3,
    Blob = 4,
    Null = 5,
}

Exec_Callback :: proc "c" (
    user_data: rawptr, column_count: c.int,
    column_values, column_names: ^cstring) -> c.int

// transient_destructor requests that SQLite copy bound bytes before bind returns.
transient_destructor :: proc() -> rawptr {
    return transmute(rawptr)(~uintptr(0))
}

foreign sqlite3_library {
    sqlite3_threadsafe :: proc() -> c.int ---
    sqlite3_libversion :: proc() -> cstring ---
    sqlite3_libversion_number :: proc() -> c.int ---

    sqlite3_open_v2 :: proc(
        filename: cstring, database: ^^Database, flags: c.int,
        vfs_name: cstring) -> Result ---
    sqlite3_close :: proc(database: ^Database) -> Result ---

    sqlite3_prepare_v3 :: proc(
        database: ^Database, sql: cstring, byte_count: c.int,
        flags: c.uint, statement: ^^Statement, tail: ^cstring) -> Result ---
    sqlite3_step :: proc(statement: ^Statement) -> Result ---
    sqlite3_reset :: proc(statement: ^Statement) -> Result ---
    sqlite3_clear_bindings :: proc(statement: ^Statement) -> Result ---
    sqlite3_finalize :: proc(statement: ^Statement) -> Result ---

    sqlite3_bind_text :: proc(
        statement: ^Statement, index: c.int, value: cstring,
        byte_count: c.int, destructor: rawptr) -> Result ---
    sqlite3_bind_int :: proc(
        statement: ^Statement, index: c.int, value: c.int) -> Result ---
    sqlite3_bind_int64 :: proc(
        statement: ^Statement, index: c.int, value: c.longlong) -> Result ---
    sqlite3_bind_double :: proc(
        statement: ^Statement, index: c.int, value: f64) -> Result ---
    sqlite3_bind_null :: proc(statement: ^Statement, index: c.int) -> Result ---

    sqlite3_column_text :: proc(statement: ^Statement, column: c.int) -> cstring ---
    sqlite3_column_bytes :: proc(statement: ^Statement, column: c.int) -> c.int ---
    sqlite3_column_int :: proc(statement: ^Statement, column: c.int) -> c.int ---
    sqlite3_column_int64 :: proc(statement: ^Statement, column: c.int) -> c.longlong ---
    sqlite3_column_double :: proc(statement: ^Statement, column: c.int) -> f64 ---
    sqlite3_column_type :: proc(statement: ^Statement, column: c.int) -> Column_Type ---

    sqlite3_errmsg :: proc(database: ^Database) -> cstring ---
    sqlite3_extended_errcode :: proc(database: ^Database) -> c.int ---
    sqlite3_errstr :: proc(result_code: c.int) -> cstring ---
    sqlite3_exec :: proc(
        database: ^Database, sql: cstring, callback: Exec_Callback,
        user_data: rawptr, error_message: ^cstring) -> Result ---
    sqlite3_free :: proc(memory: rawptr) ---

    euclid_sqlite_register_spellfix :: proc(database: ^Database) -> Result ---
}


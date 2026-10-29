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

Function_Context :: struct {}
Value :: struct {}
Scalar_Callback :: proc "c" (
    call: ^Function_Context, count: c.int, values: [^]^Value)
Destroy_Callback :: proc "c" (user_data: rawptr)
Progress_Callback :: proc "c" (user_data: rawptr) -> c.int

FUNCTION_UTF8 :: c.int(1)
FUNCTION_DIRECTONLY :: c.int(0x00080000)

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

// Authorizer_Callback decides whether a connection may perform one SQL action.
Authorizer_Callback :: proc "c" (
    user_data: rawptr, action: c.int, first, second, database, trigger: cstring) -> c.int

// transient_destructor requests that SQLite copy bound bytes before bind returns.
transient_destructor :: proc() -> rawptr {
    return transmute(rawptr)(~uintptr(0))
}

foreign sqlite3_library {
    sqlite3_create_function_v2 :: proc(
        database: ^Database, name: cstring, count, flags: c.int,
        user_data: rawptr, scalar: Scalar_Callback, step, final: rawptr,
        destroy: Destroy_Callback) -> Result ---
    sqlite3_user_data :: proc(call: ^Function_Context) -> rawptr ---
    sqlite3_context_db_handle :: proc(call: ^Function_Context) -> ^Database ---
    sqlite3_value_type :: proc(value: ^Value) -> Column_Type ---
    sqlite3_value_int64 :: proc(value: ^Value) -> c.longlong ---
    sqlite3_value_text :: proc(value: ^Value) -> cstring ---
    sqlite3_value_bytes :: proc(value: ^Value) -> c.int ---
    sqlite3_result_int :: proc(call: ^Function_Context, value: c.int) ---
    sqlite3_result_error :: proc(
        call: ^Function_Context, message: cstring, length: c.int) ---
    sqlite3_result_error_code :: proc(call: ^Function_Context, code: c.int) ---
    sqlite3_result_error_nomem :: proc(call: ^Function_Context) ---
    sqlite3_progress_handler :: proc(
        database: ^Database, instructions: c.int,
        callback: Progress_Callback, user_data: rawptr) ---
    sqlite3_threadsafe :: proc() -> c.int ---
    sqlite3_libversion :: proc() -> cstring ---
    sqlite3_libversion_number :: proc() -> c.int ---

    sqlite3_open_v2 :: proc(
        filename: cstring, database: ^^Database, flags: c.int,
        vfs_name: cstring) -> Result ---
    sqlite3_close :: proc(database: ^Database) -> Result ---
    sqlite3_get_autocommit :: proc(database: ^Database) -> c.int ---
    sqlite3_error_offset :: proc(database: ^Database) -> c.int ---
    sqlite3_bind_parameter_count :: proc(statement: ^Statement) -> c.int ---
    sqlite3_bind_parameter_name :: proc(
        statement: ^Statement, index: c.int) -> cstring ---
    sqlite3_bind_parameter_index :: proc(
        statement: ^Statement, name: cstring) -> c.int ---
    sqlite3_set_authorizer :: proc(
        database: ^Database, callback: Authorizer_Callback,
        user_data: rawptr) -> Result ---
    sqlite3_limit :: proc(database: ^Database, category, value: c.int) -> c.int ---
    sqlite3_db_config :: proc(
        database: ^Database, option: c.int, #c_vararg arguments: ..any) -> Result ---
    sqlite3_compileoption_used :: proc(option: cstring) -> c.int ---
    sqlite3_sourceid :: proc() -> cstring ---

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
    sqlite3_bind_blob :: proc(
        statement: ^Statement, index: c.int, value: rawptr,
        byte_count: c.int, destructor: rawptr) -> Result ---
    sqlite3_bind_int :: proc(
        statement: ^Statement, index: c.int, value: c.int) -> Result ---
    sqlite3_bind_int64 :: proc(
        statement: ^Statement, index: c.int, value: c.longlong) -> Result ---
    sqlite3_bind_double :: proc(
        statement: ^Statement, index: c.int, value: f64) -> Result ---
    sqlite3_bind_null :: proc(statement: ^Statement, index: c.int) -> Result ---

    sqlite3_column_text :: proc(statement: ^Statement, column: c.int) -> cstring ---
    sqlite3_column_blob :: proc(statement: ^Statement, column: c.int) -> rawptr ---
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

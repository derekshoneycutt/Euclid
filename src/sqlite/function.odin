package sqlite

import raw "../../libs/sqlite3"
import "core:c"

Function_Context :: raw.Function_Context
Value :: raw.Value
Result_Code :: raw.Result

// SQLite owns the destructor invocation, including native registration failure.
Scalar_Function :: struct {
    name: cstring,
    argument_count: c.int,
    user_data: rawptr,
    callback: raw.Scalar_Callback,
    destroy: raw.Destroy_Callback,
}

// Register an application-only, non-deterministic scalar on an exclusive connection.
// Validation rejection does not transfer ownership; a native call always does.
connection_register_scalar :: proc(
    connection: ^Connection, function: Scalar_Function) -> Error {
    if connection == nil || connection.handle == nil {
        return sqlite_make_validation_error(.Function, .Invalid_State)
    }
    if function.name == nil || function.argument_count < 0 ||
       function.callback == nil {
        return sqlite_make_validation_error(.Function, .Invalid_Argument)
    }
    result := raw.sqlite3_create_function_v2(connection.handle, function.name,
        function.argument_count, raw.FUNCTION_UTF8 | raw.FUNCTION_DIRECTONLY,
        function.user_data, function.callback, nil, nil, function.destroy)
    return sqlite_make_error(.Function, connection.handle, result)
}

// Unregister only after statements and callbacks stop borrowing the registered owner.
connection_unregister_scalar :: proc(
    connection: ^Connection, name: cstring, argument_count: int) -> Error {
    if connection == nil || connection.handle == nil || name == nil {
        return sqlite_make_validation_error(.Function, .Invalid_State)
    }
    if argument_count < 0 || argument_count > 127 {
        return sqlite_make_validation_error(.Function, .Range)
    }
    result := raw.sqlite3_create_function_v2(connection.handle, name,
        c.int(argument_count), raw.FUNCTION_UTF8, nil, nil, nil, nil, nil)
    return sqlite_make_error(.Function, connection.handle, result)
}

// Borrow registration data only during the synchronous scalar callback.
function_user_data :: proc "contextless" (call: ^Function_Context) -> rawptr {
    return raw.sqlite3_user_data(call)
}

// Read a strictly typed integer without SQLite coercion.
value_i64 :: proc(value: ^Value) -> (i64, Error) {
    if value == nil || raw.sqlite3_value_type(value) != .Integer {
        return 0, sqlite_make_validation_error(.Value, .Type_Mismatch)
    }
    return i64(raw.sqlite3_value_int64(value)), {}
}

// Borrow exact TEXT bytes until callback return; preserve SQLite conversion OOM.
value_text :: proc(
    call: ^Function_Context, value: ^Value) -> (string, Error) {
    if value == nil || raw.sqlite3_value_type(value) != .Text {
        return "", sqlite_make_validation_error(.Value, .Type_Mismatch)
    }
    pointer := raw.sqlite3_value_text(value)
    if pointer == nil {
        return "", sqlite_make_error(
            .Value, raw.sqlite3_context_db_handle(call), .No_Memory)
    }
    length := int(raw.sqlite3_value_bytes(value))
    return string((cast([^]u8)pointer)[:length]), {}
}

// Publish one boolean decision without exposing SQLite's coercion rules.
function_result_bool :: proc(call: ^Function_Context, value: bool) {
    raw.sqlite3_result_int(call, c.int(value))
}

// Return a stable diagnostic and native result code; OOM uses SQLite's dedicated API.
function_result_error :: proc(
    call: ^Function_Context, code: Result_Code, message: string) {
    if code == .No_Memory {
        raw.sqlite3_result_error_nomem(call)
        return
    }
    raw.sqlite3_result_error(call, cstring(raw_data(message)), c.int(len(message)))
    raw.sqlite3_result_error_code(call, c.int(code))
}

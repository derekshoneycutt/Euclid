package sqlite

import raw "../../libs/sqlite3"
import "core:c"

// Progress_Handler belongs to an exclusive connection user; scopes restore it exactly.
Progress_Handler :: struct {
    instructions: int,
    callback: raw.Progress_Callback,
    user_data: rawptr,
}

// Replace a tracked progress handler under exclusive connection admission.
// Callers installing a scope must chain any prior handler and restore it before release.
connection_set_progress :: proc(
    connection: ^Connection, handler: Progress_Handler) -> Error {
    if connection == nil || connection.handle == nil {
        return sqlite_make_validation_error(.Progress, .Invalid_State)
    }
    if handler.instructions < 0 || handler.instructions > int(max(c.int)) ||
       (handler.instructions > 0 && handler.callback == nil) {
        return sqlite_make_validation_error(.Progress, .Invalid_Argument)
    }
    raw.sqlite3_progress_handler(connection.handle, c.int(handler.instructions),
        handler.callback, handler.user_data)
    connection.progress = handler
    return {}
}

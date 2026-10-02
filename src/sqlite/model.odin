package sqlite

import raw "../../libs/sqlite3"

Open_Mode :: enum {
    Immutable_Readonly,
    Readonly,
    Readwrite,
    Readwrite_Create,
}

Operation :: enum {
    None,
    Open,
    Close,
    Exec,
    Register_Spellfix,
    Prepare,
    Step,
    Reset,
    Finalize,
    Bind,
    Column,
}

Step_Status :: enum {
    Row,
    Done,
    Failed,
}

Column_Type :: enum u8 {
    Invalid,
    Integer,
    Float,
    Text,
    Blob,
    Null,
}

Validation_Error :: enum {
    None,
    Invalid_State,
    Invalid_Argument,
    Type_Mismatch,
    Range,
    Capacity,
}

// SQLite failure details or a substrate validation outcome for one operation.
Error :: struct {
    operation: Operation,
    result: raw.Result,
    extended_result: i32,
    validation: Validation_Error,
}

// One explicitly opened, thread-confined SQLite connection.
Connection :: struct {
    handle: ^raw.Database,
}

// One persistent statement tied to its connection's lifetime.
Statement :: struct {
    handle: ^raw.Statement,
    database: ^raw.Database,
}

// Preserve the SQLite and operation details for one native failure.
sqlite_make_error :: proc(
    operation: Operation, database: ^raw.Database, result: raw.Result) -> Error {
    extended_result: i32
    if database != nil {
        extended_result = i32(raw.sqlite3_extended_errcode(database))
    }
    return Error{
        operation = operation,
        result = result,
        extended_result = extended_result,
    }
}

// Describe one substrate-side validation failure without fabricating an SQLite code.
sqlite_make_validation_error :: proc(
    operation: Operation, validation: Validation_Error) -> Error {
    return Error{operation = operation, validation = validation}
}
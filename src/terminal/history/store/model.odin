package termhiststore

import protocol "../../../core/protocol"
import sqlite "../../../sqlite"

// History_Record is the stable metadata stored for one submitted source.
History_Record :: struct {
    submission_id: u64,
    mode: protocol.Evaluation_Mode,
    submitted_at_unix_ms: i64,
    terminal_generation: u64,
    source_revision: u64,
}

// History_Update_Request groups one expected-revision continuation mutation.
History_Update_Request :: struct {
    submission_id: u64,
    expected_revision: u64,
    new_revision: u64,
    mode: protocol.Evaluation_Mode,
    source: string,
}

// History_Store_Error_Kind classifies rejected input and SQLite failures.
History_Store_Error_Kind :: enum u8 {
    None,
    Invalid_State,
    Invalid_Argument,
    Integer_Range,
    Capacity,
    Invalid_Data,
    Conflict,
    Sqlite,
}

// History_Store_Error retains SQLite detail and any cleanup failure.
History_Store_Error :: struct {
    kind: History_Store_Error_Kind,
    sqlite_error: sqlite.Error,
    cleanup_error: sqlite.Error,
}

// History_Write_Outcome distinguishes a committed mutation from failure or conflict.
History_Write_Outcome :: enum u8 {
    Failed,
    Stored,
    Updated,
    Conflict,
}

// History_Write_Result reports one insert or expected-revision update.
History_Write_Result :: struct {
    outcome: History_Write_Outcome,
    failure: History_Store_Error,
}

// History_Read_Outcome distinguishes a row, an absent identity, and a boundary.
History_Read_Outcome :: enum u8 {
    Failed,
    Found,
    Not_Found,
    Boundary,
}

// History_Read_Result returns copied source length and metadata without owning text.
History_Read_Result :: struct {
    outcome: History_Read_Outcome,
    record: History_Record,
    source_length: int,
    failure: History_Store_Error,
}

// History_Store owns prepared statements while borrowing the caller's connection.
History_Store :: struct {
    connection: ^sqlite.Connection,
    insert: sqlite.Statement,
    update: sqlite.Statement,
    get_by_id: sqlite.Statement,
    older: sqlite.Statement,
    newer: sqlite.Statement,
    initialized: bool,
}

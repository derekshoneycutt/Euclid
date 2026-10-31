package termhiststore

import protocol "../../../core/protocol"
import sqlite "../../../sqlite"
import termhistsearch "../../../terminal/history/search"
import pcre2 "../../../pcre2"
import "base:runtime"

// History_Record is the stable metadata stored for one submitted source.
History_Record_Scope :: enum u8 {
    Session,
    Persistent,
}

History_Record :: struct {
    submission_id: u64,
    persistent_entry_id: u64,
    scope: History_Record_Scope,
    source_id: u64,
    mode: protocol.Evaluation_Mode,
    submitted_at_unix_ms: i64,
    terminal_generation: u64,
    source_revision: u64,
}

// History_Browse_Cursor is the deterministic cross-scope ordering position.
History_Browse_Cursor :: struct {
    submitted_at_unix_ms: i64,
    scope: History_Record_Scope,
    source_id: u64,
}

// History_Update_Request groups one expected-revision continuation mutation.
History_Update_Request :: struct {
    submission_id: u64,
    persistent_entry_id: u64,
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
    Search,
    Cancelled,
}

// History_Store_Error retains SQLite detail and any cleanup failure.
History_Store_Error :: struct {
    kind: History_Store_Error_Kind,
    sqlite_error: sqlite.Error,
    cleanup_error: sqlite.Error,
    search_error: termhistsearch.Search_Error,
    engine_error: int,
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
    persistent_entry_id: u64,
    failure: History_Store_Error,
    persistence_failed: bool,
    persistence_failure: History_Store_Error,
}

// History_Clear_Outcome distinguishes a committed deletion from failure.
History_Clear_Outcome :: enum u8 {
    Failed,
    Cleared,
}

// History_Clear_Result reports whether both scopes were cleared transactionally.
History_Clear_Result :: struct {
    outcome: History_Clear_Outcome,
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

// Search bounds are bytes and matching result rows, not execution-time limits.
HISTORY_SEARCH_QUERY_MAX_BYTES :: 1024
HISTORY_SEARCH_RESULT_MAX :: 64
HISTORY_SEARCH_SUMMARY_MAX_BYTES :: 256

// An invalid cursor starts Older at the newest end, or Newer at the oldest end.
History_Search_Direction :: enum u8 {
    Older,
    Newer,
}

// Search reuses the browse tuple; session-only order uses only its session source_id.
History_Search_Request :: struct {
    query: string,
    search_identity: u64,
    direction: History_Search_Direction,
    cursor: History_Browse_Cursor,
    cursor_valid: bool,
    include_persistent: bool,
    result_limit: int,
}

// Summary offsets borrow the caller's byte destination, never SQLite column storage.
// Source is an unflattened, uninterpreted grapheme-safe prefix, not recall text.
History_Candidate_Summary :: struct {
    record: History_Record,
    source_length: int,
    summary_offset: int,
    summary_length: int,
    summary_clipped: bool,
    matches: History_Row_Matches,
}

// Row decoration borrows the joined page's packed bounded range storage.
History_Row_Matches :: struct {
    offset: int,
    count: int,
    failure: History_Store_Error,
}

// Bounded presentation output; a failure publishes no authoritative partial emphasis.
History_Match_Ranges :: struct {
    ranges: [termhistsearch.HISTORY_SEARCH_RANGE_MAX]termhistsearch.Search_Range,
    count: int,
    failure: History_Store_Error,
}

History_Search_Outcome :: enum u8 {
    Failed,
    Complete,
}

// Only row_count and summary_bytes are published on success. SQL lookahead reports
// exhaustion. Byte pressure leaves the unconsumed matching row beyond the cursor.
History_Search_Result :: struct {
    outcome: History_Search_Outcome,
    row_count: int,
    summary_bytes: int,
    cursor: History_Browse_Cursor,
    cursor_valid: bool,
    exhausted: bool,
    output_full: bool,
    failure: History_Store_Error,
    skipped_regex_count: int,
}

// History_Store owns prepared statements while borrowing the caller's connection.
History_Store :: struct {
    connection: ^sqlite.Connection,
    insert: sqlite.Statement,
    insert_persistent: sqlite.Statement,
    insert_linked_session: sqlite.Statement,
    update: sqlite.Statement,
    update_persistent: sqlite.Statement,
    get_by_id: sqlite.Statement,
    get_persistent_by_id: sqlite.Statement,
    older: sqlite.Statement,
    newer: sqlite.Statement,
    combined_older: sqlite.Statement,
    combined_newer: sqlite.Statement,
    combined_latest: sqlite.Statement,
    search_older: sqlite.Statement,
    search_newer: sqlite.Statement,
    search_combined_older: sqlite.Statement,
    search_combined_newer: sqlite.Statement,
    delete_persistent: sqlite.Statement,
    delete_session: sqlite.Statement,
    durable_available: bool,
    initialized: bool,
    search: History_Admitted_Search,
    search_adapter: History_Search_Adapter,
    search_cancel: pcre2.Cancel_Token,
}

// One worker-admitted search retains compiled resources across pages and range requests.
History_Admitted_Search :: struct {
    identity: u64,
    admitted: bool,
    failure: History_Store_Error,
    query: [HISTORY_SEARCH_QUERY_MAX_BYTES]u8,
    query_length: int,
    plan: termhistsearch.Search_Plan,
    workspace: termhistsearch.Search_Workspace,
    compile_count: u64,
}

// Registration borrows this stable store child until SQLite invokes its destructor.
// Execution, progress, and callback source borrows end before connection release.
History_Search_Adapter :: struct {
    saved_context: runtime.Context,
    registered: bool,
    active: ^History_Admitted_Search,
    cancel: ^pcre2.Cancel_Token,
    failure: History_Store_Error,
    previous_progress: sqlite.Progress_Handler,
    progress_interval: int,
    progress_ticks: int,
}

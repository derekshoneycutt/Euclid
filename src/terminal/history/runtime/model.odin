package historyruntime

import protocol "../../../core/protocol"
import sqlite "../../../sqlite"
import taskpool "../../../taskpool"
import termhiststore "../store"

HISTORY_RUNTIME_MUTATION_CAPACITY :: 8
HISTORY_RUNTIME_MUTATION_SOURCE_BUDGET :: 1024 * 1024
HISTORY_RUNTIME_READ_CAPACITY :: 8
HISTORY_RUNTIME_SOURCE_CAPACITY :: protocol.TERMINAL_RETAINED_TEXT_MAX_BYTES
History_Source_Buffer :: [HISTORY_RUNTIME_SOURCE_CAPACITY]u8

History_Runtime_Status :: enum u8 {
    Uninitialized,
    Initializing,
    Ready,
    Unavailable,
    Failed,
    Closing,
    Closed,
}

History_Persistence_Status :: enum u8 {
    Unknown,
    Ready,
    Unavailable,
    Failed,
}

History_Mutation_Kind :: enum u8 {
    None,
    Insert,
    Update,
    Clear,
}

History_Mutation :: struct {
    kind: History_Mutation_Kind,
    record: termhiststore.History_Record,
    update: termhiststore.History_Update_Request,
    source_length: int,
    persist_insert: bool,
}

History_Read_Kind :: enum u8 {
    By_Id,
    Latest,
    Older,
    Newer,
}

History_Read_Priority :: enum u8 {
    Interactive,
    Speculative,
}

// Routing is independent of scheduling priority; explorer results use separate mailboxes.
History_Read_Target :: enum u8 {
    Navigation,
    Highlighting,
}

History_Read_Request :: struct {
    kind: History_Read_Kind,
    priority: History_Read_Priority,
    target: History_Read_Target,
    submission_id: u64,
    source_scope: termhiststore.History_Record_Scope,
    request_id: u64,
    terminal_generation: u64,
    navigation_epoch: u64,
    source_revision: u64,
    face_generation: u64,
    cursor: termhiststore.History_Browse_Cursor,
    cursor_valid: bool,
    visibility_epoch: u64,
}

// The display captures this identity when starting a query. runtime_epoch also retires
// work across close/reopen, committed mutations, and repeated caller generations.
History_Explorer_Identity :: struct {
    terminal_generation: u64,
    opening_generation: u64,
    query_generation: u64,
    visibility_epoch: u64,
    runtime_epoch: u64,
}

// scan.query is borrowed only during admission, then copied into runtime-owned bytes.
History_Search_Request :: struct {
    identity: History_Explorer_Identity,
    request_id: u64,
    scan: termhiststore.History_Search_Request,
    query_length: int,
}

// Preview requires a scope-qualified identity and exact source revision.
History_Preview_Request :: struct {
    identity: History_Explorer_Identity,
    request_id: u64,
    scope: termhiststore.History_Record_Scope,
    source_id: u64,
    source_revision: u64,
}

History_Search_Completion :: struct {
    ready: bool,
    request: History_Search_Request,
    result: termhiststore.History_Search_Result,
}

History_Preview_Completion :: struct {
    ready: bool,
    request: History_Preview_Request,
    result: termhiststore.History_Read_Result,
}

// Launch-owned reusable transport storage, not a retained-command mirror.
HISTORY_RUNTIME_SEARCH_ROW_CAPACITY :: 32
HISTORY_RUNTIME_SEARCH_SUMMARY_BYTES ::
    HISTORY_RUNTIME_SEARCH_ROW_CAPACITY * termhiststore.HISTORY_SEARCH_SUMMARY_MAX_BYTES
History_Search_Row_Buffer ::
    [HISTORY_RUNTIME_SEARCH_ROW_CAPACITY]termhiststore.History_Candidate_Summary

History_Runtime_Enqueue_Result :: enum u8 {
    Queued,
    Not_Ready,
    Shutting_Down,
    Queue_Full,
    Source_Too_Large,
    Source_Budget_Exceeded,
    Invalid_Request,
}

History_Runtime_Task_Kind :: enum u8 {
    None,
    Initialize,
    Mutation,
    Read,
    Search,
    Preview,
    Destroy,
}

History_Read_Completion :: struct {
    ready: bool,
    request: History_Read_Request,
    result: termhiststore.History_Read_Result,
}

History_Runtime :: struct {
    connection: ^sqlite.Connection,
    store: termhiststore.History_Store,
    status: History_Runtime_Status,
    initialization_failure: termhiststore.History_Store_Error,
    destroy_failure: termhiststore.History_Store_Error,
    last_write_result: termhiststore.History_Write_Result,
    last_completed_mutation: History_Mutation,
    write_completion_serial: u64,
    next_submission_id: u64,
    last_read_result: termhiststore.History_Read_Result,
    last_task_result: taskpool.Task_Result,
    task_kind: History_Runtime_Task_Kind,
    task_handle: taskpool.Task_Handle,
    task_active: bool,
    shutdown_requested: bool,
    retire_reads: bool,
    shutdown_failed: bool,
    persist_enabled: bool,
    persistence_status: History_Persistence_Status,
    visibility_epoch: u64,

    queued_mutations: [HISTORY_RUNTIME_MUTATION_CAPACITY]History_Mutation,
    queued_sources: [HISTORY_RUNTIME_MUTATION_CAPACITY]History_Source_Buffer,
    mutation_head: int,
    mutation_count: int,
    queued_source_bytes: int,

    active_mutation: History_Mutation,
    active_source: History_Source_Buffer,
    active_read_request: History_Read_Request,
    active_write_result: termhiststore.History_Write_Result,
    active_clear_result: termhiststore.History_Clear_Result,
    last_clear_result: termhiststore.History_Clear_Result,
    clear_completion_serial: u64,
    active_read_result: termhiststore.History_Read_Result,

    interactive_reads: [HISTORY_RUNTIME_READ_CAPACITY]History_Read_Request,
    interactive_read_count: int,
    speculative_reads: [HISTORY_RUNTIME_READ_CAPACITY]History_Read_Request,
    speculative_read_count: int,
    read_result_request: History_Read_Request,
    read_result: termhiststore.History_Read_Result,
    read_result_source: History_Source_Buffer,
    read_result_ready: bool,
    terminal_generation: u64,

    // Display-owned coalescing slots and published mailboxes. Active payloads and
    // output bytes are worker-borrowed until join; invalidation never touches them.
    explorer_identity: History_Explorer_Identity,
    explorer_epoch: u64,
    latest_search_request_id: u64,
    latest_preview_request_id: u64,
    queued_search: History_Search_Request,
    queued_query: [termhiststore.HISTORY_SEARCH_QUERY_MAX_BYTES]u8,
    search_pending: bool,
    queued_preview: History_Preview_Request,
    preview_pending: bool,
    active_search: History_Search_Request,
    active_query: [termhiststore.HISTORY_SEARCH_QUERY_MAX_BYTES]u8,
    active_preview: History_Preview_Request,
    active_search_result: termhiststore.History_Search_Result,
    active_preview_result: termhiststore.History_Read_Result,
    search_completion: History_Search_Completion,
    preview_completion: History_Preview_Completion,
    search_rows: History_Search_Row_Buffer,
    search_summaries: [HISTORY_RUNTIME_SEARCH_SUMMARY_BYTES]u8,
    preview_source: History_Source_Buffer,
}

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

History_Mutation_Kind :: enum u8 {
    None,
    Insert,
    Update,
}

History_Mutation :: struct {
    kind: History_Mutation_Kind,
    record: termhiststore.History_Record,
    update: termhiststore.History_Update_Request,
    source_length: int,
}

History_Read_Kind :: enum u8 {
    By_Id,
    Older,
    Newer,
}

History_Read_Priority :: enum u8 {
    Interactive,
    Speculative,
}

History_Read_Request :: struct {
    kind: History_Read_Kind,
    priority: History_Read_Priority,
    submission_id: u64,
    request_id: u64,
    terminal_generation: u64,
    navigation_epoch: u64,
    source_revision: u64,
    face_generation: u64,
}

History_Runtime_Enqueue_Result :: enum u8 {
    Queued,
    Not_Ready,
    Shutting_Down,
    Queue_Full,
    Source_Too_Large,
    Source_Budget_Exceeded,
}

History_Runtime_Task_Kind :: enum u8 {
    None,
    Initialize,
    Mutation,
    Read,
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

    queued_mutations: [HISTORY_RUNTIME_MUTATION_CAPACITY]History_Mutation,
    queued_sources: [HISTORY_RUNTIME_MUTATION_CAPACITY]History_Source_Buffer,
    mutation_head: int,
    mutation_count: int,
    queued_source_bytes: int,

    active_mutation: History_Mutation,
    active_source: History_Source_Buffer,
    active_read_request: History_Read_Request,
    active_write_result: termhiststore.History_Write_Result,
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
}

package terminalview

import historyruntime "../../terminal/history/runtime"
import termhiststore "../../terminal/history/store"
import protocol "../../core/protocol"
import sqlite "../../sqlite"
import taskpool "../../taskpool"
import viewuserdata "../userdata"
import log "core:log"

// Attach the launch-owned record service to a Terminal generation without clearing rows.
history_runtime_attach_generation :: proc(
    history: ^historyruntime.History_Runtime, generation: u64) {
    if history == nil || history^.shutdown_requested {
        return
    }
    history^.terminal_generation = generation
    history^.interactive_read_count = 0
    history^.speculative_read_count = 0
    history^.read_result_ready = false
    history^.retire_reads = false
}

// Bind the borrowed launch connection and explicitly publish unavailable state when absent.
history_runtime_start :: proc(
    history: ^historyruntime.History_Runtime, connection: ^sqlite.Connection) {
    if history == nil {
        return
    }
    if connection == nil || connection.handle == nil {
        history^.status = .Unavailable
        history^.initialization_failure.kind = .Invalid_State
        log.warn("terminal_history_unavailable reason=no_connection")
        return
    }
    history^.connection = connection
    history^.status = .Uninitialized
}

// Report pending history work so the shared connection scheduler can honor its turn.
history_runtime_has_work :: proc(
    history: ^historyruntime.History_Runtime) -> bool {
    if history == nil {
        return false
    }
    return history^.task_active || history^.mutation_count > 0 ||
        history^.interactive_read_count > 0 ||
        history^.speculative_read_count > 0 ||
        (history^.status == .Uninitialized && history^.connection != nil)
}

// Report queued or active tasks that must be joined before the pool can stop.
history_runtime_has_pending_tasks :: proc(
    history: ^historyruntime.History_Runtime) -> bool {
    return history != nil && (history^.task_active ||
        history^.mutation_count > 0 || history^.interactive_read_count > 0 ||
        history^.speculative_read_count > 0)
}

// Retire pending UI reads while preserving queued mutations and retained TEMP rows.
history_runtime_retire_reads :: proc(
    history: ^historyruntime.History_Runtime) {
    if history == nil {
        return
    }
    history^.retire_reads = true
    history^.interactive_read_count = 0
    history^.speculative_read_count = 0
    history^.read_result_ready = false
}

// Mark final shutdown and retire read requests before draining accepted writes.
history_runtime_begin_shutdown :: proc(
    history: ^historyruntime.History_Runtime) {
    if history == nil {
        return
    }
    history^.shutdown_requested = true
    history_runtime_retire_reads(history)
}

// Copy one immutable insert into the bounded launch-owned mutation queue.
history_runtime_enqueue_insert :: proc(
    history: ^historyruntime.History_Runtime,
    record: termhiststore.History_Record,
    source: string) -> historyruntime.History_Runtime_Enqueue_Result {
    mutation: historyruntime.History_Mutation = {
        kind = .Insert,
        record = record,
    }
    return history_runtime_enqueue_mutation(history, mutation, source)
}

// Copy one immutable expected-revision update into the bounded mutation queue.
history_runtime_enqueue_update :: proc(
    history: ^historyruntime.History_Runtime,
    request: termhiststore.History_Update_Request) ->
        historyruntime.History_Runtime_Enqueue_Result {
    mutation: historyruntime.History_Mutation = {
        kind = .Update,
        update = request,
    }
    mutation.update.source = ""
    return history_runtime_enqueue_mutation(history, mutation, request.source)
}

// Admit a source only when both independent queue limits have room.
history_runtime_enqueue_mutation :: proc(
    history: ^historyruntime.History_Runtime,
    mutation: historyruntime.History_Mutation,
    source: string) -> historyruntime.History_Runtime_Enqueue_Result {
    if history == nil || (history^.status != .Ready &&
        history^.status != .Uninitialized &&
        history^.status != .Initializing) {
        return .Not_Ready
    }
    if history^.shutdown_requested {
        return .Shutting_Down
    }
    if len(source) > protocol.TERMINAL_RETAINED_TEXT_MAX_BYTES {
        return .Source_Too_Large
    }
    if history^.mutation_count >= historyruntime.HISTORY_RUNTIME_MUTATION_CAPACITY {
        return .Queue_Full
    }
    if len(source) > historyruntime.HISTORY_RUNTIME_MUTATION_SOURCE_BUDGET -
       history^.queued_source_bytes {
        return .Source_Budget_Exceeded
    }
    slot := history_runtime_mutation_tail(history)
    history^.queued_mutations[slot] = mutation
    history^.queued_mutations[slot].source_length = len(source)
    copy(history^.queued_sources[slot][:len(source)], transmute([]u8)source)
    history^.mutation_count += 1
    history^.queued_source_bytes += len(source)
    return .Queued
}

// Reserve a launch-unique ID for one accepted Terminal submission.
history_runtime_reserve_submission_id :: proc(
    history: ^historyruntime.History_Runtime) -> u64 {
    if history == nil ||
       history^.next_submission_id >= max(u64) - 1 {
        return 0
    }
    history^.next_submission_id += 1
    return history^.next_submission_id
}

// Queue an identity lookup in the bounded interactive or speculative read lane.
history_runtime_request_read :: proc(
    history: ^historyruntime.History_Runtime,
    request: historyruntime.History_Read_Request) -> bool {
    if history == nil || history^.status != .Ready ||
       history^.shutdown_requested || history^.retire_reads ||
       request.submission_id == 0 ||
       request.request_id == 0 || request.terminal_generation == 0 ||
       request.terminal_generation != history^.terminal_generation {
        return false
    }
    if request.priority == .Interactive {
        if history^.interactive_read_count >=
           historyruntime.HISTORY_RUNTIME_READ_CAPACITY {
            return false
        }
        history^.interactive_reads[history^.interactive_read_count] = request
        history^.interactive_read_count += 1
        return true
    }
    if request.priority != .Speculative ||
       history^.speculative_read_count >= historyruntime.HISTORY_RUNTIME_READ_CAPACITY {
        return false
    }
    history^.speculative_reads[history^.speculative_read_count] = request
    history^.speculative_read_count += 1
    return true
}

// Copy a joined read result before allowing the reusable result array to be overwritten.
history_runtime_consume_read_result :: proc(
    history: ^historyruntime.History_Runtime,
    destination: []u8) -> (historyruntime.History_Read_Completion, bool) {
    if history == nil || !history^.read_result_ready {
        return {}, false
    }
    result := history^.read_result
    if result.outcome == .Found {
        if result.source_length < 0 || result.source_length > len(destination) ||
           result.source_length > len(history^.read_result_source) {
            return {
                ready = true,
                request = history^.read_result_request,
                result = history_runtime_read_capacity_failure(&result),
            }, false
        }
        copy(destination[:result.source_length],
            history^.read_result_source[:result.source_length])
        history_runtime_clear_bytes(
            history^.read_result_source[:result.source_length])
    }
    completion: historyruntime.History_Read_Completion = {
        ready = true,
        request = history^.read_result_request,
        result = result,
    }
    history^.read_result_ready = false
    history^.read_result_request = {}
    history^.read_result = {}
    return completion, true
}

// Service one joined task or admit the next write, interactive read, or speculative read.
history_runtime_service :: proc(
    history: ^historyruntime.History_Runtime,
    admission: ^protocol.User_Data_Connection_Admission,
    pool: ^taskpool.Task_Pool,
    settings_ready: bool,
    drain_work: bool = false) {
    if history == nil || admission == nil || pool == nil {
        return
    }
    history_runtime_poll_active(history, admission, pool)
    if history^.task_active || history^.status == .Failed ||
       history^.status == .Unavailable || history^.status == .Closed {
        return
    }
    if history^.status == .Uninitialized {
        if !drain_work {
            _ = history_runtime_submit_initialization(
                history, admission, pool, settings_ready, false)
        }
        return
    }
    if history^.status != .Ready || history^.shutdown_requested {
        return
    }
    if history^.mutation_count > 0 {
        _ = history_runtime_submit_mutation(
            history, admission, pool, settings_ready, drain_work)
        return
    }
    if history^.read_result_ready || history^.retire_reads {
        return
    }
    _ = history_runtime_submit_read(
        history, admission, pool, settings_ready, drain_work)
}

// Stop new history work, retire reads, and submit a joined statement teardown when ready.
history_runtime_shutdown_step :: proc(
    history: ^historyruntime.History_Runtime,
    admission: ^protocol.User_Data_Connection_Admission,
    pool: ^taskpool.Task_Pool,
    settings_ready: bool) -> bool {
    if history == nil || admission == nil || pool == nil {
        return true
    }
    history^.shutdown_requested = true
    history_runtime_retire_reads(history)
    history_runtime_poll_active(history, admission, pool)
    if history^.task_active {
        return false
    }
    if history^.status == .Closed {
        return true
    }
    if history^.status == .Failed && history^.destroy_failure.kind != .None {
        return false
    }
    if history^.mutation_count > 0 && history^.store.initialized {
        _ = history_runtime_submit_mutation(
            history, admission, pool, settings_ready, true)
        return false
    }
    if history^.store.initialized {
        _ = history_runtime_submit_destroy(
            history, admission, pool, settings_ready)
        return false
    }
    history^.status = .Closed
    return true
}

// Admit one initialization task through shared connection ownership.
history_runtime_submit_initialization :: proc(
    history: ^historyruntime.History_Runtime,
    admission: ^protocol.User_Data_Connection_Admission,
    pool: ^taskpool.Task_Pool,
    settings_ready, drain_work: bool) -> bool {
    if !history_runtime_claim(history, admission, settings_ready, drain_work) {
        return false
    }
    if !history_runtime_submit_claimed(
        history, admission, pool, .Initialize) {
        return false
    }
    if history^.status != .Failed {
        history^.status = .Initializing
    }
    return true
}

// Move the queue head into the active payload only after claiming the connection.
history_runtime_submit_mutation :: proc(
    history: ^historyruntime.History_Runtime,
    admission: ^protocol.User_Data_Connection_Admission,
    pool: ^taskpool.Task_Pool,
    settings_ready, drain_work: bool) -> bool {
    if history^.mutation_count == 0 ||
       !history_runtime_claim(history, admission, settings_ready, drain_work) {
        return false
    }
    slot := history^.mutation_head
    mutation := history^.queued_mutations[slot]
    history^.active_mutation = mutation
    copy(history^.active_source[:mutation.source_length],
        history^.queued_sources[slot][:mutation.source_length])
    if !history_runtime_submit_claimed(history, admission, pool, .Mutation) {
        history_runtime_clear_active_mutation(history)
        return false
    }
    history_runtime_pop_mutation(history)
    return true
}

// Submit the highest-priority queued read after all writes have been admitted.
history_runtime_submit_read :: proc(
    history: ^historyruntime.History_Runtime,
    admission: ^protocol.User_Data_Connection_Admission,
    pool: ^taskpool.Task_Pool,
    settings_ready, drain_work: bool) -> bool {
    if !history_runtime_has_queued_reads(history) ||
       !history_runtime_claim(history, admission, settings_ready, drain_work) {
        return false
    }
    history^.active_read_request = history_runtime_pop_read(history)
    if !history_runtime_submit_claimed(history, admission, pool, .Read) {
        history_runtime_restore_read(history, history^.active_read_request)
        history^.active_read_request = {}
        return false
    }
    return true
}

// Submit statement finalization as worker-only work under the shared drain lease.
history_runtime_submit_destroy :: proc(
    history: ^historyruntime.History_Runtime,
    admission: ^protocol.User_Data_Connection_Admission,
    pool: ^taskpool.Task_Pool,
    settings_ready: bool) -> bool {
    if !history_runtime_claim(history, admission, settings_ready, true) {
        return false
    }
    return history_runtime_submit_claimed(history, admission, pool, .Destroy)
}

// Claim exclusive connection access while honoring the other ready borrower's turn.
history_runtime_claim :: proc(
    history: ^historyruntime.History_Runtime,
    admission: ^protocol.User_Data_Connection_Admission,
    settings_ready, drain_work: bool) -> bool {
    return viewuserdata.connection_admission_claim(
        admission, .Terminal_History, settings_ready, drain_work)
}

// Submit one prepared operation and release its claim if the task pool rejects it.
history_runtime_submit_claimed :: proc(
    history: ^historyruntime.History_Runtime,
    admission: ^protocol.User_Data_Connection_Admission,
    pool: ^taskpool.Task_Pool,
    kind: historyruntime.History_Runtime_Task_Kind) -> bool {
    history^.task_kind = kind
    handle, outcome := taskpool.task_pool_submit(
        pool, history_runtime_worker, rawptr(history), .Worker_Only)
    if outcome != .Queued {
        history^.task_kind = .None
        if !viewuserdata.connection_admission_release_rejected(
            admission, .Terminal_History) {
            log.error("terminal_history_rejected_admission_release_failed")
        }
        if outcome == .Pool_Stopped {
            history^.status = .Failed
            history^.shutdown_failed = true
            log.error("terminal_history_task_pool_stopped")
        }
        return false
    }
    if !viewuserdata.connection_admission_mark_submitted(
        admission, .Terminal_History) {
        history^.status = .Failed
        history^.shutdown_failed = true
        log.error("terminal_history_admission_submit_transition_failed")
    }
    history^.task_handle = handle
    history^.task_active = true
    return true
}

// Execute one SQLite operation using only the stable active payload and result arrays.
history_runtime_worker :: proc(
    payload: rawptr,
    token: taskpool.Task_Cancellation_Token) -> taskpool.Task_Result {
    _ = token
    history := cast(^historyruntime.History_Runtime)payload
    switch history^.task_kind {
    case .Initialize:
        history^.initialization_failure = termhiststore.history_store_init(
            &history^.store, history^.connection)
        return .Failed if history^.initialization_failure.kind != .None else .Succeeded
    case .Mutation:
        return history_runtime_worker_mutation(history)
    case .Read:
        return history_runtime_worker_read(history)
    case .Destroy:
        history^.destroy_failure = termhiststore.history_store_destroy(&history^.store)
        return .Failed if history^.destroy_failure.kind != .None else .Succeeded
    case .None:
        return .Failed
    }
    return .Failed
}

// Execute the immutable insert or continuation update from the active source array.
history_runtime_worker_mutation :: proc(
    history: ^historyruntime.History_Runtime) -> taskpool.Task_Result {
    source := string(history^.active_source[:history^.active_mutation.source_length])
    if history^.active_mutation.kind == .Insert {
        history^.active_write_result = termhiststore.history_store_insert(
            &history^.store, history^.active_mutation.record, source)
    } else if history^.active_mutation.kind == .Update {
        request := history^.active_mutation.update
        request.source = source
        history^.active_write_result = termhiststore.history_store_update_expected(
            &history^.store, request)
    } else {
        return .Failed
    }
    return .Failed if history^.active_write_result.outcome ==
        .Failed else .Succeeded
}

// Execute one keyed read into the runtime's single reusable result-source array.
history_runtime_worker_read :: proc(
    history: ^historyruntime.History_Runtime) -> taskpool.Task_Result {
    request := history^.active_read_request
    switch request.kind {
    case .By_Id:
        history^.active_read_result = termhiststore.history_store_get_by_id(
            &history^.store, request.submission_id, history^.read_result_source[:])
    case .Older:
        history^.active_read_result = termhiststore.history_store_older(
            &history^.store, request.submission_id, history^.read_result_source[:])
    case .Newer:
        history^.active_read_result = termhiststore.history_store_newer(
            &history^.store, request.submission_id, history^.read_result_source[:])
    }
    return .Failed if history^.active_read_result.outcome ==
        .Failed else .Succeeded
}

// Join one completed task before publishing results or releasing its payload storage.
history_runtime_poll_active :: proc(
    history: ^historyruntime.History_Runtime,
    admission: ^protocol.User_Data_Connection_Admission,
    pool: ^taskpool.Task_Pool) {
    if !history^.task_active {
        return
    }
    poll := taskpool.task_pool_poll(pool, history^.task_handle)
    if poll == .Pending {
        return
    }
    if poll == .Stale_Handle {
        history^.status = .Failed
        log.error("terminal_history_handle_stale")
        return
    }
    result, joined := taskpool.task_pool_wait(pool, history^.task_handle)
    if joined != .Joined {
        history^.status = .Failed
        log.error("terminal_history_join_failed")
        return
    }
    history^.task_active = false
    history^.last_task_result = result
    history_runtime_complete_task(history, result)
    if !viewuserdata.connection_admission_release_joined(
        admission, .Terminal_History) {
        history^.status = .Failed
        log.error("terminal_history_admission_release_failed")
    }
    history_runtime_clear_task_payload(history)
}

// Publish one joined operation result without releasing a read buffer prematurely.
history_runtime_complete_task :: proc(
    history: ^historyruntime.History_Runtime,
    task_result: taskpool.Task_Result) {
    switch history^.task_kind {
    case .Initialize:
        history_runtime_complete_initialization(history, task_result)
    case .Mutation:
        history_runtime_complete_mutation(history, task_result)
    case .Read:
        history_runtime_complete_read(history, task_result)
    case .Destroy:
        history_runtime_complete_destroy(history, task_result)
    case .None:
        history^.status = .Failed
        log.error("terminal_history_completed_without_operation")
    }
}

// Publish TEMP-store availability only after its initialization worker has joined.
history_runtime_complete_initialization :: proc(
    history: ^historyruntime.History_Runtime,
    task_result: taskpool.Task_Result) {
    if task_result == .Succeeded && history^.initialization_failure.kind == .None {
        history^.status = .Ready
        return
    }
    history^.status = .Unavailable
    log.warnf("terminal_history_init_failed error=%d sqlite_result=%d",
        int(history^.initialization_failure.kind),
        int(history^.initialization_failure.sqlite_error.result))
}

// Retain and report one joined mutation outcome without retrying a failed source.
history_runtime_complete_mutation :: proc(
    history: ^historyruntime.History_Runtime,
    task_result: taskpool.Task_Result) {
    history^.last_write_result = history^.active_write_result
    history^.last_completed_mutation = history^.active_mutation
    history^.write_completion_serial += 1
    if task_result != .Succeeded ||
       history^.active_write_result.outcome == .Failed {
        log.warnf("terminal_history_write_failed error=%d sqlite_result=%d",
            int(history^.active_write_result.failure.kind),
            int(history^.active_write_result.failure.sqlite_error.result))
    }
}

// Publish only reads whose Terminal generation is still attached.
history_runtime_complete_read :: proc(
    history: ^historyruntime.History_Runtime,
    task_result: taskpool.Task_Result) {
    if task_result != .Succeeded ||
       history^.active_read_result.outcome == .Failed {
        log.warnf("terminal_history_read_failed error=%d sqlite_result=%d",
            int(history^.active_read_result.failure.kind),
            int(history^.active_read_result.failure.sqlite_error.result))
        history^.last_read_result = history^.active_read_result
        if !history^.shutdown_requested && !history^.retire_reads &&
           history^.active_read_request.terminal_generation ==
               history^.terminal_generation {
            history^.read_result_request = history^.active_read_request
            history^.read_result = history^.active_read_result
            history^.read_result_ready = true
        }
        return
    }
    if history^.shutdown_requested || history^.retire_reads ||
       history^.active_read_request.terminal_generation !=
           history^.terminal_generation {
        return
    }
    history^.read_result_request = history^.active_read_request
    history^.read_result = history^.active_read_result
    history^.read_result_ready = true
    history^.last_read_result = history^.active_read_result
}

// Mark finalization complete after the worker has released every prepared statement.
history_runtime_complete_destroy :: proc(
    history: ^historyruntime.History_Runtime,
    task_result: taskpool.Task_Result) {
    if task_result == .Succeeded && history^.destroy_failure.kind == .None {
        history^.status = .Closed
        history^.connection = nil
        return
    }
    history^.status = .Failed
    history^.shutdown_failed = true
    log.errorf("terminal_history_destroy_failed error=%d sqlite_result=%d",
        int(history^.destroy_failure.kind),
        int(history^.destroy_failure.sqlite_error.result))
}

// Release active source storage only after its task handle has been joined.
history_runtime_clear_task_payload :: proc(
    history: ^historyruntime.History_Runtime) {
    if history^.task_kind == .Mutation {
        history_runtime_clear_active_mutation(history)
    }
    if history^.task_kind == .Read {
        history^.active_read_request = {}
        history^.active_read_result = {}
    }
    history^.task_kind = .None
}

// Clear the single active mutation payload after the worker join.
history_runtime_clear_active_mutation :: proc(
    history: ^historyruntime.History_Runtime) {
    history_runtime_clear_bytes(
        history^.active_source[:history^.active_mutation.source_length])
    history^.active_mutation = {}
    history^.active_write_result = {}
}

// Release the queue head's source bytes and update bounded waiting accounting.
history_runtime_pop_mutation :: proc(
    history: ^historyruntime.History_Runtime) {
    slot := history^.mutation_head
    source_length := history^.queued_mutations[slot].source_length
    history_runtime_clear_bytes(history^.queued_sources[slot][:source_length])
    history^.queued_source_bytes -= source_length
    history^.queued_mutations[slot] = {}
    history^.mutation_head =
        (history^.mutation_head + 1) % historyruntime.HISTORY_RUNTIME_MUTATION_CAPACITY
    history^.mutation_count -= 1
}

// Return the ring slot where the next admitted mutation will be stored.
history_runtime_mutation_tail :: proc(
    history: ^historyruntime.History_Runtime) -> int {
    return (history^.mutation_head + history^.mutation_count) %
        historyruntime.HISTORY_RUNTIME_MUTATION_CAPACITY
}

// Report whether either read lane has pending requests.
history_runtime_has_queued_reads :: proc(
    history: ^historyruntime.History_Runtime) -> bool {
    return history^.interactive_read_count > 0 ||
        history^.speculative_read_count > 0
}

// Remove the next interactive read, falling back to the speculative lane.
history_runtime_pop_read :: proc(
    history: ^historyruntime.History_Runtime) -> historyruntime.History_Read_Request {
    if history^.interactive_read_count > 0 {
        request := history^.interactive_reads[0]
        history_runtime_shift_reads(
            history^.interactive_reads[:], &history^.interactive_read_count)
        return request
    }
    request := history^.speculative_reads[0]
    history_runtime_shift_reads(
        history^.speculative_reads[:], &history^.speculative_read_count)
    return request
}

// Restore a temporarily removed request when worker submission is rejected.
history_runtime_restore_read :: proc(
    history: ^historyruntime.History_Runtime,
    request: historyruntime.History_Read_Request) {
    if request.priority == .Interactive {
        history_runtime_prepend_read(
            history^.interactive_reads[:], &history^.interactive_read_count, request)
        return
    }
    history_runtime_prepend_read(
        history^.speculative_reads[:], &history^.speculative_read_count, request)
}

// Shift one read lane after removing its head request.
history_runtime_shift_reads :: proc(
    requests: []historyruntime.History_Read_Request, count: ^int) {
    for index in 1..<count^ {
        requests[index - 1] = requests[index]
    }
    count^ -= 1
    requests[count^] = {}
}

// Restore a read at the head of its fixed queue without losing request order.
history_runtime_prepend_read :: proc(
    requests: []historyruntime.History_Read_Request,
    count: ^int,
    request: historyruntime.History_Read_Request) {
    for index in 0..<count^ {
        requests[count^ - index] = requests[count^ - index - 1]
    }
    requests[0] = request
    count^ += 1
}

// Clear released source bytes while preserving fixed storage capacity.
history_runtime_clear_bytes :: proc(bytes: []u8) {
    for index in 0..<len(bytes) {
        bytes[index] = 0
    }
}

// Return a source-capacity error while leaving the pending result available for retry.
history_runtime_read_capacity_failure :: proc(
    result: ^termhiststore.History_Read_Result) -> termhiststore.History_Read_Result {
    result^.outcome = .Failed
    result^.failure.kind = .Capacity
    return result^
}

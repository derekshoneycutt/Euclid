package terminalview

import historyruntime "../../terminal/history/runtime"
import termhiststore "../../terminal/history/store"
import protocol "../../core/protocol"
import taskpool "../../taskpool"
import log "core:log"

// Start an authoritative display query without admitting SQL or modifying the editor.
history_runtime_begin_query :: proc(
    history: ^historyruntime.History_Runtime,
    opening_generation: u64,
    query_generation: u64) -> (historyruntime.History_Explorer_Identity, bool) {
    if history == nil || history^.status != .Ready || history^.retire_reads ||
       history^.shutdown_requested || history^.terminal_generation == 0 ||
       opening_generation == 0 || query_generation == 0 {
        return {}, false
    }
    history_runtime_retire_explorer(history)
    history^.explorer_identity = {
        terminal_generation = history^.terminal_generation,
        opening_generation = opening_generation,
        query_generation = query_generation,
        visibility_epoch = history^.visibility_epoch,
        runtime_epoch = history^.explorer_epoch,
    }
    return history^.explorer_identity, true
}

// Retire queued and published explorer work, never worker-borrowed active storage.
history_runtime_retire_explorer :: proc(
    history: ^historyruntime.History_Runtime) {
    if history == nil {
        return
    }
    termhiststore.history_store_cancel_search(&history.store)
    if !history.task_active {
        termhiststore.history_store_retire_search(&history.store)
    }
    history^.explorer_epoch += 1
    if history^.explorer_epoch == 0 {
        history^.explorer_epoch = 1
    }
    history^.explorer_identity = {}
    history^.latest_search_request_id = 0
    history^.latest_preview_request_id = 0
    history^.queued_search = {}
    history_runtime_clear_bytes(history^.queued_query[:])
    history^.search_pending = false
    history^.queued_preview = {}
    history^.preview_pending = false
    history^.search_completion = {}
    history^.preview_completion = {}
}

// Match every captured lifecycle component before accepting or publishing work.
history_runtime_explorer_current :: proc(
    history: ^historyruntime.History_Runtime,
    identity: historyruntime.History_Explorer_Identity) -> bool {
    return history != nil && history^.status == .Ready &&
        !history^.shutdown_requested && !history^.retire_reads &&
        identity.runtime_epoch != 0 && identity == history^.explorer_identity &&
        identity.terminal_generation == history^.terminal_generation &&
        identity.visibility_epoch == history^.visibility_epoch
}

// Report admission failure without confusing unavailable storage with empty history.
history_runtime_explorer_admission :: proc(
    history: ^historyruntime.History_Runtime,
    identity: historyruntime.History_Explorer_Identity) ->
        historyruntime.History_Runtime_Enqueue_Result {
    if history == nil || history^.status != .Ready {
        return .Not_Ready
    }
    if history^.shutdown_requested || history^.retire_reads {
        return .Shutting_Down
    }
    if !history_runtime_explorer_current(history, identity) {
        return .Invalid_Request
    }
    return .Queued
}

// Coalesce search into one display-owned slot and capture query bytes and visibility.
history_runtime_request_search :: proc(
    history: ^historyruntime.History_Runtime,
    request: historyruntime.History_Search_Request) ->
        historyruntime.History_Runtime_Enqueue_Result {
    admission := history_runtime_explorer_admission(history, request.identity)
    if admission != .Queued {
        return admission
    }
    if request.request_id == 0 ||
       request.request_id <= history^.latest_search_request_id {
        return .Invalid_Request
    }
    if len(request.page.query) > termhiststore.HISTORY_SEARCH_QUERY_MAX_BYTES {
        return .Source_Too_Large
    }
    queued := request
    queued.query_length = len(request.page.query)
    queued.page.query = ""
    queued.page.include_persistent = history^.persist_enabled &&
        history^.store.durable_available
    history_runtime_clear_bytes(history^.queued_query[:])
    copy(history^.queued_query[:queued.query_length], request.page.query)
    history^.queued_search = queued
    history^.latest_search_request_id = request.request_id
    history^.search_pending = true
    history^.search_completion = {}
    return .Queued
}

// Coalesce preview independently of search; an old candidate can never win later.
history_runtime_request_preview :: proc(
    history: ^historyruntime.History_Runtime,
    request: historyruntime.History_Preview_Request) ->
        historyruntime.History_Runtime_Enqueue_Result {
    admission := history_runtime_explorer_admission(history, request.identity)
    if admission != .Queued {
        return admission
    }
    if request.request_id == 0 ||
       request.request_id <= history^.latest_preview_request_id ||
       request.source_id == 0 || request.source_id > u64(max(i64)) ||
       request.source_revision == 0 || request.source_revision > u64(max(i64)) ||
       (request.scope != .Session && request.scope != .Persistent) {
        return .Invalid_Request
    }
    if request.scope == .Persistent &&
       (!history^.persist_enabled || !history^.store.durable_available) {
        return .Not_Ready
    }
    history^.queued_preview = request
    history^.latest_preview_request_id = request.request_id
    history^.preview_pending = true
    history^.preview_completion = {}
    return .Queued
}

// Include only queued work in scheduler readiness; published mailboxes hold no lease.
history_runtime_has_explorer_work :: proc(
    history: ^historyruntime.History_Runtime) -> bool {
    return history != nil && (history^.search_pending || history^.preview_pending)
}

// Preserve write priority, then interactive recall, preview, search, and highlighting.
history_runtime_submit_next_read :: proc(
    history: ^historyruntime.History_Runtime,
    admission: ^protocol.User_Data_Connection_Admission,
    pool: ^taskpool.Task_Pool, settings_ready, drain_work: bool) -> bool {
    if !history^.read_result_ready && history^.interactive_read_count > 0 {
        return history_runtime_submit_read(
            history, admission, pool, settings_ready, drain_work)
    }
    if (history^.preview_pending && !history^.preview_completion.ready) ||
       (history^.search_pending && !history^.search_completion.ready) {
        return history_runtime_submit_explorer(
            history, admission, pool, settings_ready, drain_work)
    }
    if !history^.read_result_ready {
        return history_runtime_submit_read(
            history, admission, pool, settings_ready, drain_work)
    }
    return false
}

// Transfer one immutable payload only after claiming the existing shared connection.
history_runtime_submit_explorer :: proc(
    history: ^historyruntime.History_Runtime,
    admission: ^protocol.User_Data_Connection_Admission,
    pool: ^taskpool.Task_Pool, settings_ready, drain_work: bool) -> bool {
    if !history_runtime_claim(history, admission, settings_ready, drain_work) {
        return false
    }
    kind := historyruntime.History_Runtime_Task_Kind.Search
    if history^.preview_pending && !history^.preview_completion.ready {
        kind = .Preview
    }
    if kind == .Search {
        termhiststore.history_store_reset_search_cancel(&history.store)
        history^.active_search = history^.queued_search
        length := history^.active_search.query_length
        copy(history^.active_query[:length], history^.queued_query[:length])
    } else {
        history^.active_preview = history^.queued_preview
    }
    if !history_runtime_submit_claimed(history, admission, pool, kind) {
        history_runtime_clear_explorer_payload(history, kind)
        return false
    }
    if kind == .Search {
        history^.queued_search = {}
        history_runtime_clear_bytes(history^.queued_query[:])
        history^.search_pending = false
    } else {
        history^.queued_preview = {}
        history^.preview_pending = false
    }
    return true
}

// Execute one SQL-filtered page using the query-generation's retained native plan.
history_runtime_worker_search :: proc(
    history: ^historyruntime.History_Runtime) -> taskpool.Task_Result {
    page := history^.active_search.page
    page.search_identity = history.active_search.identity.runtime_epoch
    page.query = string(history^.active_query[:history^.active_search.query_length])
    history^.active_search_result = termhiststore.history_store_search(
        &history^.store, page, history^.search_rows[:], history^.search_summaries[:])
    if history.active_search_result.outcome == .Complete {
        history_runtime_collect_row_matches(history)
    }
    return .Succeeded if history^.active_search_result.outcome == .Complete else .Failed
}

// Read full original source by scope without relying on scrollback or session anchors.
history_runtime_worker_preview :: proc(
    history: ^historyruntime.History_Runtime) -> taskpool.Task_Result {
    request := history^.active_preview
    result: termhiststore.History_Read_Result
    if request.scope == .Persistent {
        result = termhiststore.history_store_get_persistent_by_id(
            &history^.store, request.source_id, history^.preview_source[:])
    } else {
        result = termhiststore.history_store_get_by_id(
            &history^.store, request.source_id, history^.preview_source[:])
    }
    if result.outcome == .Found &&
       (result.record.scope != request.scope ||
        result.record.source_id != request.source_id ||
        result.record.source_revision != request.source_revision) {
        result = {
            outcome = .Failed,
            failure = {
                kind = .Conflict,
            },
        }
    }
    history^.active_preview_result = result
    history.active_preview_matches = {}
    if result.outcome == .Found {
        history.active_preview_matches = history_runtime_source_matches(
            history, request.identity,
            string(history.preview_source[:result.source_length]))
    }
    return .Failed if result.outcome == .Failed else .Succeeded
}

// Publish joined search status only to the newest request of the current query.
history_runtime_complete_search :: proc(
    history: ^historyruntime.History_Runtime, task_result: taskpool.Task_Result) {
    result := history^.active_search_result
    if task_result != .Succeeded || result.outcome == .Failed {
        if result.failure.kind == .None {
            result = {
                failure = {
                    kind = .Invalid_State,
                },
            }
        }
        if result.failure.kind != .Cancelled {
            history_runtime_report_explorer_failure("search", result.failure)
        }
    }
    request := history^.active_search
    if !history_runtime_explorer_current(history, request.identity) {
        termhiststore.history_store_retire_search(&history.store)
    }
    if history_runtime_explorer_current(history, request.identity) &&
       request.request_id == history^.latest_search_request_id {
        history^.search_completion = {
            ready = true,
            request = request,
            result = result,
            ranges = history.search_ranges,
        }
    }
}

// Publish an exact preview only to the newest candidate request of the current query.
history_runtime_complete_preview :: proc(
    history: ^historyruntime.History_Runtime, task_result: taskpool.Task_Result) {
    result := history^.active_preview_result
    if task_result != .Succeeded || result.outcome == .Failed {
        if result.failure.kind == .None {
            result = {
                outcome = .Failed,
                failure = {
                    kind = .Invalid_State,
                },
            }
        }
        history_runtime_report_explorer_failure("preview", result.failure)
    }
    request := history^.active_preview
    if history_runtime_explorer_current(history, request.identity) &&
       request.request_id == history^.latest_preview_request_id {
        history^.preview_completion = {
            ready = true,
            request = request,
            result = result,
            matches = history.active_preview_matches,
        }
    }
}

// Report typed failures without including potentially sensitive source or query text.
history_runtime_report_explorer_failure :: proc(
    operation: string, failure: termhiststore.History_Store_Error) {
    log.warnf("terminal_history_explorer_failed operation=%s error=%d "+
        "sqlite_result=%d search_error=%d engine_error=%d",
        operation, int(failure.kind), int(failure.sqlite_error.result),
        int(failure.search_error), failure.engine_error)
}

// Copy joined rows and packed summaries; insufficient destination space is retryable.
history_runtime_consume_search_result :: proc(
    history: ^historyruntime.History_Runtime,
    rows: []termhiststore.History_Candidate_Summary,
    summaries: []u8) -> (historyruntime.History_Search_Completion, bool) {
    if history == nil || !history^.search_completion.ready {
        return {}, false
    }
    completion := history^.search_completion
    if !history_runtime_explorer_current(history, completion.request.identity) {
        history^.search_completion = {}
        return {}, false
    }
    if completion.result.outcome == .Complete {
        result := completion.result
        if result.row_count > len(rows) || result.summary_bytes > len(summaries) {
            completion.result = {
                failure = {
                    kind = .Capacity,
                },
            }
            return completion, false
        }
        copy(rows[:result.row_count], history^.search_rows[:result.row_count])
        copy(summaries[:result.summary_bytes],
            history^.search_summaries[:result.summary_bytes])
        history_runtime_clear_bytes(history^.search_summaries[:result.summary_bytes])
    }
    history^.search_completion = {}
    return completion, true
}

// Copy complete original source only; capacity failure never publishes partial text.
history_runtime_consume_preview_result :: proc(
    history: ^historyruntime.History_Runtime,
    destination: []u8) -> (historyruntime.History_Preview_Completion, bool) {
    if history == nil || !history^.preview_completion.ready {
        return {}, false
    }
    completion := history^.preview_completion
    if !history_runtime_explorer_current(history, completion.request.identity) {
        history^.preview_completion = {}
        return {}, false
    }
    if completion.result.outcome == .Found {
        length := completion.result.source_length
        if length > len(destination) {
            completion.result.outcome = .Failed
            completion.result.failure.kind = .Capacity
            return completion, false
        }
        copy(destination[:length], history^.preview_source[:length])
        history_runtime_clear_bytes(history^.preview_source[:length])
    }
    history^.preview_completion = {}
    return completion, true
}

// Clear only joined or rejected payloads after their worker borrow has ended.
history_runtime_clear_explorer_payload :: proc(
    history: ^historyruntime.History_Runtime,
    kind: historyruntime.History_Runtime_Task_Kind) {
    if kind == .Search {
        history^.active_search = {}
        history^.active_search_result = {}
        history_runtime_clear_bytes(history^.active_query[:])
        if !history^.search_completion.ready ||
           history^.search_completion.result.outcome != .Complete {
            history_runtime_clear_bytes(history^.search_summaries[:])
        }
    } else if kind == .Preview {
        history^.active_preview = {}
        history^.active_preview_result = {}
        history.active_preview_matches = {}
        if !history^.preview_completion.ready ||
           history^.preview_completion.result.outcome != .Found {
            history_runtime_clear_bytes(history^.preview_source[:])
        }
    }
}

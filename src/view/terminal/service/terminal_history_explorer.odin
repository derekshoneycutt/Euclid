package terminalservice

import core "../../../core"
import historyruntime "../../../terminal/history/runtime"
import termhist "../../../terminal/history"
import termhiststore "../../../terminal/history/store"
import terminalview ".."
import terminalviewmodel "../model"
import "core:log"

// Close transient state and retire transport when Terminal loses visibility or generation.
terminal_service_retire_history_explorer :: proc(
    state: ^core.Euclid_General_State) {
    if state == nil {
        return
    }
    terminalview.history_explorer_close(&state^.terminal)
    state^.terminal.history_explorer.close_requested = false
    history := &state^.terminal_history_runtime
    if history^.explorer_identity.runtime_epoch != 0 {
        terminalview.history_runtime_retire_explorer(history)
    }
}

// Consume explorer completions, admit bounded work, and revalidate recall on the display owner.
terminal_service_update_history_explorer :: proc(
    state: ^core.Euclid_General_State) {
    if state == nil {
        return
    }
    term := &state^.terminal
    explorer := &term^.history_explorer
    if !terminal_service_explorer_is_active(state) {
        return
    }
    if !terminal_service_explorer_ready(term) {
        terminal_service_retire_history_explorer(state)
        return
    }
    history := &state^.terminal_history_runtime
    if explorer.help != .None {
        terminal_service_consume_explorer_completions(state)
        return
    }
    if explorer^.identity.runtime_epoch != 0 &&
       !terminalview.history_runtime_explorer_current(history, explorer^.identity) {
        terminalview.history_explorer_query_changed(explorer)
    }
    terminal_service_consume_explorer_completions(state)
    if terminal_service_accept_explorer_candidate(state) {
        return
    }
    if !terminal_service_start_explorer_query(state) {
        return
    }
    terminal_service_request_explorer_search(state)
    terminal_service_request_explorer_preview(state)
}

// Retire a requested close before accepting additional transport results.
terminal_service_explorer_is_active :: proc(
    state: ^core.Euclid_General_State) -> bool {
    explorer := &state^.terminal.history_explorer
    if explorer^.active {
        return true
    }
    if explorer^.close_requested {
        terminal_service_retire_history_explorer(state)
    }
    return false
}

// Require the ready prompt and exclusive local input ownership throughout exploration.
terminal_service_explorer_ready :: proc(
    term: ^terminalviewmodel.Terminal_State) -> bool {
    return term^.initialized && term^.history_explorer_open_allowed &&
        !term^.awaiting_eval && term^.banner_ready &&
        !term^.collecting_continuation &&
        term^.interactive_input_request_id == 0 &&
        term^.history != nil && !term^.history.preedit_active
}

// Accept only a ready current preview and preserve capacity failures for status display.
terminal_service_accept_explorer_candidate :: proc(
    state: ^core.Euclid_General_State) -> bool {
    term := &state^.terminal
    explorer := &term^.history_explorer
    if !explorer^.accept_requested || explorer^.preview_status != .Ready {
        return false
    }
    if terminalview.history_explorer_accept(term, explorer^.identity) {
        terminal_service_retire_history_explorer(state)
    } else {
        explorer^.accept_requested = false
        if explorer^.status != .Capacity {
            explorer^.status = .Failed
            explorer^.status_failure.kind = .Invalid_State
        }
    }
    return true
}

// Consume independent mailboxes into generation-owned page and exact-source buffers.
terminal_service_consume_explorer_completions :: proc(
    state: ^core.Euclid_General_State) {
    explorer := &state^.terminal.history_explorer
    search, consumed := terminal_service_consume_history_search(
        state, explorer^.rows, explorer^.summaries)
    if consumed && search.ready {
        terminalview.history_explorer_publish_search(explorer, search)
    } else if search.result.failure.kind == .Capacity {
        explorer^.search_pending = false
        explorer^.status = .Capacity
        explorer^.status_failure = search.result.failure
    }
    preview, copied := terminal_service_consume_history_preview(
        state, explorer^.preview_source)
    if copied && preview.ready {
        terminalview.history_explorer_publish_preview(explorer, preview)
    } else if preview.result.failure.kind == .Capacity {
        explorer^.preview_pending = false
        explorer^.preview_status = .Capacity
        explorer^.status_failure = preview.result.failure
    }
}

// Establish the current generation/query identity before search admission.
terminal_service_start_explorer_query :: proc(
    state: ^core.Euclid_General_State) -> bool {
    term := &state^.terminal
    explorer := &term^.history_explorer
    if !explorer^.query_dirty {
        return true
    }
    identity, ready := terminal_service_begin_history_query(
        state, explorer^.opening_generation, explorer^.query_generation)
    if !ready {
        history := &state^.terminal_history_runtime
        if history^.status == .Unavailable || history^.status == .Failed ||
           history^.status == .Closed || history^.status == .Closing {
            explorer^.status = .Unavailable
        } else {
            explorer^.status = .Searching
        }
        return false
    }
    explorer^.identity = identity
    explorer^.query_dirty = false
    explorer^.search_pending = false
    explorer^.preview_pending = false
    explorer^.search_direction = .Older
    explorer^.search_cursor = {}
    explorer^.search_cursor_valid = false
    explorer^.page_request = .None
    explorer^.status = .Searching
    return true
}

// Submit one chronological matching page and retain visible admission failures.
terminal_service_request_explorer_search :: proc(
    state: ^core.Euclid_General_State) {
    explorer := &state^.terminal.history_explorer
    if explorer^.identity.runtime_epoch == 0 || explorer^.search_pending ||
       explorer^.status != .Searching {
        return
    }
    explorer^.next_search_request_id += 1
    if explorer^.next_search_request_id == 0 {
        explorer^.next_search_request_id = 1
    }
    query := termhist.termhist_current_text(&explorer^.query_editor)
    request: historyruntime.History_Search_Request = {
        identity = explorer^.identity,
        request_id = explorer^.next_search_request_id,
        page = {
            query = query,
            direction = .Older if explorer^.search_direction == .Older else .Newer,
            cursor = explorer^.search_cursor,
            cursor_valid = explorer^.search_cursor_valid,
            result_limit = len(explorer^.rows),
        },
    }
    outcome := terminal_service_request_history_search(state, request)
    if outcome == .Queued {
        explorer^.search_pending = true
        explorer^.search_request_id = request.request_id
        return
    }
    terminal_service_set_explorer_admission_failure(
        explorer, "search", outcome)
}

// Fetch the exact source only for the currently selected scope-qualified candidate.
terminal_service_request_explorer_preview :: proc(
    state: ^core.Euclid_General_State) {
    explorer := &state^.terminal.history_explorer
    if !explorer^.preview_pending || explorer^.identity.runtime_epoch == 0 ||
       explorer^.selected_index < 0 ||
       explorer^.selected_index >= explorer^.row_count {
        return
    }
    row := explorer^.rows[explorer^.selected_index]
    explorer^.next_preview_request_id += 1
    if explorer^.next_preview_request_id == 0 {
        explorer^.next_preview_request_id = 1
    }
    request: historyruntime.History_Preview_Request = {
        identity = explorer^.identity,
        request_id = explorer^.next_preview_request_id,
        scope = row.record.scope,
        source_id = row.record.source_id,
        source_revision = row.record.source_revision,
    }
    outcome := terminal_service_request_history_preview(state, request)
    if outcome == .Queued {
        explorer^.preview_pending = false
        explorer^.preview_request_id = request.request_id
        explorer^.preview_status = .Loading
        return
    }
    explorer^.preview_pending = false
    explorer^.preview_status = .Failed
    if outcome == .Not_Ready {
        explorer^.status = .Unavailable
    }
    explorer^.status_failure.kind = .Invalid_State
    log.warnf("terminal_history_explorer_failed operation=preview admission=%d",
        int(outcome))
}

// Preserve typed failure states for bounded request-admission errors.
terminal_service_set_explorer_admission_failure :: proc(
    explorer: ^terminalviewmodel.History_Explorer_State,
    operation: string,
    outcome: historyruntime.History_Runtime_Enqueue_Result) {
    explorer^.search_pending = false
    explorer^.status_failure.kind = .Invalid_State
    if outcome == .Source_Too_Large {
        explorer^.status = .Capacity
        explorer^.status_failure.kind = .Capacity
    } else if outcome == .Not_Ready {
        explorer^.status = .Unavailable
    } else {
        explorer^.status = .Failed
    }
    log.warnf("terminal_history_explorer_failed operation=%s admission=%d",
        operation, int(outcome))
}

// Capture the display query lifecycle; ready-prompt opening policy belongs to input.
terminal_service_begin_history_query :: proc(
    state: ^core.Euclid_General_State,
    opening_generation: u64,
    query_generation: u64) -> (historyruntime.History_Explorer_Identity, bool) {
    if state == nil || !state^.terminal.initialized ||
       state^.terminal.animation_generation !=
            state^.terminal_history_runtime.terminal_generation {
        return {}, false
    }
    return terminalview.history_runtime_begin_query(
        &state^.terminal_history_runtime, opening_generation, query_generation)
}

// Queue an immutable search without routing it through editor navigation.
terminal_service_request_history_search :: proc(
    state: ^core.Euclid_General_State,
    request: historyruntime.History_Search_Request) ->
        historyruntime.History_Runtime_Enqueue_Result {
    if !terminal_service_generation_matches(state, request.identity.terminal_generation) {
        return .Not_Ready
    }
    return terminalview.history_runtime_request_search(
        &state^.terminal_history_runtime, request)
}

// Queue exact candidate source without applying ordinary recall or submitting it.
terminal_service_request_history_preview :: proc(
    state: ^core.Euclid_General_State,
    request: historyruntime.History_Preview_Request) ->
        historyruntime.History_Runtime_Enqueue_Result {
    if !terminal_service_generation_matches(state, request.identity.terminal_generation) {
        return .Not_Ready
    }
    return terminalview.history_runtime_request_preview(
        &state^.terminal_history_runtime, request)
}

// Copy search output into display-owner storage, never the hidden ordinary editor.
terminal_service_consume_history_search :: proc(
    state: ^core.Euclid_General_State,
    rows: []termhiststore.History_Candidate_Summary,
    summaries: []u8) -> (historyruntime.History_Search_Completion, bool) {
    if state == nil || !terminal_service_generation_matches(
        state, state^.terminal_history_runtime.terminal_generation) {
        return {}, false
    }
    return terminalview.history_runtime_consume_search_result(
        &state^.terminal_history_runtime, rows, summaries)
}

// Copy a complete preview to its caller, keeping it distinct from recalled source.
terminal_service_consume_history_preview :: proc(
    state: ^core.Euclid_General_State,
    destination: []u8) -> (historyruntime.History_Preview_Completion, bool) {
    if state == nil || !terminal_service_generation_matches(
        state, state^.terminal_history_runtime.terminal_generation) {
        return {}, false
    }
    return terminalview.history_runtime_consume_preview_result(
        &state^.terminal_history_runtime, destination)
}

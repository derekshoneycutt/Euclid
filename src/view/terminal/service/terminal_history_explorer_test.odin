#+test
package terminalservice

import core "../../../core"
import historyruntime "../../../terminal/history/runtime"
import termhist "../../../terminal/history"
import termhiststore "../../../persistence/userdata/history"
import terminalview ".."
import "core:testing"

// Explorer completions never enter the navigation editor, even with colliding IDs.
@(test)
terminal_service_explorer_completions_are_not_ordinary_recall :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    testing.expect(t, terminalview.terminal_init_with_allocator(
        &state.terminal, context.allocator, 1))
    defer terminalview.terminal_destroy(&state.terminal, context.allocator)
    termhist.termhist_insert_text(state.terminal.history, "untouched draft")
    state.terminal.input_mode = .Pkg
    state.terminal_history_runtime.status = .Ready
    terminalview.history_runtime_attach_generation(&state.terminal_history_runtime, 1)
    identity, ready := terminal_service_begin_history_query(state, 1, 1)
    testing.expect(t, ready)
    terminal_service_test_explorer_mailboxes(t, state, identity)
    terminal_service_consume_history_read(state)
    rows: [1]termhiststore.History_Candidate_Summary
    summaries: [16]u8
    search, consumed := terminal_service_consume_history_search(
        state, rows[:], summaries[:])
    testing.expect(t, consumed && search.ready)
    testing.expect_value(t, string(summaries[:search.result.summary_bytes]), "summary")
    preview: historyruntime.History_Preview_Completion
    preview, consumed = terminal_service_consume_history_preview(state, summaries[:])
    testing.expect(t, consumed && preview.ready)
    testing.expect_value(t, string(summaries[:preview.result.source_length]), "original")
    testing.expect_value(t,
        termhist.termhist_current_text(state.terminal.history), "untouched draft")
    testing.expect(t, state.terminal.input_mode == .Pkg && !state.terminal.awaiting_eval)
}

// Visible service orchestration captures query bytes and keeps them separate from the draft.
@(test)
terminal_service_starts_bounded_explorer_search :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    testing.expect(t, terminalview.terminal_init_with_allocator(
        &state.terminal, context.allocator, 1))
    defer terminalview.terminal_destroy(&state.terminal, context.allocator)
    state.terminal.banner_ready = true
    state.terminal.history_explorer_open_allowed = true
    testing.expect(t, termhist.termhist_insert_text(
        state.terminal.history, "ordinary draft"))
    state.terminal_history_runtime.status = .Ready
    terminalview.history_runtime_attach_generation(&state.terminal_history_runtime, 1)
    testing.expect(t, terminalview.history_explorer_open(&state.terminal))
    testing.expect(t, terminalview.history_explorer_insert_query(
        &state.terminal.history_explorer, "literal"))

    terminal_service_update_history_explorer(state)

    explorer := &state.terminal.history_explorer
    runtime := &state.terminal_history_runtime
    testing.expect(t, explorer^.identity.runtime_epoch != 0)
    testing.expect(t, explorer^.search_pending && runtime^.search_pending)
    testing.expect_value(t,
        string(runtime^.queued_query[:runtime^.queued_search.query_length]), "literal")
    testing.expect_value(t,
        termhist.termhist_current_text(state.terminal.history), "ordinary draft")
    testing.expect(t, !state.terminal.awaiting_eval)
}

// Populate joined outputs through their distinct request and completion contracts.
terminal_service_test_explorer_mailboxes :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State,
    identity: historyruntime.History_Explorer_Identity) {
    search: historyruntime.History_Search_Request = {
        identity = identity,
        request_id = 1,
        page = {
            result_limit = 2,
        },
    }
    preview: historyruntime.History_Preview_Request = {
        identity = identity,
        request_id = 1,
        source_id = 7,
        source_revision = 3,
    }
    testing.expect(t, terminal_service_request_history_search(state, search) == .Queued)
    testing.expect(t, terminal_service_request_history_preview(state, preview) == .Queued)
    history := &state.terminal_history_runtime
    history.search_completion = {
        ready = true,
        request = search,
        result = {
            outcome = .Complete,
            row_count = 1,
            summary_bytes = 7,
        },
    }
    copy(history.search_summaries[:], "summary")
    history.preview_completion = {
        ready = true,
        request = preview,
        result = {
            outcome = .Found,
            source_length = 8,
        },
    }
    copy(history.preview_source[:], "original")
}

// Changing scheduling priority cannot accidentally route highlighting into recall.
@(test)
terminal_service_history_route_is_not_scheduling_priority :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    testing.expect(t, terminalview.terminal_init_with_allocator(
        &state.terminal, context.allocator, 1))
    defer terminalview.terminal_destroy(&state.terminal, context.allocator)
    termhist.termhist_insert_text(state.terminal.history, "draft")
    terminal_service_test_set_highlight_read_result(state, 55, 1)
    state.terminal_history_runtime.read_result_request.priority = .Interactive
    state.terminal.history_navigation_pending_id = 100
    terminal_service_consume_history_read(state)
    testing.expect_value(t,
        termhist.termhist_current_text(state.terminal.history), "draft")
    testing.expect_value(t, state.terminal.history_navigation_pending_id, u64(100))
}

// Replacing Terminal retires queued work once without changing the saved draft.
@(test)
terminal_service_replacement_retires_explorer_transport :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    testing.expect(t, terminalview.terminal_init_with_allocator(
        &state.terminal, context.allocator, 1))
    defer terminalview.terminal_destroy(&state.terminal, context.allocator)
    termhist.termhist_insert_text(state.terminal.history, "draft")
    state.terminal_history_runtime.status = .Ready
    terminalview.history_runtime_attach_generation(&state.terminal_history_runtime, 1)
    identity, ready := terminal_service_begin_history_query(state, 1, 1)
    testing.expect(t, ready)
    testing.expect(t, terminal_service_request_history_search(state, {
        identity = identity,
        request_id = 1,
        page = {
            result_limit = 2,
        },
    }) == .Queued)
    _ = terminal_service_update(state, nil, {})
    testing.expect(t, !terminalview.history_runtime_explorer_current(
        &state.terminal_history_runtime, identity))
    testing.expect(t, !state.terminal_history_runtime.search_pending)
    epoch := state.terminal_history_runtime.explorer_epoch
    _ = terminal_service_update(state, nil, {})
    testing.expect_value(t, state.terminal_history_runtime.explorer_epoch, epoch)
    testing.expect_value(t, termhist.termhist_current_text(state.terminal.history), "draft")
}

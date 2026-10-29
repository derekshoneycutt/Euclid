#+test
package terminalview

import viewterminalmodel "model"
import termhist "../../terminal/history"
import termhiststore "../../terminal/history/store"
import historyruntime "../../terminal/history/runtime"
import "core:testing"

// Exact trimmed sentinels reserve help without stealing ordinary source queries.
@(test)
history_explorer_help_requires_exact_query :: proc(t: ^testing.T) {
    testing.expect_value(t, history_explorer_help_kind(" \t?\u2003"),
        viewterminalmodel.History_Explorer_Help.Short)
    testing.expect_value(t, history_explorer_help_kind(" ?? "),
        viewterminalmodel.History_Explorer_Help.Extended)
    queries := [?]string{"?sin", "???", "/?", "=??", "x ?"}
    for query in queries {
        testing.expect_value(t, history_explorer_help_kind(query),
            viewterminalmodel.History_Explorer_Help.None)
    }
}

// Replace a query through its ordinary bounded selection/insertion path.
history_explorer_test_replace_query :: proc(
    t: ^testing.T, explorer: ^viewterminalmodel.History_Explorer_State, text: string) {
    _ = termhist.termhist_set_cursor(&explorer.query_editor, 0)
    _ = termhist.termhist_set_cursor(
        &explorer.query_editor, explorer.query_editor.text_len, true)
    testing.expect(t, history_explorer_insert_query(explorer, text))
}

// Help overlays the same page, survives form switches, and never accepts or evaluates source.
@(test)
history_explorer_help_restores_page_and_editor :: proc(t: ^testing.T) {
    term: viewterminalmodel.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term, context.allocator)
    term.banner_ready, term.history_explorer_open_allowed = true, true
    testing.expect(t, history_explorer_open(&term))
    explorer := &term.history_explorer
    testing.expect(t, history_explorer_insert_query(explorer, "needle"))
    explorer.row_count, explorer.selected_index = 1, 0
    explorer.preview_length, explorer.preview_scroll_lines = 6, 3
    explorer.status, explorer.preview_status = .Ready, .Ready
    copy(explorer.preview_source, "needle")
    explorer.identity.runtime_epoch = 9
    history_explorer_test_replace_query(t, explorer, "?")
    testing.expect_value(t, explorer.help, viewterminalmodel.History_Explorer_Help.Short)
    testing.expect(t, history_explorer_insert_query(explorer, "?"))
    testing.expect_value(t, explorer.help,
        viewterminalmodel.History_Explorer_Help.Extended)
    _ = terminal_update_keyboard_event(&term, {
        kind = .Press,
        key = .Enter,
    }, "")
    testing.expect(t, !explorer.accept_requested && !term.awaiting_eval)
    terminal_history_explorer_test_cancel(&term)
    testing.expect_value(t, termhist.termhist_current_text(&explorer.query_editor), "needle")
    testing.expect_value(t, explorer.query_editor.cursor, 6)
    testing.expect_value(t, explorer.query_editor.anchor, 0)
    testing.expect_value(t, explorer.identity.runtime_epoch, u64(9))
    testing.expect(t, explorer.row_count == 1 && explorer.preview_scroll_lines == 3)
    testing.expect_value(t, string(explorer.preview_source[:explorer.preview_length]), "needle")
    terminal_history_explorer_test_cancel(&term)
    testing.expect(t, !explorer.active)
}

// Editing a help sentinel into source invalidates the suspended page before new admission.
@(test)
history_explorer_help_edit_retires_decorations :: proc(t: ^testing.T) {
    term: viewterminalmodel.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term, context.allocator)
    term.banner_ready, term.history_explorer_open_allowed = true, true
    testing.expect(t, history_explorer_open(&term))
    explorer := &term.history_explorer
    testing.expect(t, history_explorer_insert_query(explorer, "needle"))
    explorer.row_count = 1
    explorer.preview_matches.count = 1
    history_explorer_test_replace_query(t, explorer, "?")
    testing.expect(t, !history_explorer_select_candidate(explorer, 0))
    testing.expect(t, history_explorer_insert_query(explorer, "sin"))
    testing.expect_value(t, explorer.help, viewterminalmodel.History_Explorer_Help.None)
    testing.expect(t, explorer.query_dirty && explorer.identity.runtime_epoch == 0)
    testing.expect(t, explorer.row_count == 0 && explorer.preview_matches.count == 0)
}

// Late preview emphasis cannot decorate a different query, scope, or source revision.
@(test)
history_explorer_ranges_reject_stale_publication :: proc(t: ^testing.T) {
    rows: [1]termhiststore.History_Candidate_Summary
    explorer: viewterminalmodel.History_Explorer_State = {
        active = true,
        rows = rows[:],
        row_count = 1,
        selected_index = 0,
        preview_request_id = 1,
    }
    explorer.identity.runtime_epoch = 2
    rows[0].record = {
        source_id = 7,
        source_revision = 3,
    }
    completion: historyruntime.History_Preview_Completion
    completion.ready = true
    completion.request.identity.runtime_epoch = 1
    completion.request.request_id = 1
    completion.request.source_id, completion.request.source_revision = 7, 3
    completion.result.outcome = .Found
    completion.result.record = rows[0].record
    completion.result.source_length = 4
    completion.matches.count = 1
    history_explorer_publish_preview(&explorer, completion)
    testing.expect_value(t, explorer.preview_matches.count, 0)
    completion.request.identity = explorer.identity
    completion.request.source_revision = 2
    history_explorer_publish_preview(&explorer, completion)
    testing.expect_value(t, explorer.preview_matches.count, 0)
    completion.request.source_revision = 3
    completion.request.scope = .Persistent
    history_explorer_publish_preview(&explorer, completion)
    testing.expect_value(t, explorer.preview_matches.count, 0)
}

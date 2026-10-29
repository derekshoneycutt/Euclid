#+test
package terminalservice

import core "../../../core"
import termhist "../../../terminal/history"
import terminalview ".."
import "core:testing"

// A lifecycle change during help must refetch on restore, never resurrect stale rows or ranges.
@(test)
terminal_service_help_restore_revalidates_identity :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    testing.expect(t, terminalview.terminal_init_with_allocator(
        &state.terminal, context.allocator, 1))
    defer terminalview.terminal_destroy(&state.terminal, context.allocator)
    state.terminal.banner_ready, state.terminal.history_explorer_open_allowed = true, true
    state.terminal_history_runtime.status = .Ready
    terminalview.history_runtime_attach_generation(&state.terminal_history_runtime, 1)
    testing.expect(t, terminalview.history_explorer_open(&state.terminal))
    explorer := &state.terminal.history_explorer
    testing.expect(t, terminalview.history_explorer_insert_query(explorer, "needle"))
    terminal_service_update_history_explorer(state)
    previous := explorer.identity
    explorer.row_count = 1
    explorer.preview_matches.count = 1
    _ = termhist.termhist_set_cursor(&explorer.query_editor, 0)
    _ = termhist.termhist_set_cursor(&explorer.query_editor, 6, true)
    testing.expect(t, terminalview.history_explorer_insert_query(explorer, "?"))
    terminalview.history_runtime_retire_explorer(&state.terminal_history_runtime)
    terminal_service_update_history_explorer(state)
    testing.expect(t, !state.terminal_history_runtime.search_pending)
    testing.expect(t, terminalview.history_explorer_restore_query(explorer))
    terminal_service_update_history_explorer(state)
    testing.expect(t, explorer.identity != previous && explorer.search_pending)
    testing.expect(t, explorer.row_count == 0 && explorer.preview_matches.count == 0)
    testing.expect_value(t,
        string(state.terminal_history_runtime.queued_query[:6]), "needle")
}

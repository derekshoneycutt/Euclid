package viewscenario

import scenario "../../evidence/scenario"
import termhist "../../terminal/history"
import terminalview "../terminal"
import "core:log"

// Wait for actionable source or an exhausted/retired explorer, not an idle task gap.
scenario_terminal_explorer_matches :: proc(
    runtime: ^Scenario_Runtime, name: string) -> bool {
    explorer := &runtime^.state^.terminal.history_explorer
    switch name {
    case "closed":
        return !explorer^.active
    case "ready":
        return explorer^.active && explorer^.status == .Ready &&
            explorer^.preview_status == .Ready && !explorer^.query_dirty &&
            !explorer^.search_pending && !explorer^.preview_pending &&
            scenario_terminal_explorer_current(runtime)
    case "empty":
        return explorer^.active && explorer^.status == .Empty &&
            explorer^.row_count == 0 && !explorer^.search_pending
    case "unavailable":
        return explorer^.active && explorer^.status == .Unavailable
    }
    return false
}

// Reject a cached visual result before frame-owned visibility policy has caught up.
scenario_terminal_explorer_current :: proc(runtime: ^Scenario_Runtime) -> bool {
    state := runtime^.state
    history := &state^.terminal_history_runtime
    return history^.persist_enabled ==
        state^.ui_runtime.preferences.values.terminal.persist_history &&
        terminalview.history_runtime_explorer_current(
            history, state^.terminal.history_explorer.identity)
}

// Verify exact source/mode, cursor/selection, and no unrequested evaluation.
scenario_terminal_editor_matches :: proc(
    runtime: ^Scenario_Runtime, command: ^scenario.Command) -> bool {
    term := &runtime^.state^.terminal
    if term^.history == nil {
        log.error("scenario_terminal_editor_unavailable")
        return false
    }
    expected := command^.terminal_editor
    matches := !term^.awaiting_eval &&
        termhist.termhist_current_text(term^.history) ==
            scenario.text_string(&command^.text) &&
        term^.input_mode == expected.mode &&
        term^.history.cursor == expected.cursor &&
        term^.history.anchor == expected.anchor &&
        u64(term^.next_eval_request_id) == expected.evaluation_requests
    if !matches {
        log.errorf(
            "scenario_terminal_editor_mismatch mode=%v cursor=%d anchor=%d requests=%d",
            term^.input_mode, term^.history.cursor, term^.history.anchor,
            term^.next_eval_request_id)
    }
    return matches
}

// Compare the complete current preview, never a flattened summary or partial source.
scenario_terminal_preview_matches :: proc(
    runtime: ^Scenario_Runtime, text: string) -> bool {
    if !scenario_terminal_explorer_matches(runtime, "ready") {
        return false
    }
    explorer := &runtime^.state^.terminal.history_explorer
    return string(explorer^.preview_source[:explorer^.preview_length]) == text
}

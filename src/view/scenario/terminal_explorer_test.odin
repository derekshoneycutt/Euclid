#+test
package viewscenario

import core "../../core"
import scenario "../../evidence/scenario"
import "core:log"
import "core:testing"

// Cached Ready state cannot satisfy a wait across pending policy or runtime retirement.
@(test)
scenario_terminal_explorer_ready_requires_current_visibility :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    runtime: Scenario_Runtime = {
        state = state,
    }
    explorer := &state^.terminal.history_explorer
    explorer^.active = true
    explorer^.status = .Ready
    explorer^.preview_status = .Ready
    explorer^.identity.runtime_epoch = 1
    history := &state^.terminal_history_runtime
    history^.status = .Ready
    history^.explorer_identity = explorer^.identity
    testing.expect(t, scenario_terminal_explorer_matches(&runtime, "ready"))
    state^.ui_runtime.preferences.values.terminal.persist_history = true
    testing.expect(t, !scenario_terminal_explorer_matches(&runtime, "ready"))
    history^.persist_enabled = true
    testing.expect(t, scenario_terminal_explorer_matches(&runtime, "ready"))
    history^.visibility_epoch += 1
    testing.expect(t, !scenario_terminal_explorer_matches(&runtime, "ready"))
    explorer^.identity.visibility_epoch = history^.visibility_epoch
    history^.explorer_identity = explorer^.identity
    testing.expect(t, scenario_terminal_explorer_matches(&runtime, "ready"))
    history^.shutdown_requested = true
    testing.expect(t, !scenario_terminal_explorer_matches(&runtime, "ready"))
}

// An assertion before Terminal initialization fails explicitly rather than dereferencing nil.
@(test)
scenario_terminal_editor_missing_history_is_not_a_match :: proc(t: ^testing.T) {
    previous_logger := context.logger
    context.logger = log.nil_logger()
    defer context.logger = previous_logger
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    runtime: Scenario_Runtime = {
        state = state,
    }
    command: scenario.Command
    testing.expect(t, !scenario_terminal_editor_matches(&runtime, &command))
}

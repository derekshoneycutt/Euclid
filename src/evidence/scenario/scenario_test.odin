#+test
package scenario

import "../observe"
import trace "../trace"

import "core:testing"

// Return accepted allocation assertions for runner tests.
scenario_test_allocation_action :: proc(
    _: rawptr, command: ^Command) -> Action_Result {
    return {
        accepted = command.kind == .Allocation_Checkpoint ||
            command.kind == .Assert_Allocation_Baseline ||
            command.kind == .Assert_No_Bad_Frees,
    }
}

// Return one typed runtime-request identity for action-alias tests.
scenario_test_runtime_action :: proc(
    _: rawptr, _: ^Command) -> Action_Result {
    return {
        accepted = true,
        correlation = {.Runtime_Request, 42, 3},
    }
}

// Verify bounded JSONL is validated into Euclid commands.
@(test)
scenario_test_parse_json_lines :: proc(t: ^testing.T) {
    program: Program
    result := parse(
        "{\"select_animation\":\"Euclid.Proposition1\",\"as\":\"selection\"}\n" +
        "{\"wait_state\":\"animation_idle\",\"timeout_ms\":10}\n" +
        "{\"shutdown\":true}\n", &program)
    testing.expect_value(t, result, Parse_Error.None)
    testing.expect_value(t, program.count, 3)
    testing.expect_value(t, program.commands[0].kind, Command_Kind.Select_Animation)
    testing.expect_value(t, name_string(&program.commands[0].alias), "selection")
    testing.expect_value(t, program.commands[1].timeout_ms, u32(10))
}

// Verify animation idleness follows pending work and publication identity.
@(test)
scenario_test_animation_idle_state :: proc(t: ^testing.T) {
    testing.expect(t, !state_matches("animation_idle", observe.Display{
        animation_tick_pending = true,
        animation_tick_sequence = 2,
        animation_last_committed_sequence = 1,
    }))
    testing.expect(t, state_matches("animation_idle", observe.Display{
        animation_tick_pending = true,
        animation_tick_sequence = 2,
        animation_last_committed_sequence = 2,
    }))
    testing.expect(t, state_matches("animation_idle", observe.Display{
        animation_tick_pending = false,
        animation_tick_sequence = 2,
        animation_last_committed_sequence = 1,
    }))
}

// Verify Terminal input and cell assertions are bounded scenario commands.
@(test)
scenario_test_terminal_commands :: proc(t: ^testing.T) {
    program: Program
    result := parse(
        "{\"type\":\"1 + 1\"}\n" +
        "{\"key\":\"enter\"}\n" +
        "{\"assert_terminal_contains\":\"2\"}\n", &program)
    testing.expect_value(t, result, Parse_Error.None)
    testing.expect_value(t, program.count, 3)
    testing.expect_value(t, program.commands[0].kind, Command_Kind.Type_Text)
    testing.expect_value(t, program.commands[1].kind, Command_Kind.Key)
    testing.expect_value(t,
        program.commands[2].kind, Command_Kind.Assert_Terminal_Contains)
    testing.expect(t, state_matches(
        "terminal_idle", observe.Display{terminal_idle = true}))
}

// Verify event predicates progress immediately and deadlines bound failure.
@(test)
scenario_test_runner_event_and_deadline :: proc(t: ^testing.T) {
    program: Program
    testing.expect_value(t, parse(
        "{\"wait_event\":\"runtime_ready\",\"timeout_ms\":5}\n",
        &program), Parse_Error.None)
    runner: Runner
    runner_init(&runner, program)
    display := observe.Display{required_evidence_complete = true}

    testing.expect_value(t,
        runner_update(&runner, {now_ns = 100, display = display}),
        Run_Status.Running)
    event := trace.Event{kind = .Runtime_Ready}
    testing.expect_value(t,
        runner_update(&runner, {
            now_ns = 101, events = {event}, display = display,
        }), Run_Status.Passed)

    runner_init(&runner, program)
    testing.expect_value(t,
        runner_update(&runner, {now_ns = 100, display = display}),
        Run_Status.Running)
    testing.expect_value(t,
        runner_update(&runner, {now_ns = 5_000_100, display = display}),
        Run_Status.Failed)
}

// Verify presentation replacement transitions are available to scenarios.
@(test)
scenario_test_presentation_lifecycle_events :: proc(t: ^testing.T) {
    cleared, cleared_valid := event_kind("presentation_cleared")
    superseded, superseded_valid := event_kind("presentation_superseded")
    testing.expect(t, cleared_valid && superseded_valid)
    testing.expect_value(t, cleared, trace.Kind.Presentation_Cleared)
    testing.expect_value(t, superseded, trace.Kind.Presentation_Superseded)
}

// Verify the scenario vocabulary exposes generation-owned animation lifecycle events.
@(test)
scenario_test_animation_loaded_event :: proc(t: ^testing.T) {
    loaded, loaded_valid := event_kind("animation_loaded")
    reset, reset_valid := event_kind("animation_reset_committed")
    testing.expect(t, loaded_valid && reset_valid)
    testing.expect_value(t, loaded, trace.Kind.Animation_Loaded)
    testing.expect_value(t, reset, trace.Kind.Animation_Reset_Committed)
}

// Verify deterministic reload failure injection is parsed as an ordinary action.
@(test)
scenario_test_reload_failure_injection :: proc(t: ^testing.T) {
    program: Program
    testing.expect_value(t, parse(
        "{\"inject_reload_failure\":\"candidate_load\"}\n",
        &program), Parse_Error.None)
    testing.expect_value(t, program.count, 1)
    testing.expect_value(t,
        program.commands[0].kind, Command_Kind.Inject_Reload_Failure)
}

// Verify required evidence loss makes the run inconclusive before actions execute.
@(test)
scenario_test_required_trace_loss_is_inconclusive :: proc(t: ^testing.T) {
    program := Program{count = 1}
    program.commands[0] = {kind = .Shutdown}
    runner: Runner
    runner_init(&runner, program)

    testing.expect_value(t,
        runner_update(&runner, {}), Run_Status.Inconclusive)
}

// Verify aliases retain kind and generation when matching events.
@(test)
scenario_test_typed_alias_matching :: proc(t: ^testing.T) {
    program: Program
    testing.expect_value(t, parse(
        "{\"do\":\"reload_runtime\",\"as\":\"reload\"}\n" +
        "{\"wait_event\":\"runtime_reload_committed\"," +
        "\"correlation\":\"reload\"}\n", &program), Parse_Error.None)
    runner: Runner
    runner_init(&runner, program)
    display := observe.Display{required_evidence_complete = true}
    testing.expect_value(t, runner_update(&runner, {
        display = display,
        actions = {issue = scenario_test_runtime_action},
    }), Run_Status.Running)

    wrong_generation := trace.Event{
        kind = .Runtime_Reload_Committed,
        correlation_kind = .Runtime_Request,
        correlation = 42,
        generation = 2,
    }
    testing.expect_value(t, runner_update(&runner, {
        now_ns = 1,
        events = {wrong_generation},
        display = display,
    }), Run_Status.Running)
    matching := [2]trace.Event{wrong_generation, {
        kind = .Runtime_Reload_Committed,
        correlation_kind = .Runtime_Request,
        correlation = 42,
        generation = 3,
    }}
    testing.expect_value(t, runner_update(&runner, {
        now_ns = 2,
        events = matching[:],
        display = display,
    }), Run_Status.Passed)
}

// Verify frame-specific waits inspect the typed animation event payload.
@(test)
scenario_test_animation_frame_matching :: proc(t: ^testing.T) {
    program: Program
    testing.expect_value(t, parse(
        "{\"wait_event\":\"animation_frame_presented\"," +
        "\"frame_number\":2}\n", &program), Parse_Error.None)
    runner: Runner
    runner_init(&runner, program)
    display := observe.Display{required_evidence_complete = true}
    wrong_frame := trace.Event{
        kind = .Animation_Frame_Presented,
        payload = {counts = {first = 1}},
    }
    testing.expect_value(t, runner_update(&runner, {
        events = {wrong_frame}, display = display,
    }), Run_Status.Running)
    matching := [2]trace.Event{wrong_frame, {
        kind = .Animation_Frame_Presented,
        payload = {counts = {first = 2}},
    }}
    testing.expect_value(t, runner_update(&runner, {
        events = matching[:], display = display,
    }), Run_Status.Passed)
}

// Verify allocation checkpoints and assertions use the ordinary action boundary.
@(test)
scenario_test_allocation_commands :: proc(t: ^testing.T) {
    program: Program
    testing.expect_value(t, parse(
        "{\"allocation_checkpoint\":\"runtime\"}\n" +
        "{\"assert_allocation_baseline\":\"runtime\"}\n" +
        "{\"assert_no_bad_frees\":true}\n", &program), Parse_Error.None)
    runner: Runner
    runner_init(&runner, program)
    testing.expect_value(t, runner_update(&runner, {
        display = observe.Display{required_evidence_complete = true},
        actions = {issue = scenario_test_allocation_action},
    }), Run_Status.Passed)
    testing.expect_value(t, runner.assertion_count, u32(2))
}

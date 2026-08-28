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

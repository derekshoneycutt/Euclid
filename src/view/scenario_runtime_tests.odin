package view

import capture "../evidence/capture"
import "../diagnostics"
import artifact "../evidence/artifact"
import scenario "../evidence/scenario"

import "core:log"
import "core:os"
import "core:strings"
import "core:testing"

// Accept one injected post-presentation capture.
scenario_runtime_test_capture :: proc(
    user_data: rawptr, checkpoint: capture.Checkpoint) -> bool {
    captured := cast(^capture.Checkpoint)user_data
    captured^ = checkpoint
    return true
}

// Verify the expected passed and failed scenario records in one completed log.
scenario_runtime_expect_outcome_logs :: proc(t: ^testing.T, path: string) {
    context.logger = log.nil_logger()
    content_bytes, read_error := os.read_entire_file(path, context.allocator)
    testing.expect(t, read_error == nil)
    defer delete(content_bytes)
    defer os.remove(path)
    content := string(content_bytes)
    testing.expect(t, strings.contains(content,
        "scenario_passed step=3 assertions=0 failures=0 reason=0"))
    testing.expect(t, strings.contains(content,
        "scenario_failed step=5 assertions=3 failures=1"))
}

// Verify ordinary state requests and orderly shutdown flow through the action sink.
@(test)
scenario_runtime_actions_use_display_owned_state :: proc(t: ^testing.T) {
    path := ".build/test-artifacts/scenario-outcomes.log"
    os.make_directory_all(".build/test-artifacts")
    os.remove(path)
    logging_state: diagnostics.Logging_State
    testing.expect(t, diagnostics.logging_start(&logging_state, path, .Info))
    context.logger = logging_state.logger
    state := new(Euclid_General_State)
    defer free(state)
    state^.julia_interface = &state^.julia_interface_slots[0]
    state^.evidence_session.enabled = true
    state^.evidence_session.required_evidence_complete = true

    program := scenario.Program{count = 3}
    program.commands[0] = {kind = .Pause_Simulation}
    program.commands[1] = {kind = .Resume_Simulation}
    program.commands[2] = {kind = .Shutdown}
    runtime: Scenario_Runtime
    scenario_runtime_init(&runtime, state, program)

    testing.expect_value(t,
        scenario_runtime_update(&runtime, 1), scenario.Run_Status.Passed)
    testing.expect(t, !state^.ui_runtime.simulation_paused)
    testing.expect(t, runtime.shutdown_requested)

    failed := Scenario_Runtime{
        state = state,
        terminal_reason = artifact.Reason.Assertion_Failed,
    }
    failed.runner.step = 5
    failed.runner.assertion_count = 3
    failed.runner.failure_count = 1
    scenario_runtime_record_terminal(&failed, .Failed)

    context.logger = log.nil_logger()
    diagnostics.logging_stop(&logging_state)
    scenario_runtime_expect_outcome_logs(t, path)
}

// Verify a required screenshot keeps the run active until post-presentation completion.
@(test)
scenario_runtime_waits_for_post_present_capture :: proc(t: ^testing.T) {
    state := new(Euclid_General_State)
    defer free(state)
    state^.julia_interface = &state^.julia_interface_slots[0]
    state^.evidence_session.enabled = true
    state^.evidence_session.required_evidence_complete = true
    state^.fixed_step = 11

    path, copied := scenario.text_copy(".build/test-artifacts/frame.png")
    testing.expect(t, copied)
    program := scenario.Program{count = 1}
    program.commands[0] = {kind = .Request_Screenshot, text = path}
    runtime: Scenario_Runtime
    scenario_runtime_init(&runtime, state, program)

    testing.expect_value(t,
        scenario_runtime_update(&runtime, 1), scenario.Run_Status.Running)
    captured: capture.Checkpoint
    testing.expect_value(t, scenario_runtime_after_present(&runtime, {
        user_data = &captured,
        capture = scenario_runtime_test_capture,
    }), capture.Checkpoint_Status.Completed)
    testing.expect_value(t, captured.fixed_step, u64(11))
    testing.expect_value(t,
        scenario_runtime_update(&runtime, 2), scenario.Run_Status.Passed)
}

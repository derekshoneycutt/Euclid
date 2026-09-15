#+test
package scenario

import particlemodel "../../particles/model"
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

// Verify named viewport payloads retain explicit zero and both splitter coordinates.
@(test)
scenario_test_parse_viewport_actions :: proc(t: ^testing.T) {
    program: Program
    result := parse(
        "{\"set_view_scroll\":{\"y\":0}}\n" +
        "{\"set_splitters\":{\"vertical\":640.5,\"horizontal\":360}}\n",
        &program)
    testing.expect_value(t, result, Parse_Error.None)
    testing.expect_value(t, program.count, 2)
    testing.expect_value(t, program.commands[0].kind, Command_Kind.Set_View_Scroll)
    testing.expect_value(t, program.commands[0].value, f32(0))
    testing.expect_value(t, program.commands[1].kind, Command_Kind.Set_Splitters)
    testing.expect_value(t, program.commands[1].value, f32(640.5))
    testing.expect_value(t, program.commands[1].secondary_value, f32(360))
}

// Verify viewport payloads reject missing, extra, nonnumeric, and competing actions.
@(test)
scenario_test_reject_invalid_viewport_actions :: proc(t: ^testing.T) {
    invalid_sources := [?]string{
        "{\"set_view_scroll\":{}}\n",
        "{\"set_view_scroll\":{\"y\":1,\"extra\":2}}\n",
        "{\"set_view_scroll\":{\"y\":\"bottom\"}}\n",
        "{\"set_splitters\":{\"vertical\":640}}\n",
        "{\"set_splitters\":{\"vertical\":640,\"horizontal\":360,\"extra\":1}}\n",
        "{\"set_view_scroll\":{\"y\":10},\"shutdown\":true}\n",
    }
    for source in invalid_sources {
        program: Program
        testing.expect_value(t, parse(source, &program), Parse_Error.Invalid_Command)
    }
}

// Verify view-content actions preserve exact source, MIME, alias, and empty content.
@(test)
scenario_test_parse_view_content_actions :: proc(t: ^testing.T) {
    program: Program
    source := "\\textbf{Point} $A_1$"
    result := parse(
        "{\"set_view_content\":{\"mime\":\"text/latex\",\"source\":\"\\\\textbf{Point} $A_1$\"},\"as\":\"latex\"}\n" +
        "{\"set_view_content\":{\"mime\":\"text/plain\",\"source\":\"\"}}\n",
        &program)
    testing.expect_value(t, result, Parse_Error.None)
    testing.expect_value(t, program.count, 2)
    testing.expect_value(t, program.commands[0].kind, Command_Kind.Set_View_Content)
    testing.expect_value(t, program.commands[0].view_content_mime,
        View_Content_Mime.Text_Latex)
    testing.expect_value(t, text_string(&program.commands[0].text), source)
    testing.expect_value(t, name_string(&program.commands[0].alias), "latex")
    testing.expect_value(t, program.commands[1].view_content_mime,
        View_Content_Mime.Text_Plain)
    testing.expect_value(t, text_string(&program.commands[1].text), "")
}

// Verify the exact view-content capacity is accepted and one extra byte is rejected.
@(test)
scenario_test_view_content_respects_text_capacity :: proc(t: ^testing.T) {
    accepted_bytes: [SCENARIO_TEXT_CAPACITY]u8
    rejected_bytes: [SCENARIO_TEXT_CAPACITY + 1]u8
    for &value in accepted_bytes { value = 'x' }
    for &value in rejected_bytes { value = 'x' }
    accepted, accepted_ok := text_copy(string(accepted_bytes[:]))
    _, rejected_ok := text_copy(string(rejected_bytes[:]))
    testing.expect(t, accepted_ok)
    testing.expect_value(t, len(text_string(&accepted)), SCENARIO_TEXT_CAPACITY)
    testing.expect(t, !rejected_ok)
}

// Verify view-content objects reject malformed shape, MIME, and competing actions.
@(test)
scenario_test_reject_invalid_view_content_actions :: proc(t: ^testing.T) {
    invalid_sources := [?]string{
        "{\"set_view_content\":{\"source\":\"x\"}}\n",
        "{\"set_view_content\":{\"mime\":\"text/markdown\",\"source\":\"x\"}}\n",
        "{\"set_view_content\":{\"mime\":\"text/plain\",\"source\":\"x\",\"extra\":1}}\n",
        "{\"set_view_content\":{\"mime\":\"text/plain\",\"source\":\"x\"},\"shutdown\":true}\n",
    }
    for source in invalid_sources {
        program: Program
        testing.expect_value(t, parse(source, &program), Parse_Error.Invalid_Command)
    }
    program: Program
    testing.expect_value(t, parse(
        "{\"set_view_content\":\"x\"}\n", &program), Parse_Error.Invalid_Json)
}

// Verify scenario dust emission preserves its deterministic bounded payload.
@(test)
scenario_test_parse_dust_emission :: proc(t: ^testing.T) {
    program: Program
    source := "{\"emit_dust\":{\"distribution\":\"disc\",\"count\":20000," +
        "\"x\":0.5,\"y\":0.4,\"radius\":0.03,\"seed\":7},\"as\":\"dust\"}\n"
    testing.expect_value(t, parse(source, &program), Parse_Error.None)
    command := &program.commands[0]
    testing.expect_value(t, command.kind, Command_Kind.Emit_Dust)
    testing.expect_value(t, command.dust_distribution, Dust_Distribution.Disc)
    testing.expect_value(t, command.dust_count, u32(20_000))
    testing.expect_value(t, command.value, f32(0.5))
    testing.expect_value(t, command.secondary_value, f32(0.4))
    testing.expect_value(t, command.tertiary_value, f32(0.03))
    testing.expect_value(t, command.dust_seed, u64(7))
    testing.expect_value(t, name_string(&command.alias), "dust")
}

// Verify malformed, out-of-range, and competing dust emissions are rejected.
@(test)
scenario_test_reject_invalid_dust_emission :: proc(t: ^testing.T) {
    invalid_sources := [?]string{
        "{\"emit_dust\":{\"distribution\":\"disc\",\"count\":0,\"x\":0.5,\"y\":0.5,\"radius\":0.1,\"seed\":1}}\n",
        "{\"emit_dust\":{\"distribution\":\"cloud\",\"count\":1,\"x\":0.5,\"y\":0.5,\"radius\":0.1,\"seed\":1}}\n",
        "{\"emit_dust\":{\"distribution\":\"point\",\"count\":1,\"x\":-1,\"y\":0.5,\"radius\":0,\"seed\":1}}\n",
        "{\"emit_dust\":{\"distribution\":\"grid\",\"count\":1,\"x\":0.5,\"y\":0.5,\"radius\":2,\"seed\":1}}\n",
        "{\"emit_dust\":{\"distribution\":\"point\",\"count\":1,\"x\":0.5,\"y\":0.5,\"radius\":0,\"seed\":1,\"extra\":1}}\n",
        "{\"emit_dust\":{\"distribution\":\"point\",\"count\":1,\"x\":0.5,\"y\":0.5,\"radius\":0,\"seed\":1},\"shutdown\":true}\n",
    }
    for source in invalid_sources {
        program: Program
        testing.expect_value(t, parse(source, &program), Parse_Error.Invalid_Command)
    }
}

// Verify dust disturbance commands are exact, bounded scenario actions.
@(test)
scenario_test_parse_dust_disturbance_actions :: proc(t: ^testing.T) {
    program: Program
    source := "{\"contact_dust\":{\"x\":0.25,\"y\":0.75}}\n" +
        "{\"do\":\"kick_dust\"}\n" +
        "{\"do\":\"pause_animation\"}\n" +
        "{\"do\":\"resume_animation\"}\n"
    testing.expect_value(t, parse(source, &program), Parse_Error.None)
    testing.expect_value(t, program.commands[0].kind, Command_Kind.Contact_Dust)
    testing.expect_value(t, program.commands[0].value, f32(0.25))
    testing.expect_value(t, program.commands[0].secondary_value, f32(0.75))
    testing.expect_value(t, program.commands[1].kind, Command_Kind.Kick_Dust)
    testing.expect_value(t, program.commands[2].kind, Command_Kind.Pause_Animation)
    testing.expect_value(t, program.commands[3].kind, Command_Kind.Resume_Animation)

    invalid_sources := [?]string{
        "{\"contact_dust\":{\"x\":-1,\"y\":0.5}}\n",
        "{\"contact_dust\":{\"x\":0.5,\"y\":2}}\n",
        "{\"contact_dust\":{\"x\":0.5,\"y\":0.5,\"z\":0}}\n",
    }
    for invalid in invalid_sources {
        testing.expect_value(t, parse(invalid, &program), Parse_Error.Invalid_Command)
    }
}

// Verify viewport actions yield a frame before the next scenario command executes.
@(test)
scenario_test_viewport_actions_create_frame_boundaries :: proc(t: ^testing.T) {
    program: Program
    testing.expect_value(t, parse(
        "{\"set_view_scroll\":{\"y\":10}}\n" +
        "{\"set_splitters\":{\"vertical\":640,\"horizontal\":360}}\n" +
        "{\"shutdown\":true}\n", &program), Parse_Error.None)
    runner: Runner
    runner_init(&runner, program)
    frame := Runner_Frame{
        display = {required_evidence_complete = true},
        actions = {issue = scenario_test_runtime_action},
    }

    testing.expect_value(t, runner_update(&runner, frame), Run_Status.Running)
    testing.expect_value(t, runner.step, 1)
    testing.expect_value(t, runner_update(&runner, frame), Run_Status.Running)
    testing.expect_value(t, runner.step, 2)
    testing.expect_value(t, runner_update(&runner, frame), Run_Status.Passed)
}

// Verify view-content publication yields a frame before later commands execute.
@(test)
scenario_test_view_content_creates_frame_boundary :: proc(t: ^testing.T) {
    program: Program
    testing.expect_value(t, parse(
        "{\"set_view_content\":{\"mime\":\"text/plain\",\"source\":\"Point\"}}\n" +
        "{\"shutdown\":true}\n", &program), Parse_Error.None)
    runner: Runner
    runner_init(&runner, program)
    frame := Runner_Frame{
        display = {required_evidence_complete = true},
        actions = {issue = scenario_test_runtime_action},
    }

    testing.expect_value(t, runner_update(&runner, frame), Run_Status.Running)
    testing.expect_value(t, runner.step, 1)
    testing.expect_value(t, runner_update(&runner, frame), Run_Status.Passed)
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

// Verify dust predicates distinguish complete rest from local and airborne activity.
@(test)
scenario_test_dust_state_predicates :: proc(t: ^testing.T) {
    settled := observe.Display{
        dust_live_count = 8, dust_grounded_count = 8,
        dust_peak_speed_sq = particlemodel.DUST_SETTLED_SPEED_SQ}
    testing.expect(t, state_matches("dust_settled", settled))
    testing.expect(t, !state_matches("dust_active", settled))
    testing.expect(t, !state_matches("dust_settled", observe.Display{
        dust_live_count = 8, dust_grounded_count = 7}))
    testing.expect(t, state_matches("dust_active", observe.Display{
        dust_live_count = 8, dust_grounded_count = 8,
        dust_peak_speed_sq =
            particlemodel.DUST_SETTLED_SPEED_SQ * 2}))
    testing.expect(t, state_matches("dust_airborne", observe.Display{
        dust_live_count = 8, dust_airborne_count = 1}))
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

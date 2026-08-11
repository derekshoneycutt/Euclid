package view_tests

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import app_core "../../src/core"
import app_trace "../../src/trace"

set_trace_run_id :: proc(state: ^app_core.Trace_State, run_id: string) {
    state^.run_id_len = copy(state^.run_id[:], transmute([]u8)run_id)
}

set_trace_record_text :: proc(destination: []u8, text: string) -> int {
    return copy(destination, transmute([]u8)text)
}

prepare_trace_sandbox :: proc(t: ^testing.T, dir_name: string) -> string {
    temp_dir, temp_err := os.temp_directory(context.temp_allocator)
    testing.expect(t, temp_err == nil)
    testing.expect(t, len(temp_dir) > 0)

    sandbox, join_err := filepath.join([]string{temp_dir, dir_name}, context.allocator)
    testing.expect(t, join_err == nil)
    _ = os.remove_all(sandbox)
    testing.expect(t, os.make_directory_all(sandbox) == nil)
    return sandbox
}

read_text_file :: proc(t: ^testing.T, path: string) -> string {
    data, read_err := os.read_entire_file(path, context.temp_allocator)
    testing.expect(t, read_err == nil)
    return string(data)
}

configure_enabled_trace :: proc(
    t: ^testing.T, state: ^app_core.Trace_State, output_path: string, strict: bool) {

    settings := app_core.Euclid_Run_Settings{
        semantic_trace_enabled = true,
        semantic_trace_strict = strict,
        semantic_trace_output = output_path,
        semantic_trace_events = "",
    }
    testing.expect(t, app_trace.initialize_trace_state(state, &settings))
    testing.expect(t, app_trace.begin_trace(state))
}

@(test)
semantic_trace_argument_parsing_accepts_supported_forms :: proc(t: ^testing.T) {
    settings := app_core.Euclid_Run_Settings{}

    handled, valid := app_trace.parse_semantic_trace_argument(&settings, "--semantic-trace")
    testing.expect(t, handled)
    testing.expect(t, valid)
    testing.expect(t, settings.semantic_trace_enabled)

    handled, valid = app_trace.parse_semantic_trace_argument(
        &settings, "--semantic-trace-events=runtime,animation")
    testing.expect(t, handled)
    testing.expect(t, valid)
    testing.expect_value(t, settings.semantic_trace_events, "runtime,animation")

    handled, valid = app_trace.parse_semantic_trace_argument(
        &settings, "--semantic-trace-output=/tmp/euclid-trace.jsonl")
    testing.expect(t, handled)
    testing.expect(t, valid)
    testing.expect_value(t, settings.semantic_trace_output, "/tmp/euclid-trace.jsonl")

    handled, valid = app_trace.parse_semantic_trace_argument(&settings, "--semantic-trace-strict")
    testing.expect(t, handled)
    testing.expect(t, valid)
    testing.expect(t, settings.semantic_trace_strict)
}

@(test)
semantic_trace_argument_parsing_rejects_unknown_categories :: proc(t: ^testing.T) {
    settings := app_core.Euclid_Run_Settings{}

    handled, valid := app_trace.parse_semantic_trace_argument(
        &settings, "--semantic-trace-events=runtime,unknown")
    testing.expect(t, handled)
    testing.expect(t, !valid)
}

@(test)
trace_json_serialization_escapes_strings_and_writes_envelope :: proc(t: ^testing.T) {
    state := new(app_core.Trace_State)
    defer free(state)
    state^.enabled = true
    set_trace_run_id(state, "run-test")

    record := app_core.Trace_Event_Record{}
    record.sequence = 7
    record.event_len = set_trace_record_text(record.event[:], "trace.started")
    record.payload_len = set_trace_record_text(record.payload[:], "{\"note\":\"a\\nb\"}")

    buffer: [app_core.TRACE_SERIALIZE_BUFFER_CAPACITY]u8
    out_len, ok := app_trace.serialize_event_record(state, &record, buffer[:])
    testing.expect(t, ok)
    line := string(buffer[:out_len])

    testing.expect(t, strings.contains(line, "\"schema\":\"euclid.semantic-trace\""))
    testing.expect(t, strings.contains(line, "\"version\":1"))
    testing.expect(t, strings.contains(line, "\"event\":\"trace.started\""))
    testing.expect(t, strings.contains(line, "\"seq\":7"))
    testing.expect(t, strings.contains(line, "\"run_id\":\"run-test\""))
    testing.expect(t, strings.contains(line, "\"payload\":{\"note\":\"a\\nb\"}"))
}

@(test)
trace_ring_wraps_and_preserves_monotonic_sequence_order :: proc(t: ^testing.T) {
    state := new(app_core.Trace_State)
    defer free(state)
    state^.enabled = true
    state^.output_mode = .Sink
    state^.categories = app_core.Trace_Category_Set{.Trace}
    set_trace_run_id(state, "run-wrap")
    state^.next_sequence = 1

    for _ in 0..<app_core.TRACE_RECORD_CAPACITY {
        testing.expect(t, app_trace.record_event(state, .Trace, "trace.started", ""))
    }

    testing.expect(t, app_trace.drain_trace(state))
    for _ in 0..<3 {
        testing.expect(t, app_trace.record_event(state, .Trace, "trace.started", ""))
    }

    testing.expect_value(t, state^.records_count, 3)
    testing.expect_value(t, state^.records[state^.records_head].sequence, u64(257))
    testing.expect_value(t, state^.next_sequence, u64(260))
}

@(test)
trace_strict_overflow_marks_state_invalid :: proc(t: ^testing.T) {
    state := new(app_core.Trace_State)
    defer free(state)
    state^.enabled = true
    state^.strict = true
    state^.output_mode = .Sink
    state^.categories = app_core.Trace_Category_Set{.Trace}
    set_trace_run_id(state, "run-strict")

    for _ in 0..<app_core.TRACE_RECORD_CAPACITY {
        testing.expect(t, app_trace.record_event(state, .Trace, "trace.started", ""))
    }

    testing.expect(t, !app_trace.record_event(state, .Trace, "trace.started", ""))
    testing.expect(t, state^.invalid)
    testing.expect_value(t, state^.dropped_count, u64(1))
    testing.expect(t, app_trace.should_fail_process(state))
}

@(test)
trace_file_lifecycle_writes_started_config_and_finished_records :: proc(t: ^testing.T) {
    sandbox := prepare_trace_sandbox(t, "euclid_trace_phase1")
    defer delete(sandbox)
    defer _ = os.remove_all(sandbox)

    output_path, join_err := filepath.join([]string{sandbox, "trace.jsonl"}, context.allocator)
    defer delete(output_path)
    testing.expect(t, join_err == nil)

    state := new(app_core.Trace_State)
    defer free(state)
    configure_enabled_trace(t, state, output_path, true)
    testing.expect(t, app_trace.record_runtime_event(state, "runtime.starting"))
    testing.expect(t, app_trace.record_animation_event(state, "animation.selected"))
    testing.expect(t, app_trace.finish_trace(state))

    content := read_text_file(t, output_path)
    testing.expect(t, strings.contains(content, "\"event\":\"trace.started\""))
    testing.expect(t, strings.contains(content, "\"event\":\"trace.configuration\""))
    testing.expect(t, strings.contains(content, "\"event\":\"runtime.starting\""))
    testing.expect(t, strings.contains(content, "\"event\":\"animation.selected\""))
    testing.expect(t, strings.contains(content, "\"event\":\"trace.finished\""))
    testing.expect(t, strings.contains(content, "\"dropped_count\":0"))
}

@(test)
trace_disabled_state_is_inert_and_does_not_emit :: proc(t: ^testing.T) {
    state := new(app_core.Trace_State)
    defer free(state)
    settings := app_core.Euclid_Run_Settings{}
    testing.expect(t, app_trace.initialize_trace_state(state, &settings))
    testing.expect(t, app_trace.begin_trace(state))
    testing.expect(t, app_trace.record_runtime_event(state, "runtime.starting"))
    testing.expect(t, app_trace.drain_trace(state))
    testing.expect(t, app_trace.finish_trace(state))
    testing.expect_value(t, state^.emitted_count, u64(0))
    testing.expect_value(t, state^.dropped_count, u64(0))
    testing.expect(t, !state^.invalid)
}

@(test)
trace_phase2_structured_events_include_expected_payload_fields :: proc(t: ^testing.T) {
    sandbox := prepare_trace_sandbox(t, "euclid_trace_phase2")
    defer delete(sandbox)
    defer _ = os.remove_all(sandbox)

    output_path, join_err := filepath.join([]string{sandbox, "trace.jsonl"}, context.allocator)
    defer delete(output_path)
    testing.expect(t, join_err == nil)

    state := new(app_core.Trace_State)
    defer free(state)
    configure_enabled_trace(t, state, output_path, true)

    testing.expect(t, app_trace.record_runtime_event_ex(
        state, "runtime.reload_committed", 9, 2, 77))
    testing.expect(t, app_trace.record_animation_event_ex(
        state, "animation.tick_rejected", 8, 126, "anim-1", "stale_sequence"))
    testing.expect(t, app_trace.finish_trace(state))

    content := read_text_file(t, output_path)
    testing.expect(t, strings.contains(content, "\"event\":\"runtime.reload_committed\""))
    testing.expect(t, strings.contains(content, "\"runtime_generation\":9"))
    testing.expect(t, strings.contains(content, "\"reload_state\":2"))
    testing.expect(t, strings.contains(content, "\"request_id\":77"))
    testing.expect(t, strings.contains(content, "\"event\":\"animation.tick_rejected\""))
    testing.expect(t, strings.contains(content, "\"animation_generation\":8"))
    testing.expect(t, strings.contains(content, "\"animation_tick\":126"))
    testing.expect(t, strings.contains(content, "\"animation_id\":\"anim-1\""))
    testing.expect(t, strings.contains(content, "\"reason\":\"stale_sequence\""))
}

@(test)
trace_phase3_summary_events_include_geometry_tool_and_particle_payloads :: proc(t: ^testing.T) {
    sandbox := prepare_trace_sandbox(t, "euclid_trace_phase3")
    defer delete(sandbox)
    defer _ = os.remove_all(sandbox)

    output_path, join_err := filepath.join([]string{sandbox, "trace.jsonl"}, context.allocator)
    defer delete(output_path)
    testing.expect(t, join_err == nil)

    state := new(app_core.Trace_State)
    defer free(state)
    configure_enabled_trace(t, state, output_path, true)

    testing.expect(t, app_trace.record_point_event(
        state,
        "point.position_changed",
        14,
        app_core.Vector3{0.25, 0.40, 0.0},
        app_core.Vector3{0.50, 0.40, 0.0},
        nil,
        nil,
        nil,
        nil))
    testing.expect(t, app_trace.record_tool_event(
        state,
        "pen.visibility_changed",
        "pen",
        "",
        nil,
        true,
        nil))
    testing.expect(t, app_trace.record_particles_emitted(
        state,
        "flicker",
        "high",
        10,
        app_core.Vector3{0.5, 0.4, 0.0},
        app_core.Bridge_Color{r = 70, g = 130, b = 180, a = 255}))
    testing.expect(t, app_trace.record_constraint_solve_summary(
        state,
        130,
        2.166667,
        12,
        18))
    testing.expect(t, app_trace.finish_trace(state))

    content := read_text_file(t, output_path)
    testing.expect(t, strings.contains(content, "\"event\":\"point.position_changed\""))
    testing.expect(t, strings.contains(content, "\"index\":14"))
    testing.expect(t, strings.contains(content, "\"from\":[0.25,0.4,0]"))
    testing.expect(t, strings.contains(content, "\"to\":[0.5,0.4,0]"))
    testing.expect(t, strings.contains(content, "\"event\":\"pen.visibility_changed\""))
    testing.expect(t, strings.contains(content, "\"tool\":\"pen\""))
    testing.expect(t, strings.contains(content, "\"visible\":true"))
    testing.expect(t, strings.contains(content, "\"event\":\"particles.emitted\""))
    testing.expect(t, strings.contains(content, "\"kind\":\"flicker\""))
    testing.expect(t, strings.contains(content, "\"layer\":\"high\""))
    testing.expect(t, strings.contains(content, "\"count\":10"))
    testing.expect(t, strings.contains(content, "\"event\":\"constraint.solve_summary\""))
    testing.expect(t, strings.contains(content, "\"fixed_step\":130"))
    testing.expect(t, strings.contains(content, "\"active_constraints\":12"))
    testing.expect(t, strings.contains(content, "\"next_constraint_index\":18"))
}

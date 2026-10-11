#+test
package artifact

import allocation "../allocation"
import trace "../trace"
import observe "../observe"
import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:testing"

// Tree facts retain their numeric types and remain separate from accordion state.
@(test)
artifact_tree_state_preserves_json_contract :: proc(t: ^testing.T) {
    state := observe.Display{
        tree_transition_count = 2, tree_visual_height = 130.5, tree_scroll_y = 10.25}
    text := artifact_state_json(state, {}, {})
    decoded: struct {
        tree: struct {transition_count: int, visual_height: f32, scroll_y: f32},
    }
    testing.expect(t, json.unmarshal_string(
        text, &decoded, allocator = context.allocator) == nil)
    testing.expect_value(t, decoded.tree.transition_count, 2)
    testing.expect_value(t, decoded.tree.visual_height, f32(130.5))
    testing.expect_value(t, decoded.tree.scroll_y, f32(10.25))
}

// Host JSON remains valid and keeps lifecycle and trace facts at the snapshot root.
@(test)
artifact_host_state_preserves_top_level_json_contract :: proc(t: ^testing.T) {
    host := observe.Julia_Host{active_request_id = 17, failed_request_count = 3,
        trace = {event_count = 5, evidence_complete = true}}
    text := artifact_state_json({}, host, {})
    decoded: struct {
        lifecycle: int `json:"julia_lifecycle"`,
        active_request_id: u64 `json:"julia_active_request_id"`,
        failed_requests: u64 `json:"julia_failed_requests"`,
        event_count: int `json:"julia_event_count"`,
        evidence_complete: bool `json:"julia_evidence_complete"`,
    }
    testing.expect(t, json.unmarshal_string(
        text, &decoded, allocator = context.allocator) == nil)
    testing.expect_value(t, decoded.lifecycle, int(host.lifecycle))
    testing.expect_value(t, decoded.active_request_id, host.active_request_id)
    testing.expect_value(t, decoded.failed_requests, host.failed_request_count)
    testing.expect_value(t, decoded.event_count, host.trace.event_count)
    testing.expect_value(t, decoded.evidence_complete, host.trace.evidence_complete)
}

// Verify the serialized failure manifest contains the canonical result.
artifact_test_expect_failure_manifest :: proc(t: ^testing.T, directory: string) {
    manifest, read_error := os.read_entire_file(
        fmt.tprintf("%s/manifest.json", directory), context.allocator)
    defer delete(manifest)
    testing.expect(t, read_error == nil)
    testing.expect(t, strings.contains(string(manifest), "\"result\":\"failed\""))
}

// Verify the serialized trace has the canonical header and two fixed events.
artifact_test_expect_failure_trace :: proc(t: ^testing.T, directory: string) {
    trace_data, read_error := os.read_entire_file(
        fmt.tprintf("%s/evidence.bin", directory), context.allocator)
    defer delete(trace_data)
    testing.expect(t, read_error == nil)
    testing.expect_value(t, len(trace_data),
        size_of(Trace_Header) + 2 * trace.TRACE_EVENT_SIZE_BYTES)
    testing.expect_value(t, string(trace_data[:4]), "EUCL")
}

// Verify standalone and bundle writers produce identical canonical trace bytes.
artifact_test_expect_standalone_trace :: proc(
    t: ^testing.T, directory: string, events: []trace.Event) {
    standalone_path := fmt.tprintf("%s/standalone.bin", directory)
    testing.expect(t, write_trace(standalone_path, events))
    standalone, standalone_error := os.read_entire_file(
        standalone_path, context.allocator)
    defer delete(standalone)
    bundled, bundled_error := os.read_entire_file(
        fmt.tprintf("%s/evidence.bin", directory), context.allocator)
    defer delete(bundled)
    testing.expect(t, standalone_error == nil)
    testing.expect(t, bundled_error == nil)
    testing.expect_value(t, len(standalone), len(bundled))
    testing.expect(t, mem.compare(standalone, bundled) == 0)
}

// Verify all named arena domains and the retained assertion result are serialized.
artifact_test_expect_arena_allocations :: proc(t: ^testing.T, directory: string) {
    data, read_error := os.read_entire_file(
        fmt.tprintf("%s/allocations.json", directory), context.allocator)
    defer delete(data)
    text := string(data)
    testing.expect(t, read_error == nil)
    testing.expect(t, strings.contains(text, "\"animation\""))
    testing.expect(t, strings.contains(text, "\"snapshot_slots\""))
    testing.expect(t, strings.contains(text, "\"display_cache\""))
    testing.expect(t, strings.contains(text, "\"assertion_present\":true"))
    testing.expect(t, strings.contains(text, "\"matched\":true"))
}

// Verify final state artifacts retain effective presentation viewport values.
artifact_test_expect_viewport_state :: proc(t: ^testing.T, directory: string) {
    data, read_error := os.read_entire_file(
        fmt.tprintf("%s/state.json", directory), context.allocator)
    defer delete(data)
    text := string(data)
    testing.expect(t, read_error == nil)
    testing.expect(t, strings.contains(text, "\"view_text_scroll_y\":90.5"))
    testing.expect(t, strings.contains(text, "\"view_text_scroll_max\":120"))
    testing.expect(t, strings.contains(text, "\"vertical_split_x\":640"))
    testing.expect(t, strings.contains(text, "\"horizontal_split_y\":360"))
    testing.expect(t, strings.contains(text, "\"animation_policy_paused\":true"))
    testing.expect(t, strings.contains(text, "\"colored_draw\""))
    testing.expect(t, strings.contains(text, "\"curve_candidate_points\":100"))
    testing.expect(t, strings.contains(text, "\"curve_retained_points\":25"))
    testing.expect(t, strings.contains(text, "\"curve_retention_ratio\":0.25"))
    testing.expect(t, strings.contains(text, "\"primitive_overflows\":0"))
    testing.expect(t, strings.contains(text, "\"terminal_graphics\""))
    testing.expect(t, strings.contains(text, "\"decode_count\":11"))
    testing.expect(t, strings.contains(text, "\"gpu_byte_count\":4096"))
    testing.expect(t, strings.contains(text, "\"simulation_workers\""))
    testing.expect(t, strings.contains(text, "\"particle\":{"))
    testing.expect(t, strings.contains(text, "\"next_sequence\":7"))
}

// Build the canonical failed bundle payload used by the artifact integration test.
artifact_test_failure_bundle_data :: proc(
    events: []trace.Event, arenas: allocation.Arena_Baselines) -> Bundle {
    return {
        manifest = {.Failed, .Wait_Timeout, 14, true, 2},
        events = events,
        state = {
            fixed_step = 9,
            animation_policy_paused = true,
            graphics_decode_count = 11,
            graphics_gpu_byte_count = 4096,
            view_text_scroll_y = 90.5,
            view_text_scroll_max = 120,
            vertical_split_x = 640,
            horizontal_split_y = 360,
            colored_vertex_count = 400,
            colored_index_count = 600,
            curve_candidate_point_count = 100,
            curve_retained_point_count = 25,
            curve_retention_ratio = 0.25,
        },
        julia_host = {runtime_generation = 2},
        simulation = {particle = {next_sequence = 7}},
        arena_baselines = arenas,
    }
}

// Verify a forced failure writes its canonical result and fixed binary trace.
@(test)
artifact_test_failure_bundle :: proc(t: ^testing.T) {
    directory := ".build/test-artifacts/artifact"
    os.remove_all(directory)
    defer os.remove_all(directory)
    events := [2]trace.Event{
        {sequence = 1, kind = .Runtime_Starting},
        {sequence = 2, kind = .Runtime_Reload_Rolled_Back},
    }
    arenas: allocation.Arena_Baselines
    arenas.present[allocation.Arena_Domain_Kind.Animation] = true
    arenas.observed_present[allocation.Arena_Domain_Kind.Animation] = true
    arenas.matched[allocation.Arena_Domain_Kind.Animation] = true
    written := write_bundle(
        directory, artifact_test_failure_bundle_data(events[:], arenas))
    testing.expect(t, written)
    if !written {
        return
    }

    artifact_test_expect_failure_manifest(t, directory)
    artifact_test_expect_failure_trace(t, directory)
    artifact_test_expect_standalone_trace(t, directory, events[:])
    artifact_test_expect_arena_allocations(t, directory)
    artifact_test_expect_viewport_state(t, directory)
    testing.expect(t, !write_bundle("../outside", {}))
    testing.expect(t, !write_trace("../outside.bin", events[:]))
}

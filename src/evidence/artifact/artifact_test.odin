#+test
package artifact

import "../observe"
import allocation "../allocation"
import trace "../trace"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:testing"

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
    written := write_bundle(directory, {
        manifest = {
            result = .Failed,
            reason = .Wait_Timeout,
            failed_step = 14,
            trace_complete = true,
            last_trace_sequence = 2,
        },
        events = events[:],
        state = observe.Display{fixed_step = 9},
        julia_host = observe.Julia_Host{runtime_generation = 2},
        arena_baselines = arenas,
    })
    testing.expect(t, written)
    if !written {
        return
    }

    artifact_test_expect_failure_manifest(t, directory)
    artifact_test_expect_failure_trace(t, directory)
    artifact_test_expect_standalone_trace(t, directory, events[:])
    artifact_test_expect_arena_allocations(t, directory)
    testing.expect(t, !write_bundle("../outside", {}))
    testing.expect(t, !write_trace("../outside.bin", events[:]))
}

package artifact

// Package artifact writes completed scenario evidence without runtime authority.

import "../observe"
import trace "../trace"
import "core:fmt"
import "core:os"
import json "core:encoding/json"
import allocation_evidence "../allocation"

ARTIFACT_MAX_EVENTS :: trace.TRACE_RING_CAPACITY * 16

ARTIFACT_SCHEMA_VERSION :: 1

// Stable scenario outcome serialized into the canonical manifest.
Result :: enum u8 {
    Passed,
    Failed,
    Inconclusive,
}

// Stable explanation for a failed or inconclusive scenario outcome.
//
// None accompanies successful runs. The remaining values distinguish behavioral
// failure from missing evidence so consumers do not infer success from process exit.
Reason :: enum u8 {
    None,
    Wait_Timeout,
    Assertion_Failed,
    Required_Evidence_Lost,
    Capture_Failed,
}

// Fixed prefix identifying and describing the binary trace payload.
//
// The header precedes contiguous trace.Event records and remains eight bytes so
// readers can reject incompatible schemas before decoding any event.
Trace_Header :: struct {
    // File identity; canonical bundles write the ASCII bytes "EUCL".
    magic : [4]u8,

    // Trace vocabulary version and serialized record width.
    schema_version : u16,
    event_size : u16,
}

#assert(size_of(Trace_Header) == 8)

// Canonical scenario result and trace-completeness summary.
//
// This value contains only scalar evidence selected by the scenario owner. The
// artifact writer serializes it but does not reinterpret or authorize the outcome.
Manifest :: struct {
    // Overall scenario outcome and its stable explanation.
    result : Result,
    reason : Reason,
    failed_step : int,

    // Completeness and final sequence metadata for the exported trace snapshot.
    trace_complete : bool,
    last_trace_sequence : u64,
}

// Borrowed and scalar evidence required to write one canonical bundle.
Bundle :: struct {
    manifest : Manifest,
    events : []trace.Event,
    state : observe.Display,
    julia_host : observe.Julia_Host,
    allocations : allocation_evidence.Snapshot,
    arena_baselines : allocation_evidence.Arena_Baselines,
}

//   Serialize one retained arena checkpoint and its final assertion sample.
artifact_arena_baseline_json :: proc(
    baselines: allocation_evidence.Arena_Baselines,
    kind: allocation_evidence.Arena_Domain_Kind) -> string {

    checkpoint := baselines.snapshots[kind]
    observed := baselines.observed[kind]
    return fmt.tprintf(
        "{{\"checkpoint_present\":%v,\"assertion_present\":%v," +
        "\"matched\":%v,\"checkpoint\":{{\"current_used\":%d," +
        "\"current_reserved\":%d,\"current_committed\":%d," +
        "\"peak_used\":%d,\"peak_reserved\":%d,\"peak_committed\":%d," +
        "\"reset_count\":%d,\"initialized_count\":%d}}," +
        "\"observed\":{{\"current_used\":%d,\"current_reserved\":%d," +
        "\"current_committed\":%d,\"peak_used\":%d," +
        "\"peak_reserved\":%d,\"peak_committed\":%d," +
        "\"reset_count\":%d,\"initialized_count\":%d}}}}",
        baselines.present[kind], baselines.observed_present[kind],
        baselines.matched[kind], checkpoint.current_used,
        checkpoint.current_reserved, checkpoint.current_committed,
        checkpoint.peak_used, checkpoint.peak_reserved,
        checkpoint.peak_committed, checkpoint.reset_count,
        checkpoint.initialized_count, observed.current_used,
        observed.current_reserved, observed.current_committed,
        observed.peak_used, observed.peak_reserved, observed.peak_committed,
        observed.reset_count, observed.initialized_count)
}

//   Serialize aggregate tracking counters and all retained arena assertions.
artifact_allocations_json :: proc(bundle: Bundle) -> string {
    animation_json := artifact_arena_baseline_json(
        bundle.arena_baselines, .Animation)
    snapshot_slots_json := artifact_arena_baseline_json(
        bundle.arena_baselines, .Snapshot_Slots)
    display_cache_json := artifact_arena_baseline_json(
        bundle.arena_baselines, .Display_Cache)
    return fmt.tprintf(
        "{{\"live_allocations\":%d,\"current_bytes\":%d," +
        "\"peak_bytes\":%d,\"total_allocations\":%d,\"bad_frees\":%d," +
        "\"arenas\":{{\"animation\":%s,\"snapshot_slots\":%s," +
        "\"display_cache\":%s}}}}\n",
        bundle.allocations.live_allocations, bundle.allocations.current_bytes,
        bundle.allocations.peak_bytes, bundle.allocations.total_allocations,
        bundle.allocations.bad_frees, animation_json, snapshot_slots_json,
        display_cache_json)
}

//   Serialize canonical scenario outcome metadata.
artifact_manifest_json :: proc(manifest: Manifest) -> string {
    return fmt.tprintf(
        "{{\"schema_version\":%d,\"result\":\"%s\",\"reason\":\"%s\"," +
        "\"failed_step\":%d,\"trace_complete\":%v," +
        "\"last_trace_sequence\":%d,\"artifacts\":{{" +
        "\"trace\":\"evidence.bin\",\"state\":\"state.json\"," +
        "\"allocations\":\"allocations.json\"}}}}\n",
        ARTIFACT_SCHEMA_VERSION, artifact_result_name(manifest.result),
        artifact_reason_name(manifest.reason), manifest.failed_step,
        manifest.trace_complete, manifest.last_trace_sequence)
}

//   Serialize the synchronized display and Julia-host observation snapshot.
artifact_state_json :: proc(
    state: observe.Display, julia_host: observe.Julia_Host) -> string {
    return fmt.tprintf(
        "{{\"fixed_step\":%d,\"simulation_time\":%g," +
        "\"simulation_paused\":%v,\"runtime_lifecycle\":%d," +
        "\"runtime_generation\":%d,\"active_runtime_request_id\":%d," +
        "\"failed_runtime_request_count\":%d,\"animation_generation\":%d," +
        "\"animation_tick_sequence\":%d," +
        "\"animation_last_committed_sequence\":%d," +
        "\"point_count\":%d,\"constraint_count\":%d," +
        "\"particle_count\":%d,\"dynview_enabled\":%v," +
        "\"gif_capture_active\":%v,\"gif_captured_frames\":%d," +
        "\"evidence_complete\":%v,\"display_event_count\":%d," +
        "\"display_pending_drops\":%d,\"julia_lifecycle\":%d," +
        "\"julia_active_request_id\":%d,\"julia_failed_requests\":%d," +
        "\"julia_event_count\":%d,\"julia_evidence_complete\":%v}}\n",
        state.fixed_step, state.simulation_time, state.simulation_paused,
        state.runtime_lifecycle, state.runtime_generation,
        state.active_runtime_request_id, state.failed_runtime_request_count,
        state.animation_generation, state.animation_tick_sequence,
        state.animation_last_committed_sequence, state.point_count,
        state.constraint_count, state.particle_count, state.dynview_enabled,
        state.gif_capture_active, state.gif_captured_frames,
        state.required_evidence_complete, state.trace.event_count,
        state.trace.pending_drops, julia_host.lifecycle,
        julia_host.active_request_id, julia_host.failed_request_count,
        julia_host.trace.event_count, julia_host.trace.evidence_complete)
}

//   Encode one unsigned 16-bit value in canonical little-endian order.
artifact_put_u16 :: proc(destination: []u8, offset: int, value: u16) {
    destination[offset] = u8(value)
    destination[offset + 1] = u8(value >> 8)
}

//   Encode one unsigned 32-bit value in canonical little-endian order.
artifact_put_u32 :: proc(destination: []u8, offset: int, value: u32) {
    for byte_index in 0..<4 {
        destination[offset + byte_index] = u8(value >> u32(byte_index * 8))
    }
}

//   Encode one unsigned 64-bit value in canonical little-endian order.
artifact_put_u64 :: proc(destination: []u8, offset: int, value: u64) {
    for byte_index in 0..<8 {
        destination[offset + byte_index] = u8(value >> u64(byte_index * 8))
    }
}

//   Encode the kind-selected payload variant field by field.
artifact_encode_payload :: proc(
    destination: []u8, kind: trace.Kind, payload: trace.Event_Payload) {
    #partial switch kind {
    case .Point_Position_Committed, .Point_Style_Committed,
         .Point_Visibility_Committed:
        artifact_put_u32(destination, 0, payload.point.point_index)
        artifact_put_u16(destination, 4, payload.point.field)
        destination[6] = payload.point.visible
        destination[7] = payload.point.reserved
    case .Animation_Tick_Accepted, .Animation_Tick_Rejected,
         .Scene_Batch_Rejected, .Scene_Command_Rejected:
        artifact_put_u16(destination, 0, payload.request.status)
        artifact_put_u16(destination, 2, payload.request.reason)
        artifact_put_u32(destination, 4, payload.request.slot)
    case .Checkpoint_Stored, .Checkpoint_Evicted:
        artifact_put_u16(destination, 0, payload.handle.slot)
        artifact_put_u16(destination, 2, payload.handle.generation)
        artifact_put_u16(destination, 4, payload.handle.flags)
        artifact_put_u16(destination, 6, payload.handle.reserved)
    case:
        artifact_put_u32(destination, 0, payload.counts.first)
        artifact_put_u32(destination, 4, payload.counts.second)
    }
}

//   Encode one fixed event without relying on native layout or endianness.
artifact_encode_event :: proc(destination: []u8, event: trace.Event) {
    artifact_put_u64(destination, 0, event.sequence)
    artifact_put_u64(destination, 8, event.timestamp_ns)
    artifact_put_u64(destination, 16, event.correlation)
    artifact_put_u64(destination, 24, event.generation)
    artifact_put_u64(destination, 32, event.tick)
    artifact_put_u64(destination, 40, event.revision)
    destination[48] = u8(event.producer)
    destination[49] = u8(event.lane)
    destination[50] = u8(event.correlation_kind)
    destination[51] = event.reserved
    artifact_put_u16(destination, 52, u16(event.kind))
    artifact_put_u16(destination, 54, transmute(u16)event.flags)
    artifact_encode_payload(destination[56:64], event.kind, event.payload)
}

//   Allocate and explicitly encode the schema header and trace records.
//
// The caller owns and must delete the returned bytes when successful.
artifact_trace_bytes :: proc(events: []trace.Event) -> ([]byte, bool) {
    trace_size := size_of(Trace_Header) + len(events) * size_of(trace.Event)
    trace_bytes, trace_error := make([]byte, trace_size, context.temp_allocator)
    if trace_error != nil {
        return nil, false
    }
    copy(trace_bytes[:4], []u8{'E', 'U', 'C', 'L'})
    artifact_put_u16(trace_bytes, 4, trace.TRACE_SCHEMA_VERSION)
    artifact_put_u16(trace_bytes, 6, trace.TRACE_EVENT_SIZE_BYTES)
    for event, event_index in events {
        offset := size_of(Trace_Header) + event_index * trace.TRACE_EVENT_SIZE_BYTES
        artifact_encode_event(
            trace_bytes[offset:offset + trace.TRACE_EVENT_SIZE_BYTES], event)
    }
    return trace_bytes, true
}

//   Write one canonical bounded evidence bundle beneath a caller-selected directory.
//
// Parameters:
//   - directory: Destination created recursively when absent.
//   - bundle: Canonical outcome, trace, observations, and allocation evidence.
//
// Returns:
//   - True only when every requested artifact was written.
//
// Side effects:
//   - Creates the destination directory and writes the manifest, trace, state,
//     allocation artifacts in canonical filenames.
//   - Temporarily allocates the complete binary trace buffer from the context allocator.
//
// Notes:
//   - The directory must be a safe relative path, and bounded inputs are rejected before
//     serialization. A filesystem failure may leave an earlier artifact already written.
//   - Trace records are copied from their fixed native representation; readers must
//     validate the header schema and event size before interpreting the payload.
write_bundle :: proc(
    directory: string, bundle: Bundle) -> bool {
    if !artifact_path_safe(directory) ||
        len(bundle.events) > ARTIFACT_MAX_EVENTS ||
        os.make_directory_all(directory) != nil {
        return false
    }
    manifest_json := artifact_manifest_json(bundle.manifest)
    state_json := artifact_state_json(bundle.state, bundle.julia_host)
    if !json.is_valid(transmute([]byte)manifest_json) ||
        !json.is_valid(transmute([]byte)state_json) {
        return false
    }
    allocations_json := artifact_allocations_json(bundle)
    trace_bytes, trace_ok := artifact_trace_bytes(bundle.events)
    if !trace_ok {
        return false
    }
    defer delete(trace_bytes)
    return os.write_entire_file(fmt.tprintf("%s/manifest.json", directory),
            manifest_json) == nil &&
        os.write_entire_file(fmt.tprintf("%s/evidence.bin", directory),
            trace_bytes) == nil &&
        os.write_entire_file(fmt.tprintf("%s/state.json", directory),
            state_json) == nil &&
        os.write_entire_file(fmt.tprintf("%s/allocations.json", directory),
            allocations_json) == nil
}

//   Return whether a bundle path is relative and contains no parent segment.
//
// Parameters:
//   - path: Candidate directory path supplied by the artifact caller.
//
// Returns:
//   - True for a nonempty relative path without parent traversal, NUL, or drive syntax.
//
// Notes:
//   - Both slash forms delimit segments so the same check protects cross-platform runs.
artifact_path_safe :: proc(path: string) -> bool {
    if len(path) == 0 {
        return false
    }
    bytes := transmute([]u8)path
    if bytes[0] == '/' || bytes[0] == '\\' {
        return false
    }
    segment_start := 0
    for index := 0; index <= len(bytes); index += 1 {
        if index < len(bytes) && bytes[index] != '/' && bytes[index] != '\\' {
            if bytes[index] == 0 || bytes[index] == ':' {
                return false
            }
            continue
        }
        if index - segment_start == 2 && bytes[segment_start] == '.' &&
            bytes[segment_start + 1] == '.' {
            return false
        }
        segment_start = index + 1
    }
    return true
}

//   Return the stable serialized spelling of one run result.
//
// Parameters:
//   - result: Scenario outcome represented in the manifest schema.
//
// Returns:
//   - A static lowercase name; unknown backing values conservatively map to
//     "inconclusive".
artifact_result_name :: proc(result: Result) -> string {
    switch result {
    case .Passed: return "passed"
    case .Failed: return "failed"
    case .Inconclusive: return "inconclusive"
    }
    return "inconclusive"
}

//   Return the stable serialized spelling of one failure reason.
//
// Parameters:
//   - reason: Scenario reason represented in the manifest schema.
//
// Returns:
//   - A static lowercase snake-case name; unknown backing values map to "none".
artifact_reason_name :: proc(reason: Reason) -> string {
    switch reason {
    case .None: return "none"
    case .Wait_Timeout: return "wait_timeout"
    case .Assertion_Failed: return "assertion_failed"
    case .Required_Evidence_Lost: return "required_evidence_lost"
    case .Capture_Failed: return "capture_failed"
    }
    return "none"
}

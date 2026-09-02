package evidence_export

// Package evidence_export presents completed typed evidence as versioned JSON Lines.
//
// Each line is one self-contained event envelope. The exporter borrows the
// session snapshot, preserves its retained order, and owns no runtime state.

import evidence_session "../session"
import trace "../trace"

import "core:fmt"
import "core:os"

// Stable identity and version of the JSON envelope, independent of the binary
// trace record version.
JSONL_SCHEMA_NAME :: "euclid.semantic-evidence"
JSONL_SCHEMA_VERSION :: 1

// Stable external names for event kinds in the version-one JSON vocabulary.
// New serializable kinds must receive an explicit name in this table.
EVENT_KIND_NAMES :: #sparse [trace.Kind]string{
    .Unknown = "unknown",
    .Session_Started = "session.started",
    .Session_Configured = "session.configured",
    .Session_Finished = "session.finished",
    .Trace_Gap = "trace.gap",
    .Runtime_Starting = "runtime.starting",
    .Runtime_Ready = "runtime.ready",
    .Runtime_Reload_Started = "runtime.reload_started",
    .Runtime_Reload_Committed = "runtime.reload_committed",
    .Runtime_Reload_Rolled_Back = "runtime.reload_rolled_back",
    .Runtime_Shutdown_Started = "runtime.shutdown_started",
    .Runtime_Shutdown_Complete = "runtime.shutdown_complete",
    .Animation_Reset_Requested = "animation.reset_requested",
    .Animation_Reset_Committed = "animation.reset_committed",
    .Animation_Selected = "animation.selected",
    .Animation_Tick_Accepted = "animation.tick_accepted",
    .Animation_Tick_Committed = "animation.tick_committed",
    .Animation_Tick_Rejected = "animation.tick_rejected",
    .Animation_Cycle_Boundary = "animation.cycle_boundary",
    .Animation_Loaded = "animation.loaded",
    .Scene_Batch_Published = "scene.batch_published",
    .Scene_Batch_Committed = "scene.batch_committed",
    .Scene_Batch_Rejected = "scene.batch_rejected",
    .Scene_Command_Rejected = "scene.command_rejected",
    .Point_Position_Committed = "point.position_committed",
    .Point_Style_Committed = "point.style_committed",
    .Point_Visibility_Committed = "point.visibility_committed",
    .Constraint_Solve_Completed = "constraint.solve_completed",
    .Constraint_Solve_Failed = "constraint.solve_failed",
    .Pen_Joint_Committed = "pen.joint_committed",
    .Pen_Active_Committed = "pen.active_committed",
    .Pen_Visibility_Committed = "pen.visibility_committed",
    .Compass_Joint_Committed = "compass.joint_committed",
    .Compass_Active_Committed = "compass.active_committed",
    .Compass_Visibility_Committed = "compass.visibility_committed",
    .Particle_Emission_Committed = "particle.emission_committed",
    .Particle_Emission_Rejected = "particle.emission_rejected",
    .Frame_Presented = "frame.presented",
    .Dynview_Published = "dynview.published",
    .Capture_Requested = "capture.requested",
    .Capture_Completed = "capture.completed",
    .Capture_Failed = "capture.failed",
    .Gif_Started = "gif.started",
    .Gif_Completed = "gif.completed",
    .Gif_Failed = "gif.failed",
    .Shape_Cache_Prepared = "shape_cache.prepared",
    .Dynview_Compiled = "dynview.compiled",
    .Scratchpad_Completed = "scratchpad.completed",
    .Checkpoint_Requested = "checkpoint.requested",
    .Checkpoint_Stored = "checkpoint.stored",
    .Checkpoint_Unavailable = "checkpoint.unavailable",
    .Checkpoint_Evicted = "checkpoint.evicted",
    .Scenario_Started = "scenario.started",
    .Scenario_Action_Issued = "scenario.action_issued",
    .Scenario_Wait_Satisfied = "scenario.wait_satisfied",
    .Scenario_Assertion_Passed = "scenario.assertion_passed",
    .Scenario_Assertion_Failed = "scenario.assertion_failed",
    .Scenario_Passed = "scenario.passed",
    .Scenario_Failed = "scenario.failed",
    .Scenario_Inconclusive = "scenario.inconclusive",
    .Allocation_Checkpoint = "allocation.checkpoint",
    .Allocation_Baseline_Matched = "allocation.baseline_matched",
    .Allocation_Baseline_Mismatched = "allocation.baseline_mismatched",
    .Allocation_Bad_Free = "allocation.bad_free",
}

//   Return the stable serialized name of one typed event kind.
//
// Parameters:
//   - kind: Typed occurrence whose external JSON name is required.
//
// Returns:
//   - Stable event name, or "unknown" when the kind has no mapped name.
event_kind_name :: proc(kind: trace.Kind) -> string {
    names := EVENT_KIND_NAMES
    name := names[kind]
    if len(name) == 0 {
        return "unknown"
    }
    return name
}

//   Serialize one typed event into the version-one JSONL envelope.
//
// Parameters:
//   - run_id: Session identity copied into the event envelope.
//   - event: Complete typed event to present without semantic modification.
//
// Returns:
//   - One temporary-allocator-backed JSON object followed by a newline.
//
// Notes:
//   - The event kind determines how consumers interpret payload_a and payload_b.
//   - Those fields expose the fixed eight-byte payload as two raw words.
jsonl_event :: proc(run_id: string, event: trace.Event) -> string {
    return fmt.tprintf(
        "{{\"schema\":\"%s\",\"version\":%d,\"event\":\"%s\"," +
        "\"seq\":%d,\"run_id\":\"%s\",\"producer\":%d,\"lane\":%d," +
        "\"correlation_kind\":%d,\"correlation\":%d,\"generation\":%d," +
        "\"tick\":%d,\"revision\":%d,\"flags\":%d," +
        "\"payload_a\":%d,\"payload_b\":%d}}\n",
        JSONL_SCHEMA_NAME, JSONL_SCHEMA_VERSION, event_kind_name(event.kind),
        event.sequence, run_id, event.producer, event.lane,
        event.correlation_kind, event.correlation, event.generation,
        event.tick, event.revision, transmute(u16)event.flags,
        event.payload.counts.first, event.payload.counts.second)
}

//   Write the cumulative typed snapshot to the configured destination.
//
// Parameters:
//   - session: Borrowed session containing output policy and retained events.
//
// Returns:
//   - true when output is unnecessary or every retained event was written.
//   - false for a missing file path or any open/write failure.
//
// Side effects:
//   - Writes complete lines to stdout, or creates and truncates the output file.
//
// Notes:
//   - Events are emitted in session retention order.
//   - Nil, disabled, and sink sessions intentionally perform no I/O and succeed.
//   - The caller owns recording export failure in run-level evidence policy.
write_session_jsonl_file :: proc(
    session: ^evidence_session.Session, run_id: string) -> bool {
    path := string(session.output_path[:session.output_path_count])
    if len(path) == 0 {
        return false
    }
    handle, open_error := os.open(path, {.Create, .Write, .Trunc})
    if open_error != nil {
        return false
    }
    defer os.close(handle)
    for event in session.events[:session.event_count] {
        line := jsonl_event(run_id, event)
        written := 0
        for written < len(line) {
            count, write_error := os.write(handle, transmute([]u8)line[written:])
            if write_error != nil || count <= 0 {
                return false
            }
            written += count
        }
    }
    return true
}

//   Write the cumulative typed snapshot to the configured destination.
//
// Parameters:
//   - session: Borrowed session containing output policy and retained events.
//
// Returns:
//   - true when output is unnecessary or every retained event was written.
//   - false for a missing file path or any open/write failure.
//
// Side effects:
//   - Writes complete lines to stdout, or creates and truncates the output file.
//
// Notes:
//   - Events are emitted in session retention order.
//   - Nil, disabled, and sink sessions intentionally perform no I/O and succeed.
//   - The caller owns recording export failure in run-level evidence policy.
write_session_jsonl :: proc(session: ^evidence_session.Session) -> bool {
    if session == nil || !session.enabled || session.output_mode == .Sink {
        return true
    }
    run_id := string(session.run_id[:session.run_id_count])
    switch session.output_mode {
    case .Stdout:
        for event in session.events[:session.event_count] {
            fmt.print(jsonl_event(run_id, event))
        }
        return true
    case .File:
        return write_session_jsonl_file(session, run_id)
    case .Disabled, .Sink:
        return true
    }
    return false
}

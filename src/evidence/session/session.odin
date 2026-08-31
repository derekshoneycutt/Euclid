package session

// Package session owns semantic evidence policy, retained events, and run health.
//
// Producer rings remain owner-local. A session accepts their events only at
// established synchronization boundaries and retains a bounded cumulative
// snapshot for export and scenario evaluation.

import "../trace"

import "core:fmt"
import "core:os"
import "core:time"

// Fixed capacities for copied configuration and cumulative event storage.
SESSION_RUN_ID_CAPACITY :: 64
SESSION_OUTPUT_PATH_CAPACITY :: 1024
SESSION_EVENT_CAPACITY :: trace.TRACE_RING_CAPACITY * 8
SESSION_OPTIONAL_EVENT_CAPACITY :: SESSION_EVENT_CAPACITY / 2

// Final evidence destination selected independently from event recording.
Output_Mode :: enum u8 {
    // No durable destination is configured.
    Disabled,

    // Emit completed JSON Lines to standard output.
    Stdout,

    // Create or replace the configured evidence file.
    File,

    // Retain evidence in memory without final output.
    Sink,
}

// Compact recording policy selecting semantic evidence lanes.
Lane_Set :: bit_set[trace.Lane; u8]

// Complete lane policy used when the CLI does not provide a selection.
ALL_LANES :: Lane_Set{
    .Lifecycle,
    .Domain,
    .Transport,
    .Presentation,
    .Scenario,
    .Diagnostic,
}

// Borrowed initialization policy copied into fixed session-owned storage.
Config :: struct {
    // Recording and shutdown-failure policy.
    enabled: bool,
    strict: bool,

    // Final destination and accepted evidence classes.
    output_mode: Output_Mode,
    lanes: Lane_Set,

    // Optional run identity and destination path copied during initialization.
    run_id: string,
    output_path: string,
}

// Application-owned semantic evidence policy, storage, and aggregate health.
//
// Required-evidence and export failures are sticky for the session lifetime.
// Fixed byte arrays own copied configuration; event_count selects the valid
// prefix of the cumulative event snapshot.
Session :: struct {
    // Recording policy and lifecycle state.
    enabled: bool,
    strict: bool,
    finished: bool,

    // Final destination and enabled evidence classes.
    output_mode: Output_Mode,
    lanes: Lane_Set,

    // Sticky correctness-evidence and export outcomes.
    required_evidence_complete: bool,
    export_succeeded: bool,

    // Inline run identity and initialized byte count.
    run_id: [SESSION_RUN_ID_CAPACITY]u8,
    run_id_count: int,

    // Inline destination path and initialized byte count.
    output_path: [SESSION_OUTPUT_PATH_CAPACITY]u8,
    output_path_count: int,

    // Cumulative accepted events in synchronization-handoff order.
    events: [SESSION_EVENT_CAPACITY]trace.Event,
    event_count: int,
}

//   Resolve one public lane name or legacy category alias.
//
// Parameters:
//   - name: One nonempty token from a comma-separated CLI selection.
//
// Returns:
//   - Corresponding evidence lanes and true, or an empty set and false.
lane_selection_token :: proc(name: string) -> (Lane_Set, bool) {
    switch name {
    case "lifecycle", "runtime":
        return {.Lifecycle}, true
    case "domain", "animation", "geometry", "tools", "particles":
        return {.Domain}, true
    case "transport":
        return {.Transport}, true
    case "presentation", "view":
        return {.Presentation}, true
    case "scenario":
        return {.Scenario}, true
    case "diagnostic", "trace":
        return {.Diagnostic}, true
    }
    return {}, false
}

//   Parse a comma-separated evidence lane selection without allocating.
//
// Parameters:
//   - selection: Canonical lane names or retained legacy category aliases.
//
// Returns:
//   - Selected lanes and true, or an empty set and false for any invalid token.
//
// Notes:
//   - Empty input selects every lane.
//   - Legacy aliases map to their nearest typed evidence lane and may coalesce.
parse_lane_selection :: proc(selection: string) -> (Lane_Set, bool) {
    if len(selection) == 0 {
        return ALL_LANES, true
    }
    lanes: Lane_Set
    token_start := 0
    for token_end in 0..=len(selection) {
        if token_end < len(selection) && selection[token_end] != ',' {
            continue
        }
        selected, valid := lane_selection_token(selection[token_start:token_end])
        if !valid {
            return {}, false
        }
        lanes += selected
        token_start = token_end + 1
    }
    return lanes, true
}

//   Initialize fixed session policy and run identity without opening outputs.
//
// Parameters:
//   - session: Application-owned destination for policy and retained evidence.
//   - config: Borrowed policy whose strings are copied into fixed storage.
//
// Returns:
//   - True when policy and identity fit; false for nil or oversized input.
//
// Side effects:
//   - Replaces session state after validating output-path capacity.
//   - Generates a process-and-time run identity when an enabled config omits one.
//
// Notes:
//   - Disabled policy forces Disabled output and leaves run identity empty.
//   - Initialization does not open, create, or validate an output destination.
session_init :: proc(session: ^Session, config: Config) -> bool {
    if session == nil || len(config.output_path) > SESSION_OUTPUT_PATH_CAPACITY {
        return false
    }
    session^ = {
        enabled = config.enabled,
        strict = config.strict,
        output_mode = config.output_mode,
        lanes = config.lanes,
        required_evidence_complete = true,
        export_succeeded = true,
    }
    if !config.enabled {
        session.output_mode = .Disabled
        return true
    }
    session.output_path_count = copy(
        session.output_path[:], transmute([]u8)config.output_path)
    identity := config.run_id
    if len(identity) == 0 {
        identity = fmt.tprintf(
            "run-%d-%d", os.get_pid(), time.time_to_unix_nano(time.now()))
    }
    if len(identity) > SESSION_RUN_ID_CAPACITY {
        return false
    }
    session.run_id_count = copy(session.run_id[:], transmute([]u8)identity)
    return session.run_id_count > 0
}

//   Report whether one lane is enabled for this evidence session.
//
// Parameters:
//   - session: Session policy to inspect.
//   - lane: Evidence class proposed for recording.
//
// Returns:
//   - True only when the session is enabled and includes the lane.
session_lane_enabled :: proc(session: ^Session, lane: trace.Lane) -> bool {
    return session != nil && session.enabled && lane in session.lanes
}

//   Record one typed event into producer-owned storage under session policy.
//
// Parameters:
//   - session: Session supplying lane policy and aggregate health.
//   - ring: Current producer's owner-local destination.
//   - event: Typed event considered for recording.
//
// Returns:
//   - True when retained or intentionally filtered; false when the ring drops it.
//
// Side effects:
//   - Records enabled lanes through the producer ring's sequencing policy.
//   - Makes session completeness sticky-false when a required event is dropped.
//
// Notes:
//   - The caller must own ring mutation; this procedure performs no synchronization.
session_record :: proc(
    session: ^Session, ring: ^trace.Ring, event: trace.Event) -> bool {
    if session == nil || ring == nil ||
        !session_lane_enabled(session, event.lane) {
        return true
    }
    retained := trace.ring_record(ring, event)
    if !retained && .Required in event.flags {
        session.required_evidence_complete = false
    }
    return retained
}

//   Permanently mark required semantic evidence incomplete.
//
// Parameters:
//   - session: Session whose aggregate health must record evidence loss.
//
// Side effects:
//   - Sets required_evidence_complete false; nil is an accepted no-op.
session_mark_incomplete :: proc(session: ^Session) {
    if session != nil {
        session.required_evidence_complete = false
    }
}

//   Apply synchronized producer completeness to the sticky session result.
//
// Parameters:
//   - session: Session receiving aggregate producer health.
//   - rings: Producer rings stable at an established synchronization boundary.
//
// Side effects:
//   - Makes session completeness sticky-false if any ring lost required evidence.
//
// Notes:
//   - This procedure does not lock rings or restore an already incomplete session.
session_merge_ring_completeness :: proc(session: ^Session, rings: []^trace.Ring) {
    if session == nil || !session.required_evidence_complete {
        return
    }
    if !trace.session_evidence_complete(rings) {
        session.required_evidence_complete = false
    }
}

//   Drain one synchronized producer ring into the bounded cumulative snapshot.
//
// Parameters:
//   - session: Session owning cumulative event storage.
//   - ring: Producer ring stable for owner handoff and destructive draining.
//
// Returns:
//   - Number of events drained from the producer ring.
//
// Side effects:
//   - Drains the producer ring and admits events under bounded session policy.
//   - Makes completeness sticky-false for required producer loss or overflow.
//
// Notes:
//   - Retained events remain in producer-local order; this does not globally merge.
//   - Optional events beyond their budget are intentionally omitted.
session_accept_ring :: proc(session: ^Session, ring: ^trace.Ring) -> int {
    if session == nil || ring == nil || !session.enabled {
        return 0
    }
    if !trace.ring_evidence_complete(ring) {
        session.required_evidence_complete = false
    }
    pending: [trace.TRACE_RING_CAPACITY]trace.Event
    drained := trace.ring_drain(ring, pending[:])
    for event in pending[:drained] {
        _ = session_accept_event(session, event)
    }
    return drained
}

//   Append one event delivered through an existing synchronized owner handoff.
//
// Parameters:
//   - session: Session owning cumulative event storage.
//   - event: Complete event already admitted by its producer policy.
//
// Returns:
//   - True when appended, intentionally omitted, or recording is disabled.
//   - False when required evidence exceeds total session capacity.
//
// Side effects:
//   - Appends under required-reserve policy or marks required overflow sticky.
//
// Notes:
//   - Lane filtering is not repeated at this synchronized handoff boundary.
//   - Optional records cannot consume the capacity reserved for required evidence.
session_accept_event :: proc(session: ^Session, event: trace.Event) -> bool {
    if session == nil || !session.enabled {
        return true
    }
    required := .Required in event.flags
    if !required && session.event_count >= SESSION_OPTIONAL_EVENT_CAPACITY {
        return true
    }
    if session.event_count == len(session.events) {
        session.required_evidence_complete = false
        return false
    }
    session.events[session.event_count] = event
    session.event_count += 1
    return true
}

//   Mark final export success and close the session policy lifecycle.
//
// Parameters:
//   - session: Session reaching its owner-controlled shutdown boundary.
//   - export_succeeded: Outcome of the final configured export attempt.
//
// Side effects:
//   - Accumulates export failure and marks the session finished.
//
// Notes:
//   - A prior export failure remains sticky across later successful calls.
session_finish :: proc(session: ^Session, export_succeeded: bool) {
    if session == nil {
        return
    }
    session.export_succeeded = session.export_succeeded && export_succeeded
    session.finished = true
}

//   Report whether strict policy requires process failure at the safe shutdown boundary.
//
// Parameters:
//   - session: Completed or completing session policy to evaluate.
//
// Returns:
//   - True only for enabled strict sessions with evidence loss or export failure.
session_should_fail_process :: proc(session: ^Session) -> bool {
    return session != nil && session.enabled && session.strict &&
        (!session.required_evidence_complete || !session.export_succeeded)
}

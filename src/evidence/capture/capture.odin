package capture

// Package capture binds expensive evidence to post-presentation semantic checkpoints.

import trace "../trace"

CAPTURE_PATH_CAPACITY :: 512

// Lifecycle state for one post-presentation evidence request.
//
// Idle also represents the absence of applicable work when no request is pending.
Checkpoint_Status :: enum u8 {
    Idle,
    Pending,
    Completed,
    Failed,
}

// Stable reason a requested capture did not complete.
Failure_Reason :: enum u8 {
    None,
    No_Sink,
    Materialization_Failed,
}

// Scalar identity and presentation facts associated with one evidence capture.
//
// Trigger fields identify why capture was requested. Presentation fields are filled
// only when the display owner reaches the first eligible completed frame.
Checkpoint :: struct {
    // Request lifecycle and semantic trigger identity.
    status : Checkpoint_Status,
    failure_reason: Failure_Reason,
    scenario_step : u32,
    trigger: trace.Identity,

    // Display and simulation state visible when fulfillment was attempted.
    presented_frame : u64,
    fixed_step : u64,
}

// Display-owned callback that materializes evidence for one checkpoint value.
//
// The callback receives opaque caller state and a copied checkpoint. It returns true
// only when all evidence under its authority was captured successfully.
Capture_Proc :: proc(user_data: rawptr, checkpoint: Checkpoint) -> bool

// Optional capture destination invoked at the post-presentation boundary.
Sink :: struct {
    // Opaque state interpreted exclusively by the callback implementation.
    user_data : rawptr,

    // Capture operation; nil causes a pending checkpoint to fail explicitly.
    capture : Capture_Proc,
}

// Display-owned coordinator retaining at most one checkpoint request.
//
// The path is stored inline to keep request admission bounded and independent of the
// caller's source lifetime. The initialized prefix is followed by a zero byte.
Coordinator :: struct {
    // Current request identity, lifecycle, and eventual presentation facts.
    checkpoint : Checkpoint,

    // Inline screenshot path and its initialized byte count.
    path : [CAPTURE_PATH_CAPACITY]u8,
    path_count : int,
}

//   Request evidence for the first complete frame presented after a semantic trigger.
//
// Parameters:
//   - coordinator: Display-owned destination for the pending request.
//   - scenario_step: Scenario command index responsible for the checkpoint.
//   - trigger_sequence: Semantic trace sequence that authorized capture.
//   - path: Optional safe relative screenshot target copied into fixed storage.
//
// Returns:
//   - False while another request is pending; true after storing this request.
//
// Side effects:
//   - Replaces any nonpending checkpoint and its retained path with a pending request.
//
// Notes:
//   - Paths reserve one byte for NUL termination and require no allocation.
checkpoint_request :: proc(
    coordinator: ^Coordinator, scenario_step: u32,
    trigger: trace.Identity, path: string = "") -> bool {
    if coordinator == nil || coordinator.checkpoint.status == .Pending ||
        len(path) >= CAPTURE_PATH_CAPACITY || !capture_path_safe(path) {
        return false
    }
    coordinator.path = {}
    copy(coordinator.path[:], transmute([]u8)path)
    coordinator.path_count = len(path)
    coordinator.checkpoint = {
        status = .Pending,
        scenario_step = scenario_step,
        trigger = trigger,
    }
    return true
}

//   Return whether a screenshot path is relative and contains no parent segment.
//
// Parameters:
//   - path: Candidate screenshot target; an empty path represents no screenshot.
//
// Returns:
//   - True for an empty or relative path without parent traversal, NUL, or drive syntax.
//
// Notes:
//   - Both slash forms delimit segments so validation is stable across platforms.
capture_path_safe :: proc(path: string) -> bool {
    if len(path) == 0 {
        return true
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

//   Return the bounded NUL-terminated screenshot target for a pending checkpoint.
//
// Parameters:
//   - coordinator: Coordinator retaining the copied path bytes.
//
// Returns:
//   - A borrowed C string, or nil when no coordinator or path is available.
//
// Notes:
//   - The pointer remains valid only until the coordinator is modified or destroyed.
checkpoint_path :: proc(coordinator: ^Coordinator) -> cstring {
    if coordinator == nil || coordinator.path_count == 0 {
        return nil
    }
    return cstring(&coordinator.path[0])
}

//   Fulfill pending evidence only after the display owner completes presentation.
//
// Parameters:
//   - coordinator: Display-owned checkpoint state.
//   - frame: Monotonic presented-frame identity.
//   - engine_tick: Engine tick visible in that frame.
//   - engine_revision: Engine revision visible in that frame.
//   - sink: Optional real display capture mechanism.
//
// Returns:
//   - Current checkpoint status.
//
// Side effects:
//   - Records presentation and engine facts, invokes the sink synchronously, and marks
//     the request completed or failed according to the callback result.
//
// Notes:
//   - A missing coordinator or nonpending request returns Idle without mutation.
//   - The callback runs only after the caller has completed frame presentation.
checkpoint_after_present :: proc(
    coordinator: ^Coordinator, presented_frame, fixed_step: u64,
    sink: Sink) -> Checkpoint_Status {
    if coordinator == nil || coordinator.checkpoint.status != .Pending {
        return .Idle
    }
    coordinator.checkpoint.presented_frame = presented_frame
    coordinator.checkpoint.fixed_step = fixed_step
    if sink.capture == nil {
        coordinator.checkpoint.failure_reason = .No_Sink
        coordinator.checkpoint.status = .Failed
        return .Failed
    }
    if !sink.capture(sink.user_data, coordinator.checkpoint) {
        coordinator.checkpoint.failure_reason = .Materialization_Failed
        coordinator.checkpoint.status = .Failed
        return .Failed
    }
    coordinator.checkpoint.status = .Completed
    return .Completed
}

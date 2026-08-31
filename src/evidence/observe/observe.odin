package observe

// Package observe copies bounded Euclid facts at explicit ownership boundaries.
//
// Observations are pointer-free values and do not retain source storage. This
// package does not establish synchronization: callers must already own the
// source or have completed the documented producer handoff or task join.

import app_core "../../core"
import allocation_evidence "../allocation"
import evidence_trace "../trace"

// Point-in-time summary of one producer-owned evidence ring.
//
// Retained event count and pending drops describe current bounded storage;
// next_sequence includes sequence identities consumed by dropped events.
Trace_State :: struct {
    // Producer identity and sticky required-evidence health.
    producer : evidence_trace.Producer,
    evidence_complete : bool,

    // Current retained records, unreported drops, and next local identity.
    event_count : int,
    pending_drops : u64,
    next_sequence : u64,
}

// Pointer-free snapshot of state authoritative to the display owner.
//
// Optional subsystem fields remain zero when their backing service or system
// is absent. required_evidence_complete combines session-wide health with the
// display producer ring's sticky required-evidence state.
Display :: struct {
    // Fixed-step simulation clock and display-owned pause control.
    fixed_step : u64,
    simulation_time : f32,
    simulation_paused : bool,

    // Julia runtime lifecycle, active request, and submission pressure.
    runtime_lifecycle : app_core.Julia_Lifecycle_State,
    runtime_generation : u64,
    active_runtime_request_id : u64,
    failed_runtime_request_count : u64,
    runtime_request_saturation_count : u64,
    scratchpad_idle : bool,

    // Animation publication identity and display-side tick state.
    animation_generation : u64,
    animation_tick_sequence : u64,
    animation_last_committed_sequence : u64,
    animation_tick_pending : bool,
    animation_ticks_dropped : u64,

    // Current initialized prefixes of display-visible model storage.
    point_count : int,
    constraint_count : int,
    particle_count : int,

    // Dynamic-view activation and pending invalidation work.
    dynview_enabled : bool,
    dynview_pending_invalidation_mask : u32,

    // GIF capture lifecycle and completed frame count.
    gif_capture_active : bool,
    gif_capture_phase : app_core.Gif_Capture_Phase,
    gif_captured_frames : int,

    // Aggregate required-evidence health and display producer state.
    required_evidence_complete : bool,
    trace : Trace_State,
}

// Pointer-free snapshot of state authoritative to the Julia host owner.
//
// Runtime fields describe serialized request processing. Animation counters
// distinguish submitted work from committed, coalesced, stale, and dropped
// outcomes without exposing the service's mutable queues.
Julia_Host :: struct {
    // Runtime lifecycle, active request identity, and submission outcomes.
    lifecycle : app_core.Julia_Lifecycle_State,
    runtime_generation : u64,
    active_request_id : u64,
    active_request_kind : app_core.Julia_Request_Kind,
    failed_request_count : u64,
    request_saturation_count : u64,

    // Animation publication identity, pending state, and lifetime outcomes.
    animation_generation : u64,
    animation_tick_sequence : u64,
    animation_last_committed_sequence : u64,
    animation_tick_pending : bool,
    animation_ticks_submitted : u64,
    animation_ticks_committed : u64,
    animation_ticks_coalesced : u64,
    animation_ticks_stale : u64,
    animation_ticks_dropped : u64,

    // Julia-host producer evidence state.
    trace : Trace_State,
}

// Producer-ring summaries made stable by simulation and preparation joins.
Simulation :: struct {
    // Fixed-step worker evidence.
    particle : Trace_State,
    constraint : Trace_State,

    // Frame-preparation worker evidence.
    shape_cache : Trace_State,
    dynview : Trace_State,
}

// Stable scenario lifecycle independent of parser and runner storage.
Scenario_Lifecycle :: enum u8 {
    // No scenario is active at this boundary.
    Inactive,

    // At least one command remains pending or active.
    Running,

    // Terminal outcomes distinguish success, behavioral failure, and lost evidence.
    Passed,
    Failed,
    Inconclusive,
}

// Pointer-free scenario progress copied at the runner ownership boundary.
//
// Step and assertion counters are cumulative for one run. deadline_ns is the
// active monotonic wait deadline, or zero when no bounded wait is active.
Scenario :: struct {
    // Current lifecycle and command progress.
    lifecycle : Scenario_Lifecycle,
    current_step : u32,
    step_count : u32,

    // Cumulative verification outcomes.
    assertion_count : u32,
    failure_count : u32,

    // Active wait bound and sticky required-evidence health.
    deadline_ns : u64,
    required_evidence_complete : bool,
}

//   Copy one ring's scalar state at its owner or synchronized boundary.
//
// Parameters:
//   - ring: Producer-owned ring already safe for observation.
//
// Returns:
//   - Pointer-free ring summary, or zero values for a nil ring.
//
// Notes:
//   - This procedure does not lock the ring or establish an ownership boundary.
trace_state :: proc(ring: ^evidence_trace.Ring) -> Trace_State {
    if ring == nil {
        return {}
    }
    return {
        producer = ring.producer,
        evidence_complete = evidence_trace.ring_evidence_complete(ring),
        event_count = ring.count,
        pending_drops = ring.pending_drops,
        next_sequence = ring.next_sequence,
    }
}

//   Copy Julia-service fields into an in-progress display observation.
observe_display_julia_service :: proc(
    service: ^app_core.Julia_Runtime_Service, result: ^Display) {
    if service == nil {
        return
    }
    result.runtime_lifecycle = service.lifecycle
    result.runtime_generation = service.runtime_generation
    result.active_runtime_request_id = service.active_request_id
    result.failed_runtime_request_count = service.failed_request_count
    result.runtime_request_saturation_count = service.request_saturation_count
    result.animation_generation = service.animation_generation
    result.animation_tick_sequence = service.animation_tick_sequence
    result.animation_last_committed_sequence = service.animation_last_committed_sequence
    result.animation_tick_pending = service.animation_tick_pending
    result.animation_ticks_dropped = service.animation_ticks_dropped
}

//   Copy display-owned Euclid truth without advancing any subsystem.
//
// Parameters:
//   - state: Display-owned state observed from the display thread.
//
// Returns:
//   - Pointer-free display snapshot, or zero values for nil state.
//
// Notes:
//   - Missing point, particle, or Julia services leave their field groups zero.
//   - The source and all nested mutable services must be stable for the copy.
display :: proc(state: ^app_core.Euclid_General_State) -> Display {
    if state == nil {
        return {}
    }
    result := Display{
        fixed_step = state.fixed_step,
        simulation_time = state.simulation_time,
        simulation_paused = state.ui_runtime.simulation_paused,
        scratchpad_idle =
            state.ui_runtime.scratchpad_pending_submit_request_id == 0 &&
            state.ui_runtime.scratchpad_forced_bottom_request_id == 0,
        dynview_enabled = state.dynview.enabled,
        dynview_pending_invalidation_mask = state.dynview.pending_invalidation_mask,
        gif_capture_active = state.gif_capture.active,
        gif_capture_phase = state.ui_runtime.gif_capture_phase,
        gif_captured_frames = state.ui_runtime.gif_captured_frames,
        required_evidence_complete =
            state.evidence_session.required_evidence_complete &&
            evidence_trace.ring_evidence_complete(&state.evidence_ring),
        trace = trace_state(&state.evidence_ring),
    }
    if state.point_system != nil {
        result.point_count = state.point_system.next_point_index
        result.constraint_count = state.point_system.next_constraint_index
    }
    if state.particle_system != nil {
        result.particle_count = state.particle_system.next_index
    }
    observe_display_julia_service(state.julia_runtime_service, &result)
    return result
}

//   Copy Julia-host state at its owner or post-publication synchronization boundary.
//
// Parameters:
//   - service: Julia runtime service already stable for observation.
//
// Returns:
//   - Pointer-free host snapshot, or zero values for a nil service.
//
// Notes:
//   - This procedure does not inspect Julia objects or mutable request payloads.
julia_host :: proc(service: ^app_core.Julia_Runtime_Service) -> Julia_Host {
    if service == nil {
        return {}
    }
    return {
        lifecycle = service.lifecycle,
        runtime_generation = service.runtime_generation,
        active_request_id = service.active_request_id,
        active_request_kind = service.active_request_kind,
        failed_request_count = service.failed_request_count,
        request_saturation_count = service.request_saturation_count,
        animation_generation = service.animation_generation,
        animation_tick_sequence = service.animation_tick_sequence,
        animation_last_committed_sequence = service.animation_last_committed_sequence,
        animation_tick_pending = service.animation_tick_pending,
        animation_ticks_submitted = service.animation_ticks_submitted,
        animation_ticks_committed = service.animation_ticks_committed,
        animation_ticks_coalesced = service.animation_ticks_coalesced,
        animation_ticks_stale = service.animation_ticks_stale,
        animation_ticks_dropped = service.animation_ticks_dropped,
        trace = trace_state(&service.evidence_ring),
    }
}

//   Copy simulation producer rings after fixed-step and preparation joins.
//
// Parameters:
//   - executor: Simulation executor whose producer tasks have completed their joins.
//
// Returns:
//   - One pointer-free summary for each worker ring, or zero values for nil executor.
//
// Notes:
//   - Calling before all relevant task fences join would race producer-owned rings.
simulation :: proc(executor: ^app_core.Simulation_Executor) -> Simulation {
    if executor == nil {
        return {}
    }
    return {
        particle = trace_state(&executor.particle_task.evidence_ring),
        constraint = trace_state(&executor.constraint_task.evidence_ring),
        shape_cache = trace_state(&executor.shape_cache_task.evidence_ring),
        dynview = trace_state(&executor.dynview_task.evidence_ring),
    }
}

//   Copy one allocation domain at its owner-controlled synchronization point.
//
// Parameters:
//   - domain: Allocation domain to sample through its synchronized tracker.
//
// Returns:
//   - Consistent allocation counters, or zero values for an unavailable domain.
//
// Notes:
//   - Sampling uses the allocation domain's internal mutex and does not allocate.
allocation :: proc(domain: ^allocation_evidence.Domain) -> allocation_evidence.Snapshot {
    return allocation_evidence.domain_snapshot(domain)
}

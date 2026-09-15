package observe

import viewmodel "../../view/model"
import viewterminalmodel "../../view/terminal/model"

import bridgemodel "../../bridge/model"
import dynviewmodel "../../dynview/model"
import particlemodel "../../particles/model"
import shapemodel "../../shapes/model"

// Package observe copies bounded Euclid facts at explicit ownership boundaries.
//
// Observations are pointer-free values and do not retain source storage. This
// package does not establish synchronization: callers must already own the
// source or have completed the documented producer handoff or task join.

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
    animation_policy_paused : bool,

    // Julia runtime lifecycle, active request, and submission pressure.
    runtime_lifecycle : bridgemodel.Julia_Lifecycle_State,
    runtime_generation : u64,
    active_runtime_request_id : u64,
    failed_runtime_request_count : u64,
    runtime_request_saturation_count : u64,
    terminal_ready : bool,
    terminal_idle : bool,
    terminal_continuation : bool,

    // Terminal graphics transfer, publication, residency, and playback state.
    graphics_transfer_admission_count : u64,
    graphics_transfer_rejection_count : u64,
    graphics_decode_count : u64,
    graphics_failure_count : u64,
    graphics_cancellation_count : u64,
    graphics_publication_count : u64,
    graphics_stale_completion_count : u64,
    graphics_eviction_count : u64,
    graphics_draw_count : u64,
    graphics_draw_rejection_count : u64,
    graphics_cpu_byte_count : int,
    graphics_gpu_byte_count : int,
    graphics_animation_decode_byte_count : int,
    graphics_animated_attachment_count : int,
    graphics_animation_admission_count : u64,
    graphics_animation_rejection_count : u64,
    graphics_gif_preflight_acceptance_count : u64,
    graphics_gif_preflight_rejection_count : u64,
    graphics_queue_full_count : u64,
    graphics_playback_transition_count : u64,
    graphics_playback_completion_count : u64,
    graphics_playback_upload_failure_count : u64,
    graphics_playback_stale_count : u64,
    graphics_visibility_pause_count : u64,
    graphics_visibility_resume_count : u64,

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

    // Particle-owned dust settling and bounded contact diagnostics.
    dust_live_count : int,
    dust_airborne_count : int,
    dust_grounded_count : int,
    dust_peak_speed_sq : f32,
    dust_kinetic_measure : f32,
    dust_field_solve_node_count : int,
    dust_tool_contact_overflow_count : int,
    dust_tool_contact_coalesced_count : u64,
    dust_tool_contact_sample_count : u64,
    dust_tool_contact_field_node_visit_count : u64,
    dust_rendered_count : int,

    // Dynamic-view activation and pending invalidation work.
    dynview_enabled : bool,
    dynview_pending_invalidation_mask : u32,

    // Effective display-owned presentation viewport state.
    view_text_scroll_y : f32,
    view_text_scroll_max : f32,
    vertical_split_x : f32,
    horizontal_split_y : f32,

    // GIF capture lifecycle and completed frame count.
    gif_capture_active : bool,
    gif_capture_phase : viewmodel.Gif_Capture_Phase,
    gif_captured_frames : int,

    // Aggregate required-evidence health and display producer state.
    required_evidence_complete : bool,
    trace : Trace_State,
}

// Borrowed owner-model components used to assemble one display observation.
//
// Callers must keep every non-nil component stable for the duration of display.
Display_Source :: struct {
    fixed_step : u64,
    simulation_time : f32,
    ui_runtime : ^viewmodel.Euclid_Ui_Runtime_State,
    gif_capture : ^viewmodel.Gif_Capture_Session,
    terminal : ^viewterminalmodel.Terminal_State,
    dynview : ^dynviewmodel.Dynview_System,
    shape_world : ^shapemodel.Shape_World,
    particle_system : ^particlemodel.Particle_System,
    julia_service : ^bridgemodel.Julia_Runtime_Service,
    required_evidence_complete : bool,
    evidence_ring : ^evidence_trace.Ring,
}

// Pointer-free snapshot of state authoritative to the Julia host owner.
//
// Runtime fields describe serialized request processing. Animation counters
// distinguish submitted work from committed, coalesced, stale, and dropped
// outcomes without exposing the service's mutable queues.
Julia_Host :: struct {
    // Runtime lifecycle, active request identity, and submission outcomes.
    lifecycle : bridgemodel.Julia_Lifecycle_State,
    runtime_generation : u64,
    active_request_id : u64,
    active_request_kind : bridgemodel.Julia_Request_Kind,
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

// Borrowed producer rings made stable by simulation and preparation joins.
Simulation_Source :: struct {
    particle : ^evidence_trace.Ring,
    constraint : ^evidence_trace.Ring,
    shape_cache : ^evidence_trace.Ring,
    dynview : ^evidence_trace.Ring,
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
    service: ^bridgemodel.Julia_Runtime_Service, result: ^Display) {
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

//   Copy display-owned UI and capture state into an in-progress observation.
observe_display_ui :: proc(
    source: ^Display_Source, result: ^Display) {
    if source.ui_runtime != nil {
        result.simulation_paused = source.ui_runtime.simulation_paused
        result.animation_policy_paused = source.ui_runtime.animation_policy_paused
        result.view_text_scroll_y = source.ui_runtime.view_text_scroll_y
        result.view_text_scroll_max = source.ui_runtime.view_text_scroll_max
        result.vertical_split_x = source.ui_runtime.vertical_split_x
        result.horizontal_split_y = source.ui_runtime.horizontal_split_y
        result.gif_capture_phase = source.ui_runtime.gif_capture_phase
        result.gif_captured_frames = source.ui_runtime.gif_captured_frames
    }
    if source.gif_capture != nil {
        result.gif_capture_active = source.gif_capture.active
    }
}

// Copy synchronized particle diagnostics and classify current dust populations.
observe_display_particles :: proc(
    particles: ^particlemodel.Particle_System, result: ^Display) {
    if particles == nil {
        return
    }
    result.particle_count = particles.next_index
    result.dust_grounded_count = particles.dust_grounded_count
    result.dust_peak_speed_sq = particles.dust_peak_speed_sq
    result.dust_kinetic_measure = particles.dust_kinetic_measure
    bounds := particles.dust_field.previous_solve_bounds
    if bounds.valid {
        width := int(bounds.max_x - bounds.min_x + 1)
        height := int(bounds.max_y - bounds.min_y + 1)
        result.dust_field_solve_node_count = width * height
    }
    result.dust_tool_contact_overflow_count =
        particles.dust_tool_contact_overflow_count
    result.dust_tool_contact_coalesced_count =
        particles.dust_tool_contact_coalesced_count
    result.dust_tool_contact_sample_count = particles.dust_tool_contact_sample_count
    result.dust_tool_contact_field_node_visit_count =
        particles.dust_tool_contact_field_node_visit_count
    result.dust_rendered_count = particles.last_render_low
    for index in 0..<particles.use_max_dust_particles {
        if !particles.low_particles[index].alive {continue}
        result.dust_live_count += 1
        if particles.low_particles.pos_z[index] > 0 {
            result.dust_airborne_count += 1
        }
    }
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
//   - Missing shape, particle, or Julia services leave their field groups zero.
//   - The source and all nested mutable services must be stable for the copy.
display :: proc(source: ^Display_Source) -> Display {
    if source == nil {
        return {}
    }
    result := Display{
        fixed_step = source.fixed_step,
        simulation_time = source.simulation_time,
        required_evidence_complete = source.required_evidence_complete &&
            evidence_trace.ring_evidence_complete(source.evidence_ring),
        trace = trace_state(source.evidence_ring),
    }
    if source.terminal != nil {
        result.terminal_ready = source.terminal.initialized &&
            source.terminal.julia_session_ready
        result.terminal_idle = result.terminal_ready && !source.terminal.awaiting_eval
        result.terminal_continuation = result.terminal_ready &&
            source.terminal.collecting_continuation
    }
    if source.dynview != nil {
        result.dynview_enabled = source.dynview.enabled
        result.dynview_pending_invalidation_mask =
            source.dynview.pending_invalidation_mask
    }
    observe_display_ui(source, &result)
    if source.shape_world != nil {
        result.point_count = int(source.shape_world.transforms.count)
        result.constraint_count = int(source.shape_world.constraints.count)
    }
    observe_display_particles(source.particle_system, &result)
    observe_display_julia_service(source.julia_service, &result)
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
julia_host :: proc(service: ^bridgemodel.Julia_Runtime_Service) -> Julia_Host {
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
simulation :: proc(source: ^Simulation_Source) -> Simulation {
    if source == nil {
        return {}
    }
    return {
        particle = trace_state(source.particle),
        constraint = trace_state(source.constraint),
        shape_cache = trace_state(source.shape_cache),
        dynview = trace_state(source.dynview),
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

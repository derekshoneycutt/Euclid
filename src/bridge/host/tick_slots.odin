package julia_host

import bridge_scene "../scene"
import bridgemodel "../model"
import animationmodel "../../core/animation"
import capturemodel "../../view/capture/model"
import particles "../../particles"
import "../../core"
import evidence_session "../../evidence/session"
import evidence_trace "../../evidence/trace"
import "core:log"
import "core:time"

//   Preserve bounded elapsed time while one replaceable tick is in flight.
// The cap prevents a delayed worker from replaying an unbounded simulation interval when
// it next accepts a tick.
coalesce_animation_tick :: proc(
    service: ^Julia_Runtime_Service, dt, authored_dt: f32,
    accelerated: bool, step: u64 = 1) {
    retained_authored := min(
        authored_dt,
        max(0, MAX_ACCUMULATED_ANIMATION_DT -
            service^.animation_accumulated_authored_dt))
    if !append_animation_time_interval(
        service, step, service^.animation_generation, f64(retained_authored)) {
        service^.animation_time_backpressured = true
        log.errorf("animation_time_interval_capacity_exhausted generation=%d step=%d",
            service^.animation_generation, step)
    }
    service^.animation_accumulated_dt = min(
        service^.animation_accumulated_dt + dt, MAX_ACCUMULATED_ANIMATION_DT)
    service.animation_accumulated_authored_dt = min(
        service.animation_accumulated_authored_dt + authored_dt,
        MAX_ACCUMULATED_ANIMATION_DT)
    service.animation_accumulated_accelerated =
        service.animation_accumulated_accelerated || accelerated
    service^.animation_ticks_coalesced += 1
}

// Identify the current display step and the authored time admitted at its playback rate.
animation_step_time_interval :: proc(
    state: ^core.Euclid_General_State, service: ^Julia_Runtime_Service,
    authored_seconds: f64) -> particles.Formation_Time_Interval {
    return {
        step = state^.fixed_step + 1,
        generation = service^.animation_generation,
        authored_seconds = authored_seconds,
    }
}

// Append bounded authored time, merging repeated requests for the same display step.
append_animation_time_interval :: proc(
    service: ^Julia_Runtime_Service, step, generation: u64,
    authored_seconds: f64) -> bool {
    if authored_seconds <= 0 {
        return true
    }
    count := service^.animation_accumulated_interval_count
    if count > 0 {
        previous := &service^.animation_accumulated_intervals[count - 1]
        if previous.step == step && previous.generation == generation {
            previous.authored_seconds += authored_seconds
            return true
        }
    }
    if count >= len(service^.animation_accumulated_intervals) {
        return false
    }
    service^.animation_accumulated_intervals[count] = {
        step, generation, authored_seconds,
    }
    service^.animation_accumulated_interval_count += 1
    return true
}

//   Submit one fully prepared animation tick slot and finalize request bookkeeping.
submit_animation_tick_slot :: proc(
    service: ^Julia_Runtime_Service, slot: ^Animation_Tick_Slot,
    slot_index: int, total_dt: f32) -> bool {
    handle: bridgemodel.Animation_Tick_Slot_Handle = {
        index = i32(slot_index),
        reservation_generation = slot^.reservation_generation,
    }
    request_id, sent := try_submit_animation_tick(service, {
        handle = handle,
        animation_generation = slot^.generation,
        sequence = slot^.sequence,
    })
    if !sent {
        rollback_animation_tick_slot(service, slot, total_dt)
        return false
    }
    assert(slot^.request_id == request_id)
    service^.animation_tick_pending = true
    service^.animation_ticks_submitted += 1
    service^.animation_queue_high_water = max(
        service^.animation_queue_high_water, u64(1))
    return true
}

//   Submit one bounded animation tick without blocking the display thread.
// The display thread snapshots query state before submission. On saturation, the slot is
// recycled and elapsed time is retained for the next request instead of partially lost.
try_request_animation_tick :: proc(state: ^core.Euclid_General_State, dt: f32) -> bool {
    if state == nil || state^.julia_runtime_service == nil ||
        state^.julia_interface == nil {
        return false
    }
    service := state^.julia_runtime_service
    if service^.animation_time_backpressured {
        return false
    }
    rate := capturemodel.gif_capture_playback_rate(
        state.ui_runtime.playback.rate,
        state.gif_capture_status.gif_capture_phase,
        state.gif_capture_status.save_gif_requested)
    authored_dt := dt * animationmodel.playback_rate_multiplier(rate)
    if service^.animation_tick_pending {
        coalesce_animation_tick(
            service, dt, authored_dt, rate != .Normal, state^.fixed_step + 1)
        return false
    }
    slot_index := reserve_animation_tick_slot(service)
    if slot_index < 0 {
        coalesce_animation_tick(
            service, dt, authored_dt, rate != .Normal, state^.fixed_step + 1)
        return false
    }
    slot, total_dt := prepare_animation_tick_slot(
        state, slot_index, dt, authored_dt, rate != .Normal)
    if slot == nil {
        return false
    }
    return submit_animation_tick_slot(
        service, slot, slot_index, total_dt)
}

// Move accumulated timing into a reserved immutable slot before transport submission.
prepare_animation_tick_slot :: proc(
    state: ^core.Euclid_General_State, slot_index: int,
    dt, authored_dt: f32, accelerated: bool) -> (^Animation_Tick_Slot, f32) {
    service := state^.julia_runtime_service
    total_dt := min(dt + service^.animation_accumulated_dt, MAX_ACCUMULATED_ANIMATION_DT)
    total_authored_dt := min(authored_dt + service.animation_accumulated_authored_dt,
        MAX_ACCUMULATED_ANIMATION_DT)
    retained_current_authored := max(
        0, total_authored_dt - service.animation_accumulated_authored_dt)
    interval := animation_step_time_interval(
        state, service, f64(retained_current_authored))
    if !append_animation_time_interval(
        service, interval.step, interval.generation, interval.authored_seconds) {
        service^.animation_tick_slots[slot_index].state = .Free
        service^.animation_time_backpressured = true
        log.errorf("animation_time_interval_capacity_exhausted generation=%d step=%d",
            service^.animation_generation, state^.fixed_step + 1)
        return nil, 0
    }
    effective_accelerated := accelerated || service.animation_accumulated_accelerated
    service^.animation_accumulated_dt = 0
    service.animation_accumulated_authored_dt = 0
    service.animation_accumulated_accelerated = false
    service^.animation_tick_sequence += 1
    fill_animation_tick_slot(
        state, &service^.animation_tick_slots[slot_index],
        total_dt, total_authored_dt, effective_accelerated)
    slot := &service^.animation_tick_slots[slot_index]
    service^.animation_accumulated_interval_count = 0
    return slot, total_dt
}

// Copy the precise authored intervals into the immutable submitted tick slot.
copy_animation_intervals_to_slot :: proc(
    service: ^Julia_Runtime_Service, slot: ^Animation_Tick_Slot) {
    slot^.formation_interval_count = service^.animation_accumulated_interval_count
    for index in 0..<slot^.formation_interval_count {
        slot^.formation_intervals[index] =
            service^.animation_accumulated_intervals[index]
    }
}

//   Populate one animation tick slot and snapshot its query state for the request.
fill_animation_tick_slot :: proc(
    state: ^core.Euclid_General_State, slot: ^Animation_Tick_Slot,
    total_dt, authored_dt: f32, accelerated: bool) {
    service := state.julia_runtime_service
    reservation_generation := slot^.reservation_generation
    slot^ = Animation_Tick_Slot{
        state = .Pending,
        request_id = service^.next_request_id,
        reservation_generation = reservation_generation,
        generation = service^.animation_generation,
        sequence = service^.animation_tick_sequence,
        host_state = state,
        animation = state^.julia_interface^.current_animation,
        dt = authored_dt,
        maintenance_dt = total_dt,
        accelerated = accelerated,
        effective_progress = service^.animation_progress + f64(authored_dt),
        submitted_at = time.tick_now(),
    }
    bridge_scene.capture_animation_query_snapshot(state, &slot^.query_snapshot)
    copy_animation_intervals_to_slot(service, slot)
}

//   Recycle a tick slot and retain its elapsed time after a failed submission.
rollback_animation_tick_slot :: proc(
    service: ^Julia_Runtime_Service, slot: ^Animation_Tick_Slot, total_dt: f32) {

    slot^.state = .Free
    service^.animation_accumulated_dt = total_dt
    service.animation_accumulated_authored_dt = slot.dt
    service.animation_accumulated_accelerated = slot.accelerated
    for index in 0..<slot^.formation_interval_count {
        interval := slot^.formation_intervals[index]
        if !append_animation_time_interval(
            service, interval.step, interval.generation, interval.authored_seconds) {
            service^.animation_time_backpressured = true
            log.errorf("animation_time_interval_rollback_failed generation=%d step=%d",
                interval.generation, interval.step)
        }
    }
    service^.animation_ticks_dropped += 1
}

//   Commit one completed generation-matched animation batch at a frame boundary.
// Event draining updates service metadata, while completed slot storage remains authoritative.
// Every completed slot is recycled after selecting and attempting the newest valid batch.
publish_available_animation_tick :: proc(state: ^core.Euclid_General_State) -> bool {
    if state == nil || state^.julia_runtime_service == nil ||
        state^.julia_interface == nil {
        return false
    }
    service := state^.julia_runtime_service
    _ = drain_julia_egress(service)
    slot_index := newest_completed_animation_tick_index(service)
    if slot_index < 0 {
        return false
    }
    slot := &service^.animation_tick_slots[slot_index]
    matches_current := animation_tick_matches_current(state, service, slot)
    committed, reject_reason := commit_completed_animation_tick(
        state, service, slot, matches_current)
    if slot^.show_completed && matches_current {
        publish_animation_completion_state(state, slot, committed)
    }
    record_animation_tick_outcome(state, service, slot, committed, reject_reason)
    retire_superseded_animation_intervals(state, service, slot_index)
    release_completed_animation_ticks(service)
    service^.animation_tick_pending = false
    return committed
}

// Reconcile and commit one completed Julia result while retiring its overlap record.
commit_completed_animation_tick :: proc(
    state: ^core.Euclid_General_State, service: ^Julia_Runtime_Service,
    slot: ^Animation_Tick_Slot, matches_current: bool) -> (bool, string) {
    committed := false
    reject_reason := ""
    if !matches_current {
        reject_reason = animation_tick_reject_reason(state, service, slot)
    } else {
        progress, reconciled := particles.formation_reconcile_julia_intervals(
            &state^.particle_system, slot^.generation,
            slot^.formation_intervals[:slot^.formation_interval_count])
        if !reconciled {
            reject_reason = "formation_interval_reconciliation_failed"
        } else {
            slot^.scene_batch.formation_progress = progress
            slot^.scene_batch.formation_progress_set = true
            committed = bridge_scene.commit_scene_command_batch(
                state, &slot^.scene_batch)
            if committed {
                service^.animation_progress = slot^.effective_progress
                service^.animation_last_commit_accelerated = slot^.accelerated
            } else {
                reject_reason = "invalid_command_batch"
            }
        }
    }
    particles.formation_retire_native_intervals(
        &state^.particle_system, slot^.generation,
        slot^.formation_intervals[:slot^.formation_interval_count])
    return committed, reject_reason
}

// Retire interval coverage for accepted results superseded before publication.
retire_superseded_animation_intervals :: proc(
    state: ^core.Euclid_General_State,
    service: ^Julia_Runtime_Service, published_index: int) {
    for &completed, index in service^.animation_tick_slots {
        if index != published_index && completed.state == .Accepted {
            particles.formation_retire_native_intervals(
                &state^.particle_system, completed.generation,
                completed.formation_intervals[:completed.formation_interval_count])
        }
    }
}

// Resolve completion intent only for the current result and start its native arrival.
publish_animation_completion_state :: proc(
    state: ^core.Euclid_General_State, slot: ^Animation_Tick_Slot, committed: bool) {
    playback := &state^.ui_runtime.playback
    playback^.completion_requested = false
    playback^.completed = committed
    playback^.completion_failed = !committed
    if committed {
        playback^.completion_initial = false
        particles.begin_completed_arrival(&state^.particle_system)
    } else {
        log.errorf("animation_completed_publication_failed request_id=%d", slot^.request_id)
    }
}

//   Record the commit/reject bookkeeping and trace event for one completed tick.
record_animation_tick_outcome :: proc(
    state: ^core.Euclid_General_State, service: ^Julia_Runtime_Service,
    slot: ^Animation_Tick_Slot, committed: bool, reject_reason: string) {

    if committed {
        service^.animation_ticks_committed += 1
        service^.animation_last_committed_sequence = slot^.sequence
        latency_ms := time.duration_seconds(time.tick_since(slot^.submitted_at)) * 1000
        service^.animation_last_latency_ms = latency_ms
        service^.animation_max_latency_ms =
            max(service^.animation_max_latency_ms, latency_ms)
        kind := evidence_trace.Kind.Animation_Tick_Committed
        if slot^.show_completed {
            kind = .Animation_Completed_Committed
        }
        _ = evidence_session.session_record(
            &state^.evidence_session, &state^.evidence_ring, {
                lane = .Transport,
                kind = kind,
                correlation_kind = .Animation_Tick,
                correlation = slot^.sequence,
                generation = service^.animation_generation,
                tick = state^.fixed_step,
                flags = {.Required},
            })
        return
    }
    service^.animation_ticks_stale += 1
    kind := evidence_trace.Kind.Animation_Tick_Rejected
    if slot^.show_completed {
        kind = .Animation_Completed_Rejected
    }
    _ = evidence_session.session_record(
        &state^.evidence_session, &state^.evidence_ring, {
            lane = .Transport,
            kind = kind,
            correlation_kind = .Animation_Tick,
            correlation = slot^.sequence,
            generation = service^.animation_generation,
            tick = state^.fixed_step,
            flags = {.Failure},
        })
}

//   Classify why one completed tick was not committed against canonical state.
//
// Parameters:
//   - state: Global runtime state containing current animation selection.
//   - service: Julia runtime service with lifecycle counters.
//   - slot: Completed animation tick slot under evaluation.
//
// Returns:
//   - reason: Stable rejection reason token for trace payload.
animation_tick_reject_reason :: proc(
    state: ^core.Euclid_General_State,
    service: ^Julia_Runtime_Service,
    slot: ^Animation_Tick_Slot) -> string {

    if slot == nil || state == nil || state^.julia_interface == nil {
        return "invalid_command_batch"
    }
    if slot^.generation != service^.animation_generation {
        return "stale_generation"
    }
    if slot^.sequence <= service^.animation_last_committed_sequence {
        return "stale_sequence"
    }
    if state^.julia_interface^.pending_animation_reset {
        return "reset_pending"
    }
    if slot^.animation != state^.julia_interface^.current_animation ||
        slot^.animation != state^.julia_interface^.selected_animation {
        return "selection_mismatch"
    }
    return "invalid_command_batch"
}

//   Match one result against current lifecycle generation and selection identity.
// This prevents callbacks started before reset, reload, or selection changes from mutating
// the newly active canonical scene.
animation_tick_matches_current :: proc(
    state: ^core.Euclid_General_State,
    service: ^Julia_Runtime_Service,
    slot: ^Animation_Tick_Slot) -> bool {

    completion_current := !slot^.show_completed ||
        (state^.ui_runtime.playback.completion_requested &&
         state^.ui_runtime.playback.construction_paused)
    return completion_current &&
        slot^.generation == service^.animation_generation &&
        slot^.sequence > service^.animation_last_committed_sequence &&
        !state^.julia_interface^.pending_animation_reset &&
        slot^.animation == state^.julia_interface^.current_animation &&
        slot^.animation == state^.julia_interface^.selected_animation
}

//   Reserve free fixed storage for one worker-produced animation result.
// Slots are service-owned and recycled in place; no animation-tick allocation is permitted.
reserve_animation_tick_slot :: proc(service: ^Julia_Runtime_Service) -> int {
    for &slot, slot_index in service^.animation_tick_slots {
        if slot.state == .Free {
            slot.reservation_generation += 1
            if slot.reservation_generation == 0 {
                slot.reservation_generation = 1
            }
            return slot_index
        }
    }
    return -1
}

//   Find the newest accepted completion without relying on event payload retention.
// Older completed sequences may be superseded because only the latest canonical intent is
// useful at the next fixed-step publication boundary.
newest_completed_animation_tick_index :: proc(service: ^Julia_Runtime_Service) -> int {
    newest_index := -1
    newest_sequence: u64
    for &slot, slot_index in service^.animation_tick_slots {
        if slot.state == .Accepted && (newest_index < 0 ||
            slot.sequence > newest_sequence) {
            newest_index = slot_index
            newest_sequence = slot.sequence
        }
    }
    return newest_index
}

//   Release all consumed or superseded accepted animation slots.
// Pending slots remain worker-owned and must not be recycled by the display thread.
release_completed_animation_ticks :: proc(service: ^Julia_Runtime_Service) {
    for &slot in service^.animation_tick_slots {
        if slot.state == .Accepted {
            slot.state = .Free
        }
    }
}

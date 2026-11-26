package julia_host

import bridge_scene "../scene"
import bridgemodel "../model"
import core "../../core"
import audio "../../audio"
import modifier "../../animation"
import operations "../../animation/operations"
import math "core:math"
import shapemodel "../../shapes/model"

Active_Operation_Sample :: struct {
    request: modifier.Modifier_Request,
    group: operations.Active_Operation_Group_Transform,
    polygon: operations.Active_Operation_Polygon_Trace,
    consumer: operations.Active_Operation_Consumer,
    previous_elapsed: f64,
    current_elapsed: f64,
    interval_seconds: f64,
}

// Reserve, copy, and publish one modifier-backed operation at time zero.
active_operation_submit_modifier :: proc(
    state: ^core.Euclid_General_State,
    submission: operations.Active_Operation_Submission_Request) -> (
        operations.Active_Operation_Reservation,
        operations.Active_Operation_Status) {
    if state == nil || state^.scene_command_batch_target != nil {
        return {}, .Invalid_Argument
    }
    reservation, reserve_status := operations.active_operation_reserve_modifier(
        &state^.active_operations, submission)
    if reserve_status != .Ok {
        return {}, reserve_status
    }
    return active_operation_start_reserved_modifier(state, reservation, submission)
}

// Commit a reserved native operation's initial sample before making it live.
active_operation_start_reserved_modifier :: proc(
    state: ^core.Euclid_General_State,
    reservation: operations.Active_Operation_Reservation,
    submission: operations.Active_Operation_Submission_Request) -> (
        operations.Active_Operation_Reservation,
        operations.Active_Operation_Status) {
    if state == nil || state^.scene_command_batch_target != nil {
        return reservation, .Invalid_Argument
    }
    admission_status := active_operation_prepare_admission(state, reservation, submission)
    if admission_status != .Ok {
        return reservation, admission_status
    }
    if operations.active_operation_admit(
        &state^.active_operations, reservation.execution) != .Ok {
        assert(false)
        return reservation, .Invalid_Handle
    }
    if submission.modifier_request.duration <= 0 {
        _ = operations.active_operation_publish_outcome(
            &state^.active_operations, reservation.outcome, .Committed)
        _ = operations.active_operation_release_execution(
            &state^.active_operations, reservation.execution)
    }
    return reservation, .Ok
}

// Reject conflicts or commit the required time-zero sample before activation.
active_operation_prepare_admission :: proc(
    state: ^core.Euclid_General_State,
    reservation: operations.Active_Operation_Reservation,
    submission: operations.Active_Operation_Submission_Request) ->
        operations.Active_Operation_Status {
    claims := submission.claims
    if operations.active_operation_claims_conflict(
        &state^.active_operations,
        claims[:submission.claim_count], reservation.execution) {
        active_operation_reject_reservation(state, reservation)
        return .Conflict
    }
    initial := submission.modifier_request
    initial.elapsed = 0
    sample: Active_Operation_Sample = {
        request = initial,
        group = submission.group_transform,
        polygon = submission.polygon_trace,
        consumer = submission.consumer,
    }
    if !commit_active_operation_sample(state, submission.request_id, sample) {
        active_operation_reject_reservation(state, reservation)
        return .Admission_Rejected
    }
    return .Ok
}

// Preserve the failed correlation while rolling back its uncommitted execution slot.
active_operation_reject_reservation :: proc(
    state: ^core.Euclid_General_State,
    reservation: operations.Active_Operation_Reservation) {
    _ = operations.active_operation_publish_outcome(
        &state^.active_operations, reservation.outcome, .Rejected)
    _ = operations.active_operation_release_execution(
        &state^.active_operations, reservation.execution)
}

// Advance each eligible operation once in ascending stable slot order.
advance_active_operations :: proc(
    state: ^core.Euclid_General_State, dt: f32) {
    if state == nil || !state^.active_operations.initialized ||
        state^.scene_command_batch_target != nil || dt <= 0 ||
        math.is_nan(dt) || math.is_inf(dt) {
        return
    }
    for slot, index in state^.active_operations.execution_slots {
        if slot.state != .Live {
            continue
        }
        handle: operations.Active_Operation_Handle = {
            index = u16(index),
            generation = slot.generation,
        }
        advance_one_active_operation(state, handle, dt)
    }
}

// Preflight one candidate sample and accept its clock only after scene commit.
advance_one_active_operation :: proc(
    state: ^core.Euclid_General_State,
    handle: operations.Active_Operation_Handle, dt: f32) {
    progress, found := operations.active_operation_observe(
        &state^.active_operations, handle)
    if !found {
        return
    }
    request := progress.modifier_request
    candidate_elapsed := min(progress.elapsed + f64(dt), progress.duration)
    request.elapsed = f32(candidate_elapsed)
    if modifier.construction_recipe_kind(request.kind) {
        request.integer = modifier.construction_transition_flags(
            request.kind, progress.elapsed, candidate_elapsed, progress.duration)
    }
    control := state^.active_operations.control_slots[
        state^.active_operations.execution_slots[handle.index].control_index]
    producer_id := control.request_id
    sample: Active_Operation_Sample = {
        request = request,
        group = progress.group_transform,
        polygon = progress.polygon_trace,
        consumer = control.consumer,
        previous_elapsed = progress.elapsed,
        current_elapsed = candidate_elapsed,
        interval_seconds = f64(dt),
    }
    if !commit_active_operation_sample(state, producer_id, sample) {
        active_operation_finish(state, handle, .Rejected)
        return
    }
    status := operations.active_operation_accept_progress(
        &state^.active_operations, handle, candidate_elapsed)
    assert(status == .Ok)
    if candidate_elapsed >= progress.duration {
        active_operation_finish(state, handle, .Committed)
    }
}

// Commit one modifier sample through the shared native scene validator and applier.
commit_active_operation_sample :: proc(
    state: ^core.Euclid_General_State, producer_id: u64,
    sample: Active_Operation_Sample) -> bool {
    batch: bridge_scene.Scene_Command_Batch
    bridge_scene.begin_native_scene_command_batch(state, &batch, producer_id)
    defer bridge_scene.end_scene_command_batch(state)
    if sample.interval_seconds > 0 {
        batch.native_interval_step = state^.fixed_step + 1
        batch.native_interval_seconds = sample.interval_seconds
        batch.native_interval_set = true
        batch.native_interval_reconcile_julia =
            sample.consumer == .Julia
    }
    if !append_active_operation_sample_commands(state, sample) {
        return false
    }
    bridge_scene.end_scene_command_batch(state)
    return bridge_scene.commit_scene_command_batch(state, &batch)
}

// Expand group output into one preflighted scene batch before any target changes.
append_active_operation_sample_commands :: proc(
    state: ^core.Euclid_General_State, sample: Active_Operation_Sample) -> bool {
    if sample.polygon.count > 0 {
        return append_active_polygon_trace_sample(state, sample)
    }
    if sample.request.kind == .Cycloid_Sequence ||
        sample.request.kind == .Trochoid_Sequence {
        return append_active_rolling_sequence_samples(state, sample)
    }
    if sample.request.kind == .Parabola_Sequence ||
        sample.request.kind == .Hyperbola_Sequence {
        return append_active_conic_sequence_samples(state, sample)
    }
    REQUESTCAP :: operations.ACTIVE_OPERATION_GROUP_TARGET_CAPACITY + 1
    requests: [REQUESTCAP]modifier.Modifier_Request
    request_count := 1
    if sample.group.count > 0 {
        if !operations.active_operation_group_sample_requests(
            sample.group, sample.request, sample.request.elapsed,
            &requests, &request_count) {
            return false
        }
    } else {
        requests[0] = sample.request
    }
    for sample in requests[:request_count] {
        command, captured := bridge_scene.append_scene_command(
            state, .Apply_Native_Modifier)
        if !captured || command == nil {
            return false
        }
        command^.modifier = sample
    }
    return true
}

// Expand skipped conic phases and reveal the host when drawing begins.
append_active_conic_sequence_samples :: proc(
    state: ^core.Euclid_General_State, operation: Active_Operation_Sample) -> bool {
    samples := modifier.conic_sequence_samples(
        operation.request, f32(operation.previous_elapsed),
        f32(operation.current_elapsed))
    for sample in samples.requests[:samples.count] {
        command, captured := bridge_scene.append_scene_command(
            state, .Apply_Native_Modifier)
        if !captured || command == nil {
            return false
        }
        command^.modifier = sample
    }
    draw_start := f64(operation.request.duration) *
        modifier.CONIC_SEQUENCE_DESCEND_SHARE
    reveal_due := operation.previous_elapsed < draw_start &&
        operation.current_elapsed >= draw_start
    completion_due := operation.current_elapsed >= f64(operation.request.duration)
    if !reveal_due && !completion_due {
        return true
    }
    return append_active_conic_visibility(state, operation.request.entity)
}

// Reveal an analytic host in the current scene transaction.
append_active_conic_visibility :: proc(
    state: ^core.Euclid_General_State, entity: u64) -> bool {
    command, captured := bridge_scene.append_scene_command(state, .Set_Shape_Visible)
    if !captured || command == nil {
        return false
    }
    command^.entity = entity
    command^.flag = true
    return true
}

// Expand skipped rolling phases into ordered requests in the same scene transaction.
append_active_rolling_sequence_samples :: proc(
    state: ^core.Euclid_General_State, operation: Active_Operation_Sample) -> bool {
    samples := modifier.rolling_sequence_samples(
        operation.request, f32(operation.previous_elapsed),
        f32(operation.current_elapsed))
    for sample in samples.requests[:samples.count] {
        command, captured := bridge_scene.append_scene_command(
            state, .Apply_Native_Modifier)
        if !captured || command == nil {
            return false
        }
        command^.modifier = sample
    }
    return true
}

// Expand one polygon step and any crossed reveal/finalization intents atomically.
append_active_polygon_trace_sample :: proc(
    state: ^core.Euclid_General_State, operation: Active_Operation_Sample) -> bool {
    sample := modifier.polygon_trace_motion_request(
        operation.request, operation.polygon, operation.request.elapsed)
    command, captured := bridge_scene.append_scene_command(
        state, .Apply_Native_Modifier)
    if !captured || command == nil {
        return false
    }
    command^.modifier = sample
    if modifier.polygon_trace_reveal_due(
        operation.previous_elapsed, operation.current_elapsed,
        f64(operation.request.duration)) &&
        !append_active_polygon_reveal(state, operation.request) {
        return false
    }
    return operation.current_elapsed < f64(operation.request.duration) ||
        append_active_polygon_visibility(state, operation.request.entity)
}

// Capture the once-only region reveal alongside its crossing motion sample.
append_active_polygon_reveal :: proc(
    state: ^core.Euclid_General_State, request: modifier.Modifier_Request) -> bool {
    command, captured := bridge_scene.append_scene_command(state, .Reveal_Region)
    if !captured || command == nil {
        return false
    }
    command^.entity = request.entity
    command^.reveal = {
        kind = .Region,
        owner_entity = request.entity,
        duration = request.duration *
            f32(modifier.POLYGON_TRACE_REVEAL_SHARE),
    }
    return true
}

// Show the constructed polygon in the native sample that completes its pen rise.
append_active_polygon_visibility :: proc(
    state: ^core.Euclid_General_State, entity: u64) -> bool {
    command, captured := bridge_scene.append_scene_command(state, .Set_Shape_Visible)
    if !captured || command == nil {
        return false
    }
    command^.entity = entity
    command^.flag = true
    return true
}

// Publish one terminal result, clear its audio source, and release execution claims.
active_operation_finish :: proc(
    state: ^core.Euclid_General_State,
    handle: operations.Active_Operation_Handle,
    outcome: operations.Active_Operation_Outcome_State) {
    slot := operations.valid_execution_handle(&state^.active_operations, handle)
    if slot == nil {
        return
    }
    control := &state^.active_operations.control_slots[slot^.control_index]
    status := operations.active_operation_publish_outcome(
        &state^.active_operations, control^.outcome_handle, outcome)
    assert(status == .Ok)
    assert(audio.set_native_drawing_activity(
        &state^.chalk_audio, control^.request_id, false))
    assert(operations.active_operation_release_execution(
        &state^.active_operations, handle) == .Ok)
}

// Cancel one operation without discarding its correlated terminal result.
active_operation_cancel_on_display :: proc(
    state: ^core.Euclid_General_State,
    handle: operations.Active_Operation_Handle) -> operations.Active_Operation_Status {
    if state == nil {
        return .Invalid_Argument
    }
    slot := operations.valid_execution_handle(&state^.active_operations, handle)
    if slot == nil {
        return .Invalid_Handle
    }
    request_id := state^.active_operations.control_slots[slot^.control_index].request_id
    status := operations.active_operation_cancel(&state^.active_operations, handle)
    if status == .Ok {
        assert(audio.set_native_drawing_activity(
            &state^.chalk_audio, request_id, false))
    }
    return status
}

// Cancel every operation owned by one committed animation generation.
active_operation_retire_animation_generation :: proc(
    state: ^core.Euclid_General_State, animation_generation: u64) {
    if state == nil || animation_generation == 0 {
        return
    }
    for slot, index in state^.active_operations.execution_slots {
        if slot.state == .Free ||
            state^.active_operations.control_slots[slot.control_index].
                animation_generation != animation_generation {
            continue
        }
        _ = active_operation_cancel_on_display(state, {
            index = u16(index),
            generation = slot.generation,
        })
    }
}

// Cancel every operation owned by one Terminal session after its close commits.
active_operation_retire_session :: proc(
    state: ^core.Euclid_General_State, session_generation: u64) {
    if state == nil || session_generation == 0 {
        return
    }
    for slot, index in state^.active_operations.execution_slots {
        if slot.state == .Free ||
            state^.active_operations.control_slots[slot.control_index].
                session_generation != session_generation {
            continue
        }
        _ = active_operation_cancel_on_display(state, {
            index = u16(index),
            generation = slot.generation,
        })
    }
}

// Release only the outcome matching a complete consumer receipt identity.
active_operation_acknowledge_outcome :: proc(
    state: ^core.Euclid_General_State,
    identity: operations.Active_Operation_Outcome_Identity) -> i32 {
    if state == nil {
        return bridgemodel.BRIDGE_STATUS_ILLEGAL_STATE
    }
    context = state^.saved_context
    status := operations.active_operation_acknowledge_outcome_identity(
        &state^.active_operations, identity)
    #partial switch status {
    case .Ok, .Invalid_Handle:
        return bridgemodel.BRIDGE_STATUS_OK
    case .Invalid_Argument:
        return bridgemodel.BRIDGE_STATUS_INVALID_ARGUMENT
    }
    return bridgemodel.BRIDGE_STATUS_ILLEGAL_STATE
}

// Consume one Builder-owned result directly without entering Julia egress.
active_operation_consume_native_outcome :: proc(
    state: ^core.Euclid_General_State,
    handle: operations.Active_Operation_Outcome_Handle) -> (
        operations.Active_Operation_Outcome, operations.Active_Operation_Status) {
    if state == nil {
        return {}, .Invalid_Argument
    }
    return operations.active_operation_consume_native_outcome(
        &state^.active_operations, handle)
}

// Add deduplicated claims for the native joints moved by a construction recipe.
active_operation_add_construction_tool_claims :: proc(
    submission: ^operations.Active_Operation_Submission_Request,
    state: ^core.Euclid_General_State,
    kind: modifier.Modifier_Kind) -> bool {
    if submission == nil || state == nil {
        return false
    }
    if !modifier.construction_recipe_kind(kind) {
        return true
    }
    if kind == .Construct_Circle || kind == .Construct_Filled_Circle {
        return active_operation_add_request_claim(
                submission, shapemodel.shape_entity_pack(state^.world_compass.joint1)) &&
            active_operation_add_request_claim(
                submission, shapemodel.shape_entity_pack(state^.world_compass.joint2))
    }
    return active_operation_add_request_claim(
            submission, shapemodel.shape_entity_pack(state^.world_pen.joint1)) &&
        active_operation_add_request_claim(
            submission, shapemodel.shape_entity_pack(state^.world_pen.joint2))
}

// Add one nonzero entity claim without duplicating an existing identity.
active_operation_add_request_claim :: proc(
    submission: ^operations.Active_Operation_Submission_Request,
    entity: u64) -> bool {
    if submission == nil {
        return false
    }
    if entity == 0 {
        return true
    }
    for existing in 0..<submission^.claim_count {
        if submission^.claims[existing].identity == entity {
            return true
        }
    }
    if submission^.claim_count >= operations.ACTIVE_OPERATION_CLAIMS_PER_SLOT {
        return false
    }
    submission^.claims[submission^.claim_count] = {
        kind = operations.ACTIVE_OPERATION_CLAIM_ENTITY,
        identity = entity,
    }
    submission^.claim_count += 1
    return true
}

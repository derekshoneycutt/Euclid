package julia_host

import buildermodel "../../animation/builder"
import core "../../core"
import bridge_scene "../scene"
import bridgemodel "../model"
import color "../../core/color"
import geometry "../../core/geometry"
import operations "../../animation/operations"
import shapes "../../shapes"
import shapemodel "../../shapes/model"
import math "core:math"
import "core:log"

BUILDER_POINT_DURATION :: f32(5.5)
BUILDER_REQUEST_ID_PREFIX :: u64(1) << 63

Builder_Status :: enum u8 {
    Ok,
    Idle,
    Waiting,
    Retry,
    Invalid_Argument,
    Invalid_State,
    Queue_Full,
    Point_Capacity_Full,
    Stale_Identity,
    Point_Not_Found,
    Native_Failure,
    Failed,
    Retirement_Unsafe,
}

// Return the logical point, construction command, and admission outcome together.
Builder_Point_Enqueue_Result :: struct {
    point: buildermodel.Point_Identity,
    command: buildermodel.Command_Identity,
    status: Builder_Status,
}

// Begin one native Builder generation over the current shape-world prefix.
builder_begin :: proc(state: ^core.Euclid_General_State) -> Builder_Status {
    if state == nil || state^.builder.generation != 0 ||
        state^.scene_command_batch_target != nil {
        return .Invalid_State
    }
    if !shapemodel.shape_world_baseline_is_frozen(&state^.shape_world) &&
        (shapemodel.shape_world_has_frozen_baseline_storage(&state^.shape_world) ||
            shapemodel.shape_world_freeze_baseline(&state^.shape_world) != .Ok) {
        return .Invalid_State
    }
    state^.builder = {
        generation = 1,
        next_command_id = 1,
        next_point_id = 1,
        base_entity_count = state^.shape_world.registry.entity_count,
        color = buildermodel.BUILDER_DEFAULT_COLOR,
        brush_size = buildermodel.BUILDER_DEFAULT_BRUSH_SIZE,
        placement_status = .Ready,
    }
    return .Ok
}

// Queue one point with captured position and initial style.
builder_enqueue_point :: proc(
    state: ^core.Euclid_General_State, position: geometry.Vector3,
    initial_color: color.Color_RGBA8, brush_size: f32) -> Builder_Point_Enqueue_Result {
    if state == nil || !builder_vector_is_finite(position) ||
        !shapemodel.shape_scalar_is_finite(brush_size) || brush_size < 0 {
        return {{}, {}, .Invalid_Argument}
    }
    status := builder_point_enqueue_status(&state^.builder)
    if status != .Ok {
        return {{}, {}, status}
    }
    return builder_enqueue_point_job(state, position, initial_color, brush_size)
}

// Publish one preflighted logical point and its construction command atomically.
builder_enqueue_point_job :: proc(
    state: ^core.Euclid_General_State, position: geometry.Vector3,
    initial_color: color.Color_RGBA8, brush_size: f32) -> Builder_Point_Enqueue_Result {
    point_id: buildermodel.Point_Identity = {
        generation = state^.builder.generation,
        id = state^.builder.next_point_id,
    }
    record := &state^.builder.points[state^.builder.point_count]
    record^ = {
        identity = point_id,
        position = position,
        color = initial_color,
        brush_size = brush_size,
        state = .Pending,
    }
    state^.builder.point_count += 1
    state^.builder.next_point_id += 1
    job: buildermodel.Job = {
        kind = .Construct_Point,
        point = point_id,
        position = position,
        style = {
            color_set = true,
            color = initial_color,
            brush_set = true,
            brush_size = brush_size,
        },
    }
    command, enqueue_status := builder_enqueue_job(state, job)
    if enqueue_status != .Ok {
        state^.builder.points[state^.builder.point_count - 1] = {}
        state^.builder.point_count -= 1
        state^.builder.next_point_id -= 1
        return {{}, {}, enqueue_status}
    }
    return {point_id, command, .Ok}
}

// Preflight every bounded resource needed to admit a logical point.
builder_point_enqueue_status :: proc(
    runtime: ^buildermodel.Runtime) -> Builder_Status {
    if !builder_is_ready(runtime) {
        return .Invalid_State
    }
    if runtime^.failed {
        return .Failed
    }
    if runtime^.job_count >= buildermodel.BUILDER_JOB_CAPACITY {
        return .Queue_Full
    }
    if runtime^.point_count >= buildermodel.BUILDER_POINT_CAPACITY {
        return .Point_Capacity_Full
    }
    if runtime^.next_point_id >= BUILDER_REQUEST_ID_PREFIX ||
        runtime^.next_command_id >= BUILDER_REQUEST_ID_PREFIX {
        return .Invalid_State
    }
    return .Ok
}

// Queue a validated partial style update for a pending or ready logical point.
builder_enqueue_style :: proc(
    state: ^core.Euclid_General_State, point: buildermodel.Point_Identity,
    edit: buildermodel.Point_Style_Edit) -> (
        buildermodel.Command_Identity, Builder_Status) {
    if state == nil || (!edit.color_set && !edit.brush_set) ||
        (edit.brush_set && (!shapemodel.shape_scalar_is_finite(edit.brush_size) ||
            edit.brush_size < 0)) {
        return {}, .Invalid_Argument
    }
    record, status := builder_find_point(&state^.builder, point)
    if status != .Ok {
        return {}, status
    }
    if record^.state == .Failed {
        return {}, .Failed
    }
    job: buildermodel.Job = {
        kind = .Edit_Point_Style,
        point = point,
        style = edit,
    }
    identity, enqueue_status := builder_enqueue_job(state, job)
    return identity, enqueue_status
}

// Queue a visibility change without resolving a pending point to a native entity.
builder_enqueue_visibility :: proc(
    state: ^core.Euclid_General_State, point: buildermodel.Point_Identity,
    visible: bool) -> (buildermodel.Command_Identity, Builder_Status) {
    if state == nil {
        return {}, .Invalid_Argument
    }
    _, point_status := builder_find_point(&state^.builder, point)
    if point_status != .Ok {
        return {}, point_status
    }
    kind := buildermodel.Job_Kind.Hide_Point
    if visible {
        kind = .Show_Point
    }
    job: buildermodel.Job = {
        kind = kind,
        point = point,
    }
    identity, enqueue_status := builder_enqueue_job(state, job)
    return identity, enqueue_status
}

// Queue a hide command for one generation-qualified logical point.
builder_enqueue_hide :: proc(
    state: ^core.Euclid_General_State,
    point: buildermodel.Point_Identity) -> (
        buildermodel.Command_Identity, Builder_Status) {
    return builder_enqueue_visibility(state, point, false)
}

// Queue a show command for one generation-qualified logical point.
builder_enqueue_show :: proc(
    state: ^core.Euclid_General_State,
    point: buildermodel.Point_Identity) -> (
        buildermodel.Command_Identity, Builder_Status) {
    return builder_enqueue_visibility(state, point, true)
}

// Admit one command unless its generation has failed or bounded FIFO is full.
builder_enqueue_job :: proc(
    state: ^core.Euclid_General_State, job: buildermodel.Job) -> (
        buildermodel.Command_Identity, Builder_Status) {
    runtime := &state^.builder
    if !builder_is_ready(runtime) || runtime^.failed {
        return {}, .Failed
    }
    if runtime^.job_count >= buildermodel.BUILDER_JOB_CAPACITY {
        return {}, .Queue_Full
    }
    if runtime^.next_command_id == 0 ||
        runtime^.next_command_id >= BUILDER_REQUEST_ID_PREFIX {
        return {}, .Invalid_State
    }
    identity: buildermodel.Command_Identity = {
        generation = runtime^.generation,
        id = runtime^.next_command_id,
    }
    accepted_job := job
    accepted_job.identity = identity
    tail := (runtime^.job_head + runtime^.job_count) % buildermodel.BUILDER_JOB_CAPACITY
    runtime^.jobs[tail] = accepted_job
    runtime^.job_count += 1
    runtime^.next_command_id += 1
    return identity, .Ok
}

// Start or observe one FIFO head at a deterministic display fixed-step boundary.
builder_fixed_step :: proc(
    state: ^core.Euclid_General_State,
    allow_construction_start: bool) -> Builder_Status {
    if state == nil || state^.builder.generation == 0 {
        return .Idle
    }
    runtime := &state^.builder
    if runtime^.active_operation {
        return builder_collect_operation(state)
    }
    if runtime^.failed || runtime^.job_count == 0 {
        return .Idle
    }
    job := runtime^.jobs[runtime^.job_head]
    if job.kind == .Construct_Point {
        if !allow_construction_start {
            return .Waiting
        }
        return builder_start_point(state, job)
    }
    return builder_commit_edit(state, job)
}

// Reserve native operation storage before publishing the point entity.
builder_start_point :: proc(
    state: ^core.Euclid_General_State, job: buildermodel.Job) -> Builder_Status {
    record, point_status := builder_find_point(&state^.builder, job.point)
    if point_status != .Ok || record^.state != .Pending {
        return builder_fail_head(state, .Point_Not_Found)
    }
    predicted, can_append := shapemodel.shape_registry_next_entity(
        &state^.shape_world.registry)
    if !can_append || !builder_point_world_capacity_available(state) {
        return builder_fail_head(state, .Point_Capacity_Full)
    }
    submission := builder_point_submission(state, job, predicted)
    if submission.claim_count != 3 {
        return builder_fail_head(state, .Native_Failure)
    }
    reservation, reserve_status := operations.active_operation_reserve_modifier(
        &state^.active_operations, submission)
    if reserve_status != .Ok {
        return builder_handle_reservation_status(state, reserve_status)
    }
    return builder_publish_reserved_point(
        state, record, predicted, submission, reservation)
}

// Publish one point and activate its already-reserved native recipe.
builder_publish_reserved_point :: proc(
    state: ^core.Euclid_General_State, record: ^buildermodel.Point_Record,
    predicted: shapemodel.Shape_Entity,
    submission: operations.Active_Operation_Submission_Request,
    reservation: operations.Active_Operation_Reservation) -> Builder_Status {
    point, create_status := shapes.world_create_point(
        &state^.shape_world, record^.position, {
            color = record^.color,
            brush_size = record^.brush_size,
        })
    if create_status != .Ok || point.entity != predicted {
        active_operation_reject_reservation(state, reservation)
        if !builder_consume_native_outcome(state, reservation.outcome) {
            return builder_fail_head(state, .Native_Failure)
        }
        return builder_fail_head(state, .Native_Failure)
    }
    record^.entity = shapemodel.shape_entity_pack(point.entity)
    _, admission_status := active_operation_start_reserved_modifier(
        state, reservation, submission)
    if admission_status != .Ok {
        if !builder_remove_point_record_entity(state, record) {
            return builder_fail_head(state, .Native_Failure)
        }
        if !builder_consume_native_outcome(state, reservation.outcome) {
            return builder_fail_head(state, .Native_Failure)
        }
        return builder_fail_head(state, .Native_Failure)
    }
    record^.state = .Constructing
    record^.visible = true
    state^.builder.active_operation = true
    state^.builder.active_reservation = reservation
    return .Ok
}

// Build one native point recipe with unique Builder correlation and physical claims.
builder_point_submission :: proc(
    state: ^core.Euclid_General_State, job: buildermodel.Job,
    entity: shapemodel.Shape_Entity) -> operations.Active_Operation_Submission_Request {
    request_id := BUILDER_REQUEST_ID_PREFIX | job.identity.id
    submission: operations.Active_Operation_Submission_Request = {
        kind = operations.ACTIVE_OPERATION_KIND_MODIFIER,
        request_id = request_id,
        session_generation = state^.builder.generation,
        runtime_generation = state^.builder.generation,
        animation_generation = state^.particle_system.formation.animation_generation,
        consumer = .Native,
        modifier_request = {
            kind = .Construct_Point,
            entity = shapemodel.shape_entity_pack(entity),
            duration = BUILDER_POINT_DURATION,
            start_position = job.position,
            radius = f32(0.35),
            brush = job.style.brush_size,
            color_packed = builder_pack_color(job.style.color),
        },
    }
    submission.claim_count = 1
    submission.claims[0] = {
        kind = operations.ACTIVE_OPERATION_CLAIM_ENTITY,
        identity = shapemodel.shape_entity_pack(entity),
    }
    _ = active_operation_add_construction_tool_claims(
        &submission, state, .Construct_Point)
    return submission
}

// Apply one admitted point edit through the native scene transaction boundary.
builder_commit_edit :: proc(
    state: ^core.Euclid_General_State, job: buildermodel.Job) -> Builder_Status {
    record, point_status := builder_find_point(&state^.builder, job.point)
    if point_status != .Ok || record^.state != .Ready || record^.entity == 0 {
        return builder_fail_head(state, .Point_Not_Found)
    }
    batch: bridge_scene.Scene_Command_Batch
    bridge_scene.begin_native_scene_command_batch(
        state, &batch, builder_job_request_id(job.identity))
    edits_ok := builder_capture_job(state, job, record^.entity)
    bridge_scene.end_scene_command_batch(state)
    if !edits_ok || !bridge_scene.commit_scene_command_batch(state, &batch) {
        return builder_fail_head(state, .Native_Failure)
    }
    builder_apply_record_edit(record, job)
    builder_pop_head(&state^.builder)
    return .Ok
}

// Capture style or visibility changes without mutating canonical state early.
builder_capture_job :: proc(
    state: ^core.Euclid_General_State, job: buildermodel.Job,
    entity: u64) -> bool {
    #partial switch job.kind {
    case .Edit_Point_Style:
        return builder_capture_style(state, entity, job.style)
    case .Hide_Point:
        return bridge_scene.shape_set_visible(
            state, entity, 0) == bridgemodel.BRIDGE_STATUS_OK
    case .Show_Point:
        return bridge_scene.shape_set_visible(
            state, entity, 1) == bridgemodel.BRIDGE_STATUS_OK
    case .Construct_Point:
        return false
    }
    return false
}

// Capture only the requested fields of one point style edit.
builder_capture_style :: proc(
    state: ^core.Euclid_General_State, entity: u64,
    edit: buildermodel.Point_Style_Edit) -> bool {
    if edit.color_set && bridge_scene.shape_set_color(
        state, entity, edit.color) != bridgemodel.BRIDGE_STATUS_OK {
        return false
    }
    if edit.brush_set && bridge_scene.shape_set_brush_size(
        state, entity, edit.brush_size) != bridgemodel.BRIDGE_STATUS_OK {
        return false
    }
    return true
}

// Publish one committed style or visibility projection to its point record.
builder_apply_record_edit :: proc(
    record: ^buildermodel.Point_Record, job: buildermodel.Job) {
    #partial switch job.kind {
    case .Edit_Point_Style:
        if job.style.color_set {
            record^.color = job.style.color
        }
        if job.style.brush_set {
            record^.brush_size = job.style.brush_size
        }
    case .Hide_Point:
        record^.visible = false
    case .Show_Point:
        record^.visible = true
    case .Construct_Point:
    }
}

// Consume one direct result before allowing the queue head to advance.
builder_collect_operation :: proc(
    state: ^core.Euclid_General_State) -> Builder_Status {
    runtime := &state^.builder
    outcome, status := active_operation_consume_native_outcome(
        state, runtime^.active_reservation.outcome)
    if status == .Invalid_Argument {
        return .Waiting
    }
    if status != .Ok {
        return builder_fail_head(state, .Native_Failure)
    }
    runtime^.active_operation = false
    if outcome.state != .Committed {
        _ = builder_reset_pen_tool(state)
        return builder_fail_head(state, .Native_Failure)
    }
    record, point_status := builder_find_point(
        runtime, runtime^.jobs[runtime^.job_head].point)
    if point_status != .Ok {
        return builder_fail_head(state, .Native_Failure)
    }
    record^.state = .Ready
    builder_pop_head(runtime)
    return .Ok
}

// Keep later accepted commands but stop after one failed head and surface the error.
builder_fail_head :: proc(
    state: ^core.Euclid_General_State, failure: Builder_Status) -> Builder_Status {
    runtime := &state^.builder
    if runtime^.job_count > 0 {
        job := runtime^.jobs[runtime^.job_head]
        if job.kind == .Construct_Point {
            record, _ := builder_find_point(runtime, job.point)
            if record != nil {
                record^.state = .Failed
                _ = builder_remove_point_record_entity(state, record)
            }
        }
        log.errorf("builder_command_failed generation=%d command=%d status=%d",
            job.identity.generation, job.identity.id, failure)
        builder_pop_head(runtime)
    }
    runtime^.failed = true
    return failure
}

// Remove a partially constructed point only while it remains the latest entity.
builder_remove_point_record_entity :: proc(
    state: ^core.Euclid_General_State, record: ^buildermodel.Point_Record) -> bool {
    if record == nil || record^.entity == 0 {
        return true
    }
    entity := shapemodel.shape_entity_unpack(record^.entity)
    if shapemodel.shape_world_remove_last_point(&state^.shape_world, entity) != .Ok {
        log.errorf("builder_point_rollback_failed entity=%d generation=%d",
            record^.entity, state^.builder.generation)
        return false
    }
    record^.entity = 0
    return true
}

// Retry only capacity failures; every other reservation error is terminal for the FIFO.
builder_handle_reservation_status :: proc(
    state: ^core.Euclid_General_State,
    status: operations.Active_Operation_Status) -> Builder_Status {
    if status == .Execution_Full || status == .Payload_Full ||
        status == .Target_Full || status == .Claim_Full ||
        status == .Control_Full || status == .Outcome_Full {
        return .Retry
    }
    return builder_fail_head(state, .Native_Failure)
}

// Verify the fixed world stores can accept one standalone point.
builder_point_world_capacity_available :: proc(
    state: ^core.Euclid_General_State) -> bool {
    return shapemodel.shape_world_has_capacity(&state^.shape_world, {
        entities = 1,
        transforms = 1,
        render_styles = 1,
        geometries = 1,
    })
}

// Remove a committed FIFO head and preserve ring wraparound.
builder_pop_head :: proc(runtime: ^buildermodel.Runtime) {
    runtime^.jobs[runtime^.job_head] = {}
    runtime^.job_head = (runtime^.job_head + 1) % buildermodel.BUILDER_JOB_CAPACITY
    runtime^.job_count -= 1
}

// Resolve a generation-qualified point identity in the bounded record table.
builder_find_point :: proc(
    runtime: ^buildermodel.Runtime,
    identity: buildermodel.Point_Identity) -> (
        ^buildermodel.Point_Record, Builder_Status) {
    if runtime == nil || identity.generation == 0 || identity.id == 0 ||
        identity.generation != runtime^.generation {
        return nil, .Stale_Identity
    }
    for index := 0; index < runtime^.point_count; index += 1 {
        record := &runtime^.points[index]
        if record.identity.id == identity.id {
            return record, .Ok
        }
    }
    return nil, .Point_Not_Found
}

// Consume one rejected or rolled-back native result and report ownership failures.
builder_consume_native_outcome :: proc(
    state: ^core.Euclid_General_State,
    handle: operations.Active_Operation_Outcome_Handle) -> bool {
    _, status := active_operation_consume_native_outcome(state, handle)
    if status != .Ok {
        log.errorf("builder_outcome_consume_failed status=%d", status)
        return false
    }
    return true
}

// Retire one Builder generation only when its point suffix is exclusively owned.
builder_restart :: proc(state: ^core.Euclid_General_State) -> Builder_Status {
    if state == nil || state^.builder.generation == 0 ||
        state^.scene_command_batch_target != nil ||
        !builder_points_match_world_suffix(&state^.builder, &state^.shape_world) {
        return .Retirement_Unsafe
    }
    if state^.builder.generation == max(u64) {
        return .Invalid_State
    }
    if !builder_cancel_active_operation(state) {
        return .Native_Failure
    }
    if !builder_reset_pen_tool(state) {
        return .Native_Failure
    }
    for index := state^.builder.point_count - 1; index >= 0; index -= 1 {
        record := &state^.builder.points[index]
        if !builder_remove_point_record_entity(state, record) {
            return .Retirement_Unsafe
        }
    }
    generation := state^.builder.generation + 1
    state^.builder = {
        generation = generation,
        next_command_id = 1,
        next_point_id = 1,
        base_entity_count = state^.shape_world.registry.entity_count,
        color = buildermodel.BUILDER_DEFAULT_COLOR,
        brush_size = buildermodel.BUILDER_DEFAULT_BRUSH_SIZE,
        placement_status = .Ready,
    }
    return .Ok
}

// Forget Builder identities after the animation lifecycle rewinds the shape world.
builder_reset_after_animation_rewind :: proc(
    state: ^core.Euclid_General_State) -> bool {
    if state == nil || state^.builder.generation == 0 {
        return true
    }
    if state^.builder.active_operation ||
        state^.builder.generation == max(u64) {
        return false
    }
    generation := state^.builder.generation + 1
    state^.builder = {
        generation = generation,
        next_command_id = 1,
        next_point_id = 1,
        base_entity_count = state^.shape_world.registry.entity_count,
        color = buildermodel.BUILDER_DEFAULT_COLOR,
        brush_size = buildermodel.BUILDER_DEFAULT_BRUSH_SIZE,
        placement_status = .Ready,
    }
    return true
}

// Hide the shared construction pen and clear its transient active feature.
builder_reset_pen_tool :: proc(state: ^core.Euclid_General_State) -> bool {
    if state == nil || state^.scene_command_batch_target != nil {
        return false
    }
    pen := shapemodel.shape_entity_pack(state^.world_pen.shape)
    if pen == 0 {
        return true
    }
    batch: bridge_scene.Scene_Command_Batch
    bridge_scene.begin_native_scene_command_batch(
        state, &batch, BUILDER_REQUEST_ID_PREFIX)
    feature_status := bridge_scene.shape_set_active_feature(state, pen, 0)
    visible_status := bridge_scene.shape_set_visible(state, pen, 0)
    bridge_scene.end_scene_command_batch(state)
    if feature_status != bridgemodel.BRIDGE_STATUS_OK ||
        visible_status != bridgemodel.BRIDGE_STATUS_OK {
        log.errorf("builder_pen_cleanup_capture_failed feature=%d visible=%d",
            feature_status, visible_status)
        return false
    }
    if !bridge_scene.commit_scene_command_batch(state, &batch) {
        log.errorf("builder_pen_cleanup_commit_failed generation=%d",
            state^.builder.generation)
        return false
    }
    return true
}

// Cancel and consume the active native result before retiring any point owner.
builder_cancel_active_operation :: proc(
    state: ^core.Euclid_General_State) -> bool {
    runtime := &state^.builder
    if !runtime^.active_operation {
        return true
    }
    cancel_status := active_operation_cancel_on_display(
        state, runtime^.active_reservation.execution)
    if cancel_status != .Ok && cancel_status != .Invalid_Handle {
        log.errorf("builder_operation_cancel_failed status=%d", cancel_status)
        return false
    }
    _, status := active_operation_consume_native_outcome(
        state, runtime^.active_reservation.outcome)
    if status != .Ok {
        return false
    }
    runtime^.active_operation = false
    return true
}

// Verify that every point is the contiguous entity suffix owned by this generation.
builder_points_match_world_suffix :: proc(
    runtime: ^buildermodel.Runtime, world: ^shapemodel.Shape_World) -> bool {
    if runtime == nil || world == nil {
        return false
    }
    created: u32
    for record in runtime^.points[:runtime^.point_count] {
        if record.entity != 0 {
            created += 1
        }
    }
    if world.registry.entity_count != runtime^.base_entity_count + created {
        return false
    }
    expected := runtime^.base_entity_count
    for record in runtime^.points[:runtime^.point_count] {
        if record.entity == 0 {
            continue
        }
        expected += 1
        entity := shapemodel.shape_entity_unpack(record.entity)
        if entity.slot != expected ||
            !shapemodel.shape_registry_resolves(&world.registry, entity) {
            return false
        }
    }
    return true
}

// Validate a finite three-dimensional placement captured at admission.
builder_vector_is_finite :: proc(value: geometry.Vector3) -> bool {
    return !math.is_nan(value.x) && !math.is_inf(value.x) &&
        !math.is_nan(value.y) && !math.is_inf(value.y) &&
        !math.is_nan(value.z) && !math.is_inf(value.z)
}

// Ensure a runtime has a live generation and a still-available monotonic identity range.
builder_is_ready :: proc(runtime: ^buildermodel.Runtime) -> bool {
    return runtime != nil && runtime^.generation != 0 &&
        runtime^.next_command_id != 0 && runtime^.next_point_id != 0
}

// Reserve the high-bit request namespace for Builder operation identities.
builder_job_request_id :: proc(identity: buildermodel.Command_Identity) -> u64 {
    return BUILDER_REQUEST_ID_PREFIX | identity.id
}

// Pack the captured RGBA bytes using the native modifier color convention.
builder_pack_color :: proc(value: color.Color_RGBA8) -> u32 {
    return u32(value.r) | (u32(value.g) << 8) |
        (u32(value.b) << 16) | (u32(value.a) << 24)
}

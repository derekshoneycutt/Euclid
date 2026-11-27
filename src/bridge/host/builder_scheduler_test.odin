package julia_host

import buildermodel "../../animation/builder"
import bridge_scene "../scene"
import core "../../core"
import color "../../core/color"
import geometry "../../core/geometry"
import operations "../../animation/operations"
import particles "../../particles"
import modifier "../../animation"
import shapes "../../shapes"
import shapemodel "../../shapes/model"
import testing "core:testing"
import log "core:log"

// Keep a real pen and live formation generation in the frozen test baseline.
builder_test_state_create :: proc(t: ^testing.T) -> ^core.Euclid_General_State {
    state := active_operation_test_state()
    particles.formation_reset_generation(&state^.particle_system, 4)
    pen, status := shapes.world_create_pen(&state^.shape_world, {
        joint1 = {0.25, 0.3, 1.4},
        joint2 = {0.25, 0.3, 1.75},
        length = 0.35,
    })
    testing.expect_value(t, status, shapemodel.Shape_World_Status.Ok)
    state^.world_pen = pen
    testing.expect_value(t, builder_begin(state), Builder_Status.Ok)
    return state
}

// Cancel a live Builder recipe before releasing the owning test state.
builder_test_state_destroy :: proc(state: ^core.Euclid_General_State) {
    if state^.builder.generation != 0 {
        _ = builder_restart(state)
    }
    active_operation_test_destroy(state)
}

// Enqueue one point with stable test style and placement.
builder_test_enqueue_point :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State) ->
        buildermodel.Point_Identity {
    result := builder_enqueue_point(
        state, {0.25, 0.3, 0}, {12, 34, 56, 255}, 0.08)
    testing.expect_value(t, result.status, Builder_Status.Ok)
    return result.point
}

// Keep Builder point construction at Terminal's default full-sequence duration.
@(test)
builder_point_submission_uses_terminal_default_duration :: proc(t: ^testing.T) {
    state := builder_test_state_create(t)
    defer builder_test_state_destroy(state)
    job: buildermodel.Job = {
        kind = .Construct_Point,
        identity = {
            generation = 1,
            id = 1,
        },
        point = {
            generation = 1,
            id = 1,
        },
        position = {0.25, 0.3, 0},
        style = {
            color_set = true,
            color = {12, 34, 56, 255},
            brush_set = true,
            brush_size = 5,
        },
    }
    submission := builder_point_submission(state, job, {
        slot = 1,
        generation = 1,
    })
    testing.expect_value(t, submission.modifier_request.duration, f32(5.5))
}

// Advance one construction through the Terminal-default full pen duration.
builder_test_complete_head :: proc(t: ^testing.T, state: ^core.Euclid_General_State) {
    testing.expect_value(t, builder_fixed_step(state, true), Builder_Status.Ok)
    for _ in 0..<300 {
        state^.fixed_step += 1
        advance_active_operations(state, 0.02)
        status := builder_fixed_step(state, true)
        particles.update_particles(&state^.particle_system, 0.02)
        if !state^.builder.active_operation {
            testing.expect_value(t, status, Builder_Status.Ok)
            break
        }
    }
    record, _ := builder_find_point(
        &state^.builder, state^.builder.points[0].identity)
    testing.expect_value(t, record^.state, buildermodel.Point_State.Ready)
}

// Count the active head against all 32 bounded FIFO positions.
@(test)
builder_fifo_capacity_includes_active_construction :: proc(t: ^testing.T) {
    state := builder_test_state_create(t)
    defer builder_test_state_destroy(state)
    _ = builder_test_enqueue_point(t, state)
    testing.expect_value(t, builder_fixed_step(state, true), Builder_Status.Ok)
    for _ in 0 ..< buildermodel.BUILDER_JOB_CAPACITY - 1 {
        result := builder_enqueue_point(
            state, {0.3, 0.4, 0}, {1, 2, 3, 255}, 0.04)
        testing.expect_value(t, result.status, Builder_Status.Ok)
    }
    result := builder_enqueue_point(
        state, {0.4, 0.5, 0}, {1, 2, 3, 255}, 0.04)
    testing.expect_value(t, result.status, Builder_Status.Queue_Full)
    testing.expect_value(t, state^.builder.job_count, buildermodel.BUILDER_JOB_CAPACITY)
}

// Preserve command order and FIFO ring wraparound while reusing one ready point.
@(test)
builder_fifo_wraparound_preserves_visibility_order :: proc(t: ^testing.T) {
    state := builder_test_state_create(t)
    defer builder_test_state_destroy(state)
    point := builder_test_enqueue_point(t, state)
    builder_test_complete_head(t, state)
    for index in 0 ..< buildermodel.BUILDER_JOB_CAPACITY {
        _, status := builder_enqueue_visibility(state, point, index % 2 == 1)
        testing.expect_value(t, status, Builder_Status.Ok)
    }
    _, full_status := builder_enqueue_hide(state, point)
    testing.expect_value(t, full_status, Builder_Status.Queue_Full)
    for _ in 0 ..< buildermodel.BUILDER_JOB_CAPACITY / 2 {
        testing.expect_value(t, builder_fixed_step(state, true), Builder_Status.Ok)
    }
    for index in 0 ..< buildermodel.BUILDER_JOB_CAPACITY / 2 {
        _, status := builder_enqueue_visibility(state, point, index % 2 == 0)
        testing.expect_value(t, status, Builder_Status.Ok)
    }
    for _ in 0 ..< buildermodel.BUILDER_JOB_CAPACITY {
        testing.expect_value(t, builder_fixed_step(state, true), Builder_Status.Ok)
    }
    testing.expect(t, !state^.builder.points[0].visible)
}

// Position changes commit in order and preserve point identity and style.
@(test)
builder_move_commits_transactionally_in_fifo_order :: proc(t: ^testing.T) {
    state := builder_test_state_create(t)
    defer builder_test_state_destroy(state)
    point := builder_test_enqueue_point(t, state)
    builder_test_complete_head(t, state)
    record := &state^.builder.points[0]
    entity := record^.entity
    initial := record^.position
    target: geometry.Vector3 = {0.6, 0.7, 0}
    _, style_status := builder_enqueue_style(state, point, {
        color_set = true,
        color = {90, 80, 70, 255},
    })
    command, status := builder_enqueue_move(state, point, target)
    testing.expect_value(t, style_status, Builder_Status.Ok)
    testing.expect_value(t, status, Builder_Status.Ok)
    record^.preview_active = true
    record^.preview_position = target
    record^.preview_command = command
    testing.expect_value(t, builder_fixed_step(state, false), Builder_Status.Ok)
    testing.expect_value(t, record^.position, initial)
    testing.expect(t, record^.preview_active)
    testing.expect_value(t, builder_fixed_step(state, false), Builder_Status.Ok)
    testing.expect_value(t, record^.position, target)
    testing.expect_value(t, record^.identity, point)
    testing.expect_value(t, record^.entity, entity)
    testing.expect_value(t, record^.color, color.Color_RGBA8{90, 80, 70, 255})
    testing.expect(t, !record^.preview_active)
    transform, found := shapemodel.shape_component_get(
        &state^.shape_world.transforms, &state^.shape_world.registry,
        shapemodel.shape_entity_unpack(entity))
    testing.expect(t, found)
    testing.expect_value(t, transform.position, target)
    testing.expect_value(t, transform.previous_position, target)
    _, invalid := builder_enqueue_move(state, point, {2, 0, 0})
    testing.expect_value(t, invalid, Builder_Status.Invalid_Argument)
}

// An older committed move cannot retire a newer move's displayed preview.
@(test)
builder_move_preview_tracks_latest_admitted_command :: proc(t: ^testing.T) {
    state := builder_test_state_create(t)
    defer builder_test_state_destroy(state)
    point := builder_test_enqueue_point(t, state)
    builder_test_complete_head(t, state)
    first: geometry.Vector3 = {0.4, 0.4, 0}
    second: geometry.Vector3 = {0.6, 0.6, 0}
    _, first_status := builder_enqueue_move(state, point, first)
    command, second_status := builder_enqueue_move(state, point, second)
    testing.expect_value(t, first_status, Builder_Status.Ok)
    testing.expect_value(t, second_status, Builder_Status.Ok)
    record := &state^.builder.points[0]
    record^.preview_active = true
    record^.preview_position = second
    record^.preview_command = command
    testing.expect_value(t, builder_fixed_step(state, false), Builder_Status.Ok)
    testing.expect_value(t, record^.position, first)
    testing.expect(t, record^.preview_active)
    testing.expect_value(t, record^.preview_position, second)
    testing.expect_value(t, builder_fixed_step(state, false), Builder_Status.Ok)
    testing.expect_value(t, record^.position, second)
    testing.expect(t, !record^.preview_active)
}

// Stress native-only Builder edits beyond interval-ledger capacity without Julia ticks.
@(test)
builder_native_only_steps_exceed_formation_ledger_without_tick_requests :: proc(
    t: ^testing.T) {
    state := builder_test_state_create(t)
    defer builder_test_state_destroy(state)
    point := builder_test_enqueue_point(t, state)
    builder_test_complete_head(t, state)
    service := new(Julia_Runtime_Service, context.allocator)
    state^.julia_runtime_service = service
    defer free(service, context.allocator)
    defer state^.julia_runtime_service = nil
    service^.animation_tick_sequence = 257
    before_tick_sequence := service^.animation_tick_sequence
    for index in 0..<300 {
        color: color.Color_RGBA8 = {u8(index % 255), 20, 30, 255}
        _, enqueue_status := builder_enqueue_style(state, point, {
            color_set = true,
            color = color,
        })
        testing.expect_value(t, enqueue_status, Builder_Status.Ok)
        testing.expect_value(t, builder_fixed_step(state, false), Builder_Status.Ok)
        testing.expect_value(t, state^.builder.job_count, 0)
    }
    testing.expect_value(t, service^.animation_tick_sequence, before_tick_sequence)
    diagnostics := operations.active_operation_storage_diagnostics(
        &state^.active_operations)
    testing.expect_value(t, diagnostics.execution_live, 0)
    testing.expect_value(t, diagnostics.execution_reserved, 0)
    testing.expect_value(t, diagnostics.outcome_used, 0)
    testing.expect_value(t, diagnostics.payload_used, 0)
    testing.expect_value(t, diagnostics.claim_used, 0)
}

// Resolve edits accepted against a pending point after its native recipe commits.
@(test)
builder_pending_point_edits_commit_in_fifo_order :: proc(t: ^testing.T) {
    state := builder_test_state_create(t)
    defer builder_test_state_destroy(state)
    initial: color.Color_RGBA8 = {12, 34, 56, 255}
    changed: color.Color_RGBA8 = {90, 80, 70, 255}
    point_result := builder_enqueue_point(state, {0.25, 0.3, 0}, initial, 0.08)
    point := point_result.point
    _, style_status := builder_enqueue_style(state, point, {
        color_set = true,
        color = changed,
    })
    _, hide_status := builder_enqueue_hide(state, point)
    _, show_status := builder_enqueue_show(state, point)
    testing.expect_value(t, style_status, Builder_Status.Ok)
    testing.expect_value(t, hide_status, Builder_Status.Ok)
    testing.expect_value(t, show_status, Builder_Status.Ok)
    builder_test_complete_head(t, state)
    testing.expect_value(t, builder_fixed_step(state, true), Builder_Status.Ok)
    testing.expect_value(t, state^.builder.points[0].color, changed)
    testing.expect_value(t, state^.builder.points[0].brush_size, f32(0.08))
    view := bridge_scene.shape_get_view(state, state^.builder.points[0].entity)
    testing.expect_value(t, view.color, changed)
    testing.expect_value(t, view.brush_size, f32(0.08))
    testing.expect_value(t, builder_fixed_step(state, true), Builder_Status.Ok)
    testing.expect(t, !state^.builder.points[0].visible)
    testing.expect_value(t, bridge_scene.shape_get_view(
        state, state^.builder.points[0].entity).visible, u8(0))
    testing.expect_value(t, builder_fixed_step(state, true), Builder_Status.Ok)
    testing.expect(t, state^.builder.points[0].visible)
    testing.expect_value(t, bridge_scene.shape_get_view(
        state, state^.builder.points[0].entity).visible, u8(1))
}

// Retain the pending head and avoid point publication while operation slots are full.
@(test)
builder_retries_native_slot_pressure_without_leaking_point :: proc(t: ^testing.T) {
    state := active_operation_test_state()
    defer active_operation_test_destroy(state)
    particles.formation_reset_generation(&state^.particle_system, 4)
    RESERVATION_COUNT :: operations.ACTIVE_OPERATION_SLOT_COUNT
    reservations: [RESERVATION_COUNT]operations.Active_Operation_Reservation
    for index in 0..<operations.ACTIVE_OPERATION_SLOT_COUNT {
        host := bridge_scene.shape_create_point(
            state, bridge_shape_test_input({f32(index), 0, 0}))
        request: modifier.Modifier_Request = {
            kind = .Set_Point_Position,
            entity = host.entity,
            duration = 1,
            displacement = {0.01, 0, 0},
        }
        submission := active_operation_test_submission(
            u64(index + 100), request, active_operation_test_claim(host.entity))
        submission.consumer = .Native
        reservation, status := active_operation_submit_modifier(state, submission)
        testing.expect_value(t, status, operations.Active_Operation_Status.Ok)
        reservations[index] = reservation
    }
    pen, pen_status := shapes.world_create_pen(&state^.shape_world, {
        joint1 = {0.25, 0.3, 1.4},
        joint2 = {0.25, 0.3, 1.75},
        length = 0.35,
    })
    testing.expect_value(t, pen_status, shapemodel.Shape_World_Status.Ok)
    state^.world_pen = pen
    testing.expect_value(t, builder_begin(state), Builder_Status.Ok)
    point := builder_test_enqueue_point(t, state)
    testing.expect_value(t, builder_fixed_step(state, true), Builder_Status.Retry)
    record, _ := builder_find_point(&state^.builder, point)
    testing.expect_value(t, record^.entity, u64(0))
    testing.expect_value(t, state^.builder.job_count, 1)
    for reservation in reservations {
        testing.expect_value(t, active_operation_cancel_on_display(
            state, reservation.execution), operations.Active_Operation_Status.Ok)
        _, status := active_operation_consume_native_outcome(
            state, reservation.outcome)
        testing.expect_value(t, status, operations.Active_Operation_Status.Ok)
    }
    testing.expect_value(t, builder_fixed_step(state, true), Builder_Status.Ok)
    testing.expect_value(t, builder_restart(state), Builder_Status.Ok)
}

// Roll back rejected initial admission, stop later work, and reject active-only identities.
@(test)
builder_rejected_admission_rolls_back_and_stops_fifo :: proc(t: ^testing.T) {
    previous_logger := context.logger
    context.logger = log.nil_logger()
    defer context.logger = previous_logger
    state := builder_test_state_create(t)
    defer builder_test_state_destroy(state)
    joint := shapemodel.shape_entity_pack(state^.world_pen.joint1)
    request: modifier.Modifier_Request = {
        kind = .Set_Point_Position,
        entity = joint,
        duration = 1,
        displacement = {0.01, 0, 0},
    }
    submission := active_operation_test_submission(
        600, request, active_operation_test_claim(joint))
    competing, admission_status := active_operation_submit_modifier(state, submission)
    testing.expect_value(t, admission_status, operations.Active_Operation_Status.Ok)
    point := builder_test_enqueue_point(t, state)
    _, queued_status := builder_enqueue_hide(state, point)
    testing.expect_value(t, queued_status, Builder_Status.Ok)
    base_count := state^.builder.base_entity_count
    testing.expect_value(t,
        builder_fixed_step(state, true), Builder_Status.Native_Failure)
    record, _ := builder_find_point(&state^.builder, point)
    testing.expect_value(t, record^.state, buildermodel.Point_State.Failed)
    testing.expect_value(t, record^.entity, u64(0))
    testing.expect_value(t, state^.shape_world.registry.entity_count, base_count)
    testing.expect(t, state^.builder.failed)
    testing.expect_value(t, state^.builder.job_count, 1)
    point_count := state^.builder.point_count
    result := builder_enqueue_point(
        state, {0.6, 0.6, 0}, {1, 2, 3, 255}, 0.04)
    testing.expect_value(t, result.status, Builder_Status.Failed)
    testing.expect_value(t, state^.builder.point_count, point_count)
    _, stale_status := builder_enqueue_hide(state, {point.generation, point.id + 99})
    testing.expect_value(t, stale_status, Builder_Status.Point_Not_Found)
    testing.expect_value(t, active_operation_cancel_on_display(
        state, competing.execution), operations.Active_Operation_Status.Ok)
}

// Stop on cancellation, preserve later accepted work, and retire generation-owned points.
@(test)
builder_failure_stop_and_restart_retire_points :: proc(t: ^testing.T) {
    previous_logger := context.logger
    context.logger = log.nil_logger()
    defer context.logger = previous_logger
    state := builder_test_state_create(t)
    defer builder_test_state_destroy(state)
    point := builder_test_enqueue_point(t, state)
    _, queued_status := builder_enqueue_hide(state, point)
    testing.expect_value(t, queued_status, Builder_Status.Ok)
    testing.expect_value(t, builder_fixed_step(state, true), Builder_Status.Ok)
    reservation := state^.builder.active_reservation
    testing.expect_value(t, active_operation_cancel_on_display(
        state, reservation.execution), operations.Active_Operation_Status.Ok)
    testing.expect_value(t,
        builder_fixed_step(state, true), Builder_Status.Native_Failure)
    record, _ := builder_find_point(&state^.builder, point)
    testing.expect_value(t, record^.state, buildermodel.Point_State.Failed)
    pen := shapemodel.shape_entity_pack(state^.world_pen.shape)
    testing.expect_value(t, bridge_scene.shape_get_view(state, pen).visible, u8(0))
    testing.expect_value(t, state^.builder.job_count, 1)
    generation := state^.builder.generation
    testing.expect_value(t, builder_restart(state), Builder_Status.Ok)
    testing.expect_value(t, state^.builder.generation, generation + 1)
    _, stale_status := builder_enqueue_hide(state, point)
    testing.expect_value(t, stale_status, Builder_Status.Stale_Identity)
    testing.expect_value(t, state^.shape_world.registry.entity_count,
        state^.builder.base_entity_count)
}

// Cancel an active native recipe and remove its owned point during explicit restart.
@(test)
builder_restart_cancels_active_recipe_and_cleans_entities :: proc(t: ^testing.T) {
    state := builder_test_state_create(t)
    defer builder_test_state_destroy(state)
    _ = builder_test_enqueue_point(t, state)
    testing.expect_value(t, builder_fixed_step(state, true), Builder_Status.Ok)
    pen := shapemodel.shape_entity_pack(state^.world_pen.shape)
    testing.expect_value(t, bridge_scene.shape_get_view(state, pen).visible, u8(1))
    entity_count := state^.shape_world.registry.entity_count
    testing.expect_value(t, builder_restart(state), Builder_Status.Ok)
    testing.expect_value(t, state^.shape_world.registry.entity_count,
        entity_count - 1)
    pen_view := bridge_scene.shape_get_view(state, pen)
    testing.expect_value(t, pen_view.visible, u8(0))
    testing.expect_value(t, pen_view.active_feature, u16(0))
    testing.expect(t, !state^.builder.active_operation)
    diagnostics := operations.active_operation_storage_diagnostics(
    &state^.active_operations)
    testing.expect_value(t, diagnostics.execution_live, 0)
    testing.expect_value(t, diagnostics.execution_reserved, 0)
    testing.expect_value(t, diagnostics.outcome_used, 0)
    testing.expect_value(t, diagnostics.payload_used, 0)
    testing.expect_value(t, diagnostics.claim_used, 0)
}

// Retire active and queued work on departure and keep reentry free of late geometry.
@(test)
builder_departure_and_reentry_leave_no_late_geometry :: proc(t: ^testing.T) {
    state := builder_test_state_create(t)
    defer builder_test_state_destroy(state)
    _ = builder_test_enqueue_point(t, state)
    _ = builder_test_enqueue_point(t, state)
    testing.expect_value(t, builder_fixed_step(state, true), Builder_Status.Ok)
    testing.expect_value(t, state^.builder.job_count, 2)
    for _ in 0..<300 {
        state^.fixed_step += 1
        advance_active_operations(state, 0.02)
        _ = builder_fixed_step(state, false)
        particles.update_particles(&state^.particle_system, 0.02)
        if !state^.builder.active_operation {
            break
        }
    }
    testing.expect(t, !state^.builder.active_operation)
    testing.expect_value(t, state^.builder.points[0].state,
        buildermodel.Point_State.Ready)
    testing.expect_value(t, state^.builder.job_count, 1)
    testing.expect_value(t, builder_restart(state), Builder_Status.Ok)
    testing.expect(t, builder_reset_after_animation_rewind(state))
    testing.expect_value(t, state^.builder.point_count, 0)
    testing.expect_value(t, state^.builder.job_count, 0)
    entity_count := state^.shape_world.registry.entity_count
    testing.expect_value(t, builder_fixed_step(state, true), Builder_Status.Idle)
    testing.expect_value(t, state^.shape_world.registry.entity_count, entity_count)
    reentry := builder_test_enqueue_point(t, state)
    testing.expect_value(t, reentry.generation, state^.builder.generation)
}

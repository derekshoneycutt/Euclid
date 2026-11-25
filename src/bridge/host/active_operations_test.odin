package julia_host

import bridge_scene "../scene"
import bridgemodel "../model"
import core "../../core"
import bridge_animation "../animation"
import audio "../../audio"
import modifier "../../animation"
import operations "../../operations"
import particles "../../particles"
import geometry "../../core/geometry"
import shapes "../../shapes"
import shapemodel "../../shapes/model"
import transport "../transport"
import math "core:math"
import testing "core:testing"

// Keep native outcomes and exact receipts safe for their Julia isbits transfers.
@(test)
active_operation_outcome_abi_layouts_match_fixed_field_widths :: proc(
    t: ^testing.T) {
    testing.expect_value(
        t, size_of(operations.Active_Operation_Outcome_Identity), 40)
    testing.expect_value(
        t, size_of(Bridge_Active_Group_Transform_Target), 24)
    testing.expect_value(
        t, size_of(Bridge_Active_Group_Transform_Request), 568)
    testing.expect_value(
        t, size_of(Bridge_Active_Polygon_Trace_Target), 24)
    testing.expect_value(
        t, size_of(Bridge_Active_Polygon_Trace_Request), 272)
    testing.expect_value(t,
        size_of(bridgemodel.Active_Operation_Outcome_Ready), 48)
    testing.expect_value(t,
        size_of(bridgemodel.Active_Operation_Progress_Ready), 48)
}

// Keep native construction conflicts attached to the physical tool joints.
@(test)
active_construction_claims_resolve_pen_and_compass_joints :: proc(t: ^testing.T) {
    state := active_operation_test_state()
    defer active_operation_test_destroy(state)
    pen, pen_status := shapes.world_create_pen(&state^.shape_world, {
        joint1 = {0.25, 0.3, 1.4},
        joint2 = {0.25, 0.3, 1.75},
        length = 0.35,
    })
    compass, compass_status := shapes.world_create_compass(&state^.shape_world, {
        joint1 = {0.5, 0.5, 0},
        joint2 = {0.7, 0.5, 0},
        limb_length = 0.2,
    })
    testing.expect_value(t, pen_status, shapemodel.Shape_World_Status.Ok)
    testing.expect_value(t, compass_status, shapemodel.Shape_World_Status.Ok)
    state^.world_pen = pen
    state^.world_compass = compass
    pen_submission: operations.Active_Operation_Submission_Request
    testing.expect(t, active_operation_add_construction_tool_claims(
        &pen_submission, state, .Construct_Point))
    testing.expect_value(t, pen_submission.claim_count, 2)
    testing.expect_value(t, pen_submission.claims[0].identity,
        shapemodel.shape_entity_pack(pen.joint1))
    testing.expect_value(t, pen_submission.claims[1].identity,
        shapemodel.shape_entity_pack(pen.joint2))
    pen_motion: modifier.Modifier_Request = {
        kind = .Pen_Descend,
        second_entity = 1,
    }
    testing.expect(t, bridge_scene.scene_active_operation_claim_matches_modifier(
        state, pen_submission.claims[:pen_submission.claim_count], pen_motion))
    compass_submission: operations.Active_Operation_Submission_Request
    testing.expect(t, active_operation_add_construction_tool_claims(
        &compass_submission, state, .Construct_Circle))
    testing.expect_value(t, compass_submission.claim_count, 2)
    testing.expect_value(t, compass_submission.claims[0].identity,
        shapemodel.shape_entity_pack(compass.joint1))
    testing.expect_value(t, compass_submission.claims[1].identity,
        shapemodel.shape_entity_pack(compass.joint2))
    compass_motion: modifier.Modifier_Request = {
        kind = .Compass_Descend,
        entity = 2,
        second_entity = 3,
    }
    testing.expect(t, bridge_scene.scene_active_operation_claim_matches_modifier(
        state, compass_submission.claims[:compass_submission.claim_count],
        compass_motion))
}

// Prove admission samples immediately and fixed steps commit the final modifier pose.
@(test)
active_modifier_operation_progresses_and_delivers_correlated_completion :: proc(
    t: ^testing.T) {
    state := active_operation_test_state()
    defer active_operation_test_destroy(state)
    point := bridge_scene.shape_create_point(
        state, bridge_shape_test_input({0, 0, 0}))
    claim := active_operation_test_claim(point.entity)
    request: modifier.Modifier_Request = {
        kind = .Set_Point_Position,
        entity = point.entity,
        duration = 1,
        displacement = {1, 0, 0},
    }
    submission := active_operation_test_submission(51, request, claim)
    reservation, status := active_operation_submit_modifier(state, submission)
    testing.expect_value(t, status, operations.Active_Operation_Status.Ok)
    testing.expect_value(t, bridge_scene.shape_get_view(
        state, point.entity).position.x, f32(0))
    advance_active_operations(state, 0.4)
    testing.expect(t, math.abs(bridge_scene.shape_get_view(
        state, point.entity).position.x - f32(0.4)) < f32(1e-6))
    testing.expect(t, math.abs(
        state^.particle_system.formation.accepted_progress - f64(0.4)) < f64(1e-6))
    state^.fixed_step += 1
    advance_active_operations(state, 0.6)
    testing.expect_value(t, bridge_scene.shape_get_view(
        state, point.entity).position.x, f32(1))
    testing.expect(t, math.abs(
        state^.particle_system.formation.accepted_progress - f64(1)) < f64(1e-6))
    reused := active_operation_test_immediate_reuse(t, state, point.entity, claim)
    testing.expect(t, reused.execution.index == reservation.execution.index)
    testing.expect(t, reused.execution.generation != reservation.execution.generation)
    active_operation_test_expect_outcome(
        t, state, reservation.outcome, .Committed)
    active_operation_test_expect_outcome(t, state, reused.outcome, .Committed)
}

// Advance a point recipe across fixed steps and release its claims on completion.
@(test)
active_point_recipe_advances_transactionally_and_completes :: proc(t: ^testing.T) {
    state := active_operation_test_state()
    defer active_operation_test_destroy(state)
    point, reservation := active_recipe_test_submit_point(t, state, 101)
    deltas: [3]f32 = {0.2, 0.4, 0.4}
    for dt in deltas {
        state^.fixed_step += 1
        advance_active_operations(state, dt)
    }
    view := bridge_scene.shape_get_view(state, point)
    testing.expect(t, view.visible != 0)
    testing.expect_value(t, view.position, geometry.Vector3{0.25, 0.3, 0})
    tool, found := shapemodel.shape_component_get(
        &state^.shape_world.active_features, &state^.shape_world.registry,
        state^.world_pen.shape)
    testing.expect(t, found)
    testing.expect_value(t, tool.index, u16(0))
    outcome, outcome_status := operations.active_operation_read_outcome(
        &state^.active_operations, reservation.outcome)
    testing.expect_value(t, outcome_status, operations.Active_Operation_Status.Ok)
    testing.expect_value(t, outcome.state,
        operations.Active_Operation_Outcome_State.Committed)
}

// Keep committed point geometry while cancelling before the native recipe completes.
@(test)
active_point_recipe_cancellation_retains_partial_geometry :: proc(t: ^testing.T) {
    state := active_operation_test_state()
    defer active_operation_test_destroy(state)
    point, reservation := active_recipe_test_submit_point(t, state, 102)
    state^.fixed_step += 1
    advance_active_operations(state, 0.5)
    before := bridge_scene.shape_get_view(state, point)
    testing.expect(t, before.visible != 0)
    testing.expect_value(t, active_operation_cancel_on_display(
        state, reservation.execution), operations.Active_Operation_Status.Ok)
    after := bridge_scene.shape_get_view(state, point)
    testing.expect(t, after.visible != 0)
    testing.expect_value(t, after.position, before.position)
    active_operation_test_expect_outcome(
        t, state, reservation.outcome, .Cancelled)
}

// Reserve an ordered native polygon trace with an exclusive pen claim.
active_recipe_test_submit_polygon :: proc(
    t: ^testing.T,
    state: ^core.Euclid_General_State,
    request_id: u64) -> (u64, operations.Active_Operation_Reservation) {
    positions: [3]geometry.Vector3 = {
        {0.2, 0.3, 0}, {0.8, 0.3, 0}, {0.5, 0.8, 0},
    }
    polygon, polygon_status := shapes.world_create_triangle(
        &state^.shape_world, positions, shapes.Shape_Style{})
    pen, pen_status := shapes.world_create_pen(&state^.shape_world, {
        joint1 = {0.2, 0.3, 1.4},
        joint2 = {0.2, 0.3, 1.75},
        length = 0.35,
    })
    testing.expect_value(t, polygon_status, shapemodel.Shape_World_Status.Ok)
    testing.expect_value(t, pen_status, shapemodel.Shape_World_Status.Ok)
    state^.world_pen = pen
    submission: operations.Active_Operation_Submission_Request = {
        kind = operations.ACTIVE_OPERATION_KIND_POLYGON_TRACE,
        request_id = request_id,
        session_generation = 2,
        runtime_generation = 3,
        animation_generation = 4,
        modifier_request = {
            kind = .Identity,
            entity = shapemodel.shape_entity_pack(polygon.shape),
            duration = 1,
            radius = 0.35,
            color_packed = 0x123456ff,
        },
        polygon_trace = {
            count = 3,
        },
    }
    active_recipe_test_polygon_targets(&submission, polygon, positions)
    testing.expect(t, active_operation_add_request_claim(
        &submission, shapemodel.shape_entity_pack(pen.joint1)))
    testing.expect(t, active_operation_add_request_claim(
        &submission, shapemodel.shape_entity_pack(pen.joint2)))
    reservation, status := active_operation_submit_modifier(state, submission)
    testing.expect_value(t, status, operations.Active_Operation_Status.Ok)
    return shapemodel.shape_entity_pack(polygon.shape), reservation
}

// Copy all ordered polygon identities and activation positions into the request.
active_recipe_test_polygon_targets :: proc(
    submission: ^operations.Active_Operation_Submission_Request,
    polygon: shapemodel.Shape_Triangle_Handle, positions: [3]geometry.Vector3) {
    ids: [3]u64 = {
        shapemodel.shape_entity_pack(polygon.first),
        shapemodel.shape_entity_pack(polygon.second),
        shapemodel.shape_entity_pack(polygon.third),
    }
    for index in 0..<3 {
        submission^.polygon_trace.vertices[index] = {
            entity = ids[index],
            position = positions[index],
        }
        assert(active_operation_add_request_claim(submission, ids[index]))
    }
    assert(active_operation_add_request_claim(
        submission, shapemodel.shape_entity_pack(polygon.shape)))
}

// Commit a skipped reveal boundary once and finish with visible geometry and raised pen.
@(test)
active_polygon_trace_reveals_once_and_finishes_native :: proc(t: ^testing.T) {
    state := active_operation_test_state()
    defer active_operation_test_destroy(state)
    polygon, reservation := active_recipe_test_submit_polygon(t, state, 601)
    state^.fixed_step += 1
    advance_active_operations(state, 0.69)
    testing.expect_value(t, state^.particle_system.formation.reveal_count, 0)
    state^.fixed_step += 1
    advance_active_operations(state, 0.02)
    testing.expect_value(t, state^.particle_system.formation.reveal_count, 1)
    state^.fixed_step += 1
    advance_active_operations(state, 0.08)
    testing.expect_value(t, state^.particle_system.formation.reveal_count, 1)
    state^.fixed_step += 1
    advance_active_operations(state, 0.22)
    testing.expect_value(t, bridge_scene.shape_get_view(state, polygon).visible, u8(1))
    testing.expect_value(t, state^.particle_system.formation.reveal_count, 0)
    pen_position := bridge_scene.shape_get_view(state,
        shapemodel.shape_entity_pack(state^.world_pen.joint1)).position
    testing.expect(t, math.abs(pen_position.z - f32(1.4)) < f32(1e-6))
    active_operation_test_expect_outcome(t, state, reservation.outcome, .Committed)
}

// Reject a full reveal-capacity transaction without advancing or duplicating its effect.
@(test)
active_polygon_trace_reveal_capacity_rejects_atomically :: proc(t: ^testing.T) {
    state := active_operation_test_state()
    defer active_operation_test_destroy(state)
    _, reservation := active_recipe_test_submit_polygon(t, state, 602)
    state^.fixed_step += 1
    advance_active_operations(state, 0.69)
    formation := &state^.particle_system.formation
    formation^.reveal_count = particles.MAX_FORMATION_REVEALS
    for index in 0..<particles.MAX_FORMATION_REVEALS {
        formation^.reveals[index] = {
            kind = .Region,
            owner_entity = u64(index + 1000),
            animation_generation = formation^.animation_generation,
            start_progress = 0,
            duration = 10,
            active = true,
        }
    }
    state^.fixed_step += 1
    advance_active_operations(state, 0.02)
    testing.expect_value(t, state^.particle_system.formation.reveal_count,
        particles.MAX_FORMATION_REVEALS)
    active_operation_test_expect_outcome(t, state, reservation.outcome, .Rejected)
}

// Keep native rolling sequences bounded to one guide and both compass joints.
@(test)
active_rolling_sequences_commit_exact_frontiers_after_skipped_phases :: proc(
    t: ^testing.T) {
    state := active_operation_test_state()
    defer active_operation_test_destroy(state)
    active_operation_test_create_rolling_tools(t, state)
    cycloid := bridge_scene.shape_create_cycloid(state, {0.2, 0.3, 0}, {0.8, 0.3, 0}, {
        rolling_radius = 0.05,
        tracer_distance = 0.04,
        parameter_start = 1,
        parameter_finish = -1,
        draw_parameter = 0.25,
    }, bridge_shape_test_input({}).style)
    testing.expect_value(t, cycloid.status, i32(bridgemodel.BRIDGE_STATUS_OK))
    cycloid_request: Bridge_Native_Modifier_Request = {
        kind = NATIVE_MODIFIER_CYCLOID_SEQUENCE_KIND,
        entity = cycloid.shape,
        second_entity = cycloid.first,
        third_entity = cycloid.second,
        duration = 1,
        start = {0.2, 0.3, 0},
        second = {0.8, 0.3, 0},
        third = {1, -1, 0.25},
        displacement = {0.04, 0.2, 0},
        radius = 0.05,
        scalar = 1.4,
        brush = 0.01,
        color_packed = 0xff123456,
    }
    cycloid_reservation := active_rolling_test_submit(
        t, state, 801, cycloid_request)
    state^.fixed_step += 1
    advance_active_operations(state, 0.3)
    actual_cycloid := bridge_scene.shape_get_cycloid(state, cycloid.shape)
    testing.expect(t, math.abs(actual_cycloid.geometry.draw_parameter -
        f32(1 + (-0.75) * (0.1 / 0.6))) < 1e-5)
    state^.fixed_step += 1
    advance_active_operations(state, 0.7)
    actual_cycloid = bridge_scene.shape_get_cycloid(state, cycloid.shape)
    testing.expect_value(t, actual_cycloid.geometry.draw_parameter, f32(0.25))
    testing.expect_value(t,
        bridge_scene.shape_get_view(state, cycloid.shape).visible, u8(1))
    active_operation_test_expect_outcome(
        t, state, cycloid_reservation.outcome, .Committed)
}

// Preserve internal-ring semantics and exact completion through native admission.
@(test)
active_trochoid_sequence_commits_internal_ring_endpoint :: proc(t: ^testing.T) {
    state := active_operation_test_state()
    defer active_operation_test_destroy(state)
    active_operation_test_create_rolling_tools(t, state)
    trochoid := bridge_scene.shape_create_trochoid(state, {0.5, 0.5, 0}, {
        mode = 1,
        fixed_radius = 0.2,
        rolling_radius = 0.05,
        tracer_distance = 0.08,
        rotation = 0.4,
        tracer_phase = 0.3,
        parameter_start = 2,
        parameter_finish = -2,
        draw_parameter = -0.5,
    }, bridge_shape_test_input({}).style)
    testing.expect_value(t, trochoid.status, i32(bridgemodel.BRIDGE_STATUS_OK))
    request: Bridge_Native_Modifier_Request = {
        kind = NATIVE_MODIFIER_TROCHOID_SEQUENCE_KIND,
        entity = trochoid.shape,
        duration = 1,
        start = {0.5, 0.5, 0},
        third = {2, -2, -0.5},
        displacement = {0.2, 0.08, 0.3},
        angle = 0.4,
        radius = 0.05,
        scalar = 1.4,
        integer = 1,
        brush = 0.01,
        color_packed = 0xff123456,
    }
    reservation := active_rolling_test_submit(t, state, 802, request)
    state^.fixed_step += 1
    advance_active_operations(state, 0.3)
    state^.fixed_step += 1
    advance_active_operations(state, 0.7)
    geometry, found := shapemodel.shape_component_get(
        &state^.shape_world.trochoids, &state^.shape_world.registry,
        shapemodel.shape_entity_unpack(trochoid.shape))
    testing.expect(t, found)
    testing.expect_value(t, geometry^.draw_parameter, f32(-0.5))
    testing.expect_value(t, geometry^.rotation, f32(0.4))
    active_operation_test_expect_outcome(t, state, reservation.outcome, .Committed)
}

// Reveal conics at draw start and commit exact frontiers after skipped phases.
@(test)
active_conic_sequences_reveal_progressively_and_preserve_final_frontiers :: proc(
    t: ^testing.T) {
    state := active_operation_test_state()
    defer active_operation_test_destroy(state)
    active_operation_test_create_conic_tools(t, state)
    parabola_host, parabola := active_operation_test_submit_conic(
        t, state, 803, .Parabola_Sequence)
    hyperbola_host, hyperbola := active_operation_test_submit_conic(
        t, state, 804, .Hyperbola_Sequence)
    testing.expect_value(t,
        bridge_scene.shape_get_view(state, parabola_host).visible, u8(0))
    testing.expect_value(t,
        bridge_scene.shape_get_view(state, hyperbola_host).visible, u8(0))
    state^.fixed_step += 1
    advance_active_operations(state, 0.3)
    testing.expect(t, math.abs(state^.shape_world.parabola_tools.values[0].parameter -
        f32(0.75)) < f32(1e-6))
    testing.expect_value(t,
        bridge_scene.shape_get_view(state, parabola_host).visible, u8(1))
    testing.expect_value(t,
        bridge_scene.shape_get_view(state, hyperbola_host).visible, u8(1))
    testing.expect_value(t, bridge_scene.shape_get_parabola(
        state, parabola_host).geometry.draw_parameter, f32(0.75))
    testing.expect_value(t, bridge_scene.shape_get_hyperbola(
        state, hyperbola_host).geometry.draw_parameter, f32(0.75))
    testing.expect_value(t,
        state^.shape_world.hyperbola_tools.values[0].active_branches,
        shapemodel.Hyperbola_Branches.Negative)
    state^.fixed_step += 1
    advance_active_operations(state, 0.7)
    active_operation_test_expect_conic_completion(
        t, state, {parabola_host, hyperbola_host}, parabola, hyperbola)
}

// Conic tool claims reject overlap and cancellation retains a correlated result.
@(test)
active_conic_sequences_reject_shared_tool_conflicts_and_cancel :: proc(t: ^testing.T) {
    state := active_operation_test_state()
    defer active_operation_test_destroy(state)
    active_operation_test_create_conic_tools(t, state)
    _, active := active_operation_test_submit_conic(
        t, state, 805, .Parabola_Sequence)
    second_host := active_operation_test_create_conic_host(t, state, true)
    request: modifier.Modifier_Request = {
        kind = .Parabola_Sequence,
        entity = second_host,
        duration = 1,
        start_position = {0.4, 0.5, 0},
        third_position = {1, -1, -0.5},
        radius = 0.075,
        angle = 0.6,
        scalar = 1.4,
    }
    submission := active_operation_test_submission(
        806, request, active_operation_test_claim(second_host))
    testing.expect(t, active_operation_add_conic_tool_claims(
        &submission, state, .Parabola_Sequence))
    rejected, status := active_operation_submit_modifier(state, submission)
    testing.expect_value(t, status, operations.Active_Operation_Status.Conflict)
    testing.expect_value(t, active_operation_cancel_on_display(state, active.execution),
        operations.Active_Operation_Status.Ok)
    active_operation_test_expect_outcome(t, state, rejected.outcome, .Rejected)
    active_operation_test_expect_outcome(t, state, active.outcome, .Cancelled)
}

// Create the fixed conic apparatus that the active recipes exclusively claim.
active_operation_test_create_conic_tools :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State) {
    style: shapes.Shape_Style = {}
    parabola, parabola_status := shapes.world_create_parabola_tool(
        &state^.shape_world, {
            vertex = {0.4, 0.5, 0},
            focal_distance = 0.075,
            link_length = 0.16,
            rotation = 0.6,
            parameter_start = 1,
            parameter_finish = -1,
            parameter = 1,
            style = style,
        })
    hyperbola, hyperbola_status := shapes.world_create_hyperbola_tool(
        &state^.shape_world, {
            center = {0.5, 0.5, 0},
            semimajor = 0.12,
            semiminor = 0.08,
            rotation = 0.6,
            parameter_start = 1,
            parameter_finish = -1,
            parameter = 1,
            rail_half_length = 0.3,
            style = style,
        })
    testing.expect_value(t, parabola_status, shapemodel.Shape_World_Status.Ok)
    testing.expect_value(t, hyperbola_status, shapemodel.Shape_World_Status.Ok)
    state^.world_parabola_tool = parabola
    state^.world_hyperbola_tool = hyperbola
    testing.expect_value(t, bridge_scene.set_parabola_tool_geometry(
        state, {0.075, 0.16, 0.6, 1, -1, 1}), i32(bridgemodel.BRIDGE_STATUS_OK))
    testing.expect_value(t, bridge_scene.set_hyperbola_tool_geometry(
        state, {0.12, 0.08, 0.6, 1, -1, 1, 0.3}),
        i32(bridgemodel.BRIDGE_STATUS_OK))
}

// Submit one host-bound conic sequence through ordinary captured admission.
active_operation_test_submit_conic :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State, request_id: u64,
    kind: modifier.Modifier_Kind) -> (
        u64, operations.Active_Operation_Reservation) {
    is_parabola := kind == .Parabola_Sequence
    host := active_operation_test_create_conic_host(t, state, is_parabola)
    request: Bridge_Native_Modifier_Request = {
        kind = NATIVE_MODIFIER_PARABOLA_SEQUENCE_KIND,
        entity = host,
        duration = 1,
        start = {0.4, 0.5, 0},
        third = {1, -1, -0.5},
        angle = 0.6,
        radius = 0.075,
        scalar = 1.4,
        color_packed = 0xff123456,
    }
    if !is_parabola {
        request.kind = NATIVE_MODIFIER_HYPERBOLA_SEQUENCE_KIND
        request.radius = 0.12
        request.displacement.x = 0.08
        request.integer = 2
    }
    reservation := active_operation_test_capture_conic(t, state, request_id, request)
    return host, reservation
}

// Create one hidden analytic host with the exact selected conic parameters.
active_operation_test_create_conic_host :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State, parabola: bool) -> u64 {
    style := bridge_shape_test_input({}).style
    if parabola {
        result := bridge_scene.shape_create_parabola(state, {0.4, 0.5, 0},
            {0.075, 0.6, 1, -1, 1}, style)
        testing.expect_value(t, result.status, i32(bridgemodel.BRIDGE_STATUS_OK))
        return result.shape
    }
    result := bridge_scene.shape_create_hyperbola(state, {0.5, 0.5, 0},
        {0.12, 0.08, 0.6, 1, -1, 1}, style, .Negative)
    testing.expect_value(t, result.status, i32(bridgemodel.BRIDGE_STATUS_OK))
    return result.shape
}

// Capture the ABI request and verify both host and apparatus are claimed.
active_operation_test_capture_conic :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State, request_id: u64,
    request: Bridge_Native_Modifier_Request) -> operations.Active_Operation_Reservation {
    batch: bridge_scene.Scene_Command_Batch
    active_operation_test_begin_julia_batch(state, &batch)
    testing.expect_value(t, submit_active_modifier(state, request_id, request),
        i32(bridgemodel.BRIDGE_STATUS_OK))
    submission := batch.active_operation_submissions[0].request
    claims := submission.claims[:submission.claim_count]
    apparatus := state^.world_parabola_tool
    if request.kind == NATIVE_MODIFIER_HYPERBOLA_SEQUENCE_KIND {
        apparatus = state^.world_hyperbola_tool
    }
    testing.expect(t, operations.active_operation_claim_set_contains(
        claims, request.entity))
    testing.expect(t, operations.active_operation_claim_set_contains(
        claims, shapemodel.shape_entity_pack(apparatus)))
    testing.expect(t, bridge_scene.scene_active_operation_marker_valid(
        state, &batch, &batch.commands[0]))
    testing.expect(t, bridge_scene.scene_active_operation_initial_samples_match(
        &batch, 0, submission))
    testing.expect(t, bridge_scene.scene_active_operation_submission_prior_claims_clear(
        &batch, 0, submission))
    bridge_scene.end_scene_command_batch(state)
    testing.expect(t, bridge_scene.commit_scene_command_batch(state, &batch))
    return batch.active_operation_submissions[0].reservation
}

// Check final analytic geometry, selected contacts, visibility and receipts.
active_operation_test_expect_conic_completion :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State,
    hosts: [2]u64,
    parabola, hyperbola: operations.Active_Operation_Reservation) {
    testing.expect_value(t,
        state^.shape_world.parabola_tools.values[0].parameter, f32(-0.5))
    testing.expect_value(t,
        state^.shape_world.hyperbola_tools.values[0].parameter, f32(-0.5))
    testing.expect_value(t, bridge_scene.shape_get_parabola(
        state, hosts[0]).geometry.draw_parameter, f32(-0.5))
    testing.expect_value(t, bridge_scene.shape_get_hyperbola(
        state, hosts[1]).geometry.draw_parameter, f32(-0.5))
    testing.expect_value(t,
        bridge_scene.shape_get_view(state, hosts[0]).visible, u8(1))
    testing.expect_value(t,
        bridge_scene.shape_get_view(state, hosts[1]).visible, u8(1))
    testing.expect_value(t,
        state^.shape_world.hyperbola_tools.values[0].active_branches,
        shapemodel.Hyperbola_Branches.None)
    active_operation_test_expect_outcome(t, state, parabola.outcome, .Committed)
    active_operation_test_expect_outcome(t, state, hyperbola.outcome, .Committed)
}

// Create the shared apparatus required by both active rolling families.
active_operation_test_create_rolling_tools :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State) {
    compass_status, cycloid_status, trochoid_status: shapemodel.Shape_World_Status
    state^.world_compass, compass_status = shapes.world_create_compass(
        &state^.shape_world, {
            joint1 = {0.4, 0.5, 1.4},
            joint2 = {0.6, 0.5, 1.4},
            limb_length = 0.2,
        })
    state^.world_cycloid_tool, cycloid_status = shapes.world_create_cycloid_tool(
        &state^.shape_world, {
            first = {0.2, 0.3, 0},
            second = {0.8, 0.3, 0},
            rolling_radius = 0.05,
            parameter_start = 1,
            parameter_finish = -1,
        })
    state^.world_trochoid_tool, trochoid_status = shapes.world_create_trochoid_tool(
        &state^.shape_world, {
            fixed_radius = 0.2,
            rolling_radius = 0.05,
        })
    testing.expect_value(t, compass_status, shapemodel.Shape_World_Status.Ok)
    testing.expect_value(t, cycloid_status, shapemodel.Shape_World_Status.Ok)
    testing.expect_value(t, trochoid_status, shapemodel.Shape_World_Status.Ok)
}

// Capture and commit one ABI rolling sequence through normal Julia batch admission.
active_rolling_test_submit :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State, request_id: u64,
    request: Bridge_Native_Modifier_Request) -> operations.Active_Operation_Reservation {
    kind, valid := native_modifier_kind_from_abi(request.kind)
    testing.expect(t, valid)
    initial := native_modifier_request_from_abi(request, kind)
    initial.elapsed = 0
    phase := modifier.rolling_sequence_phase_request(initial, 0)
    command: bridge_scene.Scene_Command = {
        kind = .Apply_Native_Modifier,
        modifier = phase,
    }
    testing.expect(t, bridge_scene.validate_native_modifier_marker(
        state, &command), "initial rolling sample must pass native validation")
    batch: bridge_scene.Scene_Command_Batch
    active_operation_test_begin_julia_batch(state, &batch)
    testing.expect_value(t,
        submit_active_modifier(state, request_id, request),
        i32(bridgemodel.BRIDGE_STATUS_OK))
    marker := &batch.commands[0]
    submission := batch.active_operation_submissions[0].request
    active_rolling_test_claims_cover_tools(t, state, submission)
    active_rolling_test_marker_is_valid(t, state, &batch, marker, submission)
    bridge_scene.end_scene_command_batch(state)
    testing.expect(t, bridge_scene.commit_scene_command_batch(state, &batch))
    return batch.active_operation_submissions[0].reservation
}

// Assert the operation claims its rolling guide and shared compass joints.
active_rolling_test_claims_cover_tools :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State,
    submission: operations.Active_Operation_Submission_Request) {
    claim_array := submission.claims
    claims := claim_array[:submission.claim_count]
    guide := state^.world_trochoid_tool.shape
    if submission.modifier_request.kind == .Cycloid_Sequence {
        cycloid := state^.world_cycloid_tool
        testing.expect(t, operations.active_operation_claim_set_contains(
            claims, shapemodel.shape_entity_pack(cycloid.shape)))
        testing.expect(t, operations.active_operation_claim_set_contains(
            claims, shapemodel.shape_entity_pack(cycloid.first)))
        testing.expect(t, operations.active_operation_claim_set_contains(
            claims, shapemodel.shape_entity_pack(cycloid.second)))
    } else {
        testing.expect(t, operations.active_operation_claim_set_contains(
            claims, shapemodel.shape_entity_pack(guide)))
    }
    testing.expect(t, operations.active_operation_claim_set_contains(
        claims, shapemodel.shape_entity_pack(state^.world_compass.joint1)))
    testing.expect(t, operations.active_operation_claim_set_contains(
        claims, shapemodel.shape_entity_pack(state^.world_compass.joint2)))
}

// Verify the marker's initial samples and same-batch claim isolation.
active_rolling_test_marker_is_valid :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State,
    batch: ^bridge_scene.Scene_Command_Batch, marker: ^bridge_scene.Scene_Command,
    submission: operations.Active_Operation_Submission_Request) {
    testing.expect(t,
        bridge_scene.scene_active_operation_marker_valid(state, batch, marker),
        "rolling operation marker must validate")
    testing.expect(t,
        bridge_scene.scene_active_operation_initial_samples_match(batch, 0, submission),
        "rolling operation initial sample must match")
    testing.expect(t,
        bridge_scene.scene_active_operation_submission_prior_claims_clear(
            batch, 0, submission),
        "rolling operation must not conflict with prior claims")
    testing.expect(t,
        !bridge_scene.scene_active_operation_claims_conflict_with_later_commands(
            state, batch, 0, submission),
        "rolling operation initial sample must not conflict with its claims")
}

// Commit a line's intermediate endpoint and complete native pen motion.
@(test)
active_line_recipe_advances_geometry_and_retires_pen_contact :: proc(t: ^testing.T) {
    state := active_operation_test_state()
    defer active_operation_test_destroy(state)
    line, reservation := active_recipe_test_submit_line(t, state, 104)
    state^.fixed_step += 1
    advance_active_operations(state, 0.5)
    midpoint := bridge_scene.shape_get_view(state, line.second).position
    expected: geometry.Vector3 = {0.5, 0.5, 0}
    testing.expect(t, math.abs(midpoint.x - expected.x) < 1e-6)
    testing.expect(t, math.abs(midpoint.y - expected.y) < 1e-6)
    contact, contact_found := shapemodel.shape_component_get(
        &state^.shape_world.active_features, &state^.shape_world.registry,
        state^.world_pen.shape)
    testing.expect(t, contact_found)
    testing.expect_value(t, contact.index, u16(1))
    state^.fixed_step += 1
    advance_active_operations(state, 0.6)
    final := bridge_scene.shape_get_view(state, line.second).position
    testing.expect_value(t, final, geometry.Vector3{0.8, 0.7, 0})
    contact, contact_found = shapemodel.shape_component_get(
        &state^.shape_world.active_features, &state^.shape_world.registry,
        state^.world_pen.shape)
    testing.expect(t, contact_found)
    testing.expect_value(t, contact.index, u16(0))
    active_operation_test_expect_outcome(
        t, state, reservation.outcome, .Committed)
}

// Commit a filled-sector reveal when one fixed step skips its entire draw phase.
@(test)
active_filled_circle_recipe_commits_skipped_reveal_once :: proc(t: ^testing.T) {
    state := active_operation_test_state()
    defer active_operation_test_destroy(state)
    reservation := active_recipe_test_submit_filled_circle(t, state, 103)
    state^.fixed_step += 1
    advance_active_operations(state, 0.95)
    testing.expect_value(t, state^.particle_system.formation.reveal_count, 1)
    state^.fixed_step += 1
    advance_active_operations(state, 0.1)
    testing.expect(t, state^.particle_system.formation.reveal_count <= 1)
    active_operation_test_expect_outcome(
        t, state, reservation.outcome, .Committed)
}

// Preserve live claims and native sound sources when lifecycle admission fails.
@(test)
active_operation_lifecycle_failure_preserves_claims_and_activity :: proc(
    t: ^testing.T) {
    state := active_operation_test_state()
    defer active_operation_test_destroy(state)
    service := new(bridgemodel.Julia_Runtime_Service, context.allocator)
    testing.expect(t, service != nil)
    if service == nil {
        return
    }
    defer free(service, context.allocator)
    testing.expect(t, transport.consumer_mailbox_init(
        &service^.julia_inbox, 1024, 4096, 1) == .None)
    state^.julia_runtime_service = service
    defer active_operation_test_close_mailbox(state, service)
    service^.animation_generation = 4
    service^.next_request_id = 1
    reservation := active_operation_test_begin_lifecycle_operation(t, state, 83, 991)
    transport.consumer_mailbox_close(&service^.julia_inbox)
    testing.expect(t, !synchronize_animation_lifecycle(state))
    testing.expect_value(t, service^.animation_generation, u64(4))
    testing.expect(t, state^.chalk_audio.drawing_active)
    progress, live := operations.active_operation_observe(
        &state^.active_operations, reservation.execution)
    testing.expect(t, live)
    claim := active_operation_test_claim(progress.modifier_request.entity)
    claims: [1]operations.Active_Operation_Claim
    claims[0] = claim
    testing.expect(t, operations.active_operation_claims_conflict(
        &state^.active_operations, claims[:]))
    outcome_slot := &state^.active_operations.outcome_slots[
        reservation.outcome.index]
    testing.expect(t, outcome_slot.occupied)
    testing.expect_value(t, outcome_slot.state,
        operations.Active_Operation_Outcome_State.None)
}

// Keep native operation ownership when a candidate fails after native reset.
@(test)
active_operation_reload_enter_rollback_preserves_live_operation :: proc(
    t: ^testing.T) {
    state := active_operation_test_state()
    defer active_operation_test_destroy(state)
    testing.expect(t, bridge_animation.animation_storage_init(
        &state^.animation_memory, &state^.animation_values,
        &state^.dynview_documents))
    defer bridge_animation.animation_storage_destroy(
        &state^.animation_memory, &state^.animation_values,
        &state^.dynview_documents)
    testing.expect_value(t, shapemodel.shape_world_freeze_baseline(
        &state^.shape_world), shapemodel.Shape_World_Status.Ok)
    service := new(bridgemodel.Julia_Runtime_Service, context.allocator)
    testing.expect(t, service != nil)
    if service == nil {
        return
    }
    defer free(service, context.allocator)
    state^.julia_runtime_service = service
    service^.animation_generation = 4
    service^.reload_failure_injection = .Animation_Enter
    reservation := active_operation_test_begin_lifecycle_operation(
        t, state, 85, 993)
    testing.expect(t, reset_animation_switch_state(state))
    reset_succeeded := animation_lifecycle_reset_result(
        service, ANIMATION_LIFECYCLE_RELOAD, true)
    testing.expect(t, !reset_succeeded)
    testing.expect_value(t, service^.animation_generation, u64(4))
    testing.expect(t, state^.chalk_audio.drawing_active)
    active_operation_test_expect_live_claim(
        t, state, reservation.execution)
    outcome_slot := &state^.active_operations.outcome_slots[
        reservation.outcome.index]
    testing.expect_value(t, outcome_slot.state,
        operations.Active_Operation_Outcome_State.None)
}

// Retire session operations only after lifecycle success and retain their results.
@(test)
active_operation_lifecycle_commit_retires_and_retains_outcome :: proc(
    t: ^testing.T) {
    state := active_operation_test_state()
    defer active_operation_test_destroy(state)
    service := new(bridgemodel.Julia_Runtime_Service, context.allocator)
    testing.expect(t, service != nil)
    if service == nil {
        return
    }
    defer free(service, context.allocator)
    defer state^.julia_runtime_service = nil
    state^.julia_runtime_service = service
    service^.animation_generation = 4
    reservation := active_operation_test_begin_lifecycle_operation(t, state, 84, 992)
    active_operation_commit_generation_transition(state, service, 2)
    testing.expect_value(t, service^.animation_generation, u64(5))
    testing.expect(t, !state^.chalk_audio.drawing_active)
    _, live := operations.active_operation_observe(
        &state^.active_operations, reservation.execution)
    testing.expect(t, !live)
    outcome, outcome_status := operations.active_operation_read_outcome(
        &state^.active_operations, reservation.outcome)
    testing.expect_value(t, outcome_status, operations.Active_Operation_Status.Ok)
    testing.expect_value(t,
        outcome.state, operations.Active_Operation_Outcome_State.Cancelled)
    diagnostics := operations.active_operation_storage_diagnostics(
        &state^.active_operations)
    testing.expect_value(t,
        diagnostics.outcome_used, 1)
}

// A committed Terminal close cancels its operations without dropping outcomes.
@(test)
active_operation_terminal_close_retains_cancellation_outcome :: proc(
    t: ^testing.T) {
    state := active_operation_test_state()
    defer active_operation_test_destroy(state)
    reservation := active_operation_test_begin_lifecycle_operation(
        t, state, 86, 994)
    active_operation_retire_session(state, 2)
    testing.expect(t, state^.chalk_audio.drawing_active)
    active_operation_test_expect_outcome(
        t, state, reservation.outcome, .Cancelled)
    _, live := operations.active_operation_observe(
        &state^.active_operations, reservation.execution)
    testing.expect(t, !live)
}

// Reject claimed Julia writes and overlapping native admission without partial effects.
@(test)
active_modifier_claims_reject_native_and_delayed_julia_conflicts :: proc(
    t: ^testing.T) {
    state := active_operation_test_state()
    defer active_operation_test_destroy(state)
    point := bridge_scene.shape_create_point(
        state, bridge_shape_test_input({0, 0, 0}))
    request: modifier.Modifier_Request = {
        kind = .Set_Point_Position,
        entity = point.entity,
        duration = 1,
        displacement = {1, 0, 0},
    }
    claim := active_operation_test_claim(point.entity)
    first_submission := active_operation_test_submission(61, request, claim)
    first, first_status := active_operation_submit_modifier(state, first_submission)
    testing.expect_value(t, first_status, operations.Active_Operation_Status.Ok)
    second_submission := active_operation_test_submission(62, request, claim)
    second, second_status := active_operation_submit_modifier(state, second_submission)
    testing.expect_value(t, second_status, operations.Active_Operation_Status.Conflict)
    active_operation_test_expect_outcome(t, state, second.outcome, .Rejected)
    active_operation_test_reject_julia_write(t, state, point.entity)
    testing.expect_value(t, bridge_scene.shape_get_view(
        state, point.entity).position.x, f32(0))
    advance_active_operations(state, 1)
    active_operation_test_expect_outcome(t, state, first.outcome, .Committed)
}

// Preserve capture order and commit the time-zero pose with the surrounding scene batch.
@(test)
active_modifier_submission_uses_ordered_scene_transaction :: proc(t: ^testing.T) {
    state := active_operation_test_state()
    defer active_operation_test_destroy(state)
    point := bridge_scene.shape_create_point(
        state, bridge_shape_test_input({0, 0, 0}))
    other := bridge_scene.shape_create_point(
        state, bridge_shape_test_input({0, 0, 0}))
    batch: bridge_scene.Scene_Command_Batch
    active_operation_test_begin_julia_batch(state, &batch, 0)
    request := active_operation_test_abi_request(point.entity)
    testing.expect_value(t, submit_active_modifier(state, 71, request),
        i32(bridgemodel.BRIDGE_STATUS_OK))
    testing.expect_value(t,
        batch.active_operation_submissions[0].request.runtime_generation, u64(4))
    testing.expect_value(t, bridge_scene.shape_set_position(state, other.entity,
        {2, 0, 0}), i32(bridgemodel.BRIDGE_STATUS_OK))
    testing.expect_value(t, batch.command_count, 3)
    testing.expect_value(t, batch.active_operation_submission_count, 1)
    testing.expect_value(t, batch.commands[2].entity, other.entity)
    bridge_scene.end_scene_command_batch(state)
    testing.expect(t, bridge_scene.commit_scene_command_batch(state, &batch))
    testing.expect_value(t, bridge_scene.shape_get_view(
        state, point.entity).position.x, f32(0))
    testing.expect_value(t, bridge_scene.shape_get_view(
        state, other.entity).position.x, f32(2))
    reservation := batch.active_operation_submissions[0].reservation
    testing.expect_value(t,
        state^.active_operations.execution_slots[reservation.execution.index].state,
        operations.Active_Operation_State.Live)
    _, live := operations.active_operation_observe(
        &state^.active_operations, reservation.execution)
    testing.expect(t, live)
}

// Reject an overlapping later scene write before the captured operation has effects.
@(test)
active_modifier_submission_conflict_rejects_complete_scene_batch :: proc(t: ^testing.T) {
    state := active_operation_test_state()
    defer active_operation_test_destroy(state)
    point := bridge_scene.shape_create_point(
        state, bridge_shape_test_input({0, 0, 0}))
    batch: bridge_scene.Scene_Command_Batch
    active_operation_test_begin_julia_batch(state, &batch)
    request := active_operation_test_abi_request(point.entity)
    testing.expect_value(t, submit_active_modifier(state, 72, request),
        i32(bridgemodel.BRIDGE_STATUS_OK))
    _ = bridge_scene.shape_set_position(state, point.entity, {5, 0, 0})
    testing.expect_value(t, batch.command_count, 3)
    testing.expect_value(t, batch.commands[2].entity, point.entity)
    testing.expect_value(t, batch.active_operation_submissions[0].request.claim_count, 1)
    bridge_scene.end_scene_command_batch(state)
    testing.expect(t,
        bridge_scene.scene_active_operation_claims_conflict_with_later_commands(
            state, &batch, 0,
            batch.active_operation_submissions[0].request))
    testing.expect(t, !bridge_scene.commit_scene_command_batch(state, &batch))
    testing.expect_value(t, bridge_scene.shape_get_view(
        state, point.entity).position.x, f32(0))
    testing.expect_value(t, state^.active_operations.execution_slots[0].state,
        operations.Active_Operation_State.Free)
}

// Retry a retained terminal outcome after mailbox capacity returns.
@(test)
active_operation_outcome_delivery_retries_after_full_mailbox :: proc(
    t: ^testing.T) {
    state := active_operation_test_state()
    defer active_operation_test_destroy(state)
    service := new(bridgemodel.Julia_Runtime_Service, context.allocator)
    testing.expect(t, service != nil)
    if service == nil {
        return
    }
    defer free(service, context.allocator)
    testing.expect(t, transport.consumer_mailbox_init(
        &service^.julia_inbox, 1024, 4096, 1) == .None)
    state^.julia_runtime_service = service
    defer active_operation_test_close_mailbox(state, service)
    _ = active_operation_test_publish_outcome(t, state, 81)
    active_operation_test_fill_mailbox(t, service)
    testing.expect_value(t, pump_active_operation_outcomes(state),
        bridgemodel.Communication_Send_Outcome.Queue_Full)
    active_operation_test_release_mailbox_item(t, service)
    testing.expect_value(t, pump_active_operation_outcomes(state),
        bridgemodel.Communication_Send_Outcome.Sent)
    active_operation_test_expect_delivered_outcome(t, service, 81)
    testing.expect_value(t, operations.active_operation_storage_diagnostics(
        &state^.active_operations).outcome_used, 1)
}

// Keep an acknowledged outcome retained until its receipt returns to display ownership.
@(test)
active_operation_outcome_delivery_retries_and_waits_for_receipt :: proc(
    t: ^testing.T) {
    state := active_operation_test_state()
    defer active_operation_test_destroy(state)
    service := new(bridgemodel.Julia_Runtime_Service, context.allocator)
    testing.expect(t, service != nil)
    if service == nil {
        return
    }
    defer free(service, context.allocator)
    testing.expect(t, transport.consumer_mailbox_init(
        &service^.julia_inbox, 1024, 4096, 1) == .None)
    state^.julia_runtime_service = service
    defer active_operation_test_close_mailbox(state, service)
    _ = active_operation_test_publish_outcome(t, state, 81)
    testing.expect_value(t, pump_active_operation_outcomes(state),
        bridgemodel.Communication_Send_Outcome.Sent)
    active_operation_test_expect_delivered_outcome(t, service, 81)
    testing.expect_value(t, operations.active_operation_storage_diagnostics(
        &state^.active_operations).outcome_used, 1)
    testing.expect_value(t, pump_active_operation_outcomes(state),
        bridgemodel.Communication_Send_Outcome.Sent)
    _, duplicate_sent := transport.consumer_mailbox_try_recv(&service^.julia_inbox)
    testing.expect(t, !duplicate_sent)
    identity: operations.Active_Operation_Outcome_Identity = {
        request_id = 81,
        session_generation = 2,
        runtime_generation = 3,
        animation_generation = 4,
        outcome_generation = 1,
    }
    testing.expect_value(t, active_operation_acknowledge_outcome(
        state, identity), i32(bridgemodel.BRIDGE_STATUS_OK))
    testing.expect_value(t, operations.active_operation_storage_diagnostics(
        &state^.active_operations).outcome_used, 0)
}

// Accept an exact duplicate receipt without disturbing other outcome slots.
@(test)
active_operation_duplicate_outcome_receipt_is_idempotent :: proc(
    t: ^testing.T) {
    state := active_operation_test_state()
    defer active_operation_test_destroy(state)
    reservation := active_operation_test_publish_outcome(t, state, 81)
    testing.expect_value(t, operations.active_operation_mark_outcome_sent(
        &state^.active_operations, reservation.outcome),
        operations.Active_Operation_Status.Ok)
    identity: operations.Active_Operation_Outcome_Identity = {
        request_id = 81,
        session_generation = 2,
        runtime_generation = 3,
        animation_generation = 4,
        outcome_generation = reservation.outcome.generation,
    }
    testing.expect_value(t, active_operation_acknowledge_outcome(
        state, identity), i32(bridgemodel.BRIDGE_STATUS_OK))
    testing.expect_value(t, active_operation_acknowledge_outcome(
        state, identity), i32(bridgemodel.BRIDGE_STATUS_OK))
    testing.expect_value(t, operations.active_operation_storage_diagnostics(
        &state^.active_operations).outcome_used, 0)
}

// Keep an outcome reserved when the Julia inbox closes before publication.
@(test)
active_operation_outcome_delivery_preserves_closed_mailbox_result :: proc(
    t: ^testing.T) {
    state := active_operation_test_state()
    defer active_operation_test_destroy(state)
    service := new(bridgemodel.Julia_Runtime_Service, context.allocator)
    testing.expect(t, service != nil)
    if service == nil {
        return
    }
    defer free(service, context.allocator)
    testing.expect(t, transport.consumer_mailbox_init(
        &service^.julia_inbox, 1024, 4096, 1) == .None)
    state^.julia_runtime_service = service
    defer active_operation_test_close_mailbox(state, service)
    reservation := active_operation_test_publish_outcome(t, state, 82)
    transport.consumer_mailbox_close(&service^.julia_inbox)
    testing.expect_value(t, pump_active_operation_outcomes(state),
        bridgemodel.Communication_Send_Outcome.Channel_Closed)
    testing.expect(t, service^.julia_inbox.initialized)
    outcome, status := operations.active_operation_read_outcome(
        &state^.active_operations, reservation.outcome)
    testing.expect_value(t, status, operations.Active_Operation_Status.Ok)
    testing.expect_value(t, outcome.request_id, u64(82))
}

// Keep Julia's result queued when the display acknowledgment mailbox is full.
@(test)
active_operation_outcome_acknowledgment_retries_display_backpressure :: proc(
    t: ^testing.T) {
    state := active_operation_test_state()
    defer active_operation_test_destroy(state)
    service := new(bridgemodel.Julia_Runtime_Service, context.allocator)
    testing.expect(t, service != nil)
    if service == nil {
        return
    }
    defer free(service, context.allocator)
    testing.expect(t, transport.consumer_mailbox_init(
        &service^.display_inbox, 1024, 4096, 1) == .None)
    defer transport.consumer_mailbox_destroy(&service^.display_inbox)
    state^.julia_runtime_service = service
    receipt: bridgemodel.Active_Operation_Outcome_Acknowledged = {
        identity = {
            request_id = 90,
            session_generation = 2,
            runtime_generation = 3,
            animation_generation = 4,
            outcome_generation = 5,
        },
    }
    testing.expect_value(t, transport.consumer_mailbox_publish(
        &service^.display_inbox, bridgemodel.Julia_Host_Egress(receipt)),
        bridgemodel.Communication_Send_Outcome.Sent)
    testing.expect_value(t, publish_active_operation_outcome_acknowledgment(
        state, operations.Active_Operation_Outcome_Identity{
            request_id = 91,
            session_generation = 2,
            runtime_generation = 3,
            animation_generation = 4,
            outcome_generation = 6,
        }), i32(bridgemodel.BRIDGE_STATUS_OUT_OF_CAPACITY))
    message, received := transport.consumer_mailbox_try_recv(&service^.display_inbox)
    testing.expect(t, received)
    transport.consumer_mailbox_release(&service^.display_inbox, message)
    testing.expect_value(t, publish_active_operation_outcome_acknowledgment(
        state, operations.Active_Operation_Outcome_Identity{
            request_id = 91,
            session_generation = 2,
            runtime_generation = 3,
            animation_generation = 4,
            outcome_generation = 6,
        }), i32(bridgemodel.BRIDGE_STATUS_OK))
    message, received = transport.consumer_mailbox_try_recv(&service^.display_inbox)
    testing.expect(t, received)
    retained, found := message^.(bridgemodel.Active_Operation_Outcome_Acknowledged)
    testing.expect(t, found)
    testing.expect_value(t, retained.identity.request_id, u64(91))
    testing.expect_value(t, retained.identity.outcome_generation, u64(6))
    transport.consumer_mailbox_release(&service^.display_inbox, message)
}

// Create the minimal display state required by modifier-backed operation tests.
active_operation_test_state :: proc() -> ^core.Euclid_General_State {
    state := bridge_reveal_test_state_create()
    _ = operations.active_operation_storage_init(&state^.active_operations)
    return state
}

// Reserve one real point recipe with an exclusive pen claim for integration tests.
active_recipe_test_submit_point :: proc(
    t: ^testing.T,
    state: ^core.Euclid_General_State,
    request_id: u64) -> (u64, operations.Active_Operation_Reservation) {
    point := bridge_scene.shape_create_point(
        state, bridge_shape_test_input({0, 0, 0}))
    pen, pen_status := shapes.world_create_pen(&state^.shape_world, {
        joint1 = {0.25, 0.3, 1.4},
        joint2 = {0.25, 0.3, 1.75},
        length = 0.35,
    })
    testing.expect_value(t, pen_status, shapemodel.Shape_World_Status.Ok)
    state^.world_pen = pen
    request: modifier.Modifier_Request = {
        kind = .Construct_Point,
        entity = point.entity,
        duration = 1,
        start_position = {0.25, 0.3, 0},
        radius = 0.35,
        brush = 0.08,
        color_packed = 0x123456ff,
    }
    submission := active_operation_test_submission(
        request_id, request, active_operation_test_claim(point.entity))
    submission.claim_count = 2
    submission.claims[1] = active_operation_test_claim(
        shapemodel.shape_entity_pack(state^.world_pen.shape))
    reservation, status := active_operation_submit_modifier(state, submission)
    testing.expect_value(t, status, operations.Active_Operation_Status.Ok)
    return point.entity, reservation
}

// Reserve one filled-circle recipe with claims for its host and compass joints.
active_recipe_test_submit_filled_circle :: proc(
    t: ^testing.T,
    state: ^core.Euclid_General_State,
    request_id: u64) -> (operations.Active_Operation_Reservation) {
    request := active_recipe_test_filled_circle_request(t, state)
    submission := active_operation_test_submission(
        request_id, request, active_operation_test_claim(request.entity))
    submission.claim_count = 3
    submission.claims[1] = active_operation_test_claim(request.second_entity)
    submission.claims[2] = active_operation_test_claim(request.third_entity)
    reservation, status := active_operation_submit_modifier(state, submission)
    testing.expect_value(t, status, operations.Active_Operation_Status.Ok)
    return reservation
}

// Create the real filled-circle host and compass geometry used by recipe tests.
active_recipe_test_filled_circle_request :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State) -> modifier.Modifier_Request {
    particles.formation_reset_generation(&state^.particle_system, 4)
    compass, compass_status := shapes.world_create_compass(&state^.shape_world, {
        joint1 = {0.5, 0.5, 0},
        joint2 = {0.7, 0.5, 0},
        limb_length = 0.2,
    })
    testing.expect_value(t, compass_status, shapemodel.Shape_World_Status.Ok)
    state^.world_compass = compass
    host := bridge_scene.shape_create_filled_arc(state, {0.5, 0.5, 0},
        {0.2, 0, 0}, bridge_shape_test_input({}).style)
    testing.expect_value(t, host.status, bridgemodel.BRIDGE_STATUS_OK)
    request: modifier.Modifier_Request = {
        kind = .Construct_Filled_Circle,
        entity = host.shape,
        second_entity = shapemodel.shape_entity_pack(compass.joint1),
        third_entity = shapemodel.shape_entity_pack(compass.joint2),
        duration = 1,
        start_position = {0.5, 0.5, 0},
        second_position = {0.7, 0.5, 0},
        angle = f32(math.PI / 2),
        radius = 0.2,
        brush = 0.03,
        color_packed = 0xffaa55ff,
        flag = true,
    }
    return request
}

// Reserve a real line recipe with claims for its host, endpoints, and pen.
active_recipe_test_submit_line :: proc(
    t: ^testing.T,
    state: ^core.Euclid_General_State,
    request_id: u64) -> (
        bridge_scene.Bridge_Shape_Line_Result, operations.Active_Operation_Reservation) {
    line := bridge_scene.shape_create_line(state, {0.2, 0.3, 0}, {0.8, 0.7, 0},
        bridge_shape_test_input({}).style)
    pen, pen_status := shapes.world_create_pen(&state^.shape_world, {
        joint1 = {0.2, 0.3, 1.4},
        joint2 = {0.2, 0.3, 1.75},
        length = 0.35,
    })
    testing.expect_value(t, pen_status, shapemodel.Shape_World_Status.Ok)
    state^.world_pen = pen
    request: modifier.Modifier_Request = {
        kind = .Construct_Line,
        entity = line.shape,
        second_entity = line.first,
        third_entity = line.second,
        duration = 1,
        start_position = {0.2, 0.3, 0},
        second_position = {0.8, 0.7, 0},
        radius = 0.35,
        brush = 0.04,
        color_packed = 0xabcdef12,
    }
    submission := active_operation_test_submission(
        request_id, request, active_operation_test_claim(line.shape))
    submission.claim_count = 4
    submission.claims[1] = active_operation_test_claim(line.first)
    submission.claims[2] = active_operation_test_claim(line.second)
    submission.claims[3] = active_operation_test_claim(
        shapemodel.shape_entity_pack(state^.world_pen.shape))
    reservation, status := active_operation_submit_modifier(state, submission)
    testing.expect_value(t, status, operations.Active_Operation_Status.Ok)
    return line, reservation
}

// Begin one Julia scene transaction with matching active-operation generations.
active_operation_test_begin_julia_batch :: proc(
    state: ^core.Euclid_General_State, batch: ^bridge_scene.Scene_Command_Batch,
    runtime_generation: u64 = 3) {
    state^.julia_interface^.current_animation =
        &state^.julia_interface^.null_animation
    particles.formation_reset_generation(&state^.particle_system, 4)
    bridge_scene.begin_scene_command_batch(state, batch)
    batch^.runtime_generation = runtime_generation
    batch^.animation_generation = 4
    batch^.session_generation = 4
    batch^.tick_sequence = 1
}

// Build one ABI recipe for a one-second unit point translation.
active_operation_test_abi_request :: proc(
    entity: u64) -> Bridge_Native_Modifier_Request {
    return {
        kind = 1,
        entity = entity,
        duration = 1,
        displacement = {1, 0, 0},
    }
}

// Create one completed outcome for nonblocking mailbox-delivery tests.
active_operation_test_publish_outcome :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State,
    request_id: u64) -> operations.Active_Operation_Reservation {
    point := bridge_scene.shape_create_point(
        state, bridge_shape_test_input({0, 0, 0}))
    claim := active_operation_test_claim(point.entity)
    request: modifier.Modifier_Request = {
        kind = .Set_Point_Position,
        entity = point.entity,
        start_position = {1, 0, 0},
    }
    submission := active_operation_test_submission(request_id, request, claim)
    reservation, status := active_operation_submit_modifier(state, submission)
    testing.expect_value(t, status, operations.Active_Operation_Status.Ok)
    return reservation
}

// Start one claimed native operation and seed independent activity sources.
active_operation_test_begin_lifecycle_operation :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State,
    request_id, other_audio_id: u64) -> operations.Active_Operation_Reservation {
    point := bridge_scene.shape_create_point(
        state, bridge_shape_test_input({0, 0, 0}))
    claim := active_operation_test_claim(point.entity)
    request: modifier.Modifier_Request = {
        kind = .Set_Point_Position,
        entity = point.entity,
        duration = 1,
        displacement = {1, 0, 0},
    }
    submission := active_operation_test_submission(request_id, request, claim)
    reservation, status := active_operation_submit_modifier(state, submission)
    testing.expect_value(t, status, operations.Active_Operation_Status.Ok)
    testing.expect(t, audio.set_native_drawing_activity(
        &state^.chalk_audio, request_id, true))
    testing.expect(t, audio.set_native_drawing_activity(
        &state^.chalk_audio, other_audio_id, true))
    return reservation
}

// Keep the Julia inbox occupied until the outcome pump reports backpressure.
active_operation_test_fill_mailbox :: proc(
    t: ^testing.T, service: ^bridgemodel.Julia_Runtime_Service) {
    filler: bridgemodel.Runtime_Shutdown_Requested = {
        request_id = 1,
    }
    testing.expect_value(t, transport.consumer_mailbox_publish(
        &service^.julia_inbox, bridgemodel.Julia_Host_Ingress(filler)),
        bridgemodel.Communication_Send_Outcome.Sent)
}

// Release one delayed consumer message and return its typed outcome when present.
active_operation_test_release_mailbox_item :: proc(
    t: ^testing.T, service: ^bridgemodel.Julia_Runtime_Service) {
    message, received := transport.consumer_mailbox_try_recv(&service^.julia_inbox)
    testing.expect(t, received)
    transport.consumer_mailbox_release(&service^.julia_inbox, message)
}

// Assert one retained operation result crossed the bounded inbox intact.
active_operation_test_expect_delivered_outcome :: proc(
    t: ^testing.T, service: ^bridgemodel.Julia_Runtime_Service,
    request_id: u64) {
    message, received := transport.consumer_mailbox_try_recv(&service^.julia_inbox)
    testing.expect(t, received)
    outcome, found := message^.(bridgemodel.Active_Operation_Outcome_Ready)
    testing.expect(t, found)
    testing.expect_value(t, outcome.request_id, request_id)
    testing.expect(t, outcome.outcome_generation > 0)
    transport.consumer_mailbox_release(&service^.julia_inbox, message)
}

// Close test transport and detach it before the state owner is destroyed.
active_operation_test_close_mailbox :: proc(
    state: ^core.Euclid_General_State,
    service: ^bridgemodel.Julia_Runtime_Service) {
    state^.julia_runtime_service = nil
    transport.consumer_mailbox_destroy(&service^.julia_inbox)
}

// Release the interface and inline active-operation storage owned by the test state.
active_operation_test_destroy :: proc(state: ^core.Euclid_General_State) {
    operations.active_operation_storage_destroy(&state^.active_operations)
    bridge_reveal_test_state_destroy(state)
}

// Return the entity claim used by modifier-backed point operations.
active_operation_test_claim :: proc(
    entity: u64) -> operations.Active_Operation_Claim {
    return {
        kind = operations.ACTIVE_OPERATION_CLAIM_ENTITY,
        identity = entity,
    }
}

// Assemble borrowed submission input for one bounded modifier admission.
active_operation_test_submission :: proc(
    request_id: u64, request: modifier.Modifier_Request,
    claim: operations.Active_Operation_Claim) ->
        operations.Active_Operation_Submission_Request {
    submission: operations.Active_Operation_Submission_Request = {
        kind = 1,
        request_id = request_id,
        session_generation = 2,
        runtime_generation = 3,
        animation_generation = 4,
        modifier_request = request,
    }
    submission.claim_count = 1
    submission.claims[0] = claim
    return submission
}

// Reuse a completed execution slot while its prior outcome remains pending.
active_operation_test_immediate_reuse :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State, entity: u64,
    claim: operations.Active_Operation_Claim) -> operations.Active_Operation_Reservation {
    request: modifier.Modifier_Request = {
        kind = .Set_Point_Position,
        entity = entity,
        start_position = {1, 0, 0},
    }
    submission := active_operation_test_submission(52, request, claim)
    reservation, status := active_operation_submit_modifier(state, submission)
    testing.expect_value(t, status, operations.Active_Operation_Status.Ok)
    return reservation
}

// Verify one correlated result and release its bounded delivery reservation.
active_operation_test_expect_outcome :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State,
    handle: operations.Active_Operation_Outcome_Handle,
    expected: operations.Active_Operation_Outcome_State) {
    outcome, status := operations.active_operation_read_outcome(
        &state^.active_operations, handle)
    testing.expect_value(t, status, operations.Active_Operation_Status.Ok)
    testing.expect_value(t, outcome.state, expected)
    testing.expect_value(t, operations.active_operation_mark_outcome_sent(
        &state^.active_operations, handle), operations.Active_Operation_Status.Ok)
    testing.expect_value(t, operations.active_operation_acknowledge_outcome(
        &state^.active_operations, handle), operations.Active_Operation_Status.Ok)
}

// Assert one live execution still owns its exclusive entity claim.
active_operation_test_expect_live_claim :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State,
    handle: operations.Active_Operation_Handle) {
    progress, live := operations.active_operation_observe(
        &state^.active_operations, handle)
    testing.expect(t, live)
    claim := active_operation_test_claim(progress.modifier_request.entity)
    claims: [1]operations.Active_Operation_Claim
    claims[0] = claim
    testing.expect(t, operations.active_operation_claims_conflict(
        &state^.active_operations, claims[:]))
}

// Capture an in-flight Julia write, then verify its later commit sees native claims.
active_operation_test_reject_julia_write :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State, entity: u64) {
    state^.julia_interface^.current_animation =
        &state^.julia_interface^.null_animation
    batch: bridge_scene.Scene_Command_Batch
    bridge_scene.begin_scene_command_batch(state, &batch)
    status := bridge_scene.shape_set_position(state, entity, {9, 9, 9})
    bridge_scene.end_scene_command_batch(state)
    testing.expect_value(t, status, i32(bridgemodel.BRIDGE_STATUS_OK))
    testing.expect(t, !bridge_scene.commit_scene_command_batch(state, &batch))
}

package julia_host

import bridge_scene "../scene"

import bridgemodel "../model"
import core "../../core"
import geometry "../../core/geometry"
import shapemodel "../../shapes/model"
import trace "../../evidence/trace"
import "core:math"
import "core:testing"
import modifier "../../animation"

// Verify XYZW transport, snapshot isolation, rejected values, and suffix lifetime.
@(test)
bridge_shape_orientation_transport_and_lifetime :: proc(t: ^testing.T) {
    state := bridge_shape_test_state()
    defer free(state, context.allocator)
    world := &state.shape_world
    testing.expect_value(t, shapemodel.shape_world_freeze_baseline(world),
        shapemodel.Shape_World_Status.Ok)
    arc := bridge_scene.shape_create_arc(
        state, {}, {1, 0.25, 2}, bridge_shape_test_input({}).style)
    testing.expect_value(t, bridge_scene.shape_get_view(state, arc.shape).kind, i32(2))
    testing.expect_value(t,
        bridge_scene.shape_get_orientation(state, arc.shape).orientation,
        [4]f32{0, 0, 0, 1})
    snapshot := new(bridgemodel.Animation_Query_Snapshot, context.allocator)
    defer free(snapshot, context.allocator)
    bridge_scene.capture_animation_query_snapshot(state, snapshot)
    sine := math.sqrt(f32(0.5))
    testing.expect_value(t,
        bridge_scene.shape_set_orientation(state, arc.shape, {sine, 0, 0, sine}),
        i32(bridgemodel.BRIDGE_STATUS_OK))
    testing.expect_value(t,
        bridge_scene.shape_get_orientation(state, arc.shape).orientation,
        [4]f32{sine, 0, 0, sine})
    state.animation_query_snapshot_target = snapshot
    testing.expect_value(t,
        bridge_scene.shape_get_orientation(state, arc.shape).orientation,
        [4]f32{0, 0, 0, 1})
    state.animation_query_snapshot_target = nil
    bridge_shape_orientation_assert_rejections(t, state, arc.shape)

    testing.expect_value(t, bridge_scene.shape_get_arc(state, arc.shape).arc,
        shapemodel.Bridge_Arc_Geometry{1, 0.25, 2})
    testing.expect_value(t, shapemodel.shape_world_rewind_animation(world),
        shapemodel.Shape_World_Status.Ok)
    testing.expect_value(t, world.orientations.count, u16(0))
    testing.expect_value(t, bridge_scene.shape_get_orientation(state, arc.shape).status,
        i32(bridgemodel.BRIDGE_STATUS_NOT_FOUND))
}

// Reject zero, non-unit, and non-finite orientations at the native boundary.
bridge_shape_orientation_assert_rejections :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State, shape: u64) {
    invalid := [?][4]f32{{}, {0, 0, 0, 2}, {math.nan_f32(), 0, 0, 1}}
    for rejected in invalid {
        testing.expect_value(t, bridge_scene.shape_set_orientation(
            state, shape, rejected), i32(bridgemodel.BRIDGE_STATUS_INVALID_ARGUMENT))
    }
}

// Commit native point/plane samples together, then reject an incomplete tilt atomically.
@(test)
bridge_native_plane_transactions_validate_proposed_outputs :: proc(t: ^testing.T) {
    state := bridge_shape_test_state()
    defer free(state, context.allocator)
    state.julia_interface = new(bridgemodel.Euclid_Julia_Interface, context.allocator)
    defer free(state.julia_interface, context.allocator)
    state.julia_interface.current_animation = &state.julia_interface.null_animation
    region := bridge_scene.shape_create_circle_region(state, {}, {1, 0, 0},
        {0, 1, 1}, bridge_shape_test_input({}).style)
    rotation: modifier.Modifier_Request = {
        kind = .Rotate_Point,
        entity = region.second_center,
        start_position = {1, 0, 0},
        axis_b = {0, 1, 0},
        angle = math.PI / 2,
        duration = 1,
        elapsed = 1,
    }
    plane := rotation
    plane.kind = .Rotate_Shape_Orientation
    plane.entity = region.shape
    plane.scalar = 1
    batch: bridge_scene.Scene_Command_Batch
    bridge_scene.begin_native_scene_command_batch(state, &batch)
    capture_native_plane_test_request(t, state, rotation)
    capture_native_plane_test_request(t, state, plane)
    bridge_scene.end_scene_command_batch(state)
    testing.expect(t, bridge_scene.commit_scene_command_batch(state, &batch))
    position := bridge_scene.shape_get_view(state, region.second_center).position
    testing.expect(t, math.abs(position.z + 1) < 0.000001)
    orientation := bridge_scene.shape_get_orientation(state, region.shape).orientation
    plane.angle = 0
    bridge_scene.begin_native_scene_command_batch(state, &batch)
    capture_native_plane_test_request(t, state, plane)
    bridge_scene.end_scene_command_batch(state)
    testing.expect(t, !bridge_scene.commit_scene_command_batch(state, &batch))
    testing.expect_value(t,
        bridge_scene.shape_get_orientation(state, region.shape).orientation, orientation)
    testing.expect_value(t,
        bridge_scene.shape_get_view(state, region.second_center).position, position)
}

// Preserve native/direct FIFO order in the final plane and reject stale native targets.
@(test)
bridge_native_orientation_obeys_direct_order_and_identity :: proc(t: ^testing.T) {
    state := bridge_shape_test_state()
    defer free(state, context.allocator)
    state.julia_interface = new(bridgemodel.Euclid_Julia_Interface, context.allocator)
    defer free(state.julia_interface, context.allocator)
    state.julia_interface.current_animation = &state.julia_interface.null_animation
    arc := bridge_scene.shape_create_arc(
        state, {}, {0.1, 0, 1}, bridge_shape_test_input({}).style)
    state.evidence_session.enabled = true
    state.evidence_session.lanes = {.Domain}
    trace.ring_init(&state.evidence_ring, .Display)
    request: modifier.Modifier_Request = {
        kind = .Rotate_Shape_Orientation,
        entity = arc.shape,
        axis_b = {1, 0, 0},
        angle = math.PI,
        elapsed = 1,
        duration = 1,
        scalar = 1,
    }
    batch: bridge_scene.Scene_Command_Batch
    bridge_scene.begin_native_scene_command_batch(state, &batch)
    capture_native_plane_test_request(t, state, request)
    testing.expect_value(t,
        bridge_scene.shape_set_orientation(state, arc.shape, {0, 0, 0, 1}),
        i32(bridgemodel.BRIDGE_STATUS_OK))
    bridge_scene.end_scene_command_batch(state)
    testing.expect(t, bridge_scene.commit_scene_command_batch(state, &batch))
    testing.expect_value(t,
        bridge_scene.shape_get_orientation(state, arc.shape).orientation,
        [4]f32{0, 0, 0, 1})
    request.entity = 1
    bridge_scene.begin_native_scene_command_batch(state, &batch)
    _ = bridge_scene.shape_set_position(state, arc.shape, {0.5, 0.5, 0})
    capture_native_plane_test_request(t, state, request)
    bridge_scene.end_scene_command_batch(state)
    testing.expect(t, !bridge_scene.commit_scene_command_batch(state, &batch))
    testing.expect_value(t,
        bridge_scene.shape_get_view(state, arc.shape).position, geometry.Vector3{})
    testing.expect_value(t, state.evidence_ring.count, 2)
    testing.expect_value(t,
        state.evidence_ring.events[0].kind, trace.Kind.Shape_Orientation_Committed)
    testing.expect_value(t,
        state.evidence_ring.events[0].producer, trace.Producer.Display)
}

// Capture proposed native edits without committing away their shared plane boundary.
capture_native_plane_test_request :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State,
    request: modifier.Modifier_Request) {
    command, captured := bridge_scene.append_scene_command(state, .Apply_Native_Modifier)
    testing.expect(t, captured && command != nil)
    command.modifier = request
}

// Verify a coherent region tilt commits while independent incompatible edits roll back.
@(test)
bridge_shape_orientation_transactions_validate_final_plane :: proc(t: ^testing.T) {
    state := bridge_shape_test_state()
    defer free(state, context.allocator)
    state.julia_interface = new(bridgemodel.Euclid_Julia_Interface, context.allocator)
    defer free(state.julia_interface, context.allocator)
    state.julia_interface.current_animation = &state.julia_interface.null_animation
    region := bridge_scene.shape_create_circle_region(state, {}, {1, 0, 0},
        {0, 1, 1}, bridge_shape_test_input({}).style)
    testing.expect_value(t, region.status, i32(bridgemodel.BRIDGE_STATUS_OK))
    testing.expect_value(t,
        bridge_scene.shape_set_position(state, region.second_center, {0, 0, -1}),
        i32(bridgemodel.BRIDGE_STATUS_INVALID_ARGUMENT))
    sine := math.sqrt(f32(0.5))
    testing.expect_value(t, bridge_scene.shape_set_orientation(state, region.shape,
        {0, sine, 0, sine}), i32(bridgemodel.BRIDGE_STATUS_INVALID_ARGUMENT))
    batch: bridge_scene.Scene_Command_Batch
    bridge_scene.begin_native_scene_command_batch(state, &batch)
    _ = bridge_scene.shape_set_position(state, region.second_center, {0, 0, -1})
    _ = bridge_scene.shape_set_orientation(state, region.shape, {0, sine, 0, sine})
    bridge_scene.end_scene_command_batch(state)
    testing.expect(t, bridge_scene.commit_scene_command_batch(state, &batch))
    testing.expect_value(t,
        bridge_scene.shape_get_view(state, region.second_center).position,
        geometry.Vector3{0, 0, -1})
    kind, payload := bridge_scene.scene_command_evidence(&batch.commands[1])
    testing.expect_value(t, kind, trace.Kind.Shape_Orientation_Committed)
    testing.expect_value(t, payload.point.point_index,
        shapemodel.shape_entity_unpack(region.shape).slot - 1)
    bridge_shape_orientation_assert_invalid_plane_rollback(
        t, state, &batch, region.first_center, region.second_center)
}

// Verify incompatible center edits reject atomically after a successful tilt.
bridge_shape_orientation_assert_invalid_plane_rollback :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State,
    batch: ^bridge_scene.Scene_Command_Batch, first_center, second_center: u64) {
    bridge_scene.begin_native_scene_command_batch(state, batch)
    _ = bridge_scene.shape_set_position(state, first_center, {0, 1, 0})
    _ = bridge_scene.shape_set_position(state, second_center, {1, 0, 0})
    bridge_scene.end_scene_command_batch(state)
    testing.expect(t, !bridge_scene.commit_scene_command_batch(state, batch))
    testing.expect_value(t,
        bridge_scene.shape_get_view(state, first_center).position,
        geometry.Vector3{})
    testing.expect_value(t,
        bridge_scene.shape_get_view(state, second_center).position,
        geometry.Vector3{0, 0, -1})
}

// Validate rail and scalar edits together regardless of their command order.
@(test)
bridge_cycloid_transactions_validate_final_metric :: proc(t: ^testing.T) {
    state := bridge_shape_test_state()
    defer free(state, context.allocator)
    state.julia_interface = new(bridgemodel.Euclid_Julia_Interface, context.allocator)
    defer free(state.julia_interface, context.allocator)
    state.julia_interface.current_animation = &state.julia_interface.null_animation
    cycloid := bridge_scene.shape_create_cycloid(state, {}, {1, 0, 0},
        {0.1, 0.1, 0, 0, 5, 5}, bridge_shape_test_input({}).style)
    testing.expect_value(t, cycloid.status, i32(bridgemodel.BRIDGE_STATUS_OK))
    testing.expect_value(t, bridge_scene.shape_set_cycloid(state, cycloid.shape,
        {0.3, 0.1, 0, 0, 5, 5}), i32(bridgemodel.BRIDGE_STATUS_INVALID_ARGUMENT))
    batch: bridge_scene.Scene_Command_Batch
    bridge_scene.begin_native_scene_command_batch(state, &batch)
    _ = bridge_scene.shape_set_cycloid(state, cycloid.shape, {0.3, 0.1, 0, 0, 5, 5})
    _ = bridge_scene.shape_set_position(state, cycloid.second, {2, 0, 0})
    bridge_scene.end_scene_command_batch(state)
    testing.expect(t, bridge_scene.commit_scene_command_batch(state, &batch))
    testing.expect_value(t,
        bridge_scene.shape_get_cycloid(state, cycloid.shape).geometry.rolling_radius,
        f32(0.3))
    bridge_scene.begin_native_scene_command_batch(state, &batch)
    _ = bridge_scene.shape_set_position(state, cycloid.second, {1, 0, 0})
    _ = bridge_scene.shape_set_cycloid(state, cycloid.shape, {0.4, 0.1, 0, 0, 5, 5})
    bridge_scene.end_scene_command_batch(state)
    testing.expect(t, !bridge_scene.commit_scene_command_batch(state, &batch))
    testing.expect_value(t, bridge_scene.shape_get_view(state, cycloid.second).position,
        geometry.Vector3{2, 0, 0})
}

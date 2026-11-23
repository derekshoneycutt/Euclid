package julia_host

import bridge_scene "../scene"

import bridgemodel "../model"

import modifier "../../animation"
import core "../../core"
import curve "../../shapes/curve"
import shapes "../../shapes"
import shapemodel "../../shapes/model"
import "core:math"
import "core:testing"
import "core:os"

// Keep rolling setup usable when switching between conics and named rolling content.
@(test)
native_rolling_placement_uses_the_quiesced_lifecycle_owner :: proc(t: ^testing.T) {
    state := native_rolling_test_state(t)
    defer free(state, context.allocator)
    service := new(Julia_Runtime_Service, context.allocator)
    defer free(service, context.allocator)
    state.julia_runtime_service = service
    service.owner_thread_id = os.get_current_thread_id()
    service.animation_lifecycle_slot.state = .Pending
    service.animation_lifecycle_slot.host_state = state
    kinds := [?]modifier.Modifier_Kind{.Cycloid_Place, .Trochoid_Place}
    for kind in kinds {
        request := native_rolling_test_request(kind)
        request.displacement = {0.2, 0.08, 0.3}
        testing.expect_value(t,
            bridge_scene.apply_native_lifecycle_placement(state, request),
            i32(bridgemodel.BRIDGE_STATUS_OK))
    }
    testing.expect_value(t, state.shape_world.cycloid_tools.values[0].parameter, f32(-1))
    testing.expect_value(t, state.shape_world.trochoid_tools.values[0].parameter, f32(-1))
    service.animation_lifecycle_slot.state = .Free
    testing.expect_value(t, bridge_scene.apply_native_lifecycle_placement(
        state, native_rolling_test_request(.Cycloid_Place)),
        i32(bridgemodel.BRIDGE_STATUS_ILLEGAL_STATE))
}

// Establish permanent guides with deliberately different geometry from later samples.
native_rolling_test_state :: proc(t: ^testing.T) -> ^core.Euclid_General_State {
    state := native_tool_test_state()
    cycloid_status, trochoid_status: shapemodel.Shape_World_Status
    state.world_cycloid_tool, cycloid_status = shapes.world_create_cycloid_tool(
        &state.shape_world, {
            first = {0.4, 0.5, 0},
            second = {0.6, 0.5, 0},
            rolling_radius = 0.02,
            parameter_start = 0,
            parameter_finish = 1,
        })
    state.world_trochoid_tool, trochoid_status = shapes.world_create_trochoid_tool(
        &state.shape_world, {
            fixed_radius = 0.1,
            rolling_radius = 0.02,
        })
    testing.expect_value(t, cycloid_status, shapemodel.Shape_World_Status.Ok)
    testing.expect_value(t, trochoid_status, shapemodel.Shape_World_Status.Ok)
    return state
}

// Copy one partial reversed-domain sample, leaving lifecycle and clocks to Julia.
native_rolling_test_request :: proc(
    kind: modifier.Modifier_Kind) -> modifier.Modifier_Request {
    return {
        kind = kind,
        elapsed = 0.5,
        duration = 1,
        start_position = {0.1, 0.2, 0},
        second_position = {0.9, 0.8, 0},
        third_position = {2, -2, -1},
        displacement = {0.05, 0.3, 0},
        radius = 0.05,
        scalar = 0.6,
        brush = 5,
        color_packed = 0xff123456,
    }
}

// Verify a real Cycloid host keeps orientation and rail identities while publishing ink.
@(test)
native_cycloid_publishes_complete_guide_samples_and_preserves_host_orientation :: proc(
    t: ^testing.T) {
    state := native_rolling_test_state(t)
    defer free(state, context.allocator)
    request := native_rolling_test_request(.Cycloid_Draw)
    host := bridge_scene.shape_create_cycloid(
        state, request.start_position, request.second_position, {
            rolling_radius = request.radius,
            tracer_distance = request.displacement.x,
            tracer_phase = request.displacement.y,
            parameter_start = 2,
            parameter_finish = -2,
            draw_parameter = 2,
        }, bridge_shape_test_input({}).style)
    testing.expect_value(t, host.status, i32(bridgemodel.BRIDGE_STATUS_OK))
    request.entity = host.shape
    sine := math.sqrt(f32(0.5))
    testing.expect_value(t,
        bridge_scene.shape_set_orientation(
            state, host.shape, {0.8 * sine, 0.6 * sine, 0, sine}),
        i32(bridgemodel.BRIDGE_STATUS_OK))
    orientation := bridge_scene.shape_get_orientation(state, host.shape).orientation
    native_tool_test_sample(t, state, request)
    actual, found := shapemodel.shape_component_get(&state.shape_world.cycloids,
        &state.shape_world.registry, shapemodel.shape_entity_unpack(host.shape))
    testing.expect(t, found && actual.draw_parameter == 0.5)
    testing.expect_value(t,
        bridge_scene.shape_get_orientation(state, host.shape).orientation,
        orientation)
    expect_native_tool_position(t,
        bridge_scene.get_compass_joint2_position(state), curve.cycloid_point(
            request.start_position, request.second_position, actual^, 0.5))
    expect_native_tool_position(t, native_shape_test_position(t, state, host.first),
        request.start_position)
    native_expect_cycloid_guide(t, state, request)
}

// Check complete guide state and preserved interpolation history after publication.
native_expect_cycloid_guide :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State,
    request: modifier.Modifier_Request) {
    guide, found := shapemodel.shape_component_get(&state.shape_world.cycloid_tools,
        &state.shape_world.registry, state.world_cycloid_tool.shape)
    testing.expect(t, found)
    testing.expect_value(t, guide.parameter_start, f32(2))
    testing.expect_value(t, guide.parameter_finish, f32(-2))
    testing.expect_value(t, guide.parameter, f32(0.5))
    testing.expect_value(t, guide.orientation_phase, f32(0.3))
    testing.expect_value(t, guide.previous_rolling_radius, f32(0.02))
    expect_native_tool_position(t,
        native_shape_test_position(t, state,
            shapemodel.shape_entity_pack(state.world_cycloid_tool.first)),
        request.start_position)
    lock, found_lock := bridge_scene.tool_lock_constraint(
        state, state.world_compass.joint2)
    testing.expect(t, found_lock && lock.enabled)
}

// Verify both modes retain exact frontiers, host rotation, brush, and guide phase.
@(test)
native_trochoid_publishes_both_ring_modes_and_exact_completion :: proc(t: ^testing.T) {
    state := native_rolling_test_state(t)
    defer free(state, context.allocator)
    for mode in 0..<2 {
        request := native_rolling_test_request(.Trochoid_Draw)
        request.displacement, request.angle, request.integer = {0.2, 0.08, 0.3}, 0.4, mode
        host := bridge_scene.shape_create_trochoid(state, request.start_position, {
            mode = i32(mode),
            fixed_radius = 0.2,
            rolling_radius = 0.05,
            tracer_distance = 0.08,
            rotation = 0.4,
            tracer_phase = 0.3,
            parameter_start = 2,
            parameter_finish = -2,
            draw_parameter = 2,
        }, bridge_shape_test_input({}).style)
        testing.expect_value(t, host.status, i32(bridgemodel.BRIDGE_STATUS_OK))
        request.entity, request.elapsed = host.shape, 1
        native_tool_test_sample(t, state, request)
        actual, found := shapemodel.shape_component_get(&state.shape_world.trochoids,
            &state.shape_world.registry, shapemodel.shape_entity_unpack(host.shape))
        testing.expect(t, found && actual.draw_parameter == -1 && actual.rotation == 0.4)
        expect_native_tool_position(t, bridge_scene.get_compass_joint2_position(state),
            curve.trochoid_point(request.start_position, actual^, -1))
        native_expect_trochoid_guide(t, state, request)
    }
}

// Check synchronized ring values and caller-owned visibility after a native draw.
native_expect_trochoid_guide :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State,
    request: modifier.Modifier_Request) {
    guide, found := shapemodel.shape_component_get(&state.shape_world.trochoid_tools,
        &state.shape_world.registry, state.world_trochoid_tool.shape)
    testing.expect(t,
        found && guide.mode == shapemodel.Shape_Trochoid_Mode(request.integer))
    testing.expect_value(t, guide.parameter, f32(-1))
    testing.expect_value(t, guide.rotation, f32(0.4))
    testing.expect_value(t, guide.orientation_phase, f32(0.3))
    style, found_style := shapemodel.shape_component_get(&state.shape_world.render_styles,
        &state.shape_world.registry, state.world_trochoid_tool.shape)
    testing.expect(t, found_style && !style.visible)
    testing.expect_value(t, bridge_scene.native_modifier_tool_contact_count(request), 2)
}

// Reject a missing curve before mutating either permanent guide or compass joint.
@(test)
native_rolling_rejects_stale_hosts_transactionally :: proc(t: ^testing.T) {
    state := native_rolling_test_state(t)
    defer free(state, context.allocator)
    request := native_rolling_test_request(.Cycloid_Draw)
    request.entity = 99999
    before := bridge_scene.get_compass_joint2_position(state)
    command: bridge_scene.Scene_Command = {
        kind = .Apply_Native_Modifier,
        modifier = request,
    }
    testing.expect(t, !bridge_scene.validate_native_modifier_marker(state, &command))
    testing.expect_value(t, bridge_scene.get_compass_joint2_position(state), before)
    guide, _ := shapemodel.shape_component_get(&state.shape_world.cycloid_tools,
        &state.shape_world.registry, state.world_cycloid_tool.shape)
    testing.expect_value(t, guide.parameter_finish, f32(1))
}

// Verify every rolling discriminator reaches its native sampled family.
@(test)
native_rolling_abi_kinds_are_closed :: proc(t: ^testing.T) {
    kinds: [8]modifier.Modifier_Kind = {
        .Cycloid_Place, .Cycloid_Descend, .Cycloid_Draw, .Cycloid_Rise,
        .Trochoid_Place, .Trochoid_Descend, .Trochoid_Draw, .Trochoid_Rise,
    }
    for kind, index in kinds {
        actual, valid := native_modifier_kind_from_abi(i32(index + 30))
        testing.expect(t, valid)
        testing.expect_value(t, actual, kind)
    }
}

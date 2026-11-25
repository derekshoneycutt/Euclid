package julia_host

import bridge_scene "../scene"

import bridgemodel "../model"

import modifier "../../animation"
import core "../../core"
import shapemodel "../../shapes/model"
import "core:testing"
import "core:os"

// Admit only setup on the quiesced lifecycle owner, rejecting ordinary uncaptured work.
@(test)
native_conic_lifecycle_placement_requires_the_owner_handoff :: proc(t: ^testing.T) {
    state := native_conic_test_state(t)
    defer bridge_conic_test_destroy(state)
    service := new(Julia_Runtime_Service, context.allocator)
    defer free(service, context.allocator)
    state.julia_runtime_service = service
    request: modifier.Modifier_Request = {
        kind = .Parabola_Place,
        start_position = {0.4, 0.5, 0},
        third_position = {-1, 0, -1},
        scalar = 1.2,
    }
    testing.expect_value(t, bridge_scene.apply_native_lifecycle_placement(state, request),
        i32(bridgemodel.BRIDGE_STATUS_ILLEGAL_STATE))
    service.owner_thread_id = os.get_current_thread_id()
    service.reload_state = .Quiescing
    service.animation_lifecycle_slot.state = .Pending
    service.animation_lifecycle_slot.host_state = state
    testing.expect_value(t, bridge_scene.apply_native_lifecycle_placement(state, request),
        i32(bridgemodel.BRIDGE_STATUS_OK))
    testing.expect_value(t, state.shape_world.parabola_tools.values[0].parameter, f32(-1))
    request.kind = .Parabola_Descend
    testing.expect_value(t, bridge_scene.apply_native_lifecycle_placement(state, request),
        i32(bridgemodel.BRIDGE_STATUS_ILLEGAL_STATE))
    request.kind, service.animation_tick_pending = .Parabola_Place, true
    testing.expect_value(t, bridge_scene.apply_native_lifecycle_placement(state, request),
        i32(bridgemodel.BRIDGE_STATUS_ILLEGAL_STATE))
}

// Use real permanent apparatus and native conic hosts in owner-boundary tests.
native_conic_test_state :: proc(t: ^testing.T) -> ^core.Euclid_General_State {
    state := bridge_conic_test_state()
    bridge_conic_test_create_tools(t, state)
    return state
}

// Capture one native sample in the ordinary scene batch and commit it at its owner.
native_conic_test_sample :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State,
    request: modifier.Modifier_Request) {
    batch: bridge_scene.Scene_Command_Batch
    bridge_scene.begin_native_scene_command_batch(state, &batch)
    command, captured := bridge_scene.append_scene_command(state, .Apply_Native_Modifier)
    testing.expect(t, captured && command != nil)
    command.modifier = request
    bridge_scene.end_scene_command_batch(state)
    drawing := request.kind == .Parabola_Draw || request.kind == .Hyperbola_Draw
    testing.expect_value(t,
        bridge_scene.scene_command_batch_has_drawing_activity(&batch), drawing)
    testing.expect(t, bridge_scene.commit_scene_command_batch(state, &batch))
}

// Preserve host orientation, configured linkage, brush and exact reversed frontier.
@(test)
native_parabola_publishes_synchronized_pose_and_frontier :: proc(t: ^testing.T) {
    state := native_conic_test_state(t)
    defer bridge_conic_test_destroy(state)
    host := bridge_scene.shape_create_parabola(state, {0.4, 0.5, 0},
        {0.075, 0.6, 1, -1, 1}, bridge_shape_test_input({}).style)
    testing.expect_value(t, host.status, i32(bridgemodel.BRIDGE_STATUS_OK))
    _ = bridge_scene.set_parabola_tool_geometry(state, {0.075, 0.16, 0.6, 1, -1, 1})
    testing.expect_value(t,
        bridge_scene.shape_set_orientation(state, host.shape, {0.6, 0, 0, 0.8}),
        i32(bridgemodel.BRIDGE_STATUS_OK))
    orientation := bridge_scene.shape_get_orientation(state, host.shape).orientation
    native_conic_test_sample(t, state, {
        kind = .Parabola_Draw,
        entity = host.shape,
        elapsed = 0.5,
        duration = 1,
        start_position = {0.4, 0.5, 0},
        third_position = {1, 0, -0.5},
        radius = 0.075,
        angle = 0.6,
        color_packed = 0xff123456,
    })
    testing.expect_value(t,
        bridge_scene.shape_get_parabola(state, host.shape).geometry.draw_parameter,
        f32(0.25))
    testing.expect_value(t,
        bridge_scene.shape_get_orientation(state, host.shape).orientation, orientation)
    guide := state.shape_world.parabola_tools.values[0]
    testing.expect(t, guide.active && guide.parameter == 0.25 && guide.rotation == 0.6)
    testing.expect_value(t, guide.link_length, f32(0.16))
    testing.expect_value(t, guide.previous_parameter, f32(0))
    testing.expect_value(t, native_shape_test_position(t, state,
        shapemodel.shape_entity_pack(state.world_parabola_tool)),
        native_shape_test_position(t, state, host.shape))
}

// One common frontier moves both carriages while immutable selection controls contact.
@(test)
native_hyperbola_publishes_all_branch_selections_and_inactive_rise :: proc(
    t: ^testing.T) {
    state := native_conic_test_state(t)
    defer bridge_conic_test_destroy(state)
    for selection in 0..<3 {
        host := bridge_scene.shape_create_hyperbola(state, {0.5, 0.5, 0},
            {0.12, 0.1, 0.6, 1, -1, 1}, bridge_shape_test_input({}).style,
            shapemodel.Hyperbola_Branches(selection))
        testing.expect_value(t, host.status, i32(bridgemodel.BRIDGE_STATUS_OK))
        _ = bridge_scene.set_hyperbola_tool_geometry(
            state, {0.12, 0.1, 0.6, 1, -1, 1, 0.4})
        request: modifier.Modifier_Request = {
            kind = .Hyperbola_Draw,
            entity = host.shape,
            elapsed = 1,
            duration = 1,
            start_position = {0.5, 0.5, 0},
            third_position = {1, 0, -0.5},
            radius = 0.12,
            displacement = {0.1, 0, 0},
            angle = 0.6,
            integer = selection,
            color_packed = 0xff123456,
        }
        native_conic_test_sample(t, state, request)
        native_expect_hyperbola_sample(t, state, host.shape, selection)
        request.kind, request.third_position.x, request.scalar =
            .Hyperbola_Rise, -0.5, 1.2
        native_conic_test_sample(t, state, request)
        testing.expect_value(t,
            state.shape_world.hyperbola_tools.values[0].active_branches,
            shapemodel.Hyperbola_Branches.None)
    }
}

// Keep selected ink and apparatus rotation in the native owner after completion.
native_expect_hyperbola_sample :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State, host: u64, selection: int) {
    actual := bridge_scene.shape_get_hyperbola(state, host)
    testing.expect_value(t, actual.branches, shapemodel.Hyperbola_Branches(selection))
    testing.expect_value(t, actual.geometry.draw_parameter, f32(-0.5))
    guide := state.shape_world.hyperbola_tools.values[0]
    testing.expect_value(t,
        guide.active_branches, shapemodel.Hyperbola_Branches(selection))
    testing.expect_value(t, guide.parameter, f32(-0.5))
    testing.expect_value(t, guide.rotation, f32(0.6))
    testing.expect_value(t, guide.rail_half_length, f32(0.4))
}

// Invalid hosts and tool parameters reject the whole sample without partial mutation.
@(test)
native_conic_rejection_is_transactional :: proc(t: ^testing.T) {
    state := native_conic_test_state(t)
    defer bridge_conic_test_destroy(state)
    command: bridge_scene.Scene_Command = {
        kind = .Apply_Native_Modifier,
        modifier = {
            kind = .Parabola_Draw,
            entity = 99999,
            elapsed = 1,
            duration = 1,
            third_position = {1, 0, -1},
            radius = 0.075,
        },
    }
    before := state.shape_world.parabola_tools.values[0]
    testing.expect(t, !bridge_scene.validate_native_modifier_marker(state, &command))
    command.modifier.kind = .Parabola_Place
    command.modifier.third_position.x = 10
    testing.expect(t, !bridge_scene.validate_native_modifier_marker(state, &command))
    testing.expect_value(t, state.shape_world.parabola_tools.values[0], before)
}

// Keep conic and construction ABI discriminators symmetric.
@(test)
native_conic_abi_kinds_are_closed :: proc(t: ^testing.T) {
    kinds: [8]modifier.Modifier_Kind = {
        .Parabola_Place, .Parabola_Descend, .Parabola_Draw, .Parabola_Rise,
        .Hyperbola_Place, .Hyperbola_Descend, .Hyperbola_Draw, .Hyperbola_Rise,
    }
    for kind, index in kinds {
        actual, valid := native_modifier_kind_from_abi(i32(index + 38))
        testing.expect(t, valid)
        testing.expect_value(t, actual, kind)
    }
    construction_kinds: [4]modifier.Modifier_Kind = {
        .Construct_Point, .Construct_Line, .Construct_Circle,
        .Construct_Filled_Circle,
    }
    for kind, index in construction_kinds {
        actual, valid := native_modifier_kind_from_abi(i32(index + 47))
        testing.expect(t, valid)
        testing.expect_value(t, actual, kind)
    }
    sequence_kinds: [2]modifier.Modifier_Kind = {
        .Pen_Highlight, .Compass_Highlight_Sequence,
    }
    for kind, index in sequence_kinds {
        actual, valid := native_modifier_kind_from_abi(i32(index + 51))
        testing.expect(t, valid)
        testing.expect_value(t, actual, kind)
    }
    _, valid := native_modifier_kind_from_abi(53)
    testing.expect(t, !valid)
}

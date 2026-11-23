package julia_host

import bridge_scene "../scene"

import modifier "../../animation"
import bridgemodel "../model"
import core "../../core"
import geometry "../../core/geometry"
import shapes "../../shapes"
import shapemodel "../../shapes/model"
import testing "core:testing"
import math "core:math"

// Read a defining point after native publication and ordinary constraint solving.
native_shape_test_position :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State, packed: u64) -> geometry.Vector3 {
    transform, found := shapemodel.shape_component_get(
        &state^.shape_world.transforms, &state^.shape_world.registry,
        shapemodel.shape_entity_unpack(packed))
    testing.expect(t, found)
    return transform.position
}

// Verify an extension publishes the original anchor and the sampled moving endpoint.
@(test)
native_extension_publishes_real_line_geometry :: proc(t: ^testing.T) {
    state := native_tool_test_state()
    defer free(state, context.allocator)
    line := bridge_scene.shape_create_line(state, {0.2, 0.3, 0}, {0.4, 0.3, 0},
        bridge_shape_test_input({}).style)
    native_tool_test_sample(t, state, {
        kind = .Extend_Line,
        entity = line.shape,
        second_entity = line.first,
        third_entity = line.second,
        elapsed = 0.5,
        duration = 1,
        start_position = {0.4, 0.3, 0},
        second_position = {0.6, 0.3, 0},
        third_position = {0.2, 0.3, 0},
        radius = 0.14,
        angle = f32(math.PI / 3),
        brush = 0.01,
    })
    expect_native_tool_position(t, native_shape_test_position(t, state, line.first),
        geometry.Vector3{0.2, 0.3, 0})
    expect_native_tool_position(t, native_shape_test_position(t, state, line.second),
        geometry.Vector3{0.5, 0.3, 0})
}

// Verify reflected markers publish through both canonical transform and arc owners.
@(test)
native_reflected_marker_publishes_real_arc :: proc(t: ^testing.T) {
    state := native_tool_test_state()
    defer free(state, context.allocator)
    arc := bridge_scene.shape_create_arc(state, {0.4, 0.5, 0},
        {
            radius = 0.1,
        }, bridge_shape_test_input({}).style)
    native_tool_test_sample(t, state, {
        kind = .Reflect_Angle_Marker,
        entity = arc.shape,
        elapsed = 1,
        duration = 1,
        start_position = {0.4, 0.5, 0},
        second_position = {0.5, 0.5, 0},
        third_position = {0.4, 0.6, 0},
        axis_a = {0, 0.4, 0},
        axis_b = {1, 0.4, 0},
        flag = true,
    })
    expect_native_tool_position(t, native_shape_test_position(t, state, arc.shape),
        geometry.Vector3{0.4, 0.3, 0})
    arc_geometry, found := shapemodel.shape_component_get(&state^.shape_world.arcs,
        &state^.shape_world.registry, shapemodel.shape_entity_unpack(arc.shape))
    testing.expect(t, found && math.abs(arc_geometry.sweep_theta -
        f32(math.PI / 2)) < 1e-6)
}

// Keep every compound ABI discriminator symmetric with its native evaluator.
@(test)
native_compound_abi_kinds_are_closed :: proc(t: ^testing.T) {
    kinds: [12]modifier.Modifier_Kind = {
        .Pen_Tilt, .Pen_Cone, .Pen_Drag, .Pen_Transfer,
        .Compass_Transfer, .Compass_Highlight, .Line_Segment,
        .Reflect_Angle_Marker, .Pen_Highlight_Point, .Pen_Stroke,
        .Extend_Line, .Two_Segment_Stroke,
    }
    for kind, index in kinds {
        actual, valid := native_modifier_kind_from_abi(i32(index + 18))
        testing.expect(t, valid)
        testing.expect_value(t, actual, kind)
    }
    _, valid := native_modifier_kind_from_abi(47)
    testing.expect(t, !valid)
}

// Preserve caller-owned visibility during pen travel instead of implicitly showing it.
@(test)
native_pen_transfer_preserves_hidden_host :: proc(t: ^testing.T) {
    state := native_tool_test_state()
    defer free(state, context.allocator)
    bridge_scene.hide_pen(state)
    native_tool_test_sample(t, state, {
        kind = .Pen_Transfer,
        second_entity = 1,
        elapsed = 0.5,
        duration = 1,
        start_position = {0.4, 0.6, 0},
        second_position = {0.6, 0.4, 0},
        radius = 0.14,
        scalar = 0.2,
        integer = 1,
    })
    style, found := shapemodel.shape_component_get(
        &state^.shape_world.render_styles, &state^.shape_world.registry,
        state^.world_pen.shape)
    testing.expect(t, found && !style.visible)
    expect_native_tool_position(t, bridge_scene.get_pen_joint1_position(state),
        geometry.Vector3{0.5, 0.5, 0.2})
}

// Verify native compound pen motion survives real constraint solving and retirement.
@(test)
native_compound_pen_samples_preserve_tool_ownership :: proc(t: ^testing.T) {
    state := native_tool_test_state()
    defer free(state, context.allocator)
    kinds: [4]modifier.Modifier_Kind = {
        .Pen_Tilt, .Pen_Cone, .Pen_Stroke, .Pen_Highlight_Point,
    }
    for kind in kinds {
        native_tool_test_sample(t, state, {
            kind = kind,
            second_entity = 1,
            elapsed = 0.5,
            duration = 1,
            start_position = {0.4, 0.6, 0},
            second_position = {0.6, 0.4, 0},
            radius = 0.14,
            angle = f32(math.PI / 3),
            brush = f32(math.PI / 2),
            scalar = 6,
        })
        first := bridge_scene.get_pen_joint1_position(state)
        second := bridge_scene.get_pen_joint2_position(state)
        delta := second - first
        testing.expect(t, math.abs(delta.x * delta.x + delta.y * delta.y +
            delta.z * delta.z - 0.14 * 0.14) < 1e-6)
        lock, found := bridge_scene.tool_lock_constraint(state, state^.world_pen.joint2)
        testing.expect(t, found && !lock.enabled)
        bridge_scene.hide_pen(state)
        testing.expect_value(t, bridge_scene.shape_set_visible(state,
            shapemodel.shape_entity_pack(state^.world_pen.shape), 0),
            i32(bridgemodel.BRIDGE_STATUS_OK))
    }
}

// Verify highlights retain both ordinary locks without enabling filled sweep contact.
@(test)
native_compass_highlight_preserves_real_locks :: proc(t: ^testing.T) {
    state := native_tool_test_state()
    defer free(state, context.allocator)
    native_tool_test_sample(t, state, {
        kind = .Compass_Highlight,
        entity = 2,
        second_entity = 3,
        elapsed = 0.5,
        duration = 1,
        start_position = {0.4, 0.6, 0},
        second_position = {0.6, 0.6, 0},
        angle = -f32(math.PI),
        radius = 0.2,
        flag = true,
    })
    expect_native_tool_position(t, bridge_scene.get_compass_joint2_position(state),
        geometry.Vector3{0.4, 0.4, 0})
    expect_native_tool_style(t, state, state^.world_compass.shape, 3)
    lock, found := bridge_scene.tool_lock_constraint(state, state^.world_compass.joint2)
    testing.expect(t, found && lock.enabled)
}

// Allow solver roundoff without hiding a measurable tool-pose displacement.
expect_native_tool_position :: proc(
    t: ^testing.T, actual, expected: geometry.Vector3) {
    testing.expect(t, math.abs(actual.x - expected.x) < 1e-6)
    testing.expect(t, math.abs(actual.y - expected.y) < 1e-6)
    testing.expect(t, math.abs(actual.z - expected.z) < 1e-6)
}

// Initialize real tool hosts and constraints in the test-owned world.
native_tool_test_state :: proc() -> ^core.Euclid_General_State {
    state := bridge_shape_test_state()
    state^.world_pen, _ = shapes.world_create_pen(&state^.shape_world, {
        joint1 = {0.4, 0.6, 1.4},
        joint2 = {0.4, 0.6, 1.54},
        length = 0.14,
    })
    state^.world_compass, _ = shapes.world_create_compass(&state^.shape_world, {
        joint1 = {0.4, 0.6, 1.4},
        joint2 = {0.6, 0.4, 1.4},
        limb_length = 0.2,
    })
    return state
}

// Apply a fully validated native sample through its ordinary owner APIs.
native_tool_test_sample :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State,
    request: modifier.Modifier_Request) {
    command: bridge_scene.Scene_Command = {
        kind = .Apply_Native_Modifier,
        modifier = request,
    }
    testing.expect(t, bridge_scene.validate_native_modifier_marker(state, &command))
    output: modifier.Modifier_Output_Buffer
    testing.expect_value(t, modifier.evaluate_modifier(request, &output),
        modifier.Modifier_Status.Ok)
    for index in 0..<output.count {
        bridge_scene.apply_native_modifier_output(state, &output.outputs[index])
    }
    shapes.world_apply_all_constraints_to_error(&state^.shape_world, 0.00001)
}

// Assert physical tool visibility and contact feature, not construction ink.
expect_native_tool_style :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State,
    host: shapemodel.Shape_Entity, active: u16) {
    style, found := shapemodel.shape_component_get(
        &state^.shape_world.render_styles, &state^.shape_world.registry, host)
    testing.expect(t, found && style.visible)
    feature, has_feature := shapemodel.shape_component_get(
        &state^.shape_world.active_features, &state^.shape_world.registry, host)
    testing.expect(t, has_feature)
    testing.expect_value(t, feature.index, active)
}

// Verify descent shows the pen and leaves its upper joint free for later motion.
@(test)
native_pen_descent_and_rise_preserve_joint_contract :: proc(t: ^testing.T) {
    state := native_tool_test_state()
    defer free(state, context.allocator)
    kinds: [2]modifier.Modifier_Kind = {.Pen_Descend, .Pen_Rise}
    samples: [3]f32 = {0, 0.5, 1}
    for kind in kinds {
        for elapsed in samples {
            native_tool_test_sample(t, state, {
                kind = kind,
                entity = 0,
                second_entity = 1,
                elapsed = elapsed,
                duration = 1,
                start_position = {0.4, 0.6, 0},
                second_position = {0.4, 0.6, 0},
                scalar = 1.4,
                brush = 0.14,
            })
            z := 1.4 * elapsed
            if kind == .Pen_Descend {
                z = 1.4 * (1 - elapsed)
            }
            testing.expect_value(t, bridge_scene.get_pen_joint1_position(state),
                geometry.Vector3{0.4, 0.6, z})
            expect_native_tool_position(t, bridge_scene.get_pen_joint2_position(state),
                geometry.Vector3{0.4, 0.6, z + 0.14})
            lock, found := bridge_scene.tool_lock_constraint(
                state, state^.world_pen.joint2)
            testing.expect(t, found && !lock.enabled)
            expect_native_tool_style(t, state, state^.world_pen.shape, 0)
        }
    }
}

// Verify the native tilted and dragged pen maintains its full physical length.
@(test)
native_pen_pose_moves_both_joints_after_descent :: proc(t: ^testing.T) {
    state := native_tool_test_state()
    defer free(state, context.allocator)
    native_tool_test_sample(t, state, {
        kind = .Pen_Descend,
        entity = 0,
        second_entity = 1,
        elapsed = 1,
        duration = 1,
        start_position = {0.4, 0.6, 0},
        second_position = {0.4, 0.6, 0},
        scalar = 1.4,
        brush = 0.14,
    })
    positions: [2]geometry.Vector3 = {{0.4, 0.6, 0}, {0.6, 0.4, 0}}
    azimuths: [3]f32 = {0, f32(math.PI / 2), f32(math.PI)}
    for position in positions {
        for azimuth in azimuths {
            native_tool_test_sample(t, state, {
                kind = .Pen_Pose,
                entity = 0,
                second_entity = 1,
                start_position = position,
                radius = 0.14,
                angle = f32(math.PI / 4),
                scalar = azimuth,
            })
            first := bridge_scene.get_pen_joint1_position(state)
            second := bridge_scene.get_pen_joint2_position(state)
            testing.expect_value(t, first, position)
            delta := second - first
            testing.expect(t, math.abs(delta.x * delta.x + delta.y * delta.y +
                delta.z * delta.z - 0.14 * 0.14) < 1e-6)
            horizontal := 0.14 * math.cos(f32(math.PI / 4))
            expect_native_tool_position(t, delta, geometry.Vector3{
                horizontal * math.cos(azimuth),
                horizontal * math.sin(azimuth),
                0.14 * math.sin(f32(math.PI / 4)),
            })
            lock, found := bridge_scene.tool_lock_constraint(
                state, state^.world_pen.joint2)
            testing.expect(t, found && !lock.enabled)
        }
    }
}

// Verify both compass legs descend and rise while the host is visible.
@(test)
native_compass_descent_and_rise_show_both_legs :: proc(t: ^testing.T) {
    state := native_tool_test_state()
    defer free(state, context.allocator)
    kinds: [2]modifier.Modifier_Kind = {.Compass_Descend, .Compass_Rise}
    samples: [3]f32 = {0, 0.5, 1}
    for kind in kinds {
        for elapsed in samples {
            native_tool_test_sample(t, state, {
                kind = kind,
                entity = 2,
                second_entity = 3,
                elapsed = elapsed,
                duration = 1,
                start_position = {0.4, 0.6, 0},
                second_position = {0.6, 0.4, 0},
                scalar = 1.4,
            })
            z := 1.4 * elapsed
            if kind == .Compass_Descend {
                z = 1.4 * (1 - elapsed)
            }
            testing.expect_value(t, bridge_scene.get_compass_joint1_position(state),
                geometry.Vector3{0.4, 0.6, z})
            testing.expect_value(t, bridge_scene.get_compass_joint2_position(state),
                geometry.Vector3{0.6, 0.4, z})
            expect_native_tool_style(t, state, state^.world_compass.shape, 0)
        }
    }
}

// Verify the first circle shows the compass without requiring a prior transfer.
@(test)
native_first_and_second_circles_show_active_compass :: proc(t: ^testing.T) {
    state := native_tool_test_state()
    defer free(state, context.allocator)
    arc := bridge_scene.shape_create_arc(state, {0.4, 0.6, 0},
        {
            radius = 0.12,
        },
        bridge_shape_test_input({}).style)
    centers: [2]geometry.Vector3 = {{0.4, 0.6, 0}, {0.6, 0.4, 0}}
    for center in centers {
        bridge_scene.hide_compass(state)
        native_tool_test_sample(t, state, {
            kind = .Draw_Circle,
            entity = arc.shape,
            second_entity = 2,
            third_entity = 3,
            elapsed = 0.5,
            duration = 1,
            start_position = center,
            second_position = center + geometry.Vector3{0.12, 0, 0},
            radius = 0.12,
            angle = f32(math.PI),
            color_packed = 0xffffffff,
        })
        testing.expect_value(t, bridge_scene.get_compass_joint1_position(state), center)
        tip := bridge_scene.get_compass_joint2_position(state)
        testing.expect(t, math.abs(tip.x - center.x) < 1e-6)
        testing.expect(t, math.abs(tip.y - center.y - 0.12) < 1e-6)
        expect_native_tool_style(t, state, state^.world_compass.shape, 3)
    }

}

// Verify native floor contacts participate in transactional capacity preflight.
@(test)
native_tool_batch_rejects_contact_overflow_before_descent :: proc(t: ^testing.T) {
    state := native_tool_test_state()
    defer free(state, context.allocator)
    state^.julia_interface = new(bridgemodel.Euclid_Julia_Interface, context.allocator)
    defer free(state^.julia_interface, context.allocator)
    state^.julia_interface^.current_animation =
        &state^.julia_interface^.null_animation
    batch: bridge_scene.Scene_Command_Batch
    bridge_scene.begin_scene_command_batch(state, &batch)
    testing.expect_value(t, apply_native_modifier(state, {
        kind = 2,
        entity = 0,
        second_entity = 1,
        elapsed = 1,
        duration = 1,
        start = {0.4, 0.6, 0},
        second = {0.4, 0.6, 0},
        scalar = 1.4,
        brush = 0.14,
    }), i32(bridgemodel.BRIDGE_STATUS_OK))
    bridge_scene.end_scene_command_batch(state)
    testing.expect_value(t,
        bridge_scene.scene_command_batch_tool_contact_count(&batch), 1)
    state^.particle_system.dust_tool_contact_count =
        len(state^.particle_system.dust_tool_contacts)
    before := bridge_scene.get_pen_joint1_position(state)
    testing.expect(t, !bridge_scene.commit_scene_command_batch(state, &batch))
    testing.expect_value(t, bridge_scene.get_pen_joint1_position(state), before)
    state^.particle_system.dust_tool_contact_count = 0
    testing.expect(t, bridge_scene.commit_scene_command_batch(state, &batch))
    expect_native_tool_style(t, state, state^.world_pen.shape, 0)
    testing.expect_value(t, bridge_scene.get_pen_joint2_position(state),
        geometry.Vector3{0.4, 0.6, 0.14})
}

// Reject absent native tool sentinels rather than silently dropping their outputs.
@(test)
native_tool_marker_requires_initialized_tool_ownership :: proc(t: ^testing.T) {
    state := bridge_shape_test_state()
    defer free(state, context.allocator)
    command: bridge_scene.Scene_Command = {
        kind = .Apply_Native_Modifier,
        modifier = {
            kind = .Pen_Descend,
            entity = 0,
            second_entity = 1,
            scalar = 1.4,
            brush = 0.35,
        },
    }
    testing.expect(t, !bridge_scene.validate_native_modifier_marker(state, &command))
}

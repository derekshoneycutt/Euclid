package julia_host

import bridge_scene "../scene"

import bridgemodel "../model"

import core "../../core"
import particles "../../particles"
import shapes "../../shapes"
import shapemodel "../../shapes/model"
import "core:math"
import "core:testing"

// Supply a real compass and filled sector with the ordinary reveal-test lifecycle.
native_sweep_test_state :: proc(t: ^testing.T) -> (^core.Euclid_General_State, u64) {
    state := bridge_reveal_test_state_create()
    particles.formation_reset_generation(&state.particle_system, 4)
    state.world_compass, _ = shapes.world_create_compass(&state.shape_world, {
        joint1 = {0.5, 0.5, 0},
        joint2 = {0.7, 0.5, 0},
        limb_length = 0.2,
    })
    host := bridge_scene.shape_create_filled_arc(state, {0.5, 0.5, 0},
        {0.2, 0, 0}, bridge_shape_test_input({}).style)
    testing.expect_value(t, host.status, bridgemodel.BRIDGE_STATUS_OK)
    return state, host.shape
}

// Prepare the service-owned slot for one delayed Julia interval batch.
native_sweep_test_prepare_delayed_tick :: proc(
    state: ^core.Euclid_General_State,
    service: ^Julia_Runtime_Service) -> ^bridgemodel.Animation_Tick_Slot {
    state^.julia_interface^.selected_animation =
        state^.julia_interface^.current_animation
    service^.animation_generation = 4
    service^.animation_tick_pending = true
    slot := &service^.animation_tick_slots[0]
    slot^.state = .Accepted
    slot^.generation = 4
    slot^.sequence = 1
    slot^.animation = state^.julia_interface^.current_animation
    slot^.effective_progress = 0.3
    slot^.scene_batch.animation = slot^.animation
    slot^.scene_batch.animation_generation = 4
    slot^.scene_batch.tick_sequence = 1
    slot^.scene_batch.animation_progress = 0.3
    slot^.formation_intervals[0] = {
        step = 10,
        generation = 4,
        authored_seconds = 0.1,
    }
    slot^.formation_intervals[1] = {
        step = 11,
        generation = 4,
        authored_seconds = 0.2,
    }
    slot^.formation_interval_count = 2
    return slot
}

// Populate one delayed Julia result spanning native-covered and uncovered time.
@(test)
native_and_delayed_julia_share_display_formation_time :: proc(t: ^testing.T) {
    state, _ := native_sweep_test_state(t)
    defer bridge_reveal_test_state_destroy(state)
    native_batch: bridge_scene.Scene_Command_Batch
    bridge_scene.begin_native_scene_command_batch(state, &native_batch, 25)
    native_batch.native_interval_step = 10
    native_batch.native_interval_seconds = 0.1
    native_batch.native_interval_set = true
    testing.expect(t, native_batch.animation == nil)
    bridge_scene.end_scene_command_batch(state)
    testing.expect(t, bridge_scene.commit_scene_command_batch(state, &native_batch))
    testing.expect_value(t, state.particle_system.formation.accepted_progress, f64(0.1))

    service := new(Julia_Runtime_Service, context.allocator)
    defer free(service, context.allocator)
    state.julia_runtime_service = service
    _ = native_sweep_test_prepare_delayed_tick(state, service)
    testing.expect(t, publish_available_animation_tick(state))
    testing.expect(t, math.abs(
        state.particle_system.formation.accepted_progress - f64(0.3)) < f64(1e-12))
    testing.expect_value(t, state.particle_system.formation.native_time_interval_count, 0)
}

// Accept a native scene batch when the application has no Julia interface installed.
@(test)
native_scene_batch_does_not_require_julia_interface :: proc(t: ^testing.T) {
    state := bridge_shape_test_state()
    defer free(state)
    batch: bridge_scene.Scene_Command_Batch
    bridge_scene.begin_native_scene_command_batch(state, &batch)
    bridge_scene.end_scene_command_batch(state)
    testing.expect(t, state.julia_interface == nil)
    testing.expect(t, bridge_scene.commit_scene_command_batch(state, &batch))
}

// Reject interval overflow before scene geometry or accepted time can partially publish.
@(test)
native_interval_capacity_rejection_is_atomic :: proc(t: ^testing.T) {
    state, host := native_sweep_test_state(t)
    defer bridge_reveal_test_state_destroy(state)
    for step in 0..<particles.FORMATION_TIME_INTERVAL_CAPACITY {
        state.particle_system.formation.native_time_intervals[step] = {
            step = u64(step + 1),
            generation = 4,
            authored_seconds = 0.001,
        }
    }
    state.particle_system.formation.native_time_interval_count =
        particles.FORMATION_TIME_INTERVAL_CAPACITY
    before := bridge_scene.shape_get_arc(state, host).arc
    batch: bridge_scene.Scene_Command_Batch
    bridge_scene.begin_native_scene_command_batch(state, &batch, 26)
    batch.native_interval_step = u64(particles.FORMATION_TIME_INTERVAL_CAPACITY + 1)
    batch.native_interval_seconds = 0.001
    batch.native_interval_set = true
    command, captured := bridge_scene.append_scene_command(state, .Set_Shape_Arc)
    testing.expect(t, captured && command != nil)
    command.entity = host
    command.arc = {
        radius = 0.4,
        start_theta = 0,
        sweep_theta = 2,
    }
    bridge_scene.end_scene_command_batch(state)
    testing.expect(t, !bridge_scene.commit_scene_command_batch(state, &batch))
    testing.expect_value(t, bridge_scene.shape_get_arc(state, host).arc, before)
    testing.expect_value(t, state.particle_system.formation.native_time_interval_count,
        particles.FORMATION_TIME_INTERVAL_CAPACITY)
}

// Capture the native formation sample without entering Julia or publishing early.
native_sweep_test_capture :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State,
    batch: ^bridge_scene.Scene_Command_Batch, host: u64, elapsed: f32 = 0) {
    bridge_scene.begin_native_scene_command_batch(state, batch)
    batch.animation_generation = 4
    batch.tick_sequence = 1
    batch.animation_progress = 0.25 + f64(elapsed)
    command, captured := bridge_scene.append_scene_command(state, .Apply_Native_Modifier)
    testing.expect(t, captured && command != nil)
    command.modifier = {
        kind = .Draw_Filled_Circle,
        entity = host,
        second_entity = 2,
        third_entity = 3,
        start_position = {0.5, 0.5, 0},
        second_position = {0.7, 0.5, 0},
        radius = 0.2,
        angle = 1,
        duration = 1,
        elapsed = elapsed,
        flag = true,
    }
    bridge_scene.end_scene_command_batch(state)
}

// Compare the actual captured Julia reveal and native reveal at the same commit endpoint.
@(test)
native_sweep_matches_captured_julia_formation :: proc(t: ^testing.T) {
    native, native_host := native_sweep_test_state(t)
    defer bridge_reveal_test_state_destroy(native)
    julia, julia_host := native_sweep_test_state(t)
    defer bridge_reveal_test_state_destroy(julia)
    native_batch, julia_batch: bridge_scene.Scene_Command_Batch
    native_sweep_test_capture(t, native, &native_batch, native_host)
    snapshot := bridge_reveal_test_snapshot(julia)
    defer free(snapshot, context.allocator)
    bridge_scene.begin_scene_command_batch(julia, &julia_batch)
    julia_batch.animation_generation = 4
    julia_batch.tick_sequence = 1
    julia_batch.animation_progress = 0.25
    julia.animation_query_snapshot_target = snapshot
    testing.expect_value(t,
        bridge_scene.shape_reveal_sweep(julia, julia_host, 1),
        bridgemodel.BRIDGE_STATUS_OK)
    julia.animation_query_snapshot_target = nil
    bridge_scene.end_scene_command_batch(julia)
    testing.expect(t, bridge_scene.commit_scene_command_batch(native, &native_batch))
    testing.expect(t, bridge_scene.commit_scene_command_batch(julia, &julia_batch))
    slot := particles.formation_find_reveal(
        &native.particle_system.formation, .Sweep, native_host, 4)
    testing.expect(t, slot >= 0)
    testing.expect_value(t, native.particle_system.formation.reveal_count, 1)
    testing.expect_value(t, native.particle_system.formation.reveals[slot],
        julia.particle_system.formation.reveals[slot])
    native_sweep_test_capture(t, native, &native_batch, native_host, 0.5)
    testing.expect(t, bridge_scene.commit_scene_command_batch(native, &native_batch))
    testing.expect_value(t, native.particle_system.formation.reveal_count, 1)
    testing.expect_value(t,
        native.particle_system.formation.reveals[slot].start_progress, 0.25)
    native_sweep_test_prepare_sector(native, native_host)
    testing.expect(t, particles.formation_prepare_sweep_targets(
        &native.particle_system, &native.shape_world, 1) > 0)
}

// Feed the published arc into the same prepared sector representation used by rendering.
native_sweep_test_prepare_sector :: proc(state: ^core.Euclid_General_State, host: u64) {
    entity := shapemodel.shape_entity_unpack(host)
    arc := bridge_scene.shape_get_arc(state, host).arc
    state.shape_world.draw_cache.item_count = 1
    state.shape_world.draw_cache.items[0] = shapemodel.Shapes_Filled_Circle_Draw{
        source_index = int(entity.slot - 1),
        source_generation = entity.generation,
        radius = arc.radius,
        start_theta = arc.start_theta,
        sweep_theta = arc.sweep_theta,
    }
}

// Exhausted formation storage rejects native geometry and tool changes atomically.
@(test)
native_sweep_capacity_rejection_preserves_scene :: proc(t: ^testing.T) {
    state, host := native_sweep_test_state(t)
    defer bridge_reveal_test_state_destroy(state)
    bridge_test_fill_reveal_slots(t, state, 4)
    batch: bridge_scene.Scene_Command_Batch
    native_sweep_test_capture(t, state, &batch, host)
    before := bridge_scene.get_compass_joint2_position(state)
    testing.expect(t, !bridge_scene.commit_scene_command_batch(state, &batch))
    testing.expect_value(t, bridge_scene.get_compass_joint2_position(state), before)
    testing.expect_value(t,
        bridge_scene.shape_get_arc(state, host).arc.sweep_theta, f32(0))
    testing.expect_value(t, state.particle_system.formation.accepted_progress, f64(0))
}

// A later direct reveal supersedes a native reveal even when all records are occupied.
@(test)
native_sweep_and_julia_reveal_share_supersession :: proc(t: ^testing.T) {
    state, host := native_sweep_test_state(t)
    defer bridge_reveal_test_state_destroy(state)
    bridge_test_fill_reveal_slots(t, state, 4)
    batch: bridge_scene.Scene_Command_Batch
    native_sweep_test_capture(t, state, &batch, host)
    batch.commands[1] = {
        kind = .Reveal_Sweep,
        entity = host,
        reveal = {
            kind = .Sweep,
            owner_entity = host,
            duration = 0,
        },
    }
    batch.command_count = 2
    testing.expect(t, bridge_scene.commit_scene_command_batch(state, &batch))
    testing.expect_value(t, particles.formation_find_reveal(
        &state.particle_system.formation, .Sweep, host, 4), -1)
}

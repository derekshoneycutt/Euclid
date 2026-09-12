package bridge

import "core:testing"

import "../core"
import "../shapes"

// Build one bridge state around caller-owned canonical world storage.
bridge_shape_test_state :: proc(
    world: ^core.Shape_World) -> ^core.Euclid_General_State {
    state := new(core.Euclid_General_State, context.allocator)
    state.saved_context = context
    state.shape_world = world
    return state
}

// Return standard visible-test construction values.
bridge_shape_test_input :: proc(position: core.Vector3) -> Bridge_Positioned_Shape_Input {
    return {position = position,
        style = {color = {10, 20, 30, 255}, brush_size = 4}}
}

// Verify constructors return packed identities that resolve to direct world components.
@(test)
bridge_shape_abi_round_trips_packed_line_handles :: proc(t: ^testing.T) {
    world: core.Shape_World
    state := bridge_shape_test_state(&world)
    defer free(state)
    result := shape_create_line(state, {1, 2, 3}, {4, 5, 6},
        bridge_shape_test_input({}).style)

    testing.expect_value(t, result.status, i32(BRIDGE_STATUS_OK))
    shape := core.shape_entity_unpack(result.shape)
    first := core.shape_entity_unpack(result.first)
    second := core.shape_entity_unpack(result.second)
    testing.expect(t, core.shape_registry_resolves(&world.registry, shape))
    geometry, found := core.shape_component_get(
        &world.geometries, &world.registry, shape)
    testing.expect(t, found)
    testing.expect_value(t, geometry.payload.line.first, first)
    testing.expect_value(t, geometry.payload.line.second, second)
}

// Verify null-terminated UTF-8 source is copied exactly and malformed bytes fail atomically.
@(test)
bridge_shape_abi_copies_cstring_unicode_labels :: proc(t: ^testing.T) {
    world: core.Shape_World
    state := bridge_shape_test_state(&world)
    defer free(state)
    before := world.registry.entity_count
    result := shape_create_label(state, cstring("∠A′"),
        i32(core.Shape_Text_Mime.Text_Plain), bridge_shape_test_input({1, 2, 0}))
    testing.expect_value(t, result.status, i32(BRIDGE_STATUS_OK))
    entity := core.shape_entity_unpack(result.entity)
    label, found := core.shape_component_get(&world.labels, &world.registry, entity)
    testing.expect(t, found)
    stored, source_found := core.shape_label_source(&world.label_store, label^)
    testing.expect(t, source_found)
    testing.expect_value(t, stored, "∠A′")

    malformed := [2]u8{0xff, 0}
    rejected := shape_create_label(state, cstring(&malformed[0]),
        i32(core.Shape_Text_Mime.Text_Plain), bridge_shape_test_input({}))
    testing.expect_value(t, rejected.status, i32(BRIDGE_STATUS_INVALID_UTF8))
    testing.expect_value(t, world.registry.entity_count, before + 1)
}

// Verify stale packed handles cannot resolve or mutate a reused animation slot.
@(test)
bridge_shape_abi_rejects_stale_generation :: proc(t: ^testing.T) {
    world: core.Shape_World
    state := bridge_shape_test_state(&world)
    defer free(state)
    testing.expect_value(t, core.shape_world_freeze_baseline(
        &world), core.Shape_World_Status.Ok)
    stale := shape_create_point(state, bridge_shape_test_input({1, 0, 0}))
    testing.expect_value(t, core.shape_world_rewind_animation(
        &world), core.Shape_World_Status.Ok)
    current := shape_create_point(state, bridge_shape_test_input({2, 0, 0}))

    testing.expect(t, stale.entity != current.entity)
    testing.expect_value(t, shape_set_position(
        state, stale.entity, {9, 0, 0}), i32(BRIDGE_STATUS_NOT_FOUND))
    testing.expect_value(t, shape_get_view(state, stale.entity).status,
        i32(BRIDGE_STATUS_NOT_FOUND))
    testing.expect_value(t, shape_get_view(state, current.entity).position,
        core.Vector3{2, 0, 0})
}

// Verify a deferred hide emits dust on display-thread commit before visibility clears.
@(test)
bridge_shape_hide_emits_world_geometry_dust :: proc(t: ^testing.T) {
    world: core.Shape_World
    state := bridge_shape_test_state(&world)
    defer free(state)
    particles := new(core.Particle_System, context.allocator)
    defer free(particles, context.allocator)
    particles^.use_max_dust_particles = 128
    state^.particle_system = particles
    line := shape_create_line(state, {0, 0, 0}, {1, 0, 0},
        bridge_shape_test_input({}).style)
    testing.expect_value(t,
        shape_set_visible(state, line.shape, 1), i32(BRIDGE_STATUS_OK))
    state^.julia_interface = new(core.Euclid_Julia_Interface, context.allocator)
    defer free(state^.julia_interface, context.allocator)
    state^.julia_interface^.current_animation =
        &state^.julia_interface^.null_animation
    batch: Scene_Command_Batch

    begin_scene_command_batch(state, &batch)
    testing.expect_value(t,
        shape_set_visible(state, line.shape, 0), i32(BRIDGE_STATUS_OK))
    end_scene_command_batch(state)
    testing.expect(t, !particles^.low_particles.alive[0])
    testing.expect_value(t, shape_get_view(state, line.shape).visible, u8(1))
    testing.expect(t, commit_scene_command_batch(state, &batch))

    testing.expect(t, particles^.low_particles.alive[0])
    view := shape_get_view(state, line.shape)
    testing.expect_value(t, view.visible, u8(0))
}

// Verify one batch kick does not immediately age dust emitted by an earlier hide.
@(test)
bridge_shape_batch_coalesces_hide_dust_kick :: proc(t: ^testing.T) {
    world: core.Shape_World
    state := bridge_shape_test_state(&world)
    defer free(state)
    particles := new(core.Particle_System, context.allocator)
    defer free(particles, context.allocator)
    particles^.use_max_dust_particles = 256
    particles^.low_particles.alive[0] = true
    particles^.low_particles.life[0] = 10
    state^.particle_system = particles
    first := shape_create_line(state, {0, 0, 0}, {1, 0, 0},
        bridge_shape_test_input({}).style)
    second := shape_create_line(state, {0, 1, 0}, {1, 1, 0},
        bridge_shape_test_input({}).style)
    _ = shape_set_visible(state, first.shape, 1)
    _ = shape_set_visible(state, second.shape, 1)
    state^.julia_interface = new(core.Euclid_Julia_Interface, context.allocator)
    defer free(state^.julia_interface, context.allocator)
    state^.julia_interface^.current_animation =
        &state^.julia_interface^.null_animation
    batch: Scene_Command_Batch

    begin_scene_command_batch(state, &batch)
    _ = shape_set_visible(state, first.shape, 0)
    _ = shape_set_visible(state, second.shape, 0)
    end_scene_command_batch(state)
    testing.expect(t, commit_scene_command_batch(state, &batch))

    testing.expect(t, particles^.low_particles.age[0] > 0)
    testing.expect(t, particles^.low_particles.alive[1])
    testing.expect_value(t, particles^.low_particles.age[1], f32(0))
}

// Verify worker queries remain isolated from later canonical component mutation.
@(test)
bridge_shape_abi_reads_query_snapshot :: proc(t: ^testing.T) {
    world: core.Shape_World
    state := bridge_shape_test_state(&world)
    defer free(state)
    created := shape_create_label(state, cstring("β"),
        i32(core.Shape_Text_Mime.Text_Plain), bridge_shape_test_input({1, 2, 3}))
    snapshot := new(core.Animation_Query_Snapshot, context.allocator)
    defer free(snapshot)
    capture_animation_query_snapshot(state, snapshot)
    state.animation_query_snapshot_target = snapshot
    defer {state.animation_query_snapshot_target = nil}
    _ = shape_set_position(state, created.entity, {8, 9, 10})

    view := shape_get_view(state, created.entity)
    testing.expect_value(t, view.position, core.Vector3{1, 2, 3})
    bytes: [8]u8
    copied := shape_copy_label_source(state, created.entity, &bytes[0], len(bytes))
    testing.expect_value(t, copied.status, i32(BRIDGE_STATUS_OK))
    testing.expect_value(t, string(bytes[:copied.byte_count]), "β")
}

// Verify the constraint ABI stores direct packed endpoint targets.
@(test)
bridge_constraint_abi_creates_direct_distance_target :: proc(t: ^testing.T) {
    world: core.Shape_World
    state := bridge_shape_test_state(&world)
    defer free(state)
    first := shape_create_point(state, bridge_shape_test_input({1, 0, 0}))
    second := shape_create_point(state, bridge_shape_test_input({3, 0, 0}))

    status := create_distance_constraint(state, {
        first = first.entity, second = second.entity, length = 2,
        movement = 0, enabled = 1})

    testing.expect_value(t, status, i32(BRIDGE_STATUS_OK))
    testing.expect_value(t, world.constraints.count, u16(1))
    constraint := &world.constraints.values[0]
    testing.expect_value(t, constraint^.kind, core.Shape_Constraint_Kind.Distance)
    testing.expect_value(t, constraint^.payload.distance.first,
        core.shape_entity_unpack(first.entity))
    testing.expect_value(t, constraint^.payload.distance.second,
        core.shape_entity_unpack(second.entity))
}

// Verify a captured tool unlock mutates its direct constraint only at commit.
@(test)
bridge_tool_unlock_is_deferred_until_scene_commit :: proc(t: ^testing.T) {
    world: core.Shape_World
    state := bridge_shape_test_state(&world)
    defer free(state)
    state^.julia_interface = new(core.Euclid_Julia_Interface, context.allocator)
    defer free(state^.julia_interface)
    animation := &state^.julia_interface^.null_animation
    state^.julia_interface^.current_animation = animation
    state^.world_pen, _ = shapes.world_create_pen(&world, {
        joint1 = {1, 0, 0}, joint2 = {2, 0, 0}, length = 1})
    constraint := &world.constraints.values[state^.world_pen.joint1_lock_constraint]
    constraint^.enabled = true
    batch: Scene_Command_Batch

    begin_scene_command_batch(state, &batch)
    unlock_pen_joint1(state)
    end_scene_command_batch(state)

    testing.expect(t, constraint^.enabled)
    testing.expect(t, commit_scene_command_batch(state, &batch))
    testing.expect(t, !constraint^.enabled)
}
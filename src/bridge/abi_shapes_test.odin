package bridge

import bridgemodel "model"
import geometry "../core/geometry"

import particlemodel "../particles/model"
import shapemodel "../shapes/model"
import evidence_trace "../evidence/trace"

import "core:testing"

import "../core"
import "../particles"
import "../shapes"

// Build one bridge state around caller-owned canonical world storage.
bridge_shape_test_state :: proc(
    world: ^shapemodel.Shape_World) -> ^core.Euclid_General_State {
    state := new(core.Euclid_General_State, context.allocator)
    state.saved_context = context
    state.shape_world = world
    return state
}

// Return standard visible-test construction values.
bridge_shape_test_input :: proc(
    position: geometry.Vector3) -> Bridge_Positioned_Shape_Input {
    return {position = position,
        style = {color = {10, 20, 30, 255}, brush_size = 4}}
}

// Verify constructors return packed identities that resolve to direct world components.
@(test)
bridge_shape_abi_round_trips_packed_line_handles :: proc(t: ^testing.T) {
    world: shapemodel.Shape_World
    state := bridge_shape_test_state(&world)
    defer free(state)
    result := shape_create_line(state, {1, 2, 3}, {4, 5, 6},
        bridge_shape_test_input({}).style)

    testing.expect_value(t, result.status, i32(BRIDGE_STATUS_OK))
    shape := shapemodel.shape_entity_unpack(result.shape)
    first := shapemodel.shape_entity_unpack(result.first)
    second := shapemodel.shape_entity_unpack(result.second)
    testing.expect(t, shapemodel.shape_registry_resolves(&world.registry, shape))
    geometry, found := shapemodel.shape_component_get(
        &world.geometries, &world.registry, shape)
    testing.expect(t, found)
    testing.expect_value(t, geometry.payload.line.first, first)
    testing.expect_value(t, geometry.payload.line.second, second)
}

// Verify arc queries return complete geometry and remain isolated by snapshots.
@(test)
bridge_shape_abi_queries_arc_geometry_snapshot :: proc(t: ^testing.T) {
    world: shapemodel.Shape_World
    state := bridge_shape_test_state(&world)
    defer free(state)
    created := shape_create_arc(state, {1, 2, 3}, {4, 0.5, -1.5},
        bridge_shape_test_input({}).style)
    testing.expect_value(t, created.status, i32(BRIDGE_STATUS_OK))
    testing.expect_value(t, shape_get_arc(state, created.shape).arc,
        shapemodel.Bridge_Arc_Geometry{4, 0.5, -1.5})
    snapshot := new(bridgemodel.Animation_Query_Snapshot, context.allocator)
    defer free(snapshot)
    capture_animation_query_snapshot(state, snapshot)
    state.animation_query_snapshot_target = snapshot
    defer {state.animation_query_snapshot_target = nil}

    testing.expect_value(t, shape_set_arc(state, created.shape, {2, 1, 3}),
        i32(BRIDGE_STATUS_OK))
    testing.expect_value(t, shape_get_arc(state, created.shape).arc,
        shapemodel.Bridge_Arc_Geometry{4, 0.5, -1.5})
    state.animation_query_snapshot_target = nil
    testing.expect_value(t, shape_get_arc(state, created.shape).arc,
        shapemodel.Bridge_Arc_Geometry{2, 1, 3})
}

// Verify the generic ABI preserves semantic operation and direct center identities.
@(test)
bridge_shape_abi_creates_circle_region :: proc(t: ^testing.T) {
    world: shapemodel.Shape_World
    state := bridge_shape_test_state(&world)
    defer free(state)
    result := shape_create_circle_region(state, {0, 0, 0}, {1, 0, 0},
        {i32(shapemodel.Shape_Circle_Region_Operation.Difference), 1, 1},
        bridge_shape_test_input({}).style)
    testing.expect_value(t, result.status, i32(BRIDGE_STATUS_OK))
    shape := shapemodel.shape_entity_unpack(result.shape)
    first := shapemodel.shape_entity_unpack(result.first_center)
    second := shapemodel.shape_entity_unpack(result.second_center)
    geometry, found := shapemodel.shape_component_get(
        &world.geometries, &world.registry, shape)
    testing.expect(t, found)
    testing.expect_value(t, geometry.payload.circle_region.value.operation,
        shapemodel.Shape_Circle_Region_Operation.Difference)
    testing.expect(t, shapemodel.shape_registry_resolves(&world.registry, first))
    testing.expect(t, shapemodel.shape_registry_resolves(&world.registry, second))
    testing.expect_value(t, shape_get_view(state, result.shape).kind,
        i32(shapemodel.Shape_Geometry_Kind.Circle_Region))
}

// Verify stale packed arc identities cannot query a reused animation slot.
@(test)
bridge_shape_abi_rejects_stale_arc_generation :: proc(t: ^testing.T) {
    world: shapemodel.Shape_World
    state := bridge_shape_test_state(&world)
    defer free(state)
    testing.expect_value(t, shapemodel.shape_world_freeze_baseline(
        &world), shapemodel.Shape_World_Status.Ok)
    stale := shape_create_arc(state, {}, {1, 0, 1}, bridge_shape_test_input({}).style)
    testing.expect_value(t, shapemodel.shape_world_rewind_animation(
        &world), shapemodel.Shape_World_Status.Ok)
    current := shape_create_arc(state, {}, {2, 0, 2}, bridge_shape_test_input({}).style)

    testing.expect(t, stale.shape != current.shape)
    testing.expect_value(t, shape_get_arc(state, stale.shape).status,
        i32(BRIDGE_STATUS_NOT_FOUND))
    testing.expect_value(t, shape_get_arc(state, current.shape).arc,
        shapemodel.Bridge_Arc_Geometry{2, 0, 2})
}

// Verify a captured complete arc mutation becomes visible only at batch commit.
@(test)
bridge_shape_arc_mutation_is_atomic_at_scene_commit :: proc(t: ^testing.T) {
    world: shapemodel.Shape_World
    state := bridge_shape_test_state(&world)
    defer free(state)
    state^.julia_interface = new(bridgemodel.Euclid_Julia_Interface, context.allocator)
    defer free(state^.julia_interface, context.allocator)
    state^.julia_interface^.current_animation =
        &state^.julia_interface^.null_animation
    created := shape_create_arc(state, {}, {1, 0, 1}, bridge_shape_test_input({}).style)
    batch: Scene_Command_Batch

    begin_scene_command_batch(state, &batch)
    testing.expect_value(t, shape_set_arc(state, created.shape, {3, -1, -2}),
        i32(BRIDGE_STATUS_OK))
    testing.expect_value(t, shape_get_arc(state, created.shape).arc,
        shapemodel.Bridge_Arc_Geometry{1, 0, 1})
    end_scene_command_batch(state)
    testing.expect(t, commit_scene_command_batch(state, &batch))
    testing.expect_value(t, shape_get_arc(state, created.shape).arc,
        shapemodel.Bridge_Arc_Geometry{3, -1, -2})
    kind, _ := scene_command_evidence(&batch.commands[0])
    testing.expect_value(t, kind, evidence_trace.Kind.Arc_Geometry_Committed)
}

// Verify null-terminated UTF-8 source is copied exactly and malformed bytes fail atomically.
@(test)
bridge_shape_abi_copies_cstring_unicode_labels :: proc(t: ^testing.T) {
    world: shapemodel.Shape_World
    state := bridge_shape_test_state(&world)
    defer free(state)
    before := world.registry.entity_count
    result := shape_create_label(state, cstring("∠A′"),
        i32(shapemodel.Shape_Text_Mime.Text_Plain), bridge_shape_test_input({1, 2, 0}))
    testing.expect_value(t, result.status, i32(BRIDGE_STATUS_OK))
    entity := shapemodel.shape_entity_unpack(result.entity)
    label, found := shapemodel.shape_component_get(&world.labels, &world.registry, entity)
    testing.expect(t, found)
    stored, source_found := shapemodel.shape_label_source(&world.label_store, label^)
    testing.expect(t, source_found)
    testing.expect_value(t, stored, "∠A′")

    malformed := [2]u8{0xff, 0}
    rejected := shape_create_label(state, cstring(&malformed[0]),
        i32(shapemodel.Shape_Text_Mime.Text_Plain), bridge_shape_test_input({}))
    testing.expect_value(t, rejected.status, i32(BRIDGE_STATUS_INVALID_UTF8))
    testing.expect_value(t, world.registry.entity_count, before + 1)
}

// Verify stale packed handles cannot resolve or mutate a reused animation slot.
@(test)
bridge_shape_abi_rejects_stale_generation :: proc(t: ^testing.T) {
    world: shapemodel.Shape_World
    state := bridge_shape_test_state(&world)
    defer free(state)
    testing.expect_value(t, shapemodel.shape_world_freeze_baseline(
        &world), shapemodel.Shape_World_Status.Ok)
    stale := shape_create_point(state, bridge_shape_test_input({1, 0, 0}))
    testing.expect_value(t, shapemodel.shape_world_rewind_animation(
        &world), shapemodel.Shape_World_Status.Ok)
    current := shape_create_point(state, bridge_shape_test_input({2, 0, 0}))

    testing.expect(t, stale.entity != current.entity)
    testing.expect_value(t, shape_set_position(
        state, stale.entity, {9, 0, 0}), i32(BRIDGE_STATUS_NOT_FOUND))
    testing.expect_value(t, shape_get_view(state, stale.entity).status,
        i32(BRIDGE_STATUS_NOT_FOUND))
    testing.expect_value(t, shape_get_view(state, current.entity).position,
        geometry.Vector3{2, 0, 0})
}

// Verify a deferred hide emits dust on display-thread commit before visibility clears.
@(test)
bridge_shape_hide_emits_world_geometry_dust :: proc(t: ^testing.T) {
    world: shapemodel.Shape_World
    state := bridge_shape_test_state(&world)
    defer free(state)
    particles := new(particlemodel.Particle_System, context.allocator)
    defer free(particles, context.allocator)
    particles^.use_max_dust_particles = 128
    state^.particle_system = particles
    line := shape_create_line(state, {0, 0, 0}, {1, 0, 0},
        bridge_shape_test_input({}).style)
    testing.expect_value(t,
        shape_set_visible(state, line.shape, 1), i32(BRIDGE_STATUS_OK))
    state^.julia_interface = new(bridgemodel.Euclid_Julia_Interface, context.allocator)
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
    world: shapemodel.Shape_World
    state := bridge_shape_test_state(&world)
    defer free(state)
    particles := new(particlemodel.Particle_System, context.allocator)
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
    state^.julia_interface = new(bridgemodel.Euclid_Julia_Interface, context.allocator)
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
    world: shapemodel.Shape_World
    state := bridge_shape_test_state(&world)
    defer free(state)
    created := shape_create_label(state, cstring("β"),
        i32(shapemodel.Shape_Text_Mime.Text_Plain), bridge_shape_test_input({1, 2, 3}))
    snapshot := new(bridgemodel.Animation_Query_Snapshot, context.allocator)
    defer free(snapshot)
    capture_animation_query_snapshot(state, snapshot)
    state.animation_query_snapshot_target = snapshot
    defer {state.animation_query_snapshot_target = nil}
    _ = shape_set_position(state, created.entity, {8, 9, 10})

    view := shape_get_view(state, created.entity)
    testing.expect_value(t, view.position, geometry.Vector3{1, 2, 3})
    bytes: [8]u8
    copied := shape_copy_label_source(state, created.entity, &bytes[0], len(bytes))
    testing.expect_value(t, copied.status, i32(BRIDGE_STATUS_OK))
    testing.expect_value(t, string(bytes[:copied.byte_count]), "β")
}

// Verify the constraint ABI stores direct packed endpoint targets.
@(test)
bridge_constraint_abi_creates_direct_distance_target :: proc(t: ^testing.T) {
    world: shapemodel.Shape_World
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
    testing.expect_value(t, constraint^.kind, shapemodel.Shape_Constraint_Kind.Distance)
    testing.expect_value(t, constraint^.payload.distance.first,
        shapemodel.shape_entity_unpack(first.entity))
    testing.expect_value(t, constraint^.payload.distance.second,
        shapemodel.shape_entity_unpack(second.entity))
}

// Verify a captured tool unlock mutates its direct constraint only at commit.
@(test)
bridge_tool_unlock_is_deferred_until_scene_commit :: proc(t: ^testing.T) {
    world: shapemodel.Shape_World
    state := bridge_shape_test_state(&world)
    defer free(state)
    state^.julia_interface = new(bridgemodel.Euclid_Julia_Interface, context.allocator)
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

// Assert one compound contact carries the expected previous and current legs.
expect_compass_filled_sweep :: proc(t: ^testing.T,
    contact: ^particlemodel.Dust_Tool_Contact) {
    testing.expect(t, contact^.has_sweep)
    testing.expect_value(t, contact^.source,
        particlemodel.Dust_Tool_Contact_Source.Compass_Filled_Sweep)
    testing.expect_value(t, contact^.previous_segment_first,
        geometry.Vector3{0.15, 0.2, 0})
    testing.expect_value(t, contact^.previous_segment_second,
        geometry.Vector3{0.4, 0.2, 0})
    testing.expect_value(t, contact^.segment_first, geometry.Vector3{0.15, 0.2, 0})
    testing.expect_value(t, contact^.segment_second, geometry.Vector3{0.45, 0.2, 0})
}

// Verify committed compass moves retain ordered previous and current leg geometry.
@(test)
bridge_tool_moves_queue_ordered_compound_contacts :: proc(t: ^testing.T) {
    world: shapemodel.Shape_World
    state := bridge_shape_test_state(&world)
    defer free(state)
    particle_system := new(particlemodel.Particle_System, context.allocator)
    defer free(particle_system, context.allocator)
    state^.particle_system = particle_system
    state^.world_compass, _ = shapes.world_create_compass(&world, {
        joint1 = {0.1, 0.2, 0}, pivot = {0.25, 0.3, 0.01},
        joint2 = {0.4, 0.2, 0}, limb_length = 0.2})

    move_compass_joint1(state, {0.15, 0.2, 0}, true)
    move_compass_joint2(state, {0.45, 0.2, 0}, true)
    move_compass_joint1(state, {0.15, 0.2, 0.1}, true)
    move_compass_joint2(state, {0.5, 0.2, 0}, true)

    testing.expect_value(t, particle_system^.dust_tool_contact_count, 3)
    first := &particle_system^.dust_tool_contacts[0]
    second := &particle_system^.dust_tool_contacts[1]
    third := &particle_system^.dust_tool_contacts[2]
    testing.expect_value(t, first^.endpoint, geometry.Vector3{0.15, 0.2, 0})
    testing.expect_value(t, second^.endpoint, geometry.Vector3{0.45, 0.2, 0})
    testing.expect(t, !first^.has_sweep)
    testing.expect_value(t, first^.source,
        particlemodel.Dust_Tool_Contact_Source.Point)
    expect_compass_filled_sweep(t, second)
    testing.expect_value(t, third^.endpoint, geometry.Vector3{0.5, 0.2, 0})
    testing.expect(t, !third^.has_sweep)
    testing.expect_value(t, third^.source,
        particlemodel.Dust_Tool_Contact_Source.Point)
    particles.coalesce_dust_tool_contacts(particle_system)

    testing.expect_value(t, particle_system^.dust_tool_contact_count, 3)
    testing.expect_value(t, particle_system^.dust_tool_contact_coalesced_count, u64(0))
}

// Verify queue-capacity preflight rejects a complete scene batch before mutation.
@(test)
bridge_tool_batch_rejects_full_contact_queue_transactionally :: proc(t: ^testing.T) {
    world: shapemodel.Shape_World
    state := bridge_shape_test_state(&world)
    defer free(state)
    particle_system := new(particlemodel.Particle_System, context.allocator)
    defer free(particle_system, context.allocator)
    state^.particle_system = particle_system
    particle_system^.dust_tool_contact_count = particlemodel.DUST_TOOL_CONTACT_CAP
    state^.world_pen, _ = shapes.world_create_pen(&world, {
        joint1 = {0.1, 0.2, 0}, joint2 = {0.2, 0.2, 0}, length = 0.1})
    state^.julia_interface = new(bridgemodel.Euclid_Julia_Interface, context.allocator)
    defer free(state^.julia_interface, context.allocator)
    state^.julia_interface^.current_animation =
        &state^.julia_interface^.null_animation
    batch: Scene_Command_Batch

    begin_scene_command_batch(state, &batch)
    move_pen_joint1(state, {0.8, 0.7, 0})
    end_scene_command_batch(state)
    before := get_pen_joint1_position(state)

    testing.expect(t, !commit_scene_command_batch(state, &batch))
    testing.expect_value(t, get_pen_joint1_position(state), before)
    testing.expect_value(t, particle_system^.dust_tool_contact_count,
        particlemodel.DUST_TOOL_CONTACT_CAP)

    begin_scene_command_batch(state, &batch)
    move_pen_joint1(state, {0.8, 0.7, 0.1})
    end_scene_command_batch(state)
    testing.expect(t, commit_scene_command_batch(state, &batch))
    testing.expect_value(t, get_pen_joint1_position(state),
        geometry.Vector3{0.8, 0.7, 0.1})
    testing.expect_value(t, particle_system^.dust_tool_contact_count,
        particlemodel.DUST_TOOL_CONTACT_CAP)
}
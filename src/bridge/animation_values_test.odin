package bridge

import "../core"

import "base:runtime"
import "core:mem"
import "core:testing"

//   Allocate one generation-ready host state for copied value ABI tests.
animation_value_test_state_create :: proc(
    generation: u64 = 1) -> ^core.Euclid_General_State {
    state := new(core.Euclid_General_State, context.allocator)
    state^.saved_context = context
    if !core.animation_storage_init(
        &state^.animation_memory,
        &state^.animation_values,
        &state^.dynview_documents) ||
        core.animation_storage_begin_generation(
            &state^.animation_memory,
            &state^.animation_values,
            &state^.dynview_documents,
            generation) != .Ok {
        core.animation_storage_destroy(
            &state^.animation_memory,
            &state^.animation_values,
            &state^.dynview_documents)
        free(state)
        return nil
    }
    return state
}

//   Destroy one host state allocated for copied value ABI tests.
animation_value_test_state_destroy :: proc(state: ^core.Euclid_General_State) {
    core.animation_storage_destroy(
        &state^.animation_memory,
        &state^.animation_values,
        &state^.dynview_documents)
    free(state)
}

// Create one canonical transform entity for mixed transaction tests.
animation_value_test_entity :: proc(
    world: ^core.Shape_World,
    position: core.Vector3) -> core.Shape_Entity {
    entity: core.Shape_Entity
    assert(core.shape_world_create_entity(world, &entity) == .Ok)
    assert(core.shape_component_insert(&world^.transforms, &world^.registry,
        entity, core.Shape_Transform{position = position}) == .Ok)
    return entity
}

//   Verify copied ABI storage round-trips without retaining caller pointers.
@(test)
animation_value_abi_round_trips_copied_bytes :: proc(t: ^testing.T) {
    state := animation_value_test_state_create()
    testing.expect(t, state != nil)
    defer animation_value_test_state_destroy(state)
    source := [4]u8{1, 2, 3, 4}
    identity := Animation_Value_Abi_Identity{7, 11, 12}
    testing.expect_value(t, set_animation_value(
        state, identity, raw_data(source[:]), 4), i32(BRIDGE_STATUS_OK))
    source = {9, 9, 9, 9}

    destination: [4]u8
    testing.expect_value(t, get_animation_value(
        state, identity, raw_data(destination[:]), 4), i32(BRIDGE_STATUS_OK))
    testing.expect(t, mem.compare(destination[:], []u8{1, 2, 3, 4}) == 0)
}

//   Verify malformed pointers, keys, schemas, and sizes return stable statuses.
@(test)
animation_value_abi_rejects_malformed_calls :: proc(t: ^testing.T) {
    state := animation_value_test_state_create()
    testing.expect(t, state != nil)
    defer animation_value_test_state_destroy(state)
    payload := [1]u8{1}
    pointer := raw_data(payload[:])

    testing.expect_value(t, set_animation_value(
        nil, {1, 1, 1}, pointer, 1), i32(BRIDGE_STATUS_ILLEGAL_STATE))
    testing.expect_value(t, set_animation_value(
        state, {1, 1, 1}, nil, 1), i32(BRIDGE_STATUS_INVALID_ARGUMENT))
    testing.expect_value(t, set_animation_value(
        state, {0, 1, 1}, pointer, 1), i32(BRIDGE_STATUS_INVALID_ARGUMENT))
    testing.expect_value(t, set_animation_value(
        state, {1, 0, 0}, pointer, 1), i32(BRIDGE_STATUS_INVALID_ARGUMENT))
    testing.expect_value(t, set_animation_value(
        state, {1, 1, 1}, pointer, 0), i32(BRIDGE_STATUS_INVALID_ARGUMENT))
}

//   Verify missing and mismatched reads never alter caller-owned destination bytes.
@(test)
animation_value_abi_preserves_destination_on_rejection :: proc(t: ^testing.T) {
    state := animation_value_test_state_create()
    testing.expect(t, state != nil)
    defer animation_value_test_state_destroy(state)
    source := [2]u8{4, 5}
    _ = set_animation_value(state, {1, 2, 3}, raw_data(source[:]), 2)
    destination := [2]u8{8, 9}

    testing.expect_value(t, get_animation_value(
        state, {2, 2, 3}, raw_data(destination[:]), 2), i32(BRIDGE_STATUS_NOT_FOUND))
    testing.expect_value(t, get_animation_value(
        state, {1, 2, 4}, raw_data(destination[:]), 2),
        i32(BRIDGE_STATUS_SCHEMA_MISMATCH))
    testing.expect_value(t, get_animation_value(
        state, {1, 2, 3}, raw_data(destination[:]), 1),
        i32(BRIDGE_STATUS_SCHEMA_MISMATCH))
    testing.expect(t, mem.compare(destination[:], []u8{8, 9}) == 0)
}

//   Verify tick reads fall back to their snapshot and newest staged write.
animation_value_test_stage_pending_writes :: proc(
    t: ^testing.T,
    state: ^core.Euclid_General_State,
    identity: Animation_Value_Abi_Identity) {
    pending_values := [2]u8{2, 3}
    for &value in pending_values {
        testing.expect_value(t, set_animation_value(
            state, identity, &value, size_of(value)),
            i32(BRIDGE_STATUS_OK))
    }
}

//   Verify tick reads fall back to their snapshot and newest staged write.
@(test)
animation_value_abi_reads_snapshot_and_newest_pending_write :: proc(t: ^testing.T) {
    state := animation_value_test_state_create()
    testing.expect(t, state != nil)
    defer animation_value_test_state_destroy(state)
    identity := Animation_Value_Abi_Identity{1, 1, 1}
    canonical := [1]u8{1}
    _ = set_animation_value(
        state, identity, raw_data(canonical[:]), len(canonical))
    snapshot: core.Animation_Query_Snapshot
    snapshot.animation_values_valid = core.animation_value_store_pack(
        &state^.animation_values,
        state^.animation_values.generation,
        &snapshot.animation_values) == .Ok
    batch: core.Scene_Command_Batch
    state^.scene_command_batch_target = &batch
    state^.animation_query_snapshot_target = &snapshot
    destination: [1]u8

    testing.expect_value(t, get_animation_value(
        state, identity, raw_data(destination[:]), len(destination)),
        i32(BRIDGE_STATUS_OK))
    testing.expect_value(t, destination[0], u8(1))
    animation_value_test_stage_pending_writes(t, state, identity)
    testing.expect_value(t, get_animation_value(
        state, identity, raw_data(destination[:]), len(destination)),
        i32(BRIDGE_STATUS_OK))
    testing.expect_value(t, destination[0], u8(3))

    state^.scene_command_batch_target = nil
    state^.animation_query_snapshot_target = nil
    testing.expect_value(t, get_animation_value(
        state, identity, raw_data(destination[:]), len(destination)),
        i32(BRIDGE_STATUS_OK))
    testing.expect_value(t, destination[0], u8(1))
}

//   Verify one valid mixed batch publishes its scene command and typed write.
@(test)
animation_value_batch_commits_scene_and_typed_state :: proc(t: ^testing.T) {
    state := animation_value_test_state_create()
    testing.expect(t, state != nil)
    defer animation_value_test_state_destroy(state)
    interface: core.Euclid_Julia_Interface
    world: core.Shape_World
    animation := &interface.null_animation
    state^.julia_interface = &interface
    interface.current_animation = animation
    state^.shape_world = &world
    entity := animation_value_test_entity(&world, {})
    identity := core.Animation_Value_Identity{1, 1, 1, 1}
    _ = core.animation_value_store_set(
        &state^.animation_values, identity, []u8{1})
    batch := core.Scene_Command_Batch{animation = animation, command_count = 1}
    batch.commands[0] = {
        kind = .Set_Shape_Position,
        entity = core.shape_entity_pack(entity),
        position = {2, 3, 4},
    }
    _ = core.animation_value_pending_append(
        &batch.animation_value_writes, identity, []u8{2})

    testing.expect(t, commit_scene_command_batch(state, &batch))
    transform, found := core.shape_component_get(
        &world.transforms, &world.registry, entity)
    testing.expect(t, found && transform^.position == core.Vector3{2, 3, 4})
    destination: [1]u8
    testing.expect_value(t, core.animation_value_store_copy(
        &state^.animation_values, identity, destination[:]),
        core.Animation_Value_Status.Ok)
    testing.expect_value(t, destination[0], u8(2))
}

//   Verify an invalid scene tail preserves canonical typed state.
@(test)
animation_value_batch_rejects_typed_write_with_invalid_scene :: proc(t: ^testing.T) {
    state := animation_value_test_state_create()
    testing.expect(t, state != nil)
    defer animation_value_test_state_destroy(state)
    interface: core.Euclid_Julia_Interface
    world: core.Shape_World
    animation := &interface.null_animation
    state^.julia_interface = &interface
    interface.current_animation = animation
    state^.shape_world = &world
    identity := core.Animation_Value_Identity{1, 1, 1, 1}
    _ = core.animation_value_store_set(
        &state^.animation_values, identity, []u8{1})
    batch := core.Scene_Command_Batch{animation = animation, command_count = 1}
    batch.commands[0] = {
        kind = .Set_Shape_Position,
        entity = core.shape_entity_pack({slot = 1, generation = 1}),
        position = {2, 3, 4},
    }
    _ = core.animation_value_pending_append(
        &batch.animation_value_writes, identity, []u8{2})

    testing.expect(t, !commit_scene_command_batch(state, &batch))
    destination: [1]u8
    _ = core.animation_value_store_copy(
        &state^.animation_values, identity, destination[:])
    testing.expect_value(t, destination[0], u8(1))
}

//   Verify malformed typed state preserves canonical scene state.
@(test)
animation_value_batch_rejects_scene_with_invalid_typed_write :: proc(t: ^testing.T) {
    state := animation_value_test_state_create()
    testing.expect(t, state != nil)
    defer animation_value_test_state_destroy(state)
    interface: core.Euclid_Julia_Interface
    world: core.Shape_World
    animation := &interface.null_animation
    state^.julia_interface = &interface
    interface.current_animation = animation
    state^.shape_world = &world
    entity := animation_value_test_entity(&world, {9, 9, 9})
    batch := core.Scene_Command_Batch{animation = animation, command_count = 1}
    batch.commands[0] = {
        kind = .Set_Shape_Position,
        entity = core.shape_entity_pack(entity),
        position = {2, 3, 4},
    }
    _ = core.animation_value_pending_append(
        &batch.animation_value_writes, {1, 1, 1, 1}, []u8{2})
    batch.animation_value_writes.entries[0].payload_offset =
        i32(core.ANIMATION_VALUE_TOTAL_PAYLOAD_BYTES)

    testing.expect(t, !commit_scene_command_batch(state, &batch))
    transform, found := core.shape_component_get(
        &world.transforms, &world.registry, entity)
    testing.expect(t, found && transform^.position == core.Vector3{9, 9, 9})
}

//   Verify runtime generation rejection prevents stale typed publication.
@(test)
animation_value_stale_tick_does_not_commit_typed_write :: proc(t: ^testing.T) {
    state := animation_value_test_state_create()
    testing.expect(t, state != nil)
    defer animation_value_test_state_destroy(state)
    interface: core.Euclid_Julia_Interface
    service := new(Julia_Runtime_Service, context.allocator)
    testing.expect_value(t, init_julia_runtime_channels(service),
        runtime.Allocator_Error.None)
    defer destroy_julia_runtime_service(service)
    animation := &interface.null_animation
    state^.julia_interface = &interface
    state^.julia_runtime_service = service
    interface.current_animation = animation
    interface.selected_animation = animation
    service.animation_generation = 2
    identity := core.Animation_Value_Identity{1, 1, 1, 1}
    _ = core.animation_value_store_set(
        &state^.animation_values, identity, []u8{1})
    slot := &service.animation_tick_slots[0]
    slot.state = .Accepted
    slot.generation = 1
    slot.sequence = 1
    slot.animation = animation
    slot.scene_batch.animation = animation
    _ = core.animation_value_pending_append(
        &slot.scene_batch.animation_value_writes, identity, []u8{2})

    testing.expect(t, !publish_available_animation_tick(state))
    destination: [1]u8
    _ = core.animation_value_store_copy(
        &state^.animation_values, identity, destination[:])
    testing.expect_value(t, destination[0], u8(1))
}

//   Verify a current scene batch commits without reserving presentation storage.
@(test)
animation_tick_commits_without_view_candidate :: proc(t: ^testing.T) {
    state := animation_value_test_state_create()
    testing.expect(t, state != nil)
    defer animation_value_test_state_destroy(state)
    interface: core.Euclid_Julia_Interface
    service := new(Julia_Runtime_Service, context.allocator)
    testing.expect_value(t, init_julia_runtime_channels(service),
        runtime.Allocator_Error.None)
    defer destroy_julia_runtime_service(service)
    animation := &interface.null_animation
    state^.julia_interface = &interface
    state^.julia_runtime_service = service
    interface.current_animation = animation
    interface.selected_animation = animation
    service.animation_generation = 7
    slot := &service.animation_tick_slots[0]
    slot.state = .Accepted
    slot.generation = 7
    slot.sequence = 1
    slot.animation = animation
    slot.scene_batch.animation = animation
    service.animation_tick_pending = true

    testing.expect(t, publish_available_animation_tick(state))
    testing.expect_value(t, service.animation_last_committed_sequence, u64(1))
    testing.expect(t, !service.animation_tick_pending)
    testing.expect_value(t, slot.state, core.Animation_Tick_Slot_State.Free)
    for snapshot in service.view_snapshots {
        testing.expect_value(t, snapshot.state, core.View_Snapshot_Slot_State.Free)
    }
}
package bridge

import bridgemodel "model"
import core "../core"
import evidence_trace "../evidence/trace"
import shapemodel "../shapes/model"
import shapes "../shapes"

import "core:testing"

// Supply an isolated callback owner for conic command capture tests.
bridge_conic_test_state :: proc() -> ^core.Euclid_General_State {
    state := bridge_shape_test_state()
    state.julia_interface = new(bridgemodel.Euclid_Julia_Interface, context.allocator)
    state.julia_interface.current_animation = &state.julia_interface.null_animation
    return state
}

// Release the callback interface before its owning test state.
bridge_conic_test_destroy :: proc(state: ^core.Euclid_General_State) {
    free(state.julia_interface, context.allocator)
    free(state, context.allocator)
}

// Verify the by-value conic C layouts match the Julia ABI exactly.
@(test)
bridge_conic_abi_layouts_match_contract :: proc(t: ^testing.T) {
    testing.expect_value(t, size_of(shapemodel.Bridge_Parabola_Geometry), 20)
    testing.expect_value(t, size_of(shapemodel.Bridge_Hyperbola_Geometry), 24)
    testing.expect_value(t, size_of(shapemodel.Bridge_Parabola_Tool_Geometry), 24)
    testing.expect_value(t, size_of(shapemodel.Bridge_Hyperbola_Tool_Geometry), 28)
    testing.expect_value(t, size_of(Bridge_Shape_Parabola_Result), 16)
    testing.expect_value(t, size_of(Bridge_Shape_Hyperbola_Result), 16)
    testing.expect_value(t, size_of(Bridge_Shape_Parabola_Query_Result), 40)
    testing.expect_value(t, size_of(Bridge_Shape_Hyperbola_Query_Result), 48)
}

// Verify complete conic setters preserve immutable worker snapshots.
@(test)
bridge_conic_queries_read_immutable_snapshot :: proc(t: ^testing.T) {
    state := bridge_conic_test_state()
    defer bridge_conic_test_destroy(state)
    parabola := shape_create_parabola(state, {},
        {0.075, 0, -1.6, 1.6, -1.6}, bridge_shape_test_input({}).style)
    hyperbola := shape_create_hyperbola(state, {},
        {0.12, 0.1, 0, -1.35, 1.35, -1.35}, bridge_shape_test_input({}).style)
    testing.expect_value(t, parabola.status, i32(BRIDGE_STATUS_OK))
    testing.expect_value(t, hyperbola.status, i32(BRIDGE_STATUS_OK))
    snapshot := new(Animation_Query_Snapshot, context.allocator)
    defer free(snapshot, context.allocator)
    capture_animation_query_snapshot(state, snapshot)
    state.animation_query_snapshot_target = snapshot
    testing.expect_value(t, shape_set_parabola(
        state, parabola.shape, {0.08, 0.2, -1, 1, 0}), i32(BRIDGE_STATUS_OK))
    testing.expect_value(t, shape_set_hyperbola(
        state, hyperbola.shape, {0.14, 0.11, 0.2, -1, 1, 0}), i32(BRIDGE_STATUS_OK))
    testing.expect_value(t,
        shape_get_parabola(state, parabola.shape).geometry.focal_distance, f32(0.075))
    testing.expect_value(t,
        shape_get_hyperbola(state, hyperbola.shape).geometry.semimajor, f32(0.12))
    state.animation_query_snapshot_target = nil
    testing.expect_value(t,
        shape_get_parabola(state, parabola.shape).geometry.focal_distance, f32(0.08))
    testing.expect_value(t,
        shape_get_hyperbola(state, hyperbola.shape).geometry.semimajor, f32(0.14))
}

// Verify both frontier command kinds commit atomically and expose stable evidence IDs.
@(test)
bridge_conic_frontiers_commit_with_typed_events :: proc(t: ^testing.T) {
    state := bridge_conic_test_state()
    defer bridge_conic_test_destroy(state)
    parabola := shape_create_parabola(state, {},
        {0.075, 0, -1.6, 1.6, -1.6}, bridge_shape_test_input({}).style)
    hyperbola := shape_create_hyperbola(state, {},
        {0.12, 0.1, 0, -1.35, 1.35, -1.35}, bridge_shape_test_input({}).style)
    batch: Scene_Command_Batch
    begin_scene_command_batch(state, &batch)
    testing.expect_value(t, shape_set_parabola_frontier(
        state, parabola.shape, 0.4), i32(BRIDGE_STATUS_OK))
    testing.expect_value(t, shape_set_hyperbola_frontier(
        state, hyperbola.shape, 0.4), i32(BRIDGE_STATUS_OK))
    end_scene_command_batch(state)
    testing.expect_value(t,
        shape_get_parabola(state, parabola.shape).geometry.draw_parameter, f32(-1.6))
    testing.expect(t, commit_scene_command_batch(state, &batch))
    testing.expect_value(t,
        shape_get_parabola(state, parabola.shape).geometry.draw_parameter, f32(0.4))
    testing.expect_value(t,
        shape_get_hyperbola(state, hyperbola.shape).geometry.draw_parameter, f32(0.4))
    first_kind, _ := scene_command_evidence(&batch.commands[0])
    second_kind, _ := scene_command_evidence(&batch.commands[1])
    testing.expect_value(t, first_kind, evidence_trace.Kind.Parabola_Frontier_Committed)
    testing.expect_value(t, second_kind, evidence_trace.Kind.Hyperbola_Frontier_Committed)
    testing.expect_value(t, u16(first_kind), u16(191))
    testing.expect_value(t, u16(second_kind), u16(193))
}

// Verify an invalid frontier rejects the entire captured batch before any mutation.
@(test)
bridge_conic_invalid_frontier_rolls_back_scene_batch :: proc(t: ^testing.T) {
    state := bridge_conic_test_state()
    defer bridge_conic_test_destroy(state)
    parabola := shape_create_parabola(state, {},
        {0.075, 0, -1, 1, -1}, bridge_shape_test_input({}).style)
    hyperbola := shape_create_hyperbola(state, {},
        {0.12, 0.1, 0, -1, 1, -1}, bridge_shape_test_input({}).style)
    testing.expect_value(t, shape_set_parabola(
        state, parabola.shape, {0.075, 0, 1, 1, 1}), i32(BRIDGE_STATUS_INVALID_ARGUMENT))
    batch: Scene_Command_Batch
    begin_scene_command_batch(state, &batch)
    testing.expect_value(t, shape_set_parabola_frontier(
        state, parabola.shape, 0.5), i32(BRIDGE_STATUS_OK))
    testing.expect_value(t, shape_set_hyperbola_frontier(
        state, hyperbola.shape, 2), i32(BRIDGE_STATUS_OK))
    end_scene_command_batch(state)
    testing.expect(t, !commit_scene_command_batch(state, &batch))
    testing.expect_value(t,
        shape_get_parabola(state, parabola.shape).geometry.draw_parameter, f32(-1))
    testing.expect_value(t,
        shape_get_hyperbola(state, hyperbola.shape).geometry.draw_parameter, f32(-1))
}

// Verify geometry and frontier evidence identify the same complete hyperbola.
@(test)
bridge_conic_evidence_identifies_complete_hyperbola :: proc(t: ^testing.T) {
    state := bridge_conic_test_state()
    defer bridge_conic_test_destroy(state)
    shape := shape_create_hyperbola(state, {},
        {0.12, 0.1, 0, -1, 1, -1}, bridge_shape_test_input({}).style)
    batch: Scene_Command_Batch
    begin_scene_command_batch(state, &batch)
    _ = shape_set_hyperbola(state, shape.shape, {0.12, 0.1, 0, -1, 1, -1})
    _ = shape_set_hyperbola_frontier(state, shape.shape, 0.5)
    end_scene_command_batch(state)
    testing.expect(t, commit_scene_command_batch(state, &batch))
    testing.expect_value(t, batch.command_count, 2)
    for index in 0..<2 {
        command := &batch.commands[index]
        _, payload := scene_command_evidence(command)
        testing.expect_value(t, payload.point.point_index,
            shapemodel.shape_entity_unpack(shape.shape).slot - 1)
        testing.expect_value(t, payload.point.field, u16(command.kind))
    }
}

// Verify a reused animation slot does not admit stale conic queries or mutations.
@(test)
bridge_conic_stale_handles_reject_queries_and_commands :: proc(t: ^testing.T) {
    state := bridge_conic_test_state()
    defer bridge_conic_test_destroy(state)
    testing.expect_value(t, shapemodel.shape_world_freeze_baseline(
        &state.shape_world), shapemodel.Shape_World_Status.Ok)
    stale := shape_create_parabola(state, {},
        {0.075, 0, -1, 1, -1}, bridge_shape_test_input({}).style)
    testing.expect_value(t, shapemodel.shape_world_rewind_animation(
        &state.shape_world), shapemodel.Shape_World_Status.Ok)
    current := shape_create_parabola(state, {},
        {0.08, 0, -1, 1, -1}, bridge_shape_test_input({}).style)
    testing.expect(t, stale.shape != current.shape)
    testing.expect_value(t,
        shape_get_parabola(state, stale.shape).status, i32(BRIDGE_STATUS_NOT_FOUND))
    testing.expect_value(t, shape_set_parabola_frontier(
        state, stale.shape, 0), i32(BRIDGE_STATUS_NOT_FOUND))
    batch: Scene_Command_Batch
    begin_scene_command_batch(state, &batch)
    _ = shape_set_parabola_frontier(state, stale.shape, 0)
    end_scene_command_batch(state)
    testing.expect(t, !commit_scene_command_batch(state, &batch))
    testing.expect_value(t,
        shape_get_parabola(state, current.shape).geometry.draw_parameter, f32(-1))
}

// Verify stale complete-hyperbola identities cannot query or mutate a reused slot.
@(test)
bridge_hyperbola_stale_identity_rejects_reused_slot :: proc(t: ^testing.T) {
    state := bridge_conic_test_state()
    defer bridge_conic_test_destroy(state)
    _ = shapemodel.shape_world_freeze_baseline(&state.shape_world)
    geometry: shapemodel.Bridge_Hyperbola_Geometry = {0.12, 0.1, 0, -1, 1, -1}
    stale := shape_create_hyperbola(
        state, {}, geometry, bridge_shape_test_input({}).style)
    _ = shapemodel.shape_world_rewind_animation(&state.shape_world)
    current := shape_create_hyperbola(
        state, {}, geometry, bridge_shape_test_input({}).style)
    testing.expect(t, stale.shape != current.shape)
    testing.expect_value(t, shape_get_hyperbola(
        state, stale.shape).status, i32(BRIDGE_STATUS_NOT_FOUND))
    testing.expect_value(t, shape_set_hyperbola_frontier(
        state, stale.shape, 0), i32(BRIDGE_STATUS_NOT_FOUND))
    batch: Scene_Command_Batch
    begin_scene_command_batch(state, &batch)
    _ = shape_set_hyperbola_frontier(state, current.shape, 0.5)
    _ = shape_set_hyperbola(state, stale.shape, geometry)
    end_scene_command_batch(state)
    testing.expect(t, !commit_scene_command_batch(state, &batch))
    testing.expect_value(t, shape_get_hyperbola(
        state, current.shape).geometry.draw_parameter, f32(-1))
}

// Verify one complete hyperbola records one Julia-owner construction event.
@(test)
bridge_conic_construction_evidence_uses_host_owned_ring :: proc(t: ^testing.T) {
    state := bridge_conic_test_state()
    defer bridge_conic_test_destroy(state)
    service := new(Julia_Runtime_Service, context.allocator)
    defer free(service, context.allocator)
    state.julia_runtime_service = service
    state.evidence_session.enabled = true
    state.evidence_session.lanes = {.Domain}
    service.evidence_session = &state.evidence_session
    service.animation_generation = 7
    evidence_trace.ring_init(&service.evidence_ring, .Julia_Host)
    shape := shape_create_hyperbola(state, {},
        {0.12, 0.1, 0, -1, 1, -1}, bridge_shape_test_input({}).style)
    testing.expect_value(t, service.evidence_ring.count, 1)
    testing.expect_value(t, state.evidence_ring.count, 0)
    first := service.evidence_ring.events[0]
    testing.expect_value(t, first.producer, evidence_trace.Producer.Julia_Host)
    testing.expect_value(t, first.kind, evidence_trace.Kind.Hyperbola_Geometry_Committed)
    testing.expect_value(t, first.generation, u64(7))
    testing.expect_value(t, first.payload.point.point_index,
        shapemodel.shape_entity_unpack(shape.shape).slot - 1)
}

// Construct and retain both native instruments for bridge callback lifecycle tests.
bridge_conic_test_create_tools :: proc(t: ^testing.T, state: ^core.Euclid_General_State) {
    parabola, parabola_status := shapes.world_create_parabola_tool(&state.shape_world, {
        focal_distance = 0.075,
        link_length = 0.16,
        parameter_start = -1.6,
        parameter_finish = 1.6,
    })
    hyperbola, hyperbola_status := shapes.world_create_hyperbola_tool(
        &state.shape_world, {
            semimajor = 0.12,
            semiminor = 0.1,
            rail_half_length = 0.4,
            parameter_start = -1.35,
            parameter_finish = 1.35,
        })
    testing.expect_value(t, parabola_status, shapemodel.Shape_World_Status.Ok)
    testing.expect_value(t, hyperbola_status, shapemodel.Shape_World_Status.Ok)
    state.world_parabola_tool = parabola
    state.world_hyperbola_tool = hyperbola
}

// Verify captured tool geometry, contact state, and parameters apply at the owner boundary.
@(test)
bridge_conic_tool_commands_preserve_contact_and_snapshot_state :: proc(t: ^testing.T) {
    state := bridge_conic_test_state()
    defer bridge_conic_test_destroy(state)
    bridge_conic_test_create_tools(t, state)
    snapshot := new(Animation_Query_Snapshot, context.allocator)
    defer free(snapshot, context.allocator)
    capture_animation_query_snapshot(state, snapshot)
    batch: Scene_Command_Batch
    begin_scene_command_batch(state, &batch)
    state.animation_query_snapshot_target = snapshot
    _ = set_parabola_tool_active(state, 1, {200, 30, 40, 255})
    _ = set_hyperbola_tool_active(state, 1, {200, 30, 40, 255})
    _ = set_parabola_tool_geometry(state, {0.075, 0.16, 0.2, -1.6, 1.6, 0})
    _ = set_hyperbola_tool_geometry(state, {0.12, 0.1, 0.2, -1.35, 1.35, 0, 0.4})
    testing.expect_value(t,
        set_parabola_tool_parameter(state, 0.5), i32(BRIDGE_STATUS_OK))
    testing.expect_value(t,
        set_hyperbola_tool_parameter(state, 0.5), i32(BRIDGE_STATUS_OK))
    testing.expect_value(t, snapshot.shapes.parabola_tools.values[0].parameter, f32(0))
    state.animation_query_snapshot_target = nil
    end_scene_command_batch(state)
    testing.expect(t, commit_scene_command_batch(state, &batch))
    testing.expect(t, state.shape_world.parabola_tools.values[0].active)
    testing.expect_value(t, state.shape_world.hyperbola_tools.values[0].active_branches,
        shapemodel.Hyperbola_Branches.Both)
    testing.expect_value(t,
        state.shape_world.parabola_tools.values[0].parameter, f32(0.5))
    testing.expect_value(t,
        state.shape_world.hyperbola_tools.values[0].parameter, f32(0.5))
    bridge_conic_test_assert_payload(t, &batch.commands[2], state.world_parabola_tool)
    bridge_conic_test_assert_payload(t, &batch.commands[3], state.world_hyperbola_tool)
    bridge_conic_test_assert_payload(t, &batch.commands[4], state.world_parabola_tool)
    bridge_conic_test_assert_payload(t, &batch.commands[5], state.world_hyperbola_tool)
}

// Assert compact geometry evidence carries its resolved host index and command field.
bridge_conic_test_assert_payload :: proc(
    t: ^testing.T, command: ^Scene_Command, entity: shapemodel.Shape_Entity) {
    _, payload := scene_command_evidence(command)
    testing.expect_value(t, payload.point.point_index, entity.slot - 1)
    testing.expect_value(t, payload.point.field, u16(command.kind))
}

// Verify selection survives native queries, snapshots, and captured geometry updates.
@(test)
bridge_hyperbola_selection_is_immutable :: proc(t: ^testing.T) {
    state := bridge_conic_test_state()
    defer bridge_conic_test_destroy(state)
    selections := [?]shapemodel.Hyperbola_Branches{.Both, .Positive, .Negative}
    for selection in selections {
        shape := shape_create_hyperbola(state, {},
            {0.12, 0.1, 0, -1, 1, -1}, bridge_shape_test_input({}).style, selection)
        testing.expect_value(t, shape.status, i32(BRIDGE_STATUS_OK))
        testing.expect_value(t,
            shape_get_hyperbola(state, shape.shape).branches, selection)
        snapshot := new(Animation_Query_Snapshot, context.allocator)
        capture_animation_query_snapshot(state, snapshot)
        state.animation_query_snapshot_target = snapshot
        _ = shape_set_hyperbola(state, shape.shape, {0.14, 0.11, 0.4, 1, -1, 0.5})
        testing.expect_value(t,
            shape_get_hyperbola(state, shape.shape).branches, selection)
        testing.expect_value(t,
            shape_get_hyperbola(state, shape.shape).geometry.semimajor, f32(0.12))
        state.animation_query_snapshot_target = nil
        free(snapshot, context.allocator)
        batch: Scene_Command_Batch
        begin_scene_command_batch(state, &batch)
        _ = shape_set_hyperbola(state, shape.shape, {0.16, 0.12, 0.8, 1, -1, 0.5})
        _ = shape_set_hyperbola_frontier(state, shape.shape, -0.5)
        end_scene_command_batch(state)
        testing.expect(t, commit_scene_command_batch(state, &batch))
        result := shape_get_hyperbola(state, shape.shape)
        testing.expect_value(t, result.branches, selection)
        testing.expect_value(t, result.geometry.rotation, f32(0.8))
        testing.expect_value(t, result.geometry.draw_parameter, f32(-0.5))
    }
}

// Verify captured contact selection and geometry changes preserve inactive nibs.
@(test)
bridge_hyperbola_contact_selection_survives_geometry :: proc(t: ^testing.T) {
    state := bridge_conic_test_state()
    defer bridge_conic_test_destroy(state)
    bridge_conic_test_create_tools(t, state)
    selections := [?]shapemodel.Hyperbola_Branches{.Both, .Positive, .Negative}
    for selection in selections {
        batch: Scene_Command_Batch
        begin_scene_command_batch(state, &batch)
        _ = set_hyperbola_tool_active(state, 1, {}, selection)
        _ = set_hyperbola_tool_geometry(state, {0.12, 0.1, 0.4, -1, 1, 0.5, 0.4})
        end_scene_command_batch(state)
        testing.expect(t, commit_scene_command_batch(state, &batch))
        testing.expect_value(t,
            state.shape_world.hyperbola_tools.values[0].active_branches, selection)
        _ = set_hyperbola_tool_active(state, 0, {}, selection)
        testing.expect_value(t,
            state.shape_world.hyperbola_tools.values[0].active_branches,
            shapemodel.Hyperbola_Branches.None)
    }
    testing.expect_value(t, set_hyperbola_tool_active(state, 2, {}),
        i32(BRIDGE_STATUS_INVALID_ARGUMENT))
    testing.expect_value(t, set_hyperbola_tool_active(state, 1, {}, .None),
        i32(BRIDGE_STATUS_INVALID_ARGUMENT))
    batch: Scene_Command_Batch
    begin_scene_command_batch(state, &batch)
    _ = set_hyperbola_tool_active(state, 1, {}, .Positive)
    end_scene_command_batch(state)
    batch.commands[0].integer = 4
    testing.expect(t, !commit_scene_command_batch(state, &batch))
    testing.expect_value(t, state.shape_world.hyperbola_tools.values[0].active_branches,
        shapemodel.Hyperbola_Branches.None)
}

// Inspect selected-ink departure without connecting or emitting an unselected branch.
bridge_test_hyperbola_departure_selection :: proc(
    t: ^testing.T, selection: shapemodel.Hyperbola_Branches) {
    state := bridge_conic_test_state()
    defer bridge_conic_test_destroy(state)
    state.particle_system.use_max_dust_particles = 256
    shape := shape_create_hyperbola(state, {0.5, 0.5, 0},
        {0.12, 0.1, 0, -1.35, 1.35, 1.35}, bridge_shape_test_input({}).style, selection)
    testing.expect_value(t, shape_set_visible(
        state, shape.shape, 1), i32(BRIDGE_STATUS_OK))
    testing.expect_value(t, shape_set_visible(
        state, shape.shape, 0), i32(BRIDGE_STATUS_OK))
    positive_dust, negative_dust := 0, 0
    for index in 0..<state.particle_system.use_max_dust_particles {
        particle := state.particle_system.low_particles[index]
        if !particle.alive {
            continue
        }
        testing.expect(t, particle.authored_ink)
        testing.expectf(t, particle.pos_x < 0.39 || particle.pos_x > 0.61,
            "branch dust must retain the empty center gap")
        if particle.pos_x > 0.5 {
            positive_dust += 1
        } else {
            negative_dust += 1
        }
    }
    testing.expect_value(t, positive_dust > 0,
        shapemodel.hyperbola_branch_is_selected(selection, 1))
    testing.expect_value(t, negative_dust > 0,
        shapemodel.hyperbola_branch_is_selected(selection, -1))
    _ = shape_set_visible(state, shape.shape, 1)
    testing.expect_value(t, shape_get_hyperbola(state, shape.shape).branches, selection)
}

// Verify one hide departs exactly the selected branches and show retains selection.
@(test)
bridge_conic_branch_departures_do_not_bridge_center :: proc(t: ^testing.T) {
    selections := [?]shapemodel.Hyperbola_Branches{.Both, .Positive, .Negative}
    for selection in selections {
        bridge_test_hyperbola_departure_selection(t, selection)
    }
}

// Verify permanent conic tool hides never emit authored-ink departure dust.
@(test)
bridge_conic_tool_hide_has_no_ink_departure :: proc(t: ^testing.T) {
    state := bridge_conic_test_state()
    defer bridge_conic_test_destroy(state)
    state.particle_system.use_max_dust_particles = 64
    bridge_conic_test_create_tools(t, state)
    testing.expect_value(t, show_parabola_tool(state), i32(BRIDGE_STATUS_OK))
    testing.expect_value(t, hide_parabola_tool(state), i32(BRIDGE_STATUS_OK))
    for alive in state.particle_system.low_particles.alive[:64] {
        testing.expect(t, !alive)
    }
}

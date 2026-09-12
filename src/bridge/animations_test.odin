package bridge

import "../core"
import "../shapes"

import "core:testing"

//   Verify programmatic selection synchronizes flags, ancestry, and reveal intent.
@(test)
programmatic_selection_synchronizes_tree_state :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state)
    ji := &state^.julia_interface_slots[0]
    state^.julia_interface = ji
    nodes: [3]core.Euclid_Julia_Animation_Interface
    ji.animation_head = &nodes[0]
    ji.animation_count = len(nodes)
    nodes[0].next_in_registry = &nodes[1]
    nodes[1].next_in_registry = &nodes[2]
    nodes[0].first_child = &nodes[1]
    nodes[1].parent = &nodes[0]
    nodes[1].first_child = &nodes[2]
    nodes[2].parent = &nodes[1]
    nodes[0].is_selected = true

    testing.expect(t, select_animation_programmatically(state, &nodes[2]))
    testing.expect_value(t, ji.selected_animation, &nodes[2])
    testing.expect(t, !nodes[0].is_selected && !nodes[1].is_selected)
    testing.expect(t, nodes[2].is_selected)
    testing.expect(t, nodes[0].is_expanded && nodes[1].is_expanded)
    testing.expect(t, state^.ui_runtime.tree_reveal_pending)
    testing.expect_value(t,
        state^.ui_runtime.tree_reveal_stable_id, nodes[2].stable_id)
}

//   Verify a target outside the registry cannot disturb current selection.
@(test)
programmatic_selection_rejects_unregistered_target :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state)
    ji := &state^.julia_interface_slots[0]
    state^.julia_interface = ji
    selected, outsider: core.Euclid_Julia_Animation_Interface
    ji.animation_head = &selected
    ji.animation_count = 1
    ji.selected_animation = &selected
    selected.is_selected = true

    testing.expect(t, !select_animation_programmatically(state, &outsider))
    testing.expect_value(t, ji.selected_animation, &selected)
    testing.expect(t, selected.is_selected)
    testing.expect(t, !state^.ui_runtime.tree_reveal_pending)
}

//   Verify an explicit reload request schedules owner-thread lifecycle work.
@(test)
explicit_reload_requests_animation_lifecycle_update :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state)
    service := new(core.Julia_Runtime_Service, context.allocator)
    defer free(service)
    ji := &state^.julia_interface_slots[0]
    animation := &ji^.null_animation
    state^.julia_interface = ji
    state^.julia_runtime_service = service
    ji^.selected_animation = animation
    ji^.current_animation = animation
    service^.reload_requested = true

    testing.expect(t, animation_lifecycle_update_needed(state))
}

//   Verify retirement emits clear effects while animation geometry is still valid.
@(test)
animation_retirement_emits_before_world_rewind :: proc(t: ^testing.T) {
    state := animation_value_test_state_create()
    testing.expect(t, state != nil)
    if state == nil {return}
    defer animation_value_test_state_destroy(state)
    world: core.Shape_World
    particles := new(core.Particle_System, context.allocator)
    defer free(particles, context.allocator)
    service := new(core.Julia_Runtime_Service, context.allocator)
    defer free(service, context.allocator)
    service^.animation_generation = 1
    state^.shape_world = &world
    state^.particle_system = particles
    state^.julia_runtime_service = service
    particles^.use_max_dust_particles = 4
    testing.expect_value(t,
        core.shape_world_freeze_baseline(&world), core.Shape_World_Status.Ok)
    line, status := shapes.world_create_line(
        &world, {0, 0, 0}, {1, 0, 0}, {})
    testing.expect_value(t, status, core.Shape_World_Status.Ok)
    style, found := core.shape_component_get_mut(
        &world.render_styles, &world.registry, line.shape)
    testing.expect(t, found)
    if found {style^.visible = true}

    testing.expect(t, reset_animation_switch_state(state))

    testing.expect(t, particles^.low_particles.alive[0])
    testing.expect_value(t, world.registry.entity_count, u32(0))
    testing.expect_value(t, world.transforms.count, u16(0))
    testing.expect(t, !core.shape_registry_resolves(&world.registry, line.shape))
}
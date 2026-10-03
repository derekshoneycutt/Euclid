package bridge

import bridgemodel "model"

import particlemodel "../particles/model"
import shapemodel "../shapes/model"
import contentdata "../core/content"

import "../core"
import "../shapes"
import content "../view/content"

import "core:encoding/uuid"
import "core:strings"
import "core:testing"

//   Build a compact generation fixture with intentionally nonsequential child order.
catalog_materializer_test_snapshot :: proc() -> ^content.Content_Generation {
    generation := new(content.Content_Generation, context.allocator)
    if contentdata.content_generation_init(generation) != .Ok ||
       contentdata.content_generation_begin(generation, 17) != .Ok {
        contentdata.content_generation_destroy(generation)
        free(generation, context.allocator)
        return nil
    }
    records := [?]content.Catalog_Record{
        {stable_id = catalog_materializer_test_id(1), node_kind = .Category,
            sibling_order = 0, catalog_order = 0},
        {stable_id = catalog_materializer_test_id(2),
            parent_stable_id = catalog_materializer_test_id(1), has_parent = true,
            node_kind = .Leaf, sibling_order = 5, catalog_order = 1},
        {stable_id = catalog_materializer_test_id(3),
            parent_stable_id = catalog_materializer_test_id(1), has_parent = true,
            node_kind = .Leaf, sibling_order = 1, catalog_order = 2},
        {stable_id = catalog_materializer_test_id(4), node_kind = .Terminal,
            sibling_order = 1, catalog_order = 3},
    }
    names := [?]string{"Root", "Later child", "Earlier child", "Terminal"}
    paths := [?]string{"root.jl", "later.jl", "earlier.jl", ""}
    for index in 0..<len(records) {
        if !catalog_materializer_test_append(
            generation, &records[index], names[index], paths[index]) {
            contentdata.content_generation_destroy(generation)
            free(generation, context.allocator)
            return nil
        }
    }
    if contentdata.content_generation_seal(generation) != .Ok {
        contentdata.content_generation_destroy(generation)
        free(generation, context.allocator)
        return nil
    }
    return generation
}

//   Append one record's strings before storing its generation-local references.
catalog_materializer_test_append :: proc(
    generation: ^content.Content_Generation, record: ^content.Catalog_Record,
    name, path: string) -> bool {
    name_status := contentdata.content_generation_append_text(
        generation, name, content.CATALOG_NAME_BYTE_CAPACITY, &record^.display_name)
    path_status := contentdata.content_generation_append_text(
        generation, path, content.CATALOG_PATH_BYTE_CAPACITY,
        &record^.implementation_path)
    if name_status != .Ok || path_status != .Ok {
        return false
    }
    return contentdata.content_generation_append_record(generation, record^) == .Ok
}

//   Return a distinct nonzero stable identity for one fixture record.
catalog_materializer_test_id :: proc(value: u8) -> uuid.Identifier {
    identifier: uuid.Identifier
    identifier[15] = value
    return identifier
}

// Verify snapshot materialization preserves identity, paths, and both orderings.
@(test)
catalog_snapshot_materializes_native_registry :: proc(t: ^testing.T) {
    iface: bridgemodel.Euclid_Julia_Interface
    defer destroy_julia_interface_instance(&iface)
    snapshot := catalog_materializer_test_snapshot()
    defer free(snapshot, context.allocator)
    defer contentdata.content_generation_destroy(snapshot)
    testing.expect(t, content_generation_materialize(&iface, snapshot))
    testing.expect_value(t, iface.content_generation, u64(17))
    testing.expect_value(t, iface.animation_count, 4)
    root := animation_lookup_find(&iface, catalog_materializer_test_id(1))
    testing.expect(t, root != nil)
    if root == nil {
         return 
    }
    testing.expect_value(t, root^.name, "Root")
    testing.expect_value(t, root^.implementation_path, "root.jl")
    testing.expect_value(t, contentdata.content_generation_reset(snapshot),
        contentdata.Content_Generation_Status.Ok)
    testing.expect_value(t, root^.name, "Root")
    testing.expect_value(t, root^.implementation_path, "root.jl")
    testing.expect_value(t, root^.next_in_registry^.catalog_order, i32(1))
    testing.expect_value(t, root^.first_child^.sibling_order, i32(1))
    testing.expect_value(t, root^.first_child^.next_sibling^.sibling_order, i32(5))
    testing.expect_value(t, root^.first_child^.parent, root)
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state)
    state^.julia_interface = &iface
    select_default_animation(state)
    testing.expect_value(t, iface.selected_animation, root)
    clean_julia_interface_instance(&iface)
    testing.expect_value(t, iface.animation_count, 0)
    testing.expect_value(t, iface.content_generation, u64(0))
    testing.expect(t,
        animation_lookup_find(&iface, catalog_materializer_test_id(1)) == nil)
}

// Verify UUID lookup copies only bounded path bytes and reports Terminal explicitly.
@(test)
catalog_path_copy_uses_materialized_registry :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state)
    iface := &state^.julia_interface_slots[0]
    state^.julia_interface = iface
    state^.saved_context = context
    snapshot := catalog_materializer_test_snapshot()
    defer free(snapshot, context.allocator)
    defer contentdata.content_generation_destroy(snapshot)
    testing.expect(t, content_generation_materialize(iface, snapshot))

    destination: [16]u8
    status, metadata := catalog_path_copy_test_call(
        state, catalog_materializer_test_id(2), destination[:], i32(len(destination)))
    testing.expect_value(t, status, BRIDGE_STATUS_OK)
    testing.expect_value(t, metadata.byte_count, i32(len("later.jl")))
    testing.expect_value(t, metadata.node_kind,
        i32(bridgemodel.Animation_Node_Kind.Leaf))
    testing.expect_value(t, string(destination[:metadata.byte_count]), "later.jl")

    for index in 0..<len(destination) {
        destination[index] = 0x7f
    }
    status, metadata = catalog_path_copy_test_call(
        state, catalog_materializer_test_id(2), destination[:], 4)
    testing.expect_value(t, status, BRIDGE_STATUS_OUT_OF_CAPACITY)
    testing.expect_value(t, metadata.byte_count, i32(len("later.jl")))
    testing.expect_value(t, destination[0], u8(0x7f))

    status, metadata = catalog_path_copy_test_call(
        state, catalog_materializer_test_id(4), destination[:], i32(len(destination)))
    testing.expect_value(t, status, BRIDGE_STATUS_OK)
    testing.expect_value(t, metadata.byte_count, i32(0))
    testing.expect_value(t, metadata.node_kind,
        i32(bridgemodel.Animation_Node_Kind.Terminal))

    status, _ = catalog_path_copy_test_call(
        state, catalog_materializer_test_id(99), destination[:], i32(len(destination)))
    testing.expect_value(t, status, BRIDGE_STATUS_NOT_FOUND)
}

// Route a stable UUID through the C ABI with caller-owned bounded destination bytes.
catalog_path_copy_test_call :: proc(
    state: ^core.Euclid_General_State, stable_id: uuid.Identifier,
    destination: []u8, capacity: i32) -> (
        i32, Animation_Implementation_Path_Metadata) {
    stable_id_buffer: [36]u8
    stable_id_text := uuid.to_string(stable_id, stable_id_buffer[:])
    stable_id_cstr := strings.clone_to_cstring(stable_id_text, context.temp_allocator)
    metadata: Animation_Implementation_Path_Metadata
    status := copy_animation_implementation_path(
        state, stable_id_cstr, &destination[0], capacity, &metadata)
    return status, metadata
}

// Verify malformed snapshots fail closed and leave no partially published registry.
@(test)
catalog_snapshot_materializer_rejects_invalid_topology :: proc(t: ^testing.T) {
    iface: bridgemodel.Euclid_Julia_Interface
    defer destroy_julia_interface_instance(&iface)
    snapshot := catalog_materializer_test_snapshot()
    defer free(snapshot, context.allocator)
    defer contentdata.content_generation_destroy(snapshot)
    snapshot^.records[2].stable_id = snapshot^.records[1].stable_id
    testing.expect(t, !content_generation_materialize(&iface, snapshot))
    testing.expect_value(t, iface.animation_count, 0)
    testing.expect_value(t, iface.animation_lookup_count, 0)
    snapshot^.records[2].stable_id = catalog_materializer_test_id(3)
    snapshot^.records[2].parent_stable_id = catalog_materializer_test_id(9)
    testing.expect(t, !content_generation_materialize(&iface, snapshot))
    testing.expect_value(t, iface.animation_count, 0)
    testing.expect_value(t, iface.content_generation, u64(0))
}

//   Verify programmatic selection synchronizes flags, ancestry, and reveal intent.
@(test)
programmatic_selection_synchronizes_tree_state :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state)
    defer destroy_julia_interface_resources(state)
    ji := &state^.julia_interface_slots[0]
    state^.julia_interface = ji
    snapshot := catalog_materializer_test_snapshot()
    defer free(snapshot, context.allocator)
    defer contentdata.content_generation_destroy(snapshot)
    testing.expect(t, content_generation_materialize(ji, snapshot))
    root := animation_lookup_find(ji, catalog_materializer_test_id(1))
    selected := animation_lookup_find(ji, catalog_materializer_test_id(2))
    earlier_sibling := animation_lookup_find(ji, catalog_materializer_test_id(3))
    testing.expect(t, root != nil && selected != nil && earlier_sibling != nil)
    if root == nil || selected == nil || earlier_sibling == nil {
         return 
    }

    testing.expect(t, select_animation_programmatically(state, selected))
    testing.expect_value(t, ji.selected_animation, selected)
    testing.expect(t, !root^.is_selected && !earlier_sibling^.is_selected)
    testing.expect(t, selected^.is_selected)
    testing.expect(t, root^.is_expanded)
    testing.expect(t, state^.ui_runtime.tree_reveal_pending)
    testing.expect_value(t,
        state^.ui_runtime.tree_reveal_stable_id, selected^.stable_id)
}

//   Verify a target outside the registry cannot disturb current selection.
@(test)
programmatic_selection_rejects_unregistered_target :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state)
    ji := &state^.julia_interface_slots[0]
    state^.julia_interface = ji
    selected, outsider: bridgemodel.Euclid_Julia_Animation_Interface
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
    service := new(bridgemodel.Julia_Runtime_Service, context.allocator)
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
    if state == nil {
        return
    }
    defer animation_value_test_state_destroy(state)
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    particles := new(particlemodel.Particle_System, context.allocator)
    defer free(particles, context.allocator)
    service := new(bridgemodel.Julia_Runtime_Service, context.allocator)
    defer free(service, context.allocator)
    service^.animation_generation = 1
    state^.shape_world = world
    state^.particle_system = particles
    state^.julia_runtime_service = service
    particles^.use_max_dust_particles = 4
    testing.expect_value(t,
        shapemodel.shape_world_freeze_baseline(world), shapemodel.Shape_World_Status.Ok)
    line, status := shapes.world_create_line(
        world, {0, 0, 0}, {1, 0, 0}, {})
    testing.expect_value(t, status, shapemodel.Shape_World_Status.Ok)
    style, found := shapemodel.shape_component_get_mut(
        &world.render_styles, &world.registry, line.shape)
    testing.expect(t, found)
    if found {
        style^.visible = true
    }

    testing.expect(t, reset_animation_switch_state(state))

    testing.expect(t, particles^.low_particles.alive[0])
    testing.expect_value(t, world.registry.entity_count, u32(0))
    testing.expect_value(t, world.transforms.count, u16(0))
    testing.expect(t, !shapemodel.shape_registry_resolves(&world.registry, line.shape))
}
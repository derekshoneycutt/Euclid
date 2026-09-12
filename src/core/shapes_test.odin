package core

import "core:testing"

// Supply a minimal scalar payload for generic component-set tests.
Shape_Test_Value :: struct {
    number: i32,
}

// Verify packed entities preserve both ABI-width identity fields.
@(test)
core_test_shape_entity_pack_round_trip :: proc(t: ^testing.T) {
    entity := Shape_Entity{slot = 0x1234_5678, generation = 0x9abc_def0}
    testing.expect_value(t, shape_entity_unpack(shape_entity_pack(entity)), entity)
    testing.expect_value(t, shape_entity_pack({}), u64(0))
}

// Verify registry rewind retains baseline identities and rejects stale animation handles.
@(test)
core_test_shape_registry_rewinds_animation_suffix :: proc(t: ^testing.T) {
    registry: Shape_Registry
    baseline, animation: Shape_Entity
    testing.expect_value(t, shape_registry_create(
        &registry, &baseline), Shape_World_Status.Ok)
    testing.expect_value(t, shape_registry_freeze_baseline(
        &registry), Shape_World_Status.Ok)
    testing.expect_value(t, shape_registry_create(
        &registry, &animation), Shape_World_Status.Ok)
    testing.expect(t, shape_registry_resolves(&registry, baseline))
    testing.expect(t, shape_registry_resolves(&registry, animation))

    testing.expect_value(t, shape_registry_rewind_animation(
        &registry), Shape_World_Status.Ok)
    testing.expect(t, shape_registry_resolves(&registry, baseline))
    testing.expect(t, !shape_registry_resolves(&registry, animation))
    replacement: Shape_Entity
    testing.expect_value(t, shape_registry_create(
        &registry, &replacement), Shape_World_Status.Ok)
    testing.expect_value(t, replacement.slot, animation.slot)
    testing.expect(t, replacement.generation != animation.generation)
}

// Verify registry exhaustion rejects without changing the live prefix.
@(test)
core_test_shape_registry_rejects_capacity_exhaustion :: proc(t: ^testing.T) {
    registry: Shape_Registry
    entity: Shape_Entity
    for _ in 0..<MAX_SHAPE_ENTITIES {
        testing.expect_value(t, shape_registry_create(
            &registry, &entity), Shape_World_Status.Ok)
    }
    before := registry.entity_count
    rejected := Shape_Entity{slot = 77, generation = 88}
    testing.expect_value(t, shape_registry_create(
        &registry, &rejected), Shape_World_Status.Out_Of_Capacity)
    testing.expect_value(t, registry.entity_count, before)
    testing.expect_value(t, rejected, Shape_Entity{slot = 77, generation = 88})
}

// Verify sparse membership, duplicate rejection, and mutable lookup use dense values.
@(test)
core_test_shape_component_lookup_and_duplicate_rejection :: proc(t: ^testing.T) {
    registry: Shape_Registry
    entity: Shape_Entity
    set: Shape_Component_Set(Shape_Test_Value)
    testing.expect_value(t, shape_registry_create(
        &registry, &entity), Shape_World_Status.Ok)
    testing.expect_value(t, shape_component_insert(
        &set, &registry, entity, Shape_Test_Value{number = 12}),
        Shape_World_Status.Ok)
    testing.expect_value(t, shape_component_insert(
        &set, &registry, entity, Shape_Test_Value{number = 13}),
        Shape_World_Status.Already_Present)

    value, found := shape_component_get_mut(&set, &registry, entity)
    testing.expect(t, found)
    value.number = 19
    immutable, immutable_found := shape_component_get(&set, &registry, entity)
    testing.expect(t, immutable_found)
    testing.expect_value(t, immutable.number, i32(19))
    testing.expect_value(t, set.count, u16(1))
}

// Verify a component dense span cannot diverge from entity construction order.
@(test)
core_test_shape_component_rejects_out_of_order_insertion :: proc(t: ^testing.T) {
    registry: Shape_Registry
    first, second: Shape_Entity
    set: Shape_Component_Set(Shape_Test_Value)
    testing.expect_value(t, shape_registry_create(
        &registry, &first), Shape_World_Status.Ok)
    testing.expect_value(t, shape_registry_create(
        &registry, &second), Shape_World_Status.Ok)
    testing.expect_value(t, shape_component_insert(
        &set, &registry, second, Shape_Test_Value{number = 2}),
        Shape_World_Status.Ok)
    testing.expect_value(t, shape_component_insert(
        &set, &registry, first, Shape_Test_Value{number = 1}),
        Shape_World_Status.Illegal_State)
    testing.expect_value(t, set.count, u16(1))
}

// Verify frozen components reject late baseline membership and rewind their suffix.
@(test)
core_test_shape_component_freeze_and_rewind :: proc(t: ^testing.T) {
    registry: Shape_Registry
    baseline, animation: Shape_Entity
    set: Shape_Component_Set(Shape_Test_Value)
    testing.expect_value(t, shape_registry_create(
        &registry, &baseline), Shape_World_Status.Ok)
    testing.expect_value(t, shape_registry_freeze_baseline(
        &registry), Shape_World_Status.Ok)
    testing.expect_value(t, shape_component_freeze_baseline(
        &set), Shape_World_Status.Ok)
    testing.expect_value(t, shape_component_insert(
        &set, &registry, baseline, Shape_Test_Value{number = 1}),
        Shape_World_Status.Illegal_State)
    testing.expect_value(t, shape_registry_create(
        &registry, &animation), Shape_World_Status.Ok)
    testing.expect_value(t, shape_component_insert(
        &set, &registry, animation, Shape_Test_Value{number = 2}),
        Shape_World_Status.Ok)

    testing.expect_value(t, shape_component_rewind_animation(
        &set), Shape_World_Status.Ok)
    testing.expect_value(t, shape_registry_rewind_animation(
        &registry), Shape_World_Status.Ok)
    testing.expect_value(t, set.count, u16(0))
    testing.expect(t, !shape_component_contains(&set, &registry, animation))
}

// Verify a stale identity cannot resolve a component after suffix slot reuse.
@(test)
core_test_shape_component_rejects_stale_generation :: proc(t: ^testing.T) {
    registry: Shape_Registry
    set: Shape_Component_Set(Shape_Test_Value)
    testing.expect_value(t, shape_registry_freeze_baseline(
        &registry), Shape_World_Status.Ok)
    stale: Shape_Entity
    testing.expect_value(t, shape_registry_create(
        &registry, &stale), Shape_World_Status.Ok)
    testing.expect_value(t, shape_component_insert(
        &set, &registry, stale, Shape_Test_Value{number = 4}),
        Shape_World_Status.Ok)
    testing.expect_value(t, shape_component_freeze_baseline(
        &set), Shape_World_Status.Ok)
    testing.expect_value(t, shape_component_rewind_animation(
        &set), Shape_World_Status.Ok)
    testing.expect_value(t, shape_registry_rewind_animation(
        &registry), Shape_World_Status.Ok)

    current: Shape_Entity
    testing.expect_value(t, shape_registry_create(
        &registry, &current), Shape_World_Status.Ok)
    testing.expect_value(t, shape_component_insert(
        &set, &registry, current, Shape_Test_Value{number = 5}),
        Shape_World_Status.Ok)
    testing.expect(t, !shape_component_contains(&set, &registry, stale))
    _, found := shape_component_get(&set, &registry, stale)
    testing.expect(t, !found)
}

// Verify world-level freeze and repeated rewind restore every inline component frontier.
@(test)
core_test_shape_world_repeated_rewind_restores_frontiers :: proc(t: ^testing.T) {
    world: Shape_World
    baseline: Shape_Entity
    testing.expect_value(t, shape_world_create_entity(
        &world, &baseline), Shape_World_Status.Ok)
    testing.expect_value(t, shape_component_insert(
        &world.transforms, &world.registry, baseline,
        Shape_Transform{position = {1, 2, 3}}), Shape_World_Status.Ok)
    testing.expect_value(t, shape_world_freeze_baseline(
        &world), Shape_World_Status.Ok)

    for expected_generation in u32(1)..=u32(2) {
        animation: Shape_Entity
        testing.expect_value(t, shape_world_create_entity(
            &world, &animation), Shape_World_Status.Ok)
        testing.expect_value(t, animation.generation, expected_generation)
        testing.expect_value(t, shape_component_insert(
            &world.transforms, &world.registry, animation,
            Shape_Transform{position = {4, 5, 6}}), Shape_World_Status.Ok)
        testing.expect_value(t, shape_component_insert(
            &world.render_styles, &world.registry, animation,
            Shape_Render_Style{visible = true}), Shape_World_Status.Ok)
        testing.expect_value(t, shape_component_insert(
            &world.active_features, &world.registry, animation,
            Shape_Active_Feature{index = 2}), Shape_World_Status.Ok)

        testing.expect_value(t, shape_world_rewind_animation(
            &world), Shape_World_Status.Ok)
        testing.expect_value(t, world.registry.entity_count, u32(1))
        testing.expect_value(t, world.transforms.count, u16(1))
        testing.expect_value(t, world.render_styles.count, u16(0))
        testing.expect_value(t, world.active_features.count, u16(0))
        testing.expect(t, shape_component_contains(
            &world.transforms, &world.registry, baseline))
        testing.expect(t, !shape_registry_resolves(&world.registry, animation))
    }
}
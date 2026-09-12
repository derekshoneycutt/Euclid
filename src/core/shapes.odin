package core

import rl "vendor:raylib"

MAX_SHAPE_ENTITIES :: MAX_SHAPESPOINTS
SHAPE_ENTITY_INVALID_SLOT :: u32(0)
SHAPE_ENTITY_INVALID_GENERATION :: u32(0)

// Report bounded shape-world operation outcomes without bridge coupling.
Shape_World_Status :: enum {
    Ok,
    Invalid_Argument,
    Illegal_State,
    Not_Found,
    Already_Present,
    Out_Of_Capacity,
}

// Identify one entity slot across animation-suffix reuse.
Shape_Entity :: struct {
    slot: u32,
    generation: u32,
}

// Own append-only entity identities with one frozen baseline prefix.
Shape_Registry :: struct {
    generations: [MAX_SHAPE_ENTITIES]u32,
    entity_count: u32,
    animation_entity_start: u32,
    baseline_frozen: bool,
}

// Store one optional component densely with constant-time entity membership.
Shape_Component_Set :: struct($Value: typeid) {
    sparse: [MAX_SHAPE_ENTITIES]u16,
    entities: [MAX_SHAPE_ENTITIES]Shape_Entity,
    values: [MAX_SHAPE_ENTITIES]Value,
    count: u16,
    animation_start: u16,
    baseline_frozen: bool,
}

// Hold current and previous world positions for one transform-bearing entity.
Shape_Transform :: struct {
    position: Vector3,
    previous_position: Vector3,
}

// Hold canonical presentation state for one renderable entity.
Shape_Render_Style :: struct {
    color: rl.Color,
    active_color: Maybe(rl.Color),
    brush_size: f32,
    offset: Vector3,
    visible: bool,
}

// Select one active subfeature only for entities whose behavior requires it.
Shape_Active_Feature :: struct {
    index: u16,
}

// Hold the first bounded canonical world slice during the shape migration.
Shape_World :: struct {
    registry: Shape_Registry,
    transforms: Shape_Component_Set(Shape_Transform),
    render_styles: Shape_Component_Set(Shape_Render_Style),
    active_features: Shape_Component_Set(Shape_Active_Feature),
}

// Pack one pointer-free entity identity for bridge and snapshot storage.
shape_entity_pack :: proc(entity: Shape_Entity) -> u64 {
    return u64(entity.generation)<<32 | u64(entity.slot)
}

// Unpack one pointer-free entity identity without asserting its liveness.
shape_entity_unpack :: proc(value: u64) -> Shape_Entity {
    return {
        slot = u32(value & 0xffff_ffff),
        generation = u32(value >> 32),
    }
}

// Return whether one nonzero entity identity resolves in the live registry prefix.
shape_registry_resolves :: proc(
    registry: ^Shape_Registry,
    entity: Shape_Entity) -> bool {
    if registry == nil || entity.slot == SHAPE_ENTITY_INVALID_SLOT ||
        entity.generation == SHAPE_ENTITY_INVALID_GENERATION ||
        entity.slot > registry.entity_count {
        return false
    }
    slot_index := entity.slot - 1
    return registry.generations[slot_index] == entity.generation
}

// Append one entity to the current lifetime suffix.
shape_registry_create :: proc(
    registry: ^Shape_Registry,
    entity: ^Shape_Entity) -> Shape_World_Status {
    if registry == nil || entity == nil {
        return .Invalid_Argument
    }
    if registry.entity_count >= MAX_SHAPE_ENTITIES {
        return .Out_Of_Capacity
    }
    slot_index := registry.entity_count
    generation := registry.generations[slot_index]
    if generation == SHAPE_ENTITY_INVALID_GENERATION {
        generation = 1
        registry.generations[slot_index] = generation
    }
    entity^ = {slot = slot_index + 1, generation = generation}
    registry.entity_count += 1
    return .Ok
}

// Freeze the current registry prefix as process-lifetime baseline entities.
shape_registry_freeze_baseline :: proc(
    registry: ^Shape_Registry) -> Shape_World_Status {
    if registry == nil {
        return .Invalid_Argument
    }
    if registry.baseline_frozen {
        return .Illegal_State
    }
    registry.animation_entity_start = registry.entity_count
    registry.baseline_frozen = true
    return .Ok
}

// Retire the complete animation suffix and invalidate every retired identity.
shape_registry_rewind_animation :: proc(
    registry: ^Shape_Registry) -> Shape_World_Status {
    if registry == nil {
        return .Invalid_Argument
    }
    if !registry.baseline_frozen {
        return .Illegal_State
    }
    for slot_index in registry.animation_entity_start..<registry.entity_count {
        generation := registry.generations[slot_index] + 1
        if generation == SHAPE_ENTITY_INVALID_GENERATION {
            generation = 1
        }
        registry.generations[slot_index] = generation
    }
    registry.entity_count = registry.animation_entity_start
    return .Ok
}

// Return whether one validated entity owns a value in this component set.
shape_component_contains :: proc(
    set: ^Shape_Component_Set($Value),
    registry: ^Shape_Registry,
    entity: Shape_Entity) -> bool {
    if set == nil || !shape_registry_resolves(registry, entity) {
        return false
    }
    slot_index := entity.slot - 1
    sparse_value := set.sparse[slot_index]
    if sparse_value == 0 {
        return false
    }
    dense_index := int(sparse_value - 1)
    return dense_index < int(set.count) && set.entities[dense_index] == entity
}

// Insert one component while preserving entity construction order.
shape_component_insert :: proc(
    set: ^Shape_Component_Set($Value),
    registry: ^Shape_Registry,
    entity: Shape_Entity,
    value: Value) -> Shape_World_Status {
    if set == nil || registry == nil {
        return .Invalid_Argument
    }
    if !shape_registry_resolves(registry, entity) {
        return .Not_Found
    }
    if shape_component_contains(set, registry, entity) {
        return .Already_Present
    }
    if set.count > 0 && set.entities[set.count - 1].slot > entity.slot {
        return .Illegal_State
    }
    if set.baseline_frozen && entity.slot <= registry.animation_entity_start {
        return .Illegal_State
    }
    if set.count >= MAX_SHAPE_ENTITIES {
        return .Out_Of_Capacity
    }
    dense_index := set.count
    set.entities[dense_index] = entity
    set.values[dense_index] = value
    slot_index := entity.slot - 1
    set.sparse[slot_index] = dense_index + 1
    set.count += 1
    return .Ok
}

// Resolve one immutable component after validating entity identity and membership.
shape_component_get :: proc(
    set: ^Shape_Component_Set($Value),
    registry: ^Shape_Registry,
    entity: Shape_Entity) -> (^Value, bool) {
    if !shape_component_contains(set, registry, entity) {
        return nil, false
    }
    slot_index := entity.slot - 1
    dense_index := set.sparse[slot_index] - 1
    return &set.values[dense_index], true
}

// Resolve one mutable component after validating entity identity and membership.
shape_component_get_mut :: proc(
    set: ^Shape_Component_Set($Value),
    registry: ^Shape_Registry,
    entity: Shape_Entity) -> (^Value, bool) {
    return shape_component_get(set, registry, entity)
}

// Freeze the current dense prefix as baseline component membership.
shape_component_freeze_baseline :: proc(
    set: ^Shape_Component_Set($Value)) -> Shape_World_Status {
    if set == nil {
        return .Invalid_Argument
    }
    if set.baseline_frozen {
        return .Illegal_State
    }
    set.animation_start = set.count
    set.baseline_frozen = true
    return .Ok
}

// Retire the complete dense animation suffix and clear its sparse membership.
shape_component_rewind_animation :: proc(
    set: ^Shape_Component_Set($Value)) -> Shape_World_Status {
    if set == nil {
        return .Invalid_Argument
    }
    if !set.baseline_frozen {
        return .Illegal_State
    }
    for dense_index in set.animation_start..<set.count {
        entity := set.entities[dense_index]
        slot_index := entity.slot - 1
        set.sparse[slot_index] = 0
        set.entities[dense_index] = {}
        set.values[dense_index] = {}
    }
    set.count = set.animation_start
    return .Ok
}

// Append one entity through the canonical world's registry.
shape_world_create_entity :: proc(
    world: ^Shape_World,
    entity: ^Shape_Entity) -> Shape_World_Status {
    if world == nil {
        return .Invalid_Argument
    }
    return shape_registry_create(&world.registry, entity)
}

// Freeze every current world frontier as baseline membership.
shape_world_freeze_baseline :: proc(world: ^Shape_World) -> Shape_World_Status {
    if world == nil {
        return .Invalid_Argument
    }
    if world.registry.baseline_frozen || world.transforms.baseline_frozen ||
        world.render_styles.baseline_frozen || world.active_features.baseline_frozen {
        return .Illegal_State
    }
    _ = shape_registry_freeze_baseline(&world.registry)
    _ = shape_component_freeze_baseline(&world.transforms)
    _ = shape_component_freeze_baseline(&world.render_styles)
    _ = shape_component_freeze_baseline(&world.active_features)
    return .Ok
}

// Retire every component suffix before invalidating animation entity identities.
shape_world_rewind_animation :: proc(world: ^Shape_World) -> Shape_World_Status {
    if world == nil {
        return .Invalid_Argument
    }
    if !world.registry.baseline_frozen || !world.transforms.baseline_frozen ||
        !world.render_styles.baseline_frozen || !world.active_features.baseline_frozen {
        return .Illegal_State
    }
    _ = shape_component_rewind_animation(&world.transforms)
    _ = shape_component_rewind_animation(&world.render_styles)
    _ = shape_component_rewind_animation(&world.active_features)
    return shape_registry_rewind_animation(&world.registry)
}
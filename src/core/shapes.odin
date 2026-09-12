package core

import "core:unicode/utf8"
import rl "vendor:raylib"

MAX_SHAPE_ENTITIES :: MAX_SHAPESPOINTS
MAX_SHAPE_VERTEX_REFERENCES :: MAX_SHAPE_ENTITIES
MAX_SHAPE_CONSTRAINTS :: MAX_SHAPESCONSTRAINTS
MAX_SHAPE_LABEL_SOURCE_BYTES :: 256
MAX_SHAPE_LABEL_TOTAL_BYTES :: 32 * 1024
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
    Invalid_Utf8,
    Unsupported_Mime,
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
    offset: f32,
    visible: bool,
}

// Select one active subfeature only for entities whose behavior requires it.
Shape_Active_Feature :: struct {
    index: u16,
}

// Distinguish the immutable topology payload owned by one shape entity.
Shape_Geometry_Kind :: enum u8 {
    Point,
    Line,
    Arc,
    Filled_Arc,
    Polygon,
    Pen,
    Compass,
}

// Name both transform entities required by one line.
Shape_Line_Geometry :: struct {
    first: Shape_Entity,
    second: Shape_Entity,
}

// Name the center and endpoint transforms required by one arc.
Shape_Arc_Geometry :: struct {
    center: Shape_Entity,
    start: Shape_Entity,
    finish: Shape_Entity,
}

// Locate one immutable ordered polygon span in the world reference pool.
Shape_Polygon_Geometry :: struct {
    first_vertex: u16,
    vertex_count: u16,
}

// Name both transform entities required by one pen.
Shape_Pen_Geometry :: struct {
    joint1: Shape_Entity,
    joint2: Shape_Entity,
}

// Name all transform entities required by one compass.
Shape_Compass_Geometry :: struct {
    joint1: Shape_Entity,
    pivot: Shape_Entity,
    joint2: Shape_Entity,
}

// Store one immutable kind-valid geometry payload.
Shape_Geometry :: struct {
    kind: Shape_Geometry_Kind,
    payload: struct #raw_union {
        line: Shape_Line_Geometry,
        arc: Shape_Arc_Geometry,
        polygon: Shape_Polygon_Geometry,
        pen: Shape_Pen_Geometry,
        compass: Shape_Compass_Geometry,
    },
}

// Identify the canonical source language for one geometric annotation.
Shape_Text_Mime :: enum u8 {
    Text_Plain,
    Text_Latex,
}

// Locate one immutable label source span without retaining an internal pointer.
Shape_Label :: struct {
    mime: Shape_Text_Mime,
    byte_offset: u16,
    byte_count: u16,
    revision: u32,
}

// Own ordered variable-arity polygon topology in one fixed inline pool.
Shape_Vertex_Reference_Store :: struct {
    entities: [MAX_SHAPE_VERTEX_REFERENCES]Shape_Entity,
    count: u16,
    animation_start: u16,
    baseline_frozen: bool,
}

// Own canonical label source bytes in one fixed inline pool.
Shape_Label_Store :: struct {
    bytes: [MAX_SHAPE_LABEL_TOTAL_BYTES]u8,
    byte_count: u16,
    animation_byte_start: u16,
    baseline_frozen: bool,
}

// Select which distance or angle endpoints a correction may move.
Shape_Constraint_Movement_Policy :: enum u8 {
    Move_First,
    Move_Both,
    Move_Second,
}

// Distinguish direct-target constraint payloads without geometry coupling.
Shape_Constraint_Kind :: enum u8 {
    Distance,
    Floor,
    Snap_To_Floor,
    Snap_Point,
    Max_Angle,
    Min_Angle,
    Center_Pivot,
}

// Keep one transform at or above a floor height with optional bounce.
Shape_Floor_Constraint :: struct {
    point: Shape_Entity,
    height: f32,
    bounce: f32,
}

// Snap one transform to a floor height outside the allowed tolerance.
Shape_Snap_To_Floor_Constraint :: struct {
    point: Shape_Entity,
    height: f32,
    allowance: f32,
}

// Snap one transform to an explicit world position.
Shape_Snap_Point_Constraint :: struct {
    point: Shape_Entity,
    position: Vector3,
}

// Preserve one direct endpoint distance under an explicit movement policy.
Shape_Distance_Constraint :: struct {
    first: Shape_Entity,
    second: Shape_Entity,
    length: f32,
    movement: Shape_Constraint_Movement_Policy,
}

// Bound one direct three-transform angle under an explicit movement policy.
Shape_Angle_Constraint :: struct {
    first: Shape_Entity,
    pivot: Shape_Entity,
    second: Shape_Entity,
    limit: f32,
    movement: Shape_Constraint_Movement_Policy,
}

// Keep one pivot at the planar midpoint of two direct endpoints.
Shape_Center_Pivot_Constraint :: struct {
    first: Shape_Entity,
    pivot: Shape_Entity,
    second: Shape_Entity,
}

// Store one kind-valid direct-target constraint payload.
Shape_Constraint :: struct {
    kind: Shape_Constraint_Kind,
    payload: struct #raw_union {
        distance: Shape_Distance_Constraint,
        floor: Shape_Floor_Constraint,
        snap_to_floor: Shape_Snap_To_Floor_Constraint,
        snap_point: Shape_Snap_Point_Constraint,
        angle: Shape_Angle_Constraint,
        center_pivot: Shape_Center_Pivot_Constraint,
    },
    enabled: bool,
}

// Own constraints in stable solver order with one rewindable animation suffix.
Shape_Constraint_Store :: struct {
    values: [MAX_SHAPE_CONSTRAINTS]Shape_Constraint,
    count: u16,
    animation_start: u16,
    baseline_frozen: bool,
}

// Describe all fixed capacities required by one transactional construction.
Shape_Construction_Needs :: struct {
    entities: int,
    transforms: int,
    render_styles: int,
    active_features: int,
    geometries: int,
    labels: int,
    label_bytes: int,
    vertex_references: int,
    constraints: int,
}

// Identify one standalone point entity.
Shape_Point_Handle :: struct {
    entity: Shape_Entity,
}

// Identify one standalone label entity.
Shape_Label_Handle :: struct {
    entity: Shape_Entity,
}

// Identify a line host and both endpoint transforms.
Shape_Line_Handle :: struct {
    shape: Shape_Entity,
    first: Shape_Entity,
    second: Shape_Entity,
}

// Identify an arc host and its center and endpoint transforms.
Shape_Arc_Handle :: struct {
    shape: Shape_Entity,
    center: Shape_Entity,
    start: Shape_Entity,
    finish: Shape_Entity,
}

// Identify one variable-arity polygon host.
Shape_Polygon_Handle :: struct {
    shape: Shape_Entity,
}

// Identify one triangle host and its three ordered vertices.
Shape_Triangle_Handle :: struct {
    shape: Shape_Entity,
    first: Shape_Entity,
    second: Shape_Entity,
    third: Shape_Entity,
}

// Identify one square host and its four ordered vertices.
Shape_Square_Handle :: struct {
    shape: Shape_Entity,
    vertices: [4]Shape_Entity,
}

// Identify one pentagon host and its five ordered vertices.
Shape_Pentagon_Handle :: struct {
    shape: Shape_Entity,
    vertices: [5]Shape_Entity,
}

// Identify one pen host and its direct geometry references.
Shape_Pen_Handle :: struct {
    shape: Shape_Entity,
    joint1: Shape_Entity,
    joint2: Shape_Entity,
    length_constraint: u16,
    joint1_floor_constraint: u16,
    joint2_floor_constraint: u16,
    joint1_lock_constraint: u16,
    joint2_lock_constraint: u16,
}

// Identify one compass host and its direct geometry references.
Shape_Compass_Handle :: struct {
    shape: Shape_Entity,
    joint1: Shape_Entity,
    pivot: Shape_Entity,
    joint2: Shape_Entity,
    center_pivot_constraint: u16,
    limb1_length_constraint: u16,
    limb2_length_constraint: u16,
    joint1_floor_constraint: u16,
    pivot_floor_constraint: u16,
    joint2_floor_constraint: u16,
    joint1_lock_constraint: u16,
    joint2_lock_constraint: u16,
}

// Hold the first bounded canonical world slice during the shape migration.
Shape_World :: struct {
    draw_cache: Shapes_Draw_Cache,
    registry: Shape_Registry,
    transforms: Shape_Component_Set(Shape_Transform),
    render_styles: Shape_Component_Set(Shape_Render_Style),
    active_features: Shape_Component_Set(Shape_Active_Feature),
    geometries: Shape_Component_Set(Shape_Geometry),
    labels: Shape_Component_Set(Shape_Label),
    vertex_references: Shape_Vertex_Reference_Store,
    label_store: Shape_Label_Store,
    constraints: Shape_Constraint_Store,
}

// Invalidate every published packet frontier before canonical world mutation.
shape_world_invalidate_draw_cache :: proc(world: ^Shape_World) {
    if world == nil {
        return
    }
    world.draw_cache.item_count = 0
    world.draw_cache.label_byte_count = 0
    world.draw_cache.polygon_vertex_count = 0
    world.draw_cache.polygon_triangle_count = 0
    world.draw_cache.draw_pen = false
    world.draw_cache.draw_compass = false
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

// Return whether one entity is a live transform target in the canonical world.
shape_constraint_target_resolves :: proc(
    world: ^Shape_World,
    entity: Shape_Entity) -> bool {
    return world != nil && shape_component_contains(
        &world.transforms, &world.registry, entity)
}

// Validate every direct target required by one kind-specific constraint payload.
shape_constraint_targets_resolve :: proc(
    world: ^Shape_World,
    constraint: Shape_Constraint) -> bool {
    if world == nil {
        return false
    }
    switch constraint.kind {
    case .Floor:
        return shape_constraint_target_resolves(world, constraint.payload.floor.point)
    case .Snap_To_Floor:
        return shape_constraint_target_resolves(
            world, constraint.payload.snap_to_floor.point)
    case .Snap_Point:
        return shape_constraint_target_resolves(
            world, constraint.payload.snap_point.point)
    case .Distance:
        payload := constraint.payload.distance
        return shape_constraint_target_resolves(world, payload.first) &&
            shape_constraint_target_resolves(world, payload.second)
    case .Max_Angle, .Min_Angle:
        payload := constraint.payload.angle
        return shape_constraint_target_resolves(world, payload.first) &&
            shape_constraint_target_resolves(world, payload.pivot) &&
            shape_constraint_target_resolves(world, payload.second)
    case .Center_Pivot:
        payload := constraint.payload.center_pivot
        return shape_constraint_target_resolves(world, payload.first) &&
            shape_constraint_target_resolves(world, payload.pivot) &&
            shape_constraint_target_resolves(world, payload.second)
    }
    return false
}

// Append one fully validated constraint without partially advancing its store.
shape_constraint_append :: proc(
    world: ^Shape_World,
    constraint: Shape_Constraint,
    index: ^u16 = nil) -> Shape_World_Status {
    if world == nil {
        return .Invalid_Argument
    }
    if !shape_constraint_targets_resolve(world, constraint) {
        return .Not_Found
    }
    if world.constraints.count >= MAX_SHAPE_CONSTRAINTS {
        return .Out_Of_Capacity
    }
    constraint_index := world.constraints.count
    world.constraints.values[constraint_index] = constraint
    world.constraints.count += 1
    if index != nil {
        index^ = constraint_index
    }
    return .Ok
}

// Return whether one construction fits every fixed world store without mutation.
shape_world_has_capacity :: proc(
    world: ^Shape_World,
    needs: Shape_Construction_Needs) -> bool {
    if world == nil || needs.entities < 0 || needs.transforms < 0 ||
        needs.render_styles < 0 || needs.active_features < 0 ||
        needs.geometries < 0 || needs.labels < 0 || needs.label_bytes < 0 ||
        needs.vertex_references < 0 || needs.constraints < 0 {
        return false
    }
    component_capacity := MAX_SHAPE_ENTITIES
    return int(world.registry.entity_count) + needs.entities <= MAX_SHAPE_ENTITIES &&
        int(world.transforms.count) + needs.transforms <= component_capacity &&
        int(world.render_styles.count) + needs.render_styles <= component_capacity &&
        int(world.active_features.count) + needs.active_features <= component_capacity &&
        int(world.geometries.count) + needs.geometries <= component_capacity &&
        int(world.labels.count) + needs.labels <= component_capacity &&
        int(world.label_store.byte_count) + needs.label_bytes <=
            MAX_SHAPE_LABEL_TOTAL_BYTES &&
        int(world.vertex_references.count) + needs.vertex_references <=
            MAX_SHAPE_VERTEX_REFERENCES &&
        int(world.constraints.count) + needs.constraints <= MAX_SHAPE_CONSTRAINTS
}

// Validate one immutable, single-line plain-text label source.
shape_label_validate_source :: proc(
    mime: Shape_Text_Mime,
    source: string) -> Shape_World_Status {
    if mime != .Text_Plain {
        return .Unsupported_Mime
    }
    if len(source) == 0 || len(source) > MAX_SHAPE_LABEL_SOURCE_BYTES {
        return .Invalid_Argument
    }
    if !utf8.valid_string(source) {
        return .Invalid_Utf8
    }
    offset := 0
    for offset < len(source) {
        codepoint, width := utf8.decode_rune(source[offset:])
        if codepoint < 0x20 || codepoint >= 0x7f && codepoint <= 0x9f {
            return .Invalid_Argument
        }
        offset += width
    }
    return .Ok
}

// Append validated label bytes and return their pointer-free descriptor.
shape_label_store_append :: proc(
    store: ^Shape_Label_Store,
    mime: Shape_Text_Mime,
    source: string,
    label: ^Shape_Label) -> Shape_World_Status {
    if store == nil || label == nil {
        return .Invalid_Argument
    }
    status := shape_label_validate_source(mime, source)
    if status != .Ok {
        return status
    }
    if int(store.byte_count) + len(source) > MAX_SHAPE_LABEL_TOTAL_BYTES {
        return .Out_Of_Capacity
    }
    offset := store.byte_count
    end := int(offset) + len(source)
    copy(store.bytes[offset:end], transmute([]u8)source)
    label^ = {mime = mime, byte_offset = offset,
        byte_count = u16(len(source)), revision = 1}
    store.byte_count = u16(end)
    return .Ok
}

// Resolve one validated immutable label descriptor into borrowed world bytes.
shape_label_source :: proc(
    store: ^Shape_Label_Store,
    label: Shape_Label) -> (string, bool) {
    if store == nil || label.byte_count == 0 {
        return "", false
    }
    start := int(label.byte_offset)
    end := start + int(label.byte_count)
    if start < 0 || end > int(store.byte_count) || end < start {
        return "", false
    }
    return string(store.bytes[start:end]), true
}

// Append one immutable ordered polygon reference span.
shape_vertex_references_append :: proc(
    world: ^Shape_World,
    entities: []Shape_Entity,
    geometry: ^Shape_Polygon_Geometry) -> Shape_World_Status {
    if world == nil || geometry == nil || len(entities) < 3 {
        return .Invalid_Argument
    }
    if int(world.vertex_references.count) + len(entities) >
        MAX_SHAPE_VERTEX_REFERENCES {
        return .Out_Of_Capacity
    }
    for entity in entities {
        if !shape_component_contains(&world.transforms, &world.registry, entity) {
            return .Not_Found
        }
    }
    store := &world.vertex_references
    first := store.count
    end := int(first) + len(entities)
    copy(store.entities[first:end], entities)
    store.count = u16(end)
    geometry^ = {first_vertex = first, vertex_count = u16(len(entities))}
    return .Ok
}

// Resolve one polygon span after validating bounds and every entity identity.
shape_polygon_vertices :: proc(
    world: ^Shape_World,
    geometry: Shape_Polygon_Geometry) -> ([]Shape_Entity, bool) {
    if world == nil || geometry.vertex_count < 3 {
        return nil, false
    }
    start := int(geometry.first_vertex)
    end := start + int(geometry.vertex_count)
    if start < 0 || end > int(world.vertex_references.count) || end < start {
        return nil, false
    }
    vertices := world.vertex_references.entities[start:end]
    for entity in vertices {
        if !shape_component_contains(&world.transforms, &world.registry, entity) {
            return nil, false
        }
    }
    return vertices, true
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
        world.render_styles.baseline_frozen || world.active_features.baseline_frozen ||
        world.geometries.baseline_frozen || world.labels.baseline_frozen ||
        world.vertex_references.baseline_frozen || world.label_store.baseline_frozen ||
        world.constraints.baseline_frozen {
        return .Illegal_State
    }
    _ = shape_registry_freeze_baseline(&world.registry)
    _ = shape_component_freeze_baseline(&world.transforms)
    _ = shape_component_freeze_baseline(&world.render_styles)
    _ = shape_component_freeze_baseline(&world.active_features)
    _ = shape_component_freeze_baseline(&world.geometries)
    _ = shape_component_freeze_baseline(&world.labels)
    world.vertex_references.animation_start = world.vertex_references.count
    world.vertex_references.baseline_frozen = true
    world.label_store.animation_byte_start = world.label_store.byte_count
    world.label_store.baseline_frozen = true
    world.constraints.animation_start = world.constraints.count
    world.constraints.baseline_frozen = true
    return .Ok
}

// Retire every component suffix before invalidating animation entity identities.
shape_world_rewind_animation :: proc(world: ^Shape_World) -> Shape_World_Status {
    if world == nil {
        return .Invalid_Argument
    }
    if !world.registry.baseline_frozen || !world.transforms.baseline_frozen ||
        !world.render_styles.baseline_frozen || !world.active_features.baseline_frozen ||
        !world.geometries.baseline_frozen || !world.labels.baseline_frozen ||
        !world.vertex_references.baseline_frozen || !world.label_store.baseline_frozen ||
        !world.constraints.baseline_frozen {
        return .Illegal_State
    }
    shape_world_invalidate_draw_cache(world)
    _ = shape_component_rewind_animation(&world.transforms)
    _ = shape_component_rewind_animation(&world.render_styles)
    _ = shape_component_rewind_animation(&world.active_features)
    _ = shape_component_rewind_animation(&world.geometries)
    _ = shape_component_rewind_animation(&world.labels)
    world.vertex_references.count = world.vertex_references.animation_start
    world.label_store.byte_count = world.label_store.animation_byte_start
    world.constraints.count = world.constraints.animation_start
    return shape_registry_rewind_animation(&world.registry)
}
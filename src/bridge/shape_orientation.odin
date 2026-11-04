package bridge

import "../core"
import geometry "../core/geometry"
import shapemodel "../shapes/model"
import "core:math"
import "core:math/linalg"

// Return a pointer-free snapshot orientation with explicit status.
Bridge_Shape_Orientation_Result :: struct {
    status: i32,
    orientation: [4]f32,
}

// Query canonical plane orientation only through the active immutable query source.
@(export)
shape_get_orientation :: proc "c" (
    state: ^core.Euclid_General_State,
    packed: u64) -> Bridge_Shape_Orientation_Result {
    context = state.saved_context
    source, available := bridge_shape_query_source(state)
    if !available {
        return {BRIDGE_STATUS_ILLEGAL_STATE, {}}
    }
    entity := shapemodel.shape_entity_unpack(packed)
    value, found := shapemodel.shape_component_get(
        source.orientations, source.registry, entity)
    if !found {
        return {BRIDGE_STATUS_NOT_FOUND, {}}
    }
    q := value.orientation
    return {BRIDGE_STATUS_OK, {q.x, q.y, q.z, q.w}}
}

// Capture a complete plane rotation; positional changes share its scene transaction.
@(export)
shape_set_orientation :: proc "c" (
    state: ^core.Euclid_General_State, packed: u64,
    components: [4]f32) -> i32 {
    context = state.saved_context
    orientation := quaternion(
        x = components.x, y = components.y, z = components.z, w = components.w)
    if !shape_orientation_is_valid(orientation) {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }
    command, captured := capture_shape_command(state, .Set_Shape_Orientation, packed)
    if command != nil {
        command.orientation = linalg.normalize(orientation)
    }
    if captured {
        return BRIDGE_STATUS_OK
    }
    entity, found := bridge_shape_resolve(state, packed)
    if !found {
        return BRIDGE_STATUS_NOT_FOUND
    }
    value, present := shapemodel.shape_component_get_mut(
        &state.shape_world.orientations, &state.shape_world.registry, entity)
    if !present {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }
    commands := [?]Scene_Command{{
        kind = .Set_Shape_Orientation,
        entity = packed,
        orientation = orientation,
    }}
    if !shape_plane_edits_valid(&state.shape_world, commands[:]) {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }
    value.orientation = linalg.normalize(orientation)
    return BRIDGE_STATUS_OK
}

// Validate one orientation write without observing uncommitted positional writes.
validate_command_shape_orientation :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) -> bool {
    entity, found := bridge_shape_resolve(state, command.entity)
    return found && shape_orientation_is_valid(command.orientation) &&
        shapemodel.shape_component_contains(
            &state.shape_world.orientations, &state.shape_world.registry, entity)
}

// Apply a prevalidated orientation write without recapturing a command.
apply_set_shape_orientation :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    entity := shapemodel.shape_entity_unpack(command.entity)
    value, found := shapemodel.shape_component_get_mut(
        &state.shape_world.orientations, &state.shape_world.registry, entity)
    assert(found)
    value.orientation = linalg.normalize(command.orientation)
}

// Resolve the last prospective position without partially applying a coordinated edit.
prospective_shape_position :: proc(
    world: ^shapemodel.Shape_World, commands: []Scene_Command,
    entity: shapemodel.Shape_Entity) -> (geometry.Vector3, bool) {
    value, found := shapemodel.shape_component_get(
        &world.transforms, &world.registry, entity)
    if !found {
        return {}, false
    }
    result := value.position
    packed := shapemodel.shape_entity_pack(entity)
    for command in commands {
        if command.kind == .Set_Shape_Position && command.entity == packed {
            result = command.position
        }
    }
    return result, true
}

// Resolve the last prospective plane normal from the same transactional batch.
prospective_shape_orientation :: proc(
    commands: []Scene_Command, entity: shapemodel.Shape_Entity,
    initial: quaternion128) -> quaternion128 {
    result := initial
    packed := shapemodel.shape_entity_pack(entity)
    for command in commands {
        if command.kind == .Set_Shape_Orientation && command.entity == packed {
            result = command.orientation
        }
    }
    return result
}

// Reject incompatible final rail/center geometry, not intermediate individual writes.
scene_command_batch_planes_valid :: proc(
    state: ^core.Euclid_General_State, batch: ^Scene_Command_Batch) -> bool {
    return shape_plane_edits_valid(
        &state.shape_world, batch.commands[:batch.command_count])
}

// Check final analytic dependencies for direct edits and complete scene transactions.
shape_plane_edits_valid :: proc(
    world: ^shapemodel.Shape_World, commands: []Scene_Command) -> bool {
    for index in 0..<world.orientations.count {
        entity := world.orientations.entities[index]
        definition, found := shapemodel.shape_component_get(
            &world.geometries, &world.registry, entity)
        if !found {
            return false
        }
        q := prospective_shape_orientation(
            commands, entity, world.orientations.values[index].orientation)
        if !prospective_shape_plane_valid(world, commands, entity, definition^, q) {
            return false
        }
    }
    return true
}

// Validate a final endpoint-defined analytic plane and its intrinsic metric bounds.
prospective_shape_plane_valid :: proc(
    world: ^shapemodel.Shape_World, commands: []Scene_Command,
    entity: shapemodel.Shape_Entity, definition: shapemodel.Shape_Geometry,
    q: quaternion128) -> bool {
    first, second: shapemodel.Shape_Entity
    #partial switch definition.kind {
    case .Cycloid:
        first, second =
            definition.payload.cycloid.first, definition.payload.cycloid.second
    case .Circle_Region:
        first = definition.payload.circle_region.first_center
        second = definition.payload.circle_region.second_center
    case:
        return true
    }
    a, first_ok := prospective_shape_position(world, commands, first)
    b, second_ok := prospective_shape_position(world, commands, second)
    delta := b - a
    length := linalg.length(delta)
    normal := linalg.mul(q, geometry.Vector3{0, 0, 1})
    if !first_ok || !second_ok || length <= 0 ||
        math.abs(linalg.dot(normal, delta)) > 0.00001 * max(1, length) {
        return false
    }

    return prospective_shape_metric_valid(world, commands, entity, definition, length)
}

// Reject nonfinite or nonunit ABI values before publishing canonical plane state.
shape_orientation_is_valid :: proc(q: quaternion128) -> bool {
    components: [4]f32 = {q.x, q.y, q.z, q.w}
    for value in components {
        if math.is_nan(value) || math.is_inf(value) {
            return false
        }
    }
    return math.abs(linalg.dot(q, q) - 1) <= 0.0001
}

// Preserve circle intersections and no-slip travel using prospective scalar geometry.
prospective_shape_metric_valid :: proc(
    world: ^shapemodel.Shape_World, commands: []Scene_Command,
    entity: shapemodel.Shape_Entity, definition: shapemodel.Shape_Geometry,
    length: f32) -> bool {
    if definition.kind == .Circle_Region {
        region := definition.payload.circle_region.value
        return length > math.abs(region.first_radius - region.second_radius) &&
            length < region.first_radius + region.second_radius
    }
    value, found := shapemodel.shape_component_get(
        &world.cycloids, &world.registry, entity)
    if !found {
        return false
    }
    candidate := value^
    for command in commands {
        if command.kind == .Set_Shape_Cycloid &&
            command.entity == shapemodel.shape_entity_pack(entity) {
            candidate = command.cycloid
        }
    }
    return candidate.rolling_radius *
        math.abs(candidate.parameter_finish - candidate.parameter_start) <=
            length + 0.00001
}

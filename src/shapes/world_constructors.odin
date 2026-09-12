package shapes

import "core:math"

import "../core"

import rl "vendor:raylib"

// Supply presentation values shared by canonical shape constructors.
Shape_Style :: struct {
    color: rl.Color,
    brush_size: f32,
}

// Supply canonical arc geometry and presentation values.
Arc_Input :: struct {
    center: Vector3,
    radius, start_theta, end_theta: f32,
    style: Shape_Style,
}

// Supply canonical source and presentation values for one world label.
World_Label_Input :: struct {
    source: string,
    mime: core.Shape_Text_Mime,
    position: Vector3,
    style: Shape_Style,
}

// Supply fixed pen geometry, presentation, and length policy.
World_Pen_Input :: struct {
    joint1: Vector3,
    joint2: Vector3,
    length: f32,
    style: Shape_Style,
}

// Supply fixed compass geometry, presentation, and limb policy.
World_Compass_Input :: struct {
    joint1: Vector3,
    pivot: Vector3,
    joint2: Vector3,
    limb_length: f32,
    style: Shape_Style,
}

// Append one entity after its complete construction has passed capacity preflight.
world_shape_append_entity :: proc(world: ^core.Shape_World) -> core.Shape_Entity {
    entity: core.Shape_Entity
    status := core.shape_world_create_entity(world, &entity)
    assert(status == .Ok)
    return entity
}

// Append one transform-bearing entity after capacity preflight.
world_shape_append_transform :: proc(
    world: ^core.Shape_World,
    position: Vector3) -> core.Shape_Entity {
    entity := world_shape_append_entity(world)
    status := core.shape_component_insert(
        &world.transforms, &world.registry, entity,
        core.Shape_Transform{position = position, previous_position = position})
    assert(status == .Ok)
    return entity
}

// Publish presentation and immutable geometry for one preflighted host entity.
world_shape_publish_host :: proc(
    world: ^core.Shape_World,
    entity: core.Shape_Entity,
    style: Shape_Style,
    geometry: core.Shape_Geometry) {
    style_status := core.shape_component_insert(
        &world.render_styles, &world.registry, entity,
        core.Shape_Render_Style{color = style.color,
            brush_size = style.brush_size, visible = false})
    geometry_status := core.shape_component_insert(
        &world.geometries, &world.registry, entity, geometry)
    assert(style_status == .Ok && geometry_status == .Ok)
}

// Create one standalone drawable point with no topology.
world_create_point :: proc(
    world: ^core.Shape_World,
    position: Vector3,
    style: Shape_Style) -> (core.Shape_Point_Handle, core.Shape_World_Status) {
    if world == nil {
        return {}, .Invalid_Argument
    }
    needs := core.Shape_Construction_Needs{
        entities = 1, transforms = 1, render_styles = 1, geometries = 1}
    if !core.shape_world_has_capacity(world, needs) {
        return {}, .Out_Of_Capacity
    }
    entity := world_shape_append_transform(world, position)
    world_shape_publish_host(world, entity, style, {.Point, {}})
    return {entity = entity}, .Ok
}

// Create one immutable single-line label after validating and preflighting its source.
world_create_label :: proc(
    world: ^core.Shape_World,
    input: World_Label_Input) -> (core.Shape_Label_Handle, core.Shape_World_Status) {
    if world == nil {
        return {}, .Invalid_Argument
    }
    status := core.shape_label_validate_source(input.mime, input.source)
    if status != .Ok {
        return {}, status
    }
    needs := core.Shape_Construction_Needs{entities = 1, transforms = 1,
        render_styles = 1, labels = 1, label_bytes = len(input.source)}
    if !core.shape_world_has_capacity(world, needs) {
        return {}, .Out_Of_Capacity
    }
    entity := world_shape_append_transform(world, input.position)
    label: core.Shape_Label
    status = core.shape_label_store_append(
        &world.label_store, input.mime, input.source, &label)
    assert(status == .Ok)
    status = core.shape_component_insert(&world.labels, &world.registry, entity, label)
    assert(status == .Ok)
    world_shape_publish_style(world, entity, input.style)
    return {entity = entity}, .Ok
}

// Publish presentation for one preflighted entity without geometry.
world_shape_publish_style :: proc(
    world: ^core.Shape_World,
    entity: core.Shape_Entity,
    style: Shape_Style) {
    status := core.shape_component_insert(
        &world.render_styles, &world.registry, entity,
        core.Shape_Render_Style{color = style.color,
            brush_size = style.brush_size, visible = false})
    assert(status == .Ok)
}

// Create one line host with direct endpoint references.
world_create_line :: proc(
    world: ^core.Shape_World,
    first_position, second_position: Vector3,
    style: Shape_Style) -> (core.Shape_Line_Handle, core.Shape_World_Status) {
    if world == nil {
        return {}, .Invalid_Argument
    }
    needs := core.Shape_Construction_Needs{
        entities = 3, transforms = 2, render_styles = 1, geometries = 1}
    if !core.shape_world_has_capacity(world, needs) {
        return {}, .Out_Of_Capacity
    }
    shape := world_shape_append_entity(world)
    first := world_shape_append_transform(world, first_position)
    second := world_shape_append_transform(world, second_position)
    geometry := core.Shape_Geometry{kind = .Line}
    geometry.payload.line = {first = first, second = second}
    world_shape_publish_host(world, shape, style, geometry)
    return {shape = shape, first = first, second = second}, .Ok
}

// Calculate one arc endpoint in the center's plane.
world_arc_endpoint :: proc(center: Vector3, radius, theta: f32) -> Vector3 {
    return {center.x + radius*f32(math.cos(theta)),
        center.y + radius*f32(math.sin(theta)), center.z}
}

// Create one arc variant with direct center and endpoint references.
world_create_arc_kind :: proc(
    world: ^core.Shape_World,
    input: Arc_Input,
    kind: core.Shape_Geometry_Kind) -> (core.Shape_Arc_Handle, core.Shape_World_Status) {
    needs := core.Shape_Construction_Needs{
        entities = 3, transforms = 3, render_styles = 1, geometries = 1}
    if world == nil || kind != .Arc && kind != .Filled_Arc {
        return {}, .Invalid_Argument
    }
    if !core.shape_world_has_capacity(world, needs) {
        return {}, .Out_Of_Capacity
    }
    shape := world_shape_append_transform(world, input.center)
    start := world_shape_append_transform(world, world_arc_endpoint(
        input.center, input.radius, input.start_theta))
    finish := world_shape_append_transform(world, world_arc_endpoint(
        input.center, input.radius, input.end_theta))
    geometry := core.Shape_Geometry{kind = kind}
    geometry.payload.arc = {center = shape, start = start, finish = finish}
    world_shape_publish_host(world, shape, input.style, geometry)
    return {shape = shape, center = shape, start = start, finish = finish}, .Ok
}

// Create one outlined arc with direct transform references.
world_create_arc :: proc(
    world: ^core.Shape_World,
    input: Arc_Input) -> (core.Shape_Arc_Handle, core.Shape_World_Status) {
    return world_create_arc_kind(world, input, .Arc)
}

// Create one filled arc with direct transform references.
world_create_filled_arc :: proc(
    world: ^core.Shape_World,
    input: Arc_Input) -> (core.Shape_Arc_Handle, core.Shape_World_Status) {
    return world_create_arc_kind(world, input, .Filled_Arc)
}

// Append ordered transform entities for one preflighted polygon.
world_shape_append_vertices :: proc(
    world: ^core.Shape_World,
    positions: []Vector3,
    entities: []core.Shape_Entity) {
    assert(len(positions) == len(entities))
    for position, index in positions {
        entities[index] = world_shape_append_transform(world, position)
    }
}

// Create one polygon and return its ordered vertex entities in caller storage.
world_create_polygon_into :: proc(
    world: ^core.Shape_World,
    positions: []Vector3,
    style: Shape_Style,
    vertices: []core.Shape_Entity) -> (
    core.Shape_Polygon_Handle, core.Shape_World_Status) {
    if world == nil || len(positions) < 3 || len(vertices) != len(positions) {
        return {}, .Invalid_Argument
    }
    needs := core.Shape_Construction_Needs{entities = len(positions) + 1,
        transforms = len(positions), render_styles = 1, geometries = 1,
        vertex_references = len(positions)}
    if !core.shape_world_has_capacity(world, needs) {
        return {}, .Out_Of_Capacity
    }
    shape := world_shape_append_entity(world)
    world_shape_append_vertices(world, positions, vertices)
    polygon: core.Shape_Polygon_Geometry
    status := core.shape_vertex_references_append(
        world, vertices, &polygon)
    assert(status == .Ok)
    geometry := core.Shape_Geometry{kind = .Polygon}
    geometry.payload.polygon = polygon
    world_shape_publish_host(world, shape, style, geometry)
    return {shape = shape}, .Ok
}

// Create one variable-arity polygon with immutable ordered topology.
world_create_polygon :: proc(
    world: ^core.Shape_World,
    positions: []Vector3,
    style: Shape_Style) -> (core.Shape_Polygon_Handle, core.Shape_World_Status) {
    vertices: [core.MAX_SHAPE_VERTEX_REFERENCES]core.Shape_Entity
    if len(positions) > len(vertices) {
        return {}, .Out_Of_Capacity
    }
    return world_create_polygon_into(world, positions, style, vertices[:len(positions)])
}

// Create one triangle as a typed three-vertex polygon convenience.
world_create_triangle :: proc(
    world: ^core.Shape_World,
    positions: [3]Vector3,
    style: Shape_Style) -> (core.Shape_Triangle_Handle, core.Shape_World_Status) {
    position_values := positions
    vertices: [3]core.Shape_Entity
    polygon, status := world_create_polygon_into(
        world, position_values[:], style, vertices[:])
    if status != .Ok {
        return {}, status
    }
    return {shape = polygon.shape, first = vertices[0], second = vertices[1],
        third = vertices[2]}, .Ok
}

// Create one square as a typed four-vertex polygon convenience.
world_create_square :: proc(
    world: ^core.Shape_World,
    positions: [4]Vector3,
    style: Shape_Style) -> (core.Shape_Square_Handle, core.Shape_World_Status) {
    position_values := positions
    vertices: [4]core.Shape_Entity
    polygon, status := world_create_polygon_into(
        world, position_values[:], style, vertices[:])
    if status != .Ok {
        return {}, status
    }
    return {shape = polygon.shape, vertices = vertices}, .Ok
}

// Create one pentagon as a typed five-vertex polygon convenience.
world_create_pentagon :: proc(
    world: ^core.Shape_World,
    positions: [5]Vector3,
    style: Shape_Style) -> (core.Shape_Pentagon_Handle, core.Shape_World_Status) {
    position_values := positions
    vertices: [5]core.Shape_Entity
    polygon, status := world_create_polygon_into(
        world, position_values[:], style, vertices[:])
    if status != .Ok {
        return {}, status
    }
    return {shape = polygon.shape, vertices = vertices}, .Ok
}

// Append the five direct-target constraints owned by one preflighted pen.
world_append_pen_constraints :: proc(
    world: ^core.Shape_World,
    joint1, joint2: core.Shape_Entity,
    length: f32) -> [5]u16 {
    indices: [5]u16
    indices[0], _ = world_create_distance_constraint(world, {
        first = joint1, second = joint2, length = length,
        movement = .Move_Both, enabled = true})
    indices[1], _ = world_create_floor_constraint(world, {
        point = joint1, enabled = true})
    indices[2], _ = world_create_floor_constraint(world, {
        point = joint2, enabled = true})
    indices[3], _ = world_create_snap_point_constraint(world, {
        point = joint1, enabled = false})
    indices[4], _ = world_create_snap_point_constraint(world, {
        point = joint2, enabled = false})
    return indices
}

// Create one pen whose geometry and constraints name both joints directly.
world_create_pen :: proc(
    world: ^core.Shape_World,
    input: World_Pen_Input) -> (core.Shape_Pen_Handle, core.Shape_World_Status) {
    if world == nil {
        return {}, .Invalid_Argument
    }
    needs := core.Shape_Construction_Needs{entities = 3, transforms = 2,
        render_styles = 1, active_features = 1, geometries = 1, constraints = 5}
    if !core.shape_world_has_capacity(world, needs) {
        return {}, .Out_Of_Capacity
    }
    shape := world_shape_append_entity(world)
    joint1 := world_shape_append_transform(world, input.joint1)
    joint2 := world_shape_append_transform(world, input.joint2)
    geometry := core.Shape_Geometry{kind = .Pen}
    geometry.payload.pen = {joint1 = joint1, joint2 = joint2}
    world_shape_publish_host(world, shape, input.style, geometry)
    feature_status := core.shape_component_insert(&world.active_features,
        &world.registry, shape, core.Shape_Active_Feature{})
    assert(feature_status == .Ok)
    indices := world_append_pen_constraints(world, joint1, joint2, input.length)
    return {shape, joint1, joint2,
        indices[0], indices[1], indices[2], indices[3], indices[4]}, .Ok
}

// Append the eight direct-target constraints owned by one preflighted compass.
world_append_compass_constraints :: proc(
    world: ^core.Shape_World,
    joint1, pivot, joint2: core.Shape_Entity,
    limb_length: f32) -> [8]u16 {
    indices: [8]u16
    indices[0], _ = world_create_center_pivot_constraint(world, {
        first = joint1, pivot = pivot, second = joint2,
        limb_length = limb_length, enabled = true})
    indices[1], _ = world_create_distance_constraint(world, {
        first = joint1, second = pivot, length = limb_length,
        movement = .Move_Second, enabled = true})
    indices[2], _ = world_create_distance_constraint(world, {
        first = pivot, second = joint2, length = limb_length,
        movement = .Move_First, enabled = true})
    floor_targets := [3]core.Shape_Entity{joint1, pivot, joint2}
    for target, offset in floor_targets {
        indices[3 + offset], _ = world_create_floor_constraint(world, {
            point = target, enabled = true})
    }
    indices[6], _ = world_create_snap_point_constraint(world, {
        point = joint1, enabled = false})
    indices[7], _ = world_create_snap_point_constraint(world, {
        point = joint2, enabled = false})
    return indices
}

// Create one compass whose geometry and constraints name all joints directly.
world_create_compass :: proc(
    world: ^core.Shape_World,
    input: World_Compass_Input) -> (
    core.Shape_Compass_Handle, core.Shape_World_Status) {
    if world == nil {
        return {}, .Invalid_Argument
    }
    needs := core.Shape_Construction_Needs{entities = 4, transforms = 3,
        render_styles = 1, active_features = 1, geometries = 1, constraints = 8}
    if !core.shape_world_has_capacity(world, needs) {
        return {}, .Out_Of_Capacity
    }
    shape := world_shape_append_entity(world)
    joint1 := world_shape_append_transform(world, input.joint1)
    pivot := world_shape_append_transform(world, input.pivot)
    joint2 := world_shape_append_transform(world, input.joint2)
    geometry := core.Shape_Geometry{kind = .Compass}
    geometry.payload.compass = {joint1 = joint1, pivot = pivot, joint2 = joint2}
    world_shape_publish_host(world, shape, input.style, geometry)
    feature_status := core.shape_component_insert(&world.active_features,
        &world.registry, shape, core.Shape_Active_Feature{})
    assert(feature_status == .Ok)
    indices := world_append_compass_constraints(
        world, joint1, pivot, joint2, input.limb_length)
    return {shape, joint1, pivot, joint2, indices[0], indices[1], indices[2],
        indices[3], indices[4], indices[5], indices[6], indices[7]}, .Ok
}
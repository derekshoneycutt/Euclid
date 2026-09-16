package shapes

import shapemodel "model"

import "core:math"

import rl "vendor:raylib"

// Supply presentation values shared by canonical shape constructors.
Shape_Style :: struct {
    color: rl.Color,
    brush_size: f32,
}

// Supply canonical arc geometry and presentation values.
Arc_Input :: struct {
    center: Vector3,
    radius, start_theta, sweep_theta: f32,
    style: Shape_Style,
}

// Supply two circles and the Boolean operation for one filled region.
Circle_Region_Input :: struct {
    first_center, second_center: Vector3,
    first_radius, second_radius: f32,
    operation: shapemodel.Shape_Circle_Region_Operation,
    style: Shape_Style,
}

// Supply canonical trochoid geometry and presentation values.
Trochoid_Input :: struct {
    center: Vector3,
    mode: shapemodel.Shape_Trochoid_Mode,
    fixed_radius: f32,
    rolling_radius: f32,
    tracer_distance: f32,
    tracer_phase: f32,
    rotation: f32,
    parameter_start: f32,
    parameter_finish: f32,
    draw_parameter: f32,
    style: Shape_Style,
}

// Supply canonical geometry and presentation values for the permanent guide tool.
Trochoid_Tool_Input :: struct {
    center: Vector3,
    mode: shapemodel.Shape_Trochoid_Mode,
    fixed_radius: f32,
    rolling_radius: f32,
    parameter: f32,
    rotation: f32,
    orientation_phase: f32,
    style: Shape_Style,
}

// Supply literal rail, scalar geometry, and presentation for one cycloid.
Cycloid_Input :: struct {
    first: Vector3,
    second: Vector3,
    rolling_radius: f32,
    tracer_distance: f32,
    tracer_phase: f32,
    parameter_start: f32,
    parameter_finish: f32,
    draw_parameter: f32,
    style: Shape_Style,
}

// Supply literal rail and rolling-circle values for the permanent guide.
Cycloid_Tool_Input :: struct {
    first: Vector3,
    second: Vector3,
    rolling_radius: f32,
    parameter_start: f32,
    parameter_finish: f32,
    parameter: f32,
    orientation_phase: f32,
    style: Shape_Style,
}

// Supply canonical source and presentation values for one world label.
World_Label_Input :: struct {
    source: string,
    mime: shapemodel.Shape_Text_Mime,
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
world_shape_append_entity :: proc(
    world: ^shapemodel.Shape_World) -> shapemodel.Shape_Entity {
    entity: shapemodel.Shape_Entity
    status := shapemodel.shape_world_create_entity(world, &entity)
    assert(status == .Ok)
    return entity
}

// Append one transform-bearing entity after capacity preflight.
world_shape_append_transform :: proc(
    world: ^shapemodel.Shape_World,
    position: Vector3) -> shapemodel.Shape_Entity {
    entity := world_shape_append_entity(world)
    status := shapemodel.shape_component_insert(
        &world.transforms, &world.registry, entity,
        shapemodel.Shape_Transform{position = position, previous_position = position})
    assert(status == .Ok)
    return entity
}

// Publish presentation and immutable geometry for one preflighted host entity.
world_shape_publish_host :: proc(
    world: ^shapemodel.Shape_World,
    entity: shapemodel.Shape_Entity,
    style: Shape_Style,
    geometry: shapemodel.Shape_Geometry) {
    style_status := shapemodel.shape_component_insert(
        &world.render_styles, &world.registry, entity,
        shapemodel.Shape_Render_Style{color = style.color,
            brush_size = style.brush_size, visible = false})
    geometry_status := shapemodel.shape_component_insert(
        &world.geometries, &world.registry, entity, geometry)
    assert(style_status == .Ok && geometry_status == .Ok)
}

// Create one standalone drawable point with no topology.
world_create_point :: proc(
    world: ^shapemodel.Shape_World,
    position: Vector3,
    style: Shape_Style) -> (
        shapemodel.Shape_Point_Handle, shapemodel.Shape_World_Status) {
    if world == nil {
        return {}, .Invalid_Argument
    }
    needs := shapemodel.Shape_Construction_Needs{
        entities = 1, transforms = 1, render_styles = 1, geometries = 1}
    if !shapemodel.shape_world_has_capacity(world, needs) {
        return {}, .Out_Of_Capacity
    }
    entity := world_shape_append_transform(world, position)
    world_shape_publish_host(world, entity, style, {.Point, {}})
    return {entity = entity}, .Ok
}

// Create one immutable single-line label after validating and preflighting its source.
world_create_label :: proc(
    world: ^shapemodel.Shape_World,
    input: World_Label_Input) -> (
        shapemodel.Shape_Label_Handle, shapemodel.Shape_World_Status) {
    if world == nil {
        return {}, .Invalid_Argument
    }
    status := shapemodel.shape_label_validate_source(input.mime, input.source)
    if status != .Ok {
        return {}, status
    }
    needs := shapemodel.Shape_Construction_Needs{entities = 1, transforms = 1,
        render_styles = 1, labels = 1, label_bytes = len(input.source)}
    if !shapemodel.shape_world_has_capacity(world, needs) {
        return {}, .Out_Of_Capacity
    }
    entity := world_shape_append_transform(world, input.position)
    label: shapemodel.Shape_Label
    status = shapemodel.shape_label_store_append(
        &world.label_store, input.mime, input.source, &label)
    assert(status == .Ok)
    status = shapemodel.shape_component_insert(
        &world.labels, &world.registry, entity, label)
    assert(status == .Ok)
    world_shape_publish_style(world, entity, input.style)
    return {entity = entity}, .Ok
}

// Publish presentation for one preflighted entity without geometry.
world_shape_publish_style :: proc(
    world: ^shapemodel.Shape_World,
    entity: shapemodel.Shape_Entity,
    style: Shape_Style) {
    status := shapemodel.shape_component_insert(
        &world.render_styles, &world.registry, entity,
        shapemodel.Shape_Render_Style{color = style.color,
            brush_size = style.brush_size, visible = false})
    assert(status == .Ok)
}

// Create one line host with direct endpoint references.
world_create_line :: proc(
    world: ^shapemodel.Shape_World,
    first_position, second_position: Vector3,
    style: Shape_Style) -> (shapemodel.Shape_Line_Handle, shapemodel.Shape_World_Status) {
    if world == nil {
        return {}, .Invalid_Argument
    }
    needs := shapemodel.Shape_Construction_Needs{
        entities = 3, transforms = 2, render_styles = 1, geometries = 1}
    if !shapemodel.shape_world_has_capacity(world, needs) {
        return {}, .Out_Of_Capacity
    }
    shape := world_shape_append_entity(world)
    first := world_shape_append_transform(world, first_position)
    second := world_shape_append_transform(world, second_position)
    geometry := shapemodel.Shape_Geometry{kind = .Line}
    geometry.payload.line = {first = first, second = second}
    world_shape_publish_host(world, shape, style, geometry)
    return {shape = shape, first = first, second = second}, .Ok
}

// Create one arc variant whose host transform is its center.
world_create_arc_kind :: proc(
    world: ^shapemodel.Shape_World,
    input: Arc_Input,
    kind: shapemodel.Shape_Geometry_Kind) -> (
        shapemodel.Shape_Arc_Handle, shapemodel.Shape_World_Status) {
    needs := shapemodel.Shape_Construction_Needs{
        entities = 1, transforms = 1, arcs = 1, render_styles = 1, geometries = 1}
    if world == nil || kind != .Arc && kind != .Filled_Arc {
        return {}, .Invalid_Argument
    }
    arc := shapemodel.Shape_Arc{radius = input.radius,
        start_theta = input.start_theta,
        sweep_theta = input.sweep_theta,
        previous_radius = input.radius,
        previous_start_theta = input.start_theta,
        previous_sweep_theta = input.sweep_theta}
    if !shapemodel.shape_arc_is_valid(arc) {
        return {}, .Invalid_Argument
    }
    if !shapemodel.shape_world_has_capacity(world, needs) {
        return {}, .Out_Of_Capacity
    }
    shape := world_shape_append_transform(world, input.center)
    geometry := shapemodel.Shape_Geometry{kind = kind}
    arc_status := shapemodel.shape_component_insert(
        &world.arcs, &world.registry, shape, arc)
    assert(arc_status == .Ok)
    world_shape_publish_host(world, shape, input.style, geometry)
    return {shape = shape}, .Ok
}

// Create one outlined arc with direct transform references.
world_create_arc :: proc(
    world: ^shapemodel.Shape_World,
    input: Arc_Input) -> (shapemodel.Shape_Arc_Handle, shapemodel.Shape_World_Status) {
    return world_create_arc_kind(world, input, .Arc)
}

// Create one filled arc with direct transform references.
world_create_filled_arc :: proc(
    world: ^shapemodel.Shape_World,
    input: Arc_Input) -> (shapemodel.Shape_Arc_Handle, shapemodel.Shape_World_Status) {
    return world_create_arc_kind(world, input, .Filled_Arc)
}

// Return whether two coplanar circles have exactly two distinct intersections.
world_circle_region_input_is_valid :: proc(input: Circle_Region_Input) -> bool {
    delta := input.second_center - input.first_center
    distance_squared := delta.x * delta.x + delta.y * delta.y
    distance := f32(math.sqrt(distance_squared))
    radius_delta := math.abs(input.first_radius - input.second_radius)
    return shapemodel.shape_circle_region_is_valid({operation = input.operation,
        first_radius = input.first_radius, second_radius = input.second_radius}) &&
        shapemodel.shape_scalar_is_finite(input.first_center.x) &&
        shapemodel.shape_scalar_is_finite(input.first_center.y) &&
        shapemodel.shape_scalar_is_finite(input.first_center.z) &&
        shapemodel.shape_scalar_is_finite(input.second_center.x) &&
        shapemodel.shape_scalar_is_finite(input.second_center.y) &&
        shapemodel.shape_scalar_is_finite(input.second_center.z) &&
        input.first_center.z == input.second_center.z &&
        distance > radius_delta && distance < input.first_radius + input.second_radius
}

// Create one analytic two-circle filled region after complete capacity preflight.
world_create_circle_region :: proc(
    world: ^shapemodel.Shape_World,
    input: Circle_Region_Input) -> (
    shapemodel.Shape_Circle_Region_Handle, shapemodel.Shape_World_Status) {
    if world == nil || !world_circle_region_input_is_valid(input) {
        return {}, .Invalid_Argument
    }
    needs := shapemodel.Shape_Construction_Needs{entities = 3, transforms = 2,
        render_styles = 1, geometries = 1}
    if !shapemodel.shape_world_has_capacity(world, needs) {
        return {}, .Out_Of_Capacity
    }
    shape := world_shape_append_entity(world)
    first := world_shape_append_transform(world, input.first_center)
    second := world_shape_append_transform(world, input.second_center)
    value := shapemodel.Shape_Circle_Region{operation = input.operation,
        first_radius = input.first_radius, second_radius = input.second_radius}
    geometry := shapemodel.Shape_Geometry{kind = .Circle_Region}
    geometry.payload.circle_region = {
        first_center = first, second_center = second, value = value}
    world_shape_publish_host(world, shape, input.style, geometry)
    return {shape = shape, first_center = first, second_center = second}, .Ok
}

// Create the intersection of two properly overlapping circles.
world_create_lens :: proc(
    world: ^shapemodel.Shape_World,
    input: Circle_Region_Input) -> (
    shapemodel.Shape_Circle_Region_Handle, shapemodel.Shape_World_Status) {
    value := input
    value.operation = .Intersection
    return world_create_circle_region(world, value)
}

// Create the directional difference of the first circle minus the second.
world_create_lune :: proc(
    world: ^shapemodel.Shape_World,
    input: Circle_Region_Input) -> (
    shapemodel.Shape_Circle_Region_Handle, shapemodel.Shape_World_Status) {
    value := input
    value.operation = .Difference
    return world_create_circle_region(world, value)
}

// Create one outlined trochoid whose host transform is its fixed center.
world_create_trochoid :: proc(
    world: ^shapemodel.Shape_World,
    input: Trochoid_Input) -> (
        shapemodel.Shape_Trochoid_Handle, shapemodel.Shape_World_Status) {
    value := shapemodel.Shape_Trochoid{mode = input.mode,
        fixed_radius = input.fixed_radius, rolling_radius = input.rolling_radius,
        tracer_distance = input.tracer_distance, tracer_phase = input.tracer_phase,
        rotation = input.rotation, parameter_start = input.parameter_start,
        parameter_finish = input.parameter_finish, draw_parameter = input.draw_parameter,
        previous_fixed_radius = input.fixed_radius,
        previous_rolling_radius = input.rolling_radius,
        previous_tracer_distance = input.tracer_distance,
        previous_tracer_phase = input.tracer_phase, previous_rotation = input.rotation,
        previous_parameter_start = input.parameter_start,
        previous_parameter_finish = input.parameter_finish,
        previous_draw_parameter = input.draw_parameter}
    if world == nil || !shapemodel.shape_trochoid_is_valid(value) {
        return {}, .Invalid_Argument
    }
    needs := shapemodel.Shape_Construction_Needs{entities = 1, transforms = 1,
        trochoids = 1, render_styles = 1, geometries = 1}
    if !shapemodel.shape_world_has_capacity(world, needs) {
        return {}, .Out_Of_Capacity
    }
    shape := world_shape_append_transform(world, input.center)
    status := shapemodel.shape_component_insert(
        &world.trochoids, &world.registry, shape, value)
    assert(status == .Ok)
    world_shape_publish_host(world, shape, input.style, {.Trochoid, {}})
    return {shape = shape}, .Ok
}

// Create one two-ring guide whose host transform is its fixed center.
world_create_trochoid_tool :: proc(
    world: ^shapemodel.Shape_World,
    input: Trochoid_Tool_Input) -> (
        shapemodel.Shape_Trochoid_Tool_Handle, shapemodel.Shape_World_Status) {
    value := shapemodel.Shape_Trochoid_Tool{mode = input.mode,
        fixed_radius = input.fixed_radius, rolling_radius = input.rolling_radius,
        parameter = input.parameter, rotation = input.rotation,
        orientation_phase = input.orientation_phase,
        previous_fixed_radius = input.fixed_radius,
        previous_rolling_radius = input.rolling_radius,
        previous_parameter = input.parameter, previous_rotation = input.rotation,
        previous_orientation_phase = input.orientation_phase}
    if world == nil || !shapemodel.shape_trochoid_tool_is_valid(value) {
        return {}, .Invalid_Argument
    }
    needs := shapemodel.Shape_Construction_Needs{entities = 1, transforms = 1,
        trochoid_tools = 1, render_styles = 1, geometries = 1}
    if !shapemodel.shape_world_has_capacity(world, needs) {
        return {}, .Out_Of_Capacity
    }
    shape := world_shape_append_transform(world, input.center)
    status := shapemodel.shape_component_insert(
        &world.trochoid_tools, &world.registry, shape, value)
    assert(status == .Ok)
    world_shape_publish_host(world, shape, input.style, {.Trochoid_Tool, {}})
    return {shape = shape}, .Ok
}

// Create one cycloid host with two authoritative endpoint transforms.
world_create_cycloid :: proc(
    world: ^shapemodel.Shape_World,
    input: Cycloid_Input) -> (
        shapemodel.Shape_Cycloid_Handle, shapemodel.Shape_World_Status) {
    value := shapemodel.Shape_Cycloid{rolling_radius = input.rolling_radius,
        tracer_distance = input.tracer_distance, tracer_phase = input.tracer_phase,
        parameter_start = input.parameter_start,
        parameter_finish = input.parameter_finish, draw_parameter = input.draw_parameter,
        previous_rolling_radius = input.rolling_radius,
        previous_tracer_distance = input.tracer_distance,
        previous_tracer_phase = input.tracer_phase,
        previous_parameter_start = input.parameter_start,
        previous_parameter_finish = input.parameter_finish,
        previous_draw_parameter = input.draw_parameter}
    if world == nil || !shapemodel.shape_cycloid_is_valid(value) ||
        !shapemodel.shape_cycloid_line_is_valid(input.first, input.second,
            input.rolling_radius, input.parameter_start, input.parameter_finish) {
        return {}, .Invalid_Argument
    }
    needs := shapemodel.Shape_Construction_Needs{entities = 3, transforms = 2,
        cycloids = 1, render_styles = 1, geometries = 1}
    if !shapemodel.shape_world_has_capacity(world, needs) {
        return {}, .Out_Of_Capacity
    }
    shape := world_shape_append_entity(world)
    first := world_shape_append_transform(world, input.first)
    second := world_shape_append_transform(world, input.second)
    status := shapemodel.shape_component_insert(
        &world.cycloids, &world.registry, shape, value)
    assert(status == .Ok)
    geometry := shapemodel.Shape_Geometry{kind = .Cycloid}
    geometry.payload.cycloid = {first = first, second = second}
    world_shape_publish_host(world, shape, input.style, geometry)
    return {shape = shape, first = first, second = second}, .Ok
}

// Create the permanent cycloid guide with its own endpoint transforms.
world_create_cycloid_tool :: proc(
    world: ^shapemodel.Shape_World,
    input: Cycloid_Tool_Input) -> (
        shapemodel.Shape_Cycloid_Tool_Handle, shapemodel.Shape_World_Status) {
    value := shapemodel.Shape_Cycloid_Tool{rolling_radius = input.rolling_radius,
        parameter_start = input.parameter_start,
        parameter_finish = input.parameter_finish, parameter = input.parameter,
        orientation_phase = input.orientation_phase,
        previous_rolling_radius = input.rolling_radius,
        previous_parameter_start = input.parameter_start,
        previous_parameter_finish = input.parameter_finish,
        previous_parameter = input.parameter,
        previous_orientation_phase = input.orientation_phase}
    if world == nil || !shapemodel.shape_cycloid_tool_is_valid(value) ||
        !shapemodel.shape_cycloid_line_is_valid(input.first, input.second,
            input.rolling_radius, input.parameter_start, input.parameter_finish) {
        return {}, .Invalid_Argument
    }
    needs := shapemodel.Shape_Construction_Needs{entities = 3, transforms = 2,
        cycloid_tools = 1, render_styles = 1, geometries = 1}
    if !shapemodel.shape_world_has_capacity(world, needs) {
        return {}, .Out_Of_Capacity
    }
    shape := world_shape_append_entity(world)
    first := world_shape_append_transform(world, input.first)
    second := world_shape_append_transform(world, input.second)
    status := shapemodel.shape_component_insert(
        &world.cycloid_tools, &world.registry, shape, value)
    assert(status == .Ok)
    geometry := shapemodel.Shape_Geometry{kind = .Cycloid_Tool}
    geometry.payload.cycloid_tool = {first = first, second = second}
    world_shape_publish_host(world, shape, input.style, geometry)
    return {shape = shape, first = first, second = second}, .Ok
}

// Append ordered transform entities for one preflighted polygon.
world_shape_append_vertices :: proc(
    world: ^shapemodel.Shape_World,
    positions: []Vector3,
    entities: []shapemodel.Shape_Entity) {
    assert(len(positions) == len(entities))
    for position, index in positions {
        entities[index] = world_shape_append_transform(world, position)
    }
}

// Create one polygon and return its ordered vertex entities in caller storage.
world_create_polygon_into :: proc(
    world: ^shapemodel.Shape_World,
    positions: []Vector3,
    style: Shape_Style,
    vertices: []shapemodel.Shape_Entity) -> (
    shapemodel.Shape_Polygon_Handle, shapemodel.Shape_World_Status) {
    if world == nil || len(positions) < 3 || len(vertices) != len(positions) {
        return {}, .Invalid_Argument
    }
    needs := shapemodel.Shape_Construction_Needs{entities = len(positions) + 1,
        transforms = len(positions), render_styles = 1, geometries = 1,
        vertex_references = len(positions)}
    if !shapemodel.shape_world_has_capacity(world, needs) {
        return {}, .Out_Of_Capacity
    }
    shape := world_shape_append_entity(world)
    world_shape_append_vertices(world, positions, vertices)
    polygon: shapemodel.Shape_Polygon_Geometry
    status := shapemodel.shape_vertex_references_append(
        world, vertices, &polygon)
    assert(status == .Ok)
    geometry := shapemodel.Shape_Geometry{kind = .Polygon}
    geometry.payload.polygon = polygon
    world_shape_publish_host(world, shape, style, geometry)
    return {shape = shape}, .Ok
}

// Create one variable-arity polygon with immutable ordered topology.
world_create_polygon :: proc(
    world: ^shapemodel.Shape_World,
    positions: []Vector3,
    style: Shape_Style) -> (
        shapemodel.Shape_Polygon_Handle, shapemodel.Shape_World_Status) {
    vertices: [shapemodel.MAX_SHAPE_VERTEX_REFERENCES]shapemodel.Shape_Entity
    if len(positions) > len(vertices) {
        return {}, .Out_Of_Capacity
    }
    return world_create_polygon_into(world, positions, style, vertices[:len(positions)])
}

// Create one triangle as a typed three-vertex polygon convenience.
world_create_triangle :: proc(
    world: ^shapemodel.Shape_World,
    positions: [3]Vector3,
    style: Shape_Style) -> (
        shapemodel.Shape_Triangle_Handle, shapemodel.Shape_World_Status) {
    position_values := positions
    vertices: [3]shapemodel.Shape_Entity
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
    world: ^shapemodel.Shape_World,
    positions: [4]Vector3,
    style: Shape_Style) -> (
        shapemodel.Shape_Square_Handle, shapemodel.Shape_World_Status) {
    position_values := positions
    vertices: [4]shapemodel.Shape_Entity
    polygon, status := world_create_polygon_into(
        world, position_values[:], style, vertices[:])
    if status != .Ok {
        return {}, status
    }
    return {shape = polygon.shape, vertices = vertices}, .Ok
}

// Create one pentagon as a typed five-vertex polygon convenience.
world_create_pentagon :: proc(
    world: ^shapemodel.Shape_World,
    positions: [5]Vector3,
    style: Shape_Style) -> (
        shapemodel.Shape_Pentagon_Handle, shapemodel.Shape_World_Status) {
    position_values := positions
    vertices: [5]shapemodel.Shape_Entity
    polygon, status := world_create_polygon_into(
        world, position_values[:], style, vertices[:])
    if status != .Ok {
        return {}, status
    }
    return {shape = polygon.shape, vertices = vertices}, .Ok
}

// Append the five direct-target constraints owned by one preflighted pen.
world_append_pen_constraints :: proc(
    world: ^shapemodel.Shape_World,
    joint1, joint2: shapemodel.Shape_Entity,
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
    world: ^shapemodel.Shape_World,
    input: World_Pen_Input) -> (
        shapemodel.Shape_Pen_Handle, shapemodel.Shape_World_Status) {
    if world == nil {
        return {}, .Invalid_Argument
    }
    needs := shapemodel.Shape_Construction_Needs{entities = 3, transforms = 2,
        render_styles = 1, active_features = 1, geometries = 1, constraints = 5}
    if !shapemodel.shape_world_has_capacity(world, needs) {
        return {}, .Out_Of_Capacity
    }
    shape := world_shape_append_entity(world)
    joint1 := world_shape_append_transform(world, input.joint1)
    joint2 := world_shape_append_transform(world, input.joint2)
    geometry := shapemodel.Shape_Geometry{kind = .Pen}
    geometry.payload.pen = {joint1 = joint1, joint2 = joint2}
    world_shape_publish_host(world, shape, input.style, geometry)
    feature_status := shapemodel.shape_component_insert(&world.active_features,
        &world.registry, shape, shapemodel.Shape_Active_Feature{})
    assert(feature_status == .Ok)
    indices := world_append_pen_constraints(world, joint1, joint2, input.length)
    return {shape, joint1, joint2,
        indices[0], indices[1], indices[2], indices[3], indices[4]}, .Ok
}

// Append the eight direct-target constraints owned by one preflighted compass.
world_append_compass_constraints :: proc(
    world: ^shapemodel.Shape_World,
    joint1, pivot, joint2: shapemodel.Shape_Entity,
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
    floor_targets := [3]shapemodel.Shape_Entity{joint1, pivot, joint2}
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
    world: ^shapemodel.Shape_World,
    input: World_Compass_Input) -> (
    shapemodel.Shape_Compass_Handle, shapemodel.Shape_World_Status) {
    if world == nil {
        return {}, .Invalid_Argument
    }
    needs := shapemodel.Shape_Construction_Needs{entities = 4, transforms = 3,
        render_styles = 1, active_features = 1, geometries = 1, constraints = 8}
    if !shapemodel.shape_world_has_capacity(world, needs) {
        return {}, .Out_Of_Capacity
    }
    shape := world_shape_append_entity(world)
    joint1 := world_shape_append_transform(world, input.joint1)
    pivot := world_shape_append_transform(world, input.pivot)
    joint2 := world_shape_append_transform(world, input.joint2)
    geometry := shapemodel.Shape_Geometry{kind = .Compass}
    geometry.payload.compass = {joint1 = joint1, pivot = pivot, joint2 = joint2}
    world_shape_publish_host(world, shape, input.style, geometry)
    feature_status := shapemodel.shape_component_insert(&world.active_features,
        &world.registry, shape, shapemodel.Shape_Active_Feature{})
    assert(feature_status == .Ok)
    indices := world_append_compass_constraints(
        world, joint1, pivot, joint2, input.limb_length)
    return {shape, joint1, pivot, joint2, indices[0], indices[1], indices[2],
        indices[3], indices[4], indices[5], indices[6], indices[7]}, .Ok
}
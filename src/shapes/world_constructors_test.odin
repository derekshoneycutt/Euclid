package shapes

import shapemodel "model"

import "core:math"
import "core:testing"


// Return one visible test style with stable scalar values.
world_shape_test_style :: proc() -> Shape_Style {
    return {color = {10, 20, 30, 255}, brush_size = 0.25}
}

// Verify point and line constructors publish only their meaningful components.
@(test)
shapes_test_world_creates_point_and_line_geometry :: proc(t: ^testing.T) {
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    point, point_status := world_create_point(
        world, {1, 2, 3}, world_shape_test_style())
    testing.expect_value(t, point_status, shapemodel.Shape_World_Status.Ok)
    testing.expect(t, shapemodel.shape_component_contains(
        &world.transforms, &world.registry, point.entity))

    line, line_status := world_create_line(
        world, {4, 5, 6}, {7, 8, 9}, world_shape_test_style())
    testing.expect_value(t, line_status, shapemodel.Shape_World_Status.Ok)
    geometry, found := shapemodel.shape_component_get(
        &world.geometries, &world.registry, line.shape)
    testing.expect(t, found)
    testing.expect_value(t, geometry.kind, shapemodel.Shape_Geometry_Kind.Line)
    testing.expect_value(t, geometry.payload.line.first, line.first)
    testing.expect_value(t, geometry.payload.line.second, line.second)
}

// Verify outlined and filled arcs retain one direct signed-sweep component each.
@(test)
shapes_test_world_creates_arc_variants :: proc(t: ^testing.T) {
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    input := Arc_Input{center = {1, 2, 3}, radius = 2,
        start_theta = 0, sweep_theta = f32(math.PI), style = world_shape_test_style()}
    arc, arc_status := world_create_arc(world, input)
    filled, filled_status := world_create_filled_arc(world, input)
    testing.expect_value(t, arc_status, shapemodel.Shape_World_Status.Ok)
    testing.expect_value(t, filled_status, shapemodel.Shape_World_Status.Ok)

    arc_geometry, arc_found := shapemodel.shape_component_get(
        &world.geometries, &world.registry, arc.shape)
    filled_geometry, filled_found := shapemodel.shape_component_get(
        &world.geometries, &world.registry, filled.shape)
    testing.expect(t, arc_found && filled_found)
    testing.expect_value(t, arc_geometry.kind, shapemodel.Shape_Geometry_Kind.Arc)
    testing.expect_value(
        t, filled_geometry.kind, shapemodel.Shape_Geometry_Kind.Filled_Arc)
    arc_value, arc_value_found := shapemodel.shape_component_get(
        &world.arcs, &world.registry, arc.shape)
    filled_value, filled_value_found := shapemodel.shape_component_get(
        &world.arcs, &world.registry, filled.shape)
    testing.expect(t, arc_value_found && filled_value_found)
    testing.expect_value(t, arc_value.radius, f32(2))
    testing.expect_value(t, arc_value.start_theta, f32(0))
    testing.expect_value(t, arc_value.sweep_theta, f32(math.PI))
    testing.expect_value(t, filled_value.sweep_theta, f32(math.PI))
    testing.expect_value(t, world.registry.entity_count, u32(2))
    testing.expect_value(t, world.transforms.count, u16(2))
    testing.expect_value(t, world.arcs.count, u16(2))
}

// Verify Lens and directional Lune constructors publish one shared region topology.
@(test)
shapes_test_world_creates_circle_region_variants :: proc(t: ^testing.T) {
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    input := Circle_Region_Input{first_center = {0, 0, 0},
        second_center = {1, 0, 0}, first_radius = 1, second_radius = 1,
        style = world_shape_test_style()}
    lens, lens_status := world_create_lens(world, input)
    lune, lune_status := world_create_lune(world, input)
    testing.expect_value(t, lens_status, shapemodel.Shape_World_Status.Ok)
    testing.expect_value(t, lune_status, shapemodel.Shape_World_Status.Ok)
    lens_geometry, lens_found := shapemodel.shape_component_get(
        &world.geometries, &world.registry, lens.shape)
    lune_geometry, lune_found := shapemodel.shape_component_get(
        &world.geometries, &world.registry, lune.shape)
    testing.expect(t, lens_found && lune_found)
    testing.expect_value(t, lens_geometry.payload.circle_region.value.operation,
        shapemodel.Shape_Circle_Region_Operation.Intersection)
    testing.expect_value(t, lune_geometry.payload.circle_region.value.operation,
        shapemodel.Shape_Circle_Region_Operation.Difference)
    testing.expect(t, lens.first_center != lens.second_center)
}

// Verify unsupported circle topology is rejected without partial publication.
@(test)
shapes_test_world_rejects_nonproper_circle_region :: proc(t: ^testing.T) {
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    _, status := world_create_lens(world, {first_center = {0, 0, 0},
        second_center = {3, 0, 0}, first_radius = 1, second_radius = 1,
        style = world_shape_test_style()})
    testing.expect_value(t, status, shapemodel.Shape_World_Status.Invalid_Argument)
    testing.expect_value(t, world.registry.entity_count, u32(0))
    testing.expect_value(t, world.transforms.count, u16(0))
}

// Verify trochoid curve and guide constructors publish independent analytic hosts.
@(test)
shapes_test_world_creates_trochoid_and_guide :: proc(t: ^testing.T) {
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    curve, curve_status := world_create_trochoid(world, {center = {1, 2, 3},
        mode = .External, fixed_radius = 2, rolling_radius = 1,
        tracer_distance = 0.5, parameter_start = 0, parameter_finish = 4,
        draw_parameter = 1, style = world_shape_test_style()})
    guide, guide_status := world_create_trochoid_tool(world, {center = {1, 2, 3},
        mode = .External, fixed_radius = 2, rolling_radius = 1,
        style = world_shape_test_style()})

    testing.expect_value(t, curve_status, shapemodel.Shape_World_Status.Ok)
    testing.expect_value(t, guide_status, shapemodel.Shape_World_Status.Ok)
    curve_geometry, curve_found := shapemodel.shape_component_get(
        &world.geometries, &world.registry, curve.shape)
    guide_geometry, guide_found := shapemodel.shape_component_get(
        &world.geometries, &world.registry, guide.shape)
    testing.expect(t, curve_found && guide_found)
    testing.expect_value(t, curve_geometry.kind, shapemodel.Shape_Geometry_Kind.Trochoid)
    testing.expect_value(t, guide_geometry.kind,
        shapemodel.Shape_Geometry_Kind.Trochoid_Tool)
    testing.expect_value(t, world.trochoids.count, u16(1))
    testing.expect_value(t, world.trochoid_tools.count, u16(1))
}

// Verify invalid trochoid construction leaves every world frontier unchanged.
@(test)
shapes_test_world_rejects_invalid_trochoid_transactionally :: proc(t: ^testing.T) {
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    _, status := world_create_trochoid(world, {mode = .Internal,
        fixed_radius = 1, rolling_radius = 1, tracer_distance = 1,
        parameter_start = 0, parameter_finish = 2, draw_parameter = 0,
        style = world_shape_test_style()})

    testing.expect_value(t, status, shapemodel.Shape_World_Status.Invalid_Argument)
    testing.expect_value(t, world.registry.entity_count, u32(0))
    testing.expect_value(t, world.transforms.count, u16(0))
    testing.expect_value(t, world.trochoids.count, u16(0))
    testing.expect_value(t, world.geometries.count, u16(0))
}

// Verify cycloid curve and guide retain independent literal endpoint identities.
@(test)
shapes_test_world_creates_cycloid_and_guide :: proc(t: ^testing.T) {
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    first := Vector3{-0.4, 0.2, 0}
    second := Vector3{0.4, 0.2, 0}
    curve, curve_status := world_create_cycloid(world, {first = first,
        second = second, rolling_radius = 0.05, tracer_distance = 0.05,
        parameter_start = 0, parameter_finish = 4 * math.PI,
        draw_parameter = 0, style = world_shape_test_style()})
    guide, guide_status := world_create_cycloid_tool(world, {first = first,
        second = second, rolling_radius = 0.05, parameter_start = 0,
        parameter_finish = 4 * math.PI, style = world_shape_test_style()})

    testing.expect_value(t, curve_status, shapemodel.Shape_World_Status.Ok)
    testing.expect_value(t, guide_status, shapemodel.Shape_World_Status.Ok)
    curve_geometry, curve_found := shapemodel.shape_component_get(
        &world.geometries, &world.registry, curve.shape)
    guide_geometry, guide_found := shapemodel.shape_component_get(
        &world.geometries, &world.registry, guide.shape)
    testing.expect(t, curve_found && guide_found)
    testing.expect_value(t, curve_geometry.payload.cycloid.first, curve.first)
    testing.expect_value(t, curve_geometry.payload.cycloid.second, curve.second)
    testing.expect_value(t, guide_geometry.payload.cycloid_tool.first, guide.first)
    testing.expect_value(t, guide_geometry.payload.cycloid_tool.second, guide.second)
    testing.expect(t, curve.first != guide.first && curve.second != guide.second)
    testing.expect_value(t, world.registry.entity_count, u32(6))
    testing.expect_value(t, world.transforms.count, u16(4))
}

// Verify invalid rail travel leaves every world frontier unchanged.
@(test)
shapes_test_world_rejects_invalid_cycloid_transactionally :: proc(t: ^testing.T) {
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    _, status := world_create_cycloid(world, {first = {0, 0, 0},
        second = {0.1, 0, 0}, rolling_radius = 0.1, tracer_distance = 0.1,
        parameter_start = 0, parameter_finish = 4 * math.PI,
        draw_parameter = 0, style = world_shape_test_style()})

    testing.expect_value(t, status, shapemodel.Shape_World_Status.Invalid_Argument)
    testing.expect_value(t, world.registry.entity_count, u32(0))
    testing.expect_value(t, world.transforms.count, u16(0))
    testing.expect_value(t, world.cycloids.count, u16(0))
    testing.expect_value(t, world.geometries.count, u16(0))
}

// Verify polygon conveniences preserve authored vertex order in the reference pool.
@(test)
shapes_test_world_polygon_conveniences_preserve_order :: proc(t: ^testing.T) {
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    positions := [5]Vector3{{1, 0, 0}, {2, 0, 0}, {3, 0, 0}, {4, 0, 0}, {5, 0, 0}}
    pentagon, status := world_create_pentagon(
        world, positions, world_shape_test_style())
    testing.expect_value(t, status, shapemodel.Shape_World_Status.Ok)
    geometry, found := shapemodel.shape_component_get(
        &world.geometries, &world.registry, pentagon.shape)
    testing.expect(t, found)
    vertices, vertices_found := shapemodel.shape_polygon_vertices(
        world, geometry.payload.polygon)
    testing.expect(t, vertices_found)
    testing.expect_value(t, len(vertices), 5)
    for vertex, index in vertices {
        testing.expect_value(t, vertex, pentagon.vertices[index])
        transform, transform_found := shapemodel.shape_component_get(
            &world.transforms, &world.registry, vertex)
        testing.expect(t, transform_found)
        testing.expect_value(t, transform.position, positions[index])
    }
}

// Verify triangle and square conveniences publish the expected polygon spans.
@(test)
shapes_test_world_creates_triangle_and_square :: proc(t: ^testing.T) {
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    triangle_positions := [3]Vector3{{0, 0, 0}, {1, 0, 0}, {0, 1, 0}}
    square_positions := [4]Vector3{{0, 0, 0}, {1, 0, 0}, {1, 1, 0}, {0, 1, 0}}
    triangle, triangle_status := world_create_triangle(
        world, triangle_positions, world_shape_test_style())
    square, square_status := world_create_square(
        world, square_positions, world_shape_test_style())
    testing.expect_value(t, triangle_status, shapemodel.Shape_World_Status.Ok)
    testing.expect_value(t, square_status, shapemodel.Shape_World_Status.Ok)
    testing.expect(t, shapemodel.shape_registry_resolves(&world.registry, triangle.third))
    testing.expect(t, shapemodel.shape_registry_resolves(
        &world.registry, square.vertices[3]))
    testing.expect_value(t, world.vertex_references.count, u16(7))
}

// Verify label creation publishes bytes and components as one successful operation.
@(test)
shapes_test_world_creates_unicode_label :: proc(t: ^testing.T) {
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    label, status := world_create_label(world, {
        source = "A′", mime = .Text_Plain, position = {1, 2, 3},
        style = world_shape_test_style()})
    testing.expect_value(t, status, shapemodel.Shape_World_Status.Ok)
    component, found := shapemodel.shape_component_get(
        &world.labels, &world.registry, label.entity)
    testing.expect(t, found)
    source, source_found := shapemodel.shape_label_source(&world.label_store, component^)
    testing.expect(t, source_found)
    testing.expect_value(t, source, "A′")
}

// Verify label pool exhaustion rejects before publishing any entity or component.
@(test)
shapes_test_world_label_capacity_failure_is_transactional :: proc(t: ^testing.T) {
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    world.label_store.byte_count = shapemodel.MAX_SHAPE_LABEL_TOTAL_BYTES - 1
    before_entities := world.registry.entity_count
    before_labels := world.labels.count
    before_styles := world.render_styles.count

    _, status := world_create_label(world, {
        source = "AB", mime = .Text_Plain, style = world_shape_test_style()})
    testing.expect_value(t, status, shapemodel.Shape_World_Status.Out_Of_Capacity)
    testing.expect_value(t, world.registry.entity_count, before_entities)
    testing.expect_value(t, world.labels.count, before_labels)
    testing.expect_value(t, world.render_styles.count, before_styles)
    testing.expect_value(t, world.label_store.byte_count,
        u16(shapemodel.MAX_SHAPE_LABEL_TOTAL_BYTES - 1))
}

// Verify animation retirement rewinds topology and label source with their components.
@(test)
shapes_test_world_rewinds_polygon_and_label_storage :: proc(t: ^testing.T) {
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    baseline_positions := [3]Vector3{{0, 0, 0}, {1, 0, 0}, {0, 1, 0}}
    _, baseline_polygon_status := world_create_triangle(
        world, baseline_positions, world_shape_test_style())
    baseline_label, baseline_label_status := world_create_label(world, {
        source = "A", mime = .Text_Plain, style = world_shape_test_style()})
    testing.expect_value(t, baseline_polygon_status, shapemodel.Shape_World_Status.Ok)
    testing.expect_value(t, baseline_label_status, shapemodel.Shape_World_Status.Ok)
    testing.expect_value(t, shapemodel.shape_world_freeze_baseline(
        world), shapemodel.Shape_World_Status.Ok)
    positions := [3]Vector3{{0, 0, 0}, {1, 0, 0}, {0, 1, 0}}
    _, polygon_status := world_create_triangle(
        world, positions, world_shape_test_style())
    _, label_status := world_create_label(world, {
        source = "α", mime = .Text_Plain, style = world_shape_test_style()})
    testing.expect_value(t, polygon_status, shapemodel.Shape_World_Status.Ok)
    testing.expect_value(t, label_status, shapemodel.Shape_World_Status.Ok)

    testing.expect_value(t, shapemodel.shape_world_rewind_animation(
        world), shapemodel.Shape_World_Status.Ok)
    testing.expect_value(t, world.registry.entity_count, u32(5))
    testing.expect_value(t, world.geometries.count, u16(1))
    testing.expect_value(t, world.labels.count, u16(1))
    testing.expect_value(t, world.vertex_references.count, u16(3))
    testing.expect_value(t, world.label_store.byte_count, u16(1))
    label, found := shapemodel.shape_component_get(
        &world.labels, &world.registry, baseline_label.entity)
    testing.expect(t, found)
    source, source_found := shapemodel.shape_label_source(&world.label_store, label^)
    testing.expect(t, source_found)
    testing.expect_value(t, source, "A")
}

// Verify capacity rejection occurs before any world frontier changes.
@(test)
shapes_test_world_constructor_capacity_failure_is_transactional :: proc(t: ^testing.T) {
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    world.registry.entity_count = shapemodel.MAX_SHAPE_ENTITIES - 2
    before_registry := world.registry.entity_count
    before_transforms := world.transforms.count
    before_styles := world.render_styles.count
    before_geometry := world.geometries.count

    _, status := world_create_line(
        world, {1, 2, 3}, {4, 5, 6}, world_shape_test_style())
    testing.expect_value(t, status, shapemodel.Shape_World_Status.Out_Of_Capacity)
    testing.expect_value(t, world.registry.entity_count, before_registry)
    testing.expect_value(t, world.transforms.count, before_transforms)
    testing.expect_value(t, world.render_styles.count, before_styles)
    testing.expect_value(t, world.geometries.count, before_geometry)
}

// Verify pen construction publishes direct geometry and its five ordered constraints.
@(test)
shapes_test_world_creates_pen_with_direct_constraints :: proc(t: ^testing.T) {
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    pen, status := world_create_pen(world, {
        joint1 = {-1, 0, 0}, joint2 = {1, 0, 0}, length = 2,
        style = world_shape_test_style()})
    testing.expect_value(t, status, shapemodel.Shape_World_Status.Ok)
    testing.expect_value(t, world.constraints.count, u16(5))
    geometry, found := shapemodel.shape_component_get(
        &world.geometries, &world.registry, pen.shape)
    testing.expect(t, found)
    testing.expect_value(t, geometry.payload.pen.joint1, pen.joint1)
    distance := world.constraints.values[pen.length_constraint].payload.distance
    testing.expect_value(t, distance.first, pen.joint1)
    testing.expect_value(t, distance.second, pen.joint2)
    testing.expect_value(t, distance.movement,
        shapemodel.Shape_Constraint_Movement_Policy.Move_Both)
    testing.expect(t, !world.constraints.values[pen.joint1_lock_constraint].enabled)
    testing.expect(t, !world.constraints.values[pen.joint2_lock_constraint].enabled)
}

// Verify compass construction names each limb and pivot without child offsets.
@(test)
shapes_test_world_creates_compass_with_direct_constraints :: proc(t: ^testing.T) {
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    compass, status := world_create_compass(world, {
        joint1 = {-1, 0, 0}, pivot = {}, joint2 = {1, 0, 0}, limb_length = 1,
        style = world_shape_test_style()})
    testing.expect_value(t, status, shapemodel.Shape_World_Status.Ok)
    testing.expect_value(t, world.constraints.count, u16(8))
    center := world.constraints.values[
        compass.center_pivot_constraint].payload.center_pivot
    first_limb := world.constraints.values[
        compass.limb1_length_constraint].payload.distance
    second_limb := world.constraints.values[
        compass.limb2_length_constraint].payload.distance
    testing.expect_value(t, center.pivot, compass.pivot)
    testing.expect_value(t, first_limb.first, compass.joint1)
    testing.expect_value(t, first_limb.second, compass.pivot)
    testing.expect_value(t, second_limb.first, compass.pivot)
    testing.expect_value(t, second_limb.second, compass.joint2)
}

// Verify complete tool capacity is checked before any world frontier advances.
@(test)
shapes_test_world_tool_constraint_capacity_failure_is_transactional :: proc(
    t: ^testing.T) {
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    world.constraints.count = shapemodel.MAX_SHAPE_CONSTRAINTS - 4
    before_entities := world.registry.entity_count
    before_constraints := world.constraints.count

    _, status := world_create_pen(world, {
        joint1 = {-1, 0, 0}, joint2 = {1, 0, 0}, length = 2,
        style = world_shape_test_style()})

    testing.expect_value(t, status, shapemodel.Shape_World_Status.Out_Of_Capacity)
    testing.expect_value(t, world.registry.entity_count, before_entities)
    testing.expect_value(t, world.transforms.count, u16(0))
    testing.expect_value(t, world.constraints.count, before_constraints)
}
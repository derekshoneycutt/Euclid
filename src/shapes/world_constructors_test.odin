package shapes

import "core:math"
import "core:testing"

import "../core"

// Return one visible test style with stable scalar values.
world_shape_test_style :: proc() -> Shape_Style {
    return {color = {10, 20, 30, 255}, brush_size = 0.25}
}

// Verify point and line constructors publish only their meaningful components.
@(test)
shapes_test_world_creates_point_and_line_geometry :: proc(t: ^testing.T) {
    world: core.Shape_World
    point, point_status := world_create_point(
        &world, {1, 2, 3}, world_shape_test_style())
    testing.expect_value(t, point_status, core.Shape_World_Status.Ok)
    testing.expect(t, core.shape_component_contains(
        &world.transforms, &world.registry, point.entity))

    line, line_status := world_create_line(
        &world, {4, 5, 6}, {7, 8, 9}, world_shape_test_style())
    testing.expect_value(t, line_status, core.Shape_World_Status.Ok)
    geometry, found := core.shape_component_get(
        &world.geometries, &world.registry, line.shape)
    testing.expect(t, found)
    testing.expect_value(t, geometry.kind, core.Shape_Geometry_Kind.Line)
    testing.expect_value(t, geometry.payload.line.first, line.first)
    testing.expect_value(t, geometry.payload.line.second, line.second)
}

// Verify outlined and filled arcs retain direct center and endpoint identities.
@(test)
shapes_test_world_creates_arc_variants :: proc(t: ^testing.T) {
    world: core.Shape_World
    input := Arc_Input{center = {1, 2, 3}, radius = 2,
        start_theta = 0, end_theta = f32(math.PI), style = world_shape_test_style()}
    arc, arc_status := world_create_arc(&world, input)
    filled, filled_status := world_create_filled_arc(&world, input)
    testing.expect_value(t, arc_status, core.Shape_World_Status.Ok)
    testing.expect_value(t, filled_status, core.Shape_World_Status.Ok)

    arc_geometry, arc_found := core.shape_component_get(
        &world.geometries, &world.registry, arc.shape)
    filled_geometry, filled_found := core.shape_component_get(
        &world.geometries, &world.registry, filled.shape)
    testing.expect(t, arc_found && filled_found)
    testing.expect_value(t, arc_geometry.kind, core.Shape_Geometry_Kind.Arc)
    testing.expect_value(t, filled_geometry.kind, core.Shape_Geometry_Kind.Filled_Arc)
    testing.expect_value(t, arc_geometry.payload.arc.center, arc.center)
    testing.expect_value(t, filled_geometry.payload.arc.finish, filled.finish)
}

// Verify polygon conveniences preserve authored vertex order in the reference pool.
@(test)
shapes_test_world_polygon_conveniences_preserve_order :: proc(t: ^testing.T) {
    world: core.Shape_World
    positions := [5]Vector3{{1, 0, 0}, {2, 0, 0}, {3, 0, 0}, {4, 0, 0}, {5, 0, 0}}
    pentagon, status := world_create_pentagon(
        &world, positions, world_shape_test_style())
    testing.expect_value(t, status, core.Shape_World_Status.Ok)
    geometry, found := core.shape_component_get(
        &world.geometries, &world.registry, pentagon.shape)
    testing.expect(t, found)
    vertices, vertices_found := core.shape_polygon_vertices(
        &world, geometry.payload.polygon)
    testing.expect(t, vertices_found)
    testing.expect_value(t, len(vertices), 5)
    for vertex, index in vertices {
        testing.expect_value(t, vertex, pentagon.vertices[index])
        transform, transform_found := core.shape_component_get(
            &world.transforms, &world.registry, vertex)
        testing.expect(t, transform_found)
        testing.expect_value(t, transform.position, positions[index])
    }
}

// Verify triangle and square conveniences publish the expected polygon spans.
@(test)
shapes_test_world_creates_triangle_and_square :: proc(t: ^testing.T) {
    world: core.Shape_World
    triangle_positions := [3]Vector3{{0, 0, 0}, {1, 0, 0}, {0, 1, 0}}
    square_positions := [4]Vector3{{0, 0, 0}, {1, 0, 0}, {1, 1, 0}, {0, 1, 0}}
    triangle, triangle_status := world_create_triangle(
        &world, triangle_positions, world_shape_test_style())
    square, square_status := world_create_square(
        &world, square_positions, world_shape_test_style())
    testing.expect_value(t, triangle_status, core.Shape_World_Status.Ok)
    testing.expect_value(t, square_status, core.Shape_World_Status.Ok)
    testing.expect(t, core.shape_registry_resolves(&world.registry, triangle.third))
    testing.expect(t, core.shape_registry_resolves(
        &world.registry, square.vertices[3]))
    testing.expect_value(t, world.vertex_references.count, u16(7))
}

// Verify label creation publishes bytes and components as one successful operation.
@(test)
shapes_test_world_creates_unicode_label :: proc(t: ^testing.T) {
    world: core.Shape_World
    label, status := world_create_label(&world, {
        source = "A′", mime = .Text_Plain, position = {1, 2, 3},
        style = world_shape_test_style()})
    testing.expect_value(t, status, core.Shape_World_Status.Ok)
    component, found := core.shape_component_get(
        &world.labels, &world.registry, label.entity)
    testing.expect(t, found)
    source, source_found := core.shape_label_source(&world.label_store, component^)
    testing.expect(t, source_found)
    testing.expect_value(t, source, "A′")
}

// Verify label pool exhaustion rejects before publishing any entity or component.
@(test)
shapes_test_world_label_capacity_failure_is_transactional :: proc(t: ^testing.T) {
    world: core.Shape_World
    world.label_store.byte_count = core.MAX_SHAPE_LABEL_TOTAL_BYTES - 1
    before_entities := world.registry.entity_count
    before_labels := world.labels.count
    before_styles := world.render_styles.count

    _, status := world_create_label(&world, {
        source = "AB", mime = .Text_Plain, style = world_shape_test_style()})
    testing.expect_value(t, status, core.Shape_World_Status.Out_Of_Capacity)
    testing.expect_value(t, world.registry.entity_count, before_entities)
    testing.expect_value(t, world.labels.count, before_labels)
    testing.expect_value(t, world.render_styles.count, before_styles)
    testing.expect_value(t, world.label_store.byte_count,
        u16(core.MAX_SHAPE_LABEL_TOTAL_BYTES - 1))
}

// Verify animation retirement rewinds topology and label source with their components.
@(test)
shapes_test_world_rewinds_polygon_and_label_storage :: proc(t: ^testing.T) {
    world: core.Shape_World
    baseline_positions := [3]Vector3{{0, 0, 0}, {1, 0, 0}, {0, 1, 0}}
    _, baseline_polygon_status := world_create_triangle(
        &world, baseline_positions, world_shape_test_style())
    baseline_label, baseline_label_status := world_create_label(&world, {
        source = "A", mime = .Text_Plain, style = world_shape_test_style()})
    testing.expect_value(t, baseline_polygon_status, core.Shape_World_Status.Ok)
    testing.expect_value(t, baseline_label_status, core.Shape_World_Status.Ok)
    testing.expect_value(t, core.shape_world_freeze_baseline(
        &world), core.Shape_World_Status.Ok)
    positions := [3]Vector3{{0, 0, 0}, {1, 0, 0}, {0, 1, 0}}
    _, polygon_status := world_create_triangle(
        &world, positions, world_shape_test_style())
    _, label_status := world_create_label(&world, {
        source = "α", mime = .Text_Plain, style = world_shape_test_style()})
    testing.expect_value(t, polygon_status, core.Shape_World_Status.Ok)
    testing.expect_value(t, label_status, core.Shape_World_Status.Ok)

    testing.expect_value(t, core.shape_world_rewind_animation(
        &world), core.Shape_World_Status.Ok)
    testing.expect_value(t, world.registry.entity_count, u32(5))
    testing.expect_value(t, world.geometries.count, u16(1))
    testing.expect_value(t, world.labels.count, u16(1))
    testing.expect_value(t, world.vertex_references.count, u16(3))
    testing.expect_value(t, world.label_store.byte_count, u16(1))
    label, found := core.shape_component_get(
        &world.labels, &world.registry, baseline_label.entity)
    testing.expect(t, found)
    source, source_found := core.shape_label_source(&world.label_store, label^)
    testing.expect(t, source_found)
    testing.expect_value(t, source, "A")
}

// Verify capacity rejection occurs before any world frontier changes.
@(test)
shapes_test_world_constructor_capacity_failure_is_transactional :: proc(t: ^testing.T) {
    world: core.Shape_World
    world.registry.entity_count = core.MAX_SHAPE_ENTITIES - 2
    before_registry := world.registry.entity_count
    before_transforms := world.transforms.count
    before_styles := world.render_styles.count
    before_geometry := world.geometries.count

    _, status := world_create_line(
        &world, {1, 2, 3}, {4, 5, 6}, world_shape_test_style())
    testing.expect_value(t, status, core.Shape_World_Status.Out_Of_Capacity)
    testing.expect_value(t, world.registry.entity_count, before_registry)
    testing.expect_value(t, world.transforms.count, before_transforms)
    testing.expect_value(t, world.render_styles.count, before_styles)
    testing.expect_value(t, world.geometries.count, before_geometry)
}
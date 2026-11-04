package shapes

import shapemodel "model"
import "core:math"
import "core:math/linalg"
import "core:testing"

// Populate each analytic evaluator and filled region with a visible complete frontier.
plane_test_populate :: proc(t: ^testing.T, world: ^shapemodel.Shape_World) {
    _, trochoid_status := world_create_trochoid(world, {
        center = {0.4, 0.3, 0},
        fixed_radius = 0.1,
        rolling_radius = 0.05,
        tracer_distance = 0.02,
        rotation = 0.3,
        parameter_finish = 3,
        draw_parameter = 3,
    })
    _, cycloid_status := world_create_cycloid(world, {
        first = {0.1, 0.2, 0},
        second = {0.9, 0.2, 0},
        rolling_radius = 0.05,
        tracer_distance = 0.03,
        parameter_finish = 3,
        draw_parameter = 3,
    })
    _, parabola_status := world_create_parabola(world, {
        vertex = {0.4, 0.4, 0},
        focal_distance = 0.1,
        rotation = 0.2,
        parameter_start = -0.3,
        parameter_finish = 0.3,
        draw_parameter = 0.3,
    })
    _, hyperbola_status := world_create_hyperbola(world, {
        center = {0.5, 0.5, 0},
        semimajor = 0.1,
        semiminor = 0.05,
        rotation = -0.1,
        parameter_start = -0.3,
        parameter_finish = 0.3,
        draw_parameter = 0.3,
    })
    testing.expect_value(t, trochoid_status, shapemodel.Shape_World_Status.Ok)
    testing.expect_value(t, cycloid_status, shapemodel.Shape_World_Status.Ok)
    testing.expect_value(t, parabola_status, shapemodel.Shape_World_Status.Ok)
    testing.expect_value(t, hyperbola_status, shapemodel.Shape_World_Status.Ok)
    region: Circle_Region_Input = {
        first_center = {0.3, 0.5, 0},
        second_center = {0.5, 0.5, 0},
        first_radius = 0.2,
        second_radius = 0.15,
    }
    _, lens_status := world_create_lens(world, region)
    _, lune_status := world_create_lune(world, region)
    testing.expect_value(t, lens_status, shapemodel.Shape_World_Status.Ok)
    testing.expect_value(t, lune_status, shapemodel.Shape_World_Status.Ok)
    for &style in world.render_styles.values[:world.render_styles.count] {
        style.visible = true
    }
}

// Verify all cached analytic samples commute with an off-origin world rigid motion.
@(test)
plane_render_analytic_geometry_is_rigid_equivariant :: proc(t: ^testing.T) {
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    plane_test_populate(t, world)
    build_shape_world_draw_cache(world, 1)
    baseline := new(shapemodel.Shapes_Draw_Cache, context.allocator)
    defer free(baseline, context.allocator)
    baseline^ = world.draw_cache
    q := linalg.quaternion_angle_axis(
        f32(1.7), linalg.normalize(Vector3{1, 2, -3}))
    pivot: Vector3 = {0.2, -0.1, 0.3}
    for &transform in world.transforms.values[:world.transforms.count] {
        transform.position = pivot + linalg.mul(q, transform.position - pivot)
    }
    for &pose in world.orientations.values[:world.orientations.count] {
        pose.orientation = q
    }
    build_shape_world_draw_cache(world, 1)
    testing.expect_value(t, world.draw_cache.item_count, baseline.item_count)
    testing.expect_value(t,
        world.draw_cache.curve_vertex_count, baseline.curve_vertex_count)
    testing.expect_value(t, world.draw_cache.polygon_vertex_count,
        baseline.polygon_vertex_count)
    for point, index in baseline.curve_vertices[:baseline.curve_vertex_count] {
        expected := pivot + linalg.mul(q, point - pivot)
        testing.expect(t, linalg.length(
            world.draw_cache.curve_vertices[index] - expected) < 0.00001)
    }
    for point, index in baseline.polygon_vertices[:baseline.polygon_vertex_count] {
        expected := pivot + linalg.mul(q, point - pivot)
        testing.expect(t, linalg.length(
            world.draw_cache.polygon_vertices[index] - expected) < 0.00001)
    }
    testing.expect_value(t, world.draw_cache.polygon_triangle_count,
        baseline.polygon_triangle_count)
}

// Verify identity initialization and sign-equivalent interpolation survive fixed steps.
@(test)
plane_render_orientation_interpolation_and_endpoint_basis :: proc(t: ^testing.T) {
    world := new(shapemodel.Shape_World, context.allocator)
    defer free(world, context.allocator)
    arc, status := world_create_arc(world, {
        radius = 1,
        sweep_theta = 1,
    })
    testing.expect_value(t, status, shapemodel.Shape_World_Status.Ok)
    testing.expect_value(t,
        world_lerped_orientation(world, arc.shape, 0), quaternion128(1))
    pose, found := shapemodel.shape_component_get_mut(
        &world.orientations, &world.registry, arc.shape)
    testing.expect(t, found)
    pose.orientation = linalg.quaternion_angle_axis(f32(3.14), Vector3{1, 0, 0})
    q := world_lerped_orientation(world, arc.shape, 0.5)
    testing.expect(t, linalg.length(
        linalg.mul(q, Vector3{0, 0, 1}) -
        Vector3{0, -math.sin(f32(1.57)), math.cos(f32(1.57))}) < 0.00001)
    shape_world_update_previous_values(world)
    pose.orientation = -pose.previous_orientation
    testing.expect(t, math.abs(linalg.dot(
        world_lerped_orientation(world, arc.shape, 0.5), pose.orientation)) > 0.99999)
    basis := world_endpoint_plane_basis(
        world, arc.shape, 1, {}, {0, 1, 0})
    testing.expect(t, basis.valid)
    testing.expect(t, math.abs(linalg.dot(basis.tangent, basis.transverse)) < 0.00001)
    testing.expect(t, math.abs(linalg.length(basis.transverse) - 1) < 0.00001)
    testing.expect(t, !world_endpoint_plane_basis(
        world, arc.shape, 0.5, {}, {}).valid)
}

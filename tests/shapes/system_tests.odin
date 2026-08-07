package shapes_tests

import "core:testing"

import app_core "../../src/core"
import "../../src/shapes"
import test_helpers "../helpers"

@(test)
update_last_cache_vectors_snapshots_active_points_only :: proc(t: ^testing.T) {
    system: shapes.Shapes_Point_System
    system.next_point_index = 1

    system.points[0].position = shapes.Vector3{2, 4, 6}

    preserved := shapes.Vector3{9, 9, 9}
    system.points[1].position = shapes.Vector3{3, 3, 3}
    system.points[1].previous_position = preserved

    shapes.update_last_cache_vectors(&system)

    snapshot := system.points[0].previous_position.? or_else shapes.Vector3{}
    test_helpers.expect_vec3_close(t, snapshot, shapes.Vector3{2, 4, 6},
        "active points should snapshot current position")

    untouched := system.points[1].previous_position.? or_else shapes.Vector3{}
    test_helpers.expect_vec3_close(t, untouched, preserved,
        "points past next_point_index should remain untouched")
}

@(test)
lerped_point_position_uses_previous_position_when_present :: proc(t: ^testing.T) {
    system: shapes.Shapes_Point_System
    system.points[0].position = shapes.Vector3{10, 0, 0}
    system.points[0].previous_position = shapes.Vector3{2, 0, 0}

    point, ok := shapes.lerped_point_position(&system, 0, 0.25)

    testing.expect(t, ok)
    test_helpers.expect_vec3_close(t, point, shapes.Vector3{4, 0, 0},
        "lerped_point_position should blend previous and current")
}

@(test)
lerped_point_position_falls_back_to_current_without_previous :: proc(t: ^testing.T) {
    system: shapes.Shapes_Point_System
    system.points[0].position = shapes.Vector3{7, -1, 3}

    point, ok := shapes.lerped_point_position(&system, 0, 0.5)

    testing.expect(t, ok)
    test_helpers.expect_vec3_close(t, point, shapes.Vector3{7, -1, 3},
        "lerped_point_position should fall back when previous_position is missing")
}

@(test)
lerped_child_positions_follows_child_chain_order :: proc(t: ^testing.T) {
    system: shapes.Shapes_Point_System
    host := shapes.Shapes_Point{child_point_head = 1}

    system.points[1].position = shapes.Vector3{1, 0, 0}
    system.points[1].previous_position = shapes.Vector3{0, 0, 0}
    system.points[1].next_child_point = 2

    system.points[2].position = shapes.Vector3{3, 0, 0}
    system.points[2].previous_position = shapes.Vector3{1, 0, 0}
    system.points[2].next_child_point = 3

    system.points[3].position = shapes.Vector3{5, 0, 0}
    system.points[3].previous_position = shapes.Vector3{3, 0, 0}

    out: [3]shapes.Vector3
    ok := shapes.lerped_child_positions(&system, &host, 0.5, out[:])

    testing.expect(t, ok)
    test_helpers.expect_vec3_close(t, out[0], shapes.Vector3{0.5, 0, 0}, "child 0 should lerp")
    test_helpers.expect_vec3_close(t, out[1], shapes.Vector3{2, 0, 0}, "child 1 should lerp")
    test_helpers.expect_vec3_close(t, out[2], shapes.Vector3{4, 0, 0}, "child 2 should lerp")
}

@(test)
draw_cache_next_item_slot_updates_count_and_capacity :: proc(t: ^testing.T) {
    system: shapes.Shapes_Point_System

    _, ok := shapes.draw_cache_next_item_slot(&system)
    testing.expect(t, ok)
    testing.expect_value(t, system.draw_cache.item_count, 1)

    system.draw_cache.item_count = len(system.draw_cache.items)
    _, has_slot := shapes.draw_cache_next_item_slot(&system)

    testing.expect(t, !has_slot)
    testing.expect_value(t, system.draw_cache.item_count, len(system.draw_cache.items))
}

@(test)
lerped_child_positions_returns_false_for_invalid_chain :: proc(t: ^testing.T) {
    system: shapes.Shapes_Point_System
    host := shapes.Shapes_Point{child_point_head = 12}

    out: [2]shapes.Vector3
    ok := shapes.lerped_child_positions(&system, &host, 0.5, out[:])

    testing.expect(t, !ok)
}

@(test)
draw_cache_reserve_polygon_indices_tracks_capacity :: proc(t: ^testing.T) {
    system: shapes.Shapes_Point_System

    first, ok := shapes.draw_cache_reserve_polygon_vertices(&system, 2)
    testing.expect(t, ok)
    testing.expect_value(t, first, 0)
    testing.expect_value(t, system.draw_cache.polygon_vertex_count, 2)

    second, ok2 := shapes.draw_cache_reserve_polygon_vertices(&system, len(system.draw_cache.polygon_vertices))
    testing.expect(t, !ok2)
    testing.expect_value(t, second, 0)
}

@(test)
polygon_area_and_point_in_triangle_handle_orientation_and_edges :: proc(t: ^testing.T) {
    vertices := [3]shapes.Vector3{{0, 0, 0}, {2, 0, 0}, {1, 2, 0}}
    testing.expect(t, shapes.polygon_signed_area_xy(vertices[:]) > 0)
    testing.expect(t, shapes.point_in_triangle_xy({1, 1, 0}, vertices[0], vertices[1], vertices[2]))
    testing.expect(t, shapes.point_in_triangle_xy({0, 0, 0}, vertices[0], vertices[1], vertices[2]))
}

@(test)
clear_animation_data_clears_animation_owned_slots :: proc(t: ^testing.T) {
    system: shapes.Shapes_Point_System
    particle_system := new(app_core.Particle_System)
    defer free(particle_system)

    particle_system^.use_max_dust_particles = 2
    system.next_point_index = 2
    system.next_constraint_index = 1
    system.anim_points_start = 1
    system.anim_constraints_start = 0
    system.points[0].do_draw = true
    system.points[1].do_draw = true
    system.constraints[0].do_apply = true

    shapes.clear_animation_data(&system, particle_system)

    testing.expect_value(t, system.next_point_index, 1)
    testing.expect_value(t, system.next_constraint_index, 0)
    testing.expect(t, !system.points[1].do_draw)
    testing.expect(t, !system.constraints[0].do_apply)
}

expect_polygon_triangle_indices_in_range :: proc(
    t: ^testing.T,
    triangles: []shapes.Shapes_Polygon_Triangle,
    first_vertex, vertex_count: int,
    msg: string) {

    max_index := first_vertex + vertex_count
    for tri in triangles {
        testing.expectf(t, tri.a >= first_vertex && tri.a < max_index,
            "%s (a) | idx=%v range=[%v,%v)", msg, tri.a, first_vertex, max_index)
        testing.expectf(t, tri.b >= first_vertex && tri.b < max_index,
            "%s (b) | idx=%v range=[%v,%v)", msg, tri.b, first_vertex, max_index)
        testing.expectf(t, tri.c >= first_vertex && tri.c < max_index,
            "%s (c) | idx=%v range=[%v,%v)", msg, tri.c, first_vertex, max_index)
    }
}

seed_polygon_host :: proc(
    system: ^shapes.Shapes_Point_System,
    kind: shapes.Shapes_Point_Type,
    points: []shapes.Vector3) {

    if len(points) < 3 {
        return
    }

    host := shapes.Shapes_Point{
        kind = kind,
        child_count = len(points),
        child_point_head = 1,
        do_draw = true,
    }
    system.points[0] = host

    for i in 0..<len(points) {
        child_id := i + 1
        child := shapes.Shapes_Point{
            kind = .Point,
            position = points[i],
        }
        if i + 1 < len(points) {
            child.next_child_point = child_id + 1
        }
        system.points[child_id] = child
    }

    system.next_point_index = len(points) + 1
}

@(test)
triangulate_polygon_ear_clip_convex_hexagon_emits_n_minus_2 :: proc(t: ^testing.T) {
    system: shapes.Shapes_Point_System
    vertices := [6]shapes.Vector3{
        {0, 0, 0},
        {2, 0, 0},
        {3, 1, 0},
        {2, 2, 0},
        {0, 2, 0},
        {-1, 1, 0},
    }

    triangle_count := shapes.triangulate_polygon_ear_clip(&system, 0, vertices[:], 0)

    testing.expect_value(t, triangle_count, 4)
    tris := system.draw_cache.polygon_triangles[:triangle_count]
    expect_polygon_triangle_indices_in_range(t, tris, 0, len(vertices),
        "convex hexagon triangles should index local vertex range")
}

@(test)
triangulate_polygon_ear_clip_clockwise_hexagon_emits_n_minus_2 :: proc(t: ^testing.T) {
    system: shapes.Shapes_Point_System
    vertices := [6]shapes.Vector3{
        {-1, 1, 0},
        {0, 2, 0},
        {2, 2, 0},
        {3, 1, 0},
        {2, 0, 0},
        {0, 0, 0},
    }

    triangle_count := shapes.triangulate_polygon_ear_clip(&system, 0, vertices[:], 0)

    testing.expect_value(t, triangle_count, 4)
    tris := system.draw_cache.polygon_triangles[:triangle_count]
    expect_polygon_triangle_indices_in_range(t, tris, 0, len(vertices),
        "clockwise hexagon should still triangulate within vertex range")
}

@(test)
triangulate_polygon_ear_clip_collinear_uses_fallback_fan :: proc(t: ^testing.T) {
    system: shapes.Shapes_Point_System
    vertices := [5]shapes.Vector3{
        {0, 0, 0},
        {1, 0, 0},
        {2, 0, 0},
        {3, 0, 0},
        {4, 0, 0},
    }

    triangle_count := shapes.triangulate_polygon_ear_clip(&system, 0, vertices[:], 0)

    testing.expect_value(t, triangle_count, 3)
    tris := system.draw_cache.polygon_triangles[:triangle_count]
    expect_polygon_triangle_indices_in_range(t, tris, 0, len(vertices),
        "degenerate polygon fallback should still use valid vertex indices")
}

@(test)
draw_cache_reset_clears_polygon_pool_counters :: proc(t: ^testing.T) {
    system: shapes.Shapes_Point_System
    system.draw_cache.item_count = 5
    system.draw_cache.polygon_vertex_count = 7
    system.draw_cache.polygon_triangle_count = 9
    system.draw_cache.draw_pen = true
    system.draw_cache.draw_compass = true

    shapes.draw_cache_reset(&system)

    testing.expect_value(t, system.draw_cache.item_count, 0)
    testing.expect_value(t, system.draw_cache.polygon_vertex_count, 0)
    testing.expect_value(t, system.draw_cache.polygon_triangle_count, 0)
    testing.expect(t, !system.draw_cache.draw_pen)
    testing.expect(t, !system.draw_cache.draw_compass)
}

@(test)
build_draw_cache_routes_triangle_kind_to_polygon_cache :: proc(t: ^testing.T) {
    system: shapes.Shapes_Point_System
    points := [4]shapes.Vector3{
        {0, 0, 0},
        {2, 0, 0},
        {2, 1, 0},
        {0, 1, 0},
    }
    seed_polygon_host(&system, .Triangle, points[:])

    shapes.build_draw_cache(&system, 1.0)

    testing.expect_value(t, system.draw_cache.item_count, 1)
    testing.expect_value(t, system.draw_cache.polygon_vertex_count, 4)
    testing.expect_value(t, system.draw_cache.polygon_triangle_count, 2)
}

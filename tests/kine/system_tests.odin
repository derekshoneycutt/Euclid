package kine_tests

import "core:testing"

import app_kine "../../src/kine"

@(test)
kine_update_last_cache_vectors_snapshots_active_points_only :: proc(t: ^testing.T) {
    system: app_kine.Kine_Point_System
    system.next_point_index = 1

    system.points[0].position = app_kine.Vector3{2, 4, 6}

    preserved := app_kine.Vector3{9, 9, 9}
    system.points[1].position = app_kine.Vector3{3, 3, 3}
    system.points[1].previous_position = preserved

    app_kine.kine_update_last_cache_vectors(&system)

    snapshot := system.points[0].previous_position.? or_else app_kine.Vector3{}
    expect_vec3_close(t, snapshot, app_kine.Vector3{2, 4, 6},
        "active points should snapshot current position")

    untouched := system.points[1].previous_position.? or_else app_kine.Vector3{}
    expect_vec3_close(t, untouched, preserved,
        "points past next_point_index should remain untouched")
}

@(test)
lerped_point_position_uses_previous_position_when_present :: proc(t: ^testing.T) {
    system: app_kine.Kine_Point_System
    system.points[0].position = app_kine.Vector3{10, 0, 0}
    system.points[0].previous_position = app_kine.Vector3{2, 0, 0}

    point, ok := app_kine.lerped_point_position(&system, 0, 0.25)

    testing.expect(t, ok)
    expect_vec3_close(t, point, app_kine.Vector3{4, 0, 0},
        "lerped_point_position should blend previous and current")
}

@(test)
lerped_point_position_falls_back_to_current_without_previous :: proc(t: ^testing.T) {
    system: app_kine.Kine_Point_System
    system.points[0].position = app_kine.Vector3{7, -1, 3}

    point, ok := app_kine.lerped_point_position(&system, 0, 0.5)

    testing.expect(t, ok)
    expect_vec3_close(t, point, app_kine.Vector3{7, -1, 3},
        "lerped_point_position should fall back when previous_position is missing")
}

@(test)
lerped_child_positions_follows_child_chain_order :: proc(t: ^testing.T) {
    system: app_kine.Kine_Point_System
    host := app_kine.Kine_Shape_Point{child_point_head = 1}

    system.points[1].position = app_kine.Vector3{1, 0, 0}
    system.points[1].previous_position = app_kine.Vector3{0, 0, 0}
    system.points[1].next_child_point = 2

    system.points[2].position = app_kine.Vector3{3, 0, 0}
    system.points[2].previous_position = app_kine.Vector3{1, 0, 0}
    system.points[2].next_child_point = 3

    system.points[3].position = app_kine.Vector3{5, 0, 0}
    system.points[3].previous_position = app_kine.Vector3{3, 0, 0}

    out: [3]app_kine.Vector3
    ok := app_kine.lerped_child_positions(&system, &host, 0.5, out[:])

    testing.expect(t, ok)
    expect_vec3_close(t, out[0], app_kine.Vector3{0.5, 0, 0}, "child 0 should lerp")
    expect_vec3_close(t, out[1], app_kine.Vector3{2, 0, 0}, "child 1 should lerp")
    expect_vec3_close(t, out[2], app_kine.Vector3{4, 0, 0}, "child 2 should lerp")
}

@(test)
draw_cache_next_item_slot_updates_count_and_capacity :: proc(t: ^testing.T) {
    system: app_kine.Kine_Point_System

    _, ok := app_kine.draw_cache_next_item_slot(&system)
    testing.expect(t, ok)
    testing.expect_value(t, system.draw_cache.item_count, 1)

    system.draw_cache.item_count = len(system.draw_cache.items)
    _, has_slot := app_kine.draw_cache_next_item_slot(&system)

    testing.expect(t, !has_slot)
    testing.expect_value(t, system.draw_cache.item_count, len(system.draw_cache.items))
}

expect_polygon_triangle_indices_in_range :: proc(
    t: ^testing.T,
    triangles: []app_kine.Kine_Polygon_Triangle,
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
    system: ^app_kine.Kine_Point_System,
    kind: app_kine.Kine_Shape_Point_Type,
    points: []app_kine.Vector3) {

    if len(points) < 3 {
        return
    }

    host := app_kine.Kine_Shape_Point{
        kind = kind,
        child_count = len(points),
        child_point_head = 1,
        do_draw = true,
    }
    system.points[0] = host

    for i in 0..<len(points) {
        child_id := i + 1
        child := app_kine.Kine_Shape_Point{
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
    system: app_kine.Kine_Point_System
    vertices := [6]app_kine.Vector3{
        {0, 0, 0},
        {2, 0, 0},
        {3, 1, 0},
        {2, 2, 0},
        {0, 2, 0},
        {-1, 1, 0},
    }

    triangle_count := app_kine.triangulate_polygon_ear_clip(&system, 0, vertices[:], 0)

    testing.expect_value(t, triangle_count, 4)
    tris := system.draw_cache.polygon_triangles[:triangle_count]
    expect_polygon_triangle_indices_in_range(t, tris, 0, len(vertices),
        "convex hexagon triangles should index local vertex range")
}

@(test)
triangulate_polygon_ear_clip_clockwise_hexagon_emits_n_minus_2 :: proc(t: ^testing.T) {
    system: app_kine.Kine_Point_System
    vertices := [6]app_kine.Vector3{
        {-1, 1, 0},
        {0, 2, 0},
        {2, 2, 0},
        {3, 1, 0},
        {2, 0, 0},
        {0, 0, 0},
    }

    triangle_count := app_kine.triangulate_polygon_ear_clip(&system, 0, vertices[:], 0)

    testing.expect_value(t, triangle_count, 4)
    tris := system.draw_cache.polygon_triangles[:triangle_count]
    expect_polygon_triangle_indices_in_range(t, tris, 0, len(vertices),
        "clockwise hexagon should still triangulate within vertex range")
}

@(test)
triangulate_polygon_ear_clip_collinear_uses_fallback_fan :: proc(t: ^testing.T) {
    system: app_kine.Kine_Point_System
    vertices := [5]app_kine.Vector3{
        {0, 0, 0},
        {1, 0, 0},
        {2, 0, 0},
        {3, 0, 0},
        {4, 0, 0},
    }

    triangle_count := app_kine.triangulate_polygon_ear_clip(&system, 0, vertices[:], 0)

    testing.expect_value(t, triangle_count, 3)
    tris := system.draw_cache.polygon_triangles[:triangle_count]
    expect_polygon_triangle_indices_in_range(t, tris, 0, len(vertices),
        "degenerate polygon fallback should still use valid vertex indices")
}

@(test)
kine_draw_cache_reset_clears_polygon_pool_counters :: proc(t: ^testing.T) {
    system: app_kine.Kine_Point_System
    system.draw_cache.item_count = 5
    system.draw_cache.polygon_vertex_count = 7
    system.draw_cache.polygon_triangle_count = 9
    system.draw_cache.draw_pen = true
    system.draw_cache.draw_compass = true

    app_kine.kine_draw_cache_reset(&system)

    testing.expect_value(t, system.draw_cache.item_count, 0)
    testing.expect_value(t, system.draw_cache.polygon_vertex_count, 0)
    testing.expect_value(t, system.draw_cache.polygon_triangle_count, 0)
    testing.expect(t, !system.draw_cache.draw_pen)
    testing.expect(t, !system.draw_cache.draw_compass)
}

@(test)
build_kine_draw_cache_routes_triangle_kind_to_polygon_cache :: proc(t: ^testing.T) {
    system: app_kine.Kine_Point_System
    points := [4]app_kine.Vector3{
        {0, 0, 0},
        {2, 0, 0},
        {2, 1, 0},
        {0, 1, 0},
    }
    seed_polygon_host(&system, .Triangle, points[:])

    app_kine.build_kine_draw_cache(&system, 1.0)

    testing.expect_value(t, system.draw_cache.item_count, 1)
    testing.expect_value(t, system.draw_cache.polygon_vertex_count, 4)
    testing.expect_value(t, system.draw_cache.polygon_triangle_count, 2)
}

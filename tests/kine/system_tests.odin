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

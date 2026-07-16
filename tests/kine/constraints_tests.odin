package kine_tests

import "core:math"
import "core:math/linalg"
import "core:testing"

import app_kine "../../src/kine"

TEST_EPSILON :: f32(1e-4)

expect_close :: proc(t: ^testing.T, actual, expected: f32, msg: string) {
    testing.expectf(t, math.abs(actual - expected) <= TEST_EPSILON,
        "%s | expected=%v got=%v", msg, expected, actual)
}

expect_vec3_close :: proc(
    t: ^testing.T,
    actual, expected: app_kine.Vector3,
    msg: string,
) {
    testing.expectf(t, math.abs(actual.x - expected.x) <= TEST_EPSILON,
        "%s (x) | expected=%v got=%v", msg, expected.x, actual.x)
    testing.expectf(t, math.abs(actual.y - expected.y) <= TEST_EPSILON,
        "%s (y) | expected=%v got=%v", msg, expected.y, actual.y)
    testing.expectf(t, math.abs(actual.z - expected.z) <= TEST_EPSILON,
        "%s (z) | expected=%v got=%v", msg, expected.z, actual.z)
}

make_point :: proc(x, y, z: f32) -> app_kine.Kine_Shape_Point {
    return app_kine.Kine_Shape_Point{position = app_kine.Vector3{x, y, z}}
}

make_distance_constraint :: proc(depend_on: i32, req_len: f32) -> app_kine.Kine_Constraint {
    return app_kine.Kine_Constraint{
        kind = .Distance,
        do_apply = true,
        depend_on = depend_on,
        restriction = app_kine.Vector3{req_len, 0, 0},
    }
}

@(test)
rotate_around_axis_preserves_length :: proc(t: ^testing.T) {
    axis := linalg.normalize(app_kine.Vector3{0, 0, 1})
    input := app_kine.Vector3{3, 4, 0}
    output := app_kine.rotate_around_axis(input, axis, math.PI / 2)

    input_len := linalg.length(input)
    output_len := linalg.length(output)

    expect_close(t, output_len, input_len, "rotate_around_axis must preserve vector length")
    expect_vec3_close(t, output, app_kine.Vector3{-4, 3, 0}, "rotation around +Z by 90 degrees")
}

@(test)
apply_constraint_distance_depend_on_positive_moves_point1 :: proc(t: ^testing.T) {
    p1 := make_point(0, 0, 0)
    p2 := make_point(1, 0, 0)
    constraint := make_distance_constraint(1, 3)

    app_kine.apply_constraint_distance(&constraint, &p1, &p2)

    expected_p1 := app_kine.Vector3{-2, 0, 0}
    expect_vec3_close(t, p1.position.? or_else app_kine.Vector3{}, expected_p1,
        "depend_on>0 should move point1 only")
    expect_vec3_close(t, p2.position.? or_else app_kine.Vector3{}, app_kine.Vector3{1, 0, 0},
        "depend_on>0 should keep point2 fixed")
}

@(test)
apply_constraint_distance_depend_on_zero_splits_motion :: proc(t: ^testing.T) {
    p1 := make_point(-1, 0, 0)
    p2 := make_point(1, 0, 0)
    constraint := make_distance_constraint(0, 6)

    app_kine.apply_constraint_distance(&constraint, &p1, &p2)

    expect_vec3_close(t, p1.position.? or_else app_kine.Vector3{}, app_kine.Vector3{-3, 0, 0},
        "depend_on==0 should move point1 around midpoint")
    expect_vec3_close(t, p2.position.? or_else app_kine.Vector3{}, app_kine.Vector3{3, 0, 0},
        "depend_on==0 should move point2 around midpoint")
}

@(test)
apply_constraint_distance_depend_on_negative_moves_point2 :: proc(t: ^testing.T) {
    p1 := make_point(0, 0, 0)
    p2 := make_point(1, 0, 0)
    constraint := make_distance_constraint(-1, 4)

    app_kine.apply_constraint_distance(&constraint, &p1, &p2)

    expect_vec3_close(t, p1.position.? or_else app_kine.Vector3{}, app_kine.Vector3{0, 0, 0},
        "depend_on<0 should keep point1 fixed")
    expect_vec3_close(t, p2.position.? or_else app_kine.Vector3{}, app_kine.Vector3{4, 0, 0},
        "depend_on<0 should move point2 only")
}

@(test)
resolve_constraint_targets_supports_child_offset :: proc(t: ^testing.T) {
    points: [app_kine.MAX_KINEPOINTS]app_kine.Kine_Shape_Point

    points[0] = app_kine.Kine_Shape_Point{
        child_point_head = 1,
        child_count = 3,
    }

    points[1] = app_kine.Kine_Shape_Point{next_child_point = 2}
    points[2] = app_kine.Kine_Shape_Point{next_child_point = 3}
    points[3] = app_kine.Kine_Shape_Point{}

    constraint := app_kine.Kine_Constraint{
        kind = .Distance,
        on_point = 0,
        child_offset = 1,
        do_apply = true,
    }

    targets, ok := app_kine.resolve_constraint_targets(&constraint, &points)

    testing.expect(t, ok)
    testing.expect_value(t, targets.child_count, 2)
    testing.expect_value(t, targets.host, &points[0])
    testing.expect_value(t, targets.children[0], &points[2])
    testing.expect_value(t, targets.children[1], &points[3])
}

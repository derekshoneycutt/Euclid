package geometry

import "core:math/linalg"
import "core:testing"

// Verify Euclid vectors retain native arithmetic and linalg compatibility.
@(test)
geometry_vectors_support_math :: proc(t: ^testing.T) {
    first := Vector3{1, 2, 3}
    second := Vector3{4, 6, 8}
    testing.expect_value(t, first + second, Vector3{5, 8, 11})
    testing.expect_value(t, (second - first) * 0.5, Vector3{1.5, 2, 2.5})
    testing.expect_value(t, linalg.dot(first, second), f32(40))
    testing.expect_value(t,
        linalg.cross(Vector3{1, 0, 0}, Vector3{0, 1, 0}),
        Vector3{0, 0, 1})
}

// Verify rectangle edge and visible-overlap semantics.
@(test)
geometry_rectangles_preserve_boundaries :: proc(t: ^testing.T) {
    rectangle := Rectangle{10, 20, 30, 40}
    testing.expect(t, rectangle_contains(rectangle, {10, 20}))
    testing.expect(t, rectangle_contains(rectangle, {40, 60}))
    testing.expect(t, !rectangle_contains(rectangle, {40.01, 60}))
    testing.expect(t, rectangles_intersect(rectangle, {39, 59, 2, 2}))
    testing.expect(t, !rectangles_intersect(rectangle, {40, 20, 1, 1}))
    testing.expect(t, !rectangles_intersect(rectangle, {10, 20, 0, 1}))
}
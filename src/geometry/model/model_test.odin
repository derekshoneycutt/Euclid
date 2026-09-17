package geometry_model

import "core:testing"

// Verify vectors retain component arithmetic and named coordinate access.
@(test)
geometry_vectors_preserve_numeric_contract :: proc(t: ^testing.T) {
    first := Vector3{1, 2, 3}
    second := Vector3{4, 5, 6}
    testing.expect_value(t, first + second, Vector3{5, 7, 9})
    testing.expect_value(t, first.x, f32(1))
}

// Verify rectangle containment uses half-open maximum edges.
@(test)
geometry_rectangle_contains_half_open_extent :: proc(t: ^testing.T) {
    rect := Rectangle{10, 20, 30, 40}
    testing.expect(t, rectangle_contains(rect, {10, 20}))
    testing.expect(t, rectangle_contains(rect, {39.999, 59.999}))
    testing.expect(t, !rectangle_contains(rect, {40, 60}))
}
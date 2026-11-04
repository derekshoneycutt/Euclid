package world

import geometry "../../core/geometry"
import shapemodel "../../shapes/model"
import "core:math"
import "core:math/linalg"
import "core:testing"

// Measure a clipped polygon's oriented area vector without projection.
split_test_area :: proc(vertices: []geometry.Vector3) -> geometry.Vector3 {
    result: geometry.Vector3
    for index in 1..<len(vertices) - 1 {
        result += linalg.cross(
            vertices[index] - vertices[0], vertices[index + 1] - vertices[0]) * 0.5
    }
    return result
}

// Verify both halves conserve area and winding with bounded, plane-valid vertices.
@(test)
surface_split_triangle_conserves_oriented_area :: proc(t: ^testing.T) {
    cases := [?][3]f32{{1, -1, -1}, {-1, 1, 1}, {0, 1, -1},
        {0, 0, 0}, {0.00001, -0.00001, 0}, {1, 1, 1}, {-1, -1, -1}}
    halves := [?]bool{true, false}
    for heights in cases {
        triangle := [?]geometry.Vector3{
            {0, 0, heights[0]}, {1, 0, heights[1]}, {0, 1, heights[2]}}
        total: geometry.Vector3
        expected := split_test_area(triangle[:])
        for keep_above in halves {
            clipped: [4]geometry.Vector3
            count := surface_split_triangle(
                triangle[0], triangle[1], triangle[2], keep_above, &clipped)
            testing.expect(t, count >= 0 && count <= 4)
            area := split_test_area(clipped[:count])
            total += area
            testing.expect(t, linalg.dot(area, expected) >= 0)
            for point in clipped[:count] {
                if keep_above {
                    testing.expect(t, point.z >= -Z_SPLIT_EPSILON)
                } else {
                    testing.expect(t, point.z <= Z_SPLIT_EPSILON)
                }
            }
        }
        testing.expect(t, linalg.length(total - expected) < 0.00001)
    }
}

// Verify a tilted analytic circle keeps both crossing runs and bounded chord error.
@(test)
surface_split_tilted_circle_preserves_both_halves :: proc(t: ^testing.T) {
    sine := math.sqrt(f32(0.5))
    circle := circle_arc_geometry({0.5, 0.5, 0.03}, 0.2, 0.17,
        2 * math.PI, quaternion(x = sine, y = f32(0), z = f32(0), w = sine))
    points: [CIRCLE_ARC_SEGMENTS + 1]geometry.Vector3
    circle_arc_sample_world(&circle, points[:])
    kinds: [CIRCLE_ARC_SEGMENTS + 1]shapemodel.Curve_Point_Kind
    halves := [?]bool{true, false}
    for keep_above in halves {
        projected: [MAX_CURVE_VISIBLE_POINTS]geometry.Vector2
        projected_kinds: [MAX_CURVE_VISIBLE_POINTS]shapemodel.Curve_Point_Kind
        runs: [MAX_CURVE_VISIBLE_RUNS]Curve_Visible_Run
        buffers: Curve_Visible_Run_Buffers = {projected[:], projected_kinds[:], runs[:]}
        result := build_projected_curve_visible_runs(
            {{}, points[:], kinds[:], .Closed, keep_above, false}, buffers)
        testing.expect(t, result.ok && result.run_count > 0 && result.point_count > 2)
    }
    crossings := 0
    for index in 1..<len(points) {
        first, second := points[index - 1], points[index]
        if z_split_sign(first.z) * z_split_sign(second.z) < 0 {
            intersection := z_split_intersection_with_plane(first, second)
            radial := intersection - circle.center
            testing.expect(t, math.abs(linalg.length(radial) - circle.radius) <
                circle.radius * (1 - math.cos(f32(math.PI / CIRCLE_ARC_SEGMENTS))) +
                0.000001)
            crossings += 1
        }
    }
    testing.expect_value(t, crossings, 2)
}

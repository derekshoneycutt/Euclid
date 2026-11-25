package modifier

import geometry "../core/geometry"
import testing "core:testing"
import math "core:math"

// Preserve ordered edges and interpolate the active segment in native time.
@(test)
polygon_trace_samples_ordered_edges :: proc(t: ^testing.T) {
    trace: Polygon_Trace = {
        count = 3,
    }
    trace.vertices[0] = {
        entity = 11,
        position = {0, 0, 0},
    }
    trace.vertices[1] = {
        entity = 12,
        position = {1, 0, 0},
    }
    trace.vertices[2] = {
        entity = 13,
        position = {1, 1, 0},
    }
    template: Modifier_Request = {
        duration = 1,
        radius = 0.14,
        color_packed = 0x123456ff,
    }
    edge_elapsed := f32(POLYGON_TRACE_DESCEND_SHARE) +
        f32(POLYGON_TRACE_DRAW_SHARE) / 3 * 1.5
    sample := polygon_trace_motion_request(template, trace, edge_elapsed)
    pose := pen_motion_pose(sample)
    testing.expect_value(t, sample.kind, Modifier_Kind.Pen_Drag)
    testing.expect_value(t, sample.start_position, geometry.Vector3{1, 0, 0})
    testing.expect(t, math.abs(pose.start_position.y - f32(0.5)) < 1e-6)
    testing.expect(t, math.abs(sample.scalar - f32(math.PI / 2)) < 1e-6)
}

// Keep tool contact at the final vertex through reveal and raise it afterward.
@(test)
polygon_trace_holds_final_edge_then_rises :: proc(t: ^testing.T) {
    trace: Polygon_Trace = {
        count = 3,
    }
    trace.vertices[0] = {
        entity = 11,
        position = {0, 0, 0},
    }
    trace.vertices[1] = {
        entity = 12,
        position = {1, 0, 0},
    }
    trace.vertices[2] = {
        entity = 13,
        position = {1, 1, 0},
    }
    template: Modifier_Request = {
        duration = 2,
        radius = 0.14,
    }
    held := polygon_trace_motion_request(template, trace, 1.5)
    testing.expect_value(t, held.kind, Modifier_Kind.Pen_Drag)
    testing.expect_value(t, held.start_position, geometry.Vector3{1, 1, 0})
    testing.expect_value(t, held.second_position, geometry.Vector3{0, 0, 0})
    risen := polygon_trace_motion_request(template, trace, 1.9)
    testing.expect_value(t, risen.kind, Modifier_Kind.Pen_Rise)
    testing.expect_value(t, risen.start_position, geometry.Vector3{1, 1, 0})
    testing.expect(t, math.abs(risen.elapsed - f32(0.2)) < 1e-6)
}

// Reveal bookkeeping changes only on the accepted sample crossing its boundary.
@(test)
polygon_trace_reveal_boundary_is_crossed_once :: proc(t: ^testing.T) {
    testing.expect(t, !polygon_trace_reveal_due(0, 0.69, 1))
    testing.expect(t, !polygon_trace_reveal_due(0.70, 0.71, 1))
    testing.expect(t, polygon_trace_reveal_due(0.69, 0.71, 1))
    testing.expect(t, polygon_trace_reveal_due(0, 2, 2))
}

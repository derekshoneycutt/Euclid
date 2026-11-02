package curve

import shapemodel "../model"
import test_helpers "../../test_helpers"

import "core:math"
import "core:testing"

// Measure planar distance between two world-space construction points.
conic_test_distance :: proc(first, second: Vector3) -> f32 {
    delta := first - second
    return math.sqrt(delta.x * delta.x + delta.y * delta.y)
}

// Verify the parabola evaluator satisfies its focus-directrix definition.
@(test)
parabola_curve_matches_focus_directrix_distance :: proc(t: ^testing.T) {
    center: Vector3 = {0.3, 0.4, 0}
    value: shapemodel.Shape_Parabola = {
        focal_distance = 0.075,
        rotation = 0.37,
        parameter_start = -1.6,
        parameter_finish = 1.6,
        draw_parameter = 0.8,
    }
    point := parabola_point(center, value, value.draw_parameter)
    focus := center + rotate_planar({value.focal_distance, 0, 0}, value.rotation)
    directrix := center + rotate_planar(
        {-value.focal_distance, 2 * value.focal_distance * value.draw_parameter, 0},
        value.rotation)

    testing.expectf(t,
        math.abs(conic_test_distance(point, focus) -
        conic_test_distance(point, directrix)) < 1e-5,
        "parabola point should be equidistant from focus and directrix")
}

// Verify every edge of the parabola instrument's linkage has its authored length.
@(test)
parabola_tool_pose_preserves_equal_link_lengths :: proc(t: ^testing.T) {
    center: Vector3 = {0.37, 0.5, 0}
    value: shapemodel.Shape_Parabola_Tool = {
        focal_distance = 0.075,
        link_length = 0.16,
        rotation = 0.42,
        parameter_start = -1.6,
        parameter_finish = 1.6,
        parameter = 0.9,
    }
    pose := parabola_tool_pose(center, value)
    length := value.link_length

    testing.expectf(t, math.abs(conic_test_distance(
        pose.directrix_contact, pose.diamond_first) - length) < 1e-5,
        "first directrix-side link should preserve its length")
    testing.expectf(t, math.abs(conic_test_distance(
        pose.diamond_first, pose.focus) - length) < 1e-5,
        "first focus-side link should preserve its length")
    testing.expectf(t, math.abs(conic_test_distance(
        pose.focus, pose.diamond_second) - length) < 1e-5,
        "second focus-side link should preserve its length")
    testing.expectf(t, math.abs(conic_test_distance(
        pose.diamond_second, pose.directrix_contact) - length) < 1e-5,
        "second directrix-side link should preserve its length")
    test_helpers.expect_vec3_close(t, pose.vertex,
        parabola_point(center, {
            focal_distance = value.focal_distance,
            rotation = value.rotation,
            parameter_start = value.parameter_start,
            parameter_finish = value.parameter_finish,
            draw_parameter = value.parameter,
        }, value.parameter),
        "tool nib should agree with the exact analytic parabola point")
}

// Verify the negative hyperbola branch is the central reflection of the positive branch.
@(test)
hyperbola_branches_are_centrally_symmetric :: proc(t: ^testing.T) {
    center: Vector3 = {0.5, 0.5, 0}
    positive: shapemodel.Shape_Hyperbola_Branch = {
        branch = 1,
        semimajor = 0.12,
        semiminor = 0.1,
        rotation = 0.53,
        parameter_start = -1.35,
        parameter_finish = 1.35,
        draw_parameter = 0.7,
    }
    negative := positive
    negative.branch = -1

    positive_point := hyperbola_point(center, positive, positive.draw_parameter)
    negative_point := hyperbola_point(center, negative, negative.draw_parameter)
    test_helpers.expect_vec3_close(t, negative_point, center + center - positive_point,
        "negative branch should be a central reflection of the positive branch")
}

// Verify the hyperbola instrument's carriages and ticks remain symmetric.
@(test)
hyperbola_tool_pose_keeps_symmetric_carriages_and_ticks :: proc(t: ^testing.T) {
    center: Vector3 = {0.5, 0.5, 0}
    value: shapemodel.Shape_Hyperbola_Tool = {
        semimajor = 0.12,
        semiminor = 0.1,
        rotation = 0.53,
        parameter_start = -1.35,
        parameter_finish = 1.35,
        parameter = 0.7,
        rail_half_length = 0.4,
    }
    pose := hyperbola_tool_pose(center, value)
    test_helpers.expect_vec3_close(t,
        (pose.carriage_positive + pose.carriage_negative) * 0.5, center,
        "carriage midpoint should remain at the hyperbola center")
    test_helpers.expect_vec3_close(t,
        (pose.tick_first_start + pose.tick_second_finish) * 0.5, center,
        "minimum-radius ticks should remain centrally symmetric")
    test_helpers.expect_vec3_close(t,
        pose.carriage_positive, hyperbola_point(center, {
            branch = 1,
            semimajor = value.semimajor,
            semiminor = value.semiminor,
            rotation = value.rotation,
            parameter_start = value.parameter_start,
            parameter_finish = value.parameter_finish,
            draw_parameter = value.parameter,
        }, value.parameter),
        "positive carriage should agree with the analytic hyperbola point")
}

// Verify reverse parabola sampling ends at its exact frontier without reversing order.
@(test)
parabola_curve_sampling_preserves_reverse_domain_and_frontier :: proc(t: ^testing.T) {
    value: shapemodel.Shape_Parabola = {
        focal_distance = 0.075,
        parameter_start = 1.6,
        parameter_finish = -1.6,
        draw_parameter = 0.25,
    }
    vertices: [CONIC_MAX_VERTICES]Vector3
    result := parabola_explicate({}, value, vertices[:])

    testing.expect(t, result.status != .Invalid_Input)
    testing.expect(t, result.vertex_count > 2)
    test_helpers.expect_vec3_close(t, vertices[0],
        parabola_point({}, value, value.parameter_start),
        "reverse sampling should begin at the directed domain start")
    test_helpers.expect_vec3_close(t, vertices[result.vertex_count - 1],
        parabola_point({}, value, value.draw_parameter),
        "reverse sampling should end at the exact draw frontier")
    testing.expectf(t,
        vertices[result.vertex_count - 1].y < vertices[0].y,
        "reverse samples should follow the directed parameter order")
}

// Verify each hyperbola branch samples independently to its exact parameter frontier.
@(test)
hyperbola_curve_sampling_keeps_branches_separate :: proc(t: ^testing.T) {
    positive: shapemodel.Shape_Hyperbola_Branch = {
        branch = 1,
        semimajor = 0.12,
        semiminor = 0.1,
        parameter_start = -1.35,
        parameter_finish = 1.35,
        draw_parameter = 0.4,
    }
    negative := positive
    negative.branch = -1
    positive_vertices: [CONIC_MAX_VERTICES]Vector3
    negative_vertices: [CONIC_MAX_VERTICES]Vector3
    positive_result := hyperbola_explicate({}, positive, positive_vertices[:])
    negative_result := hyperbola_explicate({}, negative, negative_vertices[:])

    testing.expect(t, positive_result.vertex_count > 1)
    testing.expect(t, negative_result.vertex_count > 1)
    test_helpers.expect_vec3_close(t,
        positive_vertices[positive_result.vertex_count - 1],
        hyperbola_point({}, positive, positive.draw_parameter),
        "positive branch should end at its exact frontier")
    test_helpers.expect_vec3_close(t,
        negative_vertices[negative_result.vertex_count - 1],
        hyperbola_point({}, negative, negative.draw_parameter),
        "negative branch should end at its own exact frontier")
    testing.expect(t,
        positive_vertices[positive_result.vertex_count - 1].x > 0 &&
        negative_vertices[negative_result.vertex_count - 1].x < 0,
        "separate branch packets should never bridge the center")
}

// Verify invalid conic geometry and insufficient bounded output are rejected.
@(test)
conic_curve_sampling_rejects_invalid_and_short_outputs :: proc(t: ^testing.T) {
    invalid: shapemodel.Shape_Parabola = {
        focal_distance = 0.075,
        parameter_start = 0,
        parameter_finish = 1,
        draw_parameter = 2,
    }
    invalid_vertices: [CONIC_MAX_VERTICES]Vector3
    invalid_result := parabola_explicate({}, invalid, invalid_vertices[:])
    short_vertices: [2]Vector3
    valid: shapemodel.Shape_Parabola = {
        focal_distance = 0.075,
        parameter_start = 0,
        parameter_finish = 1,
        draw_parameter = 1,
    }
    short_result := parabola_explicate({}, valid, short_vertices[:])

    testing.expect_value(t, invalid_result.status, Curve_Explication_Status.Invalid_Input)
    testing.expect_value(t, invalid_result.vertex_count, 0)
    testing.expect_value(t, short_result.status, Curve_Explication_Status.Invalid_Input)
    testing.expect_value(t, short_result.vertex_count, 0)
}

// Verify valid high-curvature input reports bounded sampling capacity explicitly.
@(test)
hyperbola_curve_sampling_reports_capacity_limit :: proc(t: ^testing.T) {
    value: shapemodel.Shape_Hyperbola_Branch = {
        branch = 1,
        semimajor = 100,
        semiminor = 100,
        parameter_start = -4,
        parameter_finish = 4,
        draw_parameter = 4,
    }
    vertices: [CONIC_MAX_VERTICES]Vector3
    result := hyperbola_explicate({}, value, vertices[:])

    testing.expect_value(t, result.status, Curve_Explication_Status.Capacity_Limited)
    testing.expect(t, result.vertex_count <= CONIC_MAX_VERTICES)
}

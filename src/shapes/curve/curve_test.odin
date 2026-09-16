package curve

import shapemodel "../model"
import test_helpers "../../test_helpers"

import "core:math"
import "core:testing"

// Verify an external equal-circle trochoid starts at its contact-aligned cusp.
@(test)
trochoid_curve_external_cardioid_starts_at_fixed_contact :: proc(t: ^testing.T) {
    value := shapemodel.Shape_Trochoid{mode = .External, fixed_radius = 2,
        rolling_radius = 2, tracer_distance = 2, parameter_start = 0,
        parameter_finish = 2 * math.PI, draw_parameter = 2 * math.PI}
    point := trochoid_point({}, value, 0)
    pose := trochoid_tool_pose({}, {mode = .External, fixed_radius = 2,
        rolling_radius = 2})

    test_helpers.expect_vec3_close(t, pose.rolling_center, {4, 0, 0},
        "external rolling center should start outside the fixed circle")
    test_helpers.expect_vec3_close(t, point, {2, 0, 0},
        "cardioid tracer should start at the fixed-circle contact")
    testing.expectf(t, math.abs(pose.rolling_orientation - math.PI) < 1e-5,
        "external rolling orientation should initially point toward contact")
}

// Verify an internal rolling circle starts at the outward fixed-circle contact.
@(test)
trochoid_curve_internal_contact_and_orientation_are_outward :: proc(t: ^testing.T) {
    value := shapemodel.Shape_Trochoid{mode = .Internal, fixed_radius = 4,
        rolling_radius = 1, tracer_distance = 1, parameter_start = 0,
        parameter_finish = 2 * math.PI, draw_parameter = 2 * math.PI}
    point := trochoid_point({1, 2, 3}, value, 0)
    pose := trochoid_tool_pose({1, 2, 3}, {mode = .Internal,
        fixed_radius = 4, rolling_radius = 1})

    test_helpers.expect_vec3_close(t, pose.rolling_center, {4, 2, 3},
        "internal rolling center should start inside the fixed circle")
    test_helpers.expect_vec3_close(t, point, {5, 2, 3},
        "internal tracer should start at the fixed-circle contact")
    testing.expectf(t, math.abs(pose.rolling_orientation) < 1e-5,
        "internal rolling orientation should initially point toward contact")
}

// Verify planar rotation and independent tracer phase transform the evaluator.
@(test)
trochoid_curve_rotation_and_tracer_phase_are_independent :: proc(t: ^testing.T) {
    value := shapemodel.Shape_Trochoid{mode = .External, fixed_radius = 1,
        rolling_radius = 1, tracer_distance = 0.5, tracer_phase = math.PI / 2,
        rotation = math.PI / 2, parameter_start = 0, parameter_finish = 1,
        draw_parameter = 0}
    point := trochoid_point({}, value, 0)

    test_helpers.expect_vec3_close(t, point, {0.5, 2, 0},
        "world rotation and tracer phase should affect distinct terms")
}

// Verify reveal growth retains every established adaptive vertex and adds its endpoint.
@(test)
trochoid_curve_explication_preserves_revealed_prefix :: proc(t: ^testing.T) {
    value := shapemodel.Shape_Trochoid{mode = .External, fixed_radius = 0.2,
        rolling_radius = 0.2, tracer_distance = 0.2, parameter_start = 0,
        parameter_finish = 2 * math.PI, draw_parameter = math.PI * 0.73}
    partial: [TROCHOID_MAX_VERTICES]Vector3
    partial_result := trochoid_explicate({}, value, partial[:])
    value.draw_parameter = value.parameter_finish
    complete: [TROCHOID_MAX_VERTICES]Vector3
    complete_result := trochoid_explicate({}, value, complete[:])

    testing.expect(t, partial_result.status != .Invalid_Input)
    testing.expect(t, complete_result.status != .Invalid_Input)
    testing.expect(t, partial_result.vertex_count > 1)
    for index in 0..<partial_result.vertex_count - 1 {
        test_helpers.expect_vec3_close(t, partial[index], complete[index],
            "advancing the frontier should retain completed vertices")
    }
    expected := trochoid_point({}, value, math.PI * 0.73)
    test_helpers.expect_vec3_close(t, partial[partial_result.vertex_count - 1],
        expected, "partial explication should include the exact frontier")
}

// Verify reverse directed domains explicate from their start toward their frontier.
@(test)
trochoid_curve_explication_supports_reverse_domains :: proc(t: ^testing.T) {
    value := shapemodel.Shape_Trochoid{mode = .External, fixed_radius = 0.2,
        rolling_radius = 0.1, tracer_distance = 0.1, parameter_start = math.PI,
        parameter_finish = -math.PI, draw_parameter = 0}
    vertices: [TROCHOID_MAX_VERTICES]Vector3
    result := trochoid_explicate({}, value, vertices[:])

    testing.expect(t, result.status != .Invalid_Input)
    test_helpers.expect_vec3_close(t, vertices[0],
        trochoid_point({}, value, math.PI),
        "reverse explication should begin at the directed start")
    test_helpers.expect_vec3_close(t, vertices[result.vertex_count - 1],
        trochoid_point({}, value, 0),
        "reverse explication should end at the exact frontier")
}

// Verify insufficient output storage is rejected without writing a partial curve.
@(test)
trochoid_curve_explication_rejects_short_output :: proc(t: ^testing.T) {
    value := shapemodel.Shape_Trochoid{mode = .External, fixed_radius = 1,
        rolling_radius = 1, tracer_distance = 1, parameter_start = 0,
        parameter_finish = 1, draw_parameter = 1}
    vertices: [2]Vector3
    result := trochoid_explicate({}, value, vertices[:])

    testing.expect_value(t, result.status, Curve_Explication_Status.Invalid_Input)
    testing.expect_value(t, result.vertex_count, 0)
}
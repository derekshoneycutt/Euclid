package curve

import shapemodel "../model"
import test_helpers "../../test_helpers"

import "core:math"
import "core:testing"

// Count geometric cusp vertices, excluding a duplicated cusp-closed endpoint.
curve_test_distinct_cusp_count :: proc(kinds: []Curve_Point_Kind,
    result: Curve_Explication_Result) -> int {
    count := 0
    for kind in kinds[:result.vertex_count] {
        if kind == .Cusp {count += 1}
    }
    if result.topology == .Cusp_Closed && kinds[result.vertex_count - 1] == .Cusp {
        count -= 1
    }
    return count
}

// Return whether a marked output contains the exact point at one parameter.
curve_test_has_marked_point :: proc(vertices: []Vector3,
    kinds: []Curve_Point_Kind, count: int, expected: Vector3) -> bool {
    for index in 0..<count {
        delta := vertices[index] - expected
        if kinds[index] == .Cusp &&
            delta.x * delta.x + delta.y * delta.y < 1e-10 {
            return true
        }
    }
    return false
}

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

// Verify the longest planned rational hypocycloid closes without exhausting storage.
@(test)
trochoid_curve_eleven_half_hypocycloid_is_complete_and_closed :: proc(
    t: ^testing.T) {
    fixed_radius := f32(0.25)
    rolling_radius := fixed_radius / 5.5
    value := shapemodel.Shape_Trochoid{mode = .Internal,
        fixed_radius = fixed_radius, rolling_radius = rolling_radius,
        tracer_distance = rolling_radius, parameter_start = 0,
        parameter_finish = 4 * math.PI, draw_parameter = 4 * math.PI}
    vertices: [TROCHOID_MAX_VERTICES]Vector3
    result := trochoid_explicate({}, value, vertices[:])

    testing.expect_value(t, result.status, Curve_Explication_Status.Complete)
    testing.expect_value(t, result.topology, Curve_Topology.Cusp_Closed)
    testing.expect(t, result.vertex_count > TROCHOID_BASE_SEGMENTS)
    test_helpers.expect_vec3_close(t, vertices[0],
        vertices[result.vertex_count - 1],
        "11/2 hypocycloid should close after two fixed-center revolutions")
    midpoint := trochoid_point({}, value, 2 * math.PI)
    testing.expectf(t, math.abs(midpoint.x - vertices[0].x) > 1e-4 ||
        math.abs(midpoint.y - vertices[0].y) > 1e-4,
        "11/2 hypocycloid should not close after one fixed-center revolution")
}

// Verify the planned 5:3:5 Hypotrochoid closes within bounded curve storage.
@(test)
trochoid_curve_five_point_hypotrochoid_is_complete_and_closed :: proc(
    t: ^testing.T) {
    value := shapemodel.Shape_Trochoid{mode = .Internal, fixed_radius = 0.25,
        rolling_radius = 0.15, tracer_distance = 0.25, parameter_start = 0,
        parameter_finish = 6 * math.PI, draw_parameter = 6 * math.PI}
    vertices: [TROCHOID_MAX_VERTICES]Vector3
    result := trochoid_explicate({}, value, vertices[:])

    testing.expect_value(t, result.status, Curve_Explication_Status.Complete)
    testing.expect_value(t, result.topology, Curve_Topology.Closed)
    testing.expect(t, result.vertex_count > TROCHOID_BASE_SEGMENTS)
    test_helpers.expect_vec3_close(t, vertices[0],
        vertices[result.vertex_count - 1],
        "5:3:5 Hypotrochoid should close after three fixed-center revolutions")
    first_turn := trochoid_point({}, value, 2 * math.PI)
    testing.expectf(t, math.abs(first_turn.x - vertices[0].x) > 1e-4 ||
        math.abs(first_turn.y - vertices[0].y) > 1e-4,
        "5:3:5 Hypotrochoid should not close after one fixed-center revolution")
}

// Verify two revolutions are centered on the literal rail with three cusp contacts.
@(test)
cycloid_curve_two_revolutions_use_literal_line :: proc(t: ^testing.T) {
    value := shapemodel.Shape_Cycloid{rolling_radius = 0.05,
        tracer_distance = 0.05, parameter_start = 0,
        parameter_finish = 4 * math.PI, draw_parameter = 4 * math.PI}
    first := Vector3{-0.4, 0, 2}
    second := Vector3{0.4, 0, 2}

    start := cycloid_point(first, second, value, 0)
    middle := cycloid_point(first, second, value, 2 * math.PI)
    finish := cycloid_point(first, second, value, 4 * math.PI)

    testing.expectf(t, math.abs(start.y - 0) < 1e-5 &&
        math.abs(middle.y - 0) < 1e-5 && math.abs(finish.y - 0) < 1e-5,
        "ordinary cycloid cusps should touch the literal rail")
    testing.expectf(t, math.abs(middle.x) < 1e-5,
        "two-revolution travel should be centered on the rail")
    testing.expectf(t, start.x > first.x && finish.x < second.x,
        "literal rail should retain visible margins around wheel travel")
}

// Verify rotated rails determine both rolling centers and material orientation.
@(test)
cycloid_tool_pose_follows_endpoint_direction :: proc(t: ^testing.T) {
    value := shapemodel.Shape_Cycloid_Tool{rolling_radius = 0.1,
        parameter_start = -1, parameter_finish = 1, parameter = 0}
    pose := cycloid_tool_pose({1, 1, 3}, {1, 2, 3}, value)

    test_helpers.expect_vec3_close(t, pose.baseline_start, {1, 1, 3},
        "tool should preserve the exact first rail endpoint")
    test_helpers.expect_vec3_close(t, pose.baseline_finish, {1, 2, 3},
        "tool should preserve the exact second rail endpoint")
    test_helpers.expect_vec3_close(t, pose.contact, {1, 1.5, 3},
        "centered parameter should contact the rail midpoint")
    test_helpers.expect_vec3_close(t, pose.rolling_center, {0.9, 1.5, 3},
        "rolling center should use the endpoint-derived planar normal")
}

// Verify adaptive reveal preserves completed boundaries and exact frontier.
@(test)
cycloid_curve_explication_preserves_revealed_prefix :: proc(t: ^testing.T) {
    first := Vector3{-0.5, 0, 0}
    second := Vector3{0.5, 0, 0}
    value := shapemodel.Shape_Cycloid{rolling_radius = 0.05,
        tracer_distance = 0.08, parameter_start = 0,
        parameter_finish = 4 * math.PI, draw_parameter = 1.7 * math.PI}
    partial: [CYCLOID_MAX_VERTICES]Vector3
    partial_result := cycloid_explicate(first, second, value, partial[:])
    value.draw_parameter = value.parameter_finish
    complete: [CYCLOID_MAX_VERTICES]Vector3
    complete_result := cycloid_explicate(first, second, value, complete[:])

    testing.expect(t, partial_result.status != .Invalid_Input)
    testing.expect(t, complete_result.status != .Invalid_Input)
    for index in 0..<partial_result.vertex_count - 1 {
        test_helpers.expect_vec3_close(t, partial[index], complete[index],
            "advancing cycloid frontier should retain completed vertices")
    }
    expected := cycloid_point(first, second, value, 1.7 * math.PI)
    test_helpers.expect_vec3_close(t, partial[partial_result.vertex_count - 1],
        expected, "partial cycloid should include its exact frontier")
}

// Verify canonical closed trochoids expose their distinct analytic cusp counts.
@(test)
trochoid_curve_marks_canonical_cusp_families :: proc(t: ^testing.T) {
    values := [?]shapemodel.Shape_Trochoid{
        {mode = .External, fixed_radius = 0.2, rolling_radius = 0.2,
            tracer_distance = 0.2, parameter_finish = 2 * math.PI,
            draw_parameter = 2 * math.PI},
        {mode = .Internal, fixed_radius = 0.2, rolling_radius = 0.05,
            tracer_distance = 0.05, parameter_finish = 2 * math.PI,
            draw_parameter = 2 * math.PI},
        {mode = .External, fixed_radius = 0.2, rolling_radius = 0.1,
            tracer_distance = 0.1, parameter_finish = 2 * math.PI,
            draw_parameter = 2 * math.PI},
        {mode = .Internal, fixed_radius = 0.22, rolling_radius = 0.04,
            tracer_distance = 0.04, parameter_finish = 4 * math.PI,
            draw_parameter = 4 * math.PI},
    }
    expected := [?]int{1, 4, 2, 11}
    for value, case_index in values {
        vertices: [TROCHOID_MAX_VERTICES]Vector3
        kinds: [TROCHOID_MAX_VERTICES]Curve_Point_Kind
        result := trochoid_explicate_marked({}, value, vertices[:], kinds[:])
        testing.expect_value(t, result.status, Curve_Explication_Status.Complete)
        testing.expect_value(t, result.topology, Curve_Topology.Cusp_Closed)
        testing.expect_value(t,
            curve_test_distinct_cusp_count(kinds[:], result), expected[case_index])
    }
}

// Verify curtate and prolate trochoids never acquire analytic cusp marks.
@(test)
trochoid_curve_rejects_noncontact_cusp_candidates :: proc(t: ^testing.T) {
    distances := [?]f32{0.05, 0.15}
    for distance in distances {
        value := shapemodel.Shape_Trochoid{mode = .External, fixed_radius = 0.2,
            rolling_radius = 0.1, tracer_distance = distance,
            parameter_finish = 2 * math.PI, draw_parameter = 2 * math.PI}
        vertices: [TROCHOID_MAX_VERTICES]Vector3
        kinds: [TROCHOID_MAX_VERTICES]Curve_Point_Kind
        result := trochoid_explicate_marked({}, value, vertices[:], kinds[:])
        testing.expect_value(t,
            curve_test_distinct_cusp_count(kinds[:], result), 0)
    }
}

// Verify reverse domains retain the same exact cusp family in reverse order.
@(test)
trochoid_curve_marks_reverse_domain_cusps :: proc(t: ^testing.T) {
    value := shapemodel.Shape_Trochoid{mode = .Internal, fixed_radius = 0.2,
        rolling_radius = 0.05, tracer_distance = 0.05,
        parameter_start = 2 * math.PI, parameter_finish = 0, draw_parameter = 0}
    vertices: [TROCHOID_MAX_VERTICES]Vector3
    kinds: [TROCHOID_MAX_VERTICES]Curve_Point_Kind
    result := trochoid_explicate_marked({}, value, vertices[:], kinds[:])

    testing.expect_value(t, result.topology, Curve_Topology.Cusp_Closed)
    testing.expect_value(t, curve_test_distinct_cusp_count(kinds[:], result), 4)
    testing.expect(t, curve_test_has_marked_point(vertices[:], kinds[:],
        result.vertex_count, trochoid_point({}, value, math.PI / 2)))
}

// Verify pathological cusp density reports a deterministic bounded result.
@(test)
trochoid_curve_cusp_capacity_is_bounded_and_deterministic :: proc(t: ^testing.T) {
    value := shapemodel.Shape_Trochoid{mode = .External, fixed_radius = 0.1,
        rolling_radius = 0.1, tracer_distance = 0.1,
        parameter_finish = 1000 * math.TAU, draw_parameter = 1000 * math.TAU}
    first_vertices, second_vertices: [TROCHOID_MAX_VERTICES]Vector3
    first_kinds, second_kinds: [TROCHOID_MAX_VERTICES]Curve_Point_Kind
    first := trochoid_explicate_marked(
        {}, value, first_vertices[:], first_kinds[:])
    second := trochoid_explicate_marked(
        {}, value, second_vertices[:], second_kinds[:])

    testing.expect_value(t, first.status, Curve_Explication_Status.Capacity_Limited)
    testing.expect_value(t, first.vertex_count, TROCHOID_MAX_VERTICES)
    testing.expect_value(t, first.topology, Curve_Topology.Open)
    testing.expect_value(t, first_kinds[first.vertex_count - 1],
        Curve_Point_Kind.Cusp)
    test_helpers.expect_vec3_close(t, first_vertices[first.vertex_count - 1],
        trochoid_point({}, value, 512 * math.TAU),
        "cusp overflow should retain the directed mandatory prefix")
    testing.expect_value(t, second.vertex_count, first.vertex_count)
    testing.expect(t, first_vertices == second_vertices)
    testing.expect(t, first_kinds == second_kinds)
}

// Verify phase-shifted cycloid cusps are inserted at their exact parameters.
@(test)
cycloid_curve_marks_phase_shifted_cusps :: proc(t: ^testing.T) {
    first := Vector3{-2, 0, 0}
    second := Vector3{2, 0, 0}
    value := shapemodel.Shape_Cycloid{rolling_radius = 0.1,
        tracer_distance = 0.1, tracer_phase = math.PI / 2,
        parameter_finish = 4 * math.PI, draw_parameter = 4 * math.PI}
    vertices: [CYCLOID_MAX_VERTICES]Vector3
    kinds: [CYCLOID_MAX_VERTICES]Curve_Point_Kind
    result := cycloid_explicate_marked(first, second, value, vertices[:], kinds[:])

    testing.expect_value(t, curve_test_distinct_cusp_count(kinds[:], result), 2)
    testing.expect(t, curve_test_has_marked_point(vertices[:], kinds[:],
        result.vertex_count, cycloid_point(first, second, value, 1.5 * math.PI)))
    testing.expect(t, curve_test_has_marked_point(vertices[:], kinds[:],
        result.vertex_count, cycloid_point(first, second, value, 3.5 * math.PI)))
}

// Verify a reveal endpoint changes kind only when it reaches an analytic cusp.
@(test)
cycloid_curve_frontier_preserves_cusp_transition :: proc(t: ^testing.T) {
    Frontier_Case :: struct {
        parameter: f32,
        cusps: int,
    }
    first := Vector3{-1, 0, 0}
    second := Vector3{1, 0, 0}
    value := shapemodel.Shape_Cycloid{rolling_radius = 0.1,
        tracer_distance = 0.1, parameter_start = math.PI,
        parameter_finish = 3 * math.PI, draw_parameter = 1.9 * math.PI}
    cases := [?]Frontier_Case{
        {1.9 * math.PI, 0}, {2 * math.PI, 1}, {2.1 * math.PI, 1}}
    for test_case in cases {
        value.draw_parameter = test_case.parameter
        vertices: [CYCLOID_MAX_VERTICES]Vector3
        kinds: [CYCLOID_MAX_VERTICES]Curve_Point_Kind
        result := cycloid_explicate_marked(
            first, second, value, vertices[:], kinds[:])
        testing.expect_value(t,
            curve_test_distinct_cusp_count(kinds[:], result), test_case.cusps)
        testing.expect_value(t, result.topology, Curve_Topology.Open)
    }
}

// Verify noncontact cycloids remain ordinary for both tracer-distance directions.
@(test)
cycloid_curve_rejects_curtate_and_prolate_cusps :: proc(t: ^testing.T) {
    first := Vector3{-2, 0, 0}
    second := Vector3{2, 0, 0}
    distances := [?]f32{0.05, 0.15}
    for distance in distances {
        value := shapemodel.Shape_Cycloid{rolling_radius = 0.1,
            tracer_distance = distance, parameter_finish = 4 * math.PI,
            draw_parameter = 4 * math.PI}
        vertices: [CYCLOID_MAX_VERTICES]Vector3
        kinds: [CYCLOID_MAX_VERTICES]Curve_Point_Kind
        result := cycloid_explicate_marked(
            first, second, value, vertices[:], kinds[:])
        testing.expect_value(t,
            curve_test_distinct_cusp_count(kinds[:], result), 0)
    }
}

// Verify marked explication rejects a kind stream that cannot remain aligned.
@(test)
cycloid_curve_marked_explication_rejects_short_kinds :: proc(t: ^testing.T) {
    value := shapemodel.Shape_Cycloid{rolling_radius = 0.1,
        tracer_distance = 0.1, parameter_finish = math.TAU,
        draw_parameter = math.TAU}
    vertices: [CYCLOID_MAX_VERTICES]Vector3
    kinds: [2]Curve_Point_Kind
    result := cycloid_explicate_marked(
        {-1, 0, 0}, {1, 0, 0}, value, vertices[:], kinds[:])

    testing.expect_value(t, result.status, Curve_Explication_Status.Invalid_Input)
    testing.expect_value(t, result.vertex_count, 0)
}

// Verify optional refinement saturation remains bounded after mandatory cusp work.
@(test)
trochoid_curve_refinement_capacity_is_bounded :: proc(t: ^testing.T) {
    value := shapemodel.Shape_Trochoid{mode = .Internal, fixed_radius = 0.25,
        rolling_radius = 0.001, tracer_distance = 0.0005,
        parameter_finish = math.TAU, draw_parameter = math.TAU}
    vertices: [TROCHOID_MAX_VERTICES]Vector3
    kinds: [TROCHOID_MAX_VERTICES]Curve_Point_Kind
    result := trochoid_explicate_marked({}, value, vertices[:], kinds[:])

    testing.expect_value(t, result.status, Curve_Explication_Status.Capacity_Limited)
    testing.expect_value(t, result.vertex_count, TROCHOID_MAX_VERTICES)
    testing.expect_value(t, curve_test_distinct_cusp_count(kinds[:], result), 0)
}
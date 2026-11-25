package modifier

import curve "../shapes/curve"
import "core:testing"

// Characterize a rotated, reversed, partially drawn conic with explicit local time.
conic_test_request :: proc(kind: Modifier_Kind) -> Modifier_Request {
    return {
        kind = kind,
        entity = 1,
        elapsed = 0.5,
        duration = 1,
        start_position = {0.4, 0.5, 0.1},
        third_position = {1, 0, -0.5},
        radius = 0.075,
        displacement = {0.1, 0, 0},
        angle = 0.6,
        scalar = 1.2,
        color_packed = 0xff123456,
    }
}

// Verify selected trails use canonical intrinsic axes at intermediate and exact endpoints.
@(test)
conic_draws_have_exact_frontiers_and_selected_rotated_trails :: proc(t: ^testing.T) {
    for kind in ([?]Modifier_Kind{.Parabola_Draw, .Hyperbola_Draw}) {
        for selection in 0..<3 {
            request := conic_test_request(kind)
            request.integer = selection
            for elapsed in ([?]f32{0, 0.5, 1, 2}) {
                request.elapsed = elapsed
                output: Modifier_Output_Buffer
                testing.expect_value(t,
                    evaluate_modifier(request, &output), Modifier_Status.Ok)
                parameter := f32(1) - 1.5 * min(elapsed, 1)
                testing.expect_value(t, output.outputs[0].scalar, parameter)
                testing.expect_value(t, output.outputs[2].scalar, parameter)
                testing.expect_value(t, output.outputs[1].flag, true)
                testing.expect_value(t, output.outputs[1].scalar, f32(selection))
                expect_conic_trails(t, request, parameter, &output)
            }
        }
    }
}

// Check compact expansion counts and exact tracer positions without a Julia setter mock.
expect_conic_trails :: proc(
    t: ^testing.T, request: Modifier_Request, parameter: f32,
    output: ^Modifier_Output_Buffer) {
    if request.kind == .Parabola_Draw {
        testing.expect_value(t, output.count, 5)
        testing.expect_value(t,
            output.outputs[3].kind, Modifier_Output_Kind.Queue_Tool_Contact)
        testing.expect_value(t, output.outputs[4].position, output.outputs[3].position)
        testing.expect_value(t, output.outputs[3].position,
            curve.parabola_point(request.start_position, {
                focal_distance = request.radius,
                rotation = request.angle,
            }, parameter))
        return
    }
    count := 5
    if request.integer == 0 {
        count = 7
    }
    testing.expect_value(t, output.count, count)
    index := 3
    for branch in ([?]i32{1, -1}) {
        if (request.integer == 1 && branch == -1) ||
            (request.integer == 2 && branch == 1) {
            continue
        }
        testing.expect_value(t, output.outputs[index].position,
            curve.hyperbola_point(request.start_position, {
                semimajor = request.radius,
                semiminor = request.displacement.x,
                rotation = request.angle,
            }, parameter, branch))
        testing.expect_value(t,
            output.outputs[index].kind, Modifier_Output_Kind.Queue_Tool_Contact)
        testing.expect_value(t,
            output.outputs[index + 1].position, output.outputs[index].position)
        index += 2
    }
}

// Placement leaves contact alone; travel is inactive and only descent changes visibility.
@(test)
conic_travel_keeps_authored_visibility_and_inactive_contacts :: proc(t: ^testing.T) {
    kinds: [6]Modifier_Kind = {
        .Parabola_Place, .Parabola_Descend, .Parabola_Rise,
        .Hyperbola_Place, .Hyperbola_Descend, .Hyperbola_Rise,
    }
    for kind, index in kinds {
        request := conic_test_request(kind)
        output: Modifier_Output_Buffer
        testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
        expected_count := 1
        if index % 3 == 1 {
            expected_count = 3
        } else if index % 3 == 2 {
            expected_count = 2
        }
        testing.expect_value(t, output.count, expected_count)
        testing.expect_value(t, output.outputs[0].scalar, f32(1))
        expected_z := f32(0.7)
        if index % 3 == 0 {
            expected_z = 1.3
        }
        testing.expect(t, abs(output.outputs[0].position.z - expected_z) < 1e-6)
        if output.count > 1 {
            testing.expect(t, !output.outputs[1].flag)
        }
    }
}

// Reject malformed scales, branch selections and time before publishing partial output.
@(test)
conic_invalid_requests_leave_no_outputs :: proc(t: ^testing.T) {
    output: Modifier_Output_Buffer
    request := conic_test_request(.Hyperbola_Draw)
    request.displacement.x = 0
    testing.expect_value(t, evaluate_modifier(request, &output),
        Modifier_Status.Invalid_Argument)
    request = conic_test_request(.Parabola_Draw)
    request.radius = 0
    testing.expect_value(t, evaluate_modifier(request, &output),
        Modifier_Status.Invalid_Argument)
    request = conic_test_request(.Hyperbola_Draw)
    request.integer = 3
    testing.expect_value(t, evaluate_modifier(request, &output),
        Modifier_Status.Invalid_Argument)
    request = conic_test_request(.Parabola_Draw)
    request.elapsed = -1
    testing.expect_value(t, evaluate_modifier(request, &output),
        Modifier_Status.Invalid_Argument)
    testing.expect_value(t, output.count, 0)
}

// Zero-duration completion snaps to the requested endpoint without extrapolation.
@(test)
conic_immediate_completion_uses_the_exact_requested_frontier :: proc(t: ^testing.T) {
    request := conic_test_request(.Hyperbola_Draw)
    request.elapsed, request.duration = 0, 0
    output: Modifier_Output_Buffer
    testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
    testing.expect_value(t, output.outputs[0].scalar, f32(-0.5))
    testing.expect_value(t, output.outputs[2].scalar, f32(-0.5))
    testing.expect_value(t, output.count, 7)
}

// Build one full-duration conic recipe with a directed, partial frontier.
conic_sequence_test_request :: proc(kind: Modifier_Kind) -> Modifier_Request {
    return {
        kind = kind,
        entity = 1,
        duration = 1,
        start_position = {0.4, 0.5, 0.1},
        third_position = {1, -1, -0.5},
        radius = 0.075,
        displacement = {0.16, 0, 0},
        angle = 0.6,
        scalar = 1.2,
    }
}

// Expand accelerated conic steps in phase order and retain exact boundary ink.
@(test)
conic_sequences_expand_skipped_phases_and_selected_tracer_contacts :: proc(
    t: ^testing.T) {
    for kind in ([?]Modifier_Kind{.Parabola_Sequence, .Hyperbola_Sequence}) {
        for selection in 0..<3 {
            request := conic_sequence_test_request(kind)
            request.integer = selection
            samples := conic_sequence_samples(request, 0, 1)
            testing.expect_value(t, samples.count, 3)
            testing.expect_value(t,
                samples.requests[0].kind, conic_sequence_kind(kind, false, false))
            testing.expect_value(t,
                samples.requests[1].kind, conic_sequence_kind(kind, true, false))
            testing.expect_value(t,
                samples.requests[2].kind, conic_sequence_kind(kind, false, true))
            output: Modifier_Output_Buffer
            testing.expect_value(t, evaluate_modifier(samples.requests[1], &output),
                Modifier_Status.Ok)
            testing.expect_value(t, output.outputs[2].scalar, f32(-0.5))
            expect_conic_trails(t, samples.requests[1], f32(-0.5), &output)
        }
    }
}

// Reject malformed full-duration domains before a native sequence is admitted.
@(test)
conic_sequences_reject_invalid_domain_and_duration :: proc(t: ^testing.T) {
    request := conic_sequence_test_request(.Parabola_Sequence)
    testing.expect(t, modifier_request_valid(request))
    request.duration = 0
    testing.expect(t, !modifier_request_valid(request))
    request = conic_sequence_test_request(.Hyperbola_Sequence)
    request.third_position.z = 2
    testing.expect(t, !modifier_request_valid(request))
}

package modifier

import geometry "../core/geometry"
import math "core:math"
import testing "core:testing"

// Supply a directed partial-domain request usable by either rolling family.
rolling_test_request :: proc(kind: Modifier_Kind) -> Modifier_Request {
    return {
        kind = kind,
        entity = 10,
        duration = 1,
        start_position = {0.1, 0.2, 0.03},
        second_position = {0.9, 0.8, 0.03},
        third_position = {2, -2, -1},
        displacement = {0.2, 0.04, 0.3},
        radius = 0.05,
        angle = 0.4,
        scalar = 0.6,
        brush = 0.01,
        color_packed = 0x12345678,
    }
}

// Require a finite native position to agree with independently characterized math.
expect_rolling_position :: proc(
    t: ^testing.T, actual, expected: geometry.Vector3) {
    testing.expect(t, math.abs(actual.x - expected.x) < 1e-6)
    testing.expect(t, math.abs(actual.y - expected.y) < 1e-6)
    testing.expect(t, math.abs(actual.z - expected.z) < 1e-6)
}

// Check vertical, horizontal, and oblique Cycloid rails for all tracer ratios.
@(test)
rolling_cycloid_samples_preserve_oblique_reversed_partial_geometry :: proc(
    t: ^testing.T) {
    samples: [5]f32 = {0, 0.25, 0.5, 1, 2}
    distances: [3]f32 = {0.02, 0.05, 0.08}
    bases: [3]geometry.Vector3 = {{0.8, 0.6, 0}, {1, 0, 0}, {0, 1, 0}}
    for basis in bases {
        for distance in distances {
            for elapsed in samples {
                request := rolling_test_request(.Cycloid_Draw)
                request.displacement = {distance, 0.3, 0}
                request.elapsed = elapsed
                request.second_position = request.start_position + basis
                output: Modifier_Output_Buffer
                testing.expect_value(t,
                    evaluate_modifier(request, &output), Modifier_Status.Ok)
                testing.expect_value(t, output.count, 9)
                parameter := 2 - 3 * min(elapsed, 1)
                contact := (request.start_position + request.second_position) * 0.5 +
                    basis * 0.05 * parameter
                normal: geometry.Vector3 = {-basis.y, basis.x, 0}
                center := contact + normal * 0.05
                tracer := center - basis * distance * math.sin(parameter + 0.3) -
                    normal * distance * math.cos(parameter + 0.3)
                expect_rolling_position(t, output.outputs[1].position, center)
                expect_rolling_position(t, output.outputs[2].position, tracer)
                expect_rolling_position(t, output.outputs[8].position, tracer)
                testing.expect_value(t, output.outputs[6].scalar, parameter)
                testing.expect(t, output.outputs[1].integer == 0 &&
                    output.outputs[2].integer == 0)
            }
        }
    }
}

// Check both ring modes and arbitrary phase/rotation independently of native helpers.
@(test)
rolling_trochoid_samples_preserve_rotated_material_axes :: proc(t: ^testing.T) {
    samples: [5]f32 = {0, 0.25, 0.5, 1, 2}
    distances: [4]f32 = {0, 0.02, 0.05, 0.09}
    ratios: [7]f32 = {1, 2, 3, 4, 5, 5.5, 5.0 / 3.0}
    for mode in 0..<2 {
        for ratio in ratios {
            if mode == 1 && ratio == 1 {
                continue
            }
            for distance in distances {
                for elapsed in samples {
                    request := rolling_test_request(.Trochoid_Draw)
                    request.integer = mode
                    request.radius = request.displacement.x / ratio
                    request.displacement.y = distance
                    request.elapsed = elapsed
                    expect_rolling_trochoid_sample(t, request)
                }
            }
        }
    }
}

// Compare one native ring sample against independent material-angle geometry.
expect_rolling_trochoid_sample :: proc(t: ^testing.T, request: Modifier_Request) {
    output: Modifier_Output_Buffer
    testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
    testing.expect_value(t, output.count, 9)
    parameter := 2 - 3 * min(request.elapsed, 1)
    orbit := request.displacement.x + request.radius
    direction := f32(1)
    phase := f32(math.PI)
    if request.integer == 1 {
        orbit, direction, phase = request.displacement.x - request.radius, -1, 0
    }
    center := request.start_position + geometry.Vector3{
        orbit * math.cos(parameter + 0.4), orbit * math.sin(parameter + 0.4), 0}
    angle := 0.7 + phase + direction * orbit / request.radius * parameter
    tracer := center + geometry.Vector3{
        request.displacement.y * math.cos(angle),
        request.displacement.y * math.sin(angle), 0}
    expect_rolling_position(t, output.outputs[1].position, center)
    expect_rolling_position(t, output.outputs[2].position, tracer)
    testing.expect_value(t, output.outputs[6].scalar, parameter)
}

// Verify height, visibility, contact, and bounded output contracts at phase boundaries.
@(test)
rolling_phase_outputs_are_bounded_and_visibility_is_caller_owned :: proc(t: ^testing.T) {
    kinds: [8]Modifier_Kind = {
        .Cycloid_Place, .Cycloid_Descend, .Cycloid_Draw, .Cycloid_Rise,
        .Trochoid_Place, .Trochoid_Descend, .Trochoid_Draw, .Trochoid_Rise,
    }
    counts: [4]int = {3, 5, 9, 4}
    for kind, index in kinds {
        request := rolling_test_request(kind)
        if index < 4 {
            request.displacement = {0.05, 0.3, 0}
        }
        request.elapsed = 0.5
        output: Modifier_Output_Buffer
        testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
        testing.expect_value(t, output.count, counts[index % 4])
        testing.expect(t, motion_expanded_count(&output) <= MODIFIER_OUTPUT_CAPACITY)
        if index % 4 != 0 {
            testing.expect_value(t, output.outputs[3].integer, 3 * int(index % 4 == 2))
            testing.expect_value(t, output.outputs[3].flag, index % 4 == 1)
        }
        if index % 4 == 1 || index % 4 == 3 {
            testing.expect(t, math.abs(output.outputs[2].position.z - 0.33) < 1e-6)
        }
        request.duration = 0
        testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
        if index < 4 {
            testing.expect_value(t, output.outputs[0].cycloid_tool.parameter,
                rolling_sample(request).parameter)
        } else {
            testing.expect_value(t, output.outputs[0].trochoid_tool.parameter,
                rolling_sample(request).parameter)
        }
    }
}

// Reject invalid radii, rails, domains, and modes before producing any commands.
@(test)
rolling_invalid_inputs_are_rejected :: proc(t: ^testing.T) {
    request := rolling_test_request(.Cycloid_Draw)
    request.displacement = {0.05, 0.3, 0}
    request.second_position.z = 0.1
    testing.expect(t, !modifier_request_valid(request))
    request.second_position = request.start_position
    testing.expect(t, !modifier_request_valid(request))
    request = rolling_test_request(.Trochoid_Draw)
    request.integer = 2
    testing.expect(t, !modifier_request_valid(request))
    request.integer = 1
    request.radius = request.displacement.x
    testing.expect(t, !modifier_request_valid(request))
    request.radius = 0.05
    request.third_position.z = -3
    testing.expect(t, !modifier_request_valid(request))
    request = rolling_test_request(.Trochoid_Draw)
    request.radius = 0
    testing.expect(t, !modifier_request_valid(request))
}

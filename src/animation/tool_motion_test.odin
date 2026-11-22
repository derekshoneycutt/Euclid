package modifier

import geometry "../core/geometry"
import math "core:math"
import testing "core:testing"

// Compare a sampled vector at the bridge's Float32 precision.
expect_motion_position :: proc(t: ^testing.T, actual, expected: geometry.Vector3) {
    for index in 0..<3 {
        testing.expect(t, math.abs(actual[index] - expected[index]) < 1e-6)
    }
}

// Count expanded effects, not merely the compact radial marker.
motion_expanded_count :: proc(output: ^Modifier_Output_Buffer) -> int {
    count := output.count
    for index in 0..<output.count {
        if output.outputs[index].kind == .Emit_Radial_Trail {
            count += RADIAL_TRAIL_SAMPLES - 1
        }
    }
    return count
}

// Verify fixed-length tilt, timed cone, and drag endpoints without Julia math.
@(test)
native_pen_motion_intermediate_samples :: proc(t: ^testing.T) {
    request: Modifier_Request = {
        kind = .Pen_Tilt,
        second_entity = 1,
        elapsed = 0.5,
        duration = 1,
        start_position = {0.2, 0.3, 0.1},
        second_position = {0.6, 0.3, 0.1},
        radius = 0.35,
        angle = 0,
        brush = f32(math.PI / 2),
    }
    output: Modifier_Output_Buffer
    testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
    length := 0.35 * math.sin(f32(math.PI / 4))
    expect_motion_position(t, output.outputs[1].position,
        geometry.Vector3{0.2 + length, 0.3, 0.1 + length})
    request.kind = .Pen_Cone
    request.scalar = f32(math.PI)
    testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
    expect_motion_position(t, output.outputs[1].position,
        geometry.Vector3{0.2, 0.65, 0.1})
    testing.expect_value(t, output.outputs[2].kind, Modifier_Output_Kind.Set_Tool_Visible)
    request.kind = .Pen_Drag
    request.scalar = 0
    testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
    expect_motion_position(t, output.outputs[0].position, geometry.Vector3{0.4, 0.3, 0.1})
    testing.expect_value(t, output.count, 4)
}

// Verify pen transfer height clamping, periods, completion, and floor-only strikes.
@(test)
native_pen_transfer_height_and_strikes :: proc(t: ^testing.T) {
    request: Modifier_Request = {
        kind = .Pen_Transfer,
        second_entity = 1,
        duration = 1,
        start_position = {0.2, 0.3, 0.1},
        second_position = {0.6, 0.3, 0.3},
        radius = 0.35,
        scalar = 2,
        integer = 1,
        flag = true,
    }
    output: Modifier_Output_Buffer
    request.elapsed = 0.5
    testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
    expect_motion_position(t, output.outputs[0].position, geometry.Vector3{0.4, 0.3, 1.2})
    testing.expect_value(t, output.count, 3)
    testing.expect_value(t, output.outputs[2].kind, Modifier_Output_Kind.Set_Tool_Active)
    request.elapsed = 100
    testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
    expect_motion_position(t, output.outputs[0].position, request.second_position)
    request.start_position.z = 0
    request.elapsed = 0
    testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
    testing.expect_value(t, output.count, 4)
    testing.expect_value(t, output.outputs[3].position.z, f32(0))
}

// Verify crossed joints choose the outside detour and keep authored start heights.
@(test)
native_compass_crossing_transfer_samples :: proc(t: ^testing.T) {
    request: Modifier_Request = {
        kind = .Compass_Transfer,
        entity = 2,
        second_entity = 3,
        elapsed = 0.5,
        duration = 1,
        start_position = {0.2, 0.4, 0.1},
        second_position = {0.8, 0.4, 0.9},
        third_position = {0.5, 0.3, 0.2},
        displacement = {0.5, 0.5, 0.8},
        scalar = 0.2,
        integer = 1,
        flag = true,
    }
    output: Modifier_Output_Buffer
    testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
    span := math.hypot(f32(0.3), f32(0.1))
    expect_motion_position(t, output.outputs[0].position,
        geometry.Vector3{0.5, 0.4 + span * 0.15, 0.3})
    expect_motion_position(t, output.outputs[1].position, geometry.Vector3{0.5, 0.4, 0.4})
    request.elapsed = 1
    testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
    testing.expect(t, math.abs(output.outputs[0].position.z - 0.1) < 1e-6)
    request.elapsed = 0
    request.start_position.z = 0
    testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
    testing.expect_value(t, output.count, 5)
    testing.expect_value(t, output.outputs[4].position.z, f32(0.2))
}

// Verify directed highlights do not mutate marker geometry or enable sweep contacts.
@(test)
native_compass_highlight_effect_expansion :: proc(t: ^testing.T) {
    request: Modifier_Request = {
        kind = .Compass_Highlight,
        entity = 2,
        second_entity = 3,
        elapsed = 0.5,
        duration = 1,
        start_position = {0.5, 0.5, 0.1},
        second_position = {0.7, 0.5, 0},
        radius = 0.2,
        angle = -f32(math.PI),
    }

    output: Modifier_Output_Buffer
    testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
    expect_motion_position(t, output.outputs[1].position, geometry.Vector3{0.5, 0.3, 0})
    testing.expect_value(t, output.outputs[1].integer, 0)
    testing.expect_value(t, motion_expanded_count(&output), 4)
    request.flag = true
    testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
    testing.expect_value(t, motion_expanded_count(&output), 12)
    testing.expect_value(t, output.outputs[3].kind,
        Modifier_Output_Kind.Emit_Radial_Trail)
    request.kind = .Draw_Filled_Circle
    request.entity = 10
    request.second_entity = 2
    request.third_entity = 3
    request.flag = false
    testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
    testing.expect_value(t, motion_expanded_count(&output), 16)
    testing.expect_value(t, output.outputs[7].kind,
        Modifier_Output_Kind.Emit_Radial_Trail)
}

// Verify crossing edge cases choose the other joint and avoid zero-length detours.
@(test)
native_compass_detour_edge_cases :: proc(t: ^testing.T) {
    testing.expect(t, xy_segments_intersect({0, 0, 0}, {1, 0, 0},
        {0.5, 0, 0}, {2, 0, 0}))
    testing.expect(t, !xy_segments_intersect({0, 0, 0}, {1, 0, 0},
        {0, 1, 0}, {1, 1, 0}))
    position: geometry.Vector3 = {0.5, 0.4, 0}
    compass_detour(&position, {position, position}, {{0, 0, 0}, {1, 1, 0}}, 0.5)
    testing.expect_value(t, position, geometry.Vector3{0.5, 0.4, 0})
    request: Modifier_Request = {
        kind = .Compass_Transfer,
        entity = 2,
        second_entity = 3,
        elapsed = 0.5,
        duration = 1,
        start_position = {0.5, 0.3, 0},
        second_position = {0.5, 0.5, 0},
        third_position = {0.2, 0.4, 0},
        displacement = {0.8, 0.4, 0},
        scalar = 0.2,
        integer = 1,
    }
    first, second := compass_transfer_positions(request)
    testing.expect_value(t, first, geometry.Vector3{0.5, 0.4, 0.2})
    testing.expect(t, second.y > first.y)
}

// Reject nonfinite copied inputs before a marker can reach canonical state.
@(test)
native_motion_nonfinite_inputs_reject :: proc(t: ^testing.T) {
    request: Modifier_Request = {
        kind = .Pen_Transfer,
        second_entity = 1,
        radius = 0.35,
    }
    output: Modifier_Output_Buffer
    request.scalar = transmute(f32)u32(0x7f800000)
    testing.expect_value(t, evaluate_modifier(request, &output),
        Modifier_Status.Invalid_Argument)
    testing.expect_value(t, output.count, 0)
    request.scalar = 0
    request.second_position.x = transmute(f32)u32(0x7fc00000)
    testing.expect_value(t, evaluate_modifier(request, &output),
        Modifier_Status.Invalid_Argument)
}

// Verify stroke phase boundaries and preserve the legacy two-trail drag emission.
@(test)
native_highlight_and_stroke_boundaries :: proc(t: ^testing.T) {
    request: Modifier_Request = {
        kind = .Pen_Stroke,
        duration = 1,
        start_position = {0.2, 0.3, 0},
        second_position = {0.6, 0.3, 0},
        radius = 0.35,
        angle = f32(math.PI / 3),
        scalar = 6,
    }
    output: Modifier_Output_Buffer
    samples: [5]f32 = {0, 0.15, 0.5, 0.85, 100}
    for sample in samples {
        request.elapsed = sample
        testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
        if sample >= 0.15 && sample < 0.85 {
            testing.expect_value(t, output.count, 6)
            testing.expect_value(t, output.outputs[5].integer, 0)
        } else {
            testing.expect_value(t, output.count, 3)
        }
    }
    request.kind = .Pen_Highlight_Point
    request.elapsed = 0.5
    testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
    testing.expect_value(t, output.count, 5)
    testing.expect_value(t, output.outputs[4].integer, 1)
}

// Verify extensions preserve their original endpoint and measured maximum expansion.
@(test)
native_extension_intermediate_geometry :: proc(t: ^testing.T) {
    request: Modifier_Request = {
        kind = .Extend_Line,
        entity = 10,
        second_entity = 11,
        third_entity = 12,
        elapsed = 0.5,
        duration = 1,
        start_position = {0.4, 0.3, 0},
        second_position = {0.6, 0.3, 0},
        third_position = {0.2, 0.3, 0},
        radius = 0.35,
        angle = f32(math.PI / 3),
        brush = 0.01,
    }
    output: Modifier_Output_Buffer
    testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
    testing.expect_value(t, output.count, 11)
    expect_motion_position(t, output.outputs[6].position, request.third_position)
    expect_motion_position(t, output.outputs[7].position, geometry.Vector3{0.5, 0.3, 0})
}

// Verify both hosts retain exact completed and hidden future geometry across a corner.
@(test)
native_two_segment_frontiers :: proc(t: ^testing.T) {
    request: Modifier_Request = {
        kind = .Two_Segment_Stroke,
        entity = 10,
        second_entity = 11,
        third_entity = 12,
        duration = 1,
        start_position = {0.2, 0.3, 0},
        second_position = {0.4, 0.3, 0},
        third_position = {0.4, 0.5, 0},
        radius = 0.35,
        angle = f32(math.PI / 3),
    }
    samples: [4]f32 = {0.325, 0.5, 0.675, 1}
    output: Modifier_Output_Buffer
    for sample in samples {
        request.elapsed = sample
        request.flag = false
        testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
        testing.expect(t, output.count <= 9)
        request.flag = true
        testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
        testing.expect_value(t, output.count, 5)
        testing.expect_value(t, output.outputs[4].flag, sample > 0.5)
        if sample <= 0.5 {
            expect_motion_position(t, output.outputs[1].position, request.second_position)
        } else if sample < 1 {
            expect_motion_position(t, output.outputs[1].position,
                geometry.Vector3{0.4, 0.4, 0})
        } else {
            expect_motion_position(t, output.outputs[1].position, request.third_position)
        }
    }
}

// Verify reflected marker intermediate and final projected interior geometry.
@(test)
native_reflected_marker_samples :: proc(t: ^testing.T) {
    request: Modifier_Request = {
        kind = .Reflect_Angle_Marker,
        entity = 10,
        duration = 1,
        start_position = {0, 0, 0.1},
        second_position = {0.2, 0, 0.1},
        third_position = {0, 0.2, 0.1},
        axis_b = {1, 0, 0},
        flag = true,
    }
    output: Modifier_Output_Buffer
    samples: [3]f32 = {0, 0.25, 1}
    for sample in samples {
        request.elapsed = sample
        testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
        expect_motion_position(t, output.outputs[0].position, request.start_position)
        testing.expect(t, output.outputs[1].arc_sweep <= f32(math.PI))
        testing.expect(t, math.abs(output.outputs[1].arc_sweep -
            f32(math.PI / 2)) < 1e-6)
    }
    request.axis_b = request.axis_a
    testing.expect_value(t, evaluate_modifier(request, &output),
        Modifier_Status.Invalid_Argument)
    request.axis_b = {1, 0, 0.1}
    testing.expect_value(t, evaluate_modifier(request, &output),
        Modifier_Status.Invalid_Argument)
}

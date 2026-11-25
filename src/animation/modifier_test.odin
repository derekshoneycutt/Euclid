package modifier

import testing "core:testing"
import geometry "../core/geometry"
import math "core:math"

// Verify explicit-time native modifier identity and position evaluation.
@(test)
modifier_identity_and_position_samples :: proc(t: ^testing.T) {
    identity: Modifier_Request = {
        kind = .Identity,
    }
    output: Modifier_Output_Buffer = {}
    testing.expect_value(t, evaluate_modifier(identity, &output), Modifier_Status.Ok)
    testing.expect_value(t, output.count, 0)

    request: Modifier_Request = {
        kind = .Set_Point_Position,
        entity = 7,
        elapsed = 0.25,
        duration = 1,
        start_position = {1, 2, 3},
        displacement = {4, 4, 4},
    }
    testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
    testing.expect_value(t, output.count, 1)
    testing.expect_value(t, output.outputs[0].entity, u64(7))
    testing.expect_value(t, output.outputs[0].position,
        geometry.Vector3{2, 3, 4})

    request.elapsed = 100
    testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
    testing.expect_value(t, output.outputs[0].position,
        geometry.Vector3{5, 6, 7})

    request.elapsed = 0.5
    request.duration = 0
    testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
    testing.expect_value(t, output.outputs[0].position,
        geometry.Vector3{5, 6, 7})

    request.elapsed = -1
    testing.expect_value(t, evaluate_modifier(request, &output),
        Modifier_Status.Invalid_Argument)
}

// Verify native pen and circle tool lock parity.
@(test)
modifier_tool_and_construction_samples :: proc(t: ^testing.T) {
    output: Modifier_Output_Buffer = {}
    pen: Modifier_Request = {
        kind = .Pen_Descend,
        entity = 10,
        second_entity = 11,
        elapsed = 0.5,
        duration = 1,
        start_position = {1, 2, 0},
        second_position = {1, 2, 0},
        scalar = 2,
        brush = 0.35,
    }
    testing.expect_value(t, evaluate_modifier(pen, &output), Modifier_Status.Ok)
    testing.expect_value(t, output.count, 3)
    testing.expect_value(t, output.outputs[1].kind,
        Modifier_Output_Kind.Set_Tool_Position)
    testing.expect_value(t, output.outputs[2].kind,
        Modifier_Output_Kind.Set_Tool_Style)
    testing.expect(t, output.outputs[2].flag)
    testing.expect_value(t, output.outputs[0].position,
        geometry.Vector3{1, 2, 1})
    testing.expect_value(t, output.outputs[1].position,
        geometry.Vector3{1, 2, 1.35})

    circle: Modifier_Request = {
        kind = .Draw_Circle,
        entity = 20,
        second_entity = 21,
        third_entity = 22,
        elapsed = 0.5,
        duration = 1,
        start_position = {0, 0, 0},
        second_position = {1, 0, 0},
        angle = f32(2 * math.PI),
        radius = 1,
        brush = 0.1,
        color_packed = 0xff0000ff,
    }
    testing.expect_value(t, evaluate_modifier(circle, &output), Modifier_Status.Ok)
    testing.expect(t, output.count >= 5)
    testing.expect(t, output.outputs[3].kind == .Set_Shape_Arc)
    testing.expect_value(t, output.outputs[3].arc_sweep,
        f32(math.PI))
    testing.expect(t, output.outputs[0].kind == .Set_Tool_Lock)
    testing.expect(t, output.outputs[0].flag)
}

// Verify native arbitrary-axis rotation parity.
@(test)
modifier_rotation_sample :: proc(t: ^testing.T) {
    output: Modifier_Output_Buffer = {}
    rotation: Modifier_Request = {
        kind = .Rotate_Point,
        entity = 30,
        elapsed = 0.25,
        duration = 1,
        start_position = {1, 0, 0},
        axis_a = {0, 0, 0},
        axis_b = {0, 0, 1},
        angle = f32(math.PI),
    }
    testing.expect_value(t, evaluate_modifier(rotation, &output), Modifier_Status.Ok)
    testing.expect_value(t, output.count, 1)
    testing.expect(t, math.abs(output.outputs[0].position.x -
        0.70710678) < 1e-5)
    testing.expect(t, math.abs(output.outputs[0].position.y -
        0.70710678) < 1e-5)
}

// Verify highlight phase transitions and same-sample apparatus retirement.
modifier_terminal_highlight_sequences :: proc(t: ^testing.T) {
    output: Modifier_Output_Buffer
    pen: Modifier_Request = {
        kind = .Pen_Highlight,
        second_entity = 1,
        duration = 1,
        start_position = {0, 0, 0},
        second_position = {1, 0, 0},
        radius = 0.35,
        angle = f32(math.PI / 3),
        color_packed = 0xff00ff00,
    }
    testing.expect_value(t, evaluate_modifier(pen, &output), Modifier_Status.Ok)
    testing.expect_value(t, output.outputs[0].position,
        geometry.Vector3{0, 0, 1.4})
    pen.elapsed = 1
    testing.expect_value(t, evaluate_modifier(pen, &output), Modifier_Status.Ok)
    testing.expect_value(t, output.outputs[0].position,
        geometry.Vector3{0, 0, 1.4})
    testing.expect_value(t, output.outputs[output.count - 1].kind,
        Modifier_Output_Kind.Set_Tool_Visible)
    testing.expect_value(t, output.outputs[output.count - 1].flag, false)

    compass: Modifier_Request = {
        kind = .Compass_Highlight_Sequence,
        entity = 2,
        second_entity = 3,
        duration = 1,
        start_position = {0, 0, 0},
        second_position = {1, 0, 0},
        angle = f32(math.PI / 2),
        radius = 1,
        color_packed = 0xff00ff00,
    }
    compass.elapsed = 0.65
    testing.expect_value(t,
        evaluate_modifier(compass, &output), Modifier_Status.Ok)
    testing.expect(t, math.abs(output.outputs[1].position.x -
        0.70710678) < 1e-5)
    testing.expect(t, math.abs(output.outputs[1].position.y -
        0.70710678) < 1e-5)
    compass.elapsed = 1
    testing.expect_value(t,
        evaluate_modifier(compass, &output), Modifier_Status.Ok)
    testing.expect_value(t, output.outputs[output.count - 1].kind,
        Modifier_Output_Kind.Set_Tool_Visible)
    testing.expect_value(t, output.outputs[output.count - 1].flag, false)
}

package modifier

import "core:math"
import "core:math/linalg"
import "core:testing"

// Check signed paths, initial-plane composition, exact jumps and invalid admission.
@(test)
native_orientation_preserves_world_rotation_path :: proc(t: ^testing.T) {
    request: Modifier_Request = {
        kind = .Rotate_Shape_Orientation,
        entity = 1,
        duration = 1,
        axis_b = {1, 0, 0},
        angle = 4 * math.PI,
        scalar = 1,
    }
    output: Modifier_Output_Buffer
    for elapsed in ([?]f32{0, 0.125, 0.25, 0.5, 1, 2}) {
        request.elapsed = elapsed
        testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
        angle := 4 * f32(math.PI) * clamp(elapsed, 0, 1)
        normal := linalg.mul(output.outputs[0].orientation, [3]f32{0, 0, 1})
        testing.expect(t, linalg.length(normal -
            [3]f32{0, -math.sin(angle), math.cos(angle)}) < 0.000002)
    }
    request.angle = -math.PI
    request.elapsed = 0.5
    request.displacement = {0, 0, 1}
    request.scalar = 0
    testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
    normal := linalg.mul(output.outputs[0].orientation, [3]f32{0, 0, 1})
    testing.expect(t, linalg.length(normal - [3]f32{0, 1, 0}) < 0.000002)
    request.duration = 0
    testing.expect_value(t, evaluate_modifier(request, &output), Modifier_Status.Ok)
    testing.expect(t, math.abs(output.outputs[0].orientation.y - 1) < 0.000002)
    request.scalar = 2
    testing.expect_value(t,
        evaluate_modifier(request, &output), Modifier_Status.Invalid_Argument)
    request.scalar = 0
    request.axis_b = {}
    testing.expect_value(t,
        evaluate_modifier(request, &output), Modifier_Status.Invalid_Argument)
}

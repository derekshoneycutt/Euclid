package modifier

import "core:math"
import "core:math/linalg"

// Require a live identity, directed axis and unit activation-time XYZW orientation.
orientation_request_valid :: proc(request: Modifier_Request) -> bool {
    initial := quaternion(
        x = request.displacement.x, y = request.displacement.y,
        z = request.displacement.z, w = request.scalar)
    return request.entity != 0 &&
        linalg.length(request.axis_b - request.axis_a) > 0.000001 &&
        math.abs(linalg.dot(initial, initial) - 1) <= 0.0001
}

// Compose the authored world rotation on the left without retaining sampled state.
evaluate_shape_orientation :: proc(
    request: Modifier_Request, output: ^Modifier_Output_Buffer) -> Modifier_Status {
    axis := linalg.normalize(request.axis_b - request.axis_a)
    angle := request.angle * modifier_progress(request.elapsed, request.duration) * 0.5
    sine := math.sin(angle)
    rotation := quaternion(x = axis.x * sine, y = axis.y * sine,
        z = axis.z * sine, w = math.cos(angle))
    initial := quaternion(x = request.displacement.x, y = request.displacement.y,
        z = request.displacement.z, w = request.scalar)
    return modifier_output_append(output, {
        kind = .Set_Shape_Orientation,
        entity = request.entity,
        orientation = linalg.normalize(rotation * initial),
    })
}

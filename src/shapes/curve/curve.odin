package curve

import shapemodel "../model"

import "core:math"

Vector3 :: shapemodel.Vector3

TROCHOID_BASE_SEGMENTS :: 48
TROCHOID_MAX_SEGMENTS :: 192
TROCHOID_MAX_VERTICES :: TROCHOID_MAX_SEGMENTS + 1
TROCHOID_CHORD_ERROR :: f32(0.0005)
TROCHOID_MAX_PARAMETER_STEP :: f32(math.PI / 24)
CYCLOID_BASE_SEGMENTS :: 48
CYCLOID_MAX_SEGMENTS :: 192
CYCLOID_MAX_VERTICES :: CYCLOID_MAX_SEGMENTS + 1
CYCLOID_CHORD_ERROR :: f32(0.0005)
CYCLOID_MAX_PARAMETER_STEP :: f32(math.PI / 24)

// Report whether bounded explication satisfied every requested subdivision.
Curve_Explication_Status :: enum u8 {
    Complete,
    Capacity_Limited,
    Invalid_Input,
}

// Report the initialized output prefix and its bounded completion status.
Curve_Explication_Result :: struct {
    vertex_count: int,
    status: Curve_Explication_Status,
}

// Resolve the two centers and rolling-body orientation for one guide parameter.
Trochoid_Tool_Pose :: struct {
    fixed_center: Vector3,
    rolling_center: Vector3,
    rolling_orientation: f32,
}

// Resolve the literal rail, rolling circle, and material orientation for one parameter.
Cycloid_Tool_Pose :: struct {
    baseline_start: Vector3,
    baseline_finish: Vector3,
    contact: Vector3,
    rolling_center: Vector3,
    rolling_orientation: f32,
}

// Rotate one planar vector while preserving its z coordinate.
rotate_planar :: #force_inline proc(vector: Vector3, angle: f32) -> Vector3 {
    sine, cosine := math.sincos(angle)
    return {vector.x * cosine - vector.y * sine,
        vector.x * sine + vector.y * cosine, vector.z}
}

// Return the rolling-center orbital radius for one valid circle pair.
trochoid_orbit_radius :: #force_inline proc(
    mode: shapemodel.Shape_Trochoid_Mode, fixed_radius, rolling_radius: f32) -> f32 {
    if mode == .External {
        return fixed_radius + rolling_radius
    }
    return fixed_radius - rolling_radius
}

// Return one rolling circle's contact-aligned material orientation.
trochoid_rolling_orientation :: #force_inline proc(
    mode: shapemodel.Shape_Trochoid_Mode,
    orbit_radius, rolling_radius, parameter, orientation_offset: f32) -> f32 {
    ratio := orbit_radius / rolling_radius
    if mode == .External {
        return orientation_offset + math.PI + ratio * parameter
    }
    return orientation_offset - ratio * parameter
}

// Evaluate one point from a validated canonical trochoid description.
trochoid_point :: proc(
    center: Vector3, value: shapemodel.Shape_Trochoid, parameter: f32) -> Vector3 {
    orbit_radius := trochoid_orbit_radius(
        value.mode, value.fixed_radius, value.rolling_radius)
    orbit := rotate_planar(
        {orbit_radius * math.cos(parameter), orbit_radius * math.sin(parameter), 0},
        value.rotation)
    tracer_angle := trochoid_rolling_orientation(value.mode, orbit_radius,
        value.rolling_radius, parameter, value.rotation + value.tracer_phase)
    tracer := Vector3{value.tracer_distance * math.cos(tracer_angle),
        value.tracer_distance * math.sin(tracer_angle), 0}
    return center + orbit + tracer
}

// Resolve one validated two-ring guide into render-ready planar pose values.
trochoid_tool_pose :: proc(
    center: Vector3, value: shapemodel.Shape_Trochoid_Tool) -> Trochoid_Tool_Pose {
    orbit_radius := trochoid_orbit_radius(
        value.mode, value.fixed_radius, value.rolling_radius)
    orbit := rotate_planar({orbit_radius * math.cos(value.parameter),
        orbit_radius * math.sin(value.parameter), 0}, value.rotation)
    orientation := trochoid_rolling_orientation(value.mode, orbit_radius,
        value.rolling_radius, value.parameter,
        value.rotation + value.orientation_phase)
    return {fixed_center = center, rolling_center = center + orbit,
        rolling_orientation = orientation}
}

// Resolve one literal cycloid rail's unit tangent and upward planar normal.
cycloid_line_basis :: proc(first, second: Vector3) -> (Vector3, Vector3) {
    delta := second - first
    inverse_length := 1 / math.sqrt(delta.x * delta.x + delta.y * delta.y)
    tangent := Vector3{delta.x * inverse_length, delta.y * inverse_length, 0}
    return tangent, {-tangent.y, tangent.x, 0}
}

// Resolve the centered no-slip contact point for one rolling parameter.
cycloid_contact_point :: proc(
    first, second: Vector3,
    rolling_radius, parameter_midpoint, parameter: f32) -> Vector3 {
    tangent, _ := cycloid_line_basis(first, second)
    midpoint := (first + second) * 0.5
    return midpoint + tangent * rolling_radius * (parameter - parameter_midpoint)
}

// Evaluate one point from a validated literal-line cycloid description.
cycloid_point :: proc(first, second: Vector3,
    value: shapemodel.Shape_Cycloid, parameter: f32) -> Vector3 {
    tangent, normal := cycloid_line_basis(first, second)
    parameter_midpoint := (value.parameter_start + value.parameter_finish) * 0.5
    contact := cycloid_contact_point(
        first, second, value.rolling_radius, parameter_midpoint, parameter)
    center := contact + normal * value.rolling_radius
    angle := parameter + value.tracer_phase
    return center - tangent * value.tracer_distance * math.sin(angle) -
        normal * value.tracer_distance * math.cos(angle)
}

// Resolve one validated line-and-circle guide into render-ready pose values.
cycloid_tool_pose :: proc(first, second: Vector3,
    value: shapemodel.Shape_Cycloid_Tool) -> Cycloid_Tool_Pose {
    tangent, normal := cycloid_line_basis(first, second)
    parameter_midpoint := (value.parameter_start + value.parameter_finish) * 0.5
    contact := cycloid_contact_point(
        first, second, value.rolling_radius, parameter_midpoint, value.parameter)
    line_angle := math.atan2(tangent.y, tangent.x)
    orientation := line_angle - math.PI / 2 - value.parameter +
        value.orientation_phase
    return {first, second, contact, contact + normal * value.rolling_radius,
        orientation}
}

// Return whether one cycloid interval needs another midpoint sample.
cycloid_segment_needs_refinement :: proc(first, second: Vector3,
    value: shapemodel.Shape_Cycloid, parameter_a, parameter_b: f32) -> bool {
    if math.abs(parameter_b - parameter_a) > CYCLOID_MAX_PARAMETER_STEP {
        return true
    }
    midpoint := (parameter_a + parameter_b) * 0.5
    first_point := cycloid_point(first, second, value, parameter_a)
    second_point := cycloid_point(first, second, value, parameter_b)
    midpoint_point := cycloid_point(first, second, value, midpoint)
    chord_midpoint := (first_point + second_point) * 0.5
    error := midpoint_point - chord_midpoint
    return error.x * error.x + error.y * error.y >
        CYCLOID_CHORD_ERROR * CYCLOID_CHORD_ERROR
}

// Build deterministic adaptive boundaries over one complete cycloid domain.
cycloid_full_domain_parameters :: proc(first, second: Vector3,
    value: shapemodel.Shape_Cycloid,
    parameters: ^[CYCLOID_MAX_VERTICES]f32) -> (int, bool) {
    for index in 0..=CYCLOID_BASE_SEGMENTS {
        progress := f32(index) / f32(CYCLOID_BASE_SEGMENTS)
        parameters[index] = math.lerp(
            value.parameter_start, value.parameter_finish, progress)
    }
    count := CYCLOID_BASE_SEGMENTS + 1
    capacity_limited := false
    for index := 0; index < count - 1; {
        if !cycloid_segment_needs_refinement(
            first, second, value, parameters[index], parameters[index + 1]) {
            index += 1
            continue
        }
        if count >= CYCLOID_MAX_VERTICES {
            capacity_limited = true
            index += 1
            continue
        }
        for destination := count; destination > index + 1; destination -= 1 {
            parameters[destination] = parameters[destination - 1]
        }
        parameters[index + 1] =
            (parameters[index] + parameters[index + 1]) * 0.5
        count += 1
    }
    return count, capacity_limited
}

// Explicate the revealed cycloid interval from stable full-domain boundaries.
cycloid_explicate :: proc(first, second: Vector3,
    value: shapemodel.Shape_Cycloid,
    vertices: []Vector3) -> Curve_Explication_Result {
    if !shapemodel.shape_cycloid_is_valid(value) ||
        !shapemodel.shape_cycloid_line_is_valid(first, second,
            value.rolling_radius, value.parameter_start, value.parameter_finish) ||
        len(vertices) < CYCLOID_MAX_VERTICES {
        return {status = .Invalid_Input}
    }
    parameters: [CYCLOID_MAX_VERTICES]f32
    parameter_count, capacity_limited := cycloid_full_domain_parameters(
        first, second, value, &parameters)
    vertex_count := 0
    for parameter in parameters[:parameter_count] {
        if !parameter_precedes_frontier(value.parameter_start,
            value.parameter_finish, parameter, value.draw_parameter) {
            break
        }
        vertices[vertex_count] = cycloid_point(first, second, value, parameter)
        vertex_count += 1
    }
    final_parameter := parameters[max(vertex_count - 1, 0)]
    if final_parameter != value.draw_parameter {
        vertices[vertex_count] = cycloid_point(
            first, second, value, value.draw_parameter)
        vertex_count += 1
    }
    status := Curve_Explication_Status.Complete
    if capacity_limited {
        status = .Capacity_Limited
    }
    return {vertex_count, status}
}

// Return whether a parameter is no later than the frontier in domain direction.
parameter_precedes_frontier :: #force_inline proc(
    start, finish, parameter, frontier: f32) -> bool {
    if finish > start {
        return parameter <= frontier
    }
    return parameter >= frontier
}

// Return whether one parameter interval needs another midpoint sample.
trochoid_segment_needs_refinement :: proc(
    center: Vector3, value: shapemodel.Shape_Trochoid, first, second: f32) -> bool {
    if math.abs(second - first) > TROCHOID_MAX_PARAMETER_STEP {
        return true
    }
    midpoint := (first + second) * 0.5
    first_point := trochoid_point(center, value, first)
    second_point := trochoid_point(center, value, second)
    midpoint_point := trochoid_point(center, value, midpoint)
    chord_midpoint := (first_point + second_point) * 0.5
    error := midpoint_point - chord_midpoint
    return error.x * error.x + error.y * error.y >
        TROCHOID_CHORD_ERROR * TROCHOID_CHORD_ERROR
}

// Insert one midpoint into an initialized parameter prefix.
insert_parameter_midpoint :: proc(
    parameters: ^[TROCHOID_MAX_VERTICES]f32, count, index: int) {
    for destination := count; destination > index + 1; destination -= 1 {
        parameters[destination] = parameters[destination - 1]
    }
    parameters[index + 1] = (parameters[index] + parameters[index + 1]) * 0.5
}

// Build deterministic adaptive boundaries over the complete directed domain.
trochoid_full_domain_parameters :: proc(
    center: Vector3, value: shapemodel.Shape_Trochoid,
    parameters: ^[TROCHOID_MAX_VERTICES]f32) -> (int, bool) {
    for index in 0..=TROCHOID_BASE_SEGMENTS {
        progress := f32(index) / f32(TROCHOID_BASE_SEGMENTS)
        parameters[index] = math.lerp(
            value.parameter_start, value.parameter_finish, progress)
    }
    count := TROCHOID_BASE_SEGMENTS + 1
    capacity_limited := false
    for index := 0; index < count - 1; {
        if !trochoid_segment_needs_refinement(
            center, value, parameters[index], parameters[index + 1]) {
            index += 1
            continue
        }
        if count >= TROCHOID_MAX_VERTICES {
            capacity_limited = true
            index += 1
            continue
        }
        insert_parameter_midpoint(parameters, count, index)
        count += 1
    }
    return count, capacity_limited
}

// Explicate the revealed interval from stable full-domain adaptive boundaries.
trochoid_explicate :: proc(
    center: Vector3, value: shapemodel.Shape_Trochoid,
    vertices: []Vector3) -> Curve_Explication_Result {
    if !shapemodel.shape_trochoid_is_valid(value) ||
        len(vertices) < TROCHOID_MAX_VERTICES {
        return {status = .Invalid_Input}
    }
    parameters: [TROCHOID_MAX_VERTICES]f32
    parameter_count, capacity_limited := trochoid_full_domain_parameters(
        center, value, &parameters)
    vertex_count := 0
    for parameter in parameters[:parameter_count] {
        if !parameter_precedes_frontier(value.parameter_start,
            value.parameter_finish, parameter, value.draw_parameter) {
            break
        }
        vertices[vertex_count] = trochoid_point(center, value, parameter)
        vertex_count += 1
    }
    final_parameter := parameters[max(vertex_count - 1, 0)]
    if final_parameter != value.draw_parameter {
        vertices[vertex_count] = trochoid_point(center, value, value.draw_parameter)
        vertex_count += 1
    }
    status := Curve_Explication_Status.Complete
    if capacity_limited {
        status = .Capacity_Limited
    }
    return {vertex_count, status}
}
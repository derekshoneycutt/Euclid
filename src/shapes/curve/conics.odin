package curve

import shapemodel "../model"

import "core:math"

CONIC_MAX_SEGMENTS :: 1024
CONIC_MAX_VERTICES :: CONIC_MAX_SEGMENTS + 1
CONIC_CHORD_ERROR :: f32(0.0005)

// Hold the analytically resolved diamond and pen position for one parameter.
Parabola_Tool_Pose :: struct {
    vertex: Vector3,
    focus: Vector3,
    directrix_contact: Vector3,
    diamond_first: Vector3,
    diamond_second: Vector3,
}

// Hold the rails, minimum-radius ticks, and symmetric tips for one parameter.
Hyperbola_Tool_Pose :: struct {
    center: Vector3,
    asymptote_first_start: Vector3,
    asymptote_first_finish: Vector3,
    asymptote_second_start: Vector3,
    asymptote_second_finish: Vector3,
    moving_rail_start: Vector3,
    moving_rail_finish: Vector3,
    tick_first_start: Vector3,
    tick_first_finish: Vector3,
    tick_second_start: Vector3,
    tick_second_finish: Vector3,
    carriage_positive: Vector3,
    carriage_negative: Vector3,
}

// Evaluate the exact rotated parabola point at one finite parameter.
parabola_point :: proc(
    center: Vector3, value: shapemodel.Shape_Parabola, parameter: f32) -> Vector3 {
    local: Vector3 = {value.focal_distance * parameter * parameter,
        2 * value.focal_distance * parameter, 0}
    return center + rotate_planar(local, value.rotation)
}

// Evaluate one exact rotated branch while keeping its explicit sign.
hyperbola_point :: proc(
    center: Vector3,
    value: shapemodel.Shape_Hyperbola,
    parameter: f32, branch: i32 = 1) -> Vector3 {
    assert(branch == 1 || branch == -1)
    sign := f32(branch)
    local: Vector3 = {sign * value.semimajor * math.cosh(parameter),
        sign * value.semiminor * math.sinh(parameter), 0}
    return center + rotate_planar(local, value.rotation)
}

// Resolve a nonflat equal-link diamond whose extended guide passes through P.
parabola_tool_pose :: proc(
    center: Vector3, value: shapemodel.Shape_Parabola_Tool) -> Parabola_Tool_Pose {
    f, t := value.focal_distance, value.parameter
    vertex_local: Vector3 = {f * t * t, 2 * f * t, 0}
    focus_local: Vector3 = {f, 0, 0}
    directrix_local: Vector3 = {-f, 2 * f * t, 0}
    half_diagonal := f * math.sqrt(1 + t * t)
    offset := math.sqrt(value.link_length * value.link_length -
        half_diagonal * half_diagonal)
    inverse_norm := 1 / math.sqrt(1 + t * t)
    normal: Vector3 = {t * inverse_norm, inverse_norm, 0}
    midpoint: Vector3 = {0, f * t, 0}
    first_local := midpoint + normal * offset
    second_local := midpoint - normal * offset
    return {
        vertex = center + rotate_planar(vertex_local, value.rotation),
        focus = center + rotate_planar(focus_local, value.rotation),
        directrix_contact = center + rotate_planar(directrix_local, value.rotation),
        diamond_first = center + rotate_planar(first_local, value.rotation),
        diamond_second = center + rotate_planar(second_local, value.rotation),
    }
}

// Resolve finite X rails and both symmetric analytic carriages.
hyperbola_tool_pose :: proc(
    center: Vector3, value: shapemodel.Shape_Hyperbola_Tool) -> Hyperbola_Tool_Pose {
    a, b := value.semimajor, value.semiminor
    rail := value.rail_half_length
    root := math.sqrt(a * a + b * b)
    first_direction: Vector3 = {a / root, b / root, 0}
    second_direction: Vector3 = {a / root, -b / root, 0}
    positive_local: Vector3 = {a * math.cosh(value.parameter),
        b * math.sinh(value.parameter), 0}
    radius := math.sqrt(positive_local.x * positive_local.x +
        positive_local.y * positive_local.y)
    moving_direction := positive_local / radius
    normal: Vector3 = {-moving_direction.y, moving_direction.x, 0}
    positive := center + rotate_planar(positive_local, value.rotation)
    negative := center - rotate_planar(positive_local, value.rotation)
    moving_vector := rotate_planar(moving_direction * rail, value.rotation)
    tick_offset := rotate_planar(moving_direction * a, value.rotation)
    tick_half := rotate_planar(normal * (a * 0.045), value.rotation)
    return {
        center = center,
        asymptote_first_start =
            center - rotate_planar(first_direction * rail, value.rotation),
        asymptote_first_finish =
            center + rotate_planar(first_direction * rail, value.rotation),
        asymptote_second_start =
            center - rotate_planar(second_direction * rail, value.rotation),
        asymptote_second_finish =
            center + rotate_planar(second_direction * rail, value.rotation),
        moving_rail_start = center - moving_vector,
        moving_rail_finish = center + moving_vector,
        tick_first_start = center + tick_offset - tick_half,
        tick_first_finish = center + tick_offset + tick_half,
        tick_second_start = center - tick_offset - tick_half,
        tick_second_finish = center - tick_offset + tick_half,
        carriage_positive = positive,
        carriage_negative = negative,
    }
}

// Measure midpoint deviation to decide whether an analytic interval needs subdivision.
conic_segment_needs_refinement :: proc(first, second, midpoint: Vector3) -> bool {
    chord_midpoint := (first + second) * 0.5
    error := midpoint - chord_midpoint
    return error.x * error.x + error.y * error.y >
        CONIC_CHORD_ERROR * CONIC_CHORD_ERROR
}

// Insert a parameter midpoint while keeping the bounded directed grid ordered.
conic_insert_midpoint :: proc(parameters: []f32, count, index: int) {
    for destination := count; destination > index + 1; destination -= 1 {
        parameters[destination] = parameters[destination - 1]
    }
    parameters[index + 1] = (parameters[index] + parameters[index + 1]) * 0.5
}

// Build a uniformly seeded directed parameter grid without allocating.
conic_seed_parameters :: proc(parameters: []f32, start, finish: f32) -> int {
    for index in 0..=48 {
        parameters[index] = math.lerp(start, finish, f32(index) / 48)
    }
    return 49
}

// Refine each parabola segment until chord error is bounded or capacity is explicit.
parabola_refine_parameters :: proc(
    center: Vector3, value: shapemodel.Shape_Parabola,
    parameters: []f32, count: int) -> (int, bool) {
    capacity_limited := false
    current_count := count
    index := 0
    for index < current_count - 1 {
        first := parabola_point(center, value, parameters[index])
        second := parabola_point(center, value, parameters[index + 1])
        midpoint := parabola_point(
            center, value, (parameters[index] + parameters[index + 1]) * 0.5)
        if !conic_segment_needs_refinement(first, second, midpoint) {
            index += 1
            continue
        }
        if current_count >= CONIC_MAX_VERTICES {
            capacity_limited = true
            index += 1
            continue
        }
        conic_insert_midpoint(parameters, current_count, index)
        current_count += 1
    }
    return current_count, capacity_limited
}

// Refine one hyperbola branch without combining it with its reflected branch.
hyperbola_refine_parameters :: proc(
    center: Vector3, value: shapemodel.Shape_Hyperbola,
    parameters: []f32, count: int) -> (int, bool) {
    capacity_limited := false
    current_count := count
    index := 0
    for index < current_count - 1 {
        first := hyperbola_point(center, value, parameters[index])
        second := hyperbola_point(center, value, parameters[index + 1])
        midpoint := hyperbola_point(
            center, value, (parameters[index] + parameters[index + 1]) * 0.5)
        if !conic_segment_needs_refinement(first, second, midpoint) {
            index += 1
            continue
        }
        if current_count >= CONIC_MAX_VERTICES {
            capacity_limited = true
            index += 1
            continue
        }
        conic_insert_midpoint(parameters, current_count, index)
        current_count += 1
    }
    return current_count, capacity_limited
}

// Resolve one parabola's sampled domain and exact interpolated frontier.
parabola_explicate :: proc(
    center: Vector3, value: shapemodel.Shape_Parabola,
    vertices: []Vector3) -> Curve_Explication_Result {
    if !shapemodel.shape_parabola_is_valid(value) || len(vertices) < CONIC_MAX_VERTICES {
        return {
            status = .Invalid_Input,
            topology = .Open,
        }
    }
    parameters: [CONIC_MAX_VERTICES]f32
    seed_count := conic_seed_parameters(
        parameters[:], value.parameter_start, value.parameter_finish)
    count, limited := parabola_refine_parameters(center, value, parameters[:], seed_count)
    written := 0
    for index in 0..<count {
        parameter := parameters[index]
        if !parameter_precedes_frontier(value.parameter_start, value.parameter_finish,
            parameter, value.draw_parameter) {
            break
        }
        vertices[written] = parabola_point(center, value, parameter)
        written += 1
    }
    if written == 0 || !curve_parameters_match(parameters[max(written - 1, 0)],
        value.draw_parameter) {
        vertices[written] = parabola_point(center, value, value.draw_parameter)
        written += 1
    }
    return {written, curve_explication_status(limited), .Open}
}

// Resolve one hyperbola branch's sampled domain and exact interpolated frontier.
hyperbola_explicate :: proc(
    center: Vector3, value: shapemodel.Shape_Hyperbola,
    vertices: []Vector3, branch: i32) -> Curve_Explication_Result {
    if !shapemodel.shape_hyperbola_is_valid(value) ||
       len(vertices) < CONIC_MAX_VERTICES || (branch != 1 && branch != -1) {
        return {
            status = .Invalid_Input,
            topology = .Open,
        }
    }
    parameters: [CONIC_MAX_VERTICES]f32
    seed_count := conic_seed_parameters(
        parameters[:], value.parameter_start, value.parameter_finish)
    count, limited := hyperbola_refine_parameters(
        center, value, parameters[:], seed_count)
    written := 0
    for index in 0..<count {
        parameter := parameters[index]
        if !parameter_precedes_frontier(value.parameter_start, value.parameter_finish,
            parameter, value.draw_parameter) {
            break
        }
        vertices[written] = hyperbola_point(center, value, parameter, branch)
        written += 1
    }
    if written == 0 || !curve_parameters_match(parameters[max(written - 1, 0)],
        value.draw_parameter) {
        vertices[written] = hyperbola_point(
            center, value, value.draw_parameter, branch)
        written += 1
    }
    return {written, curve_explication_status(limited), .Open}
}

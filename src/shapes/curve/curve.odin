package curve

import shapemodel "../model"

import "core:math"

Vector3 :: shapemodel.Vector3

TROCHOID_BASE_SEGMENTS :: 48
TROCHOID_MAX_SEGMENTS :: 512
TROCHOID_MAX_VERTICES :: TROCHOID_MAX_SEGMENTS + 1
TROCHOID_CHORD_ERROR :: f32(0.0005)
TROCHOID_MAX_PARAMETER_STEP :: f32(math.PI / 24)
CYCLOID_BASE_SEGMENTS :: 48
CYCLOID_MAX_SEGMENTS :: 192
CYCLOID_MAX_VERTICES :: CYCLOID_MAX_SEGMENTS + 1
CYCLOID_CHORD_ERROR :: f32(0.0005)
CYCLOID_MAX_PARAMETER_STEP :: f32(math.PI / 24)
CURVE_CUSP_RELATIVE_TOLERANCE :: f32(4e-6)
CURVE_PARAMETER_MATCH_TOLERANCE :: f32(2e-6)

Curve_Point_Kind :: shapemodel.Curve_Point_Kind
Curve_Topology :: shapemodel.Curve_Topology

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
    topology: Curve_Topology,
}

// Hold one directed integer family of analytic cusp parameters.
Curve_Cusp_Sequence :: struct {
    first: int,
    last: int,
    step: int,
    frequency: f64,
    offset: f64,
    valid: bool,
}

// Group aligned directed parameter storage for bounded insertion helpers.
Curve_Parameter_Buffer :: struct {
    parameters: []f32,
    kinds: []Curve_Point_Kind,
    start: f32,
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

// Return whether two positive curve scales agree within floating-point noise.
curve_cusp_scales_match :: #force_inline proc(first, second: f32) -> bool {
    scale := max(math.abs(first), math.abs(second))
    return math.abs(first - second) <= CURVE_CUSP_RELATIVE_TOLERANCE * scale
}

// Return whether two parameters identify the same stable boundary.
curve_parameters_match :: #force_inline proc(first, second: f32) -> bool {
    scale := max(f32(1), max(math.abs(first), math.abs(second)))
    return math.abs(first - second) <= CURVE_PARAMETER_MATCH_TOLERANCE * scale
}

// Build the bounded directed integer range intersecting one cusp equation.
curve_cusp_sequence :: proc(
    start, finish: f32, frequency, offset: f64) -> Curve_Cusp_Sequence {
    lower := min(f64(start), f64(finish))
    upper := max(f64(start), f64(finish))
    first := int(math.ceil((frequency * lower + offset) / math.TAU - 1e-7))
    last := int(math.floor((frequency * upper + offset) / math.TAU + 1e-7))
    if first > last {
        return {}
    }
    if finish < start {
        return {last, first, -1, frequency, offset, true}
    }
    return {first, last, 1, frequency, offset, true}
}

// Return the exact parameter associated with one cusp sequence member.
curve_cusp_parameter :: #force_inline proc(
    sequence: Curve_Cusp_Sequence, member: int) -> f32 {
    return f32((math.TAU * f64(member) - sequence.offset) / sequence.frequency)
}

// Insert or merge one parameter in directed order without weakening cusp intent.
curve_insert_parameter :: proc(buffer: Curve_Parameter_Buffer,
    count: int, parameter: f32,
    kind: Curve_Point_Kind) -> (int, bool) {
    for index in 0..<count {
        if curve_parameters_match(buffer.parameters[index], parameter) {
            if kind == .Cusp {buffer.kinds[index] = .Cusp}
            return count, true
        }
        if parameter_precedes_frontier(buffer.start, buffer.parameters[count - 1],
            parameter, buffer.parameters[index]) {
            if count >= len(buffer.parameters) {return count, false}
            for destination := count; destination > index; destination -= 1 {
                buffer.parameters[destination] = buffer.parameters[destination - 1]
                buffer.kinds[destination] = buffer.kinds[destination - 1]
            }
            buffer.parameters[index] = parameter
            buffer.kinds[index] = kind
            return count + 1, true
        }
    }
    return count, false
}

// Seed mandatory cusp boundaries, retaining a directed prefix on overflow.
curve_seed_cusp_parameters :: proc(parameters: []f32, kinds: []Curve_Point_Kind,
    start, finish: f32, sequence: Curve_Cusp_Sequence) -> (int, bool) {
    parameters[0] = start
    kinds[0] = .Ordinary
    count := 1
    for member := sequence.first;
        sequence.valid && member != sequence.last + sequence.step;
        member += sequence.step {
        parameter := curve_cusp_parameter(sequence, member)
        if curve_parameters_match(parameters[count - 1], parameter) {
            kinds[count - 1] = .Cusp
            continue
        }
        if count >= len(parameters) {return count, true}
        parameters[count] = parameter
        kinds[count] = .Cusp
        count += 1
    }
    if curve_parameters_match(parameters[count - 1], finish) {
        return count, false
    }
    if count >= len(parameters) {return count, true}
    parameters[count] = finish
    kinds[count] = .Ordinary
    return count + 1, false
}

// Classify closure from complete world-space output and endpoint cusp intent.
curve_explication_topology :: proc(vertices: []Vector3, kinds: []Curve_Point_Kind,
    count: int, complete: bool) -> Curve_Topology {
    if !complete || count < 2 {return .Open}
    delta := vertices[count - 1] - vertices[0]
    scale := max(f32(1), max(math.abs(vertices[0].x), math.abs(vertices[0].y)))
    tolerance := CURVE_CUSP_RELATIVE_TOLERANCE * scale
    if delta.x * delta.x + delta.y * delta.y > tolerance * tolerance {
        return .Open
    }
    if len(kinds) >= count && (kinds[0] == .Cusp || kinds[count - 1] == .Cusp) {
        return .Cusp_Closed
    }
    return .Closed
}

// Insert the optional base grid after every mandatory cusp boundary.
curve_insert_base_parameters :: proc(buffer: Curve_Parameter_Buffer,
    count: int, finish: f32, segment_count: int) -> (int, bool) {
    current_count := count
    for index in 1..<segment_count {
        progress := f32(index) / f32(segment_count)
        parameter := math.lerp(buffer.start, finish, progress)
        next_count, inserted := curve_insert_parameter(
            buffer, current_count, parameter, .Ordinary)
        if !inserted {return current_count, true}
        current_count = next_count
    }
    return current_count, false
}

// Map bounded construction pressure to the public explication status.
curve_explication_status :: #force_inline proc(
    capacity_limited: bool) -> Curve_Explication_Status {
    if capacity_limited {return .Capacity_Limited}
    return .Complete
}

// Insert one ordinary midpoint while preserving aligned cusp kinds.
curve_insert_parameter_midpoint :: proc(parameters: []f32,
    kinds: []Curve_Point_Kind, count, index: int) {
    for destination := count; destination > index + 1; destination -= 1 {
        parameters[destination] = parameters[destination - 1]
        kinds[destination] = kinds[destination - 1]
    }
    parameters[index + 1] = (parameters[index] + parameters[index + 1]) * 0.5
    kinds[index + 1] = .Ordinary
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
    parameters: ^[CYCLOID_MAX_VERTICES]f32,
    kinds: ^[CYCLOID_MAX_VERTICES]Curve_Point_Kind) -> (int, bool) {
    sequence: Curve_Cusp_Sequence
    if curve_cusp_scales_match(value.tracer_distance, value.rolling_radius) {
        sequence = curve_cusp_sequence(value.parameter_start,
            value.parameter_finish, 1, f64(value.tracer_phase))
    }
    count, capacity_limited := curve_seed_cusp_parameters(parameters[:], kinds[:],
        value.parameter_start, value.parameter_finish, sequence)
    if capacity_limited {return count, true}
    base_limited: bool
    buffer := Curve_Parameter_Buffer{
        parameters[:], kinds[:], value.parameter_start}
    count, base_limited = curve_insert_base_parameters(
        buffer, count, value.parameter_finish, CYCLOID_BASE_SEGMENTS)
    capacity_limited = capacity_limited || base_limited
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
        curve_insert_parameter_midpoint(parameters[:], kinds[:], count, index)
        count += 1
    }
    return count, capacity_limited
}

// Validate cycloid geometry and aligned output capacity before mutation.
cycloid_explication_is_valid :: proc(first, second: Vector3,
    value: shapemodel.Shape_Cycloid, vertices: []Vector3,
    kinds: []Curve_Point_Kind) -> bool {
    return shapemodel.shape_cycloid_is_valid(value) &&
        shapemodel.shape_cycloid_line_is_valid(first, second,
            value.rolling_radius, value.parameter_start, value.parameter_finish) &&
        len(vertices) >= CYCLOID_MAX_VERTICES &&
        (kinds == nil || len(kinds) >= CYCLOID_MAX_VERTICES)
}

// Explicate a cycloid interval through the shared marked implementation.
cycloid_explicate_internal :: proc(first, second: Vector3,
    value: shapemodel.Shape_Cycloid,
    vertices: []Vector3, output_kinds: []Curve_Point_Kind) -> Curve_Explication_Result {
    if !cycloid_explication_is_valid(
        first, second, value, vertices, output_kinds) {
        return {status = .Invalid_Input}
    }
    parameters: [CYCLOID_MAX_VERTICES]f32
    kinds: [CYCLOID_MAX_VERTICES]Curve_Point_Kind
    parameter_count, capacity_limited := cycloid_full_domain_parameters(
        first, second, value, &parameters, &kinds)
    vertex_count := 0
    for parameter, index in parameters[:parameter_count] {
        if !parameter_precedes_frontier(value.parameter_start,
            value.parameter_finish, parameter, value.draw_parameter) {
            break
        }
        vertices[vertex_count] = cycloid_point(first, second, value, parameter)
        if output_kinds != nil {output_kinds[vertex_count] = kinds[index]}
        vertex_count += 1
    }
    final_parameter := parameters[max(vertex_count - 1, 0)]
    frontier_reached := curve_parameters_match(final_parameter, value.draw_parameter)
    if !frontier_reached &&
        vertex_count < len(vertices) {
        vertices[vertex_count] = cycloid_point(
            first, second, value, value.draw_parameter)
        if output_kinds != nil {output_kinds[vertex_count] = .Ordinary}
        vertex_count += 1
        frontier_reached = true
    }
    status := curve_explication_status(capacity_limited)
    topology := curve_explication_topology(vertices, kinds[:], vertex_count,
        frontier_reached && value.draw_parameter == value.parameter_finish)
    return {vertex_count, status, topology}
}

// Explicate one cycloid while preserving aligned analytic cusp metadata.
cycloid_explicate_marked :: proc(first, second: Vector3,
    value: shapemodel.Shape_Cycloid, vertices: []Vector3,
    kinds: []Curve_Point_Kind) -> Curve_Explication_Result {
    return cycloid_explicate_internal(first, second, value, vertices, kinds)
}

// Explicate one cycloid for consumers that need only its sampled positions.
cycloid_explicate :: proc(first, second: Vector3,
    value: shapemodel.Shape_Cycloid,
    vertices: []Vector3) -> Curve_Explication_Result {
    return cycloid_explicate_internal(first, second, value, vertices, nil)
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

// Return the analytic cusp sequence for one canonical trochoid.
trochoid_cusp_sequence :: proc(
    value: shapemodel.Shape_Trochoid) -> Curve_Cusp_Sequence {
    if !curve_cusp_scales_match(value.tracer_distance, value.rolling_radius) {
        return {}
    }
    frequency := f64(value.fixed_radius / value.rolling_radius)
    offset := f64(value.tracer_phase)
    if value.mode == .Internal {offset = -offset}
    return curve_cusp_sequence(
        value.parameter_start, value.parameter_finish, frequency, offset)
}

// Build deterministic adaptive boundaries over the complete directed domain.
trochoid_full_domain_parameters :: proc(
    center: Vector3, value: shapemodel.Shape_Trochoid,
    parameters: ^[TROCHOID_MAX_VERTICES]f32,
    kinds: ^[TROCHOID_MAX_VERTICES]Curve_Point_Kind) -> (int, bool) {
    count, capacity_limited := curve_seed_cusp_parameters(parameters[:], kinds[:],
        value.parameter_start, value.parameter_finish,
        trochoid_cusp_sequence(value))
    if capacity_limited {return count, true}
    base_limited: bool
    buffer := Curve_Parameter_Buffer{
        parameters[:], kinds[:], value.parameter_start}
    count, base_limited = curve_insert_base_parameters(
        buffer, count, value.parameter_finish, TROCHOID_BASE_SEGMENTS)
    capacity_limited = capacity_limited || base_limited
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
        curve_insert_parameter_midpoint(parameters[:], kinds[:], count, index)
        count += 1
    }
    return count, capacity_limited
}

// Explicate a trochoid interval through the shared marked implementation.
trochoid_explicate_internal :: proc(
    center: Vector3, value: shapemodel.Shape_Trochoid,
    vertices: []Vector3, output_kinds: []Curve_Point_Kind) -> Curve_Explication_Result {
    if !shapemodel.shape_trochoid_is_valid(value) ||
        len(vertices) < TROCHOID_MAX_VERTICES ||
        (output_kinds != nil && len(output_kinds) < TROCHOID_MAX_VERTICES) {
        return {status = .Invalid_Input}
    }
    parameters: [TROCHOID_MAX_VERTICES]f32
    kinds: [TROCHOID_MAX_VERTICES]Curve_Point_Kind
    parameter_count, capacity_limited := trochoid_full_domain_parameters(
        center, value, &parameters, &kinds)
    vertex_count := 0
    for parameter, index in parameters[:parameter_count] {
        if !parameter_precedes_frontier(value.parameter_start,
            value.parameter_finish, parameter, value.draw_parameter) {
            break
        }
        vertices[vertex_count] = trochoid_point(center, value, parameter)
        if output_kinds != nil {output_kinds[vertex_count] = kinds[index]}
        vertex_count += 1
    }
    final_parameter := parameters[max(vertex_count - 1, 0)]
    frontier_reached := curve_parameters_match(final_parameter, value.draw_parameter)
    if !frontier_reached &&
        vertex_count < len(vertices) {
        vertices[vertex_count] = trochoid_point(center, value, value.draw_parameter)
        if output_kinds != nil {output_kinds[vertex_count] = .Ordinary}
        vertex_count += 1
        frontier_reached = true
    }
    status := curve_explication_status(capacity_limited)
    topology := curve_explication_topology(vertices, kinds[:], vertex_count,
        frontier_reached && value.draw_parameter == value.parameter_finish)
    return {vertex_count, status, topology}
}

// Explicate one trochoid while preserving aligned analytic cusp metadata.
trochoid_explicate_marked :: proc(
    center: Vector3, value: shapemodel.Shape_Trochoid,
    vertices: []Vector3, kinds: []Curve_Point_Kind) -> Curve_Explication_Result {
    return trochoid_explicate_internal(center, value, vertices, kinds)
}

// Explicate one trochoid for consumers that need only its sampled positions.
trochoid_explicate :: proc(
    center: Vector3, value: shapemodel.Shape_Trochoid,
    vertices: []Vector3) -> Curve_Explication_Result {
    return trochoid_explicate_internal(center, value, vertices, nil)
}
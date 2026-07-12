package kine

// Creates and applies constraints for the shape system. This is kinda where that "kine"
// name isn't completely lost, although this is just a totally stripped out version.
// It helps keep the pen and compass in appropriate shape through all animation motions
// without significant pain

import "core:math"
import "core:math/linalg"

//   Local resolved constraint targets used by get/apply constraint logic.
Constraint_Targets :: struct {
    host: ^Kine_Shape_Point,
    children: [3]^Kine_Shape_Point,
    child_count: int,
}

//   Compute the summed error across all active constraints in the point system.
//
// Parameters:
//   - system: Point system containing constraints and points to evaluate.
//
// Returns:
//   - total_error: Accumulated constraint error value.
get_total_constraint_error :: proc(
    system: ^Kine_Point_System) -> f32 {

    total_error: f32 = 0
    for &constraint in system^.constraints {
        total_error += get_constraint_error(&constraint, &system^.points)
    }
    return total_error
}

//   Apply each active constraint to the point system in forward order.
//
// Parameters:
//   - system: Point system whose constraints are applied.
//
// Returns:
//   - none.
apply_all_constraints :: proc(
    system: ^Kine_Point_System) {

    for &constraint in system.constraints {
        apply_constraint(&constraint, &system^.points)
    }
}

//   Apply each active constraint to the point system in reverse order.
//
// Parameters:
//   - system: Point system whose constraints are applied.
//
// Returns:
//   - none.
apply_all_constraints_reverse :: proc(
    system: ^Kine_Point_System) {

    #reverse for &constraint in system.constraints {
        apply_constraint(&constraint, &system^.points)
    }
}

//   Iteratively apply constraints until total error is at or below the allowed threshold.
//
// Parameters:
//   - system: Point system to solve.
//   - allow_error: Maximum acceptable total constraint error.
//
// Returns:
//   - none.
apply_all_constraints_to_error :: proc(
    system: ^Kine_Point_System, allow_error : f32) {

    error := get_total_constraint_error(system)
    reverse := false

    for error > allow_error {
        if reverse {
            apply_all_constraints(system)
        } else {
            apply_all_constraints_reverse(system)
        }
        reverse = !reverse

        error = get_total_constraint_error(system)
    }
}

//   Compute the error contribution of a single constraint against system points.
//
// Parameters:
//   - constraint: Constraint definition to evaluate.
//   - points: Fixed-capacity point array referenced by the constraint.
//
// Returns:
//   - error: Constraint error value for the current point state.
get_constraint_error :: proc(
    constraint: ^Kine_Constraint,
    points: ^[MAX_KINEPOINTS]Kine_Shape_Point) -> f32 {

    if !constraint^.do_apply {
        return 0
    }

    targets, ok := resolve_constraint_targets(constraint, points)
    if !ok {
        return 0
    }

    switch constraint^.kind {
    case .Floor:
        return get_constraint_error_floor(constraint, targets.host)

    case .SnapToFloor:
        return get_constraint_error_snaptofloor(constraint, targets.host)

    case .SnapPoint:
        return get_constraint_error_snappoint(constraint, targets.host)

    case .Distance:
        if targets.child_count < 2 {
            return 0
        }
        return get_constraint_error_distance(constraint, targets.children[0], targets.children[1])

    case .MaxAngle:
        if targets.child_count < 3 {
            return 0
        }
        return get_constraint_error_maxangle(constraint,
            targets.children[0], targets.children[1], targets.children[2])

    case .MinAngle:
        if targets.child_count < 3 {
            return 0
        }
        return get_constraint_error_minangle(constraint,
            targets.children[0], targets.children[1], targets.children[2])

    case .CenterPivot:
        if targets.child_count < 3 {
            return 0
        }
        return get_constraint_error_centerpivot(constraint,
            targets.children[0], targets.children[1], targets.children[2])

    case:
        return 0
    }
}

//   Apply one constraint mutation pass to the referenced points.
//
// Parameters:
//   - constraint: Constraint definition to apply.
//   - points: Fixed-capacity point array updated by the constraint.
//
// Returns:
//   - none.
apply_constraint :: proc(
    constraint: ^Kine_Constraint,
    points: ^[MAX_KINEPOINTS]Kine_Shape_Point) {

    if !constraint^.do_apply {
        return
    }

    targets, ok := resolve_constraint_targets(constraint, points)
    if !ok {
        return
    }

    switch constraint^.kind {
    case .Floor:
        apply_constraint_floor(constraint, targets.host)

    case .SnapToFloor:
        apply_constraint_snaptofloor(constraint, targets.host)

    case .SnapPoint:
        apply_constraint_snappoint(constraint, targets.host)

    case .Distance:
        if targets.child_count < 2 {
            return
        }
        apply_constraint_distance(constraint, targets.children[0], targets.children[1])

    case .MaxAngle:
        if targets.child_count < 3 {
            return
        }
        apply_constraint_maxangle(constraint,
            targets.children[0], targets.children[1], targets.children[2])

    case .MinAngle:
        if targets.child_count < 3 {
            return
        }
        apply_constraint_minangle(constraint,
            targets.children[0], targets.children[1], targets.children[2])

    case .CenterPivot:
        if targets.child_count < 3 {
            return
        }
        apply_constraint_centerpivot(constraint,
            targets.children[0], targets.children[1], targets.children[2])

    case:
        return
    }
}




//   Compute floor-constraint error for a single point.
get_constraint_error_floor :: proc(
    constraint: ^Kine_Constraint,
    point: ^Kine_Shape_Point) -> f32 {

    position, ok := point^.position.?
    if !ok || position.z >= constraint^.restriction.z {
        return 0
    }

    return constraint^.restriction.z - position.z
}

//   Compute snap-to-floor error for a single point with allowance tolerance.
get_constraint_error_snaptofloor :: proc(
    constraint: ^Kine_Constraint,
    point: ^Kine_Shape_Point) -> f32 {

    position, ok := point^.position.?
    if !ok || math.abs(position.z - constraint^.restriction.z) <= constraint^.allowance {
        return 0
    }

    return constraint^.restriction.z - position.z
}

//   Compute snap-point error as distance from point position to restriction target.
get_constraint_error_snappoint :: proc(
    constraint: ^Kine_Constraint,
    point: ^Kine_Shape_Point) -> f32 {

    position, ok := point^.position.?
    if !ok {
        return 0
    }
    vec := position - constraint^.restriction
    len := linalg.length(vec)
    return len
}

//   Compute distance-constraint error between two points.
get_constraint_error_distance :: proc(
    constraint: ^Kine_Constraint,
    point1, point2: ^Kine_Shape_Point) -> f32 {

    position1, ok := point1^.position.?
    if !ok {
        return 0
    }
    position2, ok2 := point2^.position.?
    if !ok2 {
        return 0
    }
    vec := position1 - position2
    len := linalg.length(vec)
    req_len := linalg.length(constraint^.restriction)
    return math.abs(req_len - len)
}

//   Compute max-angle constraint error for a three-point angle.
get_constraint_error_maxangle :: proc(
    constraint: ^Kine_Constraint,
    point1, pivot, point2: ^Kine_Shape_Point) -> f32 {

    position1, ok := point1^.position.?
    if !ok {
        return 0
    }
    position2, ok2 := point2^.position.?
    if !ok2 {
        return 0
    }
    pivot_position, ok3 := pivot^.position.?
    if !ok3 {
        return 0
    }
    vec1 := position1 - pivot_position
    vec2 := position2 - pivot_position

    dot := linalg.dot(vec1, vec2)
    vec1len := linalg.length(vec1)
    vec2len := linalg.length(vec2)

    theta := math.acos(math.clamp(dot / (vec1len * vec2len), -1, 1))

    if theta > constraint^.restriction[0] {
        radians := theta - constraint^.restriction[0]
        return radians * (180.0 / math.PI)
    }

    return 0
}

//   Compute min-angle constraint error for a three-point angle.
get_constraint_error_minangle :: proc(
    constraint: ^Kine_Constraint,
    point1, pivot, point2: ^Kine_Shape_Point) -> f32 {

    position1, ok := point1^.position.?
    if !ok {
        return 0
    }
    position2, ok2 := point2^.position.?
    if !ok2 {
        return 0
    }
    pivot_position, ok3 := pivot^.position.?
    if !ok3 {
        return 0
    }
    vec1 := position1 - pivot_position
    vec2 := position2 - pivot_position

    dot := linalg.dot(vec1, vec2)
    vec1len := linalg.length(vec1)
    vec2len := linalg.length(vec2)

    theta := math.acos(math.clamp(dot / (vec1len * vec2len), -1, 1))

    if theta < constraint^.restriction[0] {
        radians := constraint^.restriction[0] - theta
        return radians * (180.0 / math.PI)
    }

    return 0
}

//   Compute center-pivot error as pivot distance from the segment midpoint.
get_constraint_error_centerpivot :: proc(
    constraint: ^Kine_Constraint,
    point1, pivot, point2: ^Kine_Shape_Point) -> f32 {
    
    position1, ok := point1^.position.?
    if !ok {
        return 0
    }
    position2, ok2 := point2^.position.?
    if !ok2 {
        return 0
    }
    pivot_position, ok3 := pivot^.position.?
    if !ok3 {
        return 0
    }

    mid := (position1 + position2) / 2.0
    move_to := Vector3{ mid.x, mid.y, pivot_position.z }
    len := math.abs(linalg.length(move_to - pivot_position))
    
    return len
}

//   Apply floor constraint response to keep a point at or above floor height.
apply_constraint_floor :: proc(
    constraint: ^Kine_Constraint,
    point: ^Kine_Shape_Point) {

    position, ok := point^.position.?
    if !ok || position.z >= constraint^.restriction.z {
        return
    }

    offset := constraint^.restriction.z - position.z
    position.z = constraint^.restriction.z + offset * constraint^.bounce
    point^.position = position
}

//   Apply snap-to-floor constraint by forcing point height to floor level.
apply_constraint_snaptofloor :: proc(
    constraint: ^Kine_Constraint,
    point: ^Kine_Shape_Point) {

    position, ok := point^.position.?
    if !ok || math.abs(position.z - constraint^.restriction.z) <= constraint^.allowance {
        return
    }

    position.z = constraint^.restriction.z
    point^.position = position
}

//   Apply snap-point constraint by setting point position to restriction target.
apply_constraint_snappoint :: proc(
    constraint: ^Kine_Constraint,
    point: ^Kine_Shape_Point) {

    point^.position = constraint^.restriction
}

//   Apply distance constraint to two points using depend_on ownership mode.
//
// Notes:
//   - depend_on > 0 moves point1, == 0 moves both, < 0 moves point2.
apply_constraint_distance :: proc(
    constraint: ^Kine_Constraint,
    point1, point2: ^Kine_Shape_Point) {

    position1, ok := point1^.position.?
    if !ok {
        return
    }
    position2, ok2 := point2^.position.?
    if !ok2 {
        return
    }
    vec := position1 - position2
    req_len := linalg.length(constraint^.restriction)

    if constraint^.depend_on > 0 {
        norm := linalg.normalize(vec)
        point1^.position = position2 + norm * req_len
    } else if constraint^.depend_on == 0 {
        mid := (position1 + position2) / 2.0
        vec = position2 - mid
        norm := linalg.normalize(vec)
        point2^.position = mid + norm * (req_len / 2.0)
        vec = position1 - mid
        norm = linalg.normalize(vec)
        point1^.position = mid + norm * (req_len / 2.0)
    } else {
        vec = position2 - position1
        norm := linalg.normalize(vec)
        point2^.position = position1 + norm * req_len
    }
}

//   Apply max-angle constraint by rotating one or both limbs toward limit.
apply_constraint_maxangle :: proc(
    constraint: ^Kine_Constraint,
    point1, pivot, point2: ^Kine_Shape_Point) {

    position1, ok := point1^.position.?
    if !ok {
        return
    }
    position2, ok2 := point2^.position.?
    if !ok2 {
        return
    }
    pivot_position, ok3 := pivot^.position.?
    if !ok3 {
        return
    }
    vec1 := position1 - pivot_position
    vec2 := position2 - pivot_position

    dot := linalg.dot(vec1, vec2)
    vec1len := linalg.length(vec1)
    vec2len := linalg.length(vec2)

    theta := math.acos(math.clamp(dot / (vec1len * vec2len), -1, 1))

    if theta <= constraint^.restriction[0] {
        return
    }

    overage := theta - constraint^.restriction[0]
    halfoverage := overage / 2.0

    rotaxis := linalg.normalize(linalg.cross(vec1, vec2))

    new_vec1 := Vector3{0, 0, 0}
    new_vec2 := Vector3{0, 0, 0}
    if constraint^.depend_on > 0 {
        new_vec1 = rotate_around_axis(vec1, rotaxis, overage)
    } else if constraint^.depend_on == 0 {
        new_vec1 = rotate_around_axis(vec1, rotaxis, halfoverage)
        new_vec2 = rotate_around_axis(vec2, rotaxis, -halfoverage)
    } else {
        new_vec2 = rotate_around_axis(vec2, rotaxis, -overage)
    }

    point1^.position = pivot_position + new_vec1
    point2^.position = pivot_position + new_vec2
}

//   Rotate a vector around an axis by a given angle in radians.
//
// Notes:
//   - Uses Rodrigues' rotation formula and assumes axis is meaningful for rotation.
rotate_around_axis :: proc(vec, axis: Vector3, angle: f32) -> Vector3 {
    c := math.cos(angle)
    s := math.sin(angle)

    return vec * c +
        linalg.cross(axis, vec) * s +
        axis * linalg.dot(axis, vec) * (1 - c)
}

//   Apply min-angle constraint by rotating one or both limbs outward to limit.
apply_constraint_minangle :: proc(
    constraint: ^Kine_Constraint,
    point1, pivot, point2: ^Kine_Shape_Point) {

    position1, ok := point1^.position.?
    if !ok {
        return
    }
    position2, ok2 := point2^.position.?
    if !ok2 {
        return
    }
    pivot_position, ok3 := pivot^.position.?
    if !ok3 {
        return
    }
    vec1 := position1 - pivot_position
    vec2 := position2 - pivot_position

    dot := linalg.dot(vec1, vec2)
    vec1len := linalg.length(vec1)
    vec2len := linalg.length(vec2)

    theta := math.acos(math.clamp(dot / (vec1len * vec2len), -1, 1))

    if theta >= constraint^.restriction[0] {
        return
    }

    underage := constraint^.restriction[0] - theta
    halfunderage := underage / 2.0

    rotaxis := linalg.normalize(linalg.cross(vec1, vec2))

    new_vec1 := Vector3{0, 0, 0}
    new_vec2 := Vector3{0, 0, 0}
    if constraint^.depend_on > 0 {
        new_vec1 = rotate_around_axis(vec1, rotaxis, -underage)
    } else if constraint^.depend_on == 0 {
        new_vec1 = rotate_around_axis(vec1, rotaxis, -halfunderage)
        new_vec2 = rotate_around_axis(vec2, rotaxis, halfunderage)
    } else {
        new_vec2 = rotate_around_axis(vec2, rotaxis, underage)
    }

    point1^.position = pivot_position + new_vec1
    point2^.position = pivot_position + new_vec2
}

//   Apply center-pivot constraint by moving pivot to midpoint of outer points.
apply_constraint_centerpivot :: proc(
    constraint: ^Kine_Constraint,
    point1, pivot, point2: ^Kine_Shape_Point) {
    
    position1, ok := point1^.position.?
    if !ok {
        return
    }
    position2, ok2 := point2^.position.?
    if !ok2 {
        return
    }
    pivot_position, ok3 := pivot^.position.?
    if !ok3 {
        return
    }

    mid := (position1 + position2) / 2.0
    move_to := Vector3{ mid.x, mid.y, pivot_position.z }
    pivot^.position = move_to
}

//   Return whether an index references a valid point slot in the fixed point array.
is_valid_constraint_point_index :: #force_inline proc(index, len_points: int) -> bool {
    return index > 0 && index <= len_points
}

//   Resolve the first child for a constraint host, including optional child_offset traversal.
resolve_constraint_first_child :: #force_inline proc(
    host: ^Kine_Shape_Point,
    constraint: ^Kine_Constraint,
    points: ^[MAX_KINEPOINTS]Kine_Shape_Point,
    len_points: int) -> (^Kine_Shape_Point, bool) {
    if !is_valid_constraint_point_index(host^.child_point_head, len_points) {
        return nil, false
    }

    child := &points^[host^.child_point_head]
    use_child := constraint^.child_offset.? or_else 0
    for _ in 0..<use_child {
        if !is_valid_constraint_point_index(child^.next_child_point, len_points) {
            return nil, false
        }
        child = &points^[child^.next_child_point]
    }

    return child, true
}

//   Append the next child from the linked child chain into targets when available.
append_next_constraint_child :: #force_inline proc(
    targets: ^Constraint_Targets,
    points: ^[MAX_KINEPOINTS]Kine_Shape_Point,
    len_points: int) -> bool {
    last_child := targets^.children[targets^.child_count - 1]
    if !is_valid_constraint_point_index(last_child^.next_child_point, len_points) {
        return false
    }

    targets^.children[targets^.child_count] = &points^[last_child^.next_child_point]
    targets^.child_count += 1
    return true
}

//   Resolve host/children targets needed by get_constraint_error and apply_constraint.
//
// Notes:
//   - Returns ok=false only when constraint.on_point is invalid.
//   - Missing child links are represented by a lower child_count with ok=true.
resolve_constraint_targets :: #force_inline proc(
    constraint: ^Kine_Constraint,
    points: ^[MAX_KINEPOINTS]Kine_Shape_Point) -> (Constraint_Targets, bool) {
    len_points := len(points^)
    if len_points <= constraint^.on_point {
        return Constraint_Targets{}, false
    }

    targets := Constraint_Targets{
        host = &points^[constraint^.on_point],
        children = {nil, nil, nil},
        child_count = 0,
    }

    first_child, has_first_child := resolve_constraint_first_child(
        targets.host,
        constraint,
        points,
        len_points,
    )
    if !has_first_child {
        return targets, true
    }

    targets.children[0] = first_child
    targets.child_count = 1

    if !append_next_constraint_child(&targets, points, len_points) {
        return targets, true
    }

    if !append_next_constraint_child(&targets, points, len_points) {
        return targets, true
    }

    return targets, true
}

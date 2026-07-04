package kine

// Creates and applies constraints for the shape system. This is kinda where that "kine"
// name isn't completely lost, although this is just a totally stripped out version.
// It helps keep the pen and compass in appropriate shape through all animation motions
// without significant pain

import "core:math"
import "core:math/linalg"

// Summary:
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

// Summary:
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

// Summary:
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

// Summary:
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

// Summary:
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

// Summary:
//   Compute the error contribution of a single constraint against system points.
//
// Parameters:
//   - constraint: Constraint definition to evaluate.
//   - points: Fixed-capacity point array referenced by the constraint.
//
// Returns:
//   - error: Constraint error value for the current point state.
get_constraint_error :: proc(
    constraint : ^Kine_Constraint, points: ^[MAX_KINEPOINTS]Kine_Shape_Point) -> f32 {

    if !constraint^.do_apply {
        return 0
    }
    total_error : f32 = 0
    len_points := len(points^)

    if len_points <= constraint^.on_point {
        return 0
    }
    host_point := &points^[constraint^.on_point]

    if constraint^.traits & .Floor == .Floor {
        total_error += get_constraint_error_floor(constraint, host_point)
    }
    if constraint^.traits & .SnapToFloor == .SnapToFloor {
        total_error += get_constraint_error_snaptofloor(constraint, host_point)
    }
    if constraint^.traits & .SnapPoint == .SnapPoint {
        total_error += get_constraint_error_snappoint(constraint, host_point)
    }

    children : [3]^Kine_Shape_Point = { nil, nil, nil }

    if host_point^.child_point_head <= 0 || host_point^.child_point_head > len_points {
        return total_error
    }
    children[0] = &points^[host_point^.child_point_head]
    use_child := constraint^.child_offset.? or_else 0
    for _ in 0..<use_child {
        if children[0]^.next_child_point <= 0 || children[0]^.next_child_point > len_points {
            return total_error
        }
        children[0] = &points^[children[0]^.next_child_point]
    }

    if children[0]^.next_child_point <= 0 || children[0]^.next_child_point > len_points {
        return total_error
    }
    children[1] = &points^[children[0]^.next_child_point]

    if constraint^.traits & .Distance == .Distance {
        add_err := get_constraint_error_distance(constraint, children[0], children[1])
        total_error += add_err
    }

    if children[1]^.next_child_point <= 0 || children[1]^.next_child_point > len_points {
        return total_error
    }
    children[2] = &points^[children[1]^.next_child_point]

    if constraint^.traits & .MaxAngle == .MaxAngle {
        total_error += get_constraint_error_maxangle(constraint,
            children[0], children[1], children[2])
    }
    if constraint^.traits & .MinAngle == .MinAngle {
        total_error += get_constraint_error_minangle(constraint,
            children[0], children[1], children[2])
    }
    if constraint^.traits & .CenterPivot == .CenterPivot {
        total_error += get_constraint_error_centerpivot(constraint,
            children[0], children[1], children[2])
    }

    return total_error
}

// Summary:
//   Apply one constraint mutation pass to the referenced points.
//
// Parameters:
//   - constraint: Constraint definition to apply.
//   - points: Fixed-capacity point array updated by the constraint.
//
// Returns:
//   - none.
apply_constraint :: proc(
    constraint : ^Kine_Constraint, points: ^[MAX_KINEPOINTS]Kine_Shape_Point) {

    if !constraint^.do_apply {
        return
    }
    len_points := len(points^)

    if len_points <= constraint^.on_point {
        return
    }
    host_point := &points^[constraint^.on_point]

    if constraint^.traits & .Floor == .Floor {
        apply_constraint_floor(constraint, host_point)
    }
    if constraint^.traits & .SnapToFloor == .SnapToFloor {
        apply_constraint_snaptofloor(constraint, host_point)
    }
    if constraint^.traits & .SnapPoint == .SnapPoint {
        apply_constraint_snappoint(constraint, host_point)
    }

    children : [3]^Kine_Shape_Point = { nil, nil, nil }

    if host_point^.child_point_head <= 0 || host_point^.child_point_head > len_points {
        return
    }
    children[0] = &points^[host_point^.child_point_head]
    use_child := constraint^.child_offset.? or_else 0
    for _ in 0..<use_child {
        if children[0]^.next_child_point <= 0 || children[0]^.next_child_point > len_points {
            return
        }
        children[0] = &points^[children[0]^.next_child_point]
    }
    
    if children[0]^.next_child_point <= 0 || children[0]^.next_child_point > len_points {
        return
    }
    children[1] = &points^[children[0]^.next_child_point]

    if constraint^.traits & .Distance == .Distance {
        apply_constraint_distance(constraint, children[0], children[1])
    }

    if children[1]^.next_child_point <= 0 || children[1]^.next_child_point > len_points {
        return
    }
    children[2] = &points^[children[1]^.next_child_point]

    if constraint^.traits & .MaxAngle == .MaxAngle {
        apply_constraint_maxangle(constraint,
            children[0], children[1], children[2])
    }
    if constraint^.traits & .MinAngle == .MinAngle {
        apply_constraint_minangle(constraint,
            children[0], children[1], children[2])
    }
    if constraint^.traits & .CenterPivot == .CenterPivot {
        apply_constraint_centerpivot(constraint,
            children[0], children[1], children[2])
    }
}




// Summary:
//   Compute floor-constraint error for a single point.
get_constraint_error_floor :: proc(
    constraint : ^Kine_Constraint, point : ^Kine_Shape_Point) -> f32 {

    position, ok := point^.position.?
    if !ok || position.z >= constraint^.restriction.z {
        return 0
    }

    return constraint^.restriction.z - position.z
}

// Summary:
//   Compute snap-to-floor error for a single point with allowance tolerance.
get_constraint_error_snaptofloor :: proc(
    constraint : ^Kine_Constraint, point : ^Kine_Shape_Point) -> f32 {

    position, ok := point^.position.?
    if !ok || math.abs(position.z - constraint^.restriction.z) <= constraint^.allowance {
        return 0
    }

    return constraint^.restriction.z - position.z
}

// Summary:
//   Compute snap-point error as distance from point position to restriction target.
get_constraint_error_snappoint :: proc(
    constraint : ^Kine_Constraint, point : ^Kine_Shape_Point) -> f32 {

    position, ok := point^.position.?
    if !ok {
        return 0
    }
    vec := position - constraint^.restriction
    len := linalg.length(vec)
    return len
}

// Summary:
//   Compute distance-constraint error between two points.
get_constraint_error_distance :: proc(
    constraint : ^Kine_Constraint, point1, point2 : ^Kine_Shape_Point) -> f32 {

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

// Summary:
//   Compute max-angle constraint error for a three-point angle.
get_constraint_error_maxangle :: proc(
    constraint : ^Kine_Constraint, point1, pivot, point2 : ^Kine_Shape_Point) -> f32 {

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

// Summary:
//   Compute min-angle constraint error for a three-point angle.
get_constraint_error_minangle :: proc(
    constraint : ^Kine_Constraint, point1, pivot, point2 : ^Kine_Shape_Point) -> f32 {

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

// Summary:
//   Compute center-pivot error as pivot distance from the segment midpoint.
get_constraint_error_centerpivot :: proc(
    constraint : ^Kine_Constraint, point1, pivot, point2 : ^Kine_Shape_Point) -> f32 {
    
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

// Summary:
//   Apply floor constraint response to keep a point at or above floor height.
apply_constraint_floor :: proc(
    constraint : ^Kine_Constraint, point : ^Kine_Shape_Point) {

    position, ok := point^.position.?
    if !ok || position.z >= constraint^.restriction.z {
        return
    }

    offset := constraint^.restriction.z - position.z
    position.z = constraint^.restriction.z + offset * constraint^.bounce
    point^.position = position
}

// Summary:
//   Apply snap-to-floor constraint by forcing point height to floor level.
apply_constraint_snaptofloor :: proc(
    constraint : ^Kine_Constraint, point : ^Kine_Shape_Point) {

    position, ok := point^.position.?
    if !ok || math.abs(position.z - constraint^.restriction.z) <= constraint^.allowance {
        return
    }

    position.z = constraint^.restriction.z
    point^.position = position
}

// Summary:
//   Apply snap-point constraint by setting point position to restriction target.
apply_constraint_snappoint :: proc(
    constraint : ^Kine_Constraint, point : ^Kine_Shape_Point) {

    point^.position = constraint^.restriction
}

// Summary:
//   Apply distance constraint to two points using depend_on ownership mode.
//
// Notes:
//   - depend_on > 0 moves point1, == 0 moves both, < 0 moves point2.
apply_constraint_distance :: proc(
    constraint : ^Kine_Constraint, point1, point2 : ^Kine_Shape_Point) {

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

// Summary:
//   Apply max-angle constraint by rotating one or both limbs toward limit.
apply_constraint_maxangle :: proc(
    constraint : ^Kine_Constraint, point1, pivot, point2 : ^Kine_Shape_Point) {

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

// Summary:
//   Apply min-angle constraint by rotating one or both limbs outward to limit.
apply_constraint_minangle :: proc(
    constraint : ^Kine_Constraint, point1, pivot, point2 : ^Kine_Shape_Point) {

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

// Summary:
//   Apply center-pivot constraint by moving pivot to midpoint of outer points.
apply_constraint_centerpivot :: proc(
    constraint : ^Kine_Constraint, point1, pivot, point2 : ^Kine_Shape_Point) {
    
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

package kine

import "core:math"
import "core:math/linalg"

rotate_around_axis :: proc(vec, axis: Vector3, angle: f32) -> Vector3 {
    c := math.cos(angle)
    s := math.sin(angle)

    return vec * c +
        linalg.cross(axis, vec) * s +
        axis * linalg.dot(axis, vec) * (1 - c)
}

get_total_constraint_error :: proc(
    system: ^KinePointSystem) -> f32 {

    totalError: f32 = 0
    for &constraint in system^.Constraints {
        totalError += get_constraint_error(&constraint, &system^.Points)
    }
    return totalError
}

apply_all_constraints :: proc(
    system: ^KinePointSystem) {

    for &constraint in system.Constraints {
        apply_constraint(&constraint, &system^.Points)
    }
}

apply_all_constraints_reverse :: proc(
    system: ^KinePointSystem) {

    #reverse for &constraint in system.Constraints {
        apply_constraint(&constraint, &system^.Points)
    }
}

apply_all_constraints_to_error :: proc(
    system: ^KinePointSystem, allowError : f32) {

    error := get_total_constraint_error(system)
    reverse := false

    for error > allowError {
        if reverse {
            apply_all_constraints(system)
        }
        else {
            apply_all_constraints_reverse(system)
        }
        reverse = !reverse

        error = get_total_constraint_error(system)
    }
}

get_constraint_error :: proc(
    constraint : ^KineConstraint, points: ^[MAX_KINEPOINTS]KineShapePoint) -> f32 {

    if !constraint^.DoApply {
        return 0
    }
    totalError : f32 = 0
    lenPoints := len(points^)

    if lenPoints <= constraint^.OnPoint {
        return 0
    }
    hostPoint := &points^[constraint^.OnPoint]

    if constraint^.Traits & .Floor == .Floor {
        totalError += get_constraint_error_floor(constraint, hostPoint)
    }
    if constraint^.Traits & .SnapToFloor == .SnapToFloor {
        totalError += get_constraint_error_snaptofloor(constraint, hostPoint)
    }
    if constraint^.Traits & .SnapPoint == .SnapPoint {
        totalError += get_constraint_error_snappoint(constraint, hostPoint)
    }

    children : [3]^KineShapePoint = { nil, nil, nil }

    if hostPoint^.ChildPointHead <= 0 || hostPoint^.ChildPointHead > lenPoints {
        return totalError
    }
    children[0] = &points^[hostPoint^.ChildPointHead]
    useChild := constraint^.ChildOffset.? or_else 0
    for i in 0..<useChild {
        if children[0]^.NextChildPoint <= 0 || children[0]^.NextChildPoint > lenPoints {
            return totalError
        }
        children[0] = &points^[children[0]^.NextChildPoint]
    }

    if children[0]^.NextChildPoint <= 0 || children[0]^.NextChildPoint > lenPoints {
        return totalError
    }
    children[1] = &points^[children[0]^.NextChildPoint]

    if constraint^.Traits & .Distance == .Distance {
        addErr := get_constraint_error_distance(constraint, children[0], children[1])
        totalError += addErr
    }

    if children[1]^.NextChildPoint <= 0 || children[1]^.NextChildPoint > lenPoints {
        return totalError
    }
    children[2] = &points^[children[1]^.NextChildPoint]

    if constraint^.Traits & .MaxAngle == .MaxAngle {
        totalError += get_constraint_error_maxangle(constraint,
            children[0], children[1], children[2])
    }
    if constraint^.Traits & .MinAngle == .MinAngle {
        totalError += get_constraint_error_minangle(constraint,
            children[0], children[1], children[2])
    }
    if constraint^.Traits & .CenterPivot == .CenterPivot {
        totalError += get_constraint_error_centerpivot(constraint,
            children[0], children[1], children[2])
    }

    return totalError
}

apply_constraint :: proc(
    constraint : ^KineConstraint, points: ^[MAX_KINEPOINTS]KineShapePoint) {

    if !constraint^.DoApply {
        return
    }
    lenPoints := len(points^)

    if lenPoints <= constraint^.OnPoint {
        return
    }
    hostPoint := &points^[constraint^.OnPoint]

    if constraint^.Traits & .Floor == .Floor {
        apply_constraint_floor(constraint, hostPoint)
    }
    if constraint^.Traits & .SnapToFloor == .SnapToFloor {
        apply_constraint_snaptofloor(constraint, hostPoint)
    }
    if constraint^.Traits & .SnapPoint == .SnapPoint {
        apply_constraint_snappoint(constraint, hostPoint)
    }

    children : [3]^KineShapePoint = { nil, nil, nil }

    if hostPoint^.ChildPointHead <= 0 || hostPoint^.ChildPointHead > lenPoints {
        return
    }
    children[0] = &points^[hostPoint^.ChildPointHead]
    useChild := constraint^.ChildOffset.? or_else 0
    for i in 0..<useChild {
        if children[0]^.NextChildPoint <= 0 || children[0]^.NextChildPoint > lenPoints {
            return
        }
        children[0] = &points^[children[0]^.NextChildPoint]
    }
    
    if children[0]^.NextChildPoint <= 0 || children[0]^.NextChildPoint > lenPoints {
        return
    }
    children[1] = &points^[children[0]^.NextChildPoint]

    if constraint^.Traits & .Distance == .Distance {
        apply_constraint_distance(constraint, children[0], children[1])
    }

    if children[1]^.NextChildPoint <= 0 || children[1]^.NextChildPoint > lenPoints {
        return
    }
    children[2] = &points^[children[1]^.NextChildPoint]

    if constraint^.Traits & .MaxAngle == .MaxAngle {
        apply_constraint_maxangle(constraint,
            children[0], children[1], children[2])
    }
    if constraint^.Traits & .MinAngle == .MinAngle {
        apply_constraint_minangle(constraint,
            children[0], children[1], children[2])
    }
    if constraint^.Traits & .CenterPivot == .CenterPivot {
        apply_constraint_centerpivot(constraint,
            children[0], children[1], children[2])
    }
}

get_constraint_error_floor :: proc(
    constraint : ^KineConstraint, point : ^KineShapePoint) -> f32 {

    position, ok := point^.Position.?
    if !ok || position.z >= constraint^.Restriction.z {
        return 0
    }

    return constraint^.Restriction.z - position.z
}

get_constraint_error_snaptofloor :: proc(
    constraint : ^KineConstraint, point : ^KineShapePoint) -> f32 {

    position, ok := point^.Position.?
    if !ok || math.abs(position.z - constraint^.Restriction.z) <= constraint^.Allowance {
        return 0
    }

    return constraint^.Restriction.z - position.z
}

get_constraint_error_snappoint :: proc(
    constraint : ^KineConstraint, point : ^KineShapePoint) -> f32 {

    position, ok := point^.Position.?
    if !ok {
        return 0
    }
    vec := position - constraint^.Restriction
    len := linalg.length(vec)
    return len
}

get_constraint_error_distance :: proc(
    constraint : ^KineConstraint, point1, point2 : ^KineShapePoint) -> f32 {

    position1, ok := point1^.Position.?
    if !ok {
        return 0
    }
    position2, ok2 := point2^.Position.?
    if !ok2 {
        return 0
    }
    vec := position1 - position2
    len := linalg.length(vec)
    reqLen := linalg.length(constraint^.Restriction)
    return math.abs(reqLen - len)
}

get_constraint_error_maxangle :: proc(
    constraint : ^KineConstraint, point1, pivot, point2 : ^KineShapePoint) -> f32 {

    position1, ok := point1^.Position.?
    if !ok {
        return 0
    }
    position2, ok2 := point2^.Position.?
    if !ok2 {
        return 0
    }
    pivotPosition, ok3 := pivot^.Position.?
    if !ok3 {
        return 0
    }
    vec1 := position1 - pivotPosition
    vec2 := position2 - pivotPosition

    dot := linalg.dot(vec1, vec2)
    vec1len := linalg.length(vec1)
    vec2len := linalg.length(vec2)

    theta := math.acos(math.clamp(dot / (vec1len * vec2len), -1, 1))

    if theta > constraint^.Restriction[0] {
        radians := theta - constraint^.Restriction[0]
        return radians * (180.0 / math.PI)
    }

    return 0
}

get_constraint_error_minangle :: proc(
    constraint : ^KineConstraint, point1, pivot, point2 : ^KineShapePoint) -> f32 {

    position1, ok := point1^.Position.?
    if !ok {
        return 0
    }
    position2, ok2 := point2^.Position.?
    if !ok2 {
        return 0
    }
    pivotPosition, ok3 := pivot^.Position.?
    if !ok3 {
        return 0
    }
    vec1 := position1 - pivotPosition
    vec2 := position2 - pivotPosition

    dot := linalg.dot(vec1, vec2)
    vec1len := linalg.length(vec1)
    vec2len := linalg.length(vec2)

    theta := math.acos(math.clamp(dot / (vec1len * vec2len), -1, 1))

    if theta < constraint^.Restriction[0] {
        radians := constraint^.Restriction[0] - theta
        return radians * (180.0 / math.PI)
    }

    return 0
}

get_constraint_error_centerpivot :: proc(
    constraint : ^KineConstraint, point1, pivot, point2 : ^KineShapePoint) -> f32 {
    
    position1, ok := point1^.Position.?
    if !ok {
        return 0
    }
    position2, ok2 := point2^.Position.?
    if !ok2 {
        return 0
    }
    pivotPosition, ok3 := pivot^.Position.?
    if !ok3 {
        return 0
    }

    mid := (position1 + position2) / 2.0
    moveTo := Vector3{ mid.x, mid.y, pivotPosition.z }
    len := math.abs(linalg.length(moveTo - pivotPosition))
    
    return len
}

apply_constraint_floor :: proc(
    constraint : ^KineConstraint, point : ^KineShapePoint) {

    position, ok := point^.Position.?
    if !ok || position.z >= constraint^.Restriction.z {
        return
    }

    offset := constraint^.Restriction.z - position.z
    position.z = constraint^.Restriction.z + offset * constraint^.Bounce
    point^.Position = position
}

apply_constraint_snaptofloor :: proc(
    constraint : ^KineConstraint, point : ^KineShapePoint) {

    position, ok := point^.Position.?
    if !ok || math.abs(position.z - constraint^.Restriction.z) <= constraint^.Allowance {
        return
    }

    position.z = constraint^.Restriction.z
    point^.Position = position
}

apply_constraint_snappoint :: proc(
    constraint : ^KineConstraint, point : ^KineShapePoint) {

    point^.Position = constraint^.Restriction
}

apply_constraint_distance :: proc(
    constraint : ^KineConstraint, point1, point2 : ^KineShapePoint) {

    position1, ok := point1^.Position.?
    if !ok {
        return
    }
    position2, ok2 := point2^.Position.?
    if !ok2 {
        return
    }
    vec := position1 - position2
    len := linalg.length(vec)
    reqLen := linalg.length(constraint^.Restriction)

    if constraint^.DependOn > 0 {
        norm := linalg.normalize(vec)
        point1^.Position = position2 + norm * reqLen
    }
    else if constraint^.DependOn == 0 {
        mid := (position1 + position2) / 2.0
        vec = position2 - mid
        norm := linalg.normalize(vec)
        point2^.Position = mid + norm * (reqLen / 2.0)
        vec = position1 - mid
        norm = linalg.normalize(vec)
        point1^.Position = mid + norm * (reqLen / 2.0)
    }
    else {
        vec = position2 - position1
        norm := linalg.normalize(vec)
        point2^.Position = position1 + norm * reqLen
    }
}

apply_constraint_maxangle :: proc(
    constraint : ^KineConstraint, point1, pivot, point2 : ^KineShapePoint) {

    position1, ok := point1^.Position.?
    if !ok {
        return
    }
    position2, ok2 := point2^.Position.?
    if !ok2 {
        return
    }
    pivotPosition, ok3 := pivot^.Position.?
    if !ok3 {
        return
    }
    vec1 := position1 - pivotPosition
    vec2 := position2 - pivotPosition

    dot := linalg.dot(vec1, vec2)
    vec1len := linalg.length(vec1)
    vec2len := linalg.length(vec2)

    theta := math.acos(math.clamp(dot / (vec1len * vec2len), -1, 1))

    if theta <= constraint^.Restriction[0] {
        return
    }

    overage := theta - constraint^.Restriction[0]
    halfoverage := overage / 2.0

    rotaxis := linalg.normalize(linalg.cross(vec1, vec2))

    new_vec1 := Vector3{0, 0, 0}
    new_vec2 := Vector3{0, 0, 0}
    if constraint^.DependOn > 0 {
        new_vec1 = rotate_around_axis(vec1, rotaxis, overage)
    }
    else if constraint^.DependOn == 0 {
        new_vec1 = rotate_around_axis(vec1, rotaxis, halfoverage)
        new_vec2 = rotate_around_axis(vec2, rotaxis, -halfoverage)
    }
    else {
        new_vec2 = rotate_around_axis(vec2, rotaxis, -overage)
    }

    point1^.Position = pivotPosition + new_vec1
    point2^.Position = pivotPosition + new_vec2
}

apply_constraint_minangle :: proc(
    constraint : ^KineConstraint, point1, pivot, point2 : ^KineShapePoint) {

    position1, ok := point1^.Position.?
    if !ok {
        return
    }
    position2, ok2 := point2^.Position.?
    if !ok2 {
        return
    }
    pivotPosition, ok3 := pivot^.Position.?
    if !ok3 {
        return
    }
    vec1 := position1 - pivotPosition
    vec2 := position2 - pivotPosition

    dot := linalg.dot(vec1, vec2)
    vec1len := linalg.length(vec1)
    vec2len := linalg.length(vec2)

    theta := math.acos(math.clamp(dot / (vec1len * vec2len), -1, 1))

    if theta >= constraint^.Restriction[0] {
        return
    }

    underage := constraint^.Restriction[0] - theta
    halfunderage := underage / 2.0

    rotaxis := linalg.normalize(linalg.cross(vec1, vec2))

    new_vec1 := Vector3{0, 0, 0}
    new_vec2 := Vector3{0, 0, 0}
    if constraint^.DependOn > 0 {
        new_vec1 = rotate_around_axis(vec1, rotaxis, -underage)
    }
    else if constraint^.DependOn == 0 {
        new_vec1 = rotate_around_axis(vec1, rotaxis, -halfunderage)
        new_vec2 = rotate_around_axis(vec2, rotaxis, halfunderage)
    }
    else {
        new_vec2 = rotate_around_axis(vec2, rotaxis, underage)
    }

    point1^.Position = pivotPosition + new_vec1
    point2^.Position = pivotPosition + new_vec2
}

apply_constraint_centerpivot :: proc(
    constraint : ^KineConstraint, point1, pivot, point2 : ^KineShapePoint) {
    
    position1, ok := point1^.Position.?
    if !ok {
        return
    }
    position2, ok2 := point2^.Position.?
    if !ok2 {
        return
    }
    pivotPosition, ok3 := pivot^.Position.?
    if !ok3 {
        return
    }

    mid := (position1 + position2) / 2.0
    moveTo := Vector3{ mid.x, mid.y, pivotPosition.z }
    pivot^.Position = moveTo
}

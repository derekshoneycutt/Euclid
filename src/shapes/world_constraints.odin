package shapes

import "core:math"
import "core:math/linalg"

import "../core"

WORLD_CONSTRAINT_SOLVE_ITERATION_LIMIT :: 64

// Supply one direct point target and floor response parameters.
World_Floor_Constraint_Input :: struct {
    point: core.Shape_Entity,
    height: f32,
    bounce: f32,
    enabled: bool,
}

// Supply one direct point target and floor snapping parameters.
World_Snap_To_Floor_Constraint_Input :: struct {
    point: core.Shape_Entity,
    height: f32,
    allowance: f32,
    enabled: bool,
}

// Supply one direct point target and fixed world position.
World_Snap_Point_Constraint_Input :: struct {
    point: core.Shape_Entity,
    position: Vector3,
    enabled: bool,
}

// Supply both direct endpoints and distance correction policy.
World_Distance_Constraint_Input :: struct {
    first: core.Shape_Entity,
    second: core.Shape_Entity,
    length: f32,
    movement: core.Shape_Constraint_Movement_Policy,
    enabled: bool,
}

// Supply three direct angle targets and correction policy.
World_Angle_Constraint_Input :: struct {
    first: core.Shape_Entity,
    pivot: core.Shape_Entity,
    second: core.Shape_Entity,
    limit: f32,
    movement: core.Shape_Constraint_Movement_Policy,
    enabled: bool,
}

// Supply three direct targets and optional equal compass-limb length.
World_Center_Pivot_Constraint_Input :: struct {
    first: core.Shape_Entity,
    pivot: core.Shape_Entity,
    second: core.Shape_Entity,
    limb_length: f32,
    enabled: bool,
}

// Hold resolved pivot-relative vectors for one direct angle constraint.
World_Angle_Constraint_Limbs :: struct {
    pivot: Vector3,
    first: Vector3,
    second: Vector3,
    axis: Vector3,
    theta: f32,
}

// Rotate one vector around an axis using Rodrigues' formula.
rotate_around_axis :: proc(vec, axis: Vector3, angle: f32) -> Vector3 {
    cosine := math.cos(angle)
    sine := math.sin(angle)
    return vec * cosine + linalg.cross(axis, vec) * sine +
        axis * linalg.dot(axis, vec) * (1 - cosine)
}

// Append one generic direct-target constraint after complete validation.
world_create_constraint :: proc(
    world: ^core.Shape_World,
    constraint: core.Shape_Constraint) -> (u16, core.Shape_World_Status) {
    index: u16
    status := core.shape_constraint_append(world, constraint, &index)
    return index, status
}

// Append one floor constraint with a direct transform target.
world_create_floor_constraint :: proc(
    world: ^core.Shape_World,
    input: World_Floor_Constraint_Input) -> (u16, core.Shape_World_Status) {
    constraint := core.Shape_Constraint{kind = .Floor, enabled = input.enabled}
    constraint.payload.floor = {
        point = input.point, height = input.height, bounce = input.bounce}
    return world_create_constraint(world, constraint)
}

// Append one snap-to-floor constraint with a direct transform target.
world_create_snap_to_floor_constraint :: proc(
    world: ^core.Shape_World,
    input: World_Snap_To_Floor_Constraint_Input) -> (u16, core.Shape_World_Status) {
    constraint := core.Shape_Constraint{kind = .Snap_To_Floor, enabled = input.enabled}
    constraint.payload.snap_to_floor = {point = input.point,
        height = input.height, allowance = input.allowance}
    return world_create_constraint(world, constraint)
}

// Append one snap-point constraint with a direct transform target.
world_create_snap_point_constraint :: proc(
    world: ^core.Shape_World,
    input: World_Snap_Point_Constraint_Input) -> (u16, core.Shape_World_Status) {
    constraint := core.Shape_Constraint{kind = .Snap_Point, enabled = input.enabled}
    constraint.payload.snap_point = {point = input.point, position = input.position}
    return world_create_constraint(world, constraint)
}

// Append one distance constraint with direct endpoint targets.
world_create_distance_constraint :: proc(
    world: ^core.Shape_World,
    input: World_Distance_Constraint_Input) -> (u16, core.Shape_World_Status) {
    constraint := core.Shape_Constraint{kind = .Distance, enabled = input.enabled}
    constraint.payload.distance = {first = input.first, second = input.second,
        length = input.length, movement = input.movement}
    return world_create_constraint(world, constraint)
}

// Append one angle-bound constraint with direct limb and pivot targets.
world_create_angle_constraint :: proc(
    world: ^core.Shape_World,
    kind: core.Shape_Constraint_Kind,
    input: World_Angle_Constraint_Input) -> (u16, core.Shape_World_Status) {
    if kind != .Max_Angle && kind != .Min_Angle {
        return 0, .Invalid_Argument
    }
    constraint := core.Shape_Constraint{kind = kind, enabled = input.enabled}
    constraint.payload.angle = {first = input.first, pivot = input.pivot,
        second = input.second, limit = input.limit, movement = input.movement}
    return world_create_constraint(world, constraint)
}

// Append one center-pivot constraint with three direct transform targets.
world_create_center_pivot_constraint :: proc(
    world: ^core.Shape_World,
    input: World_Center_Pivot_Constraint_Input) -> (u16, core.Shape_World_Status) {
    constraint := core.Shape_Constraint{kind = .Center_Pivot, enabled = input.enabled}
    constraint.payload.center_pivot = {
        first = input.first, pivot = input.pivot, second = input.second,
        limb_length = input.limb_length}
    return world_create_constraint(world, constraint)
}

// Resolve one mutable transform only after entity generation and membership checks.
world_constraint_transform :: proc(
    world: ^core.Shape_World,
    entity: core.Shape_Entity) -> (^core.Shape_Transform, bool) {
    if world == nil {
        return nil, false
    }
    return core.shape_component_get_mut(&world.transforms, &world.registry, entity)
}

// Compute one direct-target constraint's current scalar error.
world_constraint_error :: proc(
    world: ^core.Shape_World,
    constraint: ^core.Shape_Constraint) -> f32 {
    if world == nil || constraint == nil || !constraint.enabled ||
        !core.shape_constraint_targets_resolve(world, constraint^) {
        return 0
    }
    switch constraint.kind {
    case .Floor:
        return world_floor_constraint_error(world, constraint.payload.floor)
    case .Snap_To_Floor:
        return world_snap_to_floor_constraint_error(
            world, constraint.payload.snap_to_floor)
    case .Snap_Point:
        return world_snap_point_constraint_error(world, constraint.payload.snap_point)
    case .Distance:
        return world_distance_constraint_error(world, constraint.payload.distance)
    case .Max_Angle, .Min_Angle:
        return world_angle_constraint_error(world, constraint.kind,
            constraint.payload.angle)
    case .Center_Pivot:
        return world_center_pivot_constraint_error(
            world, constraint.payload.center_pivot)
    }
    return 0
}

// Compute total error in stable constraint insertion order.
world_total_constraint_error :: proc(world: ^core.Shape_World) -> f32 {
    if world == nil {
        return 0
    }
    total: f32
    for index in 0..<world.constraints.count {
        total += world_constraint_error(world, &world.constraints.values[index])
    }
    return total
}

// Apply one direct-target constraint after revalidating all required transforms.
world_apply_constraint :: proc(
    world: ^core.Shape_World,
    constraint: ^core.Shape_Constraint) {
    if world == nil || constraint == nil || !constraint.enabled ||
        !core.shape_constraint_targets_resolve(world, constraint^) {
        return
    }
    switch constraint.kind {
    case .Floor:
        world_apply_floor_constraint(world, constraint.payload.floor)
    case .Snap_To_Floor:
        world_apply_snap_to_floor_constraint(world, constraint.payload.snap_to_floor)
    case .Snap_Point:
        world_apply_snap_point_constraint(world, constraint.payload.snap_point)
    case .Distance:
        world_apply_distance_constraint(world, constraint.payload.distance)
    case .Max_Angle, .Min_Angle:
        world_apply_angle_constraint(world, constraint.kind, constraint.payload.angle)
    case .Center_Pivot:
        world_apply_center_pivot_constraint(world, constraint.payload.center_pivot)
    }
}

// Apply every active constraint in stable forward insertion order.
world_apply_all_constraints :: proc(world: ^core.Shape_World) {
    if world == nil {
        return
    }
    for index in 0..<world.constraints.count {
        world_apply_constraint(world, &world.constraints.values[index])
    }
}

// Apply every active constraint in stable reverse insertion order.
world_apply_all_constraints_reverse :: proc(world: ^core.Shape_World) {
    if world == nil {
        return
    }
    for index := int(world.constraints.count) - 1; index >= 0; index -= 1 {
        world_apply_constraint(world, &world.constraints.values[index])
    }
}

// Alternate solve passes until convergence or the fixed frame-work budget.
world_apply_all_constraints_to_error :: proc(
    world: ^core.Shape_World,
    allowed_error: f32) {
    reverse := false
    iterations := 0
    for world_total_constraint_error(world) > allowed_error &&
        iterations < WORLD_CONSTRAINT_SOLVE_ITERATION_LIMIT {
        if reverse {
            world_apply_all_constraints(world)
        } else {
            world_apply_all_constraints_reverse(world)
        }
        reverse = !reverse
        iterations += 1
    }
}

// Compute error below one direct floor height.
world_floor_constraint_error :: proc(
    world: ^core.Shape_World,
    payload: core.Shape_Floor_Constraint) -> f32 {
    transform, ok := world_constraint_transform(world, payload.point)
    if !ok || transform.position.z >= payload.height {
        return 0
    }
    return payload.height - transform.position.z
}

// Compute error outside one floor snapping allowance.
world_snap_to_floor_constraint_error :: proc(
    world: ^core.Shape_World,
    payload: core.Shape_Snap_To_Floor_Constraint) -> f32 {
    transform, ok := world_constraint_transform(world, payload.point)
    if !ok || math.abs(transform.position.z - payload.height) <= payload.allowance {
        return 0
    }
    return payload.height - transform.position.z
}

// Compute distance from one transform to its fixed snap position.
world_snap_point_constraint_error :: proc(
    world: ^core.Shape_World,
    payload: core.Shape_Snap_Point_Constraint) -> f32 {
    transform, ok := world_constraint_transform(world, payload.point)
    if !ok {
        return 0
    }
    return linalg.length(transform.position - payload.position)
}

// Compute absolute direct-endpoint distance error.
world_distance_constraint_error :: proc(
    world: ^core.Shape_World,
    payload: core.Shape_Distance_Constraint) -> f32 {
    first, first_ok := world_constraint_transform(world, payload.first)
    second, second_ok := world_constraint_transform(world, payload.second)
    if !first_ok || !second_ok {
        return 0
    }
    return math.abs(payload.length - linalg.length(first.position - second.position))
}

// Resolve pivot-relative vectors and included angle for one direct angle payload.
world_angle_constraint_limbs :: proc(
    world: ^core.Shape_World,
    payload: core.Shape_Angle_Constraint) -> (World_Angle_Constraint_Limbs, bool) {
    first, first_ok := world_constraint_transform(world, payload.first)
    pivot, pivot_ok := world_constraint_transform(world, payload.pivot)
    second, second_ok := world_constraint_transform(world, payload.second)
    if !first_ok || !pivot_ok || !second_ok {
        return {}, false
    }
    first_limb := first.position - pivot.position
    second_limb := second.position - pivot.position
    denominator := linalg.length(first_limb) * linalg.length(second_limb)
    if denominator == 0 {
        return {}, false
    }
    theta := math.acos(math.clamp(
        linalg.dot(first_limb, second_limb) / denominator, -1, 1))
    return {pivot.position, first_limb, second_limb,
        linalg.normalize(linalg.cross(first_limb, second_limb)), theta}, true
}

// Compute error outside one direct minimum or maximum angle bound.
world_angle_constraint_error :: proc(
    world: ^core.Shape_World,
    kind: core.Shape_Constraint_Kind,
    payload: core.Shape_Angle_Constraint) -> f32 {
    limbs, ok := world_angle_constraint_limbs(world, payload)
    if !ok {
        return 0
    }
    if kind == .Max_Angle && limbs.theta > payload.limit {
        return (limbs.theta - payload.limit) * (180.0 / math.PI)
    }
    if kind == .Min_Angle && limbs.theta < payload.limit {
        return (payload.limit - limbs.theta) * (180.0 / math.PI)
    }
    return 0
}

// Compute the target for planar centering or an upper equal-limb compass hinge.
world_center_pivot_target :: proc(
    first, pivot, second: Vector3,
    limb_length: f32) -> Vector3 {
    midpoint := (first + second) / 2.0
    if limb_length <= 0 {
        return {midpoint.x, midpoint.y, pivot.z}
    }
    half_x := (second.x - first.x) / 2.0
    half_y := (second.y - first.y) / 2.0
    height_squared := max(limb_length * limb_length -
        half_x * half_x - half_y * half_y, f32(0))
    return {midpoint.x, midpoint.y, midpoint.z + math.sqrt(height_squared)}
}

// Compute pivot displacement from its direct center-pivot target.
world_center_pivot_constraint_error :: proc(
    world: ^core.Shape_World,
    payload: core.Shape_Center_Pivot_Constraint) -> f32 {
    first, first_ok := world_constraint_transform(world, payload.first)
    pivot, pivot_ok := world_constraint_transform(world, payload.pivot)
    second, second_ok := world_constraint_transform(world, payload.second)
    if !first_ok || !pivot_ok || !second_ok {
        return 0
    }
    target := world_center_pivot_target(first.position, pivot.position,
        second.position, payload.limb_length)
    return math.abs(linalg.length(target - pivot.position))
}

// Apply one floor response to its direct transform target.
world_apply_floor_constraint :: proc(
    world: ^core.Shape_World,
    payload: core.Shape_Floor_Constraint) {
    transform, ok := world_constraint_transform(world, payload.point)
    if !ok || transform.position.z >= payload.height {
        return
    }
    offset := payload.height - transform.position.z
    transform.position.z = payload.height + offset * payload.bounce
}

// Apply one floor snap outside its allowed tolerance.
world_apply_snap_to_floor_constraint :: proc(
    world: ^core.Shape_World,
    payload: core.Shape_Snap_To_Floor_Constraint) {
    transform, ok := world_constraint_transform(world, payload.point)
    if !ok || math.abs(transform.position.z - payload.height) <= payload.allowance {
        return
    }
    transform.position.z = payload.height
}

// Apply one fixed-position snap to its direct transform target.
world_apply_snap_point_constraint :: proc(
    world: ^core.Shape_World,
    payload: core.Shape_Snap_Point_Constraint) {
    transform, ok := world_constraint_transform(world, payload.point)
    if ok {
        transform.position = payload.position
    }
}

// Apply one direct distance correction according to its movement policy.
world_apply_distance_constraint :: proc(
    world: ^core.Shape_World,
    payload: core.Shape_Distance_Constraint) {
    first, first_ok := world_constraint_transform(world, payload.first)
    second, second_ok := world_constraint_transform(world, payload.second)
    if !first_ok || !second_ok {
        return
    }
    if payload.movement == .Move_First {
        direction := linalg.normalize(first.position - second.position)
        first.position = second.position + direction * payload.length
    } else if payload.movement == .Move_Both {
        midpoint := (first.position + second.position) / 2.0
        direction := linalg.normalize(second.position - midpoint)
        second.position = midpoint + direction * (payload.length / 2.0)
        first.position = midpoint - direction * (payload.length / 2.0)
    } else {
        direction := linalg.normalize(second.position - first.position)
        second.position = first.position + direction * payload.length
    }
}

// Apply one direct angle correction according to its movement policy.
world_apply_angle_constraint :: proc(
    world: ^core.Shape_World,
    kind: core.Shape_Constraint_Kind,
    payload: core.Shape_Angle_Constraint) {
    limbs, ok := world_angle_constraint_limbs(world, payload)
    if !ok || kind == .Min_Angle && limbs.theta >= payload.limit ||
        kind == .Max_Angle && limbs.theta <= payload.limit {
        return
    }
    correction := math.abs(limbs.theta - payload.limit)
    direction := f32(1) if kind == .Min_Angle else f32(-1)
    first, _ := world_constraint_transform(world, payload.first)
    second, _ := world_constraint_transform(world, payload.second)
    if payload.movement != .Move_Second {
        amount := correction if payload.movement == .Move_First else correction / 2
        first.position = limbs.pivot + rotate_around_axis(
            limbs.first, limbs.axis, -direction * amount)
    }
    if payload.movement != .Move_First {
        amount := correction if payload.movement == .Move_Second else correction / 2
        second.position = limbs.pivot + rotate_around_axis(
            limbs.second, limbs.axis, direction * amount)
    }
}

// Apply planar centering or the upper equal-limb hinge to one pivot target.
world_apply_center_pivot_constraint :: proc(
    world: ^core.Shape_World,
    payload: core.Shape_Center_Pivot_Constraint) {
    first, first_ok := world_constraint_transform(world, payload.first)
    pivot, pivot_ok := world_constraint_transform(world, payload.pivot)
    second, second_ok := world_constraint_transform(world, payload.second)
    if !first_ok || !pivot_ok || !second_ok {
        return
    }
    pivot.position = world_center_pivot_target(first.position, pivot.position,
        second.position, payload.limb_length)
}
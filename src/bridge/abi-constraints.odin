package bridge

import "../core"
import "../shapes"

// Resolve one packed direct constraint target against the canonical world.
constraint_target :: proc(
    state: ^core.Euclid_General_State,
    packed: u64) -> (core.Shape_Entity, bool) {
    return bridge_shape_resolve(state, packed)
}

// Decode one bridge movement policy after validating its enum range.
constraint_movement :: proc(
    movement: i32) -> (core.Shape_Constraint_Movement_Policy, bool) {
    if movement < 0 || movement > i32(core.Shape_Constraint_Movement_Policy.Move_Second) {
        return {}, false
    }
    return core.Shape_Constraint_Movement_Policy(movement), true
}

// Append one floor constraint naming its transform directly.
@(export)
create_floor_constraint :: proc "c" (
    state: ^core.Euclid_General_State, point: u64,
    height, bounce: f32, enabled: u8) -> i32 {
    context = state^.saved_context
    entity, found := constraint_target(state, point)
    if !found {return BRIDGE_STATUS_NOT_FOUND}
    _, status := shapes.world_create_floor_constraint(state^.shape_world, {
        point = entity, height = height, bounce = bounce, enabled = enabled != 0})
    return bridge_shape_status(status)
}

// Append one snap-to-floor constraint naming its transform directly.
@(export)
create_snap_to_floor_constraint :: proc "c" (
    state: ^core.Euclid_General_State, point: u64,
    height, allowance: f32, enabled: u8) -> i32 {
    context = state^.saved_context
    entity, found := constraint_target(state, point)
    if !found {return BRIDGE_STATUS_NOT_FOUND}
    _, status := shapes.world_create_snap_to_floor_constraint(state^.shape_world, {
        point = entity, height = height, allowance = allowance,
        enabled = enabled != 0})
    return bridge_shape_status(status)
}

// Append one snap-point constraint naming its transform directly.
@(export)
create_snap_point_constraint :: proc "c" (
    state: ^core.Euclid_General_State, point: u64,
    position: core.Vector3, enabled: u8) -> i32 {
    context = state^.saved_context
    entity, found := constraint_target(state, point)
    if !found {return BRIDGE_STATUS_NOT_FOUND}
    _, status := shapes.world_create_snap_point_constraint(state^.shape_world, {
        point = entity, position = position, enabled = enabled != 0})
    return bridge_shape_status(status)
}

// Append one distance constraint naming both endpoint transforms directly.
@(export)
create_distance_constraint :: proc "c" (
    state: ^core.Euclid_General_State,
    input: Bridge_Distance_Constraint_Input) -> i32 {
    context = state^.saved_context
    first_entity, first_found := constraint_target(state, input.first)
    second_entity, second_found := constraint_target(state, input.second)
    policy, policy_valid := constraint_movement(input.movement)
    if !first_found || !second_found {return BRIDGE_STATUS_NOT_FOUND}
    if !policy_valid {return BRIDGE_STATUS_INVALID_ARGUMENT}
    _, status := shapes.world_create_distance_constraint(state^.shape_world, {
        first = first_entity, second = second_entity, length = input.length,
        movement = policy, enabled = input.enabled != 0})
    return bridge_shape_status(status)
}

// Append one maximum-angle constraint naming all three transforms directly.
@(export)
create_max_angle_constraint :: proc "c" (
    state: ^core.Euclid_General_State,
    input: Bridge_Angle_Constraint_Input) -> i32 {
    context = state^.saved_context
    return create_angle_constraint(state, .Max_Angle, input)
}

// Append one minimum-angle constraint naming all three transforms directly.
@(export)
create_min_angle_constraint :: proc "c" (
    state: ^core.Euclid_General_State,
    input: Bridge_Angle_Constraint_Input) -> i32 {
    context = state^.saved_context
    return create_angle_constraint(state, .Min_Angle, input)
}

// Validate and append one direct-target angle constraint.
create_angle_constraint :: proc(
    state: ^core.Euclid_General_State, kind: core.Shape_Constraint_Kind,
    input: Bridge_Angle_Constraint_Input) -> i32 {
    first_entity, first_found := constraint_target(state, input.first)
    pivot_entity, pivot_found := constraint_target(state, input.pivot)
    second_entity, second_found := constraint_target(state, input.second)
    policy, policy_valid := constraint_movement(input.movement)
    if !first_found || !pivot_found || !second_found {
        return BRIDGE_STATUS_NOT_FOUND
    }
    if !policy_valid {return BRIDGE_STATUS_INVALID_ARGUMENT}
    _, status := shapes.world_create_angle_constraint(state^.shape_world, kind, {
        first = first_entity, pivot = pivot_entity, second = second_entity,
        limit = input.limit, movement = policy, enabled = input.enabled != 0})
    return bridge_shape_status(status)
}

// Append one center-pivot constraint naming all three transforms directly.
@(export)
create_center_pivot_constraint :: proc "c" (
    state: ^core.Euclid_General_State,
    first, pivot, second: u64, enabled: u8) -> i32 {
    context = state^.saved_context
    first_entity, first_found := constraint_target(state, first)
    pivot_entity, pivot_found := constraint_target(state, pivot)
    second_entity, second_found := constraint_target(state, second)
    if !first_found || !pivot_found || !second_found {
        return BRIDGE_STATUS_NOT_FOUND
    }
    _, status := shapes.world_create_center_pivot_constraint(state^.shape_world, {
        first = first_entity, pivot = pivot_entity, second = second_entity,
        enabled = enabled != 0})
    return bridge_shape_status(status)
}

// Return aggregate error across the canonical direct-target constraint store.
@(export)
get_total_constraint_error_bridge :: proc "c" (
    state: ^core.Euclid_General_State) -> f32 {
    context = state^.saved_context
    return shapes.world_total_constraint_error(state^.shape_world)
}

// Apply every canonical direct-target constraint once in the requested order.
@(export)
apply_all_constraints_bridge :: proc "c" (
    state: ^core.Euclid_General_State, reverse: u8) -> i32 {
    context = state^.saved_context
    if state^.shape_world == nil {return BRIDGE_STATUS_ILLEGAL_STATE}
    if reverse != 0 {
        shapes.world_apply_all_constraints_reverse(state^.shape_world)
    } else {
        shapes.world_apply_all_constraints(state^.shape_world)
    }
    return BRIDGE_STATUS_OK
}

// Solve canonical direct-target constraints within one bounded iteration budget.
@(export)
solve_constraints_to_error :: proc "c" (
    state: ^core.Euclid_General_State, allowable_error: f32,
    max_iterations: i32) -> Bridge_Solve_Result {
    context = state^.saved_context
    if state^.shape_world == nil || allowable_error < 0 {
        return make_solve_result(BRIDGE_STATUS_INVALID_ARGUMENT, 0, 0, 0, 0)
    }
    iteration_limit := max_iterations
    if iteration_limit <= 0 {iteration_limit = 32}
    if iteration_limit > 4096 {iteration_limit = 4096}
    initial_error := shapes.world_total_constraint_error(state^.shape_world)
    error := initial_error
    iterations: i32
    for error > allowable_error && iterations < iteration_limit {
        if iterations & 1 == 0 {
            shapes.world_apply_all_constraints_reverse(state^.shape_world)
        } else {
            shapes.world_apply_all_constraints(state^.shape_world)
        }
        iterations += 1
        error = shapes.world_total_constraint_error(state^.shape_world)
    }
    converged := error <= allowable_error
    status := converged ? i32(BRIDGE_STATUS_OK) : i32(BRIDGE_STATUS_NON_CONVERGED)
    return make_solve_result(status, iterations, initial_error, error, to_u8(converged))
}

// Build one bridge-safe solver outcome.
make_solve_result :: proc(
    status, iterations: i32, initial_error, final_error: f32,
    converged: u8) -> Bridge_Solve_Result {
    return {status, iterations, initial_error, final_error, converged}
}

package bridge_abi

import scene "../scene"
import core "../../core"

// Append one floor constraint naming its transform directly.
@(export)
create_floor_constraint :: proc "c" (
    state: ^core.Euclid_General_State,
    point: u64,
    height, bounce: f32,
    enabled: u8) -> i32 {
    return scene.create_floor_constraint(state, point, height, bounce, enabled)
}

// Append one snap-to-floor constraint naming its transform directly.
@(export)
create_snap_to_floor_constraint :: proc "c" (
    state: ^core.Euclid_General_State,
    point: u64,
    height, allowance: f32,
    enabled: u8) -> i32 {
    return scene.create_snap_to_floor_constraint(state, point, height, allowance, enabled)
}

// Append one snap-point constraint naming its transform directly.
@(export)
create_snap_point_constraint :: proc "c" (
    state: ^core.Euclid_General_State,
    point: u64,
    position: scene.Vector3,
    enabled: u8) -> i32 {
    return scene.create_snap_point_constraint(state, point, position, enabled)
}

// Append one distance constraint naming both endpoint transforms directly.
@(export)
create_distance_constraint :: proc "c" (
    state: ^core.Euclid_General_State,
    input: scene.Bridge_Distance_Constraint_Input) -> i32 {
    return scene.create_distance_constraint(state, input)
}

// Append one maximum-angle constraint naming all three transforms directly.
@(export)
create_max_angle_constraint :: proc "c" (
    state: ^core.Euclid_General_State,
    input: scene.Bridge_Angle_Constraint_Input) -> i32 {
    return scene.create_max_angle_constraint(state, input)
}

// Append one minimum-angle constraint naming all three transforms directly.
@(export)
create_min_angle_constraint :: proc "c" (
    state: ^core.Euclid_General_State,
    input: scene.Bridge_Angle_Constraint_Input) -> i32 {
    return scene.create_min_angle_constraint(state, input)
}

// Append one center-pivot constraint naming all three transforms directly.
@(export)
create_center_pivot_constraint :: proc "c" (
    state: ^core.Euclid_General_State,
    first, pivot, second: u64,
    enabled: u8) -> i32 {
    return scene.create_center_pivot_constraint(state, first, pivot, second, enabled)
}

// Return aggregate error across the canonical direct-target constraint store.
@(export)
get_total_constraint_error_bridge :: proc "c" (state: ^core.Euclid_General_State) -> f32 {
    return scene.get_total_constraint_error_bridge(state)
}

// Apply every canonical direct-target constraint once in the requested order.
@(export)
apply_all_constraints_bridge :: proc "c" (
    state: ^core.Euclid_General_State,
    reverse: u8) -> i32 {
    return scene.apply_all_constraints_bridge(state, reverse)
}

// Solve canonical direct-target constraints within one bounded iteration budget.
@(export)
solve_constraints_to_error :: proc "c" (
    state: ^core.Euclid_General_State,
    allowable_error: f32,
    max_iterations: i32) -> scene.Bridge_Solve_Result {
    return scene.solve_constraints_to_error(state, allowable_error, max_iterations)
}

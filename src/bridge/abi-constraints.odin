package bridge

import "../core"
import "../shapes"

//   Return compile-time capacity limits exposed by the bridge ABI.
//
// Returns:
//   - Bridge integer value for the requested capability, index, or status code.
@(export)
get_constraint_capacity :: proc "c" () -> i32 {
    return i32(MAX_SHAPESCONSTRAINTS)
}

//   Return the next allocation index in the active runtime system for incremental creation.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//
// Returns:
//   - Bridge integer value for the requested capability, index, or status code.
@(export)
get_constraint_next_index :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
    return i32(state^.point_system^.next_constraint_index)
}

//   Report whether an index is currently within the valid bridge addressable range.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Target point or constraint index for this bridge operation.
//
// Returns:
//   - 1 when true, 0 when false for C ABI compatibility.
@(export)
is_constraint_index_in_range :: proc "c" (
    state: ^core.Euclid_General_State, index: i32) -> u8 {

    context = state^.saved_context

    _ = state
    return to_u8(is_constraint_index_in_bounds(int(index)))
}

//   Build a bridge-safe snapshot of a constraint entry and its optional child offset field.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Target point or constraint index for this bridge operation.
//
// Returns:
//   - Snapshot struct with valid=0 and sentinel fields when index lookup fails.
@(export)
get_constraint_view :: proc "c" (
    state: ^core.Euclid_General_State, index: i32) -> Bridge_Constraint_View {

    context = state^.saved_context

    constraint_index := int(index)
    if !is_constraint_index_in_bounds(constraint_index) {
        return constraint_view_invalid()
    }

    constraint := state^.point_system^.constraints[constraint_index]
    child_offset, has_child_offset := constraint.child_offset.?

    return Bridge_Constraint_View{
        valid = 1,
        index = index,
        traits = i32(constraint.kind),
        on_point = i32(constraint.on_point),
        restriction = constraint.restriction,
        bounce = constraint.bounce,
        allowance = constraint.allowance,
        depend_on = constraint.depend_on,
        has_child_offset = to_u8(has_child_offset),
        child_offset = child_offset,
        do_apply = to_u8(constraint.do_apply),
    }
}

//   Create or mutate constraint records through validated bridge operations.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - spec: Constraint specification payload used for create/update operations.
//   - out_index: Optional output pointer that receives the created constraint index.
//
// Returns:
//   - Bridge status code where 0 is success and non-zero values map to BRIDGE_STATUS_* constants.
//
// Notes:
//   - Use BRIDGE_STATUS_* constants to branch on invalid indices, arguments, or graph state failures.
@(export)
create_constraint :: proc "c" (
    state: ^core.Euclid_General_State,
    spec: Bridge_Constraint_Spec, out_index: ^i32) -> i32 {

    context = state^.saved_context

    next_index := state^.point_system^.next_constraint_index
    status := validate_constraint_create(spec, next_index)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    on_point := int(spec.on_point)
    state^.point_system^.constraints[next_index] = core.Shapes_Constraint{
        kind = core.Shapes_Constraint_Kind(spec.traits),
        on_point = on_point,
        restriction = spec.restriction,
        bounce = spec.bounce,
        allowance = spec.allowance,
        depend_on = spec.depend_on,
        child_offset = nil,
        do_apply = spec.do_apply != 0,
    }
    if spec.has_child_offset != 0 {
        state^.point_system^.constraints[next_index].child_offset = spec.child_offset
    }

    state^.point_system^.next_constraint_index += 1
    if out_index != nil {
        out_index^ = i32(next_index)
    }
    return BRIDGE_STATUS_OK
}

//   Create or mutate constraint records through validated bridge operations.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Target point or constraint index for this bridge operation.
//   - spec_mask: Bitmask selecting which fields from spec are applied during update.
//   - spec: Constraint specification payload used for create/update operations.
//
// Returns:
//   - Bridge status code where 0 is success and non-zero values map to BRIDGE_STATUS_* constants.
//
// Notes:
//   - Use BRIDGE_STATUS_* constants to branch on invalid indices, arguments, or graph state failures.
@(export)
update_constraint :: proc "c" (
    state: ^core.Euclid_General_State, index: i32, spec_mask: i32,
    spec: Bridge_Constraint_Spec) -> i32 {

    context = state^.saved_context

    constraint_index := int(index)
    if !is_constraint_index_in_bounds(constraint_index) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    constraint := &state^.point_system^.constraints[constraint_index]

    status := apply_constraint_spec_identity(constraint, spec_mask, spec)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    apply_constraint_spec_response(constraint, spec_mask, spec)

    return apply_constraint_spec_links(constraint, spec_mask, spec)
}

//   Enable or disable one existing constraint.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Target point or constraint index for this bridge operation.
//   - enabled: Non-zero to enable behavior; zero to disable.
//
// Returns:
//   - Bridge status code where 0 is success and non-zero values map to BRIDGE_STATUS_* constants.
//
// Notes:
//   - Use BRIDGE_STATUS_* constants to branch on invalid indices, arguments, or graph state failures.
@(export)
set_constraint_enabled :: proc "c" (
    state: ^core.Euclid_General_State, index: i32, enabled: u8) -> i32 {

    context = state^.saved_context

    constraint_index := int(index)
    if !is_constraint_index_in_bounds(constraint_index) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    state^.point_system^.constraints[constraint_index].do_apply = enabled != 0
    return BRIDGE_STATUS_OK
}

//   Clear one existing constraint slot and mark it disabled.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Target point or constraint index for this bridge operation.
//
// Returns:
//   - Bridge status code where 0 is success and non-zero values map to BRIDGE_STATUS_* constants.
//
// Notes:
//   - Use BRIDGE_STATUS_* constants to branch on invalid indices, arguments, or graph state failures.
@(export)
clear_constraint :: proc "c" (state: ^core.Euclid_General_State, index: i32) -> i32 {
    context = state^.saved_context
    constraint_index := int(index)
    if !is_constraint_index_in_bounds(constraint_index) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    state^.point_system^.constraints[constraint_index] = {}
    state^.point_system^.constraints[constraint_index].do_apply = false
    return BRIDGE_STATUS_OK
}

//   Expose constraint error measurements from the solver for Julia-side control logic.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//
// Returns:
//   - Single-precision value reported by the host constraint or metadata subsystem.
@(export)
get_total_constraint_error_bridge :: proc "c" (
    state: ^core.Euclid_General_State) -> f32 {
    context = state^.saved_context
    return shapes.get_total_constraint_error(state^.point_system)
}

//   Expose constraint error measurements from the solver for Julia-side control logic.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - constraint_index: Target point or constraint index for this bridge operation.
//   - out_error: Output pointer that receives computed error for one constraint.
//
// Returns:
//   - Bridge integer value for the requested capability, index, or status code.
@(export)
get_constraint_error_bridge :: proc "c" (
    state: ^core.Euclid_General_State, constraint_index: i32, out_error: ^f32) -> i32 {

    context = state^.saved_context

    idx := int(constraint_index)
    if !is_constraint_index_in_bounds(idx) {
        return BRIDGE_STATUS_INVALID_INDEX
    }
    if out_error == nil {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }

    constraint := &state^.point_system^.constraints[idx]
    out_error^ = shapes.get_constraint_error(constraint, &state^.point_system^.points)
    return BRIDGE_STATUS_OK
}

//   Run constraint solver work through the bridge and report convergence/status outcomes.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - constraint_index: Target point or constraint index for this bridge operation.
//
// Returns:
//   - Bridge status code where 0 is success and non-zero values map to BRIDGE_STATUS_* constants.
//
// Notes:
//   - Use BRIDGE_STATUS_* constants to branch on invalid indices, arguments, or graph state failures.
@(export)
apply_constraint_bridge :: proc "c" (
    state: ^core.Euclid_General_State, constraint_index: i32) -> i32 {

    context = state^.saved_context

    idx := int(constraint_index)
    if !is_constraint_index_in_bounds(idx) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    constraint := &state^.point_system^.constraints[idx]
    shapes.apply_constraint(constraint, &state^.point_system^.points)
    return BRIDGE_STATUS_OK
}

//   Run constraint solver work through the bridge and report convergence/status outcomes.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - reverse: Non-zero to apply constraints in reverse traversal order.
//
// Returns:
//   - Bridge status code where 0 is success and non-zero values map to BRIDGE_STATUS_* constants.
//
// Notes:
//   - Use BRIDGE_STATUS_* constants to branch on invalid indices, arguments, or graph state failures.
@(export)
apply_all_constraints_bridge :: proc "c" (
    state: ^core.Euclid_General_State, reverse: u8) -> i32 {

    context = state^.saved_context

    if reverse != 0 {
        shapes.apply_all_constraints_reverse(state^.point_system)
    } else {
        shapes.apply_all_constraints(state^.point_system)
    }
    return BRIDGE_STATUS_OK
}

//   Run constraint solver work through the bridge and report convergence/status outcomes.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - allowable_error: Target maximum total constraint error for iterative solving.
//   - max_iterations: Maximum solve iterations to attempt before reporting non-convergence.
//
// Returns:
//   - Structured solver outcome including status, iteration count, error bounds, and converged flag.
//
// Notes:
//   - If status is BRIDGE_STATUS_NON_CONVERGED, inspect final_error to decide next solver action.
@(export)
solve_constraints_to_error :: proc "c" (
    state: ^core.Euclid_General_State, allowable_error: f32,
    max_iterations: i32) -> Bridge_Solve_Result {

    context = state^.saved_context

    if allowable_error < 0 {
        return make_solve_result(BRIDGE_STATUS_INVALID_ARGUMENT, 0, 0, 0, 0)
    }

    iteration_limit := max_iterations
    if iteration_limit <= 0 {
        iteration_limit = 32
    }
    if iteration_limit > 4096 {
        iteration_limit = 4096
    }

    initial_error := shapes.get_total_constraint_error(state^.point_system)
    if initial_error <= allowable_error {
        return make_solve_result(BRIDGE_STATUS_OK, 0, initial_error, initial_error, 1)
    }

    iterations, error := run_constraint_iterations(
        state^.point_system, allowable_error, iteration_limit)

    converged := error <= allowable_error
    status := i32(BRIDGE_STATUS_NON_CONVERGED)
    if converged {
        status = BRIDGE_STATUS_OK
    }

    return make_solve_result(
        status, iterations, initial_error, error, to_u8(converged))
}

//   Validate a constraint create spec and the next available constraint index.
//
// Parameters:
//   - spec: Constraint specification payload used for the create operation.
//   - next_index: Next free constraint index in the point system.
//
// Returns:
//   - BRIDGE_STATUS_OK when the spec and index are valid, otherwise the matching error status.
validate_constraint_create :: proc(spec: Bridge_Constraint_Spec, next_index: int) -> i32 {
    if !is_valid_constraint_kind_value(spec.traits) {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }
    if !is_point_index_in_bounds(int(spec.on_point)) {
        return BRIDGE_STATUS_INVALID_INDEX
    }
    if spec.depend_on >= 0 && !is_constraint_index_in_bounds(int(spec.depend_on)) {
        return BRIDGE_STATUS_INVALID_INDEX
    }
    if spec.has_child_offset != 0 && spec.child_offset < 0 {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }
    if next_index < 0 || next_index >= MAX_SHAPESCONSTRAINTS {
        return BRIDGE_STATUS_OUT_OF_CAPACITY
    }
    return BRIDGE_STATUS_OK
}

//   Build a solver outcome payload from its status, iteration, and error fields.
//
// Parameters:
//   - status: Bridge status code for the solve outcome.
//   - iterations: Number of solver iterations applied.
//   - initial_error: Total constraint error before solving.
//   - final_error: Total constraint error after solving.
//   - converged: Non-zero when the solver met the allowable error target.
//
// Returns:
//   - Populated bridge solve result payload.
make_solve_result :: proc(
    status: i32, iterations: i32, initial_error: f32, final_error: f32,
    converged: u8) -> Bridge_Solve_Result {

    return Bridge_Solve_Result{
        status = status,
        iterations = iterations,
        initial_error = initial_error,
        final_error = final_error,
        converged = converged,
    }
}

//   Run alternating forward/reverse solver passes until convergence or the limit.
//
// Parameters:
//   - point_system: Point system whose constraints are applied.
//   - allowable_error: Target maximum total constraint error.
//   - iteration_limit: Maximum solve iterations to attempt.
//
// Returns:
//   - iterations: Number of iterations applied.
//   - error: Total constraint error after the final iteration.
run_constraint_iterations :: proc(
    point_system: ^core.Shapes_Point_System, allowable_error: f32,
    iteration_limit: i32) -> (i32, f32) {

    reverse := false
    error := shapes.get_total_constraint_error(point_system)
    iterations: i32 = 0
    for iterations < iteration_limit && error > allowable_error {
        if reverse {
            shapes.apply_all_constraints_reverse(point_system)
        } else {
            shapes.apply_all_constraints(point_system)
        }
        reverse = !reverse
        iterations += 1
        error = shapes.get_total_constraint_error(point_system)
    }
    return iterations, error
}


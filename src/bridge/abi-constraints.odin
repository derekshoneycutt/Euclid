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

    constraintIndex := int(index)
    if !is_constraint_index_in_bounds(constraintIndex) {
        return constraint_view_invalid()
    }

    constraint := state^.point_system^.constraints[constraintIndex]
    childOffset, hasChildOffset := constraint.child_offset.?

    return Bridge_Constraint_View{
        valid = 1,
        index = index,
        traits = i32(constraint.kind),
        on_point = i32(constraint.on_point),
        restriction = constraint.restriction,
        bounce = constraint.bounce,
        allowance = constraint.allowance,
        depend_on = constraint.depend_on,
        has_child_offset = to_u8(hasChildOffset),
        child_offset = childOffset,
        do_apply = to_u8(constraint.do_apply),
    }
}

//   Create or mutate constraint records through validated bridge operations.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - spec: Constraint specification payload used for create/update operations.
//   - outIndex: Optional output pointer that receives the created constraint index.
//
// Returns:
//   - Bridge status code where 0 is success and non-zero values map to BRIDGE_STATUS_* constants.
//
// Notes:
//   - Use BRIDGE_STATUS_* constants to branch on invalid indices, arguments, or graph state failures.
@(export)
create_constraint :: proc "c" (
    state: ^core.Euclid_General_State,
    spec: Bridge_Constraint_Spec, outIndex: ^i32) -> i32 {

    context = state^.saved_context

    if !is_valid_constraint_kind_value(spec.traits) {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }

    onPoint := int(spec.on_point)
    if !is_point_index_in_bounds(onPoint) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    if spec.depend_on >= 0 && !is_constraint_index_in_bounds(int(spec.depend_on)) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    if spec.has_child_offset != 0 && spec.child_offset < 0 {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }

    nextIndex := state^.point_system^.next_constraint_index
    if nextIndex < 0 || nextIndex >= MAX_SHAPESCONSTRAINTS {
        return BRIDGE_STATUS_OUT_OF_CAPACITY
    }

    state^.point_system^.constraints[nextIndex] = core.Shapes_Constraint{
        kind = core.Shapes_Constraint_Kind(spec.traits),
        on_point = onPoint,
        restriction = spec.restriction,
        bounce = spec.bounce,
        allowance = spec.allowance,
        depend_on = spec.depend_on,
        child_offset = nil,
        do_apply = spec.do_apply != 0,
    }
    if spec.has_child_offset != 0 {
        state^.point_system^.constraints[nextIndex].child_offset = spec.child_offset
    }

    state^.point_system^.next_constraint_index += 1
    if outIndex != nil {
        outIndex^ = i32(nextIndex)
    }
    return BRIDGE_STATUS_OK
}

//   Create or mutate constraint records through validated bridge operations.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - index: Target point or constraint index for this bridge operation.
//   - specMask: Bitmask selecting which fields from spec are applied during update.
//   - spec: Constraint specification payload used for create/update operations.
//
// Returns:
//   - Bridge status code where 0 is success and non-zero values map to BRIDGE_STATUS_* constants.
//
// Notes:
//   - Use BRIDGE_STATUS_* constants to branch on invalid indices, arguments, or graph state failures.
@(export)
update_constraint :: proc "c" (
    state: ^core.Euclid_General_State, index: i32, specMask: i32,
    spec: Bridge_Constraint_Spec) -> i32 {

    context = state^.saved_context

    constraintIndex := int(index)
    if !is_constraint_index_in_bounds(constraintIndex) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    constraint := &state^.point_system^.constraints[constraintIndex]

    if specMask & CONSTRAINT_SPEC_TRAITS != 0 {
        if !is_valid_constraint_kind_value(spec.traits) {
            return BRIDGE_STATUS_INVALID_ARGUMENT
        }
        constraint^.kind = core.Shapes_Constraint_Kind(spec.traits)
    }
    if specMask & CONSTRAINT_SPEC_ONPOINT != 0 {
        onPoint := int(spec.on_point)
        if !is_point_index_in_bounds(onPoint) {
            return BRIDGE_STATUS_INVALID_INDEX
        }
        constraint^.on_point = onPoint
    }
    if specMask & CONSTRAINT_SPEC_RESTRICTION != 0 {
        constraint^.restriction = spec.restriction
    }
    if specMask & CONSTRAINT_SPEC_BOUNCE != 0 {
        constraint^.bounce = spec.bounce
    }
    if specMask & CONSTRAINT_SPEC_ALLOWANCE != 0 {
        constraint^.allowance = spec.allowance
    }
    if specMask & CONSTRAINT_SPEC_DEPENDON != 0 {
        if spec.depend_on >= 0 && !is_constraint_index_in_bounds(int(spec.depend_on)) {
            return BRIDGE_STATUS_INVALID_INDEX
        }
        constraint^.depend_on = spec.depend_on
    }
    if specMask & CONSTRAINT_SPEC_CHILDOFFSET != 0 {
        if spec.has_child_offset != 0 {
            if spec.child_offset < 0 {
                return BRIDGE_STATUS_INVALID_ARGUMENT
            }
            constraint^.child_offset = spec.child_offset
        } else {
            constraint^.child_offset = nil
        }
    }
    if specMask & CONSTRAINT_SPEC_DOAPPLY != 0 {
        constraint^.do_apply = spec.do_apply != 0
    }

    return BRIDGE_STATUS_OK
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

    constraintIndex := int(index)
    if !is_constraint_index_in_bounds(constraintIndex) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    state^.point_system^.constraints[constraintIndex].do_apply = enabled != 0
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
    constraintIndex := int(index)
    if !is_constraint_index_in_bounds(constraintIndex) {
        return BRIDGE_STATUS_INVALID_INDEX
    }

    state^.point_system^.constraints[constraintIndex] = {}
    state^.point_system^.constraints[constraintIndex].do_apply = false
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
//   - constraintIndex: Target point or constraint index for this bridge operation.
//   - outError: Output pointer that receives computed error for one constraint.
//
// Returns:
//   - Bridge integer value for the requested capability, index, or status code.
@(export)
get_constraint_error_bridge :: proc "c" (
    state: ^core.Euclid_General_State, constraintIndex: i32, outError: ^f32) -> i32 {

    context = state^.saved_context

    idx := int(constraintIndex)
    if !is_constraint_index_in_bounds(idx) {
        return BRIDGE_STATUS_INVALID_INDEX
    }
    if outError == nil {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }

    constraint := &state^.point_system^.constraints[idx]
    outError^ = shapes.get_constraint_error(constraint, &state^.point_system^.points)
    return BRIDGE_STATUS_OK
}

//   Run constraint solver work through the bridge and report convergence/status outcomes.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - constraintIndex: Target point or constraint index for this bridge operation.
//
// Returns:
//   - Bridge status code where 0 is success and non-zero values map to BRIDGE_STATUS_* constants.
//
// Notes:
//   - Use BRIDGE_STATUS_* constants to branch on invalid indices, arguments, or graph state failures.
@(export)
apply_constraint_bridge :: proc "c" (
    state: ^core.Euclid_General_State, constraintIndex: i32) -> i32 {

    context = state^.saved_context

    idx := int(constraintIndex)
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
//   - allowableError: Target maximum total constraint error for iterative solving.
//   - maxIterations: Maximum solve iterations to attempt before reporting non-convergence.
//
// Returns:
//   - Structured solver outcome including status, iteration count, error bounds, and converged flag.
//
// Notes:
//   - If status is BRIDGE_STATUS_NON_CONVERGED, inspect final_error to decide next solver action.
@(export)
solve_constraints_to_error :: proc "c" (
    state: ^core.Euclid_General_State, allowableError: f32,
    maxIterations: i32) -> Bridge_Solve_Result {

    context = state^.saved_context

    if allowableError < 0 {
        return Bridge_Solve_Result{
            status = BRIDGE_STATUS_INVALID_ARGUMENT,
            iterations = 0,
            initial_error = 0,
            final_error = 0,
            converged = 0,
        }
    }

    iterationLimit := maxIterations
    if iterationLimit <= 0 {
        iterationLimit = 32
    }
    if iterationLimit > 4096 {
        iterationLimit = 4096
    }

    initialError := shapes.get_total_constraint_error(state^.point_system)
    if initialError <= allowableError {
        return Bridge_Solve_Result{
            status = BRIDGE_STATUS_OK,
            iterations = 0,
            initial_error = initialError,
            final_error = initialError,
            converged = 1,
        }
    }

    reverse := false
    error := initialError
    iterations: i32 = 0
    for iterations < iterationLimit && error > allowableError {
        if reverse {
            shapes.apply_all_constraints_reverse(state^.point_system)
        } else {
            shapes.apply_all_constraints(state^.point_system)
        }
        reverse = !reverse
        iterations += 1
        error = shapes.get_total_constraint_error(state^.point_system)
    }

    converged := error <= allowableError
    status : i32 = BRIDGE_STATUS_NON_CONVERGED
    if converged {
        status = BRIDGE_STATUS_OK
    }

    return Bridge_Solve_Result{
        status = status,
        iterations = iterations,
        initial_error = initialError,
        final_error = error,
        converged = to_u8(converged),
    }
}


package bridge_abi

import exercise "../exercise"
import core "../../core"

// Queue one copied user-store operation for display-owner worker admission.
@(export)
begin_user_exercise_operation :: proc "c" (
    state: ^core.Euclid_General_State,
    input: ^exercise.User_Exercise_Input,
    token: ^u64) -> i32 {
    return exercise.begin_user_exercise_operation(state, input, token)
}

// Copy a completed user-store result into caller-owned bounded buffers.
@(export)
poll_user_exercise_operation :: proc "c" (
    state: ^core.Euclid_General_State,
    token: u64,
    metadata: ^exercise.Exercise_Query_Metadata,
    buffers: ^exercise.Exercise_Query_Buffers) -> i32 {
    return exercise.poll_user_exercise_operation(state, token, metadata, buffers)
}

// Abandon only the named operation; worker completion is still drained by the display.
@(export)
cancel_user_exercise_operation :: proc "c" (
    state: ^core.Euclid_General_State,
    token: u64) {
    exercise.cancel_user_exercise_operation(state, token)
}

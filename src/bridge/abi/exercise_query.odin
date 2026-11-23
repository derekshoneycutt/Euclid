package bridge_abi

import exercise "../exercise"
import core "../../core"

// Queue one validated operation; the display owner alone submits work to SQLite.
@(export)
begin_exercise_query :: proc "c" (
    state: ^core.Euclid_General_State,
    input: ^exercise.Exercise_Query_Input,
    token: ^u64) -> i32 {
    return exercise.begin_exercise_query(state, input, token)
}

// Copy a completed reply into Julia-owned buffers, or report that it remains pending.
@(export)
poll_exercise_query :: proc "c" (
    state: ^core.Euclid_General_State,
    token: u64,
    metadata: ^exercise.Exercise_Query_Metadata,
    buffers: ^exercise.Exercise_Query_Buffers) -> i32 {
    return exercise.poll_exercise_query(state, token, metadata, buffers)
}

// Abandon only the named operation; late worker replies remain harmless and drain normally.
@(export)
cancel_exercise_query :: proc "c" (state: ^core.Euclid_General_State, token: u64) {
    exercise.cancel_exercise_query(state, token)
}

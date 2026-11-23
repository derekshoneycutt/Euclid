package bridge_abi

import exercise "../exercise"
import core "../../core"

// Validate and enqueue plain UTF-8 header text without mutating display-owned state.
@(export)
publish_exercise_header :: proc "c" (
    state: ^core.Euclid_General_State,
    source: ^u8,
    byte_count: i32) -> i32 {
    return exercise.publish_exercise_header(state, source, byte_count)
}

// Enqueue the shared dismissal operation without mutating display-owned state.
@(export)
hide_exercise_header :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
    return exercise.hide_exercise_header(state)
}

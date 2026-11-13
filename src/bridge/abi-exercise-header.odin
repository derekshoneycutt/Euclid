package bridge

import bridgemodel "model"
import core "../core"
import exerciseheader "../core/exercise_header"

//   Map header-update admission outcomes onto the stable bridge status contract.
exercise_header_bridge_status :: proc(
    outcome: bridgemodel.Communication_Send_Outcome) -> i32 {
    switch outcome {
    case .Sent:
        return BRIDGE_STATUS_OK
    case .Queue_Full, .Allocation_Failed:
        return BRIDGE_STATUS_OUT_OF_CAPACITY
    case .Runtime_Stopping, .Channel_Closed:
        return BRIDGE_STATUS_ILLEGAL_STATE
    }
    return BRIDGE_STATUS_ILLEGAL_STATE
}

// Validate and enqueue plain UTF-8 header text without mutating display-owned state.
@(export)
publish_exercise_header :: proc "c" (
    state: ^core.Euclid_General_State, source: ^u8, byte_count: i32) -> i32 {
    if state == nil || state^.julia_runtime_service == nil ||
        !state^.terminal.initialized || state^.terminal.animation_generation == 0 {
        return BRIDGE_STATUS_ILLEGAL_STATE
    }
    if byte_count <= 0 ||
        byte_count > i32(exerciseheader.EXERCISE_HEADER_MAX_TEXT_BYTES) ||
        source == nil {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }
    context = state^.saved_context
    source_bytes := cast([^]u8)source
    text := source_bytes[:int(byte_count)]
    if !exerciseheader.text_is_valid(text) {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }
    return exercise_header_bridge_status(
        send_exercise_header_update(state, true, text))
}

// Enqueue the shared dismissal operation without mutating display-owned state.
@(export)
hide_exercise_header :: proc "c" (
    state: ^core.Euclid_General_State) -> i32 {
    if state == nil || state^.julia_runtime_service == nil ||
        !state^.terminal.initialized || state^.terminal.animation_generation == 0 {
        return BRIDGE_STATUS_ILLEGAL_STATE
    }
    context = state^.saved_context
    return exercise_header_bridge_status(
        send_exercise_header_update(state, false, nil))
}

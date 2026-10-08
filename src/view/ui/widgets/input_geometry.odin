package uiwidgets

import input "../../input"
import geometry "../../../core/geometry"

// Convert one portable screen position for UI geometry operations.
input_frame_mouse_position :: #force_inline proc(
    frame: input.Input_Frame) -> geometry.Vector2 {
    return {frame.mouse_position.x, frame.mouse_position.y}
}

// Report whether the primary pointer button was pressed this frame.
input_frame_left_pressed :: #force_inline proc(frame: input.Input_Frame) -> bool {
    return .Left in frame.mouse_pressed
}

// Report whether the primary pointer button remains down this frame.
input_frame_left_down :: #force_inline proc(frame: input.Input_Frame) -> bool {
    return .Left in frame.mouse_down
}

// Report whether the primary pointer button was released this frame.
input_frame_left_released :: #force_inline proc(frame: input.Input_Frame) -> bool {
    return .Left in frame.mouse_released
}

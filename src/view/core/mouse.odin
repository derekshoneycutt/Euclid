package view_core

import rl "vendor:raylib"


Mouse_Input_State :: struct {
	position: rl.Vector2,
	delta: rl.Vector2,
	wheel_delta: f32,
	left_pressed: bool,
	left_down: bool,
	left_released: bool,
	timestamp_seconds: f64,
}


//   Capture one canonical mouse input snapshot for this UI frame.
capture_mouse_input_state :: proc() -> Mouse_Input_State {
    return Mouse_Input_State{
        position = rl.GetMousePosition(),
        delta = rl.GetMouseDelta(),
        wheel_delta = rl.GetMouseWheelMove(),
        left_pressed = rl.IsMouseButtonPressed(.LEFT),
        left_down = rl.IsMouseButtonDown(.LEFT),
        left_released = rl.IsMouseButtonReleased(.LEFT),
        timestamp_seconds = rl.GetTime(),
    }
}


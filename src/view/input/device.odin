package input

import rl "vendor:raylib"

// Raylib key for each portable `Input_Key`, indexed by enum value.
INPUT_DEVICE_KEYS :: [int(Input_Key.Count)]rl.KeyboardKey{
    .SPACE, .APOSTROPHE, .COMMA, .MINUS, .PERIOD, .SLASH,
    .ZERO, .ONE, .TWO, .THREE, .FOUR, .FIVE, .SIX, .SEVEN, .EIGHT, .NINE,
    .SEMICOLON, .EQUAL,
    .A, .B, .C, .D, .E, .F, .G, .H, .I, .J, .K, .L, .M,
    .N, .O, .P, .Q, .R, .S, .T, .U, .V, .W, .X, .Y, .Z,
    .LEFT_BRACKET, .BACKSLASH, .RIGHT_BRACKET, .GRAVE,
    .ESCAPE, .ENTER, .TAB, .BACKSPACE, .INSERT, .DELETE,
    .RIGHT, .LEFT, .DOWN, .UP, .PAGE_UP, .PAGE_DOWN, .HOME, .END,
    .F1, .F2, .F3, .F4, .F5, .F6, .F7, .F8, .F9, .F10, .F11, .F12,
    .KP_0, .KP_1, .KP_2, .KP_3, .KP_4, .KP_5, .KP_6, .KP_7, .KP_8, .KP_9,
    .KP_DECIMAL, .KP_DIVIDE, .KP_MULTIPLY, .KP_SUBTRACT, .KP_ADD,
    .KP_ENTER, .KP_EQUAL,
}

// Poll raylib once and return a frame borrowing the runtime event buffer.
//
// Parameters:
//   - runtime: Display-owned input storage prepared and populated for this frame;
//     nil is rejected by the frame reset boundary.
//
// Returns:
//   - One device-independent frame whose event slice borrows runtime storage, or a
//     zero frame when frame initialization fails.
//
// Notes:
//   - Physical presses, repeat/release levels, and text are sampled in that stable
//     category order. Raylib does not expose a shared ordering across those queues.
//   - The returned event slice remains valid only until the next runtime frame begins.
//
// Side effects:
//   - Drains Raylib key and text queues, samples focus, modifiers, pointer buttons,
//     position, and wheel state, and updates runtime focus and event storage.
input_poll_frame :: proc(runtime: ^Input_Runtime) -> Input_Frame {
    frame: Input_Frame
    if !input_runtime_begin_frame(runtime) {
        return frame
    }

    modifiers := input_device_modifiers()
    input_device_poll_presses(runtime, modifiers)
    input_device_poll_levels(runtime, modifiers)
    input_device_poll_text(runtime)
    input_runtime_reconcile_events(runtime)
    frame.events = input_runtime_events(runtime)
    frame.window_focused, frame.window_focus_changed =
        input_runtime_update_window_focus(runtime, rl.IsWindowFocused())
    frame.mouse_modifiers = modifiers
    mouse := rl.GetMousePosition()
    frame.mouse_position = {x = mouse.x, y = mouse.y}
    frame.mouse_moved = input_runtime_update_mouse_position(
        runtime, frame.mouse_position)
    input_device_poll_mouse_button(&frame, .Left, .LEFT)
    input_device_poll_mouse_button(&frame, .Middle, .MIDDLE)
    input_device_poll_mouse_button(&frame, .Right, .RIGHT)
    frame.mouse_wheel_delta = rl.GetMouseWheelMove()
    frame.sample_time_seconds = rl.GetTime()
    return frame
}

// Poll one physical mouse button into device-independent frame bit sets.
//
// Parameters:
//   - frame: The current mutable input frame receiving button state.
//   - button: Portable button identity represented in the frame bit sets.
//   - device_button: Corresponding Raylib button sampled from the device boundary.
//
// Side effects:
//   - Adds the portable button to the frame's pressed, released, and down sets when
//     the corresponding Raylib predicates are true.
input_device_poll_mouse_button :: proc(
    frame: ^Input_Frame, button: Input_Mouse_Button,
    device_button: rl.MouseButton) {
    if rl.IsMouseButtonPressed(device_button) { frame.mouse_pressed += {button} }
    if rl.IsMouseButtonReleased(device_button) { frame.mouse_released += {button} }
    if rl.IsMouseButtonDown(device_button) { frame.mouse_down += {button} }
}

// Drain typed Unicode after physical/repeat/release events.
//
// Parameters:
//   - runtime: Display-owned frame storage receiving text events; nil or full storage
//     rejects events through the runtime append boundary.
//
// Notes:
// Raylib exposes independent key and text queues, so their cross-category OS order
// cannot be recovered; this stable category order is intentional.
//
// Side effects:
//   - Drains Raylib's character queue and appends each codepoint with a fresh modifier
//     snapshot; rejected events are counted while draining continues to queue exhaustion.
input_device_poll_text :: proc(runtime: ^Input_Runtime) {
    for {
        codepoint := rl.GetCharPressed()
        if codepoint == 0 {
            return
        }
        input_runtime_append_event(runtime, Input_Event{
            kind = .Text,
            modifiers = input_device_modifiers(),
            codepoint = codepoint,
            origin = .Device,
        })
    }
}

// Map one raylib key into the portable input vocabulary.
//
// Parameters:
//   - device_key: Raylib keyboard value to resolve.
//
// Returns:
//   - The matching portable key and true, or a zero key and false when unmapped.
input_key_from_device :: proc(device_key: rl.KeyboardKey) -> (Input_Key, bool) {
    for mapped_key, key_value in INPUT_DEVICE_KEYS {
        if mapped_key == device_key {
            return Input_Key(key_value), true
        }
    }
    return {}, false
}

// Map one portable key to raylib for canonical repeat/release sampling.
//
// Parameters:
//   - key: Portable key identity to resolve.
//
// Returns:
//   - The corresponding Raylib key and true, or a zero key and false for an invalid
//     or unmapped portable value.
input_key_to_device :: proc(key: Input_Key) -> (rl.KeyboardKey, bool) {
    if key < .Space || key >= .Count {
        return {}, false
    }
    for device_key, key_value in INPUT_DEVICE_KEYS {
        if key_value == int(key) {
            return device_key, true
        }
    }
    return {}, false
}

// Return whether either physical side of one logical modifier remains down.
input_device_modifier_down :: proc(left_down, right_down: bool) -> bool {
    return left_down || right_down
}

// Snapshot modifier levels at the device polling boundary.
//
// Returns:
//   - One portable modifier set containing every logical modifier whose left or
//     right physical key is currently down.
//
// Side effects:
//   - Samples Raylib keyboard level state for Control, Shift, Alt, and Super.
input_device_modifiers :: proc() -> Input_Modifiers {
    modifiers: Input_Modifiers
    if input_device_modifier_down(
        rl.IsKeyDown(.LEFT_CONTROL), rl.IsKeyDown(.RIGHT_CONTROL)) {
        modifiers += {.Control}
    }
    if input_device_modifier_down(
        rl.IsKeyDown(.LEFT_SHIFT), rl.IsKeyDown(.RIGHT_SHIFT)) {
        modifiers += {.Shift}
    }
    if input_device_modifier_down(
        rl.IsKeyDown(.LEFT_ALT), rl.IsKeyDown(.RIGHT_ALT)) {
        modifiers += {.Alt}
    }
    if input_device_modifier_down(
        rl.IsKeyDown(.LEFT_SUPER), rl.IsKeyDown(.RIGHT_SUPER)) {
        modifiers += {.Super}
    }
    return modifiers
}

// Drain ordered physical presses from raylib's key queue.
//
// Parameters:
//   - runtime: Display-owned frame storage receiving mapped press events.
//   - modifiers: Modifier snapshot attached consistently to every drained press.
//
// Side effects:
//   - Drains Raylib's ordered key-press queue and appends mapped portable events;
//     unmapped keys are consumed without entering runtime storage.
input_device_poll_presses :: proc(
    runtime: ^Input_Runtime, modifiers: Input_Modifiers) {
    for {
        device_key := rl.GetKeyPressed()
        if device_key == .KEY_NULL {
            return
        }
        if key, ok := input_key_from_device(device_key); ok {
            input_runtime_append_event(runtime, Input_Event{
                kind = .Press,
                key = key,
                modifiers = modifiers,
                origin = .Device,
            })
        }
    }
}

// Append repeat and release events in stable portable-key order.
//
// Parameters:
//   - runtime: Display-owned frame storage receiving level-derived events.
//   - modifiers: Modifier snapshot attached consistently to every appended event.
//
// Notes:
//   - Iterating the portable vocabulary provides deterministic order because Raylib
//     exposes repeat and release as per-key predicates rather than ordered queues.
//
// Side effects:
//   - Samples Raylib repeat and release state for every mapped key and appends the
//     corresponding portable events through the bounded runtime boundary.
input_device_poll_levels :: proc(
    runtime: ^Input_Runtime, modifiers: Input_Modifiers) {
    for key_value in 0..<int(Input_Key.Count) {
        key := Input_Key(key_value)
        device_key, ok := input_key_to_device(key)
        if !ok {
            continue
        }
        if rl.IsKeyPressedRepeat(device_key) {
            input_runtime_append_event(runtime, Input_Event{
                kind = .Repeat,
                key = key,
                modifiers = modifiers,
                origin = .Device,
            })
        }
        if rl.IsKeyReleased(device_key) {
            input_runtime_append_event(runtime, Input_Event{
                kind = .Release,
                key = key,
                modifiers = modifiers,
                origin = .Device,
            })
        }
    }
}

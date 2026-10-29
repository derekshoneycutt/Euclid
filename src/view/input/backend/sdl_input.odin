package inputbackend

import utf8 "core:unicode/utf8"
import input ".."
import native "../../native"
import sdl "vendor:sdl3"

// SDL scancode for each portable physical key, indexed by Input_Key.
SDL_INPUT_SCANCODES :: [int(input.Input_Key.Count)]sdl.Scancode{
    .SPACE, .APOSTROPHE, .COMMA, .MINUS, .PERIOD, .SLASH,
    ._0, ._1, ._2, ._3, ._4, ._5, ._6, ._7, ._8, ._9,
    .SEMICOLON, .EQUALS,
    .A, .B, .C, .D, .E, .F, .G, .H, .I, .J, .K, .L, .M,
    .N, .O, .P, .Q, .R, .S, .T, .U, .V, .W, .X, .Y, .Z,
    .LEFTBRACKET, .BACKSLASH, .RIGHTBRACKET, .GRAVE,
    .ESCAPE, .RETURN, .TAB, .BACKSPACE, .INSERT, .DELETE,
    .RIGHT, .LEFT, .DOWN, .UP, .PAGEUP, .PAGEDOWN, .HOME, .END,
    .F1, .F2, .F3, .F4, .F5, .F6, .F7, .F8, .F9, .F10, .F11, .F12,
    .KP_0, .KP_1, .KP_2, .KP_3, .KP_4, .KP_5, .KP_6, .KP_7, .KP_8, .KP_9,
    .KP_PERIOD, .KP_DIVIDE, .KP_MULTIPLY, .KP_MINUS, .KP_PLUS,
    .KP_ENTER, .KP_EQUALS,
    .APPLICATION,
}

// Sdl_Input_Accumulation retains ordered edge facts while one queue is drained.
Sdl_Input_Accumulation :: struct {
    modifiers: input.Input_Modifiers,
    mouse_pressed: input.Input_Mouse_Buttons,
    mouse_left_clicks: u8,
    mouse_released: input.Input_Mouse_Buttons,
    mouse_wheel_delta: f32,
    mouse_position: input.Input_Position,
    mouse_down: input.Input_Mouse_Buttons,
    focused: bool,
    diagnostics: native.Sdl_Input_Diagnostics,
}

// sdl_input_key_from_scancode maps one SDL physical key into portable input.
sdl_input_key_from_scancode :: proc(
    scancode: sdl.Scancode) -> (input.Input_Key, bool) {
    for mapped, key_value in SDL_INPUT_SCANCODES {
        if mapped == scancode {
            return input.Input_Key(key_value), true
        }
    }
    return {}, false
}

// sdl_input_modifiers converts one event-time SDL modifier snapshot.
sdl_input_modifiers :: proc(modifiers: sdl.Keymod) -> input.Input_Modifiers {
    result: input.Input_Modifiers
    if .LCTRL in modifiers || .RCTRL in modifiers {
        result += {.Control}
    }
    if .LSHIFT in modifiers || .RSHIFT in modifiers {
        result += {.Shift}
    }
    if .LALT in modifiers || .RALT in modifiers {
        result += {.Alt}
    }
    if .LGUI in modifiers || .RGUI in modifiers {
        result += {.Super}
    }
    return result
}

// sdl_input_append_keyboard publishes one mapped physical SDL event.
sdl_input_append_keyboard :: proc(
    runtime: ^input.Input_Runtime, event: sdl.KeyboardEvent,
    accumulation: ^Sdl_Input_Accumulation) {
    accumulation^.modifiers = sdl_input_modifiers(event.mod)
    key, mapped := sdl_input_key_from_scancode(event.scancode)
    if !mapped {
        accumulation^.diagnostics.unmapped_key_events += 1
        return
    }
    accumulation^.diagnostics.key_events += 1
    kind := input.Input_Event_Kind.Release
    if event.down {
        kind = .Repeat if event.repeat else .Press
    }
    input.input_runtime_append_event(runtime, {
        kind = kind,
        key = key,
        modifiers = accumulation^.modifiers,
        origin = .Device,
    })
}

// sdl_input_append_text retains one complete bounded UTF-8 commit event.
sdl_input_append_text :: proc(
    runtime: ^input.Input_Runtime, text: cstring,
    accumulation: ^Sdl_Input_Accumulation) {
    if runtime == nil || text == nil {
        return
    }
    source := string(text)
    invalid_count := runtime^.invalid_text_payload_count
    oversized_count := runtime^.oversized_text_payload_count
    unowned_count := runtime^.unowned_text_event_count
    if input.input_runtime_append_text_event(
        runtime, .Text_Commit, source, metadata = {
            preedit_start = -1,
            preedit_length = -1,
            modifiers = accumulation^.modifiers,
        }) {
        accumulation^.diagnostics.text_runes += u64(utf8.rune_count(source))
        accumulation^.diagnostics.text_commits += 1
    } else if runtime^.invalid_text_payload_count > invalid_count {
        accumulation^.diagnostics.invalid_text_events += 1
    } else if runtime^.oversized_text_payload_count > oversized_count {
        accumulation^.diagnostics.oversized_text_events += 1
    } else if runtime^.unowned_text_event_count > unowned_count {
        accumulation^.diagnostics.unowned_text_events += 1
    }
}

// sdl_input_append_preedit copies one SDL composition snapshot into portable input.
sdl_input_append_preedit :: proc(
    runtime: ^input.Input_Runtime, event: sdl.TextEditingEvent,
    accumulation: ^Sdl_Input_Accumulation) {
    if runtime == nil || event.text == nil {
        return
    }
    invalid_count := runtime^.invalid_text_payload_count
    oversized_count := runtime^.oversized_text_payload_count
    unowned_count := runtime^.unowned_text_event_count
    if input.input_runtime_append_text_event(runtime, .Text_Preedit, string(event.text),
        {
            preedit_start = event.start,
            preedit_length = event.length,
            modifiers = accumulation^.modifiers,
        }) {
        accumulation^.diagnostics.text_preedit_events += 1
    } else if runtime^.invalid_text_payload_count > invalid_count {
        accumulation^.diagnostics.invalid_text_events += 1
    } else if runtime^.oversized_text_payload_count > oversized_count {
        accumulation^.diagnostics.oversized_text_events += 1
    } else if runtime^.unowned_text_event_count > unowned_count {
        accumulation^.diagnostics.unowned_text_events += 1
    }
}

// sdl_input_mouse_button maps one supported SDL pointer button.
sdl_input_mouse_button :: proc(
    device_button: u8) -> (input.Input_Mouse_Button, bool) {
    switch device_button {
    case sdl.BUTTON_LEFT:
        return .Left, true
    case sdl.BUTTON_MIDDLE:
        return .Middle, true
    case sdl.BUTTON_RIGHT:
        return .Right, true
    }
    return {}, false
}

// sdl_input_consume_event translates one window-owned SDL input event.
sdl_input_consume_event :: proc(
    runtime: ^input.Input_Runtime, event: ^sdl.Event,
    accumulation: ^Sdl_Input_Accumulation) {
    #partial switch event^.type {
    case .KEY_DOWN, .KEY_UP:
        sdl_input_append_keyboard(runtime, event^.key, accumulation)
    case .TEXT_INPUT:
        if accumulation^.focused {
            sdl_input_append_text(runtime, event^.text.text, accumulation)
        }
    case .TEXT_EDITING:
        if accumulation^.focused {
            sdl_input_append_preedit(runtime, event^.edit, accumulation)
        }
    case .MOUSE_MOTION, .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP, .MOUSE_WHEEL:
        sdl_input_consume_pointer_event(event, accumulation)
    case .WINDOW_FOCUS_GAINED, .WINDOW_FOCUS_LOST:
        sdl_input_consume_focus_event(runtime, event, accumulation)
    }
}

// sdl_input_consume_pointer_event applies pointer position/levels and retains edges.
sdl_input_consume_pointer_event :: proc(
    event: ^sdl.Event, accumulation: ^Sdl_Input_Accumulation) {
    if event^.type == .MOUSE_MOTION {
        accumulation^.mouse_position = {event^.motion.x, event^.motion.y}
        accumulation^.mouse_down = sdl_input_mouse_buttons(event^.motion.state)
        return
    }
    if event^.type == .MOUSE_WHEEL {
        accumulation^.mouse_position = {event^.wheel.mouse_x, event^.wheel.mouse_y}
        accumulation^.diagnostics.wheel_events += 1
        accumulation^.mouse_wheel_delta += event^.wheel.y
        return
    }
    accumulation^.mouse_position = {event^.button.x, event^.button.y}
    if button, mapped := sdl_input_mouse_button(event^.button.button); mapped {
        accumulation^.diagnostics.button_events += 1
        if event^.button.down {
            accumulation^.mouse_down += {button}
            accumulation^.mouse_pressed += {button}
            if button == .Left {
                accumulation^.mouse_left_clicks = event^.button.clicks
            }
        } else {
            accumulation^.mouse_down -= {button}
            accumulation^.mouse_released += {button}
        }
    }
}

// sdl_input_consume_focus_event updates focus and cancels any active composition.
sdl_input_consume_focus_event :: proc(
    runtime: ^input.Input_Runtime, event: ^sdl.Event,
    accumulation: ^Sdl_Input_Accumulation) {
    accumulation^.diagnostics.focus_events += 1
    accumulation^.focused = event^.type == .WINDOW_FOCUS_GAINED
    if !accumulation^.focused {
        accumulation^.mouse_released += accumulation^.mouse_down
        accumulation^.mouse_down = {}
        accumulation^.modifiers = {}
    }
    if accumulation^.focused || runtime == nil || runtime^.text_target.kind == .None {
        return
    }
    _ = input.input_runtime_append_event(runtime, {
        kind = .Text_Cancel,
        text_target = runtime^.text_target,
        origin = .Device,
    })
    _ = input.input_runtime_set_text_target(runtime, .None, 0)
}

// sdl_input_mouse_buttons converts current SDL button levels.
sdl_input_mouse_buttons :: proc(
    flags: sdl.MouseButtonFlags) -> input.Input_Mouse_Buttons {
    result: input.Input_Mouse_Buttons
    if .LEFT in flags {
        result += {.Left}
    }
    if .MIDDLE in flags {
        result += {.Middle}
    }
    if .RIGHT in flags {
        result += {.Right}
    }
    return result
}

// sdl_input_commit_diagnostics adds one drain's content-free outcomes.
sdl_input_commit_diagnostics :: proc(
    platform: ^native.Sdl_Platform, diagnostics: native.Sdl_Input_Diagnostics,
    event_overflows: u64) {
    platform^.input_diagnostics.key_events += diagnostics.key_events
    platform^.input_diagnostics.unmapped_key_events +=
        diagnostics.unmapped_key_events
    platform^.input_diagnostics.text_runes += diagnostics.text_runes
    platform^.input_diagnostics.text_commits += diagnostics.text_commits
    platform^.input_diagnostics.text_preedit_events += diagnostics.text_preedit_events
    platform^.input_diagnostics.invalid_text_events += diagnostics.invalid_text_events
    platform^.input_diagnostics.oversized_text_events += diagnostics.oversized_text_events
    platform^.input_diagnostics.unowned_text_events += diagnostics.unowned_text_events
    platform^.input_diagnostics.button_events += diagnostics.button_events
    platform^.input_diagnostics.wheel_events += diagnostics.wheel_events
    platform^.input_diagnostics.focus_events += diagnostics.focus_events
    platform^.input_diagnostics.event_overflows = event_overflows
}

// sdl_input_finish_frame publishes owner-applied state without sampling ahead of events.
sdl_input_finish_frame :: proc(
    platform: ^native.Sdl_Platform, runtime: ^input.Input_Runtime,
    accumulation: Sdl_Input_Accumulation) -> input.Input_Frame {
    frame: input.Input_Frame
    input.input_runtime_reconcile_events(runtime)
    frame.events = input.input_runtime_events(runtime)
    frame.window_focused, frame.window_focus_changed =
        input.input_runtime_update_window_focus(runtime, accumulation.focused)
    frame.mouse_modifiers = accumulation.modifiers
    levels := accumulation.mouse_down
    mouse_x := native.sdl_application_coordinate(
        accumulation.mouse_position.x, platform^.metrics.content_scale)
    mouse_y := native.sdl_application_coordinate(
        accumulation.mouse_position.y, platform^.metrics.content_scale)
    released := accumulation.mouse_released
    if !accumulation.focused {
        released += runtime^.device_mouse_down
        levels = {}
    }
    runtime^.device_mouse_down = levels
    frame.mouse_position = {mouse_x, mouse_y}
    frame.mouse_moved = input.input_runtime_update_mouse_position(
        runtime, frame.mouse_position)
    frame.mouse_pressed = accumulation.mouse_pressed
    frame.mouse_left_clicks = accumulation.mouse_left_clicks
    frame.mouse_released = released
    frame.mouse_down = levels
    frame.mouse_wheel_delta = accumulation.mouse_wheel_delta
    frame.sample_time_seconds = native.sdl_time_seconds()
    sdl_input_commit_diagnostics(
        platform, accumulation.diagnostics, runtime^.event_overflow_count)
    return frame
}

// sdl_platform_handle_event applies one event to its owning platform state.
sdl_platform_handle_event :: proc(
    platform: ^native.Sdl_Platform, runtime: ^input.Input_Runtime,
    event: ^sdl.Event, window_id: sdl.WindowID,
    accumulation: ^Sdl_Input_Accumulation) {
    if event^.type == .QUIT {
        platform^.close_requested = true
        return
    }
    if !sdl_event_inbox_relevant(event, window_id) {
        return
    }
    if event^.type == .WINDOW_CLOSE_REQUESTED {
        platform^.close_requested = true
    }
    if event^.type == .WINDOW_RESIZED || event^.type == .WINDOW_PIXEL_SIZE_CHANGED ||
       event^.type == .WINDOW_DISPLAY_SCALE_CHANGED {
        platform^.resize_pending = true
    }
    sdl_input_consume_event(runtime, event, accumulation)
}

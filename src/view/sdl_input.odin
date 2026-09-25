package view

import "core:unicode/utf8"

import "input"
import native "native"
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
}

// Sdl_Input_Accumulation retains ordered edge facts while one queue is drained.
Sdl_Input_Accumulation :: struct {
    modifiers: input.Input_Modifiers,
    mouse_pressed: input.Input_Mouse_Buttons,
    mouse_released: input.Input_Mouse_Buttons,
    mouse_wheel_delta: f32,
    focused: bool,
    diagnostics: native.Sdl_Input_Diagnostics,
}

// sdl_input_key_from_scancode maps one SDL physical key into portable input.
sdl_input_key_from_scancode :: proc(
    scancode: sdl.Scancode) -> (input.Input_Key, bool) {
    for mapped, key_value in SDL_INPUT_SCANCODES {
        if mapped == scancode {return input.Input_Key(key_value), true}
    }
    return {}, false
}

// sdl_input_modifiers converts one event-time SDL modifier snapshot.
sdl_input_modifiers :: proc(modifiers: sdl.Keymod) -> input.Input_Modifiers {
    result: input.Input_Modifiers
    if .LCTRL in modifiers || .RCTRL in modifiers {result += {.Control}}
    if .LSHIFT in modifiers || .RSHIFT in modifiers {result += {.Shift}}
    if .LALT in modifiers || .RALT in modifiers {result += {.Alt}}
    if .LGUI in modifiers || .RGUI in modifiers {result += {.Super}}
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
    if event.down {kind = .Repeat if event.repeat else .Press}
    input.input_runtime_append_event(runtime, {
        kind = kind,
        key = key,
        modifiers = accumulation^.modifiers,
        origin = .Device,
    })
}

// sdl_input_append_text publishes every valid rune in one committed UTF-8 event.
sdl_input_append_text :: proc(
    runtime: ^input.Input_Runtime, text: cstring,
    accumulation: ^Sdl_Input_Accumulation) {
    if text == nil {return}
    source := string(text)
    if !utf8.valid_string(source) {
        accumulation^.diagnostics.invalid_text_events += 1
        return
    }
    for offset := 0; offset < len(source); {
        codepoint, width := utf8.decode_rune(source[offset:])
        if width == 0 {return}
        input.input_runtime_append_event(runtime, {
            kind = .Text,
            modifiers = accumulation^.modifiers,
            codepoint = codepoint,
            origin = .Device,
        })
        accumulation^.diagnostics.text_runes += 1
        offset += width
    }
}

// sdl_input_mouse_button maps one supported SDL pointer button.
sdl_input_mouse_button :: proc(
    device_button: u8) -> (input.Input_Mouse_Button, bool) {
    switch device_button {
    case sdl.BUTTON_LEFT: return .Left, true
    case sdl.BUTTON_MIDDLE: return .Middle, true
    case sdl.BUTTON_RIGHT: return .Right, true
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
        sdl_input_append_text(runtime, event^.text.text, accumulation)
    case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
        if button, mapped := sdl_input_mouse_button(event^.button.button); mapped {
            accumulation^.diagnostics.button_events += 1
            if event^.button.down {
                accumulation^.mouse_pressed += {button}
            } else {
                accumulation^.mouse_released += {button}
            }
        }
    case .MOUSE_WHEEL:
        accumulation^.diagnostics.wheel_events += 1
        delta := event^.wheel.y
        if event^.wheel.direction == .FLIPPED {delta = -delta}
        accumulation^.mouse_wheel_delta += delta
    case .WINDOW_FOCUS_GAINED:
        accumulation^.diagnostics.focus_events += 1
        accumulation^.focused = true
    case .WINDOW_FOCUS_LOST:
        accumulation^.diagnostics.focus_events += 1
        accumulation^.focused = false
    }
}

// sdl_input_mouse_buttons converts current SDL button levels.
sdl_input_mouse_buttons :: proc(
    flags: sdl.MouseButtonFlags) -> input.Input_Mouse_Buttons {
    result: input.Input_Mouse_Buttons
    if .LEFT in flags {result += {.Left}}
    if .MIDDLE in flags {result += {.Middle}}
    if .RIGHT in flags {result += {.Right}}
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
    platform^.input_diagnostics.invalid_text_events += diagnostics.invalid_text_events
    platform^.input_diagnostics.button_events += diagnostics.button_events
    platform^.input_diagnostics.wheel_events += diagnostics.wheel_events
    platform^.input_diagnostics.focus_events += diagnostics.focus_events
    platform^.input_diagnostics.event_overflows = event_overflows
}

// sdl_input_finish_frame samples final pointer levels and publishes one frame.
sdl_input_finish_frame :: proc(
    platform: ^native.Sdl_Platform, runtime: ^input.Input_Runtime,
    accumulation: Sdl_Input_Accumulation) -> input.Input_Frame {
    frame: input.Input_Frame
    input.input_runtime_reconcile_events(runtime)
    frame.events = input.input_runtime_events(runtime)
    frame.window_focused, frame.window_focus_changed =
        input.input_runtime_update_window_focus(runtime, accumulation.focused)
    frame.mouse_modifiers = accumulation.modifiers
    mouse_x, mouse_y: f32
    levels := sdl_input_mouse_buttons(sdl.GetMouseState(&mouse_x, &mouse_y))
    mouse_x = native.sdl_application_coordinate(
        mouse_x, platform^.metrics.content_scale)
    mouse_y = native.sdl_application_coordinate(
        mouse_y, platform^.metrics.content_scale)
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
    frame.mouse_released = released
    frame.mouse_down = levels
    frame.mouse_wheel_delta = accumulation.mouse_wheel_delta
    frame.sample_time_seconds = native.sdl_time_seconds()
    sdl_input_commit_diagnostics(
        platform, accumulation.diagnostics, runtime^.event_overflow_count)
    native.sdl_platform_sync_text_input(platform, accumulation.focused)
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
    if event^.window.windowID != window_id {return}
    if event^.type == .WINDOW_CLOSE_REQUESTED {platform^.close_requested = true}
    if event^.type == .WINDOW_RESIZED || event^.type == .WINDOW_PIXEL_SIZE_CHANGED ||
       event^.type == .WINDOW_DISPLAY_SCALE_CHANGED {
        platform^.resize_pending = true
    }
    if runtime != nil {
        sdl_input_consume_event(runtime, event, accumulation)
    } else if event^.type == .WINDOW_FOCUS_GAINED {
        accumulation^.focused = true
    } else if event^.type == .WINDOW_FOCUS_LOST {
        accumulation^.focused = false
    }
}

// sdl_platform_refresh_observed_metrics updates last-good window observations.
sdl_platform_refresh_observed_metrics :: proc(platform: ^native.Sdl_Platform) {
    if !platform^.resize_pending {return}
    if metrics, ok := native.sdl_platform_metrics(platform^.window); ok {
        platform^.metrics = metrics
    }
}

// sdl_platform_poll_events drains lifecycle and optional application input once.
sdl_platform_poll_events :: proc(
    platform: ^native.Sdl_Platform,
    runtime: ^input.Input_Runtime = nil) -> input.Input_Frame {
    accumulation := Sdl_Input_Accumulation{
        modifiers = sdl_input_modifiers(sdl.GetModState()),
        focused = .INPUT_FOCUS in sdl.GetWindowFlags(platform^.window),
    }
    if runtime != nil && !input.input_runtime_begin_frame(runtime) {return {}}
    window_id := sdl.GetWindowID(platform^.window)
    event: sdl.Event
    for sdl.PollEvent(&event) {
        sdl_platform_handle_event(
            platform, runtime, &event, window_id, &accumulation)
    }
    sdl_platform_refresh_observed_metrics(platform)
    native.sdl_platform_sync_text_input(platform, accumulation.focused)
    if runtime == nil {return {}}
    return sdl_input_finish_frame(platform, runtime, accumulation)
}
#+test
package view

import "core:testing"

import "input"
import sdl "vendor:sdl3"

// Verify every portable physical key has one stable SDL scancode mapping.
@(test)
sdl_input_test_scancode_mapping_is_complete :: proc(t: ^testing.T) {
    for scancode, key_value in SDL_INPUT_SCANCODES {
        expected := input.Input_Key(key_value)
        actual, mapped := sdl_input_key_from_scancode(scancode)
        testing.expect(t, mapped)
        testing.expect_value(t, actual, expected)
    }
}

// Verify event-time SDL modifiers collapse both physical sides correctly.
@(test)
sdl_input_test_modifiers_merge_both_sides :: proc(t: ^testing.T) {
    modifiers := sdl_input_modifiers({.RCTRL, .LSHIFT, .RALT, .LGUI})
    testing.expect(t, .Control in modifiers)
    testing.expect(t, .Shift in modifiers)
    testing.expect(t, .Alt in modifiers)
    testing.expect(t, .Super in modifiers)
}

// Verify SDL keyboard events retain queue order and distinguish repeat and release.
@(test)
sdl_input_test_keyboard_order_and_kinds :: proc(t: ^testing.T) {
    runtime: input.Input_Runtime
    accumulation: Sdl_Input_Accumulation
    testing.expect(t, input.input_runtime_begin_frame(&runtime))
    events := []sdl.KeyboardEvent{
        {scancode = .A, mod = {.LCTRL}, down = true},
        {scancode = .A, mod = {.LCTRL}, down = true, repeat = true},
        {scancode = .A, mod = {}, down = false},
    }
    for event in events {sdl_input_append_keyboard(&runtime, event, &accumulation)}
    captured := input.input_runtime_events(&runtime)
    testing.expect_value(t, len(captured), 3)
    testing.expect_value(t, captured[0].kind, input.Input_Event_Kind.Press)
    testing.expect_value(t, captured[1].kind, input.Input_Event_Kind.Repeat)
    testing.expect_value(t, captured[2].kind, input.Input_Event_Kind.Release)
    testing.expect(t, .Control in captured[0].modifiers)
}

// Verify one committed SDL text payload publishes each valid UTF-8 rune in order.
@(test)
sdl_input_test_text_decodes_multiple_runes :: proc(t: ^testing.T) {
    runtime: input.Input_Runtime
    testing.expect(t, input.input_runtime_begin_frame(&runtime))
    accumulation := Sdl_Input_Accumulation{modifiers = {.Shift}}
    sdl_input_append_text(&runtime, "A界", &accumulation)
    captured := input.input_runtime_events(&runtime)
    testing.expect_value(t, len(captured), 2)
    testing.expect_value(t, captured[0].codepoint, rune('A'))
    testing.expect_value(t, captured[1].codepoint, rune('界'))
    testing.expect(t, .Shift in captured[1].modifiers)
}

// Verify invalid committed UTF-8 is rejected without partial publication.
@(test)
sdl_input_test_text_rejects_invalid_utf8 :: proc(t: ^testing.T) {
    runtime: input.Input_Runtime
    testing.expect(t, input.input_runtime_begin_frame(&runtime))
    invalid := [2]u8{0xff, 0}
    accumulation: Sdl_Input_Accumulation
    sdl_input_append_text(&runtime, cstring(&invalid[0]), &accumulation)
    testing.expect_value(t, len(input.input_runtime_events(&runtime)), 0)
}

// Verify pointer edges, wheel direction, and focus follow SDL event values.
@(test)
sdl_input_test_pointer_wheel_and_focus :: proc(t: ^testing.T) {
    runtime: input.Input_Runtime
    accumulation := Sdl_Input_Accumulation{focused = true}
    pressed := sdl.Event{type = .MOUSE_BUTTON_DOWN}
    pressed.button.button = sdl.BUTTON_LEFT
    pressed.button.down = true
    sdl_input_consume_event(&runtime, &pressed, &accumulation)
    wheel := sdl.Event{type = .MOUSE_WHEEL}
    wheel.wheel.y = 2.5
    wheel.wheel.direction = .FLIPPED
    sdl_input_consume_event(&runtime, &wheel, &accumulation)
    lost := sdl.Event{type = .WINDOW_FOCUS_LOST}
    sdl_input_consume_event(&runtime, &lost, &accumulation)
    testing.expect(t, .Left in accumulation.mouse_pressed)
    testing.expect_value(t, accumulation.mouse_wheel_delta, f32(-2.5))
    testing.expect(t, !accumulation.focused)
}
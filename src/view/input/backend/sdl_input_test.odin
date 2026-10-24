#+test
package inputbackend

import testing "core:testing"
import input ".."
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
    for event in events {
       sdl_input_append_keyboard(&runtime, event, &accumulation)
    }
    captured := input.input_runtime_events(&runtime)
    testing.expect_value(t, len(captured), 3)
    testing.expect_value(t, captured[0].kind, input.Input_Event_Kind.Press)
    testing.expect_value(t, captured[1].kind, input.Input_Event_Kind.Repeat)
    testing.expect_value(t, captured[2].kind, input.Input_Event_Kind.Release)
    testing.expect(t, .Control in captured[0].modifiers)
}

// Verify one committed SDL payload retains whole UTF-8 text and owner identity.
@(test)
sdl_input_test_text_decodes_multiple_runes :: proc(t: ^testing.T) {
    runtime: input.Input_Runtime
    testing.expect(t, input.input_runtime_begin_frame(&runtime))
    _ = input.input_runtime_set_text_target(&runtime, .Input_Box, 27)
    accumulation := Sdl_Input_Accumulation{modifiers = {.Shift}}
    sdl_input_append_text(&runtime, "A界", &accumulation)
    captured := input.input_runtime_events(&runtime)
    testing.expect_value(t, len(captured), 1)
    testing.expect_value(t, captured[0].kind, input.Input_Event_Kind.Text_Commit)
    testing.expect_value(t, string(captured[0].text[:captured[0].text_length]), "A界")
    testing.expect_value(t, captured[0].text_target.kind,
        input.Input_Text_Target_Kind.Input_Box)
    testing.expect_value(t, captured[0].text_target.id, 27)
    testing.expect(t, .Shift in captured[0].modifiers)
    testing.expect_value(t, accumulation.diagnostics.text_runes, u64(2))
}

// Verify SDL editing updates own their preedit bytes and preserve native offsets.
@(test)
sdl_input_test_preedit_payload_and_selection :: proc(t: ^testing.T) {
    runtime: input.Input_Runtime
    testing.expect(t, input.input_runtime_begin_frame(&runtime))
    _ = input.input_runtime_set_text_target(&runtime, .Terminal, 0)
    accumulation := Sdl_Input_Accumulation{focused = true}
    event := sdl.TextEditingEvent{text = "にほん", start = 1, length = 2}
    sdl_input_append_preedit(&runtime, event, &accumulation)
    events := input.input_runtime_events(&runtime)
    testing.expect_value(t, len(events), 1)
    testing.expect_value(t, events[0].kind, input.Input_Event_Kind.Text_Preedit)
    testing.expect_value(t,
        string(events[0].text[:events[0].text_length]), "にほん")
    testing.expect_value(t, events[0].preedit_start, i32(1))
    testing.expect_value(t, events[0].preedit_length, i32(2))
    testing.expect_value(t, events[0].text_target.kind,
        input.Input_Text_Target_Kind.Terminal)
}

// Verify invalid committed UTF-8 is rejected without partial publication.
@(test)
sdl_input_test_text_rejects_invalid_utf8 :: proc(t: ^testing.T) {
    runtime: input.Input_Runtime
    testing.expect(t, input.input_runtime_begin_frame(&runtime))
    invalid := [2]u8{0xff, 0}
    accumulation: Sdl_Input_Accumulation
    _ = input.input_runtime_set_text_target(&runtime, .Input_Box, 9)
    runtime.invalid_text_payload_count = 0
    sdl_input_append_text(&runtime, cstring(&invalid[0]), &accumulation)
    testing.expect_value(t, len(input.input_runtime_events(&runtime)), 0)
}

// Verify SDL text without an eligible owner is rejected and counted.
@(test)
sdl_input_test_text_requires_active_target :: proc(t: ^testing.T) {
    runtime: input.Input_Runtime
    accumulation: Sdl_Input_Accumulation
    sdl_input_append_text(&runtime, "x", &accumulation)
    testing.expect_value(t, len(input.input_runtime_events(&runtime)), 0)
    testing.expect_value(t, runtime.unowned_text_event_count, u64(1))
    testing.expect_value(t, accumulation.diagnostics.unowned_text_events, u64(1))
}

// Verify pointer edges, delivered wheel signs, and focus follow SDL event values.
@(test)
sdl_input_test_pointer_wheel_and_focus :: proc(t: ^testing.T) {
    runtime: input.Input_Runtime
    accumulation := Sdl_Input_Accumulation{focused = true}
    pressed := sdl.Event{type = .MOUSE_BUTTON_DOWN}
    pressed.button.button = sdl.BUTTON_LEFT
    pressed.button.down = true
    pressed.button.clicks = 2
    sdl_input_consume_event(&runtime, &pressed, &accumulation)
    normal_wheel := sdl.Event{type = .MOUSE_WHEEL}
    normal_wheel.wheel.y = -1.25
    normal_wheel.wheel.direction = .NORMAL
    sdl_input_consume_event(&runtime, &normal_wheel, &accumulation)
    flipped_wheel := sdl.Event{type = .MOUSE_WHEEL}
    flipped_wheel.wheel.y = 2.5
    flipped_wheel.wheel.direction = .FLIPPED
    sdl_input_consume_event(&runtime, &flipped_wheel, &accumulation)
    lost := sdl.Event{type = .WINDOW_FOCUS_LOST}
    sdl_input_consume_event(&runtime, &lost, &accumulation)
    testing.expect(t, .Left in accumulation.mouse_pressed)
    testing.expect_value(t, accumulation.mouse_left_clicks, u8(2))
    testing.expect_value(t, accumulation.mouse_wheel_delta, f32(1.25))
    testing.expect_value(t, accumulation.diagnostics.wheel_events, u64(2))
    testing.expect(t, !accumulation.focused)
}

// Verify the latest left press retains its count across other buttons and release.
@(test)
sdl_input_test_click_count_tracks_latest_left_press :: proc(t: ^testing.T) {
    runtime: input.Input_Runtime
    accumulation: Sdl_Input_Accumulation
    event := sdl.Event{type = .MOUSE_BUTTON_DOWN}
    event.button.button = sdl.BUTTON_LEFT
    event.button.down = true
    click_counts := [?]u8{1, 2, 3}
    for clicks in click_counts {
        event.button.clicks = clicks
        sdl_input_consume_event(&runtime, &event, &accumulation)
        testing.expect_value(t, accumulation.mouse_left_clicks, clicks)
    }
    event.button.button = sdl.BUTTON_RIGHT
    event.button.clicks = 1
    sdl_input_consume_event(&runtime, &event, &accumulation)
    event.type = .MOUSE_BUTTON_UP
    event.button.button = sdl.BUTTON_LEFT
    event.button.down = false
    sdl_input_consume_event(&runtime, &event, &accumulation)
    testing.expect_value(t, accumulation.mouse_left_clicks, u8(3))
    testing.expect(t, .Left in accumulation.mouse_pressed &&
        .Left in accumulation.mouse_released)
    accumulation = {}
    sdl_input_consume_event(&runtime, &event, &accumulation)
    testing.expect_value(t, accumulation.mouse_left_clicks, u8(0))
}
#+test
package input

import "../../core/protocol"
import gfxprotocol "../../terminal/graphics/protocol"
import termemulator "../../terminal/emulator"
import termmodel "../../terminal/model"
import termpalette "../../terminal/palette"

import "core:testing"

// One semantic terminal response and its exact wire encoding.
Input_Terminal_Response_Fixture :: struct {
    response: termmodel.Terminal_Response,
    bytes: string,
}

// Enqueue and verify one exact semantic terminal response fixture.
input_test_expect_terminal_response_fixture :: proc(
    t: ^testing.T, runtime: ^Input_Runtime,
    interpreter: ^termemulator.Interpreter,
    fixture: Input_Terminal_Response_Fixture) {
    testing.expect(t,
        termemulator.interpreter_enqueue_response(interpreter, fixture.response))
    testing.expect(t, input_terminal_drain_responses(runtime, interpreter))
    bytes: [96]u8
    count := input_runtime_copy_queued_bytes(runtime, bytes[:])
    testing.expect_value(t, string(bytes[:count]), fixture.bytes)
    testing.expect(t, input_runtime_pop_queued_bytes(runtime, count))
}

// Encode one frame into the runtime ring and return its copied bytes.
input_test_encode_frame :: proc(
    runtime: ^Input_Runtime, events: []Input_Event,
    mode: termmodel.Terminal_Input_Mode = {},
    modify_other_keys_level: u8 = 0,
    kitty_keyboard_flags: u8 = 0) -> ([128]u8, int) {
    input_terminal_enqueue_frame(
        runtime, Input_Frame{events = events}, mode, modify_other_keys_level,
        kitty_keyboard_flags)
    bytes: [128]u8
    count := input_runtime_copy_queued_bytes(runtime, bytes[:])
    return bytes, count
}

// Verify every portable physical key has a stable round-trip device mapping.
@(test)
input_test_device_key_mapping_is_complete :: proc(t: ^testing.T) {
    for key_value in 0..<int(Input_Key.Count) {
        key := Input_Key(key_value)
        device_key, encoded := input_key_to_device(key)
        testing.expect(t, encoded)
        decoded_key, decoded := input_key_from_device(device_key)
        testing.expect(t, decoded)
        testing.expect_value(t, decoded_key, key)
    }
}

// Verify event queries respect kind and modifier snapshots.
@(test)
input_test_event_queries_use_captured_modifiers :: proc(t: ^testing.T) {
    frame := Input_Frame{events = []Input_Event{
        {kind = .Press, key = .C, modifiers = {.Control, .Shift}},
        {kind = .Release, key = .D},
    }}
    testing.expect(t, input_chord_pressed(frame, .C, {.Control}))
    testing.expect(t, input_chord_pressed(frame, .C, {.Control, .Shift}))
    testing.expect(t, !input_chord_pressed(frame, .C, {.Alt}))
    testing.expect(t, input_key_released(frame, .D))
}

// Verify one released modifier side cannot hide the still-held opposite side.
@(test)
input_test_device_modifier_levels_merge_both_sides :: proc(t: ^testing.T) {
    testing.expect(t, !input_device_modifier_down(false, false))
    testing.expect(t, input_device_modifier_down(true, false))
    testing.expect(t, input_device_modifier_down(false, true))
    testing.expect(t, input_device_modifier_down(true, true))
}

// Verify pointer movement begins only after the first device sample.
@(test)
input_test_pointer_movement_requires_prior_sample :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    testing.expect(t, !input_runtime_update_mouse_position(
        &runtime, {x = 10, y = 20}))
    testing.expect(t, !input_runtime_update_mouse_position(
        &runtime, {x = 10, y = 20}))
    testing.expect(t, input_runtime_update_mouse_position(
        &runtime, {x = 11, y = 20}))
}

// Verify controls and text retain event order without duplicate control text.
@(test)
input_test_terminal_ring_preserves_event_order :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    events := []Input_Event{
        {kind = .Text, codepoint = 'i'},
        {kind = .Press, key = .C, modifiers = {.Control}},
        {kind = .Text, codepoint = 'c', modifiers = {.Control}},
        {kind = .Text, codepoint = '界'},
    }
    bytes, count := input_test_encode_frame(&runtime, events)
    testing.expect_value(t, string(bytes[:count]), "i\x03界")
}

// Verify focus transitions are sampled once and encoded before frame key bytes.
@(test)
input_test_terminal_focus_reports_precede_keys :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    focused, changed := input_runtime_update_window_focus(&runtime, true)
    testing.expect(t, focused)
    testing.expect(t, !changed)
    focused, changed = input_runtime_update_window_focus(&runtime, false)
    testing.expect(t, !focused)
    testing.expect(t, changed)

    events := []Input_Event{{kind = .Text, codepoint = 'x'}}
    frame := Input_Frame{
        events = events,
        window_focused = focused,
        window_focus_changed = changed,
    }
    input_terminal_enqueue_frame(
        &runtime, frame, {focus_reporting = true})
    bytes: [8]u8
    count := input_runtime_copy_queued_bytes(&runtime, bytes[:])
    testing.expect_value(t, string(bytes[:count]), "\e[Ox")

    testing.expect(t, input_runtime_pop_queued_bytes(&runtime, count))
    _, changed = input_runtime_update_window_focus(&runtime, false)
    testing.expect(t, !changed)
    input_terminal_enqueue_frame(&runtime, {
        window_focused = false,
        window_focus_changed = changed,
    }, {focus_reporting = true})
    testing.expect_value(t, runtime.byte_queue_count, 0)
}

// Verify SGR mouse reports precede keys and encode buttons, modifiers, and wheel.
@(test)
input_test_terminal_sgr_mouse_encoding :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    frame := Input_Frame{
        events = []Input_Event{{kind = .Text, codepoint = 'x'}},
        mouse_modifiers = {.Alt, .Control},
        mouse_pressed = {.Left},
        mouse_wheel_delta = -1,
        terminal_mouse_position = {column = 12, row = 34},
        terminal_mouse_position_valid = true,
        terminal_mouse_inside = true,
        terminal_mouse_owned = true,
    }
    input_terminal_enqueue_frame(&runtime, frame, {
        mouse_tracking = .Button,
        mouse_sgr_encoding = true,
    })
    bytes: [64]u8
    count := input_runtime_copy_queued_bytes(&runtime, bytes[:])
    testing.expect_value(t, string(bytes[:count]),
        "\e[<24;12;34M\e[<89;12;34Mx")
}

// Build one resolved application-owned mouse frame for encoder tests.
input_test_mouse_frame :: proc(
    column, row: int, pressed: Input_Mouse_Buttons = {},
    released: Input_Mouse_Buttons = {}, down: Input_Mouse_Buttons = {}) -> Input_Frame {
    return {
        mouse_pressed = pressed,
        mouse_released = released,
        mouse_down = down,
        terminal_mouse_position = {column = column, row = row},
        terminal_mouse_position_valid = true,
        terminal_mouse_inside = true,
        terminal_mouse_owned = true,
    }
}

// Build one application-owned mouse frame carrying real movement evidence.
input_test_moved_mouse_frame :: proc(
    column, row: int, pressed: Input_Mouse_Buttons = {},
    down: Input_Mouse_Buttons = {}) -> Input_Frame {
    frame := input_test_mouse_frame(column, row, pressed = pressed, down = down)
    frame.mouse_moved = true
    return frame
}

// Build one moved frame carrying independently resolved cell and pixel coordinates.
input_test_pixel_mouse_frame :: proc(
    cell_column, cell_row, pixel_x, pixel_y: int) -> Input_Frame {
    frame := input_test_moved_mouse_frame(cell_column, cell_row)
    frame.terminal_mouse_pixel_position = {
        column = pixel_x,
        row = pixel_y,
    }
    return frame
}

// Verify any-event tracking reports real changed-cell hover and captured motion.
@(test)
input_test_terminal_sgr_any_motion :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    mode := termmodel.Terminal_Input_Mode{
        mouse_tracking = .Any_Motion,
        mouse_sgr_encoding = true,
    }
    input_terminal_enqueue_frame(
        &runtime, input_test_mouse_frame(2, 3), mode)
    input_terminal_enqueue_frame(
        &runtime, input_test_moved_mouse_frame(2, 3), mode)
    input_terminal_enqueue_frame(
        &runtime, input_test_moved_mouse_frame(2, 3), mode)
    input_terminal_enqueue_frame(&runtime,
        input_test_moved_mouse_frame(4, 5, pressed = {.Right},
            down = {.Right}), mode)
    input_terminal_enqueue_frame(&runtime,
        input_test_moved_mouse_frame(6, 7, down = {.Right}), mode)
    bytes: [64]u8
    count := input_runtime_copy_queued_bytes(&runtime, bytes[:])
    testing.expect_value(t, string(bytes[:count]),
        "\e[<35;2;3M\e[<2;4;5M\e[<34;6;7M")
}

// Verify pixel mode reports within-cell movement and mode changes reset coalescing.
@(test)
input_test_terminal_sgr_pixel_motion :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    mode := termmodel.Terminal_Input_Mode{
        mouse_tracking = .Any_Motion,
        mouse_sgr_encoding = true,
        mouse_pixel_coordinates = true,
    }
    input_terminal_enqueue_frame(
        &runtime, input_test_pixel_mouse_frame(2, 3, 17, 38), mode)
    input_terminal_enqueue_frame(
        &runtime, input_test_pixel_mouse_frame(2, 3, 18, 38), mode)
    input_terminal_enqueue_frame(
        &runtime, input_test_pixel_mouse_frame(2, 3, 18, 38), mode)
    mode.mouse_pixel_coordinates = false
    input_terminal_enqueue_frame(
        &runtime, input_test_pixel_mouse_frame(2, 3, 18, 38), mode)
    bytes: [64]u8
    count := input_runtime_copy_queued_bytes(&runtime, bytes[:])
    testing.expect_value(t, string(bytes[:count]),
        "\e[<35;17;38M\e[<35;18;38M\e[<35;2;3M")
}

// Verify pixel mode selects pixel coordinates for button, wheel, and captured release.
@(test)
input_test_terminal_sgr_pixel_buttons_and_wheel :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    mode := termmodel.Terminal_Input_Mode{
        mouse_tracking = .Button,
        mouse_sgr_encoding = true,
        mouse_pixel_coordinates = true,
    }
    press := input_test_mouse_frame(2, 3, pressed = {.Left})
    press.terminal_mouse_pixel_position = {column = 417, row = 238}
    press.mouse_wheel_delta = 1
    input_terminal_enqueue_frame(&runtime, press, mode)
    release := input_test_mouse_frame(20, 4, released = {.Left})
    release.terminal_mouse_pixel_position = {column = 640, row = 360}
    release.terminal_mouse_inside = false
    release.terminal_mouse_owned = false
    input_terminal_enqueue_frame(&runtime, release, mode)
    bytes: [64]u8
    count := input_runtime_copy_queued_bytes(&runtime, bytes[:])
    testing.expect_value(t, string(bytes[:count]),
        "\e[<0;417;238M\e[<64;417;238M\e[<0;640;360m")
}

// Verify pixel release pressure retains the complete clamped endpoint for retry.
@(test)
input_test_terminal_sgr_pixel_release_retries_atomically :: proc(t: ^testing.T) {
    runtime := Input_Runtime{mouse_captured = {.Middle}}
    runtime.byte_queue_count = len(runtime.byte_queue)
    mode := termmodel.Terminal_Input_Mode{
        mouse_tracking = .Button,
        mouse_sgr_encoding = true,
        mouse_pixel_coordinates = true,
    }
    frame := input_test_mouse_frame(20, 4, released = {.Middle})
    frame.terminal_mouse_pixel_position = {column = 640, row = 360}
    input_terminal_enqueue_frame(&runtime, frame, mode)
    testing.expect(t, .Middle in runtime.mouse_pending_releases)
    testing.expect(t, input_runtime_pop_queued_bytes(
        &runtime, runtime.byte_queue_count))
    input_terminal_enqueue_frame(&runtime, {}, mode)
    bytes: [24]u8
    count := input_runtime_copy_queued_bytes(&runtime, bytes[:])
    testing.expect_value(t, string(bytes[:count]), "\e[<1;640;360m")
    testing.expect_value(t, runtime.mouse_captured, Input_Mouse_Buttons{})
}

// Verify local ownership, grid bounds, and pressure gate any-event coalescing.
@(test)
input_test_terminal_sgr_any_motion_admission :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    mode := termmodel.Terminal_Input_Mode{
        mouse_tracking = .Any_Motion,
        mouse_sgr_encoding = true,
    }
    shifted := input_test_moved_mouse_frame(2, 3)
    shifted.terminal_mouse_owned = false
    input_terminal_enqueue_frame(&runtime, shifted, mode)
    outside := input_test_moved_mouse_frame(3, 4)
    outside.terminal_mouse_inside = false
    input_terminal_enqueue_frame(&runtime, outside, mode)
    runtime.byte_queue_count = len(runtime.byte_queue)
    input_terminal_enqueue_frame(
        &runtime, input_test_moved_mouse_frame(5, 6), mode)
    testing.expect(t, !runtime.mouse_last_position_valid)
    testing.expect(t, input_runtime_pop_queued_bytes(
        &runtime, runtime.byte_queue_count))
    input_terminal_enqueue_frame(
        &runtime, input_test_moved_mouse_frame(5, 6), mode)
    bytes: [16]u8
    count := input_runtime_copy_queued_bytes(&runtime, bytes[:])
    testing.expect_value(t, string(bytes[:count]), "\e[<35;5;6M")
}

// Verify button motion coalesces by cell and captured releases use lowercase m.
@(test)
input_test_terminal_sgr_mouse_capture_and_motion :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    mode := termmodel.Terminal_Input_Mode{
        mouse_tracking = .Button_Motion,
        mouse_sgr_encoding = true,
    }
    press := input_test_mouse_frame(2, 3, pressed = {.Right}, down = {.Right})
    input_terminal_enqueue_frame(&runtime, press, mode)
    input_terminal_enqueue_frame(
        &runtime, input_test_mouse_frame(2, 3, down = {.Right}), mode)
    input_terminal_enqueue_frame(
        &runtime, input_test_mouse_frame(4, 5, down = {.Right}), mode)
    release := input_test_mouse_frame(8, 6, released = {.Right})
    release.terminal_mouse_inside = false
    release.terminal_mouse_owned = false
    input_terminal_enqueue_frame(&runtime, release, mode)
    bytes: [64]u8
    count := input_runtime_copy_queued_bytes(&runtime, bytes[:])
    testing.expect_value(t, string(bytes[:count]),
        "\e[<2;2;3M\e[<34;4;5M\e[<2;8;6m")
    testing.expect_value(t, runtime.mouse_captured, Input_Mouse_Buttons{})
}

// Verify owner transitions cannot carry application mouse capture forward.
@(test)
input_test_terminal_mouse_capture_is_owner_bound :: proc(t: ^testing.T) {
    runtime := Input_Runtime{
        owner = {kind = .Terminal_Session, id = 1},
        mouse_captured = {.Left},
        mouse_pending_releases = {.Left},
        mouse_last_position_valid = true,
    }
    input_runtime_set_owner(&runtime, {kind = .Julia_Interactive, id = 2})
    testing.expect_value(t, runtime.mouse_captured, Input_Mouse_Buttons{})
    testing.expect_value(t, runtime.mouse_pending_releases, Input_Mouse_Buttons{})
    testing.expect(t, !runtime.mouse_last_position_valid)
}

// Verify queue pressure retains a captured release and retries it before new input.
@(test)
input_test_terminal_mouse_release_retries_atomically :: proc(t: ^testing.T) {
    runtime := Input_Runtime{mouse_captured = {.Middle}}
    runtime.byte_queue_count = len(runtime.byte_queue)
    mode := termmodel.Terminal_Input_Mode{
        mouse_tracking = .Button,
        mouse_sgr_encoding = true,
    }
    input_terminal_enqueue_frame(&runtime, {
        mouse_released = {.Middle},
        terminal_mouse_position = {column = 9, row = 7},
        terminal_mouse_position_valid = true,
    }, mode)
    testing.expect(t, .Middle in runtime.mouse_captured)
    testing.expect(t, .Middle in runtime.mouse_pending_releases)
    testing.expect(t, input_runtime_pop_queued_bytes(
        &runtime, runtime.byte_queue_count))

    input_terminal_enqueue_frame(&runtime, {}, mode)
    bytes: [16]u8
    count := input_runtime_copy_queued_bytes(&runtime, bytes[:])
    testing.expect_value(t, string(bytes[:count]), "\e[<1;9;7m")
    testing.expect_value(t, runtime.mouse_captured, Input_Mouse_Buttons{})
    testing.expect_value(t, runtime.mouse_pending_releases, Input_Mouse_Buttons{})
}

// Verify cursor, function, and keypad output follows authoritative modes.
@(test)
input_test_terminal_ring_honors_modes_and_modifiers :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    events := []Input_Event{
        {kind = .Press, key = .Up},
        {kind = .Press, key = .Right, modifiers = {.Control}},
        {kind = .Press, key = .F1, modifiers = {.Shift}},
        {kind = .Press, key = .F12},
        {kind = .Press, key = .Keypad2},
    }
    mode := termmodel.Terminal_Input_Mode{
        cursor_keys_application = true,
        keypad_application = true,
    }
    bytes, count := input_test_encode_frame(&runtime, events, mode)
    testing.expect_value(
        t, string(bytes[:count]), "\eOA\e[1;5C\e[1;2P\e[24~\eOr")
}

// Verify Alt text and modified editing keys use conventional xterm forms.
@(test)
input_test_terminal_ring_encodes_alt_and_modified_editing :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    events := []Input_Event{
        {kind = .Text, codepoint = 'é', modifiers = {.Alt}},
        {kind = .Press, key = .Delete, modifiers = {.Shift, .Alt}},
        {kind = .Press, key = .Tab, modifiers = {.Shift}},
        {kind = .Press, key = .Left_Bracket, modifiers = {.Control, .Alt}},
    }
    bytes, count := input_test_encode_frame(&runtime, events)
    testing.expect_value(
        t, string(bytes[:count]), "\eé\e[3;4~\e[Z\e\e")
}

// Verify fixed runtime capture retains exactly its declared rune capacity.
@(test)
input_test_runtime_events_are_fixed_capacity :: proc(t: ^testing.T) {
    runtime: Input_Runtime

    for index in 0..<INPUT_EVENT_CAPACITY {
        testing.expect(t, input_runtime_append_event(&runtime, Input_Event{
            kind = .Text,
            codepoint = rune(index),
        }))
    }

    events := input_runtime_events(&runtime)
    testing.expect_value(t, len(events), INPUT_EVENT_CAPACITY)
    testing.expect_value(t, events[len(events) - 1].codepoint, rune(127))
}

// Verify bounded capture reports pressure and frame reset preserves diagnostics.
@(test)
input_test_runtime_event_overflow_is_explicit :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    runtime.event_count = INPUT_EVENT_CAPACITY

    testing.expect(t, !input_runtime_append_event(&runtime, Input_Event{}))
    testing.expect_value(t, runtime.event_overflow_count, u64(1))
    testing.expect(t, runtime.event_frame_overflowed)
    testing.expect(t, input_runtime_begin_frame(&runtime))
    testing.expect_value(t, len(input_runtime_events(&runtime)), 0)
    testing.expect_value(t, runtime.event_overflow_count, u64(1))
    testing.expect(t, !runtime.event_frame_overflowed)
}

// Verify one device physical event and one text event correlate reciprocally.
@(test)
input_test_runtime_correlates_unambiguous_device_events :: proc(t: ^testing.T) {
    kinds := [5]Input_Event_Kind{.Press, .Press, .Press, .Press, .Repeat}
    keys := [5]Input_Key{.A, .Slash, .A, .A, .Keypad1}
    codepoints := [5]rune{'a', '?', 'a', 'a', '1'}
    modifiers := [5]Input_Modifiers{{}, {.Shift}, {.Alt}, {.Control}, {}}
    for kind, index in kinds {
        runtime: Input_Runtime
        testing.expect(t, input_runtime_append_event(&runtime, {
            kind = kind, key = keys[index], modifiers = modifiers[index],
            origin = .Device,
        }))
        testing.expect(t, input_runtime_append_event(&runtime, {
            kind = .Text, codepoint = codepoints[index],
            modifiers = modifiers[index],
            origin = .Device,
        }))
        input_runtime_reconcile_events(&runtime)
        events := input_runtime_events(&runtime)
        testing.expect(t, events[0].correlation.valid)
        testing.expect_value(t, events[0].correlation.partner_index, u16(1))
        testing.expect(t, events[1].correlation.valid)
        testing.expect_value(t, events[1].correlation.partner_index, u16(0))
        testing.expect_value(t, runtime.correlation_accepted_count, u64(1))
        testing.expect_value(t, runtime.correlation_ambiguous_count, u64(0))
    }
}

// Verify ambiguous, synthetic, and text-only frames retain conservative fallback.
@(test)
input_test_runtime_correlation_falls_back_conservatively :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    events := [3]Input_Event{
        {kind = .Press, key = .A, origin = .Device},
        {kind = .Press, key = .B, origin = .Device},
        {kind = .Text, codepoint = 'a', origin = .Device},
    }
    for event in events {
        testing.expect(t, input_runtime_append_event(&runtime, event))
    }
    input_runtime_reconcile_events(&runtime)
    testing.expect_value(t, runtime.correlation_ambiguous_count, u64(1))
    for event in input_runtime_events(&runtime) {
        testing.expect(t, !event.correlation.valid)
    }

    testing.expect(t, input_runtime_begin_frame(&runtime))
    testing.expect(t, input_runtime_inject_events(&runtime,
        []Input_Event{{kind = .Press, key = .A}}))
    testing.expect(t, input_runtime_begin_frame(&runtime))
    testing.expect(t, input_runtime_append_event(&runtime, {
        kind = .Text, codepoint = 'a', origin = .Device,
    }))
    input_runtime_reconcile_events(&runtime)
    retained := input_runtime_events(&runtime)
    testing.expect_value(t, retained[0].origin, Input_Event_Origin.Synthetic)
    testing.expect(t, !retained[0].correlation.valid)
    testing.expect(t, !retained[1].correlation.valid)
    testing.expect_value(t, runtime.correlation_ambiguous_count, u64(1))
}

// Verify one physical event retains and atomically claims bounded committed text.
@(test)
input_test_runtime_correlates_bounded_associated_text :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    events := [3]Input_Event{
        {kind = .Press, key = .A, origin = .Device},
        {kind = .Text, codepoint = 'a', origin = .Device},
        {kind = .Text, codepoint = 'á', origin = .Device},
    }
    for event in events {
        testing.expect(t, input_runtime_append_event(&runtime, event))
    }
    input_runtime_reconcile_events(&runtime)
    retained := input_runtime_events(&runtime)
    testing.expect_value(t, runtime.correlation_accepted_count, u64(1))
    testing.expect_value(t, retained[0].correlation.partner_index, u16(1))
    testing.expect_value(t, retained[0].correlation.partner_count, u16(2))
    testing.expect_value(t, retained[1].correlation.partner_index, u16(0))
    testing.expect_value(t, retained[2].correlation.partner_index, u16(0))
    claims: Input_Event_Claim_State
    testing.expect(t, input_event_claim_pair({events = retained}, 0, &claims))
    testing.expect(t, claims.claimed[0] && claims.claimed[1] && claims.claimed[2])
}

// Verify text-only and release-only frames remain valid unpaired input.
@(test)
input_test_runtime_correlation_preserves_isolated_events :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    testing.expect(t, input_runtime_append_event(&runtime, {
        kind = .Text, codepoint = '界', origin = .Device,
    }))
    input_runtime_reconcile_events(&runtime)
    testing.expect(t, !runtime.events[0].correlation.valid)
    testing.expect_value(t, runtime.correlation_ambiguous_count, u64(0))

    testing.expect(t, input_runtime_begin_frame(&runtime))
    testing.expect(t, input_runtime_append_event(&runtime, {
        kind = .Release, key = .A, origin = .Device,
    }))
    input_runtime_reconcile_events(&runtime)
    testing.expect(t, !runtime.events[0].correlation.valid)
    testing.expect_value(t, runtime.correlation_ambiguous_count, u64(0))
}

// Verify modifier mismatch and capture overflow produce counted ambiguity.
@(test)
input_test_runtime_correlation_rejects_unreliable_frames :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    testing.expect(t, input_runtime_append_event(&runtime, {
        kind = .Press, key = .A, modifiers = {.Shift}, origin = .Device,
    }))
    testing.expect(t, input_runtime_append_event(&runtime, {
        kind = .Text, codepoint = 'a', origin = .Device,
    }))
    input_runtime_reconcile_events(&runtime)
    testing.expect_value(t, runtime.correlation_ambiguous_count, u64(1))

    testing.expect(t, input_runtime_begin_frame(&runtime))
    testing.expect(t, input_runtime_append_event(&runtime, {
        kind = .Press, key = .A, origin = .Device,
    }))
    testing.expect(t, input_runtime_append_event(&runtime, {
        kind = .Text, codepoint = 'a', origin = .Device,
    }))
    runtime.event_frame_overflowed = true
    input_runtime_reconcile_events(&runtime)
    testing.expect_value(t, runtime.correlation_ambiguous_count, u64(2))
    testing.expect_value(t, runtime.correlation_accepted_count, u64(0))
}

// Verify pair claims are reciprocal and event removal repairs retained indexes.
@(test)
input_test_event_pair_claim_and_removal_are_bounded :: proc(t: ^testing.T) {
    events := [3]Input_Event{
        {kind = .Press, key = .F12},
        {kind = .Press, key = .A,
            correlation = {partner_index = 2, valid = true}},
        {kind = .Text, codepoint = 'a',
            correlation = {partner_index = 1, valid = true}},
    }
    frame := input_frame_remove_event({events = events[:]}, 0)
    testing.expect_value(t, frame.events[0].correlation.partner_index, u16(1))
    testing.expect_value(t, frame.events[1].correlation.partner_index, u16(0))
    claims: Input_Event_Claim_State
    testing.expect(t, input_event_claim_pair(frame, 0, &claims))
    testing.expect(t, claims.claimed[0] && claims.claimed[1])
    testing.expect(t, !input_event_claim_pair(frame, 1, &claims))

    frame = input_frame_remove_event(frame, 0)
    testing.expect(t, !frame.events[0].correlation.valid)
}

// Verify correlation metadata alone does not alter legacy terminal bytes.
@(test)
input_test_correlated_events_preserve_legacy_bytes :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    testing.expect(t, input_runtime_append_event(&runtime, {
        kind = .Press, key = .A, origin = .Device,
    }))
    testing.expect(t, input_runtime_append_event(&runtime, {
        kind = .Text, codepoint = 'a', origin = .Device,
    }))
    input_runtime_reconcile_events(&runtime)
    input_terminal_enqueue_frame(
        &runtime, {events = input_runtime_events(&runtime)}, {})
    bytes: [8]u8
    count := input_runtime_copy_queued_bytes(&runtime, bytes[:])
    testing.expect_value(t, string(bytes[:count]), "a")
}

// Verify xterm levels preserve legacy Tab where required and encode exact extensions.
@(test)
input_test_modify_other_keys_levels_encode_exact_bytes :: proc(t: ^testing.T) {
    cases := []struct {
        level: u8,
        event: Input_Event,
        expected: string,
    }{
        {0, {kind = .Press, key = .Tab, modifiers = {.Alt}}, "\e\t"},
        {1, {kind = .Press, key = .Tab, modifiers = {.Alt}}, "\e[27;3;9~"},
        {1, {kind = .Press, key = .Tab, modifiers = {.Shift}}, "\e[Z"},
        {2, {kind = .Press, key = .Tab, modifiers = {.Shift}}, "\e[27;2;9~"},
        {2, {kind = .Repeat, key = .Tab, modifiers = {.Alt, .Control}},
            "\e[27;7;9~"},
    }
    for test_case in cases {
        runtime: Input_Runtime
        events := []Input_Event{test_case.event}
        bytes, count := input_test_encode_frame(
            &runtime, events, modify_other_keys_level = test_case.level)
        testing.expect_value(t, string(bytes[:count]), test_case.expected)
    }
}

// Verify paired text supplies shifted punctuation and is claimed after one encoding.
@(test)
input_test_modify_other_keys_claims_correlated_text :: proc(t: ^testing.T) {
    cases := []struct {
        modifiers: Input_Modifiers,
        key: Input_Key,
        codepoint: rune,
        expected: string,
    }{
        {{.Shift}, .Digit1, '!', "\e[27;2;33~"},
        {{.Alt}, .A, 'a', "\e[27;3;97~"},
        {{.Control, .Shift}, .A, 'A', "\e[27;6;65~"},
        {{.Alt, .Control}, .Semicolon, ';', "\e[27;7;59~"},
    }
    for test_case in cases {
        runtime: Input_Runtime
        events := [2]Input_Event{
            {kind = .Press, key = test_case.key,
                modifiers = test_case.modifiers,
                correlation = {partner_index = 1, valid = true}},
            {kind = .Text, codepoint = test_case.codepoint,
                modifiers = test_case.modifiers,
                correlation = {partner_index = 0, valid = true}},
        }
        bytes, count := input_test_encode_frame(
            &runtime, events[:], modify_other_keys_level = 2)
        testing.expect_value(t, string(bytes[:count]), test_case.expected)
    }
}

// Verify level one keeps conventional Control and extends unrepresentable chords.
@(test)
input_test_modify_other_keys_level_one_control_policy :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    conventional := []Input_Event{
        {kind = .Press, key = .A, modifiers = {.Control}},
    }
    bytes, count := input_test_encode_frame(
        &runtime, conventional, modify_other_keys_level = 1)
    testing.expect_value(t, string(bytes[:count]), "\x01")
    testing.expect(t, input_runtime_pop_queued_bytes(&runtime, count))

    extended := []Input_Event{
        {kind = .Press, key = .Digit1, modifiers = {.Control}},
    }
    bytes, count = input_test_encode_frame(
        &runtime, extended, modify_other_keys_level = 1)
    testing.expect_value(t, string(bytes[:count]), "\e[27;5;49~")
}

// Verify uncertain text and excluded key classes retain legacy encoding.
@(test)
input_test_modify_other_keys_preserves_legacy_fallbacks :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    events := []Input_Event{
        {kind = .Press, key = .A, modifiers = {.Shift}},
        {kind = .Text, codepoint = 'A', modifiers = {.Shift}},
        {kind = .Press, key = .Up, modifiers = {.Shift}},
        {kind = .Press, key = .A, modifiers = {.Super}},
        {kind = .Text, codepoint = 'a', modifiers = {.Super}},
    }
    bytes, count := input_test_encode_frame(
        &runtime, events, modify_other_keys_level = 2)
    testing.expect_value(t, string(bytes[:count]), "A\e[1;2Aa")
}

// Verify queue rejection leaves a correlated pair unclaimed and emits no fallback.
@(test)
input_test_modify_other_keys_rejection_is_transactional :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    runtime.byte_queue_count = len(runtime.byte_queue) - 1
    events := [2]Input_Event{
        {kind = .Press, key = .A, modifiers = {.Alt},
            correlation = {partner_index = 1, valid = true}},
        {kind = .Text, codepoint = 'a', modifiers = {.Alt},
            correlation = {partner_index = 0, valid = true}},
    }
    claims: Input_Event_Claim_State
    outcome := input_terminal_enqueue_modify_other_key(
        &runtime, {events = events[:]}, 0, 1, &claims)
    testing.expect_value(t, outcome, Input_Protocol_Key_Outcome.Blocked)
    testing.expect(t, !claims.claimed[0] && !claims.claimed[1])
    testing.expect_value(t, runtime.byte_queue_count, len(runtime.byte_queue) - 1)
}

// Verify Kitty flag 1 disambiguates Escape and modified ordinary ASCII keys.
@(test)
input_test_kitty_keyboard_encodes_disambiguated_keys :: proc(t: ^testing.T) {
    cases := []struct {
        event: Input_Event,
        expected: string,
    }{
        {{kind = .Press, key = .Escape}, "\e[27u"},
        {{kind = .Press, key = .A, modifiers = {.Alt}}, "\e[97;3u"},
        {{kind = .Press, key = .C, modifiers = {.Control}}, "\e[99;5u"},
        {{kind = .Repeat, key = .C, modifiers = {.Control}}, "\e[99;5u"},
    }
    for test_case in cases {
        runtime: Input_Runtime
        events := []Input_Event{test_case.event}
        bytes, count := input_test_encode_frame(
            &runtime, events, kitty_keyboard_flags = 1)
        testing.expect_value(t, string(bytes[:count]), test_case.expected)
    }
}

// Verify Kitty claims correlated text while preserving ordinary UTF-8 and reset keys.
@(test)
input_test_kitty_keyboard_preserves_text_and_legacy_reset_keys :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    events := []Input_Event{
        {kind = .Press, key = .A, modifiers = {.Shift, .Alt},
            correlation = {partner_index = 1, valid = true}},
        {kind = .Text, codepoint = 'A', modifiers = {.Shift, .Alt},
            correlation = {partner_index = 0, valid = true}},
        {kind = .Text, codepoint = '界'},
        {kind = .Press, key = .Enter},
        {kind = .Press, key = .Tab},
        {kind = .Press, key = .Backspace},
        {kind = .Release, key = .Escape},
    }
    bytes, count := input_test_encode_frame(
        &runtime, events, kitty_keyboard_flags = 1)
    testing.expect_value(t, string(bytes[:count]),
        "\e[97;4u界\r\t\x7f")
}

// Verify Kitty emits distinct keypad identities and suppresses paired glyph text.
@(test)
input_test_kitty_keyboard_disambiguates_keypad :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    events := []Input_Event{
        {kind = .Press, key = .Keypad0,
            correlation = {partner_index = 1, valid = true}},
        {kind = .Text, codepoint = '0',
            correlation = {partner_index = 0, valid = true}},
        {kind = .Press, key = .Keypad_Equal, modifiers = {.Control}},
    }
    bytes, count := input_test_encode_frame(
        &runtime, events, kitty_keyboard_flags = 1)
    testing.expect_value(t, string(bytes[:count]), "\e[57399u\e[57415;5u")
}

// Verify Kitty takes precedence and legacy ambiguity remains when evidence is absent.
@(test)
input_test_kitty_keyboard_precedes_modify_other_keys :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    events := []Input_Event{
        {kind = .Press, key = .A, modifiers = {.Alt}},
        {kind = .Press, key = .Up, modifiers = {.Shift}},
    }
    bytes, count := input_test_encode_frame(
        &runtime, events, modify_other_keys_level = 2,
        kitty_keyboard_flags = 1)
    testing.expect_value(t, string(bytes[:count]), "\e[97;3u\e[1;2A")
    testing.expect(t, input_runtime_pop_queued_bytes(&runtime, count))

    bytes, count = input_test_encode_frame(
        &runtime, events[:1], modify_other_keys_level = 2)
    testing.expect_value(t, string(bytes[:count]), "\e[27;3;97~")
}

// Verify unpaired text ambiguity remains on the duplicate-preserving legacy path.
@(test)
input_test_kitty_keyboard_preserves_ambiguous_text :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    events := []Input_Event{
        {kind = .Press, key = .A, modifiers = {.Alt}},
        {kind = .Text, codepoint = 'a', modifiers = {.Alt}},
        {kind = .Text, codepoint = 'b', modifiers = {.Alt}},
    }
    bytes, count := input_test_encode_frame(
        &runtime, events, kitty_keyboard_flags = 17)
    testing.expect_value(t, string(bytes[:count]), "\ea\eb")
    testing.expect_value(t, runtime.input_fallback_count, u64(1))
}

// Verify rejected Kitty admission neither claims paired text nor emits a fallback.
@(test)
input_test_kitty_keyboard_rejection_is_transactional :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    runtime.byte_queue_count = len(runtime.byte_queue) - 1
    events := [2]Input_Event{
        {kind = .Press, key = .A, modifiers = {.Alt},
            correlation = {partner_index = 1, valid = true}},
        {kind = .Text, codepoint = 'a', modifiers = {.Alt},
            correlation = {partner_index = 0, valid = true}},
    }
    claims: Input_Event_Claim_State
    outcome := input_terminal_enqueue_kitty_key(
        &runtime, {events = events[:]}, 0, 1, &claims)
    testing.expect_value(t, outcome, Input_Protocol_Key_Outcome.Blocked)
    testing.expect(t, !claims.claimed[0] && !claims.claimed[1])
    testing.expect_value(t, runtime.byte_queue_count, len(runtime.byte_queue) - 1)
}

// Verify Kitty flag 2 distinguishes repeat and release for CSI-u keys.
@(test)
input_test_kitty_keyboard_encodes_event_types :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    events := []Input_Event{
        {kind = .Press, key = .Escape},
        {kind = .Repeat, key = .Escape},
        {kind = .Release, key = .Escape},
        {kind = .Press, key = .C, modifiers = {.Control}},
        {kind = .Repeat, key = .C, modifiers = {.Control}},
        {kind = .Release, key = .C, modifiers = {.Control}},
        {kind = .Repeat, key = .Keypad0},
        {kind = .Release, key = .Keypad_Enter},
    }
    bytes, count := input_test_encode_frame(
        &runtime, events, kitty_keyboard_flags = 3)
    testing.expect_value(t, string(bytes[:count]),
        "\e[27u\e[27;1:2u\e[27;1:3u" +
        "\e[99;5u\e[99;5:2u\e[99;5:3u" +
        "\e[57399;1:2u\e[57414;1:3u")
}

// Verify a typed repeat claims its correlated text only after complete admission.
@(test)
input_test_kitty_keyboard_event_type_claims_correlated_text :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    events := [2]Input_Event{
        {kind = .Repeat, key = .A, modifiers = {.Shift, .Alt},
            correlation = {partner_index = 1, valid = true}},
        {kind = .Text, codepoint = 'A', modifiers = {.Shift, .Alt},
            correlation = {partner_index = 0, valid = true}},
    }
    bytes, count := input_test_encode_frame(
        &runtime, events[:], kitty_keyboard_flags = 3)
    testing.expect_value(t, string(bytes[:count]), "\e[97;4:2u")
}

// Verify flag 2 alone preserves Press compatibility and types later events.
@(test)
input_test_kitty_keyboard_event_flag_is_independent :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    events := []Input_Event{
        {kind = .Press, key = .Escape},
        {kind = .Repeat, key = .Escape},
        {kind = .Release, key = .Escape},
        {kind = .Press, key = .Up},
        {kind = .Repeat, key = .Up},
        {kind = .Release, key = .Up},
    }
    bytes, count := input_test_encode_frame(
        &runtime, events, kitty_keyboard_flags = 2)
    testing.expect_value(t, string(bytes[:count]),
        "\e\e[27;1:2u\e[27;1:3u\e[A\e[1;1:2A\e[1;1:3A")
}

// Verify Kitty event types augment canonical navigation, editing, and function forms.
@(test)
input_test_kitty_keyboard_encodes_functional_event_types :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    events := []Input_Event{
        {kind = .Press, key = .Up},
        {kind = .Repeat, key = .Up},
        {kind = .Release, key = .Up, modifiers = {.Shift}},
        {kind = .Repeat, key = .Delete},
        {kind = .Release, key = .F3},
        {kind = .Repeat, key = .F12, modifiers = {.Super}},
    }
    bytes, count := input_test_encode_frame(
        &runtime, events, kitty_keyboard_flags = 3)
    testing.expect_value(t, string(bytes[:count]),
        "\e[A\e[1;1:2A\e[1;2:3A\e[3;1:2~" +
        "\e[13;1:3~\e[24;9:2~")
}

// Verify text and recovery keys retain legacy behavior under event reporting.
@(test)
input_test_kitty_keyboard_event_types_preserve_text_exceptions :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    events := []Input_Event{
        {kind = .Press, key = .A},
        {kind = .Text, codepoint = 'a'},
        {kind = .Repeat, key = .A},
        {kind = .Release, key = .A},
        {kind = .Repeat, key = .Enter},
        {kind = .Release, key = .Enter},
        {kind = .Repeat, key = .Tab},
        {kind = .Release, key = .Tab},
        {kind = .Repeat, key = .Backspace},
        {kind = .Release, key = .Backspace},
    }
    bytes, count := input_test_encode_frame(
        &runtime, events, kitty_keyboard_flags = 3)
    testing.expect_value(t, string(bytes[:count]), "a\r\t\x7f")
}

// Verify flag 4 reports authoritative shifted identities for letters and punctuation.
@(test)
input_test_kitty_keyboard_reports_alternate_keys :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    events := [4]Input_Event{
        {kind = .Press, key = .A, modifiers = {.Shift},
            correlation = {partner_index = 1, valid = true}},
        {kind = .Text, codepoint = 'A', modifiers = {.Shift},
            correlation = {partner_index = 0, valid = true}},
        {kind = .Press, key = .Slash, modifiers = {.Shift},
            correlation = {partner_index = 3, valid = true}},
        {kind = .Text, codepoint = '?', modifiers = {.Shift},
            correlation = {partner_index = 2, valid = true}},
    }
    bytes, count := input_test_encode_frame(
        &runtime, events[:], kitty_keyboard_flags = 4)
    testing.expect_value(t, string(bytes[:count]), "\e[97:65;2u\e[47:63;2u")
}

// Verify flag 8 reports ordinary and recovery presses without duplicate text.
@(test)
input_test_kitty_keyboard_reports_all_keys :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    events := [5]Input_Event{
        {kind = .Press, key = .A,
            correlation = {partner_index = 1, valid = true}},
        {kind = .Text, codepoint = 'a',
            correlation = {partner_index = 0, valid = true}},
        {kind = .Press, key = .Enter},
        {kind = .Press, key = .Tab},
        {kind = .Press, key = .Backspace},
    }
    bytes, count := input_test_encode_frame(
        &runtime, events[:], kitty_keyboard_flags = 8)
    testing.expect_value(t, string(bytes[:count]),
        "\e[97u\e[13u\e[9u\e[127u")
}

// Verify flag 16 emits all bounded committed text and claims the complete group.
@(test)
input_test_kitty_keyboard_reports_associated_text :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    events := [3]Input_Event{
        {kind = .Press, key = .A, modifiers = {.Shift},
            correlation = {partner_index = 1, partner_count = 2, valid = true}},
        {kind = .Text, codepoint = 'A', modifiers = {.Shift},
            correlation = {partner_index = 0, valid = true}},
        {kind = .Text, codepoint = rune(0x301), modifiers = {.Shift},
            correlation = {partner_index = 0, valid = true}},
    }
    bytes, count := input_test_encode_frame(
        &runtime, events[:], kitty_keyboard_flags = 20)
    testing.expect_value(t, string(bytes[:count]),
        "\e[97:65;2;65:769u")
}

// Verify a rejected associated-text sequence leaves every group event unclaimed.
@(test)
input_test_kitty_keyboard_associated_text_rejection_is_atomic :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    runtime.byte_queue_count = len(runtime.byte_queue) - 1
    events := [3]Input_Event{
        {kind = .Press, key = .A,
            correlation = {partner_index = 1, partner_count = 2, valid = true}},
        {kind = .Text, codepoint = 'a',
            correlation = {partner_index = 0, valid = true}},
        {kind = .Text, codepoint = rune(0x301),
            correlation = {partner_index = 0, valid = true}},
    }
    claims: Input_Event_Claim_State
    outcome := input_terminal_enqueue_kitty_key(
        &runtime, {events = events[:]}, 0, 24, &claims)
    testing.expect_value(t, outcome, Input_Protocol_Key_Outcome.Blocked)
    testing.expect(t,
        !claims.claimed[0] && !claims.claimed[1] && !claims.claimed[2])
    testing.expect_value(t, runtime.byte_queue_count, len(runtime.byte_queue) - 1)
}

// Verify a blocked typed release does not fall through or partially enter the ring.
@(test)
input_test_kitty_keyboard_event_type_rejection_is_atomic :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    runtime.byte_queue_count = len(runtime.byte_queue) - 1
    events := []Input_Event{{kind = .Release, key = .Up}}
    input_terminal_enqueue_frame(
        &runtime, {events = events}, {}, kitty_keyboard_flags = 3)
    testing.expect_value(t, runtime.byte_queue_count, len(runtime.byte_queue) - 1)
    testing.expect_value(t, runtime.byte_queue_rejection_count, u64(1))
    testing.expect_value(t, runtime.input_atomic_rejection_count, u64(1))
}

// Verify semantic replies preserve existing FIFO bytes and precede later frame input.
@(test)
input_test_terminal_responses_preserve_delivery_order :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    owner := Input_Owner{kind = .Terminal_Session, id = 4, generation = 7}
    testing.expect(t, input_runtime_set_owner(&runtime, owner))
    testing.expect(t, input_runtime_enqueue_bytes(&runtime, []u8{'x'}))
    retained: termemulator.Terminal_Title_State
    interpreter := termemulator.Interpreter{title_state = &retained}
    producer := termmodel.Terminal_Producer{
        kind = .Terminal_Session, id = 4, generation = 7}
    testing.expect(t, termemulator.interpreter_enqueue_response(&interpreter, {
        kind = .Modify_Other_Keys, first = 1, producer = producer}))
    testing.expect(t, termemulator.interpreter_enqueue_response(&interpreter, {
        kind = .Modify_Other_Keys, first = 2, producer = producer}))
    testing.expect(t, termemulator.interpreter_enqueue_response(&interpreter, {
        kind = .Kitty_Keyboard, first = 1, producer = producer}))
    testing.expect(t, termemulator.interpreter_enqueue_response(&interpreter, {
        kind = .Primary_Device_Attributes, producer = producer}))

    testing.expect(t, input_terminal_drain_responses(&runtime, &interpreter))
    input_terminal_enqueue_frame(&runtime, {
        events = []Input_Event{{kind = .Text, codepoint = 'y'}},
    }, {})
    bytes: [32]u8
    count := input_runtime_copy_queued_bytes(&runtime, bytes[:])
    testing.expect_value(t, string(bytes[:count]),
        "x\e[>4;1m\e[>4;2m\e[?1u\e[?62;4cy")
    testing.expect_value(t, retained.response_count, 0)
}

// Initialize one terminal-response encoding fixture with a correlated owner.
input_test_init_response_encoding :: proc(
    t: ^testing.T, runtime: ^Input_Runtime,
    interpreter: ^termemulator.Interpreter,
    retained: ^termemulator.Terminal_Title_State) -> termmodel.Terminal_Producer {
    producer := termmodel.Terminal_Producer{.Terminal_Session, 6, 9}
    testing.expect(t, input_runtime_set_owner(runtime, {
        kind = .Terminal_Session, id = 6, generation = 9,
    }))
    interpreter^ = {title_state = retained}
    return producer
}

// Verify keyboard and fixed identity responses have exact bounded encodings.
@(test)
input_test_terminal_query_response_encodings :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    retained: termemulator.Terminal_Title_State
    interpreter: termemulator.Interpreter
    producer := input_test_init_response_encoding(
        t, &runtime, &interpreter, &retained)
    fixtures := [?]Input_Terminal_Response_Fixture{
        {
            response = {kind = .Modify_Other_Keys, first = 2,
                producer = producer},
            bytes = "\e[>4;2m",
        },
        {
            response = {kind = .Kitty_Keyboard, first = 3,
                producer = producer},
            bytes = "\e[?3u",
        },
        {
            response = {kind = .Primary_Device_Attributes, producer = producer},
            bytes = "\e[?62;4c",
        },
        {
            response = {kind = .Secondary_Device_Attributes,
                producer = producer},
            bytes = "\e[>1;0;0c",
        },
        {
            response = {kind = .Device_Status, producer = producer},
            bytes = "\e[0n",
        },
    }
    for fixture in fixtures {
        input_test_expect_terminal_response_fixture(
            t, &runtime, &interpreter, fixture)
    }
    testing.expect_value(t, retained.response_count, 0)
}

// Verify cursor, mode, and geometry responses have exact bounded encodings.
@(test)
input_test_terminal_geometry_response_encodings :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    producer := termmodel.Terminal_Producer{.Terminal_Session, 6, 9}
    testing.expect(t, input_runtime_set_owner(&runtime, {
        kind = .Terminal_Session, id = 6, generation = 9,
    }))
    retained: termemulator.Terminal_Title_State
    interpreter := termemulator.Interpreter{title_state = &retained}
    fixtures := [?]Input_Terminal_Response_Fixture{
        {{kind = .Cursor_Position, first = 12, second = 34,
            producer = producer}, "\e[12;34R"},
        {{kind = .Private_Mode_Status, first = 2004, second = 1,
            producer = producer}, "\e[?2004;1$y"},
        {{kind = .Window_Pixels, first = 480, second = 640,
            producer = producer}, "\e[4;480;640t"},
        {{kind = .Cell_Pixels, first = 16, second = 8,
            producer = producer}, "\e[6;16;8t"},
        {{kind = .Text_Area_Size, first = 24, second = 80,
            producer = producer}, "\e[8;24;80t"},
        {{kind = .Osc_Color, first = 4, second = 17, third = 0x123456ff,
            producer = producer}, "\e]4;17;rgb:1212/3434/5656\e\\"},
        {{kind = .Osc_Color, first = 11, third = 0xabcdef00,
            producer = producer}, "\e]11;rgb:abab/cdcd/efef\e\\"},
    }
    for fixture in fixtures {
        input_test_expect_terminal_response_fixture(
            t, &runtime, &interpreter, fixture)
    }
    testing.expect_value(t, retained.response_count, 0)
}

// Verify every DCS query response fixture has its exact bounded encoding.
input_test_expect_dcs_query_response_fixtures :: proc(
    t: ^testing.T, runtime: ^Input_Runtime,
    interpreter: ^termemulator.Interpreter,
    producer: termmodel.Terminal_Producer) {
    attributes := termemulator.TERMINAL_SGR_BOLD |
        termemulator.TERMINAL_SGR_ITALIC | termemulator.TERMINAL_SGR_UNDERLINE
    fixtures := [?]Input_Terminal_Response_Fixture{
        {{kind = .Decrqss_Sgr, first = attributes,
            second = u32(termpalette.terminal_color_indexed(17)),
            third = u32(termpalette.terminal_color_direct(0x010203ff)),
            producer = producer},
            "\eP1$r0;1;3;4;38;5;17;48;2;1;2;3m\e\\"},
        {{kind = .Decrqss_Cursor_Style, producer = producer},
            "\eP1$r0 q\e\\"},
        {{kind = .Decrqss_Margins, first = 2, second = 23,
            producer = producer}, "\eP1$r2;23r\e\\"},
        {{kind = .Decrqss_Unsupported, producer = producer}, "\eP0$r\e\\"},
        {{kind = .Xtgetcap,
            first = u32(termemulator.Terminal_Capability_Kind.Terminal_Name),
            producer = producer}, "\eP1+r544e=746963746163637261776c\e\\"},
        {{kind = .Xtgetcap, first = u32(termemulator.Terminal_Capability_Kind.Colors),
            producer = producer}, "\eP1+r436f=323536\e\\"},
        {{kind = .Xtgetcap, first = u32(termemulator.Terminal_Capability_Kind.Rgb),
            producer = producer}, "\eP1+r524742=38\e\\"},
        {{kind = .Xtgetcap, first = u32(termemulator.Terminal_Capability_Kind.Truecolor),
            producer = producer}, "\eP1+r5463\e\\"},
        {{kind = .Xtgetcap, second = 0x61356135,
            producer = producer}, "\eP0+r5a5a\e\\"},
        {{kind = .Mode_Status, first = 4, second = 1,
            producer = producer}, "\e[4;1$y"},
    }
    for fixture in fixtures {
        input_test_expect_terminal_response_fixture(
            t, runtime, interpreter, fixture)
    }
}

// Verify DECRQSS and XTGETTCAP semantic replies have exact bounded encodings.
@(test)
input_test_terminal_dcs_query_response_encodings :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    retained: termemulator.Terminal_Title_State
    interpreter: termemulator.Interpreter
    producer := input_test_init_response_encoding(
        t, &runtime, &interpreter, &retained)
    input_test_expect_dcs_query_response_fixtures(
        t, &runtime, &interpreter, producer)
}

// Verify response pressure retains the semantic head for a later complete admission.
@(test)
input_test_terminal_response_pressure_retains_head :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    testing.expect(t, input_runtime_set_owner(&runtime, {
        kind = .Terminal_Session, id = 1, generation = 1}))
    runtime.byte_queue_count = len(runtime.byte_queue) - 1
    retained: termemulator.Terminal_Title_State
    interpreter := termemulator.Interpreter{title_state = &retained}
    testing.expect(t, termemulator.interpreter_enqueue_response(&interpreter, {
        kind = .Kitty_Keyboard, first = 3,
        producer = {.Terminal_Session, 1, 1},
    }))
    testing.expect(t, !input_terminal_drain_responses(&runtime, &interpreter))
    testing.expect_value(t, retained.response_count, 1)
    testing.expect_value(t, runtime.byte_queue_count, len(runtime.byte_queue) - 1)
}

// Verify response capacity is fixed and overflow is counted without replacement.
@(test)
input_test_terminal_response_capacity_is_bounded :: proc(t: ^testing.T) {
    retained: termemulator.Terminal_Title_State
    interpreter := termemulator.Interpreter{title_state = &retained}
    for index in 0..<termemulator.TERMINAL_RESPONSE_CAPACITY {
        testing.expect(t, termemulator.interpreter_enqueue_response(&interpreter, {
            kind = .Modify_Other_Keys, first = u32(index % 3),
        }))
    }
    testing.expect(t, !termemulator.interpreter_enqueue_response(&interpreter, {
        kind = .Modify_Other_Keys,
    }))
    testing.expect_value(t, retained.response_count,
        termemulator.TERMINAL_RESPONSE_CAPACITY)
    testing.expect_value(t, retained.response_rejection_count, u64(1))
}

// Verify stale shell replies are discarded while Julia replies await their lease.
@(test)
input_test_terminal_responses_respect_producer_lifetimes :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    retained: termemulator.Terminal_Title_State
    interpreter := termemulator.Interpreter{title_state = &retained}
    testing.expect(t, input_runtime_set_owner(&runtime, {
        kind = .Terminal_Session, id = 2, generation = 9}))
    testing.expect(t, termemulator.interpreter_enqueue_response(&interpreter, {
        kind = .Modify_Other_Keys,
        producer = {.Terminal_Session, 2, 8},
    }))
    testing.expect(t, input_terminal_drain_responses(&runtime, &interpreter))
    testing.expect_value(t, retained.response_count, 0)
    testing.expect_value(t, retained.response_stale_discard_count, u64(1))

    testing.expect(t, termemulator.interpreter_enqueue_response(&interpreter, {
        kind = .Modify_Other_Keys, first = 2,
        producer = {.Julia_Evaluation, 12, 0},
    }))
    testing.expect(t, input_terminal_drain_responses(&runtime, &interpreter))
    testing.expect_value(t, retained.response_count, 1)
    testing.expect(t, input_runtime_set_owner(&runtime, {
        kind = .Julia_Interactive, id = 12}))
    testing.expect(t, input_terminal_drain_responses(&runtime, &interpreter))
    testing.expect_value(t, retained.response_count, 0)
    bytes: [16]u8
    count := input_runtime_copy_queued_bytes(&runtime, bytes[:])
    testing.expect_value(t, string(bytes[:count]), "\e[>4;2m")
}

// Verify Kitty graphics replies are bounded, correlated, and protocol encoded.
@(test)
input_test_kitty_graphics_response_delivery :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    testing.expect(t, input_runtime_set_owner(&runtime, {
        kind = .Terminal_Session, id = 3, generation = 4,
    }))
    graphics: gfxprotocol.Graphics_Parser_State
    retained := termemulator.Terminal_Title_State{graphics = &graphics}
    interpreter := termemulator.Interpreter{title_state = &retained}
    producer := termmodel.Terminal_Producer{.Terminal_Session, 3, 4}
    testing.expect(t, gfxprotocol.graphics_parser_queue_kitty_response(&graphics, {
        producer = producer, image_id = 7, placement_id = 9, status = .Ok,
    }))
    testing.expect(t, gfxprotocol.graphics_parser_queue_kitty_response(&graphics, {
        producer = producer, image_number = 4, status = .Invalid,
    }))

    testing.expect(t, input_terminal_drain_responses(&runtime, &interpreter))
    bytes: [64]u8
    count := input_runtime_copy_queued_bytes(&runtime, bytes[:])
    testing.expect_value(t, string(bytes[:count]),
        "\e_Gi=7,p=9;OK\e\\\e_GI=4;EINVAL\e\\")

    testing.expect(t, gfxprotocol.graphics_parser_queue_kitty_response(&graphics, {
        producer = {.Terminal_Session, 3, 3}, status = .Unsupported,
    }))
    testing.expect(t, input_terminal_drain_responses(&runtime, &interpreter))
    testing.expect_value(t, graphics.kitty_response_stale_discard_count, u64(1))
    testing.expect(t, gfxprotocol.graphics_parser_queue_kitty_response(&graphics, {
        producer = {.Julia_Evaluation, 12, 0}, status = .Capacity_Exceeded,
    }))
    testing.expect(t, input_terminal_drain_responses(&runtime, &interpreter))
    testing.expect_value(t, graphics.kitty_response_count, 1)
}

// Verify the byte ring preserves FIFO order across physical wraparound.
@(test)
input_test_runtime_byte_queue_wraps_without_splitting :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    runtime.byte_queue_start = len(runtime.byte_queue) - 2
    testing.expect(t, input_runtime_enqueue_bytes(&runtime, []u8{'a', 'b', 'c'}))
    copied: [3]u8
    testing.expect_value(t,
        input_runtime_copy_queued_bytes(&runtime, copied[:]), len(copied))
    testing.expect_value(t, string(copied[:]), "abc")
    testing.expect(t, input_runtime_pop_queued_bytes(&runtime, 3))
    testing.expect_value(t, runtime.byte_queue_count, 0)
    testing.expect_value(t, runtime.byte_queue_start, 0)
}

// Verify owner transitions discard retained bytes and preserve diagnostics.
@(test)
input_test_runtime_owner_transition_discards_stale_bytes :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    shell := Input_Owner{kind = .Terminal_Session, id = 1, generation = 2}
    julia := Input_Owner{kind = .Julia_Interactive, id = 7}
    testing.expect(t, input_runtime_set_owner(&runtime, shell))
    testing.expect(t, input_runtime_enqueue_bytes(&runtime, []u8{'x', 'y'}))
    testing.expect(t, input_runtime_set_owner(&runtime, shell))
    testing.expect_value(t, runtime.byte_queue_count, 2)
    testing.expect(t, input_runtime_set_owner(&runtime, julia))
    testing.expect_value(t, runtime.byte_queue_count, 0)
    testing.expect_value(t, runtime.stale_byte_discard_count, u64(2))
}

// Verify capacity pressure rejects an entire sequence without mutating the queue.
@(test)
input_test_runtime_byte_queue_rejects_whole_sequence :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    runtime.byte_queue_count = len(runtime.byte_queue) - 1
    testing.expect(t, !input_runtime_enqueue_bytes(&runtime, []u8{'a', 'b'}))
    testing.expect_value(t, runtime.byte_queue_count, len(runtime.byte_queue) - 1)
    testing.expect_value(t, runtime.byte_queue_rejection_count, u64(1))
}

// Verify a complete valid registry snapshot publishes atomically.
@(test)
input_test_runtime_registry_commits_complete_snapshot :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    input_runtime_begin_registry(&runtime, {generation = 1, expected_count = 2})
    input_runtime_stage_registry_entry(&runtime, {
        generation = 1,
        index = 0,
        action = .Toggle_Terminal,
        key = .T,
        modifiers = transmute(u8)Input_Modifiers{.Control},
        scope = .Application,
    })
    input_runtime_stage_registry_entry(&runtime, {
        generation = 1,
        index = 1,
        action = .Toggle_Terminal,
        key = .F12,
        modifiers = transmute(u8)Input_Modifiers{.Control, .Shift},
        scope = .Reserved_Global,
    })
    result := input_runtime_commit_registry(&runtime, {generation = 1})
    testing.expect(t, result.accepted)
    testing.expect_value(t, runtime.active_binding_count, 2)
    testing.expect_value(t, runtime.active_bindings[0].key, Input_Key.T)
    testing.expect_value(t, runtime.active_bindings[1].scope,
        protocol.Hotkey_Scope.Reserved_Global)
}

// Verify a conflicting snapshot is rejected without replacing active bindings.
@(test)
input_test_runtime_registry_rejection_preserves_active :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    runtime.active_registry_generation = 1
    runtime.active_binding_count = 1
    runtime.active_bindings[0] = {
        action = .Toggle_Terminal,
        key = .T,
        modifiers = {.Control},
        scope = .Application,
    }
    input_runtime_begin_registry(&runtime, {generation = 2, expected_count = 2})
    for index in 0..<2 {
        input_runtime_stage_registry_entry(&runtime, {
            generation = 2,
            index = i32(index),
            action = .Toggle_Terminal,
            key = .F1,
            modifiers = transmute(u8)Input_Modifiers{.Control},
            scope = .Application,
        })
    }
    result := input_runtime_commit_registry(&runtime, {generation = 2})
    testing.expect(t, !result.accepted)
    testing.expect_value(t, result.reason,
        protocol.Hotkey_Registry_Reason.Duplicate_Chord)
    testing.expect_value(t, runtime.active_registry_generation, u64(1))
    testing.expect_value(t, runtime.active_bindings[0].key, Input_Key.T)
}

// Verify exact registry chords honor reserved-global filtering under ownership.
@(test)
input_test_registry_lookup_respects_scope :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    runtime.active_binding_count = 2
    runtime.active_bindings[0] = {
        action = .Toggle_Terminal, key = .T,
        modifiers = {.Control}, scope = .Application}
    runtime.active_bindings[1] = {
        action = .Toggle_Terminal, key = .F12,
        modifiers = {.Control, .Shift}, scope = .Reserved_Global}
    events := [2]Input_Event{
        {kind = .Press, key = .T, modifiers = {.Control}},
        {kind = .Press, key = .F12, modifiers = {.Control, .Shift}},
    }
    frame := Input_Frame{events = events[:]}
    _, application_matched := input_registry_action_pressed(&runtime, frame, false)
    _, global_matched := input_registry_action_pressed(&runtime, frame, true)
    testing.expect(t, application_matched)
    testing.expect(t, global_matched)
}

// Verify a consumed global chord cannot also become terminal bytes.
@(test)
input_test_consumed_global_hotkey_is_excluded_from_terminal :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    runtime.active_binding_count = 1
    runtime.active_bindings[0] = {
        action = .Toggle_Terminal, key = .F12,
        modifiers = {.Control, .Shift}, scope = .Reserved_Global}
    events := [2]Input_Event{
        {kind = .Press, key = .F12, modifiers = {.Control, .Shift}},
        {kind = .Text, codepoint = 'x'},
    }
    frame := Input_Frame{events = events[:]}
    hotkey_match, matched := input_registry_action_pressed(&runtime, frame, true)
    testing.expect(t, matched)

    frame = input_frame_remove_event(frame, hotkey_match.event_index)
    input_terminal_enqueue_frame(&runtime, frame, {})
    bytes: [8]u8
    count := input_runtime_copy_queued_bytes(&runtime, bytes[:])
    testing.expect_value(t, string(bytes[:count]), "x")
}

// Verify bracketed paste wrappers and payload enter the ring as one admission.
@(test)
input_test_terminal_bracketed_paste :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    testing.expect(t, input_terminal_enqueue_paste(
        &runtime, "a\e[200~b\e[201~c", true))
    bytes: [64]u8
    count := input_runtime_copy_queued_bytes(&runtime, bytes[:])
    testing.expect_value(t, string(bytes[:count]),
        "\e[200~a\e[200~b\e[201~c\e[201~")
    testing.expect_value(t, runtime.paste_admission_count, u64(1))
}

// Verify paste capacity accounts only for wrappers that will be encoded.
@(test)
input_test_terminal_paste_rejection_is_atomic :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    storage: [INPUT_BYTE_QUEUE_CAPACITY]u8
    testing.expect(t, input_terminal_enqueue_paste(
        &runtime, string(storage[:INPUT_PASTE_MAX_BYTES]), true))
    testing.expect_value(t, runtime.byte_queue_count, INPUT_BYTE_QUEUE_CAPACITY)
    testing.expect_value(t, runtime.paste_admission_count, u64(1))

    testing.expect(t, input_runtime_pop_queued_bytes(
        &runtime, runtime.byte_queue_count))
    testing.expect(t, !input_terminal_enqueue_paste(
        &runtime, string(storage[:INPUT_PASTE_MAX_BYTES + 1]), true))
    testing.expect_value(t, runtime.byte_queue_count, 0)
    testing.expect_value(t, runtime.paste_rejection_count, u64(1))

    testing.expect(t, input_terminal_enqueue_paste(
        &runtime, string(storage[:]), false))
    testing.expect_value(t, runtime.byte_queue_count, INPUT_BYTE_QUEUE_CAPACITY)
    testing.expect_value(t, runtime.paste_admission_count, u64(2))
}

// Verify an owner transition discards an admitted paste as one stale byte range.
@(test)
input_test_terminal_paste_does_not_cross_owners :: proc(t: ^testing.T) {
    runtime: Input_Runtime
    first := Input_Owner{kind = .Terminal_Session, id = 1, generation = 2}
    second := Input_Owner{kind = .Terminal_Session, id = 1, generation = 3}
    testing.expect(t, input_runtime_set_owner(&runtime, first))
    testing.expect(t, input_terminal_enqueue_paste(&runtime, "payload", true))
    retained := runtime.byte_queue_count

    testing.expect(t, input_runtime_set_owner(&runtime, second))
    testing.expect_value(t, runtime.byte_queue_count, 0)
    testing.expect_value(t, runtime.stale_byte_discard_count, u64(retained))
}

// Verify pressed-or-repeat reports true when only the pressed bit is set.
@(test)
input_test_key_pressed_or_repeat_pressed_only :: proc(t: ^testing.T) {
    frame := Input_Frame{events = []Input_Event{{kind = .Press, key = .Enter}}}
    testing.expect(t, input_key_pressed_or_repeat(frame, .Enter))
    testing.expect(t, !input_key_pressed_or_repeat(frame, .Backspace))
}

// Verify pressed-or-repeat reports true when only the repeat bit is set.
@(test)
input_test_key_pressed_or_repeat_repeat_only :: proc(t: ^testing.T) {
    frame := Input_Frame{events = []Input_Event{{kind = .Repeat, key = .Left}}}
    testing.expect(t, input_key_pressed_or_repeat(frame, .Left))
    testing.expect(t, !input_key_pressed_or_repeat(frame, .Right))
}

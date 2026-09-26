package ui

import viewmodel "../model"

import input "../input"

import "core:testing"

// input_box_test_frame creates one ordered keyboard frame for pure widget tests.
input_box_test_frame :: proc(events: []input.Input_Event) -> Input_Frame {
    return {events = events}
}

// Verify content publication resets selection to the UTF-8 text end exactly once.
@(test)
input_box_content_revision_reconciles_to_end :: proc(t: ^testing.T) {
    state := viewmodel.Ui_Input_Box_State{cursor_byte = 1, anchor_byte = 1}
    testing.expect(t, input_box_reconcile_content(&state, "aé", 4))
    testing.expect_value(t, state.cursor_byte, len("aé"))
    testing.expect_value(t, state.anchor_byte, len("aé"))
    testing.expect(t, !input_box_reconcile_content(&state, "aé", 4))
}

// Verify navigation advances by UTF-8 codepoints and Shift preserves its anchor.
@(test)
input_box_keyboard_navigation_is_utf8_safe :: proc(t: ^testing.T) {
    text := "aéz"
    state := viewmodel.Ui_Input_Box_State{
        cursor_byte = len(text), anchor_byte = len(text)}
    events := [2]input.Input_Event{
        {kind = .Press, key = .Left},
        {kind = .Repeat, key = .Left, modifiers = {.Shift}},
    }
    _ = input_box_apply_keyboard(&state, text, input_box_test_frame(events[:]))
    testing.expect_value(t, state.anchor_byte, len("aé"))
    testing.expect_value(t, state.cursor_byte, len("a"))
}

// Verify select-all and copy report an ordered borrowed-text range without mutation.
@(test)
input_box_keyboard_select_all_and_copy :: proc(t: ^testing.T) {
    text := "/tmp/euclid.gif"
    state: viewmodel.Ui_Input_Box_State
    events := [2]input.Input_Event{
        {kind = .Press, key = .A, modifiers = {.Control}},
        {kind = .Press, key = .C, modifiers = {.Control}},
    }
    update := input_box_apply_keyboard(
        &state, text, input_box_test_frame(events[:]))
    testing.expect(t, update.copy_requested)
    testing.expect_value(t, update.copy_start, 0)
    testing.expect_value(t, update.copy_end, len(text))
}

// Verify text and mutation events cannot alter read-only input-box state.
@(test)
input_box_keyboard_rejects_mutation :: proc(t: ^testing.T) {
    state := viewmodel.Ui_Input_Box_State{cursor_byte = 2, anchor_byte = 1}
    events := [3]input.Input_Event{
        {kind = .Text, codepoint = 'x'},
        {kind = .Press, key = .Backspace},
        {kind = .Press, key = .Delete},
    }
    _ = input_box_apply_keyboard(
        &state, "path", input_box_test_frame(events[:]))
    testing.expect_value(t, state.cursor_byte, 2)
    testing.expect_value(t, state.anchor_byte, 1)
}

// Verify an ordinary arrow collapses a selection before further navigation.
@(test)
input_box_keyboard_collapses_selection :: proc(t: ^testing.T) {
    state := viewmodel.Ui_Input_Box_State{cursor_byte = 1, anchor_byte = 4}
    left := [1]input.Input_Event{{kind = .Press, key = .Left}}
    _ = input_box_apply_keyboard(&state, "path", input_box_test_frame(left[:]))
    testing.expect_value(t, state.cursor_byte, 1)
    testing.expect_value(t, state.anchor_byte, 1)
}

// Verify pointer capture creates an ordered selection across a drag.
@(test)
input_box_pointer_drag_selects_borrowed_text :: proc(t: ^testing.T) {
    state := viewmodel.Ui_Input_Box_State{content_revision = 1}
    owner: viewmodel.Ui_Press_Owner_State
    params := Input_Box_Params{id = 8, rect = {10, 10, 80, 24}, text = "abcdef",
        content_revision = 1, state = &state, pointer_routed = true,
        column_advance = 10, frame = {mouse_position = {24, 15},
            mouse_pressed = {.Left}, mouse_down = {.Left}}}
    _ = input_box_prepare(params, &owner)
    testing.expect(t, owner.active && state.dragging)
    testing.expect_value(t, state.anchor_byte, 1)
    params.frame = {mouse_position = {44, 15}, mouse_released = {.Left}}
    _ = input_box_prepare(params, &owner)
    testing.expect_value(t, state.cursor_byte, 3)
    testing.expect(t, !owner.active && !state.dragging)
}

// Verify new content aligns to the end and Home reveals the beginning.
@(test)
input_box_scroll_tracks_caret_navigation :: proc(t: ^testing.T) {
    state: viewmodel.Ui_Input_Box_State
    owner: viewmodel.Ui_Press_Owner_State
    params := Input_Box_Params{id = 9, rect = {0, 0, 28, 24}, text = "abcdef",
        content_revision = 1, state = &state, column_advance = 10}
    _ = input_box_prepare(params, &owner)
    testing.expect_value(t, state.scroll_x, f32(41))
    home := [1]input.Input_Event{{kind = .Press, key = .Home}}
    params.focused = true
    params.frame = input_box_test_frame(home[:])
    _ = input_box_prepare(params, &owner)
    testing.expect_value(t, state.scroll_x, f32(0))
}
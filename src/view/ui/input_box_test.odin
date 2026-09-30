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

// Verify editable input replaces UTF-8 selections and applies bounded deletion.
@(test)
input_box_edit_keyboard_preserves_utf8_boundaries :: proc(t: ^testing.T) {
    buffer: [8]u8
    copy(buffer[:], "aéz")
    text_length := len("aéz")
    state := viewmodel.Ui_Input_Box_State{cursor_byte = len("aé"), anchor_byte = 1}
    events := [2]input.Input_Event{
        {kind = .Text, codepoint = 'β'},
        {kind = .Press, key = .Backspace},
    }
    update := input_box_apply_edit_keyboard(&state,
        {buffer[:], &text_length}, input_box_test_frame(events[:]))
    testing.expect(t, update.changed)
    testing.expect_value(t, string(buffer[:text_length]), "az")
    testing.expect_value(t, state.cursor_byte, 1)
}

// Verify editable input cuts selections, bounds paste, and reports submission.
@(test)
input_box_edit_keyboard_reports_cut_paste_and_submit :: proc(t: ^testing.T) {
    buffer: [6]u8
    copy(buffer[:], "abcd")
    text_length := 4
    state := viewmodel.Ui_Input_Box_State{cursor_byte = 3, anchor_byte = 1}
    events := [3]input.Input_Event{
        {kind = .Press, key = .X, modifiers = {.Control}},
        {kind = .Press, key = .V, modifiers = {.Control}},
        {kind = .Press, key = .Enter},
    }
    update := input_box_apply_edit_keyboard(&state,
        {buffer[:], &text_length}, input_box_test_frame(events[:]), "ééé")
    testing.expect(t, update.copy_requested && update.changed)
    testing.expect_value(t, update.copy_start, 1)
    testing.expect_value(t, update.copy_end, 3)
    testing.expect_value(t, string(buffer[:text_length]), "aééd")
    testing.expect(t, update.submit_requested)
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
    params := Input_Box_Params{rect = {10, 10, 80, 24},
        descriptor = {id = {domain = .Library_Control, local_id = 8},
            text = "abcdef", mode = .Editable, content_revision = 1},
        state = &state, pointer_routed = true,
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
    params := Input_Box_Params{rect = {0, 0, 28, 24},
        descriptor = {id = {domain = .Library_Control, local_id = 9},
            text = "abcdef", mode = .Read_Only, content_revision = 1},
        state = &state, column_advance = 10}
    _ = input_box_prepare(params, &owner)
    testing.expect_value(t, state.scroll_x, f32(41))
    home := [1]input.Input_Event{{kind = .Press, key = .Home}}
    params.focused = true
    params.frame = input_box_test_frame(home[:])
    _ = input_box_prepare(params, &owner)
    testing.expect_value(t, state.scroll_x, f32(0))
}

// Verify prepared descriptors expose UTF-8 byte boundaries and codepoint columns.
@(test)
input_box_descriptor_projects_utf8_selection_geometry :: proc(t: ^testing.T) {
    state := viewmodel.Ui_Input_Box_State{
        cursor_byte = len("aé"), anchor_byte = len("a"), content_revision = 3}
    owner: viewmodel.Ui_Press_Owner_State
    result := input_box_prepare({
        rect = {10, 20, 80, 24}, clip_rect = {5, 6, 100, 90},
        descriptor = {id = {domain = .Library_Control, local_id = 10},
            text = "aéz", mode = .Read_Only, cursor_byte = len("aé"),
            anchor_byte = len("a"), content_revision = 3},
        state = &state, column_advance = 10,
    }, &owner)
    testing.expect_value(t, result.descriptor.cursor_byte, len("aé"))
    testing.expect_value(t, result.descriptor.anchor_byte, len("a"))
    testing.expect_value(t, result.text_geometry.cursor_column, 2)
    testing.expect_value(t, result.text_geometry.anchor_column, 1)
    testing.expect_value(t, result.text_geometry.control.clip_bounds,
        viewmodel.Rectangle{5, 6, 100, 90})
    testing.expect_value(t, result.text_geometry.selection.width, f32(10))
}

// Verify copied native selection and replacement commands use ordinary edit storage.
@(test)
input_box_semantic_text_actions_preserve_utf8_boundaries :: proc(t: ^testing.T) {
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    id := viewmodel.Ui_Node_Id{domain = .Library_Control, local_id = 11}
    buffer: [16]u8
    copy(buffer[:], "aβc")
    length := len("aβc")
    state := viewmodel.Ui_Input_Box_State{content_revision = 1,
        cursor_byte = length, anchor_byte = length}
    semantic^.commands[0] = {target = id, kind = .Set_Text_Selection,
        selection_anchor = 1, selection_focus = 2}
    semantic^.commands[1] = {target = id, kind = .Replace_Selected_Text,
        payload_length = 1}
    semantic^.commands[1].payload[0] = 'x'
    semantic^.command_count = 2
    owner: viewmodel.Ui_Press_Owner_State
    result := input_box_prepare({rect = {0, 0, 100, 24},
        descriptor = {id = id, text = string(buffer[:length]), mode = .Editable,
            content_revision = 1}, state = &state, semantic_focus = semantic,
        edit_target = {buffer[:], &length}, column_advance = 10}, &owner)
    testing.expect(t, result.changed)
    testing.expect_value(t, string(buffer[:length]), "axc")
    testing.expect_value(t, state.cursor_byte, 2)
    testing.expect_value(t, state.anchor_byte, 2)
}

// Verify native full-text replacement ignores the owner's current selection.
@(test)
input_box_semantic_full_text_action_replaces_all :: proc(t: ^testing.T) {
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    id := viewmodel.Ui_Node_Id{domain = .Library_Control, local_id = 11}
    buffer: [16]u8
    copy(buffer[:], "old")
    length := 3
    state := viewmodel.Ui_Input_Box_State{content_revision = 1,
        cursor_byte = 2, anchor_byte = 1}
    semantic^.commands[0] = {target = id, kind = .Replace_Text,
        payload_length = 3}
    copy(semantic^.commands[0].payload[:], "new")
    semantic^.command_count = 1
    owner: viewmodel.Ui_Press_Owner_State
    result := input_box_prepare({rect = {0, 0, 100, 24},
        descriptor = {id = id, text = string(buffer[:length]), mode = .Editable,
            content_revision = 1}, state = &state, semantic_focus = semantic,
        edit_target = {buffer[:], &length}, column_advance = 10}, &owner)
    testing.expect(t, result.changed)
    testing.expect_value(t, string(buffer[:length]), "new")
}

// Verify read-only descriptor policy wins even when mutable storage is supplied.
@(test)
input_box_descriptor_rejects_read_only_mutation :: proc(t: ^testing.T) {
    buffer: [8]u8
    copy(buffer[:], "path")
    length := 4
    state := viewmodel.Ui_Input_Box_State{
        cursor_byte = 4, anchor_byte = 4, content_revision = 1}
    owner: viewmodel.Ui_Press_Owner_State
    events := [1]input.Input_Event{{kind = .Text, codepoint = 'x'}}
    result := input_box_prepare({
        descriptor = {id = {domain = .Gif_Control, local_id = 11},
            text = "path", mode = .Read_Only, content_revision = 1},
        state = &state, focused = true, frame = input_box_test_frame(events[:]),
        edit_target = {buffer[:], &length},
    }, &owner)
    testing.expect(t, !result.changed)
    testing.expect_value(t, string(buffer[:length]), "path")
}
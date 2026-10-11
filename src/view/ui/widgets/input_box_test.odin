package uiwidgets

import input "../../input"
import testing "core:testing"
import viewmodel "../model"
import geometry "../../../core/geometry"
import uisemantics "../semantics"

// Verify reusable input boxes publish only their caller-supplied control relation.
@(test)
input_box_semantics_use_owner_control_relation :: proc(t: ^testing.T) {
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    owner: viewmodel.Ui_Press_Owner_State
    input_state: viewmodel.Ui_Input_Box_State
    target := viewmodel.Ui_Node_Id{domain = .Gif_Control, local_id = 8}
    params := Input_Box_Params{
        rect = {0, 0, 120, 24}, clip_rect = {0, 0, 120, 24},
        descriptor = {id = target, text = "saved.gif", mode = .Read_Only},
        semantic_focus = semantic, state = &input_state, column_advance = 8,
    }
    testing.expect(t, uisemantics.semantic_begin(semantic))
    _ = input_box_prepare(params, &owner)
    snapshot := uisemantics.semantic_staging_snapshot(semantic)
    index := uisemantics.semantic_node_index(snapshot, target)
    testing.expect(t, index >= 0)
    if index < 0 {
        return
    }
    testing.expect_value(t, snapshot^.nodes[index].controls, viewmodel.Ui_Node_Id{})
    params.controls = {domain = .Animation_Tree, local_id = 73}
    testing.expect(t, uisemantics.semantic_begin(semantic))
    _ = input_box_prepare(params, &owner)
    snapshot = uisemantics.semantic_staging_snapshot(semantic)
    index = uisemantics.semantic_node_index(snapshot, target)
    testing.expect(t, index >= 0)
    if index >= 0 {
        testing.expect_value(t, snapshot^.nodes[index].controls, params.controls)
    }
}

// input_box_test_frame creates one ordered keyboard frame for pure widget tests.
input_box_test_frame :: proc(events: []input.Input_Event) -> input.Input_Frame {
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
        geometry.Rectangle{5, 6, 100, 90})
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

// input_box_test_pointer_params borrows text and state for isolated gesture tests.
input_box_test_pointer_params :: proc(
    state: ^viewmodel.Ui_Input_Box_State,
    text: string, clicks: u8, x: f32) -> Input_Box_Params {
    return {
        rect = {0, 0, 120, 24},
        clip_rect = {0, 0, 120, 24},
        descriptor = {
            id = {domain = .Library_Control, local_id = 8},
            text = text,
            mode = .Editable,
            content_revision = 1,
        },
        state = state,
        pointer_routed = true,
        column_advance = 10,
        frame = {
            mouse_position = {x, 12},
            mouse_pressed = {.Left},
            mouse_down = {.Left},
            mouse_left_clicks = clicks,
        },
    }
}

// Verify double-click runs distinguish identifiers, Unicode, spaces, and punctuation.
@(test)
input_box_double_click_selects_utf8_runs :: proc(t: ^testing.T) {
    cases := [?]struct {text: string, offset, first, last: int}{
        {"foo_bar42 next", 4, 0, 9},
        {"42+17", 1, 0, 2},
        {"αβ_界9!", len("α"), 0, len("αβ_界9")},
        {"foo...bar", 4, 3, 6},
        {"a \t b", 2, 1, 4},
        {"a\u00a0\u2003b", 1, 1, len("a\u00a0\u2003")},
        {"one two", 3, 3, 4},
        {"one two", 4, 4, 7},
        {"one two", 99, 4, 7},
        {"one two", -1, 0, 3},
        {"", 0, 0, 0},
    }
    for item in cases {
        state: viewmodel.Ui_Input_Box_State
        input_box_select_run(&state, item.text, item.offset)
        testing.expect_value(t, state.anchor_byte, item.first)
        testing.expect_value(t, state.cursor_byte, item.last)
    }
}

// Verify double-click cell hits do not round the right half into the next run.
@(test)
input_box_double_click_hits_character_cells :: proc(t: ^testing.T) {
    cases := [?]struct {x: f32, first, last: int}{
        {3, 0, 3}, {33, 0, 3}, {34, 3, 4},
        {43, 3, 4}, {44, 4, 7}, {114, 4, 7},
    }
    for item in cases {
        state := viewmodel.Ui_Input_Box_State{content_revision = 1}
        owner: viewmodel.Ui_Press_Owner_State
        params := input_box_test_pointer_params(&state, "one two", 2, item.x)
        _ = input_box_prepare(params, &owner)
        testing.expect_value(t, state.anchor_byte, item.first)
        testing.expect_value(t, state.cursor_byte, item.last)
    }
}

// Verify scrolling maps a double click to the visible UTF-8 word without allocation.
@(test)
input_box_double_click_accounts_for_scroll :: proc(t: ^testing.T) {
    state := viewmodel.Ui_Input_Box_State{content_revision = 1, scroll_x = 40}
    owner: viewmodel.Ui_Press_Owner_State
    params := input_box_test_pointer_params(&state, "one αβ_界9 end", 2, 13)
    params.rect.width = 54
    result := input_box_prepare(params, &owner)
    testing.expect_value(t, result.descriptor.anchor_byte, len("one "))
    testing.expect_value(t, result.descriptor.cursor_byte, len("one αβ_界9"))
    testing.expect_value(t, result.text_geometry.anchor_column, 4)
    testing.expect_value(t, result.text_geometry.cursor_column, 9)
}

// Verify multi-click selections stay fixed across movement and focus-loss release.
@(test)
input_box_multi_click_preserves_selection_until_release :: proc(t: ^testing.T) {
    click_counts := [?]u8{2, 3, 4}
    for clicks in click_counts {
        state := viewmodel.Ui_Input_Box_State{content_revision = 1}
        owner: viewmodel.Ui_Press_Owner_State
        params := input_box_test_pointer_params(&state, "one two", clicks, 49)
        _ = input_box_prepare(params, &owner)
        first := 4 if clicks == 2 else 0
        testing.expect_value(t, state.anchor_byte, first)
        testing.expect_value(t, state.cursor_byte, 7)
        testing.expect(t, state.dragging && state.fixed_selection && owner.active)
        params.frame = {mouse_position = {14, 12}, mouse_down = {.Left}}
        _ = input_box_prepare(params, &owner)
        testing.expect_value(t, state.anchor_byte, first)
        testing.expect_value(t, state.cursor_byte, 7)
        params.frame = {mouse_position = {-10, 12}, mouse_released = {.Left},
            window_focus_changed = true, window_focused = false}
        _ = input_box_prepare(params, &owner)
        testing.expect_value(t, state.anchor_byte, first)
        testing.expect_value(t, state.cursor_byte, 7)
        testing.expect(t, !owner.active && !state.dragging && !state.fixed_selection)
    }
}

// Verify all-text gestures include hidden content in editable and read-only fields.
@(test)
input_box_triple_click_selects_complete_content :: proc(t: ^testing.T) {
    modes := [?]viewmodel.Ui_Editable_Text_Mode{.Editable, .Read_Only}
    texts := [?]string{"αβ hidden text", ""}
    for mode in modes {
        for text in texts {
            state := viewmodel.Ui_Input_Box_State{content_revision = 1, scroll_x = 20}
            owner: viewmodel.Ui_Press_Owner_State
            params := input_box_test_pointer_params(&state, text, 3, 14)
            params.descriptor.mode = mode
            params.rect.width = 28
            params.frame.mouse_down = {}
            params.frame.mouse_released = {.Left}
            result := input_box_prepare(params, &owner)
            testing.expect_value(t, result.descriptor.anchor_byte, 0)
            testing.expect_value(t, result.descriptor.cursor_byte, len(text))
            testing.expect(t, !result.changed && !owner.active)
        }
    }
}

// Verify absent/single-click metadata preserves caret rounding and character dragging.
@(test)
input_box_single_click_metadata_preserves_dragging :: proc(t: ^testing.T) {
    click_counts := [?]u8{0, 1}
    for clicks in click_counts {
        state := viewmodel.Ui_Input_Box_State{content_revision = 1}
        owner: viewmodel.Ui_Press_Owner_State
        params := input_box_test_pointer_params(&state, "one two", clicks, 33)
        _ = input_box_prepare(params, &owner)
        testing.expect_value(t, state.anchor_byte, 3)
        testing.expect_value(t, state.cursor_byte, 3)
        testing.expect(t, !state.fixed_selection)
        params.frame = {mouse_position = {64, 12}, mouse_released = {.Left}}
        _ = input_box_prepare(params, &owner)
        testing.expect_value(t, state.anchor_byte, 3)
        testing.expect_value(t, state.cursor_byte, 6)
    }
}

// Verify multi-click presses cannot bypass routing, bounds, or another press owner.
@(test)
input_box_multi_click_respects_pointer_admission :: proc(t: ^testing.T) {
    for denied in 0..<3 {
        state := viewmodel.Ui_Input_Box_State{content_revision = 1,
            anchor_byte = 1, cursor_byte = 1}
        owner: viewmodel.Ui_Press_Owner_State
        params := input_box_test_pointer_params(&state, "one two", 3, 14)
        if denied == 0 {
            params.pointer_routed = false
        } else if denied == 1 {
            params.frame.mouse_position.x = -10
        } else {
            owner = {active = true, kind = .Input_Box, id = 99}
        }
        _ = input_box_prepare(params, &owner)
        testing.expect_value(t, state.anchor_byte, 1)
        testing.expect_value(t, state.cursor_byte, 1)
        testing.expect(t, !state.dragging && !state.fixed_selection)
    }
}

// Verify content publication clears a captured multi-click gesture's interaction state.
@(test)
input_box_revision_clears_multi_click_state :: proc(t: ^testing.T) {
    state := viewmodel.Ui_Input_Box_State{content_revision = 1}
    owner: viewmodel.Ui_Press_Owner_State
    params := input_box_test_pointer_params(&state, "one two", 2, 14)
    _ = input_box_prepare(params, &owner)
    testing.expect(t, state.fixed_selection)
    testing.expect(t, input_box_reconcile_content(&state, "new", 2))
    testing.expect(t, !state.dragging && !state.fixed_selection)
    testing.expect_value(t, state.anchor_byte, 3)
    testing.expect_value(t, state.cursor_byte, 3)
}

// Verify editing and deletion consume the UTF-8 range selected by a double click.
@(test)
input_box_multi_click_selection_supports_edits :: proc(t: ^testing.T) {
    keys := [?]input.Input_Key{.Space, .Backspace, .Delete}
    for key in keys {
        buffer: [32]u8
        copy(buffer[:], "αβ end")
        length := len("αβ end")
        state := viewmodel.Ui_Input_Box_State{content_revision = 1}
        owner: viewmodel.Ui_Press_Owner_State
        params := input_box_test_pointer_params(&state, string(buffer[:length]), 2, 14)
        _ = input_box_prepare(params, &owner)
        events := [1]input.Input_Event{{kind = .Press, key = key}}
        expected := " end"
        if key == .Space {
            events[0] = {kind = .Text, codepoint = '界'}
            expected = "界 end"
        }
        update := input_box_apply_edit_keyboard(&state, {buffer[:], &length},
            input_box_test_frame(events[:]))
        testing.expect(t, update.changed)
        testing.expect_value(t, string(buffer[:length]), expected)
        testing.expect_value(t, state.anchor_byte, state.cursor_byte)
    }
}

// Verify read-only word selection permits copy/navigation but rejects text mutation.
@(test)
input_box_read_only_double_click_supports_copy_navigation :: proc(t: ^testing.T) {
    state := viewmodel.Ui_Input_Box_State{content_revision = 1}
    owner: viewmodel.Ui_Press_Owner_State
    params := input_box_test_pointer_params(&state, "αβ end", 2, 14)
    params.descriptor.mode = .Read_Only
    _ = input_box_prepare(params, &owner)
    events := [2]input.Input_Event{
        {kind = .Text, codepoint = 'x'},
        {kind = .Press, key = .C, modifiers = {.Control}}}
    update := input_box_apply_keyboard(&state, params.descriptor.text,
        input_box_test_frame(events[:]))
    testing.expect(t, update.copy_requested)
    testing.expect_value(t, update.copy_start, 0)
    testing.expect_value(t, update.copy_end, len("αβ"))
    input_box_move_cursor(&state, params.descriptor.text, .Right, false)
    testing.expect_value(t, state.anchor_byte, len("αβ"))
    testing.expect_value(t, state.cursor_byte, len("αβ"))
}

// Verify multi-click ranges reach the existing accessibility selection publication.
@(test)
input_box_multi_click_publishes_semantic_selection :: proc(t: ^testing.T) {
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    state := viewmodel.Ui_Input_Box_State{content_revision = 1}
    owner: viewmodel.Ui_Press_Owner_State
    params := input_box_test_pointer_params(&state, "αβ end", 2, 14)
    params.semantic_focus = semantic
    testing.expect(t, uisemantics.semantic_begin(semantic))
    result := input_box_prepare(params, &owner)
    testing.expect_value(t, result.text_geometry.selection.width, f32(20))
    testing.expect_value(t, result.text_geometry.anchor_column, 0)
    testing.expect_value(t, result.text_geometry.cursor_column, 2)
    snapshot := uisemantics.semantic_staging_snapshot(semantic)
    index := uisemantics.semantic_node_index(snapshot, params.descriptor.id)
    testing.expect(t, index >= 0)
    if index >= 0 {
        testing.expect_value(t, snapshot^.nodes[index].text_anchor_byte, 0)
        testing.expect_value(t, snapshot^.nodes[index].text_cursor_byte, len("αβ"))
    }
}

// Verify cutting and pasting consume a triple-click selection through bounded storage.
@(test)
input_box_triple_click_supports_cut_paste :: proc(t: ^testing.T) {
    buffer: [32]u8
    copy(buffer[:], "αβ end")
    length := len("αβ end")
    state := viewmodel.Ui_Input_Box_State{content_revision = 1}
    owner: viewmodel.Ui_Press_Owner_State
    params := input_box_test_pointer_params(&state, string(buffer[:length]), 3, 14)
    _ = input_box_prepare(params, &owner)
    events := [2]input.Input_Event{
        {kind = .Press, key = .X, modifiers = {.Control}},
        {kind = .Press, key = .V, modifiers = {.Control}}}
    update := input_box_apply_edit_keyboard(&state, {buffer[:], &length},
        input_box_test_frame(events[:]), "replacement")
    testing.expect(t, update.changed && update.copy_requested)
    testing.expect_value(t, string(update.copied_bytes[:update.copied_length]), "αβ end")
    testing.expect_value(t, string(buffer[:length]), "replacement")
}
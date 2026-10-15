package uiwidgets

import input "../../input"
import testing "core:testing"
import viewmodel "../model"

// Verify completion reuses exact native TeX meanings and preserves preceding bytes.
@(test)
unicode_completion_resolves_exact_symbols :: proc(t: ^testing.T) {
    cases := [?][2]string{
        {"\\alpha", "α"}, {"\\Gamma", "Γ"}, {"\\epsilon", "ϵ"},
        {"\\varepsilon", "ε"}, {"\\times", "×"}, {"\\leq", "≤"},
        {"\\infty", "∞"}, {"\\sum", "∑"}, {"\\int", "∫"},
        {"\\rightarrow", "→"}, {"one α\\beta", "β"},
        {"\\\\\\alpha", "α"},
    }
    for &item in cases {
        candidate := unicode_completion_suffix(item[0])
        testing.expect_value(t, candidate.text, item[1])
        testing.expect(t, candidate.start >= 0 && candidate.start < len(item[0]))
        testing.expect_value(t, item[0][candidate.start], u8('\\'))
    }
    rejected := [?]string{"", "\\", "\\alph", "\\Alpha", "\\alpha ",
        "/alpha", "\\unknown", "\\\\alpha", "\\\\\\\\alpha", "\\sin", "\\lim",
        "\\hat", "\\frac", "\\mathbb", "\\{", "\\vert", "α"}
    for text in rejected {
        testing.expect_value(t, unicode_completion_suffix(text).text, "")
    }
}

// unicode_test_params borrows bounded editable storage with completion opted in.
unicode_test_params :: proc(
    state: ^viewmodel.Ui_Input_Box_State, bytes: []u8,
    length: ^int) -> Input_Box_Params {
    return {rect = {0, 0, 100, 30}, clip_rect = {0, 0, 100, 30},
        descriptor = {text = string(bytes[:length^]), mode = .Editable},
        state = state, focused = true, column_advance = 8,
        edit_target = {bytes, length}, edit_policy = {unicode_completion = true}}
}

// Verify replacement is a normal edit and consumes Right before spelling correction.
@(test)
unicode_completion_replaces_suffix_before_spelling :: proc(t: ^testing.T) {
    bytes: [32]u8
    text := "é \\alpha"
    copy(bytes[:], text)
    length := len(text)
    state := viewmodel.Ui_Input_Box_State{cursor_byte = length, anchor_byte = length}
    events := [2]input.Input_Event{
        {kind = .Press, key = .Right}, {kind = .Press, key = .Right}}
    result := input_box_apply_edit_keyboard(&state, {bytes[:], &length},
        {events = events[:]}, "", {true, "spelling"})
    testing.expect(t, result.changed && !result.suggestion_accepted)
    testing.expect(t, !result.submit_requested)
    testing.expect_value(t, string(bytes[:length]), "é α")
    testing.expect_value(t, state.cursor_byte, len("é α"))
    testing.expect_value(t, state.anchor_byte, state.cursor_byte)
}

// Verify completion uses event-time text and never applies a stale spelling proposal.
@(test)
unicode_completion_preserves_event_order :: proc(t: ^testing.T) {
    cases := [?]struct {
        text: string,
        events: [2]input.Input_Event,
        expected: string,
    }{
        {"\\alph", {{kind = .Text, codepoint = 'a'},
            {kind = .Press, key = .Right}}, "α"},
        {"\\alph", {{kind = .Press, key = .Right}, {kind = .Text, codepoint = 'a'}},
            "\\alpha"},
        {"\\alpha", {{kind = .Press, key = .Right},
            {kind = .Text, codepoint = 'x'}}, "αx"},
        {"\\alpha", {{kind = .Press, key = .Escape}, {kind = .Press, key = .Right}},
            "spelling"},
        {"\\alpha", {{kind = .Text, codepoint = 'x'}, {kind = .Press, key = .Right}},
            "\\alphax"},
    }
    for &item in cases {
        bytes: [32]u8
        copy(bytes[:], item.text)
        length := len(item.text)
        state := viewmodel.Ui_Input_Box_State{cursor_byte = length, anchor_byte = length}
        suggestion := "spelling" if item.events[0].key == .Escape else ""
        result := input_box_apply_edit_keyboard(&state, {bytes[:], &length},
            {events = item.events[:]}, "", {true, suggestion})
        testing.expect_value(t, string(bytes[:length]), item.expected)
        testing.expect(t, result.changed)
    }
}

// Verify dismissal survives unchanged caret/focus state and resets only after edits.
@(test)
unicode_completion_dismissal_tracks_text_changes :: proc(t: ^testing.T) {
    bytes: [16]u8
    copy(bytes[:], "\\alpha")
    length := len("\\alpha")
    state := viewmodel.Ui_Input_Box_State{cursor_byte = length, anchor_byte = length}
    escape := [1]input.Input_Event{{kind = .Press, key = .Escape}}
    result := input_box_apply_edit_keyboard(&state, {bytes[:], &length},
        {events = escape[:]}, "", {unicode_completion = true})
    testing.expect(t, !result.changed && state.unicode_dismissed)
    testing.expect_value(t, string(bytes[:length]), "\\alpha")
    testing.expect_value(t, input_box_unicode_candidate(&state, "\\alpha").text, "")
    testing.expect(t, !input_box_reconcile_content(&state, "\\alpha", 0))
    testing.expect(t, state.unicode_dismissed)
    events := [2]input.Input_Event{
        {kind = .Text, codepoint = 'x'}, {kind = .Press, key = .Backspace}}
    _ = input_box_apply_edit_keyboard(&state, {bytes[:], &length},
        {events = events[:]}, "", {unicode_completion = true})
    testing.expect_value(t, input_box_unicode_candidate(
        &state, string(bytes[:length])).text, "α")
    state.unicode_dismissed = true
    testing.expect(t, input_box_reconcile_content(&state, "\\alpha", 1))
    testing.expect(t, !state.unicode_dismissed)
}

// Verify hint eligibility respects editing, focus, selection, and fully visible bounds.
@(test)
unicode_completion_hint_and_scroll_are_bounded :: proc(t: ^testing.T) {
    bytes: [32]u8
    copy(bytes[:], "long query \\alpha")
    length := len("long query \\alpha")
    state := viewmodel.Ui_Input_Box_State{cursor_byte = length, anchor_byte = length}
    params := unicode_test_params(&state, bytes[:], &length)
    right := [1]input.Input_Event{{kind = .Press, key = .Right}}
    owner: viewmodel.Ui_Press_Owner_State
    result := input_box_prepare(params, &owner)
    testing.expect_value(t, result.unicode_completion.text, "α")
    testing.expect(t, state.scroll_x > 0)
    testing.expect(t, result.unicode_hint.x + result.unicode_hint.width <
        params.rect.x + params.rect.width)
    testing.expect(t, !result.changed)
    for index in 0..<6 {
        disabled := params
        disabled.frame.events = right[:]
        switch index {
        case 0: disabled.focused = false
        case 1: disabled.descriptor.mode = .Read_Only
        case 2: disabled.edit_policy.unicode_completion = false
        case 3: disabled.rect.width = 30
        case 4: disabled.clip_rect.width = 50
        case 5: state.anchor_byte = 0
        }
        result = input_box_prepare(disabled, &owner)
        expected := "α" if index == 5 else ""
        testing.expect_value(t, result.unicode_completion.text, expected)
        testing.expect(t, !result.changed)
        testing.expect_value(t, string(bytes[:length]), "long query \\alpha")
    }
}

// Verify modifiers, repeat, selection, mid-field navigation, and other keys stay literal.
@(test)
unicode_completion_preserves_ordinary_keys :: proc(t: ^testing.T) {
    events := [?]input.Input_Event{
        {kind = .Repeat, key = .Right},
        {kind = .Press, key = .Right, modifiers = {.Shift}},
        {kind = .Press, key = .Right, modifiers = {.Control}},
        {kind = .Press, key = .Right, modifiers = {.Alt}},
        {kind = .Press, key = .Right, modifiers = {.Super}},
        {kind = .Press, key = .Tab}, {kind = .Press, key = .Enter},
        {kind = .Press, key = .Space},
    }
    for event in events {
        bytes: [8]u8
        copy(bytes[:], "\\alpha")
        length := len("\\alpha")
        state := viewmodel.Ui_Input_Box_State{cursor_byte = length, anchor_byte = length}
        result := input_box_apply_edit_keyboard(&state, {bytes[:], &length},
            {events = []input.Input_Event{event}}, "", {unicode_completion = true})
        testing.expect(t, !result.changed)
        testing.expect_value(t, string(bytes[:length]), "\\alpha")
    }
    state := viewmodel.Ui_Input_Box_State{cursor_byte = 3, anchor_byte = 3}
    testing.expect_value(t, input_box_unicode_candidate(&state, "\\alpha").text, "")
    state.cursor_byte = 6
    testing.expect_value(t, input_box_unicode_candidate(&state, "\\alpha").text, "")
}

// Verify exact-capacity edits are complete and rejected growth never deletes a command.
@(test)
unicode_completion_replacement_is_atomic :: proc(t: ^testing.T) {
    bytes: [6]u8
    copy(bytes[:], "\\alpha")
    length := len("\\alpha")
    state := viewmodel.Ui_Input_Box_State{cursor_byte = length, anchor_byte = length}
    result: Input_Box_Update
    input_box_accept_completion(&state, {bytes[:], &length},
        {0, "α"}, &result)
    testing.expect_value(t, string(bytes[:length]), "α")
    testing.expect(t, result.changed)
    copy(bytes[:], "\\alpha")
    length = len("\\alpha")
    state = {cursor_byte = length, anchor_byte = length}
    result = {}
    input_box_accept_completion(&state, {bytes[:], &length},
        {len("\\alpha"), "α"}, &result)
    testing.expect_value(t, string(bytes[:length]), "\\alpha")
    testing.expect_value(t, state.anchor_byte, length)
    testing.expect(t, !result.changed)
}

// Verify earlier edits invalidate a borrowed correction even when no Unicode match remains.
@(test)
unicode_completion_rejects_stale_spelling_after_edit :: proc(t: ^testing.T) {
    bytes: [32]u8
    copy(bytes[:], "\\alpha")
    length := len("\\alpha")
    state := viewmodel.Ui_Input_Box_State{cursor_byte = length, anchor_byte = length}
    events := [2]input.Input_Event{
        {kind = .Text, codepoint = 'x'}, {kind = .Press, key = .Right}}
    result := input_box_apply_edit_keyboard(&state, {bytes[:], &length},
        {events = events[:]}, "", {true, "spelling"})
    testing.expect_value(t, string(bytes[:length]), "\\alphax")
    testing.expect(t, result.changed && !result.suggestion_accepted)
}

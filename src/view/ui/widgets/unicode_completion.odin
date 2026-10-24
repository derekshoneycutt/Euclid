package uiwidgets

import tex "../../../dynview/parse"
import utf8 "core:unicode/utf8"
import geometry "../../../core/geometry"
import input "../../input"
import viewmodel "../model"

// Unicode_Completion borrows one exact trailing command's atomic replacement.
Unicode_Completion :: struct {
    start: int,
    text: string,
}

// Input_Box_Edit_Policy opts callers into native completion and end-caret correction.
Input_Box_Edit_Policy :: struct {
    unicode_completion: bool,
    end_suggestion: string,
}

// unicode_completion_suffix resolves alphabetic, unescaped, single-symbol TeX names.
unicode_completion_suffix :: proc(text: string) -> Unicode_Completion {
    first := len(text)
    for first > 0 && ((text[first - 1] >= 'a' && text[first - 1] <= 'z') ||
        (text[first - 1] >= 'A' && text[first - 1] <= 'Z')) {
        first -= 1
    }
    if first == len(text) || first == 0 || text[first - 1] != '\\' {
        return {}
    }
    slash := first - 1
    for slash > 0 && text[slash - 1] == '\\' {
        slash -= 1
    }
    if (first - slash) % 2 == 0 {
        return {}
    }
    command := text[first - 1:]
    replacement := ""
    if symbol, ok := tex.tex_math_registry_fixed_symbol(command); ok {
        replacement = symbol.text
    } else if operator, operator_ok := tex.tex_math_registry_large_operator(command);
        operator_ok {
        replacement = operator.text
    }
    value, count := utf8.decode_rune_in_string(replacement)
    if value < 128 || value == utf8.RUNE_ERROR || count != len(replacement) {
        return {}
    }
    return {first - 1, replacement}
}

// input_box_unicode_candidate excludes selection, navigation, and dismissed input.
input_box_unicode_candidate :: proc(
    state: ^viewmodel.Ui_Input_Box_State, text: string) -> Unicode_Completion {
    if state == nil || state^.unicode_dismissed ||
        state^.cursor_byte != len(text) || state^.anchor_byte != len(text) {
        return {}
    }
    return unicode_completion_suffix(text)
}

// input_box_unicode_enabled admits hints only when the clipped field can show them.
input_box_unicode_enabled :: proc(params: Input_Box_Params) -> bool {
    if !params.edit_policy.unicode_completion || !params.focused ||
        params.descriptor.mode != .Editable || params.edit_target.length == nil ||
        params.column_advance <= 0 {
        return false
    }
    return params.rect.width >= params.column_advance * 7 &&
        geometry.rectangle_contains(params.clip_rect, {params.rect.x, params.rect.y}) &&
        geometry.rectangle_contains(params.clip_rect, {
            params.rect.x + params.rect.width, params.rect.y + params.rect.height})
}

// input_box_apply_completion_event consumes completion before ordinary key editing.
input_box_apply_completion_event :: proc(
    state: ^viewmodel.Ui_Input_Box_State, target: Input_Box_Edit_Target,
    event: input.Input_Event, policy: Input_Box_Edit_Policy,
    result: ^Input_Box_Update) -> bool {
    if (event.kind != .Press && event.kind != .Repeat) || event.modifiers != {} {
        return false
    }
    text := string(target.bytes[:target.length^])
    candidate: Unicode_Completion
    if policy.unicode_completion {
        candidate = input_box_unicode_candidate(state, text)
    }
    if len(candidate.text) > 0 && event.key == .Escape {
        state^.unicode_dismissed = true
        return true
    }
    if event.key != .Right || state^.cursor_byte != len(text) ||
        state^.anchor_byte != len(text) {
        return false
    }
    if len(candidate.text) > 0 {
        if event.kind == .Press {
            input_box_accept_completion(state, target, candidate, result)
        }
        return true
    }
    return input_box_accept_end_suggestion(state, target, policy, result)
}

// input_box_accept_completion checks complete capacity before replacing the suffix.
input_box_accept_completion :: proc(
    state: ^viewmodel.Ui_Input_Box_State, target: Input_Box_Edit_Target,
    candidate: Unicode_Completion, result: ^Input_Box_Update) {
    text_length := clamp(target.length^, 0, len(target.bytes))
    result^.changed = input_box_replace_range(
        state, target, {first = candidate.start, last = text_length},
        candidate.text, result) || result^.changed
}

// input_box_accept_end_suggestion rejects stale frame-borrowed spelling corrections.
input_box_accept_end_suggestion :: proc(
    state: ^viewmodel.Ui_Input_Box_State, target: Input_Box_Edit_Target,
    policy: Input_Box_Edit_Policy, result: ^Input_Box_Update) -> bool {
    if result^.changed || len(policy.end_suggestion) == 0 {
        return false
    }
    result^.changed = input_box_replace_range(
        state, target, {first = 0, last = target.length^}, policy.end_suggestion,
        result) || result^.changed
    result^.suggestion_accepted = !result^.edit_rejected
    return true
}

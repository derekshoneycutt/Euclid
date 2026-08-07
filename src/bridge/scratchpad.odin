package bridge

import "../julialib"
import "../core"

import "core:strings"

SCRATCHPAD_PARSE_ERROR :: i32(0)
SCRATCHPAD_PARSE_INCOMPLETE :: i32(1)
SCRATCHPAD_PARSE_COMPLETE :: i32(2)

//   Classify scratchpad text as parse-error/incomplete/complete.
//
// Returns:
//   - SCRATCHPAD_PARSE_ERROR when input has syntax errors.
//   - SCRATCHPAD_PARSE_INCOMPLETE when input is a valid prefix.
//   - SCRATCHPAD_PARSE_COMPLETE when input is complete.
scratchpad_classify_input :: proc(
    state: ^core.Euclid_General_State, text: string) -> i32 {

    if state == nil || state^.julia_interface == nil {
        return SCRATCHPAD_PARSE_ERROR
    }
    if state^.julia_interface^.scratchpad_classify_input == nil {
        return SCRATCHPAD_PARSE_ERROR
    }

    state_value := julialib.jl_box_voidpointer(state)
    text_c := strings.clone_to_cstring(text, context.temp_allocator)
    text_value := julialib.jl_cstr_to_string(text_c)
    result := julialib.jl_call2(state^.julia_interface^.scratchpad_classify_input,
        state_value, text_value)

    if julialib.jl_exception_occurred() != nil || result == nil {
        print_julia_exception("scratchpad_classify_input")
        return SCRATCHPAD_PARSE_ERROR
    }

    return i32(julialib.jl_unbox_int32(result))
}

//   Resolve one phase-1 scratchpad backslash token to a Unicode replacement.
//
// Returns:
//   - Replacement text when Julia REPL backslash completion resolves a single match.
//   - Empty string when no completion should be applied.
scratchpad_complete_backslash :: proc(
    state: ^core.Euclid_General_State, token: string) -> string {

    if state == nil || state^.julia_interface == nil {
        return ""
    }
    if state^.julia_interface^.scratchpad_complete_backslash == nil {
        return ""
    }

    state_value := julialib.jl_box_voidpointer(state)
    token_c := strings.clone_to_cstring(token, context.temp_allocator)
    token_value := julialib.jl_cstr_to_string(token_c)
    result := julialib.jl_call2(state^.julia_interface^.scratchpad_complete_backslash,
        state_value, token_value)

    if julialib.jl_exception_occurred() != nil || result == nil {
        print_julia_exception("scratchpad_complete_backslash")
        return ""
    }

    return strings.clone(string(julialib.jl_string_ptr(result)), context.temp_allocator)
}

//   Resolve one generic scratchpad completion request from full input text and caret byte offset.
//
// Returns:
//   - Encoded completion payload when Julia resolves an applicable replacement.
//   - Empty string when no completion should be applied.
scratchpad_complete_input :: proc(
    state: ^core.Euclid_General_State,
    text: string,
    caret_byte: int) -> string {

    if state == nil || state^.julia_interface == nil {
        return ""
    }
    if state^.julia_interface^.scratchpad_complete_input == nil {
        return ""
    }

    state_value := julialib.jl_box_voidpointer(state)
    text_c := strings.clone_to_cstring(text, context.temp_allocator)
    text_value := julialib.jl_cstr_to_string(text_c)
    caret_value := julialib.jl_box_int64(i64(caret_byte))
    args: [3]^julialib.jl_value_t = {state_value, text_value, caret_value}
    result := julialib.jl_call(state^.julia_interface^.scratchpad_complete_input, &args[0], 3)

    if julialib.jl_exception_occurred() != nil || result == nil {
        print_julia_exception("scratchpad_complete_input")
        return ""
    }

    return strings.clone(string(julialib.jl_string_ptr(result)), context.temp_allocator)
}

//   Queue a complete scratchpad input for one-per-frame execution.
//
// Returns:
//   - true when queued successfully.
//   - false when queueing fails.
scratchpad_queue_input :: proc(
    state: ^core.Euclid_General_State, text: string) -> bool {

    if state == nil || state^.julia_interface == nil {
        return false
    }
    if state^.julia_interface^.scratchpad_queue_input == nil {
        return false
    }

    state_value := julialib.jl_box_voidpointer(state)
    text_c := strings.clone_to_cstring(text, context.temp_allocator)
    text_value := julialib.jl_cstr_to_string(text_c)
    result := julialib.jl_call2(state^.julia_interface^.scratchpad_queue_input,
        state_value, text_value)

    if julialib.jl_exception_occurred() != nil || result == nil {
        print_julia_exception("scratchpad_queue_input")
        return false
    }

    return julialib.jl_unbox_bool(result) != 0
}

//   Save scratchpad history entries to a file path through Julia runtime.
//
// Returns:
//   - true when history is written successfully.
//   - false when bridge callback is unavailable or writing fails.
scratchpad_save_history_to_file :: proc(
    state: ^core.Euclid_General_State, path: string) -> bool {

    if state == nil || state^.julia_interface == nil {
        return false
    }
    if state^.julia_interface^.scratchpad_save_history_to_file == nil {
        return false
    }

    state_value := julialib.jl_box_voidpointer(state)
    path_c := strings.clone_to_cstring(path, context.temp_allocator)
    path_value := julialib.jl_cstr_to_string(path_c)
    result := julialib.jl_call2(state^.julia_interface^.scratchpad_save_history_to_file,
        state_value, path_value)

    if julialib.jl_exception_occurred() != nil || result == nil {
        print_julia_exception("scratchpad_save_history_to_file")
        return false
    }

    return julialib.jl_unbox_bool(result) != 0
}

//   Move scratchpad history cursor one step backward and return suggested input.
//
// Notes:
//   - The helper forwards the request through the registered Julia callback and
//     returns the resolved suggestion text for the UI to display.
scratchpad_history_previous :: proc(state: ^core.Euclid_General_State) -> string {
    if state == nil || state^.julia_interface == nil {
        return ""
    }
    if state^.julia_interface^.scratchpad_history_previous == nil {
        return ""
    }

    state_value := julialib.jl_box_voidpointer(state)
    result := julialib.jl_call1(
        state^.julia_interface^.scratchpad_history_previous, state_value)

    if julialib.jl_exception_occurred() != nil || result == nil {
        print_julia_exception("scratchpad_history_previous")
        return ""
    }

    return strings.clone(string(julialib.jl_string_ptr(result)), context.temp_allocator)
}

//   Move scratchpad history cursor one step forward and return suggested input.
//
// Notes:
//   - The helper forwards the request through the registered Julia callback and
//     returns the next suggested input text when the history cursor advances.
scratchpad_history_next :: proc(state: ^core.Euclid_General_State) -> string {
    if state == nil || state^.julia_interface == nil {
        return ""
    }
    if state^.julia_interface^.scratchpad_history_next == nil {
        return ""
    }

    state_value := julialib.jl_box_voidpointer(state)
    result := julialib.jl_call1(state^.julia_interface^.scratchpad_history_next, state_value)

    if julialib.jl_exception_occurred() != nil || result == nil {
        print_julia_exception("scratchpad_history_next")
        return ""
    }

    return strings.clone(string(julialib.jl_string_ptr(result)), context.temp_allocator)
}

//   Reset scratchpad history cursor to the position after the most recent entry.
//
// Notes:
//   - The helper forwards the reset request to Julia and reports whether the
//     callback completed successfully.
scratchpad_history_reset_cursor :: proc(state: ^core.Euclid_General_State) -> bool {
    if state == nil || state^.julia_interface == nil {
        return false
    }
    if state^.julia_interface^.scratchpad_history_reset_cursor == nil {
        return false
    }

    state_value := julialib.jl_box_voidpointer(state)
    result := julialib.jl_call1(
        state^.julia_interface^.scratchpad_history_reset_cursor, state_value)

    if julialib.jl_exception_occurred() != nil || result == nil {
        print_julia_exception("scratchpad_history_reset_cursor")
        return false
    }

    return julialib.jl_unbox_bool(result) != 0
}
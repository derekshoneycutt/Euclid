package bridge

import "../julialib"
import "../core"

import "core:strings"

SCRATCHPAD_PARSE_ERROR :: i32(0)
SCRATCHPAD_PARSE_INCOMPLETE :: i32(1)
SCRATCHPAD_PARSE_COMPLETE :: i32(2)

//   Submit one copied Scratchpad operation without blocking the display thread.
try_submit_scratchpad_async :: proc(
    state: ^core.Euclid_General_State, kind: Scratchpad_Async_Kind,
    text: string = "", caret_byte: int = 0,
    input_generation: u64 = 0) -> (u64, bool) {

    if state == nil || state^.julia_runtime_service == nil {
        return 0, false
    }
    if len(text) > SCRATCHPAD_ASYNC_TEXT_CAPACITY {
        return 0, false
    }

    service := state^.julia_runtime_service
    slot_index := reserve_scratchpad_async_slot(service)
    if slot_index < 0 {
        return 0, false
    }

    slot := &service^.scratchpad_slots[slot_index]
    slot^ = Scratchpad_Async_Slot{
        state = .Pending,
        kind = kind,
        input_generation = input_generation,
        host_state = state,
        caret_byte = caret_byte,
        input_len = len(text),
    }
    copy(slot^.input[:], transmute([]u8)text)

    request_id, sent := try_submit_julia_request(
        service, .Scratchpad, scratchpad_async_task, rawptr(slot), i32(slot_index))
    if !sent {
        slot^.state = .Free
        return 0, false
    }
    slot^.request_id = request_id
    return request_id, true
}

//   Pop one completed Scratchpad result in worker completion order.
poll_scratchpad_async_result :: proc(
    state: ^core.Euclid_General_State) -> (^Scratchpad_Async_Slot, bool) {

    if state == nil || state^.julia_runtime_service == nil {
        return nil, false
    }
    service := state^.julia_runtime_service
    for {
        _, ok := try_receive_julia_event(service)
        if !ok {
            break
        }
    }
    if service^.completed_scratchpad_count <= 0 {
        return nil, false
    }

    slot_index := service^.completed_scratchpad_slots[service^.completed_scratchpad_head]
    service^.completed_scratchpad_head =
        (service^.completed_scratchpad_head + 1) % SCRATCHPAD_ASYNC_SLOT_COUNT
    service^.completed_scratchpad_count -= 1
    slot := &service^.scratchpad_slots[slot_index]
    assert(slot^.state == .Complete)
    return slot, true
}

//   Return one consumed Scratchpad result slot to bounded service storage.
release_scratchpad_async_result :: proc(slot: ^Scratchpad_Async_Slot) {
    if slot != nil {
        slot^.state = .Free
    }
}

//   Return the completed result text stored inline in one async slot.
scratchpad_async_result_text :: proc(slot: ^Scratchpad_Async_Slot) -> string {
    if slot == nil || slot^.result_len <= 0 {
        return ""
    }
    return string(slot^.result[:slot^.result_len])
}

//   Reserve one free display-owned slot for a copied request payload.
reserve_scratchpad_async_slot :: proc(service: ^Julia_Runtime_Service) -> int {
    for &slot, slot_index in service^.scratchpad_slots {
        if slot.state == .Free {
            return slot_index
        }
    }
    return -1
}

//   Execute one copied Scratchpad request on the Julia owner thread.
scratchpad_async_task :: proc(data: rawptr) -> bool {
    slot := cast(^Scratchpad_Async_Slot)data
    assert_julia_runtime_owner(slot^.host_state)
    context = slot^.host_state^.saved_context
    input := string(slot^.input[:slot^.input_len])
    switch slot^.kind {
    case .Submit:
        execute_scratchpad_submit(slot, input)
    case .Complete:
        result := scratchpad_complete_input_direct(slot^.host_state, input, slot^.caret_byte)
        store_scratchpad_async_result(slot, result)
    case .History_Previous:
        result := scratchpad_history_previous_direct(slot^.host_state)
        store_scratchpad_async_result(slot, result)
    case .History_Next:
        result := scratchpad_history_next_direct(slot^.host_state)
        store_scratchpad_async_result(slot, result)
    case .History_Reset:
        slot^.succeeded = scratchpad_history_reset_cursor_direct(slot^.host_state)
    case .Save_History:
        slot^.succeeded = scratchpad_save_history_to_file_direct(slot^.host_state, input)
    }
    slot^.state = .Complete
    return true
}

//   Classify and optionally queue one committed input snapshot.
execute_scratchpad_submit :: proc(slot: ^Scratchpad_Async_Slot, input: string) {
    slot^.parse_result = scratchpad_classify_input_direct(slot^.host_state, input)
    if slot^.parse_result == SCRATCHPAD_PARSE_INCOMPLETE {
        slot^.succeeded = scratchpad_history_reset_cursor_direct(slot^.host_state)
        return
    }
    if slot^.parse_result != SCRATCHPAD_PARSE_COMPLETE {
        return
    }
    slot^.succeeded = scratchpad_queue_input_direct(slot^.host_state, input)
    if slot^.succeeded {
        _ = scratchpad_history_reset_cursor_direct(slot^.host_state)
    }
}

//   Copy a worker result into fixed slot storage before worker temp reset.
store_scratchpad_async_result :: proc(slot: ^Scratchpad_Async_Slot, result: string) {
    slot^.result_len = min(len(result), len(slot^.result))
    copy(slot^.result[:slot^.result_len], transmute([]u8)result[:slot^.result_len])
}

//   Classify scratchpad text as parse-error/incomplete/complete.
//
// Returns:
//   - SCRATCHPAD_PARSE_ERROR when input has syntax errors.
//   - SCRATCHPAD_PARSE_INCOMPLETE when input is a valid prefix.
//   - SCRATCHPAD_PARSE_COMPLETE when input is complete.
scratchpad_classify_input_direct :: proc(
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
scratchpad_complete_backslash_direct :: proc(
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
scratchpad_complete_input_direct :: proc(
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
scratchpad_queue_input_direct :: proc(
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
scratchpad_save_history_to_file_direct :: proc(
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
scratchpad_history_previous_direct :: proc(state: ^core.Euclid_General_State) -> string {
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
scratchpad_history_next_direct :: proc(state: ^core.Euclid_General_State) -> string {
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
scratchpad_history_reset_cursor_direct :: proc(state: ^core.Euclid_General_State) -> bool {
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
package termemulator

import termgrid "../grid"
import termpalette "../palette"

import termmodel "../model"

// Maximum hexadecimal bytes reflected by one validated XTGETTCAP name.
TERMINAL_CAPABILITY_NAME_CAPACITY :: 8

// Allowlisted terminal capability represented by one semantic reply.
Terminal_Capability_Kind :: enum u8 {
    Unknown,
    Terminal_Name,
    Colors,
    Rgb,
    Truecolor,
}

// Immutable terminal state snapshot used to construct semantic query responses.
Query_Context :: struct {
    geometry: termmodel.Terminal_Query_Geometry,
    style: termgrid.Cell_Style,
    scroll_top: int,
    scroll_bottom: int,
    palette: ^termpalette.Terminal_Palette_State,
    producer: termmodel.Terminal_Producer,
    input_mode: termmodel.Terminal_Input_Mode,
    modify_other_keys_level: u8,
    kitty_keyboard_flags: u8,
}

// Bit flags encoding supported active SGR attributes in one semantic response.
TERMINAL_SGR_BOLD :: u32(1 << 0)
TERMINAL_SGR_ITALIC :: u32(1 << 1)
TERMINAL_SGR_UNDERLINE :: u32(1 << 2)

// Append one response after caller-side capacity preflight.
interpreter_append_preflighted_response :: proc(
    state: ^Terminal_Title_State, response: termmodel.Terminal_Response) {
    index := (state.response_start + state.response_count) % len(state.responses)
    state.responses[index] = response
    state.response_count += 1
}

// Prepare one producer-correlated DECRQSS response from an immutable query snapshot.
query_prepare_decrqss_response :: proc(
    query_context: Query_Context,
    selector: []u8) -> termmodel.Terminal_Response {
    response := termmodel.Terminal_Response{
        kind = .Decrqss_Unsupported,
        producer = query_context.producer,
    }
    if len(selector) == 1 && selector[0] == 'm' {
        style := query_context.style
        response.kind = .Decrqss_Sgr
        if style.bold { response.first |= TERMINAL_SGR_BOLD }
        if style.italic { response.first |= TERMINAL_SGR_ITALIC }
        if style.underline { response.first |= TERMINAL_SGR_UNDERLINE }
        response.second = u32(style.foreground)
        response.third = u32(style.background)
    } else if len(selector) == 2 && selector[0] == ' ' && selector[1] == 'q' {
        response.kind = .Decrqss_Cursor_Style
    } else if len(selector) == 1 && selector[0] == 'r' {
        response.kind = .Decrqss_Margins
        response.first = u32(query_context.scroll_top + 1)
        response.second = u32(query_context.scroll_bottom + 1)
    }
    return response
}

// Pack at most eight validated ASCII bytes into two response words.
terminal_capability_pack_name :: proc(
    bytes: []u8, first, second: ^u32) {
    for byte, index in bytes {
        if index < 4 {
            first^ |= u32(byte) << u32(index * 8)
        } else {
            second^ |= u32(byte) << u32((index - 4) * 8)
        }
    }
}

// Classify one valid hexadecimal XTGETTCAP name without retaining arbitrary text.
terminal_capability_classify :: proc(decoded: []u8) -> Terminal_Capability_Kind {
    if len(decoded) == 2 && decoded[0] == 'T' && decoded[1] == 'N' {
        return .Terminal_Name
    }
    if len(decoded) == 2 && decoded[0] == 'C' && decoded[1] == 'o' {
        return .Colors
    }
    if len(decoded) == 3 && decoded[0] == 'R' && decoded[1] == 'G' &&
        decoded[2] == 'B' { return .Rgb }
    if len(decoded) == 2 && decoded[0] == 'T' && decoded[1] == 'c' {
        return .Truecolor
    }
    return .Unknown
}

// Decode one bounded hexadecimal XTGETTCAP name and prepare its semantic reply.
terminal_capability_prepare_response :: proc(
    encoded: []u8,
    producer: termmodel.Terminal_Producer) -> (termmodel.Terminal_Response, bool) {
    if len(encoded) == 0 || len(encoded) > TERMINAL_CAPABILITY_NAME_CAPACITY ||
        len(encoded) % 2 != 0 { return {}, false }
    decoded: [TERMINAL_CAPABILITY_NAME_CAPACITY / 2]u8
    decoded_count := len(encoded) / 2
    for index in 0..<decoded_count {
        high, high_valid := termpalette.terminal_color_hex_digit(encoded[index * 2])
        low, low_valid := termpalette.terminal_color_hex_digit(
            encoded[index * 2 + 1])
        if !high_valid || !low_valid { return {}, false }
        decoded[index] = u8(high << 4 | low)
    }
    response := termmodel.Terminal_Response{
        kind = .Xtgetcap,
        first = u32(terminal_capability_classify(decoded[:decoded_count])),
        producer = producer,
    }
    terminal_capability_pack_name(encoded, &response.second, &response.third)
    return response, true
}

// Prepare every semicolon-separated XTGETTCAP reply from one query snapshot.
query_prepare_xtgetcap_responses :: proc(
    query_context: Query_Context, candidate: []u8,
    responses: []termmodel.Terminal_Response) -> (int, bool) {
    count, start := 0, 0
    for index in 0..=len(candidate) {
        if index < len(candidate) && candidate[index] != ';' { continue }
        if count >= len(responses) || index == start { return 0, false }
        response, valid := terminal_capability_prepare_response(
            candidate[start:index], query_context.producer)
        if !valid { return 0, false }
        responses[count] = response
        count += 1
        start = index + 1
    }
    return count, count > 0
}

// Snapshot all query-visible terminal values without exposing parser storage.
interpreter_query_context :: proc(interpreter: ^Interpreter) -> Query_Context {
    if interpreter == nil || interpreter.grid == nil { return {} }
    result := Query_Context{
        style = interpreter.grid.style,
        scroll_top = interpreter.grid.editing.scroll_top,
        scroll_bottom = interpreter.grid.editing.scroll_bottom,
        producer = interpreter_sequence_producer(interpreter),
        input_mode = interpreter.input_mode,
        kitty_keyboard_flags = interpreter_kitty_keyboard_flags(interpreter),
    }
    if interpreter.title_state != nil {
        result.geometry = interpreter.title_state.query_geometry
        result.palette = &interpreter.title_state.palette
        result.modify_other_keys_level =
            interpreter.title_state.modify_other_keys_level
    }
    return result
}

// Finish one bounded DECRQSS or XTGETTCAP query after its complete ST terminator.
interpreter_finish_dcs_query :: proc(interpreter: ^Interpreter) {
    state := interpreter.title_state
    if state == nil { return }
    if state.query_candidate_invalid {
        state.query_rejection_count += 1
        return
    }
    candidate := state.query_candidate[:state.query_candidate_byte_count]
    query_context := interpreter_query_context(interpreter)
    responses: [TERMINAL_RESPONSE_CAPACITY]termmodel.Terminal_Response
    count, valid := 0, true
    if interpreter.dcs_query_prefix == '$' {
        responses[0] = query_prepare_decrqss_response(query_context, candidate)
        count = 1
    } else if interpreter.dcs_query_prefix == '+' {
        count, valid = query_prepare_xtgetcap_responses(
            query_context, candidate, responses[:])
    } else {
        valid = false
    }
    if !valid || count > len(state.responses) - state.response_count {
        state.query_rejection_count += 1
        if valid { state.response_rejection_count += 1 }
        return
    }
    for response in responses[:count] {
        interpreter_append_preflighted_response(state, response)
    }
    state.query_acceptance_count += u64(count)
}
package terminalview

import "../../core"
import termgrid "../../terminal/grid"
import termemulator "../../terminal/emulator"
import termhyperlink "../../terminal/hyperlink"
import termmodel "../../terminal/model"
import "../input"

import rl "vendor:raylib"

// Return the hyperlink leader at one visible output row and zero-based column.
terminal_output_hyperlink_at :: proc(
    term: ^core.Terminal_State, line, column: int) -> termmodel.Hyperlink_Handle {
    cells, ok := terminal_output_row(term, line)
    if !ok || column < 0 || column >= len(cells) {
        return 0
    }
    if cells[column].continuation {
        if column == 0 {
            return 0
        }
        return cells[column - 1].hyperlink
    }
    return cells[column].hyperlink
}

// Report whether one cell ends a detected-link token.
terminal_link_cell_is_boundary :: proc(cell: ^termgrid.Cell) -> bool {
    if cell == nil || cell.continuation || cell.grapheme_len == 0 { return true }
    for byte in cell.grapheme[:cell.grapheme_len] {
        if termhyperlink.hyperlink_uri_byte_rejected(byte) { return true }
    }
    return false
}

// Return whether a trailing sentence byte is always excluded from a detected URI.
terminal_link_trailing_punctuation :: proc(byte: u8) -> bool {
    return byte == '.' || byte == ',' || byte == ';' || byte == ':' ||
        byte == '!' || byte == '?' || byte == '\'' || byte == '"'
}

// Return whether one trailing closer lacks a matching opener in the candidate.
terminal_link_unmatched_closer :: proc(bytes: []u8, closer: u8) -> bool {
    opener: u8
    switch closer {
    case ')': opener = '('
    case ']': opener = '['
    case '}': opener = '{'
    case: return false
    }
    balance := 0
    for byte in bytes {
        if byte == opener { balance += 1 }
        if byte == closer { balance -= 1 }
    }
    return balance < 0
}

// Trim sentence punctuation and unmatched closing delimiters from one candidate.
terminal_link_trim_candidate :: proc(bytes: []u8) -> int {
    end := len(bytes)
    for end > 0 {
        trailing := bytes[end - 1]
        if terminal_link_trailing_punctuation(trailing) ||
            terminal_link_unmatched_closer(bytes[:end], trailing) {
            end -= 1
            continue
        }
        break
    }
    return end
}

// Compute one stable content-and-span identity for a detected link hit.
terminal_link_hit_hash :: proc(
    uri: []u8, line, start, end: int) -> u64 {
    hash := u64(14695981039346656037)
    for byte in uri {
        hash = (hash ~ u64(byte)) * 1099511628211
    }
    hash = (hash ~ u64(line)) * 1099511628211
    hash = (hash ~ u64(start)) * 1099511628211
    return (hash ~ u64(end)) * 1099511628211
}

// Copy one physical-row candidate into bounded frame-local hit storage.
terminal_link_copy_candidate :: proc(
    cells: []termgrid.Cell, start, end: int,
    hit: ^Terminal_Link_Hit) -> bool {
    for index in start..<end {
        cell := &cells[index]
        if cell.continuation { continue }
        bytes := cell.grapheme[:cell.grapheme_len]
        if hit.uri_byte_count + len(bytes) >= len(hit.uri) { return false }
        copy(hit.uri[hit.uri_byte_count:], bytes)
        hit.uri_byte_count += len(bytes)
    }
    return true
}

// Map one trimmed candidate byte count back to its physical-row end column.
terminal_link_trimmed_column_end :: proc(
    cells: []termgrid.Cell, start, end, byte_count: int) -> int {
    copied := 0
    column_end := start
    for index in start..<end {
        cell := &cells[index]
        if cell.continuation { continue }
        if copied >= byte_count { break }
        copied += int(cell.grapheme_len)
        column_end = index + max(int(cell.width), 1)
    }
    return column_end
}

// Detect one conservative absolute URI token at a physical-row column.
terminal_detect_link_at :: proc(
    cells: []termgrid.Cell, line, column: int) -> Terminal_Link_Hit {
    if column < 0 || column >= len(cells) || cells[column].continuation ||
        terminal_link_cell_is_boundary(&cells[column]) { return {} }
    start := column
    for start > 0 && !cells[start - 1].continuation &&
        !terminal_link_cell_is_boundary(&cells[start - 1]) { start -= 1 }
    end := column + max(int(cells[column].width), 1)
    for end < len(cells) &&
        !terminal_link_cell_is_boundary(&cells[end]) {
        end += max(int(cells[end].width), 1)
    }
    hit := Terminal_Link_Hit{
        kind = .Detected, line = line,
        column_start = start, column_end = end,
    }
    if !terminal_link_copy_candidate(cells, start, end, &hit) { return {} }
    trimmed := terminal_link_trim_candidate(hit.uri[:hit.uri_byte_count])
    hit.uri_byte_count = trimmed
    hit.column_end = terminal_link_trimmed_column_end(
        cells, start, end, trimmed)
    uri := string(hit.uri[:hit.uri_byte_count])
    parsed, supported := termhyperlink.hyperlink_uri_scheme(uri)
    if !supported || parsed.scheme == .File ||
        !termhyperlink.hyperlink_uri_valid(uri) || column >= hit.column_end { return {} }
    hit.identity_hash = terminal_link_hit_hash(
        hit.uri[:hit.uri_byte_count], line, hit.column_start, hit.column_end)
    return hit
}

// Clear every retained press target without affecting hover or terminal content.
terminal_clear_hyperlink_press :: proc(term: ^core.Terminal_State) {
    term.hyperlink_pressed = 0
    registry := term.hyperlink_registry
    if registry == nil { return }
    registry.detected_pressed_hash = 0
    registry.detected_pressed_line = 0
    registry.detected_pressed_start = 0
    registry.detected_pressed_end = 0
}

// Retain the compact identity of one explicit or detected press target.
terminal_store_hyperlink_press :: proc(
    term: ^core.Terminal_State, hit: Terminal_Link_Hit) {
    terminal_clear_hyperlink_press(term)
    if hit.kind == .Osc8 {
        term.hyperlink_pressed = hit.handle
    } else if hit.kind == .Detected && term.hyperlink_registry != nil {
        registry := term.hyperlink_registry
        registry.detected_pressed_hash = hit.identity_hash
        registry.detected_pressed_line = hit.line
        registry.detected_pressed_start = hit.column_start
        registry.detected_pressed_end = hit.column_end
    }
}

// Report whether one released hit exactly matches the retained press target.
terminal_hyperlink_release_matches :: proc(
    term: ^core.Terminal_State, hit: Terminal_Link_Hit) -> bool {
    if hit.kind == .Osc8 {
        return hit.handle != 0 && hit.handle == term.hyperlink_pressed
    }
    registry := term.hyperlink_registry
    if registry == nil { return false }
    return hit.kind == .Detected && hit.identity_hash != 0 &&
        hit.identity_hash == registry.detected_pressed_hash &&
        hit.line == registry.detected_pressed_line &&
        hit.column_start == registry.detected_pressed_start &&
        hit.column_end == registry.detected_pressed_end
}

// Resolve one screen-space point to an actionable link in committed presentation state.
terminal_hit_test_link :: proc(
    term: ^core.Terminal_State, bounds: rl.Rectangle,
    mouse: rl.Vector2) -> Terminal_Link_Hit {
    if term == nil || term.geometry.column_width <= 0 ||
        term.geometry.line_height <= 0 {
        return {}
    }
    padded := terminal_accepted_padded_bounds(term, bounds)
    if !rl.CheckCollisionPointRec(mouse, padded) {
        return {}
    }
    origin_y := padded.y - term.scroll_offset_y
    line := int((mouse.y - origin_y) / term.geometry.line_height)
    if line < 0 || line >= terminal_line_count(term) {
        return {}
    }
    column := int((mouse.x - padded.x) / term.geometry.column_width)
    handle := terminal_output_hyperlink_at(term, line, column)
    if handle != 0 {
        cells, _ := terminal_output_row(term, line)
        start, end := column, column + 1
        for start > 0 && terminal_output_hyperlink_at(term, line, start - 1) == handle {
            start -= 1
        }
        for end < len(cells) && terminal_output_hyperlink_at(term, line, end) == handle {
            end += 1
        }
        return {kind = .Osc8, handle = handle, line = line,
            column_start = start, column_end = end}
    }
    cells, ok := terminal_output_row(term, line)
    if !ok { return {} }
    return terminal_detect_link_at(cells, line, column)
}

// Track one press/release pair and request activation only on the same link.
terminal_update_hyperlink_click :: proc(
    term: ^core.Terminal_State, frame: input.Input_Frame,
    bounds: rl.Rectangle) -> Terminal_Hyperlink_Activation {
    if !terminal_hyperlink_interaction_allowed(term, frame.mouse_modifiers) {
        terminal_clear_hyperlink_press(term)
        return {}
    }
    mouse := rl.Vector2{frame.mouse_position.x, frame.mouse_position.y}
    if .Left in frame.mouse_pressed {
        terminal_store_hyperlink_press(
            term, terminal_hit_test_link(term, bounds, mouse))
    }
    if .Left not_in frame.mouse_released {
        return {}
    }
    released := terminal_hit_test_link(term, bounds, mouse)
    requested := terminal_hyperlink_release_matches(term, released)
    terminal_clear_hyperlink_press(term)
    activation := Terminal_Hyperlink_Activation{
        kind = released.kind, handle = released.handle, requested = requested,
    }
    if requested && released.kind == .Detected {
        copy(activation.uri[:], released.uri[:released.uri_byte_count])
        activation.uri_byte_count = released.uri_byte_count
    }
    return activation
}

// Report whether local hyperlink interaction owns unmodified pointer input.
terminal_hyperlink_interaction_allowed :: proc(
    term: ^core.Terminal_State, modifiers: input.Input_Modifiers) -> bool {
    if term == nil || .Shift in modifiers {
        return false
    }
    mode := termemulator.interpreter_input_mode(&term.output_interpreter)
    return mode.mouse_tracking == .None || !mode.mouse_sgr_encoding
}

// Resolve the actionable link under one pointer when local interaction has precedence.
terminal_hyperlink_hover_hit :: proc(
    term: ^core.Terminal_State, frame: input.Input_Frame,
    bounds: rl.Rectangle) -> Terminal_Link_Hit {
    if !terminal_hyperlink_interaction_allowed(term, frame.mouse_modifiers) {
        return {}
    }
    mouse := rl.Vector2{frame.mouse_position.x, frame.mouse_position.y}
    return terminal_hit_test_link(term, bounds, mouse)
}

// Report whether the current eligible pointer position covers an actionable link.
terminal_hyperlink_hovered :: proc(
    term: ^core.Terminal_State, frame: input.Input_Frame,
    bounds: rl.Rectangle) -> bool {
    return terminal_hyperlink_hover_hit(term, frame, bounds).kind != .None
}

// Invoke one validated hyperlink through a caller-owned display-thread adapter.
terminal_activate_hyperlink :: proc(
    term: ^core.Terminal_State, activation: Terminal_Hyperlink_Activation,
    sink: Terminal_Hyperlink_Activation_Sink) -> bool {
    if term == nil || !activation.requested || sink.activate == nil {
        return false
    }
    if activation.kind == .Detected {
        detected := activation
        uri := string(detected.uri[:detected.uri_byte_count])
        parsed, supported := termhyperlink.hyperlink_uri_scheme(uri)
        if !supported || parsed.scheme == .File ||
            !termhyperlink.hyperlink_uri_valid(uri) { return false }
        return sink.activate(sink.user_data, cstring(&detected.uri[0]))
    }
    uri, valid := termhyperlink.hyperlink_registry_cstring(
        term.hyperlink_registry, activation.handle)
    if activation.kind != .Osc8 || !valid {
        termhyperlink.hyperlink_registry_note_activation(
            term.hyperlink_registry, activation.handle, false)
        return false
    }
    accepted := sink.activate(sink.user_data, uri)
    termhyperlink.hyperlink_registry_note_activation(
        term.hyperlink_registry, activation.handle, accepted)
    return accepted
}

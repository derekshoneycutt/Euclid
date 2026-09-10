package terminalview

import "../../core"
import termgrid "../../terminal/grid"
import termmodel "../../terminal/model"
import termshellintegration "../../terminal/shell_integration"
import "../input"

import "core:unicode/utf8"

// Find a prompt row when a caller supplies shell metadata without an initialized index.
terminal_find_shell_prompt_row :: proc(
    term: ^core.Terminal_State, start_line, direction: int) -> (int, bool) {
    line_count := terminal_line_count(term)
    for line := start_line + direction;
        line >= 0 && line < line_count;
        line += direction {
        markers, present := terminal_output_row_shell_markers(term, line)
        if present && markers.present[.Prompt] { return line, true }
    }
    return 0, false
}

// Resolve one retained semantic row identity to its current presented line.
terminal_find_logical_row :: proc(
    term: ^core.Terminal_State, logical_line_id: i64) -> (int, bool) {
    line_count := terminal_line_count(term)
    for line in 0..<line_count {
        candidate, present := terminal_output_logical_row(term, line)
        if present && candidate == logical_line_id { return line, true }
    }
    return 0, false
}

// Find the nearest indexed prompt before or after one presented line.
terminal_find_shell_prompt :: proc(
    term: ^core.Terminal_State, start_line, direction: int) -> (int, bool) {
    if term == nil || direction == 0 {
        return 0, false
    }
    current_id, current_present := terminal_output_logical_row(term, start_line)
    if !current_present { return 0, false }
    target_id: i64
    found := false
    count := termshellintegration.shell_command_block_count(term.shell_integration)
    if count == 0 {
        return terminal_find_shell_prompt_row(term, start_line, direction)
    }
    for index in 0..<count {
        block, present := termshellintegration.shell_command_block(
            term.shell_integration, index)
        if !present || .Prompt not_in block.present { continue }
        candidate := i64(block.prompt.logical_line_id)
        eligible := candidate < current_id if direction < 0 else candidate > current_id
        if !eligible { continue }
        if !found || (direction < 0 && candidate > target_id) ||
            (direction > 0 && candidate < target_id) {
            target_id = candidate
            found = true
        }
    }
    if !found { return 0, false }
    return terminal_find_logical_row(term, target_id)
}

// Resolve one semantic command position into the current byte-based view model.
terminal_semantic_view_position :: proc(
    term: ^core.Terminal_State,
    position: termmodel.Terminal_Semantic_Position) ->
    (core.Terminal_View_Position, bool) {
    for line in 0..<terminal_line_count(term) {
        semantic_row := terminal_output_semantic_row(term, line)
        if !semantic_row.present ||
            semantic_row.logical_line_id != position.logical_line_id ||
            position.grapheme_offset < semantic_row.grapheme_offset {
            continue
        }
        cells, cells_found := terminal_output_row(term, line)
        if !cells_found { continue }
        count := termgrid.grid_row_grapheme_count(&termgrid.Row{cells = cells})
        if position.grapheme_offset >
            semantic_row.grapheme_offset + count { continue }
        column_offset := position.grapheme_offset - semantic_row.grapheme_offset
        column := 0
        for &cell, cell_index in cells {
            if cell.continuation || cell.grapheme_len == 0 { continue }
            if column_offset == 0 { break }
            column_offset -= 1
            column = cell_index + max(int(cell.width), 1)
        }
        return {line = line,
            byte_offset = terminal_output_row_byte_offset(cells, column)}, true
    }
    return {}, false
}

// Return the indexed block covering one logical row, or the nearest preceding block.
terminal_shell_block_at_line :: proc(
    term: ^core.Terminal_State, line: int) -> (termmodel.Command_Block, bool) {
    logical_id, present := terminal_output_logical_row(term, line)
    if !present { return {}, false }
    result: termmodel.Command_Block
    found := false
    count := termshellintegration.shell_command_block_count(term.shell_integration)
    for index in 0..<count {
        block, block_present := termshellintegration.shell_command_block(
            term.shell_integration, index)
        if !block_present { continue }
        first := i64(termshellintegration.shell_command_first_position(
            &block).logical_line_id)
        last := i64(termshellintegration.shell_command_last_position(
            &block).logical_line_id)
        if logical_id >= first && logical_id <= last {
            result, found = block, true
            continue
        }
        if first <= logical_id { result, found = block, true }
    }
    return result, found
}

// Resolve one command or output semantic range into current view-selection endpoints.
terminal_command_range :: proc(
    term: ^core.Terminal_State, block: ^termmodel.Command_Block,
    kind: Terminal_Command_Range) -> Terminal_Command_View_Range {
    start, end := block.command, block.execution
    required := bit_set[termmodel.Shell_Marker_Kind; u8]{
        .Command, .Execution,
    }
    if kind == .Output {
        start, end = block.execution, block.finished
        required = {.Execution, .Finished}
    }
    if block.present & required != required { return {} }
    first, first_ok := terminal_semantic_view_position(term, start)
    last, last_ok := terminal_semantic_view_position(term, end)
    return {start = first, end = last,
        valid = first_ok && last_ok && first != last}
}

// Append one selected row segment and its retained cell boundaries to search scratch.
terminal_command_search_append_row :: proc(
    workspace: ^Terminal_Command_Search_Workspace, cells: []termgrid.Cell,
    line, start, end: int) -> bool {
    text := terminal_output_row_text(cells)
    first := clamp(start, 0, len(text))
    last := clamp(end, first, len(text))
    count := last - first
    if workspace.byte_count + count > len(workspace.text) { return false }
    destination := workspace.byte_count
    copy(workspace.text[destination:destination + count], text[first:last])
    for column in 0..=len(cells) {
        if column < len(cells) && cells[column].continuation { continue }
        offset := terminal_output_row_byte_offset(cells, column)
        if offset < first || offset > last { continue }
        mapped := destination + offset - first
        workspace.boundaries[mapped] = true
        workspace.positions[mapped] = {line = line, byte_offset = offset}
    }
    workspace.byte_count += count
    return true
}

// Compose one B-to-C command as bounded searchable bytes and cell-boundary positions.
terminal_command_search_workspace :: proc(
    term: ^core.Terminal_State, block: ^termmodel.Command_Block,
    workspace: ^Terminal_Command_Search_Workspace) -> bool {
    workspace^ = {}
    command_range := terminal_command_range(term, block, .Command)
    if !command_range.valid { return false }
    for line := command_range.start.line;
        line <= command_range.end.line; line += 1 {
        cells, found := terminal_output_row(term, line)
        if !found { return false }
        row_start := command_range.start.byte_offset if
            line == command_range.start.line else 0
        row_end := command_range.end.byte_offset if
            line == command_range.end.line else
            len(terminal_output_row_text(cells))
        if !terminal_command_search_append_row(
            workspace, cells, line, row_start, row_end) { return false }
        if line == command_range.end.line { continue }
        wrapped, wrapped_found := terminal_output_row_wrapped(term, line)
        if !wrapped_found { return false }
        if !wrapped {
            if workspace.byte_count == len(workspace.text) { return false }
            workspace.boundaries[workspace.byte_count] = true
            workspace.positions[workspace.byte_count] = {
                line = line, byte_offset = row_end,
            }
            workspace.text[workspace.byte_count] = '\n'
            workspace.byte_count += 1
        }
    }
    workspace.boundaries[workspace.byte_count] = true
    workspace.positions[workspace.byte_count] = command_range.end
    return true
}

// Return whether one bounded byte range exactly matches the active search query.
terminal_command_search_matches :: proc(
    workspace: ^Terminal_Command_Search_Workspace,
    query: []u8, offset: int) -> bool {
    if offset < 0 || offset + len(query) > workspace.byte_count ||
        !workspace.boundaries[offset] ||
        !workspace.boundaries[offset + len(query)] { return false }
    for byte, index in query {
        if workspace.text[offset + index] != byte { return false }
    }
    return true
}

// Return whether one command-local match key precedes another chronologically.
terminal_command_search_match_before :: proc(
    left, right: Terminal_Command_Search_Match) -> bool {
    return left.block_index < right.block_index ||
        (left.block_index == right.block_index &&
         left.byte_offset < right.byte_offset)
}

// Retain one candidate as an absolute wrap target and relative next/previous target.
terminal_command_search_consider :: proc(
    candidate: Terminal_Command_Search_Match,
    current: Terminal_Command_Search_Match, direction: int,
    absolute, relative: ^Terminal_Command_Search_Match) {
    before_absolute := !absolute.valid ||
        terminal_command_search_match_before(candidate, absolute^)
    if (direction > 0 && before_absolute) ||
        (direction < 0 && (!absolute.valid ||
         terminal_command_search_match_before(absolute^, candidate))) {
        absolute^ = candidate
    }
    eligible := !current.valid ||
        (direction > 0 && terminal_command_search_match_before(current, candidate)) ||
        (direction < 0 && terminal_command_search_match_before(candidate, current))
    before_relative := !relative.valid ||
        terminal_command_search_match_before(candidate, relative^)
    if eligible && ((direction > 0 && before_relative) ||
        (direction < 0 && (!relative.valid ||
         terminal_command_search_match_before(relative^, candidate)))) {
        relative^ = candidate
    }
}

// Resolve the retained search identity to its chronological command index.
terminal_command_search_current :: proc(
    shell: ^termshellintegration.Shell_Integration_State) ->
    Terminal_Command_Search_Match {
    result := Terminal_Command_Search_Match{
        block = {generation = shell.search_match_generation},
        byte_offset = shell.search_match_byte_offset,
        valid = shell.search_match_generation != 0,
    }
    if !result.valid { return result }
    count := termshellintegration.shell_command_block_count(shell)
    for index in 0..<count {
        block, present := termshellintegration.shell_command_block(shell, index)
        if present && block.generation == result.block.generation {
            result.block_index = index
            return result
        }
    }
    result.valid = false
    return result
}

// Find and select the next or previous literal command match with wraparound.
terminal_command_search :: proc(
    term: ^core.Terminal_State, direction: int) -> bool {
    shell := term.shell_integration
    if shell == nil || direction == 0 || shell.search_query_byte_count == 0 {
        return false
    }
    query := shell.search_query[:shell.search_query_byte_count]
    current := terminal_command_search_current(shell)
    count := termshellintegration.shell_command_block_count(shell)
    absolute, relative: Terminal_Command_Search_Match
    workspace: Terminal_Command_Search_Workspace
    for index in 0..<count {
        block, present := termshellintegration.shell_command_block(shell, index)
        if !present || !terminal_command_search_workspace(
            term, &block, &workspace) { continue }
        for offset in 0..=workspace.byte_count - len(query) {
            if !terminal_command_search_matches(&workspace, query, offset) { continue }
            candidate := Terminal_Command_Search_Match{
                block = block,
                start = workspace.positions[offset],
                end = workspace.positions[offset + len(query)],
                block_index = index, byte_offset = offset, valid = true,
            }
            terminal_command_search_consider(
                candidate, current, direction, &absolute, &relative)
        }
    }
    result := relative if relative.valid else absolute
    if !result.valid { return false }
    shell.search_match_generation = result.block.generation
    shell.search_match_byte_offset = result.byte_offset
    term.view_selection_anchor = result.start
    term.view_selection_head = result.end
    term.view_selection_active = true
    term.view_selection_dragging = false
    return true
}

// Begin a fresh bounded local command-search edit transaction.
terminal_command_search_begin :: proc(term: ^core.Terminal_State) -> bool {
    if term == nil || term.shell_integration == nil { return false }
    shell := term.shell_integration
    shell.search_query = {}
    shell.search_query_byte_count = 0
    shell.search_match_generation = 0
    shell.search_match_byte_offset = 0
    shell.search_editing = true
    return true
}

// Append one typed scalar to the active bounded command-search query.
terminal_command_search_append :: proc(
    term: ^core.Terminal_State, codepoint: rune) -> bool {
    shell := term.shell_integration
    if shell == nil || !shell.search_editing { return false }
    bytes, byte_count := utf8.encode_rune(codepoint)
    if shell.search_query_byte_count + byte_count > len(shell.search_query) {
        return false
    }
    copy(shell.search_query[shell.search_query_byte_count:], bytes[:byte_count])
    shell.search_query_byte_count += byte_count
    shell.search_match_generation = 0
    shell.search_match_byte_offset = 0
    return true
}

// Remove the final UTF-8 scalar from the active command-search query.
terminal_command_search_backspace :: proc(term: ^core.Terminal_State) -> bool {
    shell := term.shell_integration
    if shell == nil || !shell.search_editing || shell.search_query_byte_count == 0 {
        return false
    }
    index := shell.search_query_byte_count - 1
    for index > 0 && shell.search_query[index] & 0xc0 == 0x80 { index -= 1 }
    for byte_index in index..<shell.search_query_byte_count {
        shell.search_query[byte_index] = 0
    }
    shell.search_query_byte_count = index
    shell.search_match_generation = 0
    shell.search_match_byte_offset = 0
    return true
}

// Consume one input event while the local command-search editor owns keyboard input.
terminal_update_command_search :: proc(
    term: ^core.Terminal_State, event: input.Input_Event) -> bool {
    shell := term.shell_integration
    if shell == nil || !shell.search_editing { return false }
    if event.kind == .Text {
        terminal_command_search_append(term, event.codepoint)
    } else if event.kind == .Press && event.key == .Backspace {
        terminal_command_search_backspace(term)
    } else if event.kind == .Press && event.key == .Escape {
        shell.search_editing = false
    } else if event.kind == .Press &&
        (event.key == .Enter || event.key == .Keypad_Enter) {
        direction := -1 if .Shift in event.modifiers else 1
        terminal_command_search(term, direction)
    }
    return true
}

// Replace the bounded literal command-search query and clear prior match identity.
terminal_command_search_set_query :: proc(
    term: ^core.Terminal_State, query: string) -> bool {
    shell := term.shell_integration
    if shell == nil || len(query) > len(shell.search_query) ||
        !utf8.valid_string(query) { return false }
    shell.search_query = {}
    copy(shell.search_query[:], transmute([]u8)query)
    shell.search_query_byte_count = len(query)
    shell.search_match_generation = 0
    shell.search_match_byte_offset = 0
    return true
}

// Select one indexed command or output range nearest the current scroll position.
terminal_select_command_range :: proc(
    term: ^core.Terminal_State, kind: Terminal_Command_Range) -> bool {
    if term == nil || term.geometry.line_height <= 0 { return false }
    line := int(term.scroll_offset_y / term.geometry.line_height)
    block, found := terminal_shell_block_at_line(term, line)
    if !found { return false }
    command_range := terminal_command_range(term, &block, kind)
    if !command_range.valid { return false }
    term.view_selection_anchor = command_range.start
    term.view_selection_head = command_range.end
    term.view_selection_active = true
    term.view_selection_dragging = false
    return true
}

// Find the nearest indexed command start before or after one presented line.
terminal_find_shell_command :: proc(
    term: ^core.Terminal_State, start_line, direction: int) -> (int, bool) {
    if term == nil || direction == 0 { return 0, false }
    current_id, current_present := terminal_output_logical_row(term, start_line)
    if !current_present { return 0, false }
    target_id: i64
    found := false
    count := termshellintegration.shell_command_block_count(term.shell_integration)
    for index in 0..<count {
        block, present := termshellintegration.shell_command_block(
            term.shell_integration, index)
        if !present || .Command not_in block.present { continue }
        candidate := i64(block.command.logical_line_id)
        eligible := candidate < current_id if direction < 0 else candidate > current_id
        if eligible && (!found || (direction < 0 && candidate > target_id) ||
            (direction > 0 && candidate < target_id)) {
            target_id, found = candidate, true
        }
    }
    if !found { return 0, false }
    return terminal_find_logical_row(term, target_id)
}

// Apply one shell-navigation press and report whether it was reserved.
terminal_update_shell_navigation_event :: proc(
    term: ^core.Terminal_State, event: input.Input_Event,
    current_line: int) -> bool {
    direction := -1 if event.key == .Page_Up else
        1 if event.key == .Page_Down else 0
    if event.modifiers == {.Control, .Shift} && direction != 0 {
        if line, found := terminal_find_shell_prompt(
            term, current_line, direction); found {
            term.scroll_offset_y = f32(line) * term.geometry.line_height
        }
        return true
    }
    if event.modifiers != {.Control, .Alt} { return false }
    if event.key == .F { terminal_command_search_begin(term); return true }
    if direction != 0 {
        if line, found := terminal_find_shell_command(
            term, current_line, direction); found {
            term.scroll_offset_y = f32(line) * term.geometry.line_height
        }
    } else if event.key == .C {
        terminal_select_command_range(term, .Command)
    } else if event.key == .O {
        terminal_select_command_range(term, .Output)
    } else { return false }
    return true
}

// Apply one reserved prompt, command-navigation, or semantic-selection chord.
terminal_update_shell_navigation :: proc(
    term: ^core.Terminal_State,
    frame: input.Input_Frame) -> (event_index: int, handled: bool) {
    if term == nil || term.geometry.line_height <= 0 {
        return 0, false
    }
    for event, index in frame.events {
        if terminal_update_command_search(term, event) { return index, true }
        if event.kind != .Press { continue }
        current_line := int(term.scroll_offset_y / term.geometry.line_height)
        if terminal_update_shell_navigation_event(
            term, event, current_line) { return index, true }
    }
    return 0, false
}

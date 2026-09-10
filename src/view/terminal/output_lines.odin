package terminalview

import "../../core"
import termgrid "../../terminal/grid"
import termmodel "../../terminal/model"

import "core:strings"

// Optional semantic provenance for one presented physical output row.
Terminal_Output_Semantic_Row :: struct {
    logical_line_id: termmodel.Terminal_Logical_Line_Id,
    grapheme_offset: u32,
    present: bool,
}

// Return one oldest-first output row from bounded scrollback or the live grid.
terminal_output_row :: proc(
    term: ^core.Terminal_State, line: int) -> ([]termgrid.Cell, bool) {

    if term == nil || line < 0 {
        return nil, false
    }
    scrollback_count := terminal_visible_scrollback_count(term)
    if line < scrollback_count {
        if term.synchronized_output.active {
            row, ok := termgrid.display_checkpoint_scrollback_row(
                &term.synchronized_output.checkpoint, line)
            return row.cells, ok
        }
        row, ok := termgrid.scrollback_row(&term.output_scrollback, line)
        return row.cells, ok
    }
    screen_row := line - scrollback_count
    screen_count := terminal_grid_line_count(term)
    if screen_row < 0 || screen_row >= screen_count {
        return nil, false
    }
    if term.synchronized_output.active {
        return termgrid.display_checkpoint_grid_row(
            &term.synchronized_output.checkpoint, screen_row)
    }
    return term.output_grid.rows[screen_row].cells, true
}

// Return the stable logical-row identity for one presented output line.
terminal_output_logical_row :: proc(
    term: ^core.Terminal_State, line: int) -> (i64, bool) {
    if term == nil || line < 0 { return 0, false }
    scrollback_count := terminal_visible_scrollback_count(term)
    if line < scrollback_count {
        if term.synchronized_output.active {
            row, ok := termgrid.display_checkpoint_scrollback_row(
                &term.synchronized_output.checkpoint, line)
            return row.logical_id, ok
        }
        row, ok := termgrid.scrollback_row(&term.output_scrollback, line)
        return row.logical_id, ok
    }
    screen_row := line - scrollback_count
    if term.synchronized_output.active {
        rows := term.synchronized_output.checkpoint.grid_rows
        if screen_row < 0 || screen_row >= len(rows) { return 0, false }
        return rows[screen_row].logical_id, true
    }
    if screen_row < 0 || screen_row >= len(term.output_grid.rows) {
        return 0, false
    }
    return term.output_grid.rows[screen_row].logical_id, true
}

// Return semantic line identity and starting grapheme ordinal for one output row.
terminal_output_semantic_row :: proc(
    term: ^core.Terminal_State, line: int) -> Terminal_Output_Semantic_Row {
    if term == nil || line < 0 { return {} }
    scrollback_count := terminal_visible_scrollback_count(term)
    if line < scrollback_count {
        if term.synchronized_output.active {
            row, ok := termgrid.display_checkpoint_scrollback_row(
                &term.synchronized_output.checkpoint, line)
            return {row.logical_line_id, row.grapheme_offset, ok}
        }
        row, ok := termgrid.scrollback_row(&term.output_scrollback, line)
        return {row.logical_line_id, row.grapheme_offset, ok}
    }
    screen_row := line - scrollback_count
    if term.synchronized_output.active {
        rows := term.synchronized_output.checkpoint.grid_rows
        if screen_row < 0 || screen_row >= len(rows) { return {} }
        row := rows[screen_row]
        return {row.logical_line_id, row.grapheme_offset, true}
    }
    if screen_row < 0 || screen_row >= len(term.output_grid.rows) {
        return {}
    }
    row := &term.output_grid.rows[screen_row]
    return {row.logical_line_id, row.grapheme_offset, true}
}

// Return whether one presented physical row soft-wraps into its successor.
terminal_output_row_wrapped :: proc(
    term: ^core.Terminal_State, line: int) -> (bool, bool) {
    if term == nil || line < 0 { return false, false }
    scrollback_count := terminal_visible_scrollback_count(term)
    if line < scrollback_count {
        if term.synchronized_output.active {
            row, ok := termgrid.display_checkpoint_scrollback_row(
                &term.synchronized_output.checkpoint, line)
            return row.wrapped, ok
        }
        row, ok := termgrid.scrollback_row(&term.output_scrollback, line)
        return row.wrapped, ok
    }
    screen_row := line - scrollback_count
    if term.synchronized_output.active {
        rows := term.synchronized_output.checkpoint.grid_rows
        if screen_row < 0 || screen_row >= len(rows) { return false, false }
        return rows[screen_row].wrapped, true
    }
    if screen_row < 0 || screen_row >= len(term.output_grid.rows) {
        return false, false
    }
    return term.output_grid.rows[screen_row].wrapped, true
}

// Hide primary history while the ephemeral alternate viewport is selected.
terminal_visible_scrollback_count :: proc(term: ^core.Terminal_State) -> int {
    if term == nil {
        return 0
    }
    if term.synchronized_output.active {
        if term.synchronized_output.captured_alternate_screen_active {
            return 0
        }
        return term.synchronized_output.checkpoint.scrollback_count
    }
    if term.output_interpreter.alternate_screen_active { return 0 }
    return term.output_scrollback.count
}

// Return whether one row contains a visible leader or continuation cell.
terminal_output_row_occupied :: proc(cells: []termgrid.Cell) -> bool {
    for &cell in cells {
        if cell.grapheme_len > 0 || cell.continuation { return true }
    }
    return false
}

// Return the meaningful screen prefix, excluding the unused fixed-grid tail.
terminal_grid_line_count :: proc(term: ^core.Terminal_State) -> int {
    if term == nil {
        return 0
    }
    output_started := term.output_started
    cursor := term.output_grid.cursor
    row_count := len(term.output_grid.rows)
    if term.synchronized_output.active {
        output_started = term.synchronized_output.captured_output_started
        cursor = term.synchronized_output.checkpoint.grid_cursor
        row_count = len(term.synchronized_output.checkpoint.grid_rows)
    }
    if !output_started { return 0 }
    count := cursor.row
    for row_index := row_count - 1; row_index >= 0; row_index -= 1 {
        cells: []termgrid.Cell
        ok := true
        if term.synchronized_output.active {
            cells, ok = termgrid.display_checkpoint_grid_row(
                &term.synchronized_output.checkpoint, row_index)
        } else {
            cells = term.output_grid.rows[row_index].cells
        }
        if !ok { continue }
        if terminal_output_row_occupied(cells) {
            count = max(count, row_index + 1)
            break
        }
    }
    return count
}

// Return shell markers for one presented scrollback or live-grid row.
terminal_output_row_shell_markers :: proc(
    term: ^core.Terminal_State,
    line: int) -> (termmodel.Shell_Row_Markers, bool) {
    if term == nil || line < 0 {
        return {}, false
    }
    scrollback_count := terminal_visible_scrollback_count(term)
    if line < scrollback_count {
        if term.synchronized_output.active {
            row, ok := termgrid.display_checkpoint_scrollback_row(
                &term.synchronized_output.checkpoint, line)
            return row.shell_markers, ok
        }
        row, ok := termgrid.scrollback_row(&term.output_scrollback, line)
        return row.shell_markers, ok
    }
    screen_row := line - scrollback_count
    if term.synchronized_output.active {
        return termgrid.display_checkpoint_grid_shell_markers(
            &term.synchronized_output.checkpoint, screen_row)
    }
    if screen_row < 0 || screen_row >= len(term.output_grid.rows) {
        return {}, false
    }
    return term.output_grid.rows[screen_row].shell_markers, true
}

// Concatenate one exact-cell row for selection, clipboard, and tests.
terminal_output_row_text :: proc(cells: []termgrid.Cell) -> string {
    builder := strings.builder_make(context.temp_allocator)
    last_text_end := 0
    for &cell, column in cells {
        if cell.continuation || cell.grapheme_len == 0 {
            continue
        }
        for last_text_end < column {
            strings.write_byte(&builder, ' ')
            last_text_end += 1
        }
        strings.write_string(&builder, termgrid.cell_text(&cell))
        last_text_end = column + max(int(cell.width), 1)
    }
    return strings.to_string(builder)
}

// Map one visual output-row column boundary to its composed UTF-8 byte offset.
//
// Continuation-column boundaries resolve to the owning wide leader. Columns past
// real text remain virtual offsets after the composed row text.
terminal_output_row_byte_offset :: proc(cells: []termgrid.Cell, column: int) -> int {
    target := max(column, 0)
    byte_offset := 0
    visual_end := 0
    for &cell, cell_column in cells {
        if cell.continuation || cell.grapheme_len == 0 {
            continue
        }
        if target <= cell_column {
            return byte_offset + max(target - visual_end, 0)
        }
        byte_offset += max(cell_column - visual_end, 0)
        cell_end := cell_column + max(int(cell.width), 1)
        if target < cell_end {
            return byte_offset
        }
        byte_offset += int(cell.grapheme_len)
        visual_end = cell_end
        if target == cell_end {
            return byte_offset
        }
    }
    return byte_offset + max(target - visual_end, 0)
}

// Return the bounded output row count currently visible to the terminal UI.
terminal_line_count :: proc(term: ^core.Terminal_State) -> int {
    if term == nil {
        return 0
    }
    return terminal_visible_scrollback_count(term) + terminal_grid_line_count(term)
}

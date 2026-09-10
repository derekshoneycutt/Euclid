package termemulator

import termgrid "../grid"

// Save the active DEC cursor, rendition, and addressing state.
interpreter_save_dec_state :: proc(interpreter: ^Interpreter) {
    termgrid.grid_dec_save_state(interpreter.grid)
}

// Restore previously saved DEC state, clamped to current screen geometry.
interpreter_restore_dec_state :: proc(interpreter: ^Interpreter) {
    termgrid.grid_dec_restore_state(interpreter.grid)
}

// Apply IND or NEL within the active vertical margin region.
interpreter_index_forward :: proc(interpreter: ^Interpreter, reset_column: bool) {
    termgrid.grid_index_forward(interpreter.grid, reset_column)
}

// Apply RI within the active vertical margin region.
interpreter_index_reverse :: proc(interpreter: ^Interpreter) {
    termgrid.grid_index_reverse(interpreter.grid)
}

// Set vertical margins from one-based parameters and home the cursor.
interpreter_set_margins :: proc(interpreter: ^Interpreter) -> bool {
    grid := interpreter.grid
    top_parameter := interpreter_parameter(interpreter, 0, 1)
    bottom_parameter := interpreter_parameter(interpreter, 1, grid.row_count)
    top := (1 if top_parameter == 0 else top_parameter) - 1
    bottom := (grid.row_count if bottom_parameter == 0 else bottom_parameter) - 1
    if top < 0 || bottom <= top || bottom >= grid.row_count {
        return false
    }
    return termgrid.grid_set_vertical_margins(grid, top, bottom)
}

// Insert or delete rows from the cursor through the bottom margin.
interpreter_edit_lines :: proc(interpreter: ^Interpreter, insert: bool) {
    amount := max(interpreter_parameter(interpreter, 0, 1), 1)
    termgrid.grid_edit_lines(interpreter.grid, amount, insert)
}

// Apply one character or line insertion, deletion, or erase command.
interpreter_apply_cell_row_edit :: proc(
    interpreter: ^Interpreter, final: u8, amount: int) -> bool {
    grid := interpreter.grid
    switch final {
    case '@':
        termgrid.grid_insert_cells(
            grid, grid.cursor.row, grid.cursor.column, amount)
    case 'P':
        termgrid.grid_delete_cells(
            grid, grid.cursor.row, grid.cursor.column, amount)
    case 'X': termgrid.grid_erase_range(
        grid, grid.cursor.row, grid.cursor.column,
        grid.cursor.column + amount)
    case 'L': interpreter_edit_lines(interpreter, true)
    case 'M': interpreter_edit_lines(interpreter, false)
    case: return false
    }
    return true
}

// Apply tab clearing, margin setting, or insert-mode selection.
interpreter_apply_tab_clear :: proc(interpreter: ^Interpreter) -> bool {
    grid := interpreter.grid
    mode := interpreter_parameter(interpreter, 0, 0)
    if mode == 0 && grid.cursor.column < termgrid.TAB_STOP_CAPACITY {
        termgrid.grid_set_tab_stop(grid, grid.cursor.column, false)
        return true
    }
    if mode == 3 {
        grid.editing.tab_stops = {}
        return true
    }
    return false
}

// Apply one supported insert or sixel scrolling mode toggle.
interpreter_apply_editing_toggle :: proc(
    interpreter: ^Interpreter, enabled: bool) -> bool {
    if interpreter.parameter_count != 1 { return false }
    switch interpreter_parameter(interpreter, 0, -1) {
    case 4: interpreter.grid.editing.insert_mode = enabled
    case 80: interpreter.grid.editing.sixel_scrolling_mode = enabled
    case: return false
    }
    return true
}

// Apply tab clearing, margin setting, or insert-mode selection.
interpreter_apply_dec_editing_mode :: proc(
    interpreter: ^Interpreter, final: u8) -> bool {
    switch final {
    case 'g': return interpreter_apply_tab_clear(interpreter)
    case 'r': return interpreter_set_margins(interpreter)
    case 'h', 'l': return interpreter_apply_editing_toggle(interpreter, final == 'h')
    case: return false
    }
}

// Apply one supported unprefixed DEC/xterm editing CSI command.
interpreter_apply_dec_editing_csi :: proc(
    interpreter: ^Interpreter, final: u8) -> bool {
    grid := interpreter.grid
    amount := max(interpreter_parameter(interpreter, 0, 1), 1)
    if interpreter_apply_cell_row_edit(interpreter, final, amount) {
        return true
    }
    switch final {
    case 'S': termgrid.grid_scroll_region_up(
        grid, grid.editing.scroll_top, grid.editing.scroll_bottom, amount)
    case 'T': termgrid.grid_scroll_region_down(
        grid, grid.editing.scroll_top, grid.editing.scroll_bottom, amount)
    case 'I': termgrid.grid_tab_forward(grid, amount)
    case 'Z': termgrid.grid_tab_backward(grid, amount)
    case: return interpreter_apply_dec_editing_mode(interpreter, final)
    }
    return true
}

// Apply DECSCA protected-field state from `CSI Ps " q`.
interpreter_apply_decsca :: proc(interpreter: ^Interpreter) -> bool {
    if interpreter.csi_intermediate != '"' || interpreter.parameter_count != 1 {
        return false
    }
    parameter := interpreter_parameter(interpreter, 0, 0)
    if parameter == 0 || parameter == 2 {
        interpreter.grid.editing.protected_mode = false
    } else if parameter == 1 {
        interpreter.grid.editing.protected_mode = true
    } else {
        return false
    }
    return true
}

// Erase one line or display while preserving DECSCA-protected cells.
interpreter_selective_erase :: proc(interpreter: ^Interpreter, final: u8) -> bool {
    grid := interpreter.grid
    if final == 'K' {
        return termgrid.grid_selective_erase_line(
            grid, interpreter_parameter(interpreter, 0, 0))
    }
    return final == 'J' && termgrid.grid_selective_erase_display(
        grid, interpreter_parameter(interpreter, 0, 0))
}
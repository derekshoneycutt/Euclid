package termemulator

import termattachment "../attachment"
import gfxsemantics "../graphics/semantics"
import termgrid "../grid"

// Snapshot the active screen anchor for one synchronous graphics semantic effect.
interpreter_graphics_anchor :: proc(
    user_data: rawptr) -> (gfxsemantics.Anchor, bool) {
    interpreter := cast(^Interpreter)user_data
    if interpreter == nil || interpreter.grid == nil ||
        interpreter.grid.cursor.row < 0 ||
        interpreter.grid.cursor.row >= interpreter.grid.row_count {
        return {}, false
    }
    grid := interpreter.grid
    screen := termattachment.Screen_Identity.Alternate if
        interpreter.alternate_screen_active else .Primary
    return {
        screen = screen,
        logical_row = grid.rows[grid.cursor.row].logical_id,
        column = grid.cursor.column,
        sixel_scrolling_mode = grid.editing.sixel_scrolling_mode,
        sixel_cursor_right_mode = grid.editing.sixel_cursor_right_mode,
    }, true
}

// Return the display-committed terminal cell width used by graphics layout.
interpreter_graphics_cell_width :: proc(user_data: rawptr) -> (int, bool) {
    interpreter := cast(^Interpreter)user_data
    if interpreter == nil || interpreter.title_state == nil ||
        !interpreter.title_state.query_geometry.valid ||
        interpreter.title_state.query_geometry.cell_width == 0 {
        return 0, false
    }
    return int(interpreter.title_state.query_geometry.cell_width), true
}

// Return the display-committed terminal cell height used by graphics layout.
interpreter_graphics_cell_height :: proc(user_data: rawptr) -> (int, bool) {
    interpreter := cast(^Interpreter)user_data
    if interpreter == nil || interpreter.title_state == nil ||
        !interpreter.title_state.query_geometry.valid ||
        interpreter.title_state.query_geometry.cell_height == 0 {
        return 0, false
    }
    return int(interpreter.title_state.query_geometry.cell_height), true
}

// Advance terminal columns for one synchronous graphics placement effect.
interpreter_graphics_advance_columns :: proc(user_data: rawptr, columns: int) {
    interpreter := cast(^Interpreter)user_data
    if interpreter == nil || interpreter.grid == nil { return }
    grid := interpreter.grid
    termgrid.grid_set_cursor(
        grid, grid.cursor.row, grid.cursor.column + max(columns, 0))
}

// Advance terminal rows for one synchronous graphics placement effect.
interpreter_graphics_advance_rows :: proc(user_data: rawptr, rows: int) {
    interpreter := cast(^Interpreter)user_data
    if interpreter == nil || interpreter.grid == nil { return }
    for _ in 0..<max(rows, 1) {
        termgrid.grid_index_forward(interpreter.grid, true)
    }
}

// Consume queued graphics frames through explicit terminal capabilities.
interpreter_consume_graphics_frames :: proc(interpreter: ^Interpreter) {
    if interpreter == nil || interpreter.title_state == nil { return }
    semantics_context := gfxsemantics.Context{
        state = interpreter.title_state.graphics,
        user_data = interpreter,
        anchor = interpreter_graphics_anchor,
        cell_width = interpreter_graphics_cell_width,
        cell_height = interpreter_graphics_cell_height,
        advance_columns = interpreter_graphics_advance_columns,
        advance_rows = interpreter_graphics_advance_rows,
    }
    gfxsemantics.graphics_semantics_consume_frames(&semantics_context)
}

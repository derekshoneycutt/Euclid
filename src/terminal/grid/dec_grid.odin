package termgrid

import termmodel "../model"

// Complete DEC cursor/rendition state retained by ESC 7/8 and mode 1048.
Dec_Saved_State :: struct {
    cursor: Cursor,
    style: Cell_Style,
    hyperlink: termmodel.Hyperlink_Handle,
    origin_mode: bool,
    autowrap_mode: bool,
    protected_mode: bool,
    valid: bool,
}

// Move forward to the requested explicit horizontal tab stop.
grid_tab_forward :: proc(grid: ^Grid, amount: int) {
    count := max(amount, 1)
    column := grid.cursor.column
    for _ in 0..<count {
        destination := grid.columns - 1
        for candidate in column + 1..<min(grid.columns, TAB_STOP_CAPACITY) {
            if grid_has_tab_stop(grid, candidate) {
                destination = candidate
                break
            }
        }
        column = destination
    }
    grid_set_cursor(grid, grid.cursor.row, column)
}

// Move backward to the requested explicit horizontal tab stop.
grid_tab_backward :: proc(grid: ^Grid, amount: int) {
    count := max(amount, 1)
    column := grid.cursor.column
    for _ in 0..<count {
        destination := 0
        for candidate := column - 1; candidate > 0; candidate -= 1 {
            if grid_has_tab_stop(grid, candidate) {
                destination = candidate
                break
            }
        }
        column = destination
    }
    grid_set_cursor(grid, grid.cursor.row, column)
}

// Save the active DEC cursor, rendition, and addressing state.
grid_dec_save_state :: proc(grid: ^Grid) {
    if grid == nil { return }
    grid.editing.dec_saved = {
        cursor = grid.cursor,
        style = grid.style,
        hyperlink = grid.hyperlink,
        origin_mode = grid.editing.origin_mode,
        autowrap_mode = grid.editing.autowrap_mode,
        protected_mode = grid.editing.protected_mode,
        valid = true,
    }
}

// Restore previously saved DEC state, clamped to current screen geometry.
grid_dec_restore_state :: proc(grid: ^Grid) {
    if grid == nil { return }
    saved := grid.editing.dec_saved
    if !saved.valid { return }
    grid.style = saved.style
    grid.hyperlink = saved.hyperlink
    grid.editing.origin_mode = saved.origin_mode
    grid.editing.autowrap_mode = saved.autowrap_mode
    grid.editing.protected_mode = saved.protected_mode
    grid_set_cursor(grid, saved.cursor.row, saved.cursor.column)
}

// Apply IND or NEL within the active vertical margin region.
grid_index_forward :: proc(grid: ^Grid, reset_column: bool) {
    if grid == nil { return }
    grid.cursor.wrap_pending = false
    if reset_column { grid.cursor.column = 0 }
    if grid.cursor.row == grid.editing.scroll_bottom {
        grid_scroll_region_up(
            grid, grid.editing.scroll_top, grid.editing.scroll_bottom, 1)
    } else if grid.cursor.row < grid.row_count - 1 {
        grid.cursor.row += 1
    }
}

// Apply RI within the active vertical margin region.
grid_index_reverse :: proc(grid: ^Grid) {
    if grid == nil { return }
    grid.cursor.wrap_pending = false
    if grid.cursor.row == grid.editing.scroll_top {
        grid_scroll_region_down(
            grid, grid.editing.scroll_top, grid.editing.scroll_bottom, 1)
    } else if grid.cursor.row > 0 {
        grid.cursor.row -= 1
    }
}

// Set zero-based vertical margins and home the cursor.
grid_set_vertical_margins :: proc(grid: ^Grid, top, bottom: int) -> bool {
    if grid == nil || top < 0 || bottom <= top || bottom >= grid.row_count {
        return false
    }
    grid.editing.scroll_top = top
    grid.editing.scroll_bottom = bottom
    row := top if grid.editing.origin_mode else 0
    grid_set_cursor(grid, row, 0)
    return true
}

// Insert or delete rows from the cursor through the bottom margin.
grid_edit_lines :: proc(grid: ^Grid, amount: int, insert: bool) {
    if grid == nil || grid.cursor.row < grid.editing.scroll_top ||
        grid.cursor.row > grid.editing.scroll_bottom {
        return
    }
    count := max(amount, 1)
    if insert {
        grid_scroll_region_down(
            grid, grid.cursor.row, grid.editing.scroll_bottom, count)
    } else {
        grid_scroll_region_up(
            grid, grid.cursor.row, grid.editing.scroll_bottom, count)
    }
}

// Selectively erase one line according to the requested mode.
grid_selective_erase_line :: proc(grid: ^Grid, mode: int) -> bool {
    if grid == nil { return false }
    column := grid.cursor.column
    switch mode {
    case 0: grid_erase_range(grid, grid.cursor.row, column, grid.columns, true)
    case 1: grid_erase_range(grid, grid.cursor.row, 0, column + 1, true)
    case 2: grid_erase_range(grid, grid.cursor.row, 0, grid.columns, true)
    case: return false
    }
    return true
}

// Selectively erase one display according to the requested mode.
grid_selective_erase_display :: proc(grid: ^Grid, mode: int) -> bool {
    if grid == nil || mode < 0 || mode > 2 { return false }
    if mode == 0 {
        grid_erase_range(
            grid, grid.cursor.row, grid.cursor.column, grid.columns, true)
        for row in grid.cursor.row + 1..<grid.row_count {
            grid_erase_range(grid, row, 0, grid.columns, true)
        }
    } else if mode == 1 {
        for row in 0..<grid.cursor.row {
            grid_erase_range(grid, row, 0, grid.columns, true)
        }
        grid_erase_range(grid, grid.cursor.row, 0, grid.cursor.column + 1, true)
    } else {
        for row in 0..<grid.row_count {
            grid_erase_range(grid, row, 0, grid.columns, true)
        }
    }
    return true
}

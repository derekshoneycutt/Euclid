package termgrid

import termshellintegration "../shell_integration"

import termattachment "../attachment"

// Fill one clamped row range with styled blank cells.
grid_fill_blank_range :: proc(
    grid: ^Grid, row_index, start, end: int) {
    row := &grid.rows[row_index]
    bounded_start := clamp(start, 0, grid.columns)
    bounded_end := clamp(end, bounded_start, grid.columns)
    for column in bounded_start..<bounded_end {
        row.cells[column] = {style = grid.style}
    }
    grid_mark_dirty(row, bounded_start, bounded_end)
}

// Repair wide pairs and ensure empty cells in one changed range use erase style.
grid_finish_row_edit :: proc(
    grid: ^Grid, row_index, start, end: int) {
    row := &grid.rows[row_index]
    grid_repair_wide_row(row.cells)
    bounded_start := clamp(start, 0, grid.columns)
    bounded_end := clamp(end, bounded_start, grid.columns)
    for column in bounded_start..<bounded_end {
        cell := &row.cells[column]
        if cell.width == 0 && !cell.continuation {
            cell.style = grid.style
        }
    }
    row.wrapped = false
    grid_mark_dirty(row, bounded_start, bounded_end)
}

// Insert blank cells at one row column and discard cells shifted past the edge.
grid_insert_cells :: proc(
    grid: ^Grid, row_index, column, amount: int) {
    if grid == nil || row_index < 0 || row_index >= grid.row_count {
        return
    }
    start := clamp(column, 0, grid.columns)
    count := clamp(amount, 0, grid.columns - start)
    if count == 0 {
        return
    }
    row := &grid.rows[row_index]
    for destination := grid.columns - 1; destination >= start + count;
        destination -= 1 {
        row.cells[destination] = row.cells[destination - count]
    }
    grid_fill_blank_range(grid, row_index, start, start + count)
    termshellintegration.shell_markers_insert_columns(
        &row.shell_markers, start, count, grid.columns)
    grid_finish_row_edit(grid, row_index, start, grid.columns)
}

// Delete cells at one row column and fill the vacated suffix with styled blanks.
grid_delete_cells :: proc(
    grid: ^Grid, row_index, column, amount: int) {
    if grid == nil || row_index < 0 || row_index >= grid.row_count {
        return
    }
    start := clamp(column, 0, grid.columns)
    count := clamp(amount, 0, grid.columns - start)
    if count == 0 {
        return
    }
    row := &grid.rows[row_index]
    for destination in start..<grid.columns - count {
        row.cells[destination] = row.cells[destination + count]
    }
    grid_fill_blank_range(
        grid, row_index, grid.columns - count, grid.columns)
    termshellintegration.shell_markers_delete_columns(
        &row.shell_markers, start, count, grid.columns)
    grid_finish_row_edit(grid, row_index, start, grid.columns)
}

// Copy complete cell and semantic metadata from one row to another.
grid_copy_row :: proc(grid: ^Grid, destination_index, source_index: int) {
    destination := &grid.rows[destination_index]
    source := &grid.rows[source_index]
    copy(destination.cells, source.cells)
    destination.logical_id = source.logical_id
    destination.logical_line_id = source.logical_line_id
    destination.grapheme_offset = source.grapheme_offset
    destination.head_truncated = source.head_truncated
    destination.wrapped = source.wrapped
    destination.shell_markers = source.shell_markers
    destination.dirty = true
    destination.dirty_start = 0
    destination.dirty_end = grid.columns
}

// Scroll one inclusive row region upward without allocating.
grid_scroll_region_up :: proc(grid: ^Grid, top, bottom, amount: int) {
    if grid == nil || top < 0 || bottom < top || bottom >= grid.row_count {
        return
    }
    count := clamp(amount, 0, bottom - top + 1)
    for _ in 0..<count {
        commits_scrollback := top == 0 && bottom == grid.row_count - 1 &&
            grid.scrollback.commit != nil
        if commits_scrollback {
            row := &grid.rows[top]
            grid.scrollback.commit(
                grid.scrollback.user_data, row.cells, {
                    logical_row_id = row.logical_id,
                    wrapped = row.wrapped,
                    shell_markers = row.shell_markers,
                    logical_line_id = row.logical_line_id,
                    grapheme_offset = row.grapheme_offset,
                    head_truncated = row.head_truncated,
                })
        } else if grid.editing.attachment_store != nil {
            termattachment.placements_remove_row(
            grid.editing.attachment_store, grid.editing.screen,
            grid.rows[top].logical_id)
        }
        for row_index in top..<bottom {
            grid_copy_row(grid, row_index, row_index + 1)
        }
        grid_clear_row(grid, bottom)
        grid_reset_row_identity(grid, bottom)
    }
}

// Scroll one inclusive row region downward without committing scrollback.
grid_scroll_region_down :: proc(grid: ^Grid, top, bottom, amount: int) {
    if grid == nil || top < 0 || bottom < top || bottom >= grid.row_count {
        return
    }
    count := clamp(amount, 0, bottom - top + 1)
    for _ in 0..<count {
        if grid.editing.attachment_store != nil {
            termattachment.placements_remove_row(
            grid.editing.attachment_store, grid.editing.screen,
            grid.rows[bottom].logical_id)
        }
        for row_index := bottom; row_index > top; row_index -= 1 {
            grid_copy_row(grid, row_index, row_index - 1)
        }
        grid_clear_row(grid, top)
        grid_reset_row_identity(grid, top)
    }
}
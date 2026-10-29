package uiterminal

import geometry "../../../core/geometry"
import coretext "../../../core/text"
import terminalview "../../terminal"
import viewterminalmodel "../../terminal/model"
import "core:math"

// Prepared regions shared by explorer drawing, hit testing, and accessibility.
Terminal_Explorer_Layout :: struct {
    bounds: geometry.Rectangle,
    query: geometry.Rectangle,
    query_text: geometry.Rectangle,
    list: geometry.Rectangle,
    preview: geometry.Rectangle,
    preview_text: geometry.Rectangle,
    status: geometry.Rectangle,
    hints: geometry.Rectangle,
    source_width: f32,
    mode_x: f32,
    age_x: f32,
    row_capacity: int,
    preview_rows: int,
    preview_columns: int,
    query_start: int,
    compact: bool,
}

// Explorer UI uses the full padded panel, not the VT grid's whole-cell viewport.
terminal_explorer_draw_layout :: proc(
    draw: terminalview.Terminal_Draw_Layout,
    bounds: geometry.Rectangle) -> terminalview.Terminal_Draw_Layout {
    result := draw
    result.padded_bounds = terminalview.terminal_padded_bounds(bounds)
    return result
}

// Reserve stable whole-line regions without changing the Terminal's native geometry.
terminal_explorer_layout :: proc(
    draw: terminalview.Terminal_Draw_Layout,
    query_label: string) -> Terminal_Explorer_Layout {
    bounds := draw.padded_bounds
    pitch := max(f32(1), draw.line_height)
    cell := max(f32(1), draw.column_width)
    lines := int(bounds.height / pitch)
    result: Terminal_Explorer_Layout = {
        bounds = bounds,
        compact = lines < 9 || bounds.width < 36*cell,
    }
    if result.compact {
        return result
    }
    preview_lines := max(3, lines / 3)
    rows := lines - preview_lines - 4
    result.query = {bounds.x, bounds.y, bounds.width, pitch}
    label_width := min(f32(coretext.text_grapheme_column(
        query_label, len(query_label))) * cell, bounds.width / 2)
    result.query_text = {bounds.x + label_width, bounds.y,
        bounds.width - label_width, pitch}
    result.list = {bounds.x, bounds.y + 2*pitch, bounds.width, f32(rows)*pitch}
    result.status = {bounds.x, result.list.y + result.list.height, bounds.width, pitch}
    result.preview = {bounds.x, result.status.y + pitch,
        bounds.width, bounds.y + bounds.height - pitch / 2 -
            (result.status.y + pitch)}
    result.preview_text = {bounds.x + cell, result.preview.y + pitch / 2,
        bounds.width - 2*cell, f32(preview_lines - 1)*pitch}
    result.hints = {bounds.x + cell, bounds.y + bounds.height - pitch,
        bounds.width - 2*cell, pitch}
    result.row_capacity = rows
    result.preview_rows = preview_lines - 1
    result.preview_columns = max(1, int(result.preview_text.width / cell) - 7)
    result.age_x = bounds.x + bounds.width - 7*cell
    result.mode_x = result.age_x - 8*cell
    result.source_width = result.mode_x - bounds.x - 3*cell
    return result
}

// Keep the selected row visible only when selection changes, not on independent wheels.
terminal_explorer_reveal_selection :: proc(
    explorer: ^viewterminalmodel.History_Explorer_State,
    layout: Terminal_Explorer_Layout) {
    maximum := max(0, explorer^.row_count - layout.row_capacity)
    if explorer^.selected_index != explorer^.list_visible_selection {
        if explorer^.selected_index < explorer^.list_scroll_rows {
            explorer^.list_scroll_rows = explorer^.selected_index
        } else if explorer^.selected_index >=
            explorer^.list_scroll_rows + layout.row_capacity {
            explorer^.list_scroll_rows =
                explorer^.selected_index - layout.row_capacity + 1
        }
        explorer^.list_visible_selection = explorer^.selected_index
    }
    explorer^.list_scroll_rows = clamp(explorer^.list_scroll_rows, 0, maximum)
}

// Return the exact prepared rectangle for a visible candidate row.
terminal_explorer_row_rect :: proc(
    layout: Terminal_Explorer_Layout, visible_index: int,
    line_height: f32) -> geometry.Rectangle {
    return {layout.list.x, layout.list.y + f32(visible_index)*line_height,
        layout.list.width, line_height}
}

// Map a list hit through its independent working-page scroll offset.
terminal_explorer_hit_row :: proc(
    layout: Terminal_Explorer_Layout, point: geometry.Vector2,
    scroll_rows, row_count: int, pitch: f32) -> int {
    if layout.compact || !geometry.rectangle_contains(layout.list, point) ||
       point.y >= layout.list.y + layout.list.height ||
       point.x >= layout.list.x + layout.list.width {
        return -1
    }
    index := scroll_rows + int(math.floor((point.y - layout.list.y) / pitch))
    return index if index >= 0 && index < row_count else -1
}

// Scroll the unboxed query horizontally just enough to expose its committed caret.
terminal_explorer_query_start :: proc(
    text: string, cursor, columns: int) -> int {
    column := coretext.text_grapheme_column(text, cursor)
    target := max(0, column - max(1, columns) + 1)
    return coretext.text_grapheme_boundary_for_column(text, target)
}

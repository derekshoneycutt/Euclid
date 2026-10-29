package uiterminal

import core "../../../core"
import content "../../../core/content"
import geometry "../../../core/geometry"
import coretext "../../../core/text"
import termhist "../../../terminal/history"
import terminalview "../../terminal"
import viewterminalmodel "../../terminal/model"
import input "../../input"
import viewmessages "../../messages"
import uiwidgets "../widgets"
import theme "../theme"
import "core:math"

// Resolve truthful status independently of row count and unfinished scan windows.
terminal_explorer_status_id :: proc(
    status: viewterminalmodel.History_Explorer_Status) -> content.Content_Message_Id {
    switch status {
    case .Closed, .Ready:
        return .Terminal_History_Ready
    case .Searching:
        return .Terminal_History_Searching
    case .Empty:
        return .Terminal_History_Empty
    case .Unavailable:
        return .Terminal_History_Unavailable
    case .Failed:
        return .Terminal_History_Failed
    case .Capacity:
        return .Terminal_History_Capacity
    }
    return .Invalid
}

// Prepare explorer input without committing ordinary Terminal scroll state.
terminal_prepare_explorer_frame :: proc(
    state: ^core.Euclid_General_State, frame: input.Input_Frame,
    layout: terminalview.Terminal_Draw_Layout, bounds: geometry.Rectangle,
    change: terminalview.Terminal_Geometry_Change) -> Terminal_Prepared_Frame {
    prepared: Terminal_Prepared_Frame = {
        available = true,
        bounds = bounds,
        layout = terminal_explorer_draw_layout(layout, bounds),
        geometry_change = change,
        explorer_active = true,
        explorer = terminal_explorer_layout(
            terminal_explorer_draw_layout(layout, bounds),
            viewmessages.shell_message(state, .Terminal_History_Query)),
    }
    surface := state^.ui_runtime.input.interaction_frame.terminal
    prepared.content_frame = ui_route_terminal_content_frame(surface, frame, bounds, {
        local_capture = state^.terminal.history_explorer.query_pointer_selecting,
    })
    terminal_explorer_reveal_selection(&state^.terminal.history_explorer,
        prepared.explorer)
    terminal_explorer_semantic_commands(state, prepared)
    terminal_explorer_update_pointer(state, &prepared)
    return prepared
}

// Publish fresh caret/row geometry after keyboard edits, joined results, or recall.
terminal_refresh_explorer_frame :: proc(
    state: ^core.Euclid_General_State, prepared: ^Terminal_Prepared_Frame) {
    if !prepared^.explorer_active && !state^.terminal.history_explorer.active {
        return
    }
    visual := terminal_prepare_visual(state, prepared^.bounds)
    visual.content_frame = prepared^.content_frame
    visual.geometry_change = prepared^.geometry_change
    visual.layout.terminal_focused =
        state^.ui_runtime.input.interaction_frame.terminal_focused
    prepared^ = visual
    if prepared^.explorer_active {
        terminal_explorer_reveal_selection(
            &state^.terminal.history_explorer, prepared^.explorer)
        explorer := &state^.terminal.history_explorer
        if explorer.help != .None {
            explorer.help_scroll_lines = clamp(explorer.help_scroll_lines, 0,
                terminal_explorer_help_scroll_max(state, prepared^))
        }
        terminal_explorer_clamp_preview(state, prepared^.explorer)
        terminal_explorer_prepare_caret(state, prepared)
    }
}

// Bound preview scrolling using exactly the wraps that will be drawn.
terminal_explorer_clamp_preview :: proc(
    state: ^core.Euclid_General_State, layout: Terminal_Explorer_Layout) {
    explorer := &state^.terminal.history_explorer
    if explorer.help != .None {
        return
    }
    if layout.compact || explorer^.preview_status != .Ready {
        explorer^.preview_scroll_lines = 0
        return
    }
    source := string(explorer^.preview_source[:explorer^.preview_length])
    lines := terminal_explorer_preview_line_count(source, layout.preview_columns)
    explorer^.preview_scroll_lines =
        clamp(explorer^.preview_scroll_lines, 0, max(0, lines - layout.preview_rows))
}

// Route candidate selection and independent wheels only through prepared regions.
terminal_explorer_update_pointer :: proc(
    state: ^core.Euclid_General_State, prepared: ^Terminal_Prepared_Frame) {
    explorer := &state^.terminal.history_explorer
    frame := prepared^.content_frame
    layout := prepared^.explorer
    point := uiwidgets.input_frame_mouse_position(frame)
    if layout.compact {
        explorer^.query_pointer_selecting = false
        return
    }
    if explorer.help != .None {
        terminal_explorer_query_pointer(explorer, prepared^)
        explorer.help_scroll_lines = max(0, explorer.help_scroll_lines +
            int(math.round(-frame.mouse_wheel_delta * theme.WHEEL_SCROLL_MULTIPLIER)))
        return
    }
    if .Left in frame.mouse_pressed {
        row := terminal_explorer_hit_row(layout, point, explorer^.list_scroll_rows,
            explorer^.row_count, prepared^.layout.line_height)
        if row >= 0 {
            _ = terminalview.history_explorer_select_candidate(explorer, row)
        }
    }
    terminal_explorer_query_pointer(explorer, prepared^)
    if frame.mouse_wheel_delta != 0 {
        step := int(math.round(-frame.mouse_wheel_delta * theme.WHEEL_SCROLL_MULTIPLIER))
        if geometry.rectangle_contains(layout.preview, point) {
            explorer^.preview_scroll_lines = max(0, explorer^.preview_scroll_lines + step)
        } else if geometry.rectangle_contains(layout.list, point) {
            terminal_explorer_scroll_list(explorer, layout, step)
        }
    }
}

// Move the loaded list independently; scan adjacent pages only at a working-page edge.
terminal_explorer_scroll_list :: proc(
    explorer: ^viewterminalmodel.History_Explorer_State,
    layout: Terminal_Explorer_Layout, delta: int) {
    maximum := max(0, explorer^.row_count - layout.row_capacity)
    next := explorer^.list_scroll_rows + delta
    if next < 0 && explorer^.list_scroll_rows == 0 {
        _ = terminalview.history_explorer_request_page(explorer, .Older)
    } else if next > maximum && explorer^.list_scroll_rows == maximum {
        _ = terminalview.history_explorer_request_page(explorer, .Newer)
    }
    explorer^.list_scroll_rows = clamp(next, 0, maximum)
}

// Apply query caret/selection hits without touching the suspended ordinary editor.
terminal_explorer_query_pointer :: proc(
    explorer: ^viewterminalmodel.History_Explorer_State,
    prepared: Terminal_Prepared_Frame) {
    frame := prepared.content_frame
    point := uiwidgets.input_frame_mouse_position(frame)
    query := &explorer^.query_editor
    if query^.preedit_active {
        return
    }
    press := .Left in frame.mouse_pressed &&
        geometry.rectangle_contains(prepared.explorer.query_text, point)
    if press || explorer^.query_pointer_selecting && .Left in frame.mouse_down {
        text := termhist.termhist_current_text(query)
        columns := max(1, int(prepared.explorer.query_text.width /
            prepared.layout.column_width))
        start := terminal_explorer_query_start(text, query^.cursor, columns)
        column := max(0, int(math.round((point.x - prepared.explorer.query_text.x) /
            prepared.layout.column_width)))
        offset := start + coretext.text_grapheme_boundary_for_column(text[start:], column)
        _ = termhist.termhist_set_cursor(query, offset,
            !press || .Shift in frame.mouse_modifiers)
        explorer^.query_pointer_selecting = true
    }
    if .Left in frame.mouse_released || .Left not_in frame.mouse_down {
        explorer^.query_pointer_selecting = false
    }
}

// Project a horizontally clipped query selection and IME insertion point.
terminal_explorer_prepare_caret :: proc(
    state: ^core.Euclid_General_State, prepared: ^Terminal_Prepared_Frame) {
    query := &state^.terminal.history_explorer.query_editor
    text := termhist.termhist_current_text(query)
    rect := prepared^.explorer.query_text
    if prepared^.explorer.compact {
        rect = prepared^.explorer.bounds
        rect.height = prepared^.layout.line_height
    }
    cell := prepared^.layout.column_width
    start := terminal_explorer_query_start(text, query^.cursor, int(rect.width / cell))
    prepared^.explorer.query_start = start
    cursor := coretext.text_grapheme_column(text[start:], max(0, query^.cursor - start))
    anchor := coretext.text_grapheme_column(text, query^.anchor) -
        coretext.text_grapheme_column(text, start)
    caret: geometry.Rectangle = {rect.x + f32(cursor)*cell, rect.y, 1, rect.height}
    if query^.preedit_active {
        preedit := string(query^.preedit[:query^.preedit_length])
        caret.x += f32(coretext.text_grapheme_column(
            preedit, query^.preedit_selection_start))*cell
    }
    caret.x = clamp(caret.x, rect.x, rect.x + max(0, rect.width - 1))
    prepared^.editable_geometry = {
        control = {rect, rect},
        caret = caret,
        selection = {rect.x + f32(min(cursor, anchor))*cell, rect.y,
            f32(abs(cursor - anchor))*cell, rect.height},
        cursor_column = cursor,
        anchor_column = anchor,
    }
    prepared^.editable_descriptor = {
        id = terminal_semantic_id(state),
        region = .Presentation,
        label = viewmessages.shell_message(state, .Terminal_History_Query),
        text = text,
        mode = .Editable,
        cursor_byte = query^.cursor,
        anchor_byte = query^.anchor,
        content_revision = termhist.termhist_content_revision(query),
    }
}

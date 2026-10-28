package uiterminal

import core "../../../core"
import termhist "../../../terminal/history"
import terminalview "../../terminal"
import viewterminalmodel "../../terminal/model"
import viewmessages "../../messages"
import viewmodel "../model"
import uisemantics "../semantics"
import "core:math"

// Identify a candidate only while its exact published working page remains current.
terminal_explorer_candidate_id :: proc(
    state: ^core.Euclid_General_State, index: int) -> viewmodel.Ui_Node_Id {
    return {
        domain = .Terminal,
        local_id = u64(100 + index),
        generation = state^.terminal.history_explorer.next_search_request_id,
    }
}

// Preserve Terminal keyboard ownership while exposing the query as editable text.
register_terminal_explorer_semantics :: proc(
    state: ^core.Euclid_General_State, prepared: Terminal_Prepared_Frame) {
    explorer := &state^.terminal.history_explorer
    query := &explorer^.query_editor
    id := terminal_semantic_id(state)
    selected: viewmodel.Ui_Node_Id
    if !prepared.explorer.compact &&
        explorer^.selected_index >= explorer^.list_scroll_rows &&
        explorer^.selected_index <
            explorer^.list_scroll_rows + prepared.explorer.row_capacity {
        selected = terminal_explorer_candidate_id(state, explorer^.selected_index)
    }
    _ = uisemantics.semantic_register_control(state^.ui_runtime.semantic_focus, {
        id = id,
        active_descendant = selected,
        role = .Terminal,
        states = {.Visible, .Enabled, .Focusable, .Tab_Stop},
        actions = {.Focus, .Replace_Selected_Text, .Set_Text_Selection},
        region = .Presentation,
        bounds = prepared.bounds,
        clip_bounds = prepared.explorer.bounds,
        text_input_area = prepared.editable_geometry.caret,
        label = viewmessages.shell_message(state, .Terminal_History_Query),
        value = termhist.termhist_current_text(query),
        text_cursor_byte = query^.cursor,
        text_anchor_byte = query^.anchor,
        text_present = true,
    })
    terminal_explorer_register_rows(state, prepared)
    terminal_explorer_register_status(state, prepared)
    terminal_explorer_register_preview(state, prepared)
}

// Expose visible candidates in the same chronological order and bounds as drawing.
terminal_explorer_register_rows :: proc(
    state: ^core.Euclid_General_State, prepared: Terminal_Prepared_Frame) {
    if prepared.explorer.compact {
        return
    }
    explorer := &state^.terminal.history_explorer
    end := min(explorer^.row_count,
        explorer^.list_scroll_rows + prepared.explorer.row_capacity)
    for index in explorer^.list_scroll_rows..<end {
        row := explorer^.rows[index]
        buffer: [4096]u8
        summary := terminal_explorer_text_row(string(explorer^.summaries[
            row.summary_offset:row.summary_offset + row.summary_length]),
            0, 256, buffer[:], true)
        states: viewmodel.Ui_Node_State = {.Visible, .Enabled, .Read_Only}
        if index == explorer^.selected_index {
            states += {.Selected}
        }
        _ = uisemantics.semantic_register_control(state^.ui_runtime.semantic_focus, {
            id = terminal_explorer_candidate_id(state, index),
            parent = terminal_semantic_id(state),
            role = .Tree_Item,
            states = states,
            actions = {.Select},
            bounds = terminal_explorer_row_rect(prepared.explorer,
                index - explorer^.list_scroll_rows, prepared.layout.line_height),
            clip_bounds = prepared.explorer.list,
            label = summary.text,
            position_in_set = u32(index + 1),
        })
    }
}

// Announce explicit status, including compact-size instructions, without fake totals.
terminal_explorer_register_status :: proc(
    state: ^core.Euclid_General_State, prepared: Terminal_Prepared_Frame) {
    id := terminal_semantic_id(state)
    id.local_id = 2
    message := terminal_explorer_status_id(state^.terminal.history_explorer.status)
    rect := prepared.explorer.status
    if prepared.explorer.compact {
        message = .Terminal_History_Compact
        rect = prepared.explorer.bounds
    }
    states: viewmodel.Ui_Node_State = {.Visible, .Enabled, .Read_Only}
    if state^.terminal.history_explorer.status == .Searching {
        states += {.Busy}
    }
    _ = uisemantics.semantic_register_control(state^.ui_runtime.semantic_focus, {
        id = id,
        parent = terminal_semantic_id(state),
        role = .Status,
        states = states,
        bounds = rect,
        clip_bounds = rect,
        label = viewmessages.shell_message(state, message),
    })
}

// Publish the independent preview range without copying complete retained source.
terminal_explorer_register_preview :: proc(
    state: ^core.Euclid_General_State, prepared: Terminal_Prepared_Frame) {
    if prepared.explorer.compact {
        return
    }
    explorer := &state^.terminal.history_explorer
    id := terminal_semantic_id(state)
    id.local_id = 1
    maximum := 0
    if explorer^.preview_status == .Ready {
        maximum = max(0, terminal_explorer_preview_line_count(
            string(explorer^.preview_source[:explorer^.preview_length]),
            prepared.explorer.preview_columns) - prepared.explorer.preview_rows)
    }
    _ = uisemantics.semantic_register_control(state^.ui_runtime.semantic_focus, {
        id = id,
        parent = terminal_semantic_id(state),
        role = .Document,
        states = {.Visible, .Enabled, .Read_Only},
        actions = {.Scroll},
        bounds = prepared.explorer.preview,
        clip_bounds = prepared.explorer.preview,
        label = viewmessages.shell_message(state, .Terminal_History_Preview),
        numeric_range = {0, f64(maximum), f64(explorer^.preview_scroll_lines),
            1, .Vertical, true},
    })
}

// Apply addressed query, candidate, and preview actions only to current explorer owners.
terminal_explorer_semantic_commands :: proc(
    state: ^core.Euclid_General_State, prepared: Terminal_Prepared_Frame) {
    semantic := state^.ui_runtime.semantic_focus
    if semantic == nil {
        return
    }
    explorer := &state^.terminal.history_explorer
    for command in semantic^.commands[:semantic^.command_count] {
        if command.target == terminal_semantic_id(state) {
            terminal_explorer_query_command(explorer, command)
        } else if command.target.domain == .Terminal && command.target.local_id == 1 &&
            command.target.generation == state^.terminal.animation_generation {
            if command.kind == .Set_Scroll_Value &&
               !math.is_nan(command.numeric_value) &&
               !math.is_inf(command.numeric_value) {
                explorer^.preview_scroll_lines = int(clamp(
                    command.numeric_value, 0, f64(explorer^.preview_length)))
            } else if command.kind == .Scroll_Page {
                explorer^.preview_scroll_lines = max(0, explorer^.preview_scroll_lines +
                    int(command.amount)*prepared.explorer.preview_rows)
            }
        } else if command.kind == .Select && command.target.local_id >= 100 &&
            command.target.local_id < u64(100 + explorer^.row_count) {
            index := int(command.target.local_id - 100)
            if command.target == terminal_explorer_candidate_id(state, index) {
                _ = terminalview.history_explorer_select_candidate(explorer, index)
            }
        }
    }
}

// Route accessibility text changes through the same bounded normalized query editor.
terminal_explorer_query_command :: proc(
    explorer: ^viewterminalmodel.History_Explorer_State,
    command: viewmodel.Ui_Focus_Command) {
    query := &explorer^.query_editor
    if command.kind == .Set_Text_Selection {
        _ = termhist.termhist_set_cursor(query, int(command.selection_anchor))
        _ = termhist.termhist_set_cursor(query, int(command.selection_focus), true)
        return
    }
    if command.kind != .Replace_Text && command.kind != .Replace_Selected_Text {
        return
    }
    buffer: [1024]u8
    payload := command
    text, valid := terminalview.history_explorer_normalize_paste(
        string(payload.payload[:payload.payload_length]), buffer[:])
    if !valid {
        explorer^.status = .Capacity
        explorer^.status_failure.kind = .Capacity
        return
    }
    if command.kind == .Replace_Text {
        _ = termhist.termhist_set_cursor(query, 0)
        _ = termhist.termhist_set_cursor(query, query^.text_len, true)
    }
    _ = terminalview.history_explorer_insert_query(explorer, text)
}

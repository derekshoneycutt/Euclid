#+test
package uiterminal

import content "../../../core/content"
import core "../../../core"
import protocol "../../../core/protocol"
import termhist "../../../terminal/history"
import termhiststore "../../../terminal/history/store"
import terminalview "../../terminal"
import viewterminalmodel "../../terminal/model"
import viewmodel "../model"
import uisemantics "../semantics"
import "core:testing"

// Check stable line-based layout, isolated columns, and minimum size at every text scale.
@(test)
terminal_explorer_layout_scales_without_overlap :: proc(t: ^testing.T) {
    percentages := [?]int{100, 125, 150, 175}
    for percent in percentages {
        scale := terminalview.terminal_text_scale_factor(percent)
        draw: terminalview.Terminal_Draw_Layout = {
            padded_bounds = {10, 20, 800*scale, 600*scale},
            column_width = 10*scale,
            line_height = 20*scale,
        }
        layout := terminal_explorer_layout(draw, "History search: ")
        testing.expect(t, !layout.compact)
        testing.expect_value(t, layout.row_capacity, 15)
        testing.expect_value(t, layout.preview_rows, 9)
        testing.expect(t, layout.list.y + layout.list.height <= layout.status.y)
        testing.expect(t, layout.preview.y + layout.preview.height <= layout.hints.y)
        testing.expect(t, layout.hints.y + layout.hints.height <=
            draw.padded_bounds.y + draw.padded_bounds.height)
        testing.expect(t, layout.list.x + 2*draw.column_width +
            layout.source_width < layout.mode_x)
        testing.expect(t, layout.mode_x < layout.age_x)
        draw.padded_bounds.height = 8*draw.line_height
        testing.expect(t, terminal_explorer_layout(draw, "").compact)
        draw.padded_bounds = {0, 0, 35*draw.column_width, 30*draw.line_height}
        testing.expect(t, terminal_explorer_layout(draw, "").compact)
    }
}

// Pointer hits use the exact row rectangles, scroll offset, and exclusive lower edge.
@(test)
terminal_explorer_row_hits_share_drawing_geometry :: proc(t: ^testing.T) {
    layout := terminal_explorer_layout({
        padded_bounds = {10, 20, 800, 600},
        column_width = 10,
        line_height = 20,
    }, "History search: ")
    row := terminal_explorer_row_rect(layout, 2, 20)
    testing.expect_value(t,
        terminal_explorer_hit_row(layout, {row.x + 1, row.y + 1}, 5, 32, 20), 7)
    testing.expect_value(t, terminal_explorer_hit_row(layout,
        {row.x, layout.list.y + layout.list.height}, 5, 32, 20), -1)
    testing.expect_value(t,
        terminal_explorer_hit_row(layout, {row.x - 1, row.y}, 5, 32, 20), -1)
}

// Safe presentation preserves complete Unicode clusters and makes controls inert.
@(test)
terminal_explorer_text_clips_and_sanitizes :: proc(t: ^testing.T) {
    storage: [128]u8
    row := terminal_explorer_text_row("e\u0301界x", 0, 3, storage[:])
    testing.expect_value(t, row.text, "e\u0301界")
    testing.expect_value(t, row.next, len("e\u0301界"))
    row = terminal_explorer_text_row("\x1b[31m\r\nx\tz", 0, 40, storage[:], true)
    testing.expect_value(t, row.text, "?[31m \\ x    z")
    row = terminal_explorer_text_row("界", 0, 1, storage[:])
    testing.expect_value(t, row.text, "?")
    testing.expect_value(t, row.next, len("界"))
    row = terminal_explorer_text_row("x\u202ey", 0, 10, storage[:])
    testing.expect_value(t, row.text, "x?y")
}

// Preview wrapping retains CRLF, empty hard lines, indentation, and trailing newlines.
@(test)
terminal_explorer_preview_wrap_boundaries :: proc(t: ^testing.T) {
    storage: [128]u8
    source := "ab界\r\n\n  x\n"
    first := terminal_explorer_text_row(source, 0, 4, storage[:])
    testing.expect_value(t, first.text, "ab界")
    second := terminal_explorer_text_row(source, first.next, 4, storage[:])
    testing.expect_value(t, second.text, "")
    third := terminal_explorer_text_row(source, second.next, 4, storage[:])
    testing.expect_value(t, third.text, "  x")
    testing.expect_value(t, terminal_explorer_preview_line_count(source, 4), 4)
    testing.expect_value(t, terminal_explorer_preview_line_count("abcdef", 3), 2)
    testing.expect_value(t, terminal_explorer_preview_line_count("", 3), 1)
}

// A query's horizontal viewport exposes its caret without splitting a grapheme.
@(test)
terminal_explorer_query_scroll_is_grapheme_safe :: proc(t: ^testing.T) {
    text := "e\u0301界abcdef"
    start := terminal_explorer_query_start(text, len(text), 5)
    testing.expect_value(t, text[start:], "cdef")
    testing.expect_value(t, terminal_explorer_query_start(text, 0, 5), 0)
}

// Selection reveal does not undo an independent list wheel until selection changes.
@(test)
terminal_explorer_independent_list_scroll :: proc(t: ^testing.T) {
    explorer: viewterminalmodel.History_Explorer_State = {
        row_count = 32,
        selected_index = 31,
        list_visible_selection = -1,
    }
    layout: Terminal_Explorer_Layout = {
        row_capacity = 5,
    }
    terminal_explorer_reveal_selection(&explorer, layout)
    testing.expect_value(t, explorer.list_scroll_rows, 27)
    terminal_explorer_scroll_list(&explorer, layout, -4)
    terminal_explorer_reveal_selection(&explorer, layout)
    testing.expect_value(t, explorer.list_scroll_rows, 23)
    explorer.selected_index = 0
    terminal_explorer_reveal_selection(&explorer, layout)
    testing.expect_value(t, explorer.list_scroll_rows, 0)
}

// Future and extreme timestamps never underflow or widen the reserved age column.
@(test)
terminal_explorer_age_and_mode_columns :: proc(t: ^testing.T) {
    id, value := terminal_explorer_age_value(1000, 2000)
    testing.expect_value(t, id, content.Content_Message_Id.Terminal_History_Age_Now)
    testing.expect_value(t, value, i64(0))
    id, value = terminal_explorer_age_value(121000, 1000)
    testing.expect_value(t, id, content.Content_Message_Id.Terminal_History_Age_Minutes)
    testing.expect_value(t, value, i64(2))
    id, value = terminal_explorer_age_value(max(i64), min(i64))
    testing.expect_value(t, value, i64(99999))
    for mode in protocol.Evaluation_Mode {
        testing.expect(t, len(terminal_explorer_mode(mode, true)) <= 5)
        testing.expect(t, len(terminal_explorer_mode(mode, false)) <= 2)
    }
}

// Candidate clicks select only; preview wheels cannot alter ordinary scrollback.
@(test)
terminal_explorer_pointer_preserves_prompt_and_scroll :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    rows: [2]termhiststore.History_Candidate_Summary
    state^.terminal.history_explorer = {
        active = true,
        rows = rows[:],
        row_count = 2,
        selected_index = 0,
    }
    state^.terminal.scroll_offset_y = 123
    prepared: Terminal_Prepared_Frame = {
        layout = {
            column_width = 10,
            line_height = 20,
        },
        explorer = terminal_explorer_layout({
            padded_bounds = {0, 0, 800, 600},
            column_width = 10,
            line_height = 20,
        }, "History search: "),
    }
    terminal_explorer_test_pointer(t, state, &prepared)
}

// Exercise prepared row selection and preview-only scrolling with explicit pointer facts.
terminal_explorer_test_pointer :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State,
    prepared: ^Terminal_Prepared_Frame) {
    rect := terminal_explorer_row_rect(prepared^.explorer, 1, 20)
    prepared^.content_frame.mouse_position = {rect.x + 1, rect.y + 1}
    prepared^.content_frame.mouse_pressed = {.Left}
    terminal_explorer_update_pointer(state, prepared)
    testing.expect_value(t, state^.terminal.history_explorer.selected_index, 1)
    testing.expect(t, state^.terminal.history_explorer.preview_pending)
    testing.expect(t, !state^.terminal.history_explorer.accept_requested)
    prepared^.content_frame.mouse_pressed = {}
    rect = prepared^.explorer.preview
    prepared^.content_frame.mouse_position = {rect.x + 1, rect.y + 1}
    prepared^.content_frame.mouse_wheel_delta = -1
    terminal_explorer_update_pointer(state, prepared)
    testing.expect(t, state^.terminal.history_explorer.preview_scroll_lines > 0)
    testing.expect_value(t, state^.terminal.scroll_offset_y, f32(123))
}

// Build a ready explorer with isolated messages and semantic storage for UI contracts.
terminal_explorer_test_state :: proc(t: ^testing.T) -> ^core.Euclid_General_State {
    state := new(core.Euclid_General_State, context.allocator)
    state^.content_service = new(content.Content_Service, context.allocator)
    service := state^.content_service
    service^.active_generation = content.content_message_test_generation(t)
    service^.running = true
    service^.index_generation = service^.active_generation.generation
    state^.ui_runtime.semantic_focus = &state^.semantic_focus
    testing.expect(t, terminalview.terminal_init(&state^.terminal))
    state^.terminal.banner_ready = true
    state^.terminal.history_explorer_open_allowed = true
    testing.expect(t, terminalview.history_explorer_open(&state^.terminal))
    return state
}

// Release every synthetic owner without entering the application lifecycle.
terminal_explorer_test_destroy :: proc(state: ^core.Euclid_General_State) {
    terminalview.terminal_destroy(&state^.terminal, context.allocator)
    viewmodel.ui_semantic_focus_destroy(&state^.semantic_focus)
    content.content_message_test_destroy(state^.content_service^.active_generation)
    free(state^.content_service, context.allocator)
    free(state, context.allocator)
}

// Supply deterministic typography without depending on a GPU or a prepared font cache.
terminal_explorer_test_prepared :: proc() -> Terminal_Prepared_Frame {
    return {
        available = true,
        bounds = {0, 0, 800, 600},
        layout = {
            column_width = 10,
            line_height = 20,
            terminal_focused = true,
        },
        explorer_active = true,
        explorer = terminal_explorer_layout({
            padded_bounds = {0, 0, 800, 600},
            column_width = 10,
            line_height = 20,
        }, "History search: "),
    }
}

// Query semantics replace the ordinary surface and preserve the same global focus stop.
@(test)
terminal_explorer_semantics_own_query_and_restore_focus :: proc(t: ^testing.T) {
    state := terminal_explorer_test_state(t)
    defer terminal_explorer_test_destroy(state)
    testing.expect(t, termhist.termhist_insert_text(state^.terminal.history, "hidden"))
    testing.expect(t, terminalview.history_explorer_insert_query(
        &state^.terminal.history_explorer, "visible"))
    prepared := terminal_explorer_test_prepared()
    terminal_explorer_prepare_caret(state, &prepared)
    testing.expect(t, uisemantics.semantic_begin(&state^.semantic_focus))
    register_terminal_explorer_semantics(state, prepared)
    id := terminal_semantic_id(state)
    testing.expect(t,
        uisemantics.semantic_request_pointer_focus(&state^.semantic_focus, id))
    testing.expect_value(t, uisemantics.semantic_publish(&state^.semantic_focus),
        viewmodel.Ui_Semantic_Status.Ok)
    snapshot := uisemantics.semantic_snapshot(&state^.semantic_focus)
    index := uisemantics.semantic_node_index(snapshot, id)
    testing.expect_value(t, snapshot^.nodes[index].role, viewmodel.Ui_Node_Role.Terminal)
    testing.expect_value(t, snapshot^.nodes[index].text_cursor_byte, u32(len("visible")))
    testing.expect(t, .Replace_Selected_Text in snapshot^.nodes[index].actions)
    terminalview.history_explorer_close(&state^.terminal)
    testing.expect(t, uisemantics.semantic_begin(&state^.semantic_focus))
    register_terminal_semantics(state, prepared.bounds, {})
    testing.expect_value(t, uisemantics.semantic_publish(&state^.semantic_focus),
        viewmodel.Ui_Semantic_Status.Ok)
    testing.expect_value(t, state^.semantic_focus.logical_focus, id)
    testing.expect_value(t,
        termhist.termhist_current_text(state^.terminal.history), "hidden")
}

// The prepared caret follows the query and IME selection rather than the hidden prompt.
@(test)
terminal_explorer_query_ime_caret_is_prepared :: proc(t: ^testing.T) {
    state := terminal_explorer_test_state(t)
    defer terminal_explorer_test_destroy(state)
    query := &state^.terminal.history_explorer.query_editor
    testing.expect(t, terminalview.history_explorer_insert_query(
        &state^.terminal.history_explorer, "abc"))
    prepared := terminal_explorer_test_prepared()
    terminal_explorer_prepare_caret(state, &prepared)
    x := prepared.editable_geometry.caret.x
    testing.expect(t, termhist.termhist_update_preedit(query, "界x", 1, 0))
    terminal_explorer_prepare_caret(state, &prepared)
    testing.expect_value(t, prepared.editable_geometry.caret.x, x + 20)
    testing.expect_value(t, prepared.editable_descriptor.text, "abc")
    testing.expect(t,
        prepared.editable_geometry.caret.x >= prepared.explorer.query_text.x)
}

// UI semantic edits share normalization and never mutate the suspended ordinary draft.
@(test)
terminal_explorer_accessible_query_and_stale_candidate :: proc(t: ^testing.T) {
    state := terminal_explorer_test_state(t)
    defer terminal_explorer_test_destroy(state)
    testing.expect(t, termhist.termhist_insert_text(state^.terminal.history, "draft"))
    command: viewmodel.Ui_Focus_Command = {
        kind = .Replace_Text,
        payload_length = 4,
    }
    copy(command.payload[:], "a\r\nb")
    terminal_explorer_query_command(&state^.terminal.history_explorer, command)
    testing.expect_value(t, termhist.termhist_current_text(
        &state^.terminal.history_explorer.query_editor), "a b")
    testing.expect_value(t,
        termhist.termhist_current_text(state^.terminal.history), "draft")
    explorer := &state^.terminal.history_explorer
    explorer^.row_count = 2
    explorer^.selected_index = 0
    explorer^.next_search_request_id = 2
    command = {
        target = terminal_explorer_candidate_id(state, 1),
        kind = .Select,
    }
    explorer^.next_search_request_id = 3
    state^.semantic_focus.commands[0] = command
    state^.semantic_focus.command_count = 1
    terminal_explorer_semantic_commands(state, terminal_explorer_test_prepared())
    testing.expect_value(t, explorer^.selected_index, 0)
}

// Compact and independently scrolled lists cannot advertise an absent active descendant.
@(test)
terminal_explorer_semantics_do_not_reference_hidden_candidates :: proc(t: ^testing.T) {
    state := terminal_explorer_test_state(t)
    defer terminal_explorer_test_destroy(state)
    explorer := &state^.terminal.history_explorer
    explorer^.row_count = 32
    explorer^.selected_index = 0
    explorer^.list_scroll_rows = 10
    prepared := terminal_explorer_test_prepared()
    testing.expect(t, uisemantics.semantic_begin(&state^.semantic_focus))
    register_terminal_explorer_semantics(state, prepared)
    testing.expect_value(t, uisemantics.semantic_publish(&state^.semantic_focus),
        viewmodel.Ui_Semantic_Status.Ok)
    terminal_explorer_test_expect_no_descendant(t, state)
    prepared.explorer.compact = true
    terminal_explorer_prepare_caret(state, &prepared)
    testing.expect(t, prepared.editable_geometry.caret.height > 0)
    testing.expect(t, prepared.editable_geometry.caret.width > 0)
    testing.expect(t, uisemantics.semantic_begin(&state^.semantic_focus))
    register_terminal_explorer_semantics(state, prepared)
    testing.expect_value(t, uisemantics.semantic_publish(&state^.semantic_focus),
        viewmodel.Ui_Semantic_Status.Ok)
    terminal_explorer_test_expect_no_descendant(t, state)
}

// Verify the focus owner has no reference to a candidate outside its published children.
terminal_explorer_test_expect_no_descendant :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State) {
    snapshot := uisemantics.semantic_snapshot(&state^.semantic_focus)
    index := uisemantics.semantic_node_index(snapshot, terminal_semantic_id(state))
    testing.expect(t, index >= 0)
    testing.expect_value(t, snapshot^.nodes[index].active_descendant,
        viewmodel.Ui_Node_Id{})
}

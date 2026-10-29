#+test
package uiterminal

import content "../../../core/content"
import color "../../../core/color"
import termhistsearch "../../../terminal/history/search"
import terminalview "../../terminal"
import viewterminalmodel "../../terminal/model"
import viewmodel "../model"
import uisemantics "../semantics"
import native "../../native"
import theme "../theme"
import "core:testing"

// Original ranges map through expanded tabs, control substitutions, flattened breaks, and combining marks.
@(test)
terminal_explorer_matches_follow_safe_fragments :: proc(t: ^testing.T) {
    source := "a\t\x1b\n  e\u0301"
    offsets := [?]int{1, 2, 3, 6}
    for offset in offsets {
        fragment := terminal_explorer_text_fragment(source, offset, true)
        ranges := [?]termhistsearch.Search_Range{{offset, offset + 1}}
        testing.expect(t, terminal_explorer_fragment_matches(fragment, ranges[:]))
        ranges[0] = {fragment.source_end, fragment.source_end + 1}
        testing.expect(t, !terminal_explorer_fragment_matches(fragment, ranges[:]))
    }
    buffer: [32]u8
    first := terminal_explorer_text_row(source, 0, 5, buffer[:])
    testing.expect_value(t, first.next, 2)
    second := terminal_explorer_text_row(source, first.next, 5, buffer[:])
    testing.expect(t, second.hard_break && second.next == 4)
    combining := terminal_explorer_text_fragment(source, 6)
    ranges := [?]termhistsearch.Search_Range{{7, 9}}
    testing.expect(t, terminal_explorer_fragment_matches(combining, ranges[:]))
    testing.expect_value(t, combining.text, "e\u0301")
}

// Match paint is a separate overline, leaving syntax underline and background ownership intact.
@(test)
terminal_explorer_match_rail_encodes_without_glyphs :: proc(t: ^testing.T) {
    vertices: [32]native.Draw_Vertex
    indices: [48]u32
    batches: [8]native.Draw_Batch
    commands: [8]native.Draw_Command
    encoder: native.Draw_Encoder
    testing.expect(t, native.draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:], commands[:], nil}, {400, 200}, {400, 200}))
    ranges := [?]termhistsearch.Search_Range{{0, 1}}
    draw: Terminal_Explorer_Draw = {
        encoder = &encoder,
        prepared = {
            layout = {
                column_width = 10,
            },
        },
    }
    terminal_explorer_draw_match(draw, {
        matches = ranges[:],
    }, {
        source_start = 0,
        source_end = 1,
        columns = 4,
    }, {10, 20})
    testing.expect_value(t, encoder.vertex_count, 4)
    testing.expect_value(t, vertices[0].color, theme.appearance_color(false, .Text))
    before := encoder.vertex_count
    terminalview.terminal_syntax_decorations(&encoder, {
        foreground = {1, 2, 3, 255},
        underline_color = {7, 8, 9, 255},
        underline = .Double,
    }, {10, 20}, 40)
    testing.expect_value(t, encoder.vertex_count, before + 8)
    testing.expect_value(t, vertices[before].color, color.Color_RGBA8{7, 8, 9, 255})
}

// Help removes hidden candidate actions while exposing its full localized text.
@(test)
terminal_explorer_help_semantics_hide_candidates :: proc(t: ^testing.T) {
    state := terminal_explorer_test_state(t)
    defer terminal_explorer_test_destroy(state)
    explorer := &state.terminal.history_explorer
    testing.expect(t, terminalview.history_explorer_insert_query(explorer, "??"))
    explorer.row_count, explorer.selected_index = 1, 0
    prepared := terminal_explorer_test_prepared()
    testing.expect(t, uisemantics.semantic_begin(&state.semantic_focus))
    register_terminal_explorer_semantics(state, prepared)
    testing.expect_value(t, uisemantics.semantic_publish(&state.semantic_focus),
        viewmodel.Ui_Semantic_Status.Ok)
    snapshot := uisemantics.semantic_snapshot(&state.semantic_focus)
    testing.expect(t, uisemantics.semantic_node_index(
        snapshot, terminal_explorer_candidate_id(state, 0)) < 0)
    id := terminal_semantic_id(state)
    id.local_id = 10
    index := uisemantics.semantic_node_index(snapshot, id)
    testing.expect(t, index >= 0)
    testing.expect_value(t, snapshot.nodes[index].role, viewmodel.Ui_Node_Role.Text_Run)
    testing.expect_value(t, len(terminal_explorer_help_sections(explorer.help)), 15)
}

// Skips, execution failures, and nonblocking range failures have distinct truthful messages.
@(test)
terminal_explorer_match_statuses_are_distinct :: proc(t: ^testing.T) {
    explorer: viewterminalmodel.History_Explorer_State = {
        status = .Ready,
        skipped_regex_count = 1,
    }
    testing.expect_value(t, terminal_explorer_status_message(&explorer),
        content.Content_Message_Id.Terminal_History_Skipped)
    explorer.status = .Failed
    explorer.status_failure.kind = .Sqlite
    testing.expect_value(t, terminal_explorer_status_message(&explorer),
        content.Content_Message_Id.Terminal_History_Sql_Failed)
    explorer.status_failure.kind = .Search
    explorer.status_failure.search_error = .Out_Of_Memory
    testing.expect_value(t, terminal_explorer_status_message(&explorer),
        content.Content_Message_Id.Terminal_History_Resource_Failed)
    explorer.status, explorer.preview_status = .Ready, .Ready
    explorer.preview_matches.failure.kind = .Search
    testing.expect_value(t, terminal_explorer_status_message(&explorer),
        content.Content_Message_Id.Terminal_History_Ranges_Failed)
}

// Accessible scrolling is finite and bounded, including page changes from stale scroll values.
@(test)
terminal_explorer_scroll_commands_are_bounded :: proc(t: ^testing.T) {
    value := 5
    terminal_explorer_apply_scroll(&value,
        {
            kind = .Set_Scroll_Value,
            numeric_value = transmute(f64)u64(0x7ff0000000000000),
        }, 20, 4)
    testing.expect_value(t, value, 5)
    terminal_explorer_apply_scroll(&value,
        {
            kind = .Set_Scroll_Value,
            numeric_value = transmute(f64)u64(0x7ff8000000000000),
        }, 20, 4)
    testing.expect_value(t, value, 5)
    terminal_explorer_apply_scroll(&value,
        {
            kind = .Set_Scroll_Value,
            numeric_value = 1e100,
        }, 20, 4)
    testing.expect_value(t, value, 20)
    terminal_explorer_apply_scroll(&value,
        {
            kind = .Scroll_Page,
            amount = -1,
        }, 20, 4)
    testing.expect_value(t, value, 16)
    terminal_explorer_apply_scroll(&value,
        {
            kind = .Scroll_Page,
            amount = -100,
        }, 20, 4)
    testing.expect_value(t, value, 0)
}

// Compact help exposes restoration text, never an invisible scrollable document or candidates.
@(test)
terminal_explorer_compact_help_has_no_hidden_actions :: proc(t: ^testing.T) {
    state := terminal_explorer_test_state(t)
    defer terminal_explorer_test_destroy(state)
    explorer := &state.terminal.history_explorer
    testing.expect(t, terminalview.history_explorer_insert_query(explorer, "?"))
    explorer.row_count, explorer.selected_index = 1, 0
    prepared := terminal_explorer_test_prepared()
    prepared.explorer.compact = true
    testing.expect(t, uisemantics.semantic_begin(&state.semantic_focus))
    register_terminal_explorer_semantics(state, prepared)
    testing.expect_value(t, uisemantics.semantic_publish(&state.semantic_focus),
        viewmodel.Ui_Semantic_Status.Ok)
    snapshot := uisemantics.semantic_snapshot(&state.semantic_focus)
    index := uisemantics.semantic_node_index(snapshot, terminal_explorer_help_id(state))
    testing.expect(t, index >= 0)
    testing.expect(t, .Scroll not_in snapshot.nodes[index].actions)
    testing.expect(t, snapshot.nodes[index].value_length > 0)
    testing.expect(t, uisemantics.semantic_node_index(
        snapshot, terminal_explorer_candidate_id(state, 0)) < 0)
}

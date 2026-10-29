package uiterminal

import core "../../../core"
import content "../../../core/content"
import geometry "../../../core/geometry"
import viewterminalmodel "../../terminal/model"
import viewmessages "../../messages"
import uisemantics "../semantics"
import viewmodel "../model"
import theme "../theme"

@(rodata)
terminal_explorer_help_section_ids := [?]content.Content_Message_Id{
    .Terminal_History_Help_Short, .Terminal_History_Help_Prefixes,
    .Terminal_History_Help_Modes, .Terminal_History_Help_Matches,
    .Terminal_History_Help_Usage, .Terminal_History_Help_Keys,
    .Terminal_History_Help_Grammar, .Terminal_History_Help_Case,
    .Terminal_History_Help_Escapes, .Terminal_History_Help_Skips,
    .Terminal_History_Help_Fuzzy, .Terminal_History_Help_Pages,
    .Terminal_History_Help_Scroll, .Terminal_History_Help_Limits,
    .Terminal_History_Help_Duplicates,
}

// Localized sections share one virtual document rather than a second candidate/source page.
terminal_explorer_help_sections :: proc(
    help: viewterminalmodel.History_Explorer_Help) -> []content.Content_Message_Id {
    if help == .Extended {
        return terminal_explorer_help_section_ids[:]
    }
    return terminal_explorer_help_section_ids[:6]
}

// Reuse the whole explorer body below its query line, leaving a separate footer.
terminal_explorer_help_rect :: proc(
    prepared: Terminal_Prepared_Frame) -> geometry.Rectangle {
    rect := prepared.explorer.bounds
    rect.y += 2*prepared.layout.line_height
    rect.height = max(0, rect.height - 3*prepared.layout.line_height)
    return rect
}

// Count the same safe wraps used by drawing, with one blank line between sections.
terminal_explorer_help_lines :: proc(
    state: ^core.Euclid_General_State, columns: int) -> int {
    count := 0
    for id in terminal_explorer_help_sections(state.terminal.history_explorer.help) {
        count += terminal_explorer_preview_line_count(
            viewmessages.shell_message(state, id), columns) + 1
    }
    return max(0, count - 1)
}

// Share the actual wrapped help boundary between drawing and accessibility scroll commands.
terminal_explorer_help_scroll_max :: proc(
    state: ^core.Euclid_General_State, prepared: Terminal_Prepared_Frame) -> int {
    rect := terminal_explorer_help_rect(prepared)
    columns := max(1, int(rect.width / prepared.layout.column_width))
    rows := max(1, int(rect.height / prepared.layout.line_height))
    return max(0, terminal_explorer_help_lines(state, columns) - rows)
}

// Help preserves query editing and exposes a readable restoration hint even in compact panes.
terminal_explorer_draw_help :: proc(draw: Terminal_Explorer_Draw) {
    if draw.prepared.explorer.compact {
        terminal_explorer_draw_compact_message(draw, .Terminal_History_Help_Compact)
        return
    }
    terminal_explorer_draw_query(draw)
    terminal_explorer_draw_help_body(draw)
    terminal_explorer_draw_text(draw,
        viewmessages.shell_message(draw.state, .Terminal_History_Help_Hints),
        draw.prepared.explorer.hints, theme.draw_color(draw.encoder, .Text))
}

// Draw a bounded visible portion of localized help without allocating joined text.
terminal_explorer_draw_help_body :: proc(draw: Terminal_Explorer_Draw) {
    explorer := &draw.state.terminal.history_explorer
    rect := terminal_explorer_help_rect(draw.prepared)
    columns := max(1, int(rect.width / draw.prepared.layout.column_width))
    visible := max(1, int(rect.height / draw.prepared.layout.line_height))
    start := min(explorer.help_scroll_lines,
        terminal_explorer_help_scroll_max(draw.state, draw.prepared))
    line := 0
    buffer: [4096]u8
    for id in terminal_explorer_help_sections(explorer.help) {
        source := viewmessages.shell_message(draw.state, id)
        offset := 0
        for offset < len(source) {
            row := terminal_explorer_text_row(source, offset, columns, buffer[:])
            if line >= start && line < start + visible {
                target := rect
                target.y += f32(line - start)*draw.prepared.layout.line_height
                target.height = draw.prepared.layout.line_height
                terminal_explorer_draw_text(
                    draw, row.text, target, theme.draw_color(draw.encoder, .Text))
            }
            if row.next <= offset {
                break
            }
            offset = row.next
            line += 1
        }
        line += 1
    }
}

// Expose complete localized sections, never the hidden candidates or their stale select actions.
terminal_explorer_register_help :: proc(
    state: ^core.Euclid_General_State, prepared: Terminal_Prepared_Frame) {
    terminal_explorer_register_help_document(state, prepared)
    if prepared.explorer.compact {
        return
    }
    for message, index in terminal_explorer_help_sections(
        state.terminal.history_explorer.help) {
        id := terminal_semantic_id(state)
        id.local_id = u64(10 + index)
        _ = uisemantics.semantic_register_control(state.ui_runtime.semantic_focus, {
            id = id,
            parent = terminal_explorer_help_id(state),
            role = .Text_Run,
            states = {.Visible, .Enabled, .Read_Only},
            bounds = terminal_explorer_help_rect(prepared),
            clip_bounds = prepared.explorer.bounds,
            label = viewmessages.shell_message(state, .Terminal_History_Help_Label),
            value = viewmessages.shell_message(state, message),
        })
    }
}

// Keep help scrolling addressed separately from the hidden exact-source preview.
terminal_explorer_help_id :: proc(
    state: ^core.Euclid_General_State) -> viewmodel.Ui_Node_Id {
    id := terminal_semantic_id(state)
    id.local_id = 3
    return id
}

// Publish restoration instructions and the same bounded scrolling range as the visible document.
terminal_explorer_register_help_document :: proc(
    state: ^core.Euclid_General_State, prepared: Terminal_Prepared_Frame) {
    message: content.Content_Message_Id = .Terminal_History_Help_Hints
    rect := terminal_explorer_help_rect(prepared)
    if prepared.explorer.compact {
        message, rect = .Terminal_History_Help_Compact, prepared.explorer.bounds
    }
    maximum := 0
    actions: viewmodel.Ui_Node_Action_Set
    if !prepared.explorer.compact {
        maximum = terminal_explorer_help_scroll_max(state, prepared)
        actions = {.Scroll}
    }
    _ = uisemantics.semantic_register_control(state.ui_runtime.semantic_focus, {
        id = terminal_explorer_help_id(state),
        parent = terminal_semantic_id(state),
        role = .Document,
        states = {.Visible, .Enabled, .Read_Only},
        actions = actions,
        bounds = rect,
        clip_bounds = prepared.explorer.bounds,
        label = viewmessages.shell_message(state, .Terminal_History_Help_Label),
        value = viewmessages.shell_message(state, message),
        numeric_range = {0, f64(maximum),
            f64(min(state.terminal.history_explorer.help_scroll_lines, maximum)),
            1, .Vertical, true},
    })
}

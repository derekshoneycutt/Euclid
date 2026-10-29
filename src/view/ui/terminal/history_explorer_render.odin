package uiterminal

import core "../../../core"
import content "../../../core/content"
import color "../../../core/color"
import geometry "../../../core/geometry"
import coretext "../../../core/text"
import protocol "../../../core/protocol"
import termhist "../../../terminal/history"
import termhiststore "../../../terminal/history/store"
import termhistsearch "../../../terminal/history/search"
import terminalview "../../terminal"
import font "../../font"
import native "../../native"
import viewmessages "../../messages"
import viewtext "../text"
import theme "../theme"
import "core:time"

// Immutable drawing inputs for the existing Terminal encoder and font resolver.
Terminal_Explorer_Draw :: struct {
    state: ^core.Euclid_General_State,
    encoder: ^native.Draw_Encoder,
    prepared: Terminal_Prepared_Frame,
    resolver: font.Font_Resolver,
    now_ms: i64,
}

// Source mapping and style context for one clipped explorer text region.
Terminal_Explorer_Source_Draw :: struct {
    source: string,
    source_start: int,
    source_end: int,
    rect: geometry.Rectangle,
    highlights: []protocol.Highlight_Run,
    matches: []termhistsearch.Search_Range,
    flatten: bool,
}

// Draw a sanitized, grapheme-clipped monospace span in its own scissor region.
terminal_explorer_draw_text :: proc(
    draw: Terminal_Explorer_Draw, text: string, rect: geometry.Rectangle,
    paint: color.Color_RGBA8, right: bool = false) {
    buffer: [4096]u8
    columns := max(0, int(rect.width / draw.prepared.layout.column_width))
    row := terminal_explorer_text_row(text, 0, columns, buffer[:], true)
    position: geometry.Vector2 = {rect.x, rect.y}
    if right {
        position.x += rect.width -
            f32(row.columns)*draw.prepared.layout.column_width
    }
    _ = native.draw_encoder_push_scissor(draw.encoder, rect)
    if !terminalview.terminal_draw_shaped_prompt_span({
        encoder = draw.encoder,
        resolver = draw.resolver,
        key = .Regular,
        text = row.text,
        position = position,
        color = paint,
    }) {
        _ = viewtext.ui_text_unshaped_paged({
            encoder = draw.encoder,
            resolver = draw.resolver,
            key = .Regular,
            text = row.text,
            position = position,
            color = paint,
            font = {draw.prepared.layout.regular, draw.prepared.layout.font_size},
        })
    }
    _ = native.draw_encoder_pop_scissor(draw.encoder)
}

// Render the compact stacked explorer without changing the existing outer panel.
terminal_draw_explorer :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    prepared: Terminal_Prepared_Frame) {
    draw: Terminal_Explorer_Draw = {
        state = state,
        encoder = encoder,
        prepared = prepared,
        resolver = font.cache_terminal_resolver(&state^.font_cache),
        now_ms = time.time_to_unix_nano(time.now()) / 1_000_000,
    }
    _ = native.draw_encoder_push_scissor(encoder, prepared.explorer.bounds)
    if state.terminal.history_explorer.help != .None {
        terminal_explorer_draw_help(draw)
    } else if prepared.explorer.compact {
        terminal_explorer_draw_compact(draw)
    } else {
        terminal_explorer_draw_query(draw)
        terminal_explorer_draw_rows(draw)
        terminal_explorer_draw_preview(draw)
        terminal_explorer_draw_text(draw, viewmessages.shell_message(state,
            terminal_explorer_status_message(&state.terminal.history_explorer)),
            prepared.explorer.status, theme.draw_color(encoder, .Text))
        terminal_explorer_draw_hints(draw)
    }
    _ = native.draw_encoder_pop_scissor(encoder)
}

// Inset the footer into the preview outline instead of reserving a separate text row.
terminal_explorer_draw_hints :: proc(draw: Terminal_Explorer_Draw) {
    text := viewmessages.shell_message(draw.state, .Terminal_History_Hints)
    rect := draw.prepared.explorer.hints
    cell := draw.prepared.layout.column_width
    width := f32(coretext.text_grapheme_column(text, len(text)))*cell
    backing := rect
    backing.width = min(rect.width + cell, width + cell)
    backing.x = rect.x + rect.width - backing.width + cell / 2
    _ = native.draw_encoder_rectangle(
        draw.encoder, backing, theme.UI_COMPONENT_BACKGROUND_COLOR)
    terminal_explorer_draw_text(
        draw, text, rect, theme.draw_color(draw.encoder, .Text), true)
}

// Wrap the minimum-size instruction so narrow panes still expose cancellation.
terminal_explorer_draw_compact :: proc(draw: Terminal_Explorer_Draw) {
    terminal_explorer_draw_compact_message(draw, .Terminal_History_Compact)
}

// Wrap localized compact instructions without clipping away cancellation/restoration.
terminal_explorer_draw_compact_message :: proc(
    draw: Terminal_Explorer_Draw, message: content.Content_Message_Id) {
    source := viewmessages.shell_message(draw.state, message)
    rect := draw.prepared.explorer.bounds
    rect.height = draw.prepared.layout.line_height
    columns := max(1, int(rect.width / draw.prepared.layout.column_width))
    buffer: [4096]u8
    offset := 0
    for offset < len(source) &&
        rect.y + rect.height <= draw.prepared.explorer.bounds.y +
            draw.prepared.explorer.bounds.height {
        row := terminal_explorer_text_row(source, offset, columns, buffer[:])
        terminal_explorer_draw_text(draw, row.text, rect,
            theme.draw_color(draw.encoder, .Text))
        if row.next <= offset {
            break
        }
        offset = row.next
        rect.y += rect.height
    }
}
// Render committed query text, selection, and a distinct underlined IME preedit.
terminal_explorer_draw_query :: proc(draw: Terminal_Explorer_Draw) {
    prepared := draw.prepared
    query := &draw.state^.terminal.history_explorer.query_editor
    layout := prepared.explorer
    label_rect := layout.query
    label_rect.width = layout.query_text.x - label_rect.x
    terminal_explorer_draw_text(draw,
        viewmessages.shell_message(draw.state, .Terminal_History_Query),
        label_rect, theme.draw_color(draw.encoder, .Text))
    _ = native.draw_encoder_push_scissor(draw.encoder, layout.query_text)
    _ = native.draw_encoder_rectangle(draw.encoder,
        prepared.editable_geometry.selection,
        theme.draw_color(draw.encoder, .History_Explorer_Selection_Background))
    text := termhist.termhist_current_text(query)
    terminal_explorer_draw_text(draw, text[layout.query_start:],
        layout.query_text, theme.draw_color(draw.encoder, .Text))
    if query^.preedit_active {
        terminal_explorer_draw_preedit(draw)
    }
    if prepared.layout.terminal_focused {
        _ = native.draw_encoder_rectangle(draw.encoder,
            prepared.editable_geometry.caret, theme.draw_color(draw.encoder, .Text))
    }
    _ = native.draw_encoder_pop_scissor(draw.encoder)
}

// Overlay composition at the committed query cursor without modifying query source.
terminal_explorer_draw_preedit :: proc(draw: Terminal_Explorer_Draw) {
    query := &draw.state^.terminal.history_explorer.query_editor
    rect := draw.prepared.explorer.query_text
    text := termhist.termhist_current_text(query)
    start := draw.prepared.explorer.query_start
    column := coretext.text_grapheme_column(text[start:], max(0, query^.cursor - start))
    rect.x += f32(column)*draw.prepared.layout.column_width
    rect.width = max(0, draw.prepared.explorer.query_text.x +
        draw.prepared.explorer.query_text.width - rect.x)
    _ = native.draw_encoder_rectangle(draw.encoder, rect,
        theme.UI_COMPONENT_BACKGROUND_COLOR)
    terminal_explorer_draw_text(draw, string(query^.preedit[:query^.preedit_length]),
        rect, theme.draw_color(draw.encoder, .Text))
    underline := rect
    underline.y += rect.height - 2
    underline.height = 1
    underline.width = min(rect.width, f32(coretext.text_grapheme_column(
        string(query^.preedit[:query^.preedit_length]), query^.preedit_length)) *
            draw.prepared.layout.column_width)
    _ = native.draw_encoder_rectangle(draw.encoder, underline,
        theme.draw_color(draw.encoder, .Text))
}

// Leave Julia implicit; expand the shared nondefault-mode icon on the current row.
terminal_explorer_mode :: proc(
    mode: protocol.Evaluation_Mode, selected: bool) -> string {
    if mode == .Normal {
        return ""
    }
    if !selected {
        return "▦"
    }
    switch mode {
    case .Normal:
        return ""
    case .Help:
        return "help"
    case .Pkg:
        return "pkg"
    case .Shell:
        return "shell"
    }
    return ""
}

// Match each explorer mode badge to its application-owned preview prompt color.
terminal_explorer_mode_role :: proc(mode: protocol.Evaluation_Mode) -> theme.Color_Role {
    switch mode {
    case .Normal:
        return .Terminal_Prompt
    case .Help:
        return .Terminal_Help
    case .Pkg:
        return .Terminal_Package
    case .Shell:
        return .Terminal_Shell
    }
    return .Text
}

// Keep compact mode icons colored and selected names readable on inverse badges.
terminal_explorer_draw_mode :: proc(
    draw: Terminal_Explorer_Draw, mode: protocol.Evaluation_Mode,
    selected: bool, bounds: geometry.Rectangle) {
    text := terminal_explorer_mode(mode, selected)
    if len(text) == 0 {
        return
    }
    rect := bounds
    paint := theme.draw_color(draw.encoder, terminal_explorer_mode_role(mode))
    if selected {
        rect.width = min(rect.width,
            f32(len(text) + 1)*draw.prepared.layout.column_width)
        _ = native.draw_encoder_rectangle(draw.encoder, rect, paint)
        paint = theme.UI_COMPONENT_BACKGROUND_COLOR
        rect.x += draw.prepared.layout.column_width / 2
        rect.width -= draw.prepared.layout.column_width / 2
    }
    terminal_explorer_draw_text(draw, text, rect, paint)
}

// Select localized age units with future-safe subtraction and bounded day counts.
terminal_explorer_age_value :: proc(
    now_ms, submitted_ms: i64) -> (content.Content_Message_Id, i64) {
    if submitted_ms >= now_ms {
        return .Terminal_History_Age_Now, 0
    }
    seconds := (now_ms - max(i64(0), submitted_ms)) / 1000
    if seconds < 1 {
        return .Terminal_History_Age_Now, 0
    }
    if seconds < 60 {
        return .Terminal_History_Age_Seconds, seconds
    }
    if seconds < 3600 {
        return .Terminal_History_Age_Minutes, seconds / 60
    }
    if seconds < 86400 {
        return .Terminal_History_Age_Hours, seconds / 3600
    }
    return .Terminal_History_Age_Days, min(i64(99999), seconds / 86400)
}

// Format compact age into caller-owned scratch; no per-row allocation is retained.
terminal_explorer_age :: proc(
    draw: Terminal_Explorer_Draw, submitted_ms: i64, storage: []u8) -> string {
    id, value := terminal_explorer_age_value(draw.now_ms, submitted_ms)
    if id == .Terminal_History_Age_Now {
        return viewmessages.shell_message(draw.state, id)
    }
    return viewmessages.shell_format(draw.state, id, {{
        name = "count",
        value = value,
    }}, storage)
}

// Draw only the bounded visible candidate rows, using fixed source/mode/age columns.
terminal_explorer_draw_rows :: proc(draw: Terminal_Explorer_Draw) {
    explorer := &draw.state^.terminal.history_explorer
    layout := draw.prepared.explorer
    end := min(explorer^.row_count, explorer^.list_scroll_rows + layout.row_capacity)
    for index in explorer^.list_scroll_rows..<end {
        terminal_explorer_draw_row(draw, index)
    }
}

// Paint one row with a restrained current marker and isolated metadata clipping.
terminal_explorer_draw_row :: proc(draw: Terminal_Explorer_Draw, index: int) {
    explorer := &draw.state^.terminal.history_explorer
    layout := draw.prepared.explorer
    row := explorer^.rows[index]
    rect := terminal_explorer_row_rect(layout, index - explorer^.list_scroll_rows,
        draw.prepared.layout.line_height)
    selected := index == explorer^.selected_index
    if selected {
        _ = native.draw_encoder_rectangle(draw.encoder, rect,
            theme.draw_color(draw.encoder, .History_Explorer_Selection_Background))
    }
    terminal_explorer_draw_text(draw, "○" if selected else "◦", rect,
        theme.draw_color(draw.encoder, .Terminal_Package if selected else .Text))
    rect.x += 2*draw.prepared.layout.column_width
    rect.width = layout.source_width
    matches_max := row.matches.offset + row.matches.count
    summary := string(explorer^.summaries[
        row.summary_offset:row.summary_offset + row.summary_length])
    terminal_explorer_draw_summary(draw, summary, rect, {
        highlights = terminal_explorer_highlights(draw.state, row.record),
        matches = explorer.row_ranges[row.matches.offset:matches_max],
    })
    rect.x, rect.width = layout.mode_x, layout.age_x - layout.mode_x -
        draw.prepared.layout.column_width
    terminal_explorer_draw_mode(draw, row.record.mode, selected, rect)
    rect.x, rect.width =
        layout.age_x, layout.bounds.x + layout.bounds.width - layout.age_x
    buffer: [128]u8
    terminal_explorer_draw_text(draw,
        terminal_explorer_age(draw, row.record.submitted_at_unix_ms, buffer[:]),
        rect, theme.draw_color(draw.encoder, .Text), true)
}

// Resolve only ready Normal-mode styles for the candidate's scoped revision.
terminal_explorer_highlights :: proc(
    state: ^core.Euclid_General_State,
    record: termhiststore.History_Record) -> []protocol.Highlight_Run {
    if record.mode != .Normal {
        return nil
    }
    target_kind: protocol.Highlight_Target = .History_Entry
    if record.scope == .Persistent {
        target_kind = .Persistent_History_Entry
    }
    return terminalview.terminal_highlight_cached_runs(
        &state^.terminal, target_kind, record.source_id, record.source_revision)
}

// Draw a sanitized summary while retaining the source offsets for cached styles.
terminal_explorer_draw_summary :: proc(
    draw: Terminal_Explorer_Draw, source: string, rect: geometry.Rectangle,
    source_draw: Terminal_Explorer_Source_Draw) {
    columns := max(0, int(rect.width / draw.prepared.layout.column_width))
    buffer: [4096]u8
    row := terminal_explorer_text_row(source, 0, columns, buffer[:], true)
    if len(source_draw.highlights) == 0 && len(source_draw.matches) == 0 {
        terminal_explorer_draw_text(
            draw, row.text, rect, theme.draw_color(draw.encoder, .Text))
        return
    }
    mapped := source_draw
    mapped.source = source
    mapped.source_start, mapped.source_end = row.source_start, row.source_end
    mapped.rect, mapped.flatten = rect, true
    terminal_explorer_draw_source_range(draw, mapped)
}

// Draw mapped grapheme fragments without exposing source controls or changing advances.
terminal_explorer_draw_source_range :: proc(
    draw: Terminal_Explorer_Draw, source_draw: Terminal_Explorer_Source_Draw) {
    capacity := max(0, int(
        source_draw.rect.width / draw.prepared.layout.column_width))
    columns := 0
    offset := source_draw.source_start
    _ = native.draw_encoder_push_scissor(draw.encoder, source_draw.rect)
    for offset < source_draw.source_end {
        fragment := terminal_explorer_text_fragment(
            source_draw.source, offset, source_draw.flatten)
        if fragment.hard_break {
            break
        }
        if fragment.columns > capacity && columns == 0 {
            fragment.text, fragment.columns = "?", 1
        }
        if columns + fragment.columns > capacity ||
            fragment.next > source_draw.source_end {
            break
        }
        position: geometry.Vector2 = {
            source_draw.rect.x + f32(columns)*draw.prepared.layout.column_width,
            source_draw.rect.y,
        }
        terminal_explorer_draw_source_fragment(
            draw, source_draw, fragment, position)
        terminal_explorer_draw_match(draw, source_draw, fragment, position)
        columns += fragment.columns
        offset = fragment.next
    }
    _ = native.draw_encoder_pop_scissor(draw.encoder)
}

// Apply source style only to source-backed fragments; synthetic markers stay neutral.
terminal_explorer_draw_source_fragment :: proc(
    draw: Terminal_Explorer_Draw, source_draw: Terminal_Explorer_Source_Draw,
    fragment: Terminal_Explorer_Text_Fragment, position: geometry.Vector2) {
    if fragment.synthetic {
        fragment_rect := source_draw.rect
        fragment_rect.x = position.x
        fragment_rect.width = f32(fragment.columns) *
            draw.prepared.layout.column_width
        terminal_explorer_draw_text(
            draw, fragment.text, fragment_rect,
            theme.draw_color(draw.encoder, .Text))
        return
    }
    request: terminalview.Terminal_Prompt_Text_Draw = {
        encoder = draw.encoder,
        resolver = draw.resolver,
        regular = draw.prepared.layout.regular,
        current_text = fragment.text,
        position = position,
        color = draw.prepared.layout.theme.default_foreground,
        highlights = source_draw.highlights,
        source_offset = fragment.source_start,
        palette = &draw.state^.terminal.output_interpreter.title_state.palette,
        theme = draw.prepared.layout.theme,
    }
    terminalview.terminal_draw_explorer_syntax_fragment(request)
}

// Preserve a stable outlined preview, including explicit loading/failure states.
terminal_explorer_draw_preview :: proc(draw: Terminal_Explorer_Draw) {
    explorer := &draw.state^.terminal.history_explorer
    layout := draw.prepared.explorer
    _ = native.draw_encoder_rectangle_outline(draw.encoder, layout.preview, 1,
        theme.draw_color(draw.encoder, .Control_Border))
    if explorer^.preview_status == .Ready {
        terminal_explorer_draw_preview_source(draw)
        return
    }
    id: content.Content_Message_Id = .Terminal_History_Preview
    #partial switch explorer^.preview_status {
    case .Loading:
        id = .Terminal_History_Preview_Loading
    case .Failed:
        id = .Terminal_History_Preview_Failed
    case .Capacity:
        id = .Terminal_History_Preview_Capacity
    }
    terminal_explorer_draw_text(draw, viewmessages.shell_message(draw.state, id),
        layout.preview_text, theme.draw_color(draw.encoder, .Text))
}

// Render unchanged hard breaks and indentation through the shared safe wrap iterator.
terminal_explorer_draw_preview_source :: proc(draw: Terminal_Explorer_Draw) {
    explorer := &draw.state^.terminal.history_explorer
    layout := draw.prepared.explorer
    source := string(explorer^.preview_source[:explorer^.preview_length])
    source_draw: Terminal_Explorer_Source_Draw = {
        source = source,
        highlights = terminal_explorer_highlights(
            draw.state, explorer^.preview_record),
        matches = explorer.preview_matches.ranges[:explorer.preview_matches.count],
    }
    offset := 0
    buffer: [4096]u8
    for line := 0;
        line < explorer^.preview_scroll_lines + layout.preview_rows; line += 1 {
        row := terminal_explorer_text_row(
            source, offset, layout.preview_columns, buffer[:])
        if line >= explorer^.preview_scroll_lines {
            terminal_explorer_draw_preview_row(draw, source_draw, row,
                line - explorer^.preview_scroll_lines, line == 0)
        }
        if row.next <= offset {
            break
        }
        offset = row.next
        if offset == len(source) && !row.hard_break {
            break
        }
    }
}

// Reserve an identical prompt gutter on every preview row, including wrapped lines.
terminal_explorer_draw_preview_row :: proc(
    draw: Terminal_Explorer_Draw, source_draw: Terminal_Explorer_Source_Draw,
    row_source: Terminal_Explorer_Text_Row, row: int, first: bool) {
    rect := draw.prepared.explorer.preview_text
    rect.y += f32(row)*draw.prepared.layout.line_height
    rect.height = draw.prepared.layout.line_height
    prompt, paint := terminal_explorer_prompt(draw)
    if first {
        terminal_explorer_draw_text(draw, prompt, rect, paint)
    }
    rect.x += 7*draw.prepared.layout.column_width
    rect.width -= 7*draw.prepared.layout.column_width
    if len(source_draw.highlights) == 0 && len(source_draw.matches) == 0 {
        terminal_explorer_draw_text(
            draw, row_source.text, rect, theme.draw_color(draw.encoder, .Text))
        return
    }
    source_range := source_draw
    source_range.source_start = row_source.source_start
    source_range.source_end = row_source.source_end
    source_range.rect = rect
    terminal_explorer_draw_source_range(draw, source_range)
}

// Reuse the ordinary Terminal's mode prompts and contrast-aware semantic colors.
terminal_explorer_prompt :: proc(
    draw: Terminal_Explorer_Draw) -> (string, color.Color_RGBA8) {
    switch draw.state^.terminal.history_explorer.preview_record.mode {
    case .Normal:
        return terminalview.TERMINAL_PROMPT,
            theme.draw_color(draw.encoder, .Terminal_Prompt)
    case .Help:
        return terminalview.TERMINAL_HELP_PROMPT,
            theme.draw_color(draw.encoder, .Terminal_Help)
    case .Pkg:
        return terminalview.TERMINAL_PKG_PROMPT,
            theme.draw_color(draw.encoder, .Terminal_Package)
    case .Shell:
        return terminalview.TERMINAL_SHELL_PROMPT,
            theme.draw_color(draw.encoder, .Terminal_Shell)
    }
    return "", {}
}

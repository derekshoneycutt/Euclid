package terminalview

import protocol "../../core/protocol"
import geometry "../../core/geometry"
import termgrid "../../terminal/grid"
import termpalette "../../terminal/palette"
import model "model"
import font "../font"
import native "../native"
import viewtext "../ui/text"

// Resolved decorative appearance; geometry continues to use regular monospace advances.
Terminal_Syntax_Style :: struct {
    foreground: Color,
    background: Color,
    underline_color: Color,
    key: font.Font_Key,
    underline: protocol.Highlight_Underline,
    strike: bool,
}

// Resolve the current native palette without converting Julia faces through ANSI.
terminal_syntax_color :: proc(
    kind: protocol.Highlight_Color_Kind, value: u32,
    fallback: Color, palette: ^termpalette.Terminal_Palette_State) -> Color {
    switch kind {
    case .Default:
        return fallback
    case .Rgb:
        return terminal_packed_color(value << 8 | 0xff)
    case .Ansi:
        rgba := termpalette.terminal_indexed_color_rgba(int(value))
        if palette != nil {
            rgba = palette.colors[value]
        }
        return terminal_packed_color(rgba)
    }
    return fallback
}

// Map only supported faces, keeping default background transparent unless inverse needs it.
terminal_syntax_style :: proc(
    run: protocol.Highlight_Run, palette: ^termpalette.Terminal_Palette_State,
    theme: Terminal_Draw_Theme) -> Terminal_Syntax_Style {
    foreground := terminal_syntax_color(
        run.foreground_kind, run.foreground, theme.default_foreground, palette)
    background := terminal_syntax_color(
        run.background_kind, run.background, Color{}, palette)
    if run.inverse != 0 {
        if background.a == 0 {
            background = theme.cursor_foreground
        }
        foreground, background = background, foreground
    }
    weight: termgrid.Cell_Style = {
        italic = run.italic != 0,
    }
    switch run.weight {
    case .Normal:
    case .Bold:
        weight.font_weight = .Bold
    case .Dim:
        weight.font_weight = .Light
    }
    return {
        foreground = foreground,
        background = background,
        underline_color = terminal_syntax_color(
            run.underline_color_kind, run.underline_color, foreground, palette),
        key = terminal_font_key_for_cell(weight),
        underline = run.underline,
        strike = run.strikethrough != 0,
    }
}

// Locate source-relative style without allocating or retaining frame-local slices.
terminal_syntax_run_at :: proc(
    runs: []protocol.Highlight_Run, offset: int) -> protocol.Highlight_Run {
    first, end := 0, len(runs)
    for first < end {
        middle := first + (end - first) / 2
        run := runs[middle]
        if offset < int(run.start_byte) {
            end = middle
        } else if offset >= int(run.end_byte) {
            first = middle + 1
        } else {
            return run
        }
    }
    return {}
}

// Extend one UTF-8 fragment only across equal appearance and equal overlay ownership.
terminal_syntax_segment_end :: proc(
    request: Terminal_Prompt_Text_Draw, start: int) -> int {
    excluded := terminal_prompt_byte_excluded(start, request.exclusions)
    style := terminal_syntax_style(
        terminal_syntax_run_at(request.highlights, request.source_offset + start),
        request.palette, request.theme)
    end := terminal_codepoint_end(request.current_text, start)
    count := 1
    for end < len(request.current_text) && count < TERMINAL_SHAPING_RUN_COLUMNS {
        next := terminal_syntax_style(
            terminal_syntax_run_at(request.highlights, request.source_offset + end),
            request.palette, request.theme)
        if next != style ||
           terminal_prompt_byte_excluded(end, request.exclusions) != excluded {
            break
        }
        end = terminal_codepoint_end(request.current_text, end)
        count += 1
    }
    return end
}

// Paint source backgrounds before glyphs, below completion, selection, and cursor overlays.
terminal_syntax_background :: proc(
    encoder: ^native.Draw_Encoder, style: Terminal_Syntax_Style,
    position: geometry.Vector2, width: f32) {
    if style.background.a != 0 && width > 0 {
        scale := terminal_text_scale_factor(encoder^.ui_text_size_percent)
        _ = native.draw_encoder_rectangle(encoder,
            {position.x, position.y, width,
             terminal_font_size(encoder^.ui_text_size_percent) +
             terminal_line_spacing(encoder^.ui_text_size_percent)},
            style.background)
        _ = scale
    }
}

// Draw a bounded underline pattern in screen pixels; curly is a repeating zigzag.
terminal_syntax_underline :: proc(
    encoder: ^native.Draw_Encoder, style: Terminal_Syntax_Style,
    position: geometry.Vector2, width: f32) {
    scale := terminal_text_scale_factor(encoder^.ui_text_size_percent)
    y := position.y + terminal_font_size(encoder^.ui_text_size_percent) - scale
    if style.underline == .Straight || style.underline == .Double {
        _ = native.draw_encoder_line(encoder,
            {position.x, y}, {position.x + width, y}, 1, style.underline_color)
        if style.underline == .Double {
            _ = native.draw_encoder_line(encoder,
                {position.x, y - 2 * scale}, {position.x + width, y - 2 * scale},
                1, style.underline_color)
        }
        return
    }
    step := f32(4) * scale if style.underline == .Dotted else f32(8) * scale
    for x := f32(0); x < width; x += step {
        length := f32(1) if style.underline == .Dotted else f32(4)
        if style.underline == .Curly {
            _ = native.draw_encoder_line(encoder, {position.x + x, y},
                {position.x + min(x + 2 * scale, width), y - 2 * scale},
                1, style.underline_color)
            _ = native.draw_encoder_line(encoder,
                {position.x + min(x + 2 * scale, width), y - 2 * scale},
                {position.x + min(x + 4 * scale, width), y},
                1, style.underline_color)
        } else {
            _ = native.draw_encoder_line(encoder, {position.x + x, y},
                {position.x + min(x + length * scale, width), y},
                1, style.underline_color)
        }
        if style.underline == .Curly {
            step = 4 * scale
        }
    }
}

// Draw supported source decorations independently of glyph page residency.
terminal_syntax_decorations :: proc(
    encoder: ^native.Draw_Encoder, style: Terminal_Syntax_Style,
    position: geometry.Vector2, width: f32) {
    if style.underline != .None {
        terminal_syntax_underline(encoder, style, position, width)
    }
    if style.strike {
        y := position.y + terminal_font_size(encoder^.ui_text_size_percent) * 0.55
        _ = native.draw_encoder_line(encoder,
            {position.x, y}, {position.x + width, y}, 1, style.foreground)
    }
}

// Draw one styled prompt fragment using regular-font geometry and the requested face.
terminal_draw_syntax_segment :: proc(
    request: Terminal_Prompt_Text_Draw, start, end: int) {
    text := request.current_text[start:end]
    style := terminal_syntax_style(
        terminal_syntax_run_at(request.highlights, request.source_offset + start),
        request.palette, request.theme)
    position: geometry.Vector2 = {
        request.position.x + terminal_text_column_width(
            request.regular, request.current_text[:start],
            request.encoder^.ui_text_size_percent), request.position.y}
    width := terminal_text_column_width(
        request.regular, text, request.encoder^.ui_text_size_percent)
    terminal_syntax_background(request.encoder, style, position, width)
    shaped := terminal_draw_shaped_prompt_span({
        request.encoder, request.resolver, style.key, text, position, style.foreground})
    if !shaped && terminal_text_is_ascii(text) {
        _ = viewtext.ui_text_unshaped_paged({
            encoder = request.encoder,
            resolver = request.resolver,
            key = style.key,
            text = text,
            position = position,
            color = style.foreground,
            font = {
                terminal_font_resolve(request.resolver, style.key),
                terminal_font_size(request.encoder^.ui_text_size_percent),
            },
        })
    }
    terminal_syntax_decorations(request.encoder, style, position, width)
}

// Return the byte length of one complete terminal grapheme, matching prompt/grid clustering.
terminal_syntax_grapheme_length :: proc(text: string) -> int {
    cells: [2]termgrid.Cell
    count := 0
    offset := 0
    for offset < len(text) {
        end := terminal_codepoint_end(text, offset)
        codepoint := rune(0)
        for decoded in text[offset:end] {
            codepoint = decoded
        }
        if !terminal_prompt_cell_append(cells[:], &count, codepoint,
            transmute([]u8)text[offset:end]) || count > 1 {
            break
        }
        offset = end
    }
    return offset
}

// Map a submitted hard line's grapheme ordinal to a byte offset including its prefix.
terminal_syntax_history_offset :: proc(
    text: string, ordinal: int) -> int {
    offset := 0
    for _ in 0..<ordinal {
        if offset >= len(text) {
            return -1
        }
        size := terminal_syntax_grapheme_length(text[offset:])
        if size == 0 {
            return -1
        }
        offset += size
    }
    return offset
}

// Borrow the anchor for one semantic row, excluding transient alternate-screen output.
terminal_syntax_history_anchor :: proc(
    term: ^model.Terminal_State, index: int) -> ^model.Terminal_Highlight_History {
    alternate := term.output_interpreter.alternate_screen_active
    if term.synchronized_output.active {
        alternate = term.synchronized_output.captured_alternate_screen_active
    }
    if term.highlighting == nil || alternate {
        return nil
    }
    row := terminal_output_semantic_row(term, index)
    for &entry in term.highlighting.history {
        if terminal_highlight_history_current(term, &entry) &&
            terminal_highlight_line_for_row(&entry, row) != nil {
            return &entry
        }
    }
    return nil
}

// Verify exact visible graphemes before applying styles; VT rewrites remain authoritative.
terminal_syntax_history_cells :: proc(
    term: ^model.Terminal_State, index: int,
    cells: []termgrid.Cell, styles: []Terminal_Syntax_Style,
    theme: Terminal_Draw_Theme) -> bool {
    entry := terminal_syntax_history_anchor(term, index)
    slot := terminal_history_highlight_slot(term, entry)
    if slot == nil || len(styles) < len(cells) {
        return false
    }
    row := terminal_output_semantic_row(term, index)
    prefix := TERMINAL_PROMPT if
        entry.line.source_start == 0 else TERMINAL_CONTINUATION_PROMPT
    text := string(slot.source[entry.line.source_start:entry.line.source_end])
    ordinal := int(row.grapheme_offset - entry.line.grapheme_offset)
    source_offset := terminal_syntax_history_offset(text, max(ordinal - len(prefix), 0))
    if source_offset < 0 {
        return false
    }
    offset := ordinal if ordinal < len(prefix) else len(prefix) + source_offset
    for &cell, column in cells {
        if cell.continuation {
            continue
        }
        if !terminal_syntax_history_cell_matches(&cell, prefix, text, offset) {
            return false
        }
        if cell.grapheme_len > 0 && offset >= len(prefix) &&
            offset < len(prefix) + len(text) {
            run := terminal_syntax_run_at(slot.runs[:slot.run_count],
                entry.line.source_start + offset - len(prefix))
            styles[column] = terminal_syntax_style(
                run, &term.output_interpreter.title_state.palette, theme)
        }
        offset += int(cell.grapheme_len)
    }
    return true
}

// Accept only intact command cells or unused trailing columns, never overwritten source.
terminal_syntax_history_cell_matches :: proc(
    cell: ^termgrid.Cell, prefix, text: string, offset: int) -> bool {
    if offset >= len(prefix) + len(text) {
        return cell.grapheme_len == 0
    }
    remaining := text[offset - len(prefix):] if offset >= len(prefix) else prefix[offset:]
    length := terminal_syntax_grapheme_length(remaining)
    return length > 0 && !cell.grapheme_truncated &&
        int(cell.grapheme_len) == length &&
        string(cell.grapheme[:cell.grapheme_len]) == remaining[:length]
}

// Prepare a copied row; original grid cells retain VT styles and submission provenance.
terminal_syntax_prepare_history_row :: proc(
    term: ^model.Terminal_State, index: int, draw: Terminal_Shaped_Output_Context,
    cells: []termgrid.Cell, styles: []Terminal_Syntax_Style) -> bool {
    if len(draw.cells) > len(cells) || len(draw.cells) > len(styles) {
        return false
    }
    copy(cells, draw.cells)
    if !terminal_syntax_history_cells(
        term, index, cells[:len(draw.cells)], styles, draw.theme) {
        return false
    }
    for &cell, column in cells[:len(draw.cells)] {
        style := &styles[column]
        if style.foreground.a != 0 {
            cell.style = terminal_syntax_cell_style(style^)
        }
    }
    return true
}

// Lower appearance to existing cell fonts/colors, leaving decorations separate.
terminal_syntax_cell_style :: proc(style: Terminal_Syntax_Style) -> termgrid.Cell_Style {
    result: termgrid.Cell_Style = {
        foreground = termpalette.terminal_color_direct(
            u32(style.foreground.r)<<24 | u32(style.foreground.g)<<16 |
            u32(style.foreground.b)<<8 | 0xff),
    }
    #partial switch style.key {
    case .Bold:
        result.font_weight = .Bold
    case .Bold_Italic:
        result.font_weight = .Bold; result.italic = true
    case .Light:
        result.font_weight = .Light
    case .Light_Italic:
        result.font_weight = .Light; result.italic = true
    case .Regular_Italic:
        result.italic = true
    }
    if style.background.a != 0 {
        result.background = termpalette.terminal_color_direct(
            u32(style.background.r)<<24 | u32(style.background.g)<<16 |
            u32(style.background.b)<<8 | 0xff)
    }
    return result
}

// Draw validated historical source using a bounded frame-local copy, below overlays.
terminal_draw_syntax_history_row :: proc(
    term: ^model.Terminal_State, index: int,
    draw: Terminal_Shaped_Output_Context, shaping_allowed: bool) -> bool {
    cells: [TERMINAL_MAX_COLUMNS]termgrid.Cell
    styles: [TERMINAL_MAX_COLUMNS]Terminal_Syntax_Style
    if !terminal_syntax_prepare_history_row(term, index, draw, cells[:], styles[:]) {
        return false
    }
    styled := draw
    styled.cells = cells[:len(draw.cells)]
    terminal_draw_output_row(styled, shaping_allowed)
    terminal_syntax_history_decorations(styled, styles[:len(draw.cells)])
    return true
}

// Merge equal neighboring decorations to keep patterns continuous across cell boundaries.
terminal_syntax_history_decorations :: proc(
    draw: Terminal_Shaped_Output_Context, styles: []Terminal_Syntax_Style) {
    column := 0
    for column < len(draw.cells) {
        cell := &draw.cells[column]
        if cell.continuation || styles[column].foreground.a == 0 {
            column += 1
            continue
        }
        style := styles[column]
        end := column + max(int(cell.width), 1)
        for end < len(draw.cells) && styles[end] == style {
            end += max(int(draw.cells[end].width), 1)
        }
        terminal_syntax_decorations(draw.encoder, style,
            {draw.position.x + f32(column)*draw.column_width, draw.position.y},
            f32(end - column)*draw.column_width)
        column = end
    }
}

// Selected output rows retain per-cell glyph ownership so overlays cannot split ligatures.
terminal_output_row_shaping_allowed :: proc(
    term: ^model.Terminal_State, index: int,
    selection: Terminal_Selection_Bounds) -> bool {
    if !term.view_selection_active {
        return true
    }
    line_text := terminal_line_text(term, index)
    span := terminal_selection_span_for_line(
        selection.start, selection.end, index, len(line_text))
    return !span.has_selection
}

#+test

package terminalview

import protocol "../../core/protocol"
import termhist "../../terminal/history"
import model "model"
import termgrid "../../terminal/grid"
import termpalette "../../terminal/palette"
import font "../font"
import native "../native"
import "core:testing"

// The prompt renderer sees preserved colors/font and a default middle before Julia replies.
@(test)
terminal_test_syntax_provisional_segments :: proc(t: ^testing.T) {
    term: model.Terminal_State
    terminal_presentation_test_seed(t, &term, "abcd")
    defer terminal_destroy(&term, context.allocator)
    testing.expect(t, termhist.termhist_replace_input_range(term.history, 2, 2, "X"))
    terminal_highlight_observe_live(&term, 2)
    request: Terminal_Prompt_Text_Draw = {
        current_text = termhist.termhist_current_text(term.history),
        highlights = terminal_live_highlight_runs(&term),
        theme = terminal_syntax_test_theme(),
        exclusions = {
            cursor_start = -1,
            cursor_end = -1,
            selection_start = -1,
            selection_end = -1,
        },
    }
    testing.expect_value(t, terminal_syntax_segment_end(request, 0), 2)
    testing.expect_value(t, terminal_syntax_segment_end(request, 2), 3)
    testing.expect_value(t, terminal_syntax_segment_end(request, 3), 5)
    retained := terminal_syntax_style(
        terminal_syntax_run_at(request.highlights, 3), nil, request.theme)
    middle := terminal_syntax_style(
        terminal_syntax_run_at(request.highlights, 2), nil, request.theme)
    testing.expect_value(t, retained.foreground, Color{0x12, 0x34, 0x56, 255})
    testing.expect_value(t, retained.key, font.Font_Key.Bold_Italic)
    testing.expect_value(t, middle.foreground, request.theme.default_foreground)
    testing.expect_value(t, middle.key, font.Font_Key.Regular)
    request.exclusions.selection_start = 1
    request.exclusions.selection_end = 4
    testing.expect_value(t, terminal_syntax_segment_end(request, 0), 1)
}

// Supply distinct overlay colors so precedence tests cannot pass on equal defaults.
terminal_syntax_test_theme :: proc() -> Terminal_Draw_Theme {
    return {
        default_foreground = {240, 241, 242, 255},
        cursor_foreground = {36, 5, 16, 255},
        selection_foreground = {255, 255, 255, 255},
        selection_background = {20, 80, 160, 255},
    }
}

// Accept deterministic styled source through the real scheduling/publication contract.
terminal_syntax_test_history :: proc(
    t: ^testing.T, term: ^model.Terminal_State, source: string) {
    terminal_highlight_test_init(t, term)
    terminal_highlight_test_submit(t, term, source)
    terminal_highlight_observe_history(term, 0, terminal_line_count(term))
    request, ready := terminal_highlight_take_request(term, 1)
    testing.expect(t, ready)
    runs: [1]protocol.Highlight_Run = {
        {
            end_byte = u32(len(source)),
            foreground_kind = .Rgb,
            foreground = 0x123456,
            weight = .Bold,
            italic = 1,
            underline = .Double,
            strikethrough = 1,
        },
    }
    testing.expect(t, terminal_highlight_publish(term,
        {request.identity, request.source, runs[:]}))
}

// Style color and weight resolution preserves exact RGB and current palette values.
@(test)
terminal_test_syntax_style_resolution :: proc(t: ^testing.T) {
    palette: termpalette.Terminal_Palette_State
    termpalette.terminal_palette_init(&palette)
    palette.colors[3] = 0x998877ff
    theme := terminal_syntax_test_theme()
    run: protocol.Highlight_Run = {
        foreground_kind = .Ansi,
        foreground = 3,
        background_kind = .Rgb,
        background = 0x010203,
        underline_color_kind = .Rgb,
        underline_color = 0x040506,
        weight = .Bold,
        italic = 1,
        underline = .Curly,
        strikethrough = 1,
    }
    style := terminal_syntax_style(run, &palette, theme)
    testing.expect_value(t, style.foreground, Color{0x99, 0x88, 0x77, 255})
    testing.expect_value(t, style.background, Color{1, 2, 3, 255})
    testing.expect_value(t, style.underline_color, Color{4, 5, 6, 255})
    testing.expect_value(t, style.key, font.Font_Key.Bold_Italic)
    testing.expect(t, style.strike && style.underline == .Curly)
    run.weight = .Dim
    testing.expect_value(t, terminal_syntax_style(run, &palette, theme).key,
        font.Font_Key.Light_Italic)
}

// Inverse swaps defaults as well as explicit colors, without making plain backgrounds opaque.
@(test)
terminal_test_syntax_default_and_inverse :: proc(t: ^testing.T) {
    theme := terminal_syntax_test_theme()
    plain := terminal_syntax_style({}, nil, theme)
    testing.expect_value(t, plain.foreground, theme.default_foreground)
    testing.expect_value(t, plain.background.a, u8(0))
    inverse := terminal_syntax_style({
        inverse = 1,
    }, nil, theme)
    testing.expect_value(t, inverse.foreground, theme.cursor_foreground)
    testing.expect_value(t, inverse.background, theme.default_foreground)
    testing.expect_value(t, inverse.underline_color, inverse.foreground)
}

// Equal appearances merge despite separate annotations; cursor/selection still split runs.
@(test)
terminal_test_syntax_segments_and_overlays :: proc(t: ^testing.T) {
    runs: [3]protocol.Highlight_Run = {
        {
            start_byte = 0,
            end_byte = 2,
            weight = .Bold,
        },
        {
            start_byte = 2,
            end_byte = 3,
            weight = .Bold,
        },
        {
            start_byte = 3,
            end_byte = 5,
            italic = 1,
        },
    }
    request: Terminal_Prompt_Text_Draw = {
        current_text = "αxβ",
        highlights = runs[:],
        theme = terminal_syntax_test_theme(),
        exclusions = {
            cursor_start = -1,
            cursor_end = -1,
            selection_start = -1,
            selection_end = -1,
        },
    }
    testing.expect_value(t, terminal_syntax_segment_end(request, 0), 3)
    testing.expect_value(t, terminal_syntax_segment_end(request, 3), 5)
    request.exclusions.cursor_start = 2
    request.exclusions.cursor_end = 3
    testing.expect_value(t, terminal_syntax_segment_end(request, 0), 2)
    testing.expect_value(t, terminal_syntax_segment_end(request, 2), 3)
    request.exclusions = {
        cursor_start = -1,
        cursor_end = -1,
        selection_start = 2,
        selection_end = 5,
    }
    testing.expect_value(t, terminal_syntax_segment_end(request, 0), 2)
}

// Multiline source coordinates stay global while physical row shaping is local.
@(test)
terminal_test_syntax_multiline_offsets :: proc(t: ^testing.T) {
    runs: [2]protocol.Highlight_Run = {
        {
            end_byte = 4,
            weight = .Bold,
        },
        {
            start_byte = 4,
            end_byte = 8,
            weight = .Dim,
        },
    }
    request: Terminal_Prompt_Text_Draw = {
        current_text = "αxy",
        source_offset = 4,
        highlights = runs[:],
        theme = terminal_syntax_test_theme(),
        exclusions = {
            cursor_start = -1,
            cursor_end = -1,
            selection_start = -1,
            selection_end = -1,
        },
    }
    testing.expect_value(t, terminal_syntax_segment_end(request, 0), 4)
    run := terminal_syntax_run_at(request.highlights, request.source_offset)
    testing.expect_value(t, terminal_syntax_style(run, nil, request.theme).key,
        font.Font_Key.Light)
}

// Copied history cells gain current source styles; prefixes and authoritative cells do not.
@(test)
terminal_test_syntax_history_copy_and_prefix :: proc(t: ^testing.T) {
    term: model.Terminal_State
    terminal_syntax_test_history(t, &term, "α = 1\nβ = 2")
    defer terminal_destroy(&term, context.allocator)
    cells: [TERMINAL_MAX_COLUMNS]termgrid.Cell
    styles: [TERMINAL_MAX_COLUMNS]Terminal_Syntax_Style
    original, _ := terminal_output_row(&term, 0)
    testing.expect(t, terminal_syntax_prepare_history_row(&term, 0,
        {
            cells = original,
            theme = terminal_syntax_test_theme(),
        }, cells[:], styles[:]))
    testing.expect_value(t, cells[0].style, original[0].style)
    testing.expect_value(t, original[7].style, termgrid.Cell_Style{})
    testing.expect_value(t, terminal_font_key_for_cell(cells[7].style),
        font.Font_Key.Bold_Italic)
    testing.expect_value(t, styles[7].foreground, Color{0x12, 0x34, 0x56, 255})
    testing.expect_value(t, styles[0].foreground.a, u8(0))
    second, _ := terminal_output_row(&term, 1)
    styles = {}
    testing.expect(t, terminal_syntax_prepare_history_row(&term, 1,
        {
            cells = second,
            theme = terminal_syntax_test_theme(),
        }, cells[:], styles[:]))
    testing.expect_value(t, cells[0].style, second[0].style)
    testing.expect_value(t, styles[7].key, font.Font_Key.Bold_Italic)
}

// Wide and combining graphemes retain their terminal columns through wrapped history.
@(test)
terminal_test_syntax_history_wrapping_unicode :: proc(t: ^testing.T) {
    source: [360]u8
    for group in 0..<60 {
        copy(source[group*6:][:6], "界e\u0301")
    }
    term: model.Terminal_State
    terminal_syntax_test_history(t, &term, string(source[:]))
    defer terminal_destroy(&term, context.allocator)
    cells: [TERMINAL_MAX_COLUMNS]termgrid.Cell
    styles: [TERMINAL_MAX_COLUMNS]Terminal_Syntax_Style
    wrapped, _ := terminal_output_row(&term, 1)
    testing.expect(t, terminal_syntax_prepare_history_row(&term, 1,
        {
            cells = wrapped,
            theme = terminal_syntax_test_theme(),
        }, cells[:], styles[:]))
    testing.expect_value(t, styles[0].key, font.Font_Key.Bold_Italic)
    wide, combining := false, false
    for &cell, column in wrapped {
        if cell.grapheme_len == 0 || cell.continuation {
            continue
        }
        testing.expect_value(t, styles[column].key, font.Font_Key.Bold_Italic)
        if cell.width == 2 {
            wide = true
            testing.expect(t, wrapped[column + 1].continuation)
        }
        combining = combining || termgrid.cell_text(&cell) == "e\u0301"
    }
    testing.expect(t, wide && combining)
    testing.expect_value(t, terminal_syntax_grapheme_length("e\u0301x"), 3)
    testing.expect_value(t, terminal_syntax_grapheme_length("👩‍💻x"), len("👩‍💻"))
    testing.expect_value(t, terminal_syntax_history_offset("界e\u0301x", 2), 6)
}

// Rewritten or stale output rejects styling for the entire row, not a plausible prefix.
@(test)
terminal_test_syntax_history_rewrite_and_fallback :: proc(t: ^testing.T) {
    term: model.Terminal_State
    terminal_syntax_test_history(t, &term, "abc")
    defer terminal_destroy(&term, context.allocator)
    cells: [TERMINAL_MAX_COLUMNS]termgrid.Cell
    styles: [TERMINAL_MAX_COLUMNS]Terminal_Syntax_Style
    original, _ := terminal_output_row(&term, 0)
    original[8].grapheme[0] = 'z'
    testing.expect(t, !terminal_syntax_prepare_history_row(&term, 0,
        {
            cells = original,
            theme = terminal_syntax_test_theme(),
        }, cells[:], styles[:]))
    testing.expect_value(t, cells[7].style, original[7].style)
    original[8].grapheme[0] = 'b'
    terminal_highlight_set_face_generation(&term, 2)
    testing.expect(t, !terminal_syntax_prepare_history_row(&term, 0,
        {
            cells = original,
            theme = terminal_syntax_test_theme(),
        }, cells[:], styles[:]))
}

// Decorations encode even when glyph pages are unavailable, with exact semantic colors.
@(test)
terminal_test_syntax_decoration_commands :: proc(t: ^testing.T) {
    vertices: [512]native.Draw_Vertex
    indices: [768]u32
    batches: [128]native.Draw_Batch
    commands: [128]native.Draw_Command
    encoder: native.Draw_Encoder
    testing.expect(t, native.draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:], commands[:], nil}, {400, 200}, {400, 200}))
    style: Terminal_Syntax_Style = {
        foreground = {1, 2, 3, 255},
        background = {4, 5, 6, 255},
        underline_color = {7, 8, 9, 255},
        underline = .Double,
        strike = true,
    }
    terminal_syntax_background(&encoder, style, {10, 20}, 30)
    testing.expect_value(t, encoder.vertex_count, 4)
    testing.expect_value(t, vertices[0].color, style.background)
    terminal_syntax_decorations(&encoder, style, {10, 20}, 30)
    testing.expect_value(t, encoder.vertex_count, 16)
    testing.expect_value(t, vertices[4].color, style.underline_color)
    testing.expect_value(t, vertices[12].color, style.foreground)
    patterns: [3]protocol.Highlight_Underline = {.Curly, .Dotted, .Dashed}
    for underline in patterns {
        style.underline = underline
        before := encoder.vertex_count
        terminal_syntax_decorations(&encoder, style, {10, 20}, 30)
        testing.expect(t, encoder.vertex_count > before)
    }
}

// Focused cursor and selection remain later encoded layers than syntax backgrounds.
@(test)
terminal_test_syntax_cursor_selection_precedence :: proc(t: ^testing.T) {
    vertices: [128]native.Draw_Vertex
    indices: [192]u32
    batches: [32]native.Draw_Batch
    commands: [32]native.Draw_Command
    encoder: native.Draw_Encoder
    testing.expect(t, native.draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:], commands[:], nil}, {400, 200}, {400, 200}))
    theme := terminal_syntax_test_theme()
    terminal_syntax_background(&encoder, {
        background = {1, 2, 3, 255},
    }, {0, 0}, 10)
    terminal_draw_prompt_overlay({
        encoder = &encoder,
        text = "x",
        theme = theme,
        font = {
            base_size = 16,
            space_advance = 10,
        },
        resolver = {
            resolve = terminal_syntax_test_font,
        },
    }, 0, {
        has_selection = true,
        start = 0,
        end = 1,
    }, true)
    testing.expect_value(t, vertices[0].color, Color{1, 2, 3, 255})
    testing.expect_value(t, vertices[4].color, theme.selection_background)
    testing.expect_value(t, vertices[8].color, theme.selection_foreground)
}

// Supply measurable terminal pitch without resident glyph pages or native resources.
terminal_syntax_test_font :: proc(_: rawptr, _: font.Font_Key) -> font.Font_Face {
    return {
        base_size = 16,
        space_advance = 10,
    }
}

// Synchronized rewrites retain checkpoint styles; alternate-screen output remains VT-owned.
@(test)
terminal_test_syntax_synchronized_and_alternate :: proc(t: ^testing.T) {
    term: model.Terminal_State
    terminal_syntax_test_history(t, &term, "x = 1")
    defer terminal_destroy(&term, context.allocator)
    terminal_append_ansi_output(&term, "\e[?2026h\e[1;8Hz")
    testing.expect(t, term.synchronized_output.active)
    cells: [TERMINAL_MAX_COLUMNS]termgrid.Cell
    styles: [TERMINAL_MAX_COLUMNS]Terminal_Syntax_Style
    presented, _ := terminal_output_row(&term, 0)
    testing.expect(t, terminal_syntax_prepare_history_row(&term, 0,
        {
            cells = presented,
            theme = terminal_syntax_test_theme(),
        }, cells[:], styles[:]))
    testing.expect_value(t, styles[7].key, font.Font_Key.Bold_Italic)
    terminal_append_ansi_output(&term, "\e[?2026l")
    rewritten, _ := terminal_output_row(&term, 0)
    testing.expect(t, !terminal_syntax_prepare_history_row(&term, 0,
        {
            cells = rewritten,
            theme = terminal_syntax_test_theme(),
        }, cells[:], styles[:]))
    terminal_append_ansi_output(&term, "\e[?1049hhidden")
    alternate, _ := terminal_output_row(&term, 0)
    testing.expect(t, !terminal_syntax_prepare_history_row(&term, 0,
        {
            cells = alternate,
            theme = terminal_syntax_test_theme(),
        }, cells[:], styles[:]))
}

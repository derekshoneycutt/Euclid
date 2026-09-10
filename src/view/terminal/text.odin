package terminalview

import "../../core"
import termhist "../../terminal/history"

import "core:fmt"
import "core:math"
import "core:unicode/utf8"

import rl "vendor:raylib"

//   Return a line's selectable text by its combined scrollback/prompt line index.
//
// Parameters:
//   - term: The terminal state field owned by the caller.
//   - line: 0..line_count-1 selects a logical scrollback line; line_count
//     selects the live prompt line; anything past that is blank virtual
//     space below the prompt line.
//
// Returns:
//   - The line's concatenated text, with any trailing newline byte stripped.
//     The live prompt line includes its "> " prefix so it can be hit-tested,
//     highlighted, and copied like any other line. Virtual lines below it
//     return an empty string.
terminal_line_text :: proc(term: ^core.Terminal_State, line: int) -> string {
    if line < 0 {
        return ""
    }

    output_line_count := terminal_line_count(term)
    if line < output_line_count {
        cells, ok := terminal_output_row(term, line)
        if !ok {
            return ""
        }
        return terminal_output_row_text(cells)
    }
    prompt_line := line - output_line_count
    if terminal_prompt_visible(term) &&
        prompt_line >= 0 && prompt_line < terminal_live_input_line_count(term) {
        text := termhist.termhist_current_text(term.history)
        prefix := TERMINAL_CONTINUATION_PROMPT
        if prompt_line == 0 {
            prefix = terminal_primary_prompt_prefix(term)
        }
        return fmt.tprintf(
            "%s%s", prefix, terminal_live_input_line_text(text, prompt_line))
    }
    return ""
}

//   Return the number of physical rows in the live editable input.
//
// Parameters:
//   - term: Terminal state whose editable history is inspected; nil yields zero.
//
// Returns:
//   - Zero for unavailable history; otherwise one plus embedded newline count.
terminal_live_input_line_count :: proc(term: ^core.Terminal_State) -> int {
    if term == nil || term.history == nil {
        return 0
    }
    text := termhist.termhist_current_text(term.history)
    count := 1
    for byte in text {
        if byte == '\n' {
            count += 1
        }
    }
    return count
}

//   Return one physical row from live editable text without its prompt.
//
// Parameters:
//   - text: Complete editable source containing newline-delimited physical rows.
//   - line: Zero-based physical row index to borrow.
//
// Returns:
//   - Borrowed text between newline delimiters, or empty for a negative/out-of-range row.
terminal_live_input_line_text :: proc(text: string, line: int) -> string {
    if line < 0 {
        return ""
    }
    start := 0
    current_line := 0
    for byte, index in text {
        if byte == '\n' {
            if current_line == line {
                return text[start:index]
            }
            current_line += 1
            start = index + 1
        }
    }
    return current_line == line ? text[start:] : ""
}

//   Map a screen-space mouse position to a terminal line and byte offset.
//
// Notes:
//   - The line is only clamped to zero, not to the last real line, so
//     dragging below the prompt line reaches blank virtual space instead of
//     collapsing onto the prompt line's own position.
//
// Parameters:
//   - term: The terminal state field owned by the caller.
//   - font: The monospace font used for hit-testing.
//   - bounds: The rectangle the terminal is drawn within, matching terminal_draw.
//   - mouse: The screen-space mouse position to hit-test.
//
// Returns:
//   - The hit position and true, or a zero value and false when the mouse sits
//     outside the terminal's padded bounds.
terminal_hit_test :: proc(
    term: ^core.Terminal_State, font: rl.Font, bounds: rl.Rectangle,
    mouse: rl.Vector2) -> (core.Terminal_View_Position, bool) {
    if term == nil || term.history == nil {
        return core.Terminal_View_Position{}, false
    }

    padded_bounds := terminal_accepted_padded_bounds(term, bounds)
    if !rl.CheckCollisionPointRec(mouse, padded_bounds) {
        return core.Terminal_View_Position{}, false
    }

    line_height := TERMINAL_FONT_SIZE + TERMINAL_LINE_SPACING
    origin_y := padded_bounds.y - term.scroll_offset_y

    line := int((mouse.y - origin_y) / line_height)
    line = math.max(line, 0)

    output_line_count := terminal_line_count(term)
    if line < output_line_count {
        cells, ok := terminal_output_row(term, line)
        if !ok {
            return core.Terminal_View_Position{}, false
        }
        column_width := terminal_column_width(font)
        column := 0
        if column_width > 0 {
            column = int((mouse.x - padded_bounds.x) / column_width + 0.5)
        }
        return core.Terminal_View_Position{
            line = line,
            byte_offset = terminal_output_row_byte_offset(cells, column),
        }, true
    }
    line_text := terminal_line_text(term, line)
    byte_offset := terminal_byte_offset_for_x(font, line_text, mouse.x - padded_bounds.x)

    return core.Terminal_View_Position{line = line, byte_offset = byte_offset}, true
}

//   Map a horizontal pixel offset within a line to the nearest UTF-8 byte
//   offset, extrapolating into virtual blank columns past the line's real text.
//
// Parameters:
//   - font: The monospace font used for terminal text.
//   - line_text: The line's text being hit-tested.
//   - relative_x: The pixel offset from the line's left edge.
//
// Returns:
//   - A real byte offset when relative_x falls within the line's text, or
//     len(line_text) plus a virtual column count when it falls past it.
terminal_byte_offset_for_x :: proc(
    font: rl.Font, line_text: string, relative_x: f32) -> int {
    if relative_x <= 0 {
        return 0
    }

    column_width := terminal_column_width(font)
    if column_width <= 0 {
        return 0
    }

    if len(line_text) == 0 {
        return int(relative_x / column_width + 0.5)
    }

    codepoint_count := utf8.rune_count_in_string(line_text)
    if codepoint_count == 0 {
        return int(relative_x / column_width + 0.5)
    }

    line_width := rl.MeasureTextEx(font, fmt.ctprintf("%s", line_text),
        TERMINAL_FONT_SIZE, TERMINAL_TEXT_SPACING).x
    if line_width <= 0 {
        return int(relative_x / column_width + 0.5)
    }

    if relative_x >= line_width {
        extra_columns := int((relative_x - line_width) / column_width + 0.5)
        return len(line_text) + extra_columns
    }

    // Font is guaranteed monospace, so a uniform advance is a valid approximation.
    glyph_advance := line_width / f32(codepoint_count)
    codepoint_index := int(relative_x / glyph_advance + 0.5)
    codepoint_index = math.clamp(codepoint_index, 0, codepoint_count)

    offset := 0
    for i := 0; i < codepoint_index && offset < len(line_text); i += 1 {
        _, width := utf8.decode_rune(line_text[offset:])
        offset += width
    }
    return offset
}

//   Compute a line's selected byte sub-range, if the line falls within the
//   selection's ordered span.
//
// Notes:
//   - start/end may exceed line_len, representing virtual blank columns past
//     the line's real text; callers must clamp before slicing line text.
//   - Any non-last line in range is always selected, even when its own
//     start point began past its true end in virtual blank space, since it
//     necessarily continues into more selected lines below it. Only the
//     final line can produce a genuinely empty (zero-width) selection.
//
// Parameters:
//   - start: The selection's ordered start position.
//   - end: The selection's ordered end position.
//   - line: The line index being drawn.
//   - line_len: The byte length of that line's text.
//
// Returns:
//   - The sub-range, with has_selection false when the intersection is empty.
terminal_selection_span_for_line :: proc(
    start, end: core.Terminal_View_Position,
    line, line_len: int) -> Terminal_Line_Selection {
    if line < start.line || line > end.line {
        return Terminal_Line_Selection{}
    }

    is_last_line := line == end.line

    span_start := line == start.line ? start.byte_offset : 0
    span_start = math.max(span_start, 0)

    span_end := is_last_line ? end.byte_offset : line_len
    span_end = math.max(span_end, span_start)

    if is_last_line && span_start == span_end {
        return Terminal_Line_Selection{}
    }

    return Terminal_Line_Selection{
        start = span_start, end = span_end, has_selection = true,
        covers_trailing_gap = !is_last_line,
    }
}

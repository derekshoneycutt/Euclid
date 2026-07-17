package ui

import "core:strings"

import rl "vendor:raylib"

//   Draw UTF-8 UI text using temp C-string conversion.
ui_text :: #force_inline proc(
    text: string, x, y: int, color: rl.Color, font: rl.Font, font_size: f32 = TREE_FONT_SIZE) {
    cloned := strings.clone_to_cstring(text, context.temp_allocator)
    rl.DrawTextEx(font, cloned, rl.Vector2{f32(x), f32(y)}, font_size, 0, color)
}

//   Estimate visible character capacity for one wrapped text row.
chars_per_text_row :: #force_inline proc(width, wrap_advance: f32) -> int {
    count := int(width / wrap_advance)
    if count < 1 {
        return 1
    }
    return count
}

//   Compute the next wrapped line span and next-start index.
next_wrapped_text_span :: proc(
    text: string, start: int, max_chars: int) -> (int, int, int) {

    if start >= len(text) {
        return start, start, start
    }

    line_end := start
    chars_used := 0
    last_space := -1

    for line_end < len(text) && text[line_end] != '\n' {
        if text[line_end] == ' ' || text[line_end] == '\t' {
            last_space = line_end
        }

        chars_used += 1
        if chars_used > max_chars {
            if last_space >= start {
                line_end = last_space
            } else if line_end > start {
                line_end -= 1
            }
            break
        }

        line_end += 1
    }

    if line_end == start && line_end < len(text) && text[line_end] != '\n' {
        line_end += 1
    }

    next_start := line_end
    if next_start < len(text) && text[next_start] == '\n' {
        next_start += 1
    } else {
        for next_start < len(text) && (text[next_start] == ' ' || text[next_start] == '\t') {
            next_start += 1
        }
    }

    return start, line_end, next_start
}

//   Count wrapped line rows needed for given text and width.
count_wrapped_text_rows :: proc(text: string, max_chars: int) -> int {
    if len(text) == 0 {
        return 1
    }

    rows := 0
    start := 0
    for start < len(text) {
        _, _, next_start := next_wrapped_text_span(text, start, max_chars)
        rows += 1
        if next_start <= start {
            break
        }
        start = next_start
    }

    return rows
}

//   Draw wrapped text rows clipped to the visible panel area.
draw_wrapped_text_content :: proc(
    text: string,
    panel: rl.Rectangle,
    scroll_y: f32,
    font: rl.Font,
    text_padding: f32,
    text_row_height: f32,
    text_color: rl.Color,
    wrap_advance: f32,
    font_size: f32) {

    max_chars := chars_per_text_row(panel.width - text_padding * 2, wrap_advance)
    start := 0
    row := 0

    if len(text) == 0 {
        ui_text("", int(panel.x + text_padding), int(panel.y + text_padding),
            text_color, font, font_size)
        return
    }

    for start < len(text) {
        line_start, line_end, next_start := next_wrapped_text_span(text, start, max_chars)
        row_y := panel.y + text_padding + f32(row) * text_row_height - scroll_y

        if row_y + text_row_height >= panel.y && row_y <= panel.y + panel.height {
            ui_text(text[line_start:line_end],
                int(panel.x + text_padding), int(row_y), text_color, font, font_size)
        }

        row += 1
        if next_start <= start {
            break
        }
        start = next_start
    }
}

package view_core

import "../../dynview"

import "core:strings"

import rl "vendor:raylib"


//   Draw UTF-8 UI text using temp C-string conversion.
ui_text :: #force_inline proc(
    text: string, x, y: int, color: rl.Color,
    font: rl.Font, font_size: f32 = TREE_FONT_SIZE) {
    cloned := strings.clone_to_cstring(text, context.temp_allocator)
    rl.DrawTextEx(font, cloned, rl.Vector2{f32(x), f32(y)}, font_size, 0, color)
}

//   Draw UTF-8 UI text using float coordinates to avoid pixel snap artifacts.
ui_text_f32 :: #force_inline proc(
    text: string, x, y: f32, color: rl.Color,
    font: rl.Font, font_size: f32 = TREE_FONT_SIZE) {
    cloned := strings.clone_to_cstring(text, context.temp_allocator)
    rl.DrawTextEx(font, cloned, rl.Vector2{x, y}, font_size, 0, color)
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

    max_chars := dynview.chars_per_text_row(panel.width - text_padding * 2, wrap_advance)
    start := 0
    row := 0

    if len(text) == 0 {
        ui_text("", int(panel.x + text_padding), int(panel.y + text_padding),
            text_color, font, font_size)
        return
    }

    for start < len(text) {
        line_start, line_end, next_start :=
            dynview.next_wrapped_text_span(text, start, max_chars)
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

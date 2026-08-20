package view_core

import "../../dynview"

import "core:strings"

import rl "vendor:raylib"

//   Draw environment for wrapped text content: the clipping panel, scroll
//   offset, font, and typography metrics, grouped so the draw call passes one
//   coherent value.
Wrapped_Text_Content_Params :: struct {
    panel:           rl.Rectangle,
    scroll_y:        f32,
    font:            rl.Font,
    text_padding:    f32,
    text_row_height: f32,
    text_color:      rl.Color,
    wrap_advance:    f32,
    font_size:       f32,
}


//   Font and size pair for UI text draw calls.
Ui_Text_Font :: struct {
    font:      rl.Font,
    font_size: f32,
}

//   Wrap a font with the default UI text size.
ui_text_font :: #force_inline proc(font: rl.Font) -> Ui_Text_Font {
    return Ui_Text_Font{font = font, font_size = TREE_FONT_SIZE}
}

//   Draw UTF-8 UI text using temp C-string conversion.
ui_text :: #force_inline proc(
    text: string, x, y: int, color: rl.Color, font: Ui_Text_Font) {
    cloned := strings.clone_to_cstring(text, context.temp_allocator)
    position := rl.Vector2{f32(x), f32(y)}
    rl.DrawTextEx(font.font, cloned, position, font.font_size, 0, color)
}

//   Draw UTF-8 UI text using float coordinates to avoid pixel snap artifacts.
ui_text_f32 :: #force_inline proc(
    text: string, x, y: f32, color: rl.Color, font: Ui_Text_Font) {
    cloned := strings.clone_to_cstring(text, context.temp_allocator)
    position := rl.Vector2{x, y}
    rl.DrawTextEx(font.font, cloned, position, font.font_size, 0, color)
}

//   Draw wrapped text rows clipped to the visible panel area.
draw_wrapped_text_content :: proc(
    text: string,
    params: Wrapped_Text_Content_Params) {

    panel := params.panel
    scroll_y := params.scroll_y
    font := params.font
    text_padding := params.text_padding
    text_row_height := params.text_row_height
    text_color := params.text_color
    wrap_advance := params.wrap_advance
    font_size := params.font_size

    max_chars := dynview.chars_per_text_row(panel.width - text_padding * 2, wrap_advance)
    start := 0
    row := 0

    if len(text) == 0 {
        ui_text("", int(panel.x + text_padding), int(panel.y + text_padding),
            text_color, Ui_Text_Font{font, font_size})
        return
    }

    for start < len(text) {
        span := dynview.next_wrapped_text_span(text, start, max_chars)
        row_y := panel.y + text_padding + f32(row) * text_row_height - scroll_y

        if row_y + text_row_height >= panel.y && row_y <= panel.y + panel.height {
            ui_text(text[span.line_start:span.line_end],
                int(panel.x + text_padding), int(row_y), text_color,
                Ui_Text_Font{font, font_size})
        }

        row += 1
        if span.next_start <= start {
            break
        }
        start = span.next_start
    }
}

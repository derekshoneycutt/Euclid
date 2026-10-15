package viewtext

import view_font "../../font"
import native "../../native"
import theme "../theme"
import geometry "../../../core/geometry"
import color "../../../core/color"

// draw_encoded_label emits one regular UI label through the portable font cache.
draw_encoded_label :: proc(
    cache: ^view_font.Font_Cache, encoder: ^native.Draw_Encoder,
    text: string, x, y: f32) {
    draw_encoded_colored_label(cache, encoder, text, {x, y}, theme.UI_TEXT_COLOR)
}

// draw_encoded_colored_label shapes a regular UI label with an explicit position and color.
draw_encoded_colored_label :: proc(
    cache: ^view_font.Font_Cache, encoder: ^native.Draw_Encoder,
    text: string, position: geometry.Vector2, draw_color: color.Color_RGBA8) {
    if len(text) == 0 {
        return
    }
    face := view_font.cache_borrow(cache, .Regular)
    _ = ui_text_shaped({
        encoder = encoder,
        resolver = view_font.cache_terminal_resolver(cache),
        key = .Regular,
        text = text,
        position = position,
        color = draw_color,
        font = ui_text_font(face),
    })
}

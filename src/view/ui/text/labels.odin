package viewtext

import view_font "../../font"
import native "../../native"
import theme "../theme"

// draw_encoded_label emits one regular UI label through the portable font cache.
draw_encoded_label :: proc(
    cache: ^view_font.Font_Cache, encoder: ^native.Draw_Encoder,
    text: string, x, y: f32) {
    if len(text) == 0 {
        return
    }
    face := view_font.cache_borrow(cache, .Regular)
    _ = ui_text_shaped({
        encoder = encoder,
        resolver = view_font.cache_terminal_resolver(cache),
        key = .Regular,
        text = text,
        position = {x, y},
        color = theme.UI_TEXT_COLOR,
        font = ui_text_font(face),
    })
}

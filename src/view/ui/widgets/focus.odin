package uiwidgets

import geometry "../../../core/geometry"
import native "../../native"
import theme "../theme"

// draw_encoded_focus_ring keeps keyboard focus visible on both dark and selected fills.
draw_encoded_focus_ring :: proc(
    encoder: ^native.Draw_Encoder, bounds: geometry.Rectangle) {
    _ = native.draw_encoder_rectangle_outline(
        encoder, bounds, 2, theme.draw_color(encoder, .Text))
    inner: geometry.Rectangle = {
        bounds.x + 2, bounds.y + 2, max(0, bounds.width - 4), max(0, bounds.height - 4)}
    _ = native.draw_encoder_rectangle_outline(
        encoder, inner, 1, theme.draw_color(encoder, .Selection_Text))
}

package uiwidgets

import geometry "../../../core/geometry"
import native "../../native"
import theme "../theme"

// draw_encoded_focus_ring keeps keyboard focus visible on both dark and selected fills.
draw_encoded_focus_ring :: proc(
    encoder: ^native.Draw_Encoder, bounds: geometry.Rectangle,
    scale := f32(1)) {
    _ = native.draw_encoder_rectangle_outline(
        encoder, bounds, 2*scale, theme.draw_color(encoder, .Text))
    inner: geometry.Rectangle = {
        bounds.x + 2*scale, bounds.y + 2*scale,
        max(0, bounds.width - 4*scale), max(0, bounds.height - 4*scale)}
    _ = native.draw_encoder_rectangle_outline(
        encoder, inner, scale, theme.draw_color(encoder, .Selection_Text))
}

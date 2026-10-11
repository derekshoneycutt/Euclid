package uiwidgets

import native "../../native"
import geometry "../../../core/geometry"
import theme "../theme"

// draw_encoded_disclosure encodes one collapsed or expanded accordion chevron.
draw_encoded_disclosure :: proc(
    encoder: ^native.Draw_Encoder, rectangle: geometry.Rectangle,
    expanded: bool) {
    center := geometry.Vector2{rectangle.x + rectangle.width * 0.5,
        rectangle.y + rectangle.height * 0.5}
    size := min(rectangle.width, rectangle.height)
    first := geometry.Vector2{-0.25 * size, -0.25 * size}
    middle := geometry.Vector2{0.125 * size, 0}
    last := geometry.Vector2{-0.25 * size, 0.25 * size}
    if expanded {
        first = {-first.y, first.x}
        middle = {-middle.y, middle.x}
        last = {-last.y, last.x}
    }
    thickness := max(f32(1.2), 0.1 * size)
    _ = native.draw_encoder_line(
        encoder, center + first, center + middle, thickness, theme.UI_TEXT_COLOR)
    _ = native.draw_encoder_line(
        encoder, center + middle, center + last, thickness, theme.UI_TEXT_COLOR)
}

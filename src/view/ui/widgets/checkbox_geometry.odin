package uiwidgets

import native "../../native"
import geometry "../../../core/geometry"
import theme "../theme"

// Draw the shared square checkbox without retaining or rendering its borrowed label.
draw_encoded_checkbox_geometry :: proc(
    encoder: ^native.Draw_Encoder, rectangle: geometry.Rectangle, checked: bool) {
    _ = native.draw_encoder_rectangle_outline(
        encoder, rectangle, 1, theme.draw_color(encoder, .Control_Border))
    if !checked {
        return
    }
    first := geometry.Vector2{rectangle.x + 3, rectangle.y + rectangle.height * 0.55}
    second := geometry.Vector2{rectangle.x + 6, rectangle.y + rectangle.height - 3}
    third := geometry.Vector2{rectangle.x + rectangle.width - 3, rectangle.y + 3}
    _ = native.draw_encoder_line(
        encoder, first, second, 1.6, theme.draw_color(encoder, .Text))
    _ = native.draw_encoder_line(
        encoder, second, third, 1.6, theme.draw_color(encoder, .Text))
}

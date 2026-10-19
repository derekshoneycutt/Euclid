#+test
package uisplitter

import native "../../../native"
import testing "core:testing"
import color "../../../../core/color"

// Verify idle splitters stay hidden and hover feedback preserves the original blue and fade.
@(test)
splitter_draw_preserves_hover_only_blue :: proc(t: ^testing.T) {
    vertices: [8]native.Draw_Vertex
    indices: [12]u32
    batches: [1]native.Draw_Batch
    commands: [1]native.Draw_Command
    encoder: native.Draw_Encoder
    for opacity in ([3]f32{0, 0.5, 1}) {
        testing.expect(t, native.draw_encoder_begin(&encoder,
            {vertices[:], indices[:], batches[:], commands[:], nil},
            {100, 100}, {100, 100}))
        draw_encoded_splitters(&encoder, {
            vertical = {
                present = true, opacity = opacity, visible_rect = {20, 0, 3, 100},
            },
            horizontal = {
                present = true, opacity = opacity, visible_rect = {0, 40, 100, 3},
            },
        })
        testing.expect_value(t, encoder.vertex_count, 0 if opacity == 0 else 8)
        for vertex in vertices[:encoder.vertex_count] {
            testing.expect_value(t, vertex.color,
                color.Color_RGBA8{70, 130, 180, u8(255 * opacity)})
        }
    }
}

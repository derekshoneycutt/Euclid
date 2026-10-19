#+test
package uiwidgets

import native "../../native"
import testing "core:testing"
import theme "../theme"

// Verify focus has contrasting light and dark edges without depending on the control fill.
@(test)
focus_ring_draws_two_contrasting_edges :: proc(t: ^testing.T) {
    vertices: [16]native.Draw_Vertex
    indices: [48]u32
    batches: [1]native.Draw_Batch
    commands: [1]native.Draw_Command
    encoder: native.Draw_Encoder
    testing.expect(t, native.draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:], commands[:], nil},
        {100, 100}, {100, 100}))
    draw_encoded_focus_ring(&encoder, {10, 20, 40, 24})
    testing.expect_value(t, encoder.vertex_count, 16)
    for vertex, index in vertices {
        expected := theme.UI_TEXT_COLOR if index < 8 else theme.UI_SELECTION_TEXT_COLOR
        testing.expect_value(t, vertex.color, expected)
    }
}

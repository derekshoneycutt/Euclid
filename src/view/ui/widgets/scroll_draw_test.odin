#+test
package uiwidgets

import testing "core:testing"
import geometry "../../../core/geometry"
import native "../../native"
import theme "../theme"
import worldmodel "../../world/model"

// Verify overflow draws the exact prepared hit-test track and thumb in UI colors.
@(test)
scrollbar_draw_matches_prepared_geometry :: proc(t: ^testing.T) {
    vertices: [8]native.Draw_Vertex
    indices: [12]u32
    batches: [1]native.Draw_Batch
    commands: [1]native.Draw_Command
    encoder: native.Draw_Encoder
    testing.expect(t, native.draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:], commands[:], nil},
        {200, 200}, {200, 200}))
    offsets := [3]f32{0, 150, 300}
    for scroll_y in offsets {
        scrollbar := build_vertical_scrollbar(
            {{10, 20, 100, 100}, 400, scroll_y, 300},
            theme.SCROLLBAR_WIDTH, theme.SCROLLBAR_THUMB_MIN_HEIGHT)
        draw_encoded_scrollbar(&encoder, scrollbar)
        testing.expect_value(t, encoder.vertex_count, 8)
        testing.expect_value(t, encoder.index_count, 12)
        rectangles := [2]geometry.Rectangle{
            scrollbar.track_rect, scrollbar.thumb_rect}
        for rect, index in rectangles {
            testing.expect_value(t, vertices[index * 4].position,
                geometry.Vector2{rect.x, rect.y})
            testing.expect_value(t, vertices[index * 4 + 2].position,
                geometry.Vector2{rect.x + rect.width, rect.y + rect.height})
        }
        testing.expect_value(t, vertices[0].color, worldmodel.BACKGROUND_COLOR)
        testing.expect_value(t, vertices[4].color, theme.UI_BORDER_COLOR)
        testing.expect(t, native.draw_encoder_begin(&encoder,
            {vertices[:], indices[:], batches[:], commands[:], nil},
            {200, 200}, {200, 200}))
    }
}

// Verify fitting and empty content do not emit scrollbar primitives.
@(test)
scrollbar_draw_omits_non_overflowing_content :: proc(t: ^testing.T) {
    vertices: [8]native.Draw_Vertex
    indices: [12]u32
    batches: [1]native.Draw_Batch
    commands: [1]native.Draw_Command
    encoder: native.Draw_Encoder
    testing.expect(t, native.draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:], commands[:], nil},
        {200, 200}, {200, 200}))
    heights := [3]f32{0, 50, 100}
    for content_height in heights {
        scrollbar := build_vertical_scrollbar(
            {{10, 20, 100, 100}, content_height, 0, 0},
            theme.SCROLLBAR_WIDTH, theme.SCROLLBAR_THUMB_MIN_HEIGHT)
        draw_encoded_scrollbar(&encoder, scrollbar)
    }
    testing.expect_value(t, encoder.vertex_count, 0)
    testing.expect_value(t, encoder.index_count, 0)
    testing.expect_value(t, encoder.command_count, 0)
}

#+test
package uipresentation

import geometry "../../../core/geometry"
import theme "../theme"
import testing "core:testing"
import core "../../../core"
import native "../../native"
import uisplitter "../layout/splitter"

// Reading order shares the footer without covering Done, including scaled narrow panes.
@(test)
presentation_note_editor_footer_preserves_both_controls :: proc(t: ^testing.T) {
    widths: [3]f32 = {240, 480, 800}
    scales: [3]int = {100, 150, 200}
    for width in widths {
        for scale in scales {
            panel: geometry.Rectangle = {20, 40, width, 520}
            layout := presentation_note_edit_layout(panel, 0.5, scale)
            testing.expect(t, layout.editor_panel.y+layout.editor_panel.height <=
                layout.order_rect.y)
            testing.expect(t, layout.order_rect.y+layout.order_rect.height <=
                panel.y+panel.height)
            testing.expect(t, layout.done_rect.x+layout.done_rect.width <=
                panel.x+panel.width)
            label_end := layout.order_rect.x+layout.order_rect.width+
                theme.ui_scaled_metric(8, scale)+
                f32(len("Notes on top"))*theme.ui_font_size(scale)
            same_row := layout.order_rect.y == layout.done_rect.y
            testing.expect(t, !same_row || label_end <= layout.done_rect.x)
            testing.expect(t, same_row ||
                layout.order_rect.y+layout.order_rect.height <= layout.done_rect.y)
        }
    }
}

// Keep scaled split regions above their useful minimums when the viewport permits.
@(test)
presentation_note_editor_layout_scales_split_minimums :: proc(t: ^testing.T) {
    panel: geometry.Rectangle = {0, 0, 480, 520}
    layout := presentation_note_edit_layout(panel, 0.1, 150)
    minimum_original := theme.ui_scaled_metric(80, 150)
    minimum_editor := theme.ui_scaled_metric(104, 150)
    testing.expect(t, layout.original_panel.height >= minimum_original)
    testing.expect(t, layout.editor_clip.height >= minimum_editor)
    testing.expect_value(t, layout.splitter.y,
        layout.original_panel.y+layout.original_panel.height)
    testing.expect(t, layout.editor_panel.y+layout.editor_panel.height <=
        layout.done_rect.y)
}

// Compact editor geometry remains ordered and non-overlapping below the minimum size.
@(test)
presentation_note_editor_layout_compacts_without_overlap :: proc(t: ^testing.T) {
    panel: geometry.Rectangle = {0, 0, 240, 90}
    layout := presentation_note_edit_layout(panel, 0.5, 150)
    testing.expect(t, layout.original_panel.height > 0)
    testing.expect(t, layout.splitter.y >=
        layout.original_panel.y+layout.original_panel.height)
    testing.expect(t, layout.editor_clip.y >=
        layout.splitter.y+layout.splitter.height)
    testing.expect(t, layout.editor_panel.y+layout.editor_panel.height <=
        layout.done_rect.y)
    testing.expect(t, layout.done_rect.y+layout.done_rect.height <=
        panel.y+panel.height)
}

// Reading content height never relocates the viewport or inserts an internal frame.
@(test)
presentation_note_reading_uses_stationary_document_viewport :: proc(t: ^testing.T) {
    panel: geometry.Rectangle = {20, 40, 320, 180}
    layout := presentation_note_reading_layout(panel, 1000)
    testing.expect_value(t, layout.original_panel, panel)
    testing.expect_value(t, layout.content_height, f32(1000))
    testing.expect(t, !layout.active && !layout.editing)
    positions: [3]f32 = {0, 400, 820}
    for position in positions {
        views := presentation_interaction_views({
            text_panel = panel,
            note_layout = layout,
            text_percent = 100,
            scroll = {
                view_rect = panel,
                scroll_y_out = position,
            },
        })
        testing.expect_value(t, views.selection.panel, panel)
        testing.expect_value(t, views.selection.scroll_y, position)
        testing.expect_value(t, views.original_screen, panel)
    }
}

// The internal splitter's idle chrome has no accent; hover paints only its narrow line.
@(test)
presentation_note_splitter_only_paints_accent_on_interaction :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    state^.ui_runtime.preferences.values.interface.control_size_percent = 100
    layout := presentation_note_edit_layout({20, 40, 320, 180}, 0.5, 100)
    vertices: [64]native.Draw_Vertex
    indices: [96]u32
    batches: [16]native.Draw_Batch
    commands: [16]native.Draw_Command
    encoder: native.Draw_Encoder
    hover_states: [2]bool = {false, true}
    for hovered in hover_states {
        testing.expect(t, native.draw_encoder_begin(&encoder,
            {vertices[:], indices[:], batches[:], commands[:], nil},
            {400, 300}, {400, 300}))
        state^.ui_runtime.library.collection_note.splitter_hovered = hovered
        presentation_draw_note_geometry(state, &encoder, &layout)
        accent_vertices := 0
        for vertex in vertices[:encoder.vertex_count] {
            if vertex.color == uisplitter.SPLITTER_ACTIVE_COLOR {
                accent_vertices += 1
                testing.expect(t, vertex.position.y >= layout.splitter.y)
                testing.expect(t, vertex.position.y <=
                    layout.splitter.y+layout.splitter.height)
            }
        }
        testing.expect_value(t, accent_vertices, 4 if hovered else 0)
        testing.expect_value(t, encoder.scissor_count, 1)
    }
}

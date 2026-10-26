#+test
package uiwidgets

import testing "core:testing"
import native "../../native"
import view_font "../../font"
import viewmodel "../model"
import theme "../theme"

Input_Box_Draw_Fixture :: struct {
    shape_calls: int,
    complete_source: bool,
}

// input_box_draw_shape verifies each clipped draw shapes the entire UTF-8 source.
input_box_draw_shape :: proc(
    data: rawptr, _: view_font.Font_Key, text: string,
    output: []view_font.Shaped_Glyph) -> (int, bool) {
    state := cast(^Input_Box_Draw_Fixture)data
    state^.shape_calls += 1
    state^.complete_source = state^.complete_source && text == "aβc"
    if len(output) < 3 {
        return 0, false
    }
    clusters: [3]u32 = {0, 1, 3}
    for cluster, index in clusters {
        output[index] = {
            glyph_id = u32(index + 1),
            cluster = cluster,
            x_advance = 1024,
        }
    }
    return 3, true
}

// input_box_draw_glyph supplies one resident raster without native font resources.
input_box_draw_glyph :: proc(
    _: rawptr, _: view_font.Font_Key, id: u32,
    _: view_font.Font_Raster_Request) -> (view_font.Resolved_Glyph, bool) {
    return {
        glyph_id = id,
        texture = {
            handle = rawptr(uintptr(1)),
            width = 32,
            height = 32,
        },
        source = {
            width = 8,
            height = 10,
        },
        raster_pixel_height = 32,
        raster_ascent = 24,
        canonical_pixel_height = 32,
        canonical_raster_ascent = 24,
        canonical_advance_x = 16,
        raster_slot_index = 1,
        raster_slot_incarnation = 2,
    }, true
}

// Verify partial, full, reversed, scrolled and empty selections preserve whole-run shaping.
@(test)
input_box_draw_selection_preserves_shaped_positions :: proc(t: ^testing.T) {
    vertices: [256]native.Draw_Vertex
    indices: [384]u32
    batches: [16]native.Draw_Batch
    commands: [16]native.Draw_Command
    workspace: [4]view_font.Shaped_Glyph
    encoder: native.Draw_Encoder
    selections := [?][3]int{{1, 3, 0}, {3, 1, 8}, {0, 4, 0}, {4, 0, 16}, {1, 1, 0}}
    for selection in selections {
        fixture: Input_Box_Draw_Fixture = {
            complete_source = true,
        }
        state: viewmodel.Ui_Input_Box_State = {
            anchor_byte = selection[0],
            cursor_byte = selection[1],
            scroll_x = f32(selection[2]),
        }
        params: Input_Box_Params = {
            rect = {10, 20, 64, 24},
            clip_rect = {10, 20, 64, 24},
            descriptor = {
                text = "aβc",
            },
            state = &state,
            column_advance = 8,
            font = {
                base_size = 32,
                space_advance = 16,
            },
            resolver = {
                user_data = &fixture,
                shape = input_box_draw_shape,
                resolve_glyph = input_box_draw_glyph,
                workspace = workspace[:],
            },
        }
        prepared := input_box_draw_result(params, false)
        testing.expect(t, native.draw_encoder_begin(&encoder,
            {vertices[:], indices[:], batches[:], commands[:], nil},
            {200, 100}, {200, 100}))
        _ = native.draw_encoder_push_scissor(&encoder, prepared.inner)
        draw_encoded_input_box_text(&encoder, params, prepared)
        _ = native.draw_encoder_pop_scissor(&encoder)
        testing.expect(t, fixture.complete_source && fixture.shape_calls > 0)
        testing.expect_value(t, encoder.scissor_count, 1)
        testing.expect_value(t, encoder.statistics.command_overflows, u32(0))
        testing.expect_value(t,
            input_box_has_selected_vertices(vertices[:encoder.vertex_count]),
            selection[0] != selection[1])
        if encoder.vertex_count >= 24 {
            testing.expect_value(t, vertices[0].position, vertices[12].position)
        }
    }
}

// Report whether the encoded text includes the selected foreground.
input_box_has_selected_vertices :: proc(vertices: []native.Draw_Vertex) -> bool {
    for vertex in vertices {
        if vertex.color == theme.UI_SELECTION_TEXT_COLOR {
            return true
        }
    }
    return false
}

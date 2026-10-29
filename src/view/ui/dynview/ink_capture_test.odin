package ui_dynview

import core "../../../core"
import dynviewmodel "../../../dynview/model"
import dyncore "../../../dynview/core"
import font "../../font"
import native "../../native"
import testing "core:testing"

Ink_Encoding_Test :: struct {
    vertices: [64]native.Draw_Vertex,
    indices: [96]u32,
    batches: [1]native.Draw_Batch,
    commands: [1]native.Draw_Command,
    encoder: native.Draw_Encoder,
}

// ink_encoding_test_begin reuses fixed storage and resets only the current frame.
ink_encoding_test_begin :: proc(t: ^testing.T, draw: ^Ink_Encoding_Test) {
    testing.expect(t, native.draw_encoder_begin(&draw^.encoder,
        {draw^.vertices[:], draw^.indices[:], draw^.batches[:], draw^.commands[:], nil},
        {100, 100}, {100, 100}))
}

// Verify real geometry captures original edge ink while defaults and live toggles stay independent.
@(test)
dynview_ink_capture_preserves_authored_edges_and_default_text :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    testing.expect(t,
        font.cache_ink_capture_init(&state^.font_cache, context.allocator))
    defer font.cache_ink_capture_destroy(&state^.font_cache, context.allocator)
    draw: Ink_Encoding_Test
    expected: [4]dynviewmodel.Color = {
        {70, 130, 180, 77}, {185, 185, 185, 77},
        {212, 212, 212, 77}, {70, 130, 180, 77}}
    item: dynviewmodel.Dynview_Layout_Item = {
        kind = .Inline_Box,
        draw_width = 20,
        draw_height = 20,
        inline_atom_stroke = 2,
        shape_edge_color_1 = {70, 130, 180, 77},
    }
    for tint, index in expected {
        state^.ui_runtime.preferences.values.animation.monochrome =
            index == 1 || index == 2
        state^.ui_runtime.platform_increased_contrast = index >= 2
        ink_encoding_test_begin(t, &draw)
        font.cache_ink_capture_begin(&state^.font_cache)
        native.draw_encoder_set_ink_sink(&draw.encoder, {
            user_data = &state^.font_cache,
            record = font.cache_ink_capture_sample,
        })
        encode_inline_item(&draw.encoder, item, 10, 20, {
            state = state,
        })
        testing.expect_value(t, draw.vertices[0].color, tint)
        testing.expect_value(t, draw.vertices[4].color, dyncore.STYLE_DEFAULT.color)
        dynview_ink_capture_test_samples(t, state)
        testing.expect(t, !draw.encoder.ink_sink.authored)
        testing.expect_value(t, item.shape_edge_color_1, expected[0])
    }
}

// dynview_ink_capture_test_samples checks sample provenance independently of resolved vertex colors.
dynview_ink_capture_test_samples :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State) {
    font.cache_ink_capture_mark_drawn(&state^.font_cache)
    font.cache_ink_capture_publish(&state^.font_cache)
    authored_count, ordinary_count := 0, 0
    for sample in font.cache_visible_ink_samples(&state^.font_cache) {
        if sample.authored {
            authored_count += 1
            testing.expect_value(t, sample.color, [4]u8{70, 130, 180, 77})
        } else {
            ordinary_count += 1
            testing.expect_value(t, sample.color, cast([4]u8)dyncore.STYLE_DEFAULT.color)
        }
    }
    testing.expect(t, authored_count > 0 && ordinary_count > 0)
}

// Verify inline math rules keep inherited authored ink through display-only encoding.
@(test)
dynview_ink_capture_math_rules_use_inherited_color :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    state^.ui_runtime.preferences.values.animation.monochrome = true
    draw: Ink_Encoding_Test
    ink_encoding_test_begin(t, &draw)
    item: dynviewmodel.Dynview_Layout_Item = {
        kind = .Frac,
        ascent = 10,
        fraction_rule_right = 20,
        fraction_rule_thickness = 2,
    }
    encode_inline_item(&draw.encoder, item, 10, 20, {
        state = state,
        authored_ink = {255, 130, 171, 90},
        has_authored_ink = true,
    })
    testing.expect_value(t,
        draw.vertices[0].color, dynviewmodel.Color{230, 230, 230, 90})
}

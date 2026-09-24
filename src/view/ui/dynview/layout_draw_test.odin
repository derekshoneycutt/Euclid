package ui_dynview

import dynviewmodel "../../../dynview/model"
import native "../../native"

import "core:testing"

import dynmath "../../../dynview/math"

//   Verify stacked limits remain inside the large operator's measured box.
@(test)
layout_draw_test_large_op_limit_tops_match_measured_stack :: proc(t: ^testing.T) {
    metrics := Large_Op_Metrics{
        glyph_ascent = 20,
        glyph_descent = 8,
        sup_height = 6,
        limit_gap = 2,
        sup_cols = 1,
    }

    sup_top := large_op_limit_top(metrics, 10, .Superscript)
    sub_top := large_op_limit_top(metrics, 10, .Subscript)

    testing.expect_value(t, sup_top, f32(10))
    testing.expect_value(t, sub_top, f32(48))
}

//   Verify delimiter children retain scoped text style during recursive drawing.
@(test)
layout_draw_test_stretch_delimiter_preserves_child_style :: proc(t: ^testing.T) {
    item := dynviewmodel.Dynview_Layout_Item{
        math_style_level = u8(dynmath.Math_Style_Level.Text),
        math_style_cramped = true,
    }
    testing.expect_value(t, stretch_delimiter_child_style(item),
        dynmath.Math_Style{.Text, true})
}

// Verify authoritative document shapes append to the active native encoder.
@(test)
layout_draw_test_document_shape_uses_native_encoder :: proc(t: ^testing.T) {
    inlines := [1]dynviewmodel.Dynview_Document_Inline{{
        kind = .Shape,
        shape = {present = true, kind = .Line, width = 4, thickness = 2},
    }}
    runtime := new(dynviewmodel.Dynview_System, context.allocator)
    defer free(runtime, context.allocator)
    runtime^.content.document_inlines = inlines[:]
    runtime^.compile_cache.last_cell_width = 8
    vertices: [4]native.Draw_Vertex
    indices: [6]u32
    batches: [1]native.Draw_Batch
    commands: [1]native.Draw_Command
    encoder: native.Draw_Encoder
    testing.expect(t, native.draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:], commands[:], nil},
        {100, 100}, {100, 100}))

    draw_document_item({encoder = &encoder, runtime = runtime}, {
        box_kind = .Shape, inline_index = 0,
    }, {10, 20})

    testing.expect_value(t, encoder.vertex_count, 4)
    testing.expect_value(t, encoder.index_count, 6)
}

// Verify document box edges retain explicit colors and inherit only when absent.
@(test)
layout_draw_test_document_box_encodes_independent_edge_colors :: proc(t: ^testing.T) {
    fallback := dynviewmodel.Color{10, 20, 30, 255}
    edge_1 := dynviewmodel.Color{200, 10, 20, 255}
    edge_2 := dynviewmodel.Color{20, 200, 30, 255}
    edge_3 := dynviewmodel.Color{30, 40, 200, 255}
    shape := dynviewmodel.Dynview_Document_Shape{
        present = true, kind = .Box, color = {true, fallback},
        width = 4, height = 3, thickness = 2,
        edge_colors = {{true, edge_1}, {true, edge_2}, {true, edge_3}, {}, {}},
    }
    item, ok := document_shape_draw_item({}, shape, 8)
    testing.expect(t, ok)
    testing.expect_value(t, item.shape_edge_color_4, dynviewmodel.Color{})
    vertices: [16]native.Draw_Vertex
    indices: [24]u32
    batches: [1]native.Draw_Batch
    commands: [1]native.Draw_Command
    encoder: native.Draw_Encoder
    testing.expect(t, native.draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:], commands[:], nil},
        {100, 100}, {100, 100}))

    encode_inline_item(&encoder, item, 10, 20)

    testing.expect_value(t, encoder.vertex_count, 16)
    testing.expect_value(t, vertices[0].color, edge_1)
    testing.expect_value(t, vertices[4].color, edge_2)
    testing.expect_value(t, vertices[8].color, edge_3)
    testing.expect_value(t, vertices[12].color, fallback)
}

// Verify triangle edge colors follow the documented left, base, right order.
@(test)
layout_draw_test_triangle_encodes_independent_edge_colors :: proc(t: ^testing.T) {
    edge_1 := dynviewmodel.Color{200, 10, 20, 255}
    edge_2 := dynviewmodel.Color{20, 200, 30, 255}
    edge_3 := dynviewmodel.Color{30, 40, 200, 255}
    vertices: [12]native.Draw_Vertex
    indices: [18]u32
    batches: [1]native.Draw_Batch
    commands: [1]native.Draw_Command
    encoder: native.Draw_Encoder
    testing.expect(t, native.draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:], commands[:], nil},
        {100, 100}, {100, 100}))
    item := dynviewmodel.Dynview_Layout_Item{
        kind = .Inline_Triangle, draw_width = 20, draw_height = 20,
        inline_atom_stroke = 2, shape_edge_color_1 = edge_1,
        shape_edge_color_2 = edge_2, shape_edge_color_3 = edge_3,
    }

    encode_inline_item(&encoder, item, 10, 20)

    testing.expect_value(t, encoder.vertex_count, 12)
    testing.expect_value(t, vertices[0].color, edge_1)
    testing.expect_value(t, vertices[4].color, edge_2)
    testing.expect_value(t, vertices[8].color, edge_3)
}

// Verify perpendicular geometry centers its stem and preserves both line colors.
@(test)
layout_draw_test_document_perpendicular_encodes_centered_colored_stem :: proc(
    t: ^testing.T) {
    base_color := dynviewmodel.Color{220, 40, 30, 255}
    stem_color := dynviewmodel.Color{30, 90, 220, 255}
    shape := dynviewmodel.Dynview_Document_Shape{
        present = true, kind = .Perpendicular, fill_color = {true, base_color},
        width = 2, height = 2, thickness = 2,
        edge_colors = {{true, stem_color}, {}, {}, {}, {}},
    }
    item, ok := document_shape_draw_item({}, shape, 10)
    testing.expect(t, ok)
    vertices: [8]native.Draw_Vertex
    indices: [12]u32
    batches: [1]native.Draw_Batch
    commands: [1]native.Draw_Command
    encoder: native.Draw_Encoder
    testing.expect(t, native.draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:], commands[:], nil},
        {100, 100}, {100, 100}))

    encode_inline_item(&encoder, item, 10, 20)

    testing.expect_value(t, encoder.vertex_count, 8)
    testing.expect_value(t, vertices[0].color, base_color)
    testing.expect_value(t, vertices[4].color, stem_color)
    stem_center_x := (vertices[4].position.x + vertices[6].position.x) * 0.5
    testing.expect_value(t, stem_center_x, 10 + item.draw_width * 0.5)
}

// Verify outlined and filled document arcs append native geometry with their colors.
@(test)
layout_draw_test_document_arcs_encode_outline_and_fill :: proc(t: ^testing.T) {
    fill := dynviewmodel.Color{15, 120, 220, 255}
    outline := dynviewmodel.Color{230, 80, 25, 255}
    vertices: [128]native.Draw_Vertex
    indices: [256]u32
    batches: [1]native.Draw_Batch
    commands: [1]native.Draw_Command
    encoder: native.Draw_Encoder
    testing.expect(t, native.draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:], commands[:], nil},
        {100, 100}, {100, 100}))
    item := dynviewmodel.Dynview_Layout_Item{
        kind = .Inline_Pie_Section, draw_width = 24, draw_height = 24,
        inline_atom_stroke = 2, inline_outline_stroke = 2,
        pie_start_angle_degrees = 0, pie_end_angle_degrees = 90,
        pie_center_offset_x = 2, pie_center_offset_y = 22,
        has_brush_color = true, brush_color = fill,
        has_outline_color = true, outline_color = outline,
    }

    encode_inline_item(&encoder, item, 10, 20)
    outline_vertex_count := encoder.vertex_count
    testing.expect(t, outline_vertex_count > 0)
    testing.expect_value(t, vertices[0].color, outline)
    item.pie_is_filled = true
    item.inline_outline_stroke = 0
    encode_inline_item(&encoder, item, 40, 20)

    testing.expect(t, encoder.vertex_count > outline_vertex_count)
    testing.expect_value(t, vertices[outline_vertex_count].color, fill)
}
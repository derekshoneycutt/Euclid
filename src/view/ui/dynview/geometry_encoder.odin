package ui_dynview

import native "../../native"

import geometry "../../../core/geometry"
import dyncore "../../../dynview/core"
import dynlayout "../../../dynview/layout"
import dynviewmodel "../../../dynview/model"

// encode_rule encodes one horizontal rule from sealed item-local geometry.
encode_rule :: proc(
    encoder: ^native.Draw_Encoder, item_x, baseline, left, right, center,
    thickness: f32, draw_color: dynviewmodel.Color) {
    _ = native.draw_encoder_line(encoder,
        {item_x + left, baseline + center},
        {item_x + right, baseline + center},
        max(1, thickness), draw_color)
}

// encode_box encodes one outlined or filled Dynview box.
encode_box :: proc(
    encoder: ^native.Draw_Encoder, item: dynviewmodel.Dynview_Layout_Item,
    item_x, item_y: f32, draw_color: dynviewmodel.Color, filled: bool) {
    rectangle := geometry.Rectangle{item_x, item_y, item.draw_width, item.draw_height}
    if filled {
        _ = native.draw_encoder_rectangle(encoder, rectangle, draw_color)
    }
    stroke := max(1, item.inline_atom_stroke)
    if !filled || item.inline_outline_stroke > 0 {
        _ = native.draw_encoder_rectangle_outline(
            encoder, rectangle, stroke, draw_color)
    }
}

// encode_circle encodes one outlined or filled Dynview circle.
encode_circle :: proc(
    encoder: ^native.Draw_Encoder, item: dynviewmodel.Dynview_Layout_Item,
    item_x, item_y: f32, draw_color: dynviewmodel.Color, filled: bool) {
    center := geometry.Vector2{item_x + item.draw_width * 0.5,
        item_y + item.draw_height * 0.5}
    radius := max(0.5, min(item.draw_width, item.draw_height) * 0.5)
    if filled {
        _ = native.draw_encoder_circle(encoder, center, radius, draw_color)
    }
    stroke := max(1, item.inline_atom_stroke)
    if !filled || item.inline_outline_stroke > 0 {
        _ = native.draw_encoder_ring(
            encoder, center, max(0, radius - stroke), radius, draw_color)
    }
}

// encode_polygon encodes a filled polygon fan and its closed outline.
encode_polygon :: proc(
    encoder: ^native.Draw_Encoder, points: []geometry.Vector2,
    draw_color: dynviewmodel.Color, filled: bool, stroke: f32) {
    if len(points) < 3 {return}
    if filled {
        for index in 1..<len(points)-1 {
            _ = native.draw_encoder_triangle(
                encoder, points[0], points[index], points[index+1], draw_color)
        }
    }
    for index in 0..<len(points) {
        _ = native.draw_encoder_line(encoder, points[index],
            points[(index+1)%len(points)], stroke, draw_color)
    }
}

// encode_inline_polygon encodes one cached triangle or pentagon atom.
encode_inline_polygon :: proc(
    encoder: ^native.Draw_Encoder, item: dynviewmodel.Dynview_Layout_Item,
    item_x, item_y: f32, draw_color: dynviewmodel.Color) {
    if item.kind == .Inline_Triangle {
        points := [3]geometry.Vector2{{item_x + item.draw_width * 0.5, item_y},
            {item_x + item.draw_width, item_y + item.draw_height},
            {item_x, item_y + item.draw_height}}
        encode_polygon(encoder, points[:], draw_color, item.shape_is_filled,
            max(1, item.inline_atom_stroke))
        return
    }
    points := [5]geometry.Vector2{{item_x + item.draw_width * 0.5, item_y},
        {item_x + item.draw_width, item_y + item.draw_height * 0.38},
        {item_x + item.draw_width * 0.81, item_y + item.draw_height},
        {item_x + item.draw_width * 0.19, item_y + item.draw_height},
        {item_x, item_y + item.draw_height * 0.38}}
    encode_polygon(encoder, points[:], draw_color, item.shape_is_filled,
        max(1, item.inline_atom_stroke))
}

// encode_inline_item encodes one font-independent cached Dynview item.
encode_inline_item :: proc(
    encoder: ^native.Draw_Encoder, item: dynviewmodel.Dynview_Layout_Item,
    item_x, item_y: f32) {
    style := dyncore.style_by_id(item.style_id)
    draw_color := dynlayout.inline_draw_color(style, item)
    center_y := item_y + item.draw_height * 0.5
    switch item.kind {
    case .Inline_Line:
        stroke := max(1, item.inline_atom_stroke)
        _ = native.draw_encoder_line(encoder, {item_x, center_y},
            {item_x + item.draw_width, center_y}, stroke, draw_color)
    case .Inline_Box:
        encode_box(encoder, item, item_x, item_y, draw_color, false)
    case .Inline_Filled_Box:
        encode_box(encoder, item, item_x, item_y, draw_color, true)
    case .Inline_Circle:
        encode_circle(encoder, item, item_x, item_y, draw_color, false)
    case .Inline_Filled_Circle:
        encode_circle(encoder, item, item_x, item_y, draw_color, true)
    case .Inline_Perpendicular:
        stroke := max(1, item.inline_atom_stroke)
        _ = native.draw_encoder_line(encoder, {item_x, item_y},
            {item_x, item_y + item.draw_height}, stroke, draw_color)
        _ = native.draw_encoder_line(encoder, {item_x, item_y + item.draw_height},
            {item_x + item.draw_width, item_y + item.draw_height}, stroke, draw_color)
    case .Inline_Triangle, .Inline_Pentagon:
        encode_inline_polygon(encoder, item, item_x, item_y, draw_color)
    case .Frac:
        encode_rule(encoder, item_x, item_y + item.ascent,
            item.fraction_rule_left, item.fraction_rule_right,
            item.fraction_rule_center, item.fraction_rule_thickness, style.color)
    case .Accent_Bar:
        encode_rule(encoder, item_x, item_y + item.ascent,
            item.accent_rule_left, item.accent_rule_right,
            item.accent_rule_center, item.accent_rule_thickness, style.color)
    case .Radical_Bar:
        encode_rule(encoder, item_x, item_y + item.ascent,
            item.radical_rule_left, item.radical_rule_right,
            item.radical_rule_center, item.radical_rule_thickness, style.color)
    case .Text_Run, .Math_Glyph_Run, .Math_Block, .Script_Attach,
        .Stretch_Delimiter, .Matrix, .Style_Override, .Stack, .Large_Op,
        .Inline_Pie_Section:
    }
}

// draw_encoded_geometry encodes cached Dynview geometry inside the presentation clip.
draw_encoded_geometry :: proc(
    runtime: ^dynviewmodel.Dynview_System, encoder: ^native.Draw_Encoder,
    panel: geometry.Rectangle, scroll_y, text_padding: f32) {
    if runtime == nil || !runtime^.compile_cache.layout_is_valid {return}
    cache := &runtime^.compile_cache
    _ = native.draw_encoder_push_scissor(encoder, panel)
    for line_index in 0..<cache^.layout_line_count {
        line := cache^.layout_lines[line_index]
        line_top := panel.y + text_padding +
            f32(line.row_start) * cache^.last_cell_height - scroll_y
        for item_index in line.item_start..<line.item_start+line.item_count {
            item := cache^.layout_items[item_index]
            item_x := panel.x + text_padding +
                f32(item.col_start) * cache^.last_cell_width + item.content_offset_x
            item_y := line_top + f32(item.row_offset) * cache^.last_cell_height +
                item.content_offset_y
            encode_inline_item(encoder, item, item_x, item_y)
        }
    }
    _ = native.draw_encoder_pop_scissor(encoder)
}

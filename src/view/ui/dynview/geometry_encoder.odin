package ui_dynview

import native "../../native"

import geometry "../../../core/geometry"
import dyncore "../../../dynview/core"
import dynlayout "../../../dynview/layout"
import dynviewmodel "../../../dynview/model"

import "core:math"

// Polygon_Encode_Style groups one polygon's fill and independent edge policy.
Polygon_Encode_Style :: struct {
    edge_colors: []dynviewmodel.Color,
    draw_color: dynviewmodel.Color,
    filled: bool,
    stroke: f32,
}

// encode_edge_color returns an explicit edge color or its inherited fallback.
encode_edge_color :: #force_inline proc(
    edge_color, fallback: dynviewmodel.Color) -> dynviewmodel.Color {
    if edge_color == {} {return fallback}
    return edge_color
}

// encode_rule encodes one horizontal rule from sealed item-local geometry.
encode_rule :: proc(
    encoder: ^native.Draw_Encoder, item_x, baseline, left, right, center,
    thickness: f32, draw_color: dynviewmodel.Color) {
    _ = native.draw_encoder_line(encoder,
        {item_x + left, baseline + center},
        {item_x + right, baseline + center},
        max(1, thickness), draw_color)
}

// encode_box encodes one outlined or filled Dynview box with independent edges.
encode_box :: proc(
    encoder: ^native.Draw_Encoder, item: dynviewmodel.Dynview_Layout_Item,
    item_x, item_y: f32, draw_color: dynviewmodel.Color, filled: bool) {
    rectangle := geometry.Rectangle{item_x, item_y, item.draw_width, item.draw_height}
    if filled {
        _ = native.draw_encoder_rectangle(encoder, rectangle, draw_color)
    }
    stroke := max(1, item.inline_atom_stroke)
    if !filled || item.inline_outline_stroke > 0 {
        top_left := geometry.Vector2{rectangle.x, rectangle.y}
        top_right := geometry.Vector2{rectangle.x + rectangle.width, rectangle.y}
        bottom_right := geometry.Vector2{
            rectangle.x + rectangle.width, rectangle.y + rectangle.height}
        bottom_left := geometry.Vector2{rectangle.x, rectangle.y + rectangle.height}
        _ = native.draw_encoder_line(encoder, top_left, top_right, stroke,
            encode_edge_color(item.shape_edge_color_1, draw_color))
        _ = native.draw_encoder_line(encoder, top_right, bottom_right, stroke,
            encode_edge_color(item.shape_edge_color_2, draw_color))
        _ = native.draw_encoder_line(encoder, bottom_right, bottom_left, stroke,
            encode_edge_color(item.shape_edge_color_3, draw_color))
        _ = native.draw_encoder_line(encoder, bottom_left, top_left, stroke,
            encode_edge_color(item.shape_edge_color_4, draw_color))
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

// encode_polygon encodes a filled polygon fan and its independently colored outline.
encode_polygon :: proc(
    encoder: ^native.Draw_Encoder, points: []geometry.Vector2,
    style: Polygon_Encode_Style) {
    if len(points) < 3 {return}
    if style.filled {
        for index in 1..<len(points)-1 {
            _ = native.draw_encoder_triangle(
                encoder, points[0], points[index], points[index+1], style.draw_color)
        }
    }
    for index in 0..<len(points) {
        edge_color := style.draw_color
        if index < len(style.edge_colors) {
            edge_color = encode_edge_color(
                style.edge_colors[index], style.draw_color)
        }
        _ = native.draw_encoder_line(encoder, points[index],
            points[(index+1)%len(points)], style.stroke, edge_color)
    }
}

// encode_inline_polygon encodes one cached triangle or pentagon atom.
encode_inline_polygon :: proc(
    encoder: ^native.Draw_Encoder, item: dynviewmodel.Dynview_Layout_Item,
    item_x, item_y: f32, draw_color: dynviewmodel.Color) {
    if item.kind == .Inline_Triangle {
        points := [3]geometry.Vector2{{item_x + item.draw_width * 0.5, item_y},
            {item_x, item_y + item.draw_height},
            {item_x + item.draw_width, item_y + item.draw_height}}
        edge_colors := [3]dynviewmodel.Color{item.shape_edge_color_1,
            item.shape_edge_color_2, item.shape_edge_color_3}
        encode_polygon(encoder, points[:], {edge_colors[:], draw_color,
            item.shape_is_filled, max(1, item.inline_atom_stroke)})
        return
    }
    points := [5]geometry.Vector2{{item_x + item.draw_width * 0.5, item_y},
        {item_x + item.draw_width, item_y + item.draw_height * 0.38},
        {item_x + item.draw_width * 0.81, item_y + item.draw_height},
        {item_x + item.draw_width * 0.19, item_y + item.draw_height},
        {item_x, item_y + item.draw_height * 0.38}}
    edge_colors := [5]dynviewmodel.Color{item.shape_edge_color_1,
        item.shape_edge_color_2, item.shape_edge_color_3,
        item.shape_edge_color_4, item.shape_edge_color_5}
    encode_polygon(encoder, points[:], {edge_colors[:], draw_color,
        item.shape_is_filled, max(1, item.inline_atom_stroke)})
}

// encode_pie_point resolves one clockwise document angle around a pie center.
encode_pie_point :: #force_inline proc(
    center: geometry.Vector2, radius, angle_degrees: f32) -> geometry.Vector2 {
    radians := f64(angle_degrees) * math.PI / 180
    return {center.x + radius * f32(math.cos(radians)),
        center.y - radius * f32(math.sin(radians))}
}

// encode_pie_section encodes one filled or outlined arc with radial edges.
encode_pie_section :: proc(
    encoder: ^native.Draw_Encoder, item: dynviewmodel.Dynview_Layout_Item,
    item_x, item_y: f32, draw_color: dynviewmodel.Color) {
    sweep := positive_sweep_degrees(
        item.pie_start_angle_degrees, item.pie_end_angle_degrees)
    if sweep <= 0 {return}
    center := geometry.Vector2{item_x + item.pie_center_offset_x,
        item_y + item.pie_center_offset_y}
    visual_radius := max(
        max(item.pie_center_offset_x, item.draw_width-item.pie_center_offset_x),
        max(item.pie_center_offset_y, item.draw_height-item.pie_center_offset_y))
    radius := max(0.5, visual_radius-item.inline_atom_stroke*0.5)
    segments := max(1, int(math.ceil(f64(sweep/8))))
    previous := encode_pie_point(center, radius, item.pie_start_angle_degrees)
    outline_color := item.has_outline_color ? item.outline_color : draw_color
    stroke := max(1, item.inline_outline_stroke)
    for index in 0..<segments {
        angle := item.pie_start_angle_degrees +
            sweep*f32(index+1)/f32(segments)
        next := encode_pie_point(center, radius, angle)
        if item.pie_is_filled {
            _ = native.draw_encoder_triangle(encoder, center, previous, next, draw_color)
        }
        if !item.pie_is_filled || item.inline_outline_stroke > 0 {
            _ = native.draw_encoder_line(
                encoder, previous, next, stroke, outline_color)
        }
        previous = next
    }
    if !item.pie_is_filled || item.inline_outline_stroke > 0 {
        start_point := encode_pie_point(
            center, radius, item.pie_start_angle_degrees)
        end_point := encode_pie_point(center, radius, item.pie_end_angle_degrees)
        _ = native.draw_encoder_line(encoder, center, start_point, stroke, outline_color)
        _ = native.draw_encoder_line(encoder, center, end_point, stroke, outline_color)
    }
}

// encode_perpendicular encodes an inset base with one centered vertical stem.
encode_perpendicular :: proc(
    encoder: ^native.Draw_Encoder, item: dynviewmodel.Dynview_Layout_Item,
    item_x, item_y: f32, base_color: dynviewmodel.Color) {
    stroke := max(1, item.inline_atom_stroke)
    inset := stroke * 0.5
    left := item_x + inset
    right := item_x + item.draw_width - inset
    top := item_y + inset
    bottom := item_y + item.draw_height - inset
    stem_x := (left + right) * 0.5
    stem_color := encode_edge_color(item.shape_edge_color_1, base_color)
    _ = native.draw_encoder_line(
        encoder, {left, bottom}, {right, bottom}, stroke, base_color)
    _ = native.draw_encoder_line(
        encoder, {stem_x, top}, {stem_x, bottom}, stroke, stem_color)
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
        encode_perpendicular(encoder, item, item_x, item_y, draw_color)
    case .Inline_Triangle, .Inline_Pentagon:
        encode_inline_polygon(encoder, item, item_x, item_y, draw_color)
    case .Inline_Pie_Section:
        encode_pie_section(encoder, item, item_x, item_y, draw_color)
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
        .Stretch_Delimiter, .Matrix, .Style_Override, .Stack, .Large_Op:
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

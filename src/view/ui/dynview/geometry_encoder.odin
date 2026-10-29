package ui_dynview

import native "../../native"

import geometry "../../../core/geometry"
import dynviewmodel "../../../dynview/model"
import core "../../../core"

import "core:math"

// Inline_Draw_Ink retains authored identity until one primitive is encoded.
Inline_Draw_Ink :: struct {
    color: dynviewmodel.Color,
    authored: bool,
}

// Polygon_Encode_Style groups one polygon's fill and independent edge policy.
Polygon_Encode_Style :: struct {
    edge_colors: []dynviewmodel.Color,
    draw_color: Inline_Draw_Ink,
    filled: bool,
    stroke: f32,
}

Dynview_Geometry_Draw_Params :: struct {
    state: ^core.Euclid_General_State,
    runtime: ^dynviewmodel.Dynview_System,
    encoder: ^native.Draw_Encoder,
    panel: geometry.Rectangle,
    scroll_y: f32,
    text_padding: f32,
}

// Rule_Encode_Geometry describes one horizontal rule relative to an item origin.
Rule_Encode_Geometry :: struct {
    origin: geometry.Vector2,
    left: f32,
    right: f32,
    center: f32,
    thickness: f32,
}

// inline_draw_color records original sample identity and resolves only explicit content ink.
inline_draw_color :: proc(
    ctx: Layout_Draw_Context, ink: Inline_Draw_Ink) -> dynviewmodel.Color {
    _ = dynview_ink_source(ctx.encoder, ink.color, ink.authored)
    if ink.authored {
        return resolve_dynview_authored_ink(ctx, ink.color)
    }
    return ink.color
}

// inline_edge_ink preserves an absent edge's inherited color and provenance.
inline_edge_ink :: proc(
    edge: dynviewmodel.Color, fallback: Inline_Draw_Ink) -> Inline_Draw_Ink {
    if edge == {} {
        return fallback
    }
    return {edge, true}
}

// encode_rule encodes one horizontal rule from sealed item-local geometry.
encode_rule :: proc(
    ctx: Layout_Draw_Context, rule: Rule_Encode_Geometry,
    draw_color: Inline_Draw_Ink) {
    _ = native.draw_encoder_line(ctx.encoder,
        {rule.origin.x + rule.left, rule.origin.y + rule.center},
        {rule.origin.x + rule.right, rule.origin.y + rule.center},
        max(1, rule.thickness), inline_draw_color(ctx, draw_color))
}

// encode_box encodes one outlined or filled Dynview box with independent edges.
encode_box :: proc(
    ctx: Layout_Draw_Context, item: dynviewmodel.Dynview_Layout_Item,
    origin: geometry.Vector2, draw_color: Inline_Draw_Ink, filled: bool) {
    rectangle: geometry.Rectangle = {
        origin.x, origin.y, item.draw_width, item.draw_height}
    if filled {
        _ = native.draw_encoder_rectangle(
            ctx.encoder, rectangle, inline_draw_color(ctx, draw_color))
    }
    stroke := max(1, item.inline_atom_stroke)
    if !filled || item.inline_outline_stroke > 0 {
        top_left: geometry.Vector2 = {rectangle.x, rectangle.y}
        top_right: geometry.Vector2 = {rectangle.x + rectangle.width, rectangle.y}
        bottom_right: geometry.Vector2 = {
            rectangle.x + rectangle.width, rectangle.y + rectangle.height}
        bottom_left: geometry.Vector2 = {rectangle.x, rectangle.y + rectangle.height}
        _ = native.draw_encoder_line(ctx.encoder, top_left, top_right, stroke,
            inline_draw_color(ctx, inline_edge_ink(item.shape_edge_color_1, draw_color)))
        _ = native.draw_encoder_line(ctx.encoder, top_right, bottom_right, stroke,
            inline_draw_color(ctx, inline_edge_ink(item.shape_edge_color_2, draw_color)))
        _ = native.draw_encoder_line(ctx.encoder, bottom_right, bottom_left, stroke,
            inline_draw_color(ctx, inline_edge_ink(item.shape_edge_color_3, draw_color)))
        _ = native.draw_encoder_line(ctx.encoder, bottom_left, top_left, stroke,
            inline_draw_color(ctx, inline_edge_ink(item.shape_edge_color_4, draw_color)))
    }
}

// encode_circle encodes one outlined or filled Dynview circle.
encode_circle :: proc(
    ctx: Layout_Draw_Context, item: dynviewmodel.Dynview_Layout_Item,
    origin: geometry.Vector2, draw_color: Inline_Draw_Ink, filled: bool) {
    center: geometry.Vector2 = {origin.x + item.draw_width * 0.5,
        origin.y + item.draw_height * 0.5}
    radius := max(0.5, min(item.draw_width, item.draw_height) * 0.5)
    if filled {
        _ = native.draw_encoder_circle(
            ctx.encoder, center, radius, inline_draw_color(ctx, draw_color))
    }
    stroke := max(1, item.inline_atom_stroke)
    if !filled || item.inline_outline_stroke > 0 {
        _ = native.draw_encoder_ring(
            ctx.encoder, center, max(0, radius - stroke), radius,
            inline_draw_color(ctx, draw_color))
    }
}

// encode_polygon encodes a filled polygon fan and its independently colored outline.
encode_polygon :: proc(
    ctx: Layout_Draw_Context, points: []geometry.Vector2,
    style: Polygon_Encode_Style) {
    if len(points) < 3 {
        return
    }
    if style.filled {
        for index in 1..<len(points)-1 {
            _ = native.draw_encoder_triangle(
                ctx.encoder, points[0], points[index], points[index+1],
                inline_draw_color(ctx, style.draw_color))
        }
    }
    for index in 0..<len(points) {
        edge_color := style.draw_color
        if index < len(style.edge_colors) {
            edge_color = inline_edge_ink(
                style.edge_colors[index], style.draw_color)
        }
        _ = native.draw_encoder_line(ctx.encoder, points[index],
            points[(index+1)%len(points)],
            style.stroke, inline_draw_color(ctx, edge_color))
    }
}

// encode_inline_polygon encodes one cached triangle or pentagon atom.
encode_inline_polygon :: proc(
    ctx: Layout_Draw_Context, item: dynviewmodel.Dynview_Layout_Item,
    item_x, item_y: f32, draw_color: Inline_Draw_Ink) {
    if item.kind == .Inline_Triangle {
        points: [3]geometry.Vector2 = {{item_x + item.draw_width * 0.5, item_y},
            {item_x, item_y + item.draw_height},
            {item_x + item.draw_width, item_y + item.draw_height}}
        edge_colors: [3]dynviewmodel.Color = {item.shape_edge_color_1,
            item.shape_edge_color_2, item.shape_edge_color_3}
        encode_polygon(ctx, points[:], {edge_colors[:], draw_color,
            item.shape_is_filled, max(1, item.inline_atom_stroke)})
        return
    }
    points: [5]geometry.Vector2 = {{item_x + item.draw_width * 0.5, item_y},
        {item_x + item.draw_width, item_y + item.draw_height * 0.38},
        {item_x + item.draw_width * 0.81, item_y + item.draw_height},
        {item_x + item.draw_width * 0.19, item_y + item.draw_height},
        {item_x, item_y + item.draw_height * 0.38}}
    edge_colors: [5]dynviewmodel.Color = {item.shape_edge_color_1,
        item.shape_edge_color_2, item.shape_edge_color_3,
        item.shape_edge_color_4, item.shape_edge_color_5}
    encode_polygon(ctx, points[:], {edge_colors[:], draw_color,
        item.shape_is_filled, max(1, item.inline_atom_stroke)})
}

// encode_pie_point resolves one clockwise document angle around a pie center.
encode_pie_point :: #force_inline proc(
    center: geometry.Vector2, radius, angle_degrees: f32) -> geometry.Vector2 {
    radians := f64(angle_degrees) * math.PI / 180
    return {center.x + radius * f32(math.cos(radians)),
        center.y - radius * f32(math.sin(radians))}
}

// encode_pie_radial_outline draws the two radial edges for an outlined pie.
encode_pie_radial_outline :: proc(
    ctx: Layout_Draw_Context, item: dynviewmodel.Dynview_Layout_Item,
    center: geometry.Vector2, radius: f32, draw_color: Inline_Draw_Ink) {
    outline_color := Inline_Draw_Ink{item.outline_color, true} if
        item.has_outline_color else draw_color
    stroke := max(1, item.inline_outline_stroke)
    start_point := encode_pie_point(center, radius, item.pie_start_angle_degrees)
    end_point := encode_pie_point(center, radius, item.pie_end_angle_degrees)
    _ = native.draw_encoder_line(
        ctx.encoder, center, start_point, stroke, inline_draw_color(ctx, outline_color))
    _ = native.draw_encoder_line(
        ctx.encoder, center, end_point, stroke, inline_draw_color(ctx, outline_color))
}

// encode_pie_section encodes one filled or outlined arc with radial edges.
encode_pie_section :: proc(
    ctx: Layout_Draw_Context, item: dynviewmodel.Dynview_Layout_Item,
    item_x, item_y: f32, draw_color: Inline_Draw_Ink) {
    sweep := positive_sweep_degrees(
        item.pie_start_angle_degrees, item.pie_end_angle_degrees)
    if sweep <= 0 {
        return
    }
    center: geometry.Vector2 = {item_x + item.pie_center_offset_x,
        item_y + item.pie_center_offset_y}
    visual_radius := max(
        max(item.pie_center_offset_x, item.draw_width-item.pie_center_offset_x),
        max(item.pie_center_offset_y, item.draw_height-item.pie_center_offset_y))
    radius := max(0.5, visual_radius-item.inline_atom_stroke*0.5)
    segments := max(1, int(math.ceil(f64(sweep/8))))
    previous := encode_pie_point(center, radius, item.pie_start_angle_degrees)
    outline_color := Inline_Draw_Ink{item.outline_color, true} if
        item.has_outline_color else draw_color
    stroke := max(1, item.inline_outline_stroke)
    for index in 0..<segments {
        angle := item.pie_start_angle_degrees + sweep*f32(index+1)/f32(segments)
        next := encode_pie_point(center, radius, angle)
        if item.pie_is_filled {
            _ = native.draw_encoder_triangle(
                ctx.encoder, center, previous, next, inline_draw_color(ctx, draw_color))
        }
        if !item.pie_is_filled || item.inline_outline_stroke > 0 {
            _ = native.draw_encoder_line(
                ctx.encoder, previous, next,
                stroke, inline_draw_color(ctx, outline_color))
        }
        previous = next
    }
    if !item.pie_is_filled || item.inline_outline_stroke > 0 {
        encode_pie_radial_outline(ctx, item, center, radius, draw_color)
    }
}

// encode_perpendicular encodes an inset base with one centered vertical stem.
encode_perpendicular :: proc(
    ctx: Layout_Draw_Context, item: dynviewmodel.Dynview_Layout_Item,
    item_x, item_y: f32, base_color: Inline_Draw_Ink) {
    stroke := max(1, item.inline_atom_stroke)
    inset := stroke * 0.5
    left := item_x + inset
    right := item_x + item.draw_width - inset
    top := item_y + inset
    bottom := item_y + item.draw_height - inset
    stem_x := (left + right) * 0.5
    stem_color := inline_edge_ink(item.shape_edge_color_1, base_color)
    _ = native.draw_encoder_line(
        ctx.encoder, {left, bottom}, {right, bottom}, stroke,
        inline_draw_color(ctx, base_color))
    _ = native.draw_encoder_line(
        ctx.encoder, {stem_x, top}, {stem_x, bottom}, stroke,
        inline_draw_color(ctx, stem_color))
}

// encode_inline_shape encodes one cached geometric atom when its kind is supported.
encode_inline_shape :: proc(
    ctx: Layout_Draw_Context, item: dynviewmodel.Dynview_Layout_Item,
    origin: geometry.Vector2, draw_color: Inline_Draw_Ink) -> bool {
    center_y := origin.y + item.draw_height * 0.5
    switch item.kind {
    case .Inline_Line:
        stroke := max(1, item.inline_atom_stroke)
        _ = native.draw_encoder_line(ctx.encoder, {origin.x, center_y},
            {origin.x + item.draw_width, center_y},
            stroke, inline_draw_color(ctx, draw_color))
    case .Inline_Box, .Inline_Filled_Box:
        encode_box(ctx, item, origin, draw_color,
            item.kind == .Inline_Filled_Box)
    case .Inline_Circle, .Inline_Filled_Circle:
        encode_circle(ctx, item, origin, draw_color,
            item.kind == .Inline_Filled_Circle)
    case .Inline_Perpendicular:
        encode_perpendicular(ctx, item, origin.x, origin.y, draw_color)
    case .Inline_Triangle, .Inline_Pentagon:
        encode_inline_polygon(ctx, item, origin.x, origin.y, draw_color)
    case .Inline_Pie_Section:
        encode_pie_section(ctx, item, origin.x, origin.y, draw_color)
    case .Text_Run, .Math_Glyph_Run, .Math_Block, .Script_Attach, .Frac,
         .Stretch_Delimiter, .Matrix, .Style_Override, .Stack, .Large_Op,
         .Accent_Bar, .Radical_Bar:
        return false
    }
    return true
}

// encode_inline_rule encodes one cached mathematical rule when supported.
encode_inline_rule :: proc(
    ctx: Layout_Draw_Context, item: dynviewmodel.Dynview_Layout_Item,
    origin: geometry.Vector2, draw_color: Inline_Draw_Ink) {
    rule: Rule_Encode_Geometry = {
        origin = {origin.x, origin.y + item.ascent},
    }
    switch item.kind {
    case .Frac:
        rule.left, rule.right = item.fraction_rule_left, item.fraction_rule_right
        rule.center, rule.thickness =
            item.fraction_rule_center, item.fraction_rule_thickness
    case .Accent_Bar:
        rule.left, rule.right = item.accent_rule_left, item.accent_rule_right
        rule.center, rule.thickness =
            item.accent_rule_center, item.accent_rule_thickness
    case .Radical_Bar:
        rule.left, rule.right = item.radical_rule_left, item.radical_rule_right
        rule.center, rule.thickness =
            item.radical_rule_center, item.radical_rule_thickness
    case .Text_Run, .Math_Glyph_Run, .Math_Block, .Script_Attach,
         .Stretch_Delimiter, .Matrix, .Style_Override, .Stack, .Large_Op,
         .Inline_Line, .Inline_Box, .Inline_Circle, .Inline_Filled_Box,
         .Inline_Filled_Circle, .Inline_Pie_Section, .Inline_Perpendicular,
         .Inline_Triangle, .Inline_Pentagon:
        return
    }
    encode_rule(ctx, rule, draw_color)
}

// encode_inline_item encodes one font-independent cached Dynview item.
encode_inline_item :: proc(
    encoder: ^native.Draw_Encoder, item: dynviewmodel.Dynview_Layout_Item,
    item_x, item_y: f32, ink_ctx: Layout_Draw_Context = {}) {
    ctx := ink_ctx
    ctx.encoder = encoder
    previous := dynview_ink_source(encoder, {}, false)
    defer native.draw_encoder_set_ink_sink(encoder, previous)
    style_ctx := ctx
    style_ctx.has_authored_ink = false
    style := layout_draw_style(style_ctx, item.style_id)
    draw_color: Inline_Draw_Ink = {style.color, false}
    if ctx.has_authored_ink {
        draw_color = {ctx.authored_ink, true}
    }
    if item.has_brush_color {
        draw_color = {item.brush_color, true}
    }
    origin: geometry.Vector2 = {item_x, item_y}
    if encode_inline_shape(ctx, item, origin, draw_color) {
        return
    }
    encode_inline_rule(ctx, item, origin, draw_color)
}

// draw_encoded_geometry encodes cached Dynview geometry inside the presentation clip.
draw_encoded_geometry :: proc(params: Dynview_Geometry_Draw_Params) {
    state, runtime, encoder := params.state, params.runtime, params.encoder
    panel, scroll_y, text_padding := params.panel, params.scroll_y, params.text_padding
    if state == nil || runtime == nil || !runtime^.compile_cache.layout_is_valid {
        return
    }
    cache := &runtime^.compile_cache
    ink_ctx: Layout_Draw_Context = {
        state = state,
    }
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
            encode_inline_item(encoder, item, item_x, item_y, ink_ctx)
        }
    }
    _ = native.draw_encoder_pop_scissor(encoder)
}

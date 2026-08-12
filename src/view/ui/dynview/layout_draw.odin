package ui_dynview

import "../../../core"
import "../../../dynview"
import view_core "../../core"

import "core:math"

import rl "vendor:raylib"

//   Measured per-cell items plus per-column widths and per-row extents.
Matrix_Draw_Cells :: struct {
    items:        [256]core.Dynview_Layout_Item,
    col_widths:   [16]f32,
    row_ascents:  [16]f32,
    row_descents: [16]f32,
}

//   Matrix grid geometry: column alignments, grid extents, and inter-cell gaps.
Matrix_Draw_Geometry :: struct {
    alignments: [16]dynview.Dynview_Matrix_Column_Alignment,
    rows:       int,
    cols:       int,
    column_gap: f32,
    row_gap:    f32,
}

//   Shared draw environment passed to cached layout item renderers so the
//   state/runtime/panel/font tuple travels as one coherent value.
Layout_Draw_Context :: struct {
    state:     ^core.Euclid_General_State,
    runtime:   ^core.Dynview_System,
    panel:     rl.Rectangle,
    font:      rl.Font,
    font_size: f32,
}

//   Complete draw context for one stretched delimiter glyph invocation.
//   Groups layout metrics, style/font state, and delimiter identity into one argument.
Stretch_Delimiter_Glyph_Params :: struct {
    state:           ^core.Euclid_General_State,
    style:           Dynview_Text_Style,
    fallback_font:   rl.Font,
    wrap_advance:    f32,
    font_size:       f32,
    content_height:  f32,
    content_ascent:  f32,
    content_descent: f32,
    delimiter_kind:  i32,
    draw_x:          f32,
    baseline_y:      f32,
}

//   Pixel-space geometry derived from baseline/ascent/descent for one delimiter glyph.
//   The geometry is normalized so family renderers can share the same frame of reference.
Stretch_Delimiter_Glyph_Geometry :: struct {
    draw_x:     f32,
    baseline_y: f32,
    top_y:      f32,
    bottom_y:   f32,
    center_y:   f32,
    width:      f32,
    height:     f32,
    thickness:  f32,
    right_side: bool,
}

//   Uniform handler shape for line-only delimiter family renderers.
Delimiter_Line_Handler :: proc(
    style: Dynview_Text_Style,
    geom: Stretch_Delimiter_Glyph_Geometry,
    family: dynview.Dynview_Delimiter_Family)

//   Line-renderers indexed by delimiter family; nil means the family needs a
//   curved renderer or the text fallback instead of a line fast path.
DELIMITER_LINE_HANDLERS ::
    [dynview.Dynview_Delimiter_Family]Delimiter_Line_Handler{
    .None = nil,
    .Paren = nil,
    .Bracket = draw_delimiter_bracket,
    .Brace = nil,
    .Vert = draw_delimiter_vert,
    .DoubleVert = draw_delimiter_double_vert,
    .Ceil = draw_delimiter_bracket,
    .Floor = draw_delimiter_bracket,
    .Angle = draw_delimiter_angle,
}

//   Fast vertical cull check for one layout line against panel bounds.
//   Returns true only when the full line is strictly outside the visible span.
layout_line_outside_panel :: #force_inline proc(
    line_top, line_bottom, panel_top, panel_bottom: f32) -> bool {

    return line_bottom < panel_top || line_top > panel_bottom
}

//   Return extra top/bottom culling margin for lines with script or accent items.
line_visual_padding :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    line: core.Dynview_Layout_Line,
    font_size: f32) -> (f32, f32) {

    top_pad: f32 = 0
    bottom_pad: f32 = 0
    item_end := line.item_start + line.item_count
    for item_index in line.item_start..<item_end {
        item := cache^.layout_items[item_index]
        top_pad = max(top_pad, item.visual_padding_top)
        bottom_pad = max(bottom_pad, item.visual_padding_bottom)

        script_font_size := max(1.0, font_size * max(0.2, item.script_scale))
        script_top_pad, script_bottom_pad :=
            dynview.script_visual_padding(script_font_size)
        top_pad = max(top_pad, script_top_pad)
        bottom_pad = max(bottom_pad, script_bottom_pad)
    }

    return top_pad, bottom_pad
}

//   Draw one cached math-block item from its precomputed program slot.
draw_math_block_item :: proc(
    state: ^core.Euclid_General_State,
    runtime: ^core.Dynview_System,
    panel: rl.Rectangle,
    font: rl.Font,
    font_size: f32,
    item: core.Dynview_Layout_Item,
    item_x, item_y: f32) {

    program_id := int(item.math_program_id)
    if runtime == nil || program_id < 0 ||
        program_id >= runtime^.compile_cache.math_program_count {
        return
    }

    program := runtime^.compile_cache.math_programs[program_id]
    if !program.valid {
        return
    }

    baseline_y := item_y + item.ascent
    draw_math_program_at(state, runtime, panel, font, font_size,
        program, item_x, baseline_y)
}

//   Draw one recursive accent wrapper by drawing the child math program first, then the line.
draw_recursive_accent_item :: proc(
    ctx: Layout_Draw_Context,
    style: Dynview_Text_Style,
    item: core.Dynview_Layout_Item,
    draw_x, item_y: f32) {

    child_program, ok := dynview.math_program_from_id(
        &ctx.runtime^.compile_cache, item.math_program_id)
    if !ok {
        return
    }

    baseline_y := item_y + item.ascent
    draw_math_program_at(ctx.state, ctx.runtime, ctx.panel, ctx.font,
        ctx.font_size, child_program^, draw_x, baseline_y)

    accent_style := dynview.style_by_id(item.accent_style_id)
    bar_thickness := max(1.0, item.accent_thickness * ctx.font_size)
    bar_offset := max(0.0, item.accent_offset * ctx.font_size)
    bar_y := baseline_y + child_program^.descent + bar_offset
    if item.accent_mode == 1 {
        bar_y = baseline_y - child_program^.ascent - bar_offset
    }

    rl.DrawLineEx(
        rl.Vector2{draw_x, bar_y},
        rl.Vector2{draw_x + child_program^.draw_width, bar_y},
        bar_thickness,
        accent_style.color)
}

//   Draw one recursive radical wrapper by drawing the child math program first, then index and radical stroke.
draw_recursive_radical_item :: proc(
    ctx: Layout_Draw_Context,
    item: core.Dynview_Layout_Item,
    draw_x, item_y: f32) {

    child_program, ok := dynview.math_program_from_id(
        &ctx.runtime^.compile_cache, item.math_program_id)
    if !ok {
        return
    }

    baseline_y := item_y + item.ascent
    style := dynview.style_by_id(item.style_id)
    script_style := dynview.style_by_id(item.script_style_id)
    script_font := resolve_font_for_style(ctx.state, script_style, ctx.font)
    base_advance :=
        dynview.effective_advance(style, ctx.runtime^.compile_cache.last_wrap_advance)
    lead_width := dynview.radical_lead_width(ctx.font_size, base_advance)
    front_padding, back_padding :=
        dynview.radical_side_paddings(ctx.font_size, base_advance)
    content_x := draw_x + front_padding + lead_width

    draw_math_program_at(ctx.state, ctx.runtime, ctx.panel, ctx.font, ctx.font_size,
        child_program^, content_x, baseline_y)

    index_text := dynview.text_span_from_buffer(
        &ctx.runtime^.command_buffer,
        item.radical_index_text_offset,
        item.radical_index_text_len)
    radical_style := dynview.style_by_id(item.accent_style_id)
    bar_thickness := max(1.0, item.accent_thickness * ctx.font_size)
    bar_offset := max(0.0, item.accent_offset * ctx.font_size)

    bar_y := baseline_y - child_program^.ascent - bar_offset
    bar_start_x := draw_x + front_padding + lead_width * 0.84
    bar_end_x := draw_x + item.draw_width - back_padding
    rl.DrawLineEx(
        rl.Vector2{bar_start_x, bar_y},
        rl.Vector2{bar_end_x, bar_y},
        bar_thickness,
        radical_style.color)

    hook_start_x := draw_x + front_padding - lead_width * 0.20
    hook_start_y := baseline_y - ctx.font_size * 0.3
    hook_flag_x := hook_start_x - 2.5
    root_low_x := draw_x + front_padding + lead_width * 0.26
    root_low_offset :=
        dynview.radical_root_low_offset(ctx.font_size, child_program^.descent)
    root_low_y := baseline_y + root_low_offset
    root_rise_x := draw_x + front_padding + lead_width * 0.88
    root_rise_y := bar_y - ctx.font_size * 0.14
    root_high_x := draw_x + front_padding + lead_width * 1.24
    root_high_y := bar_y - ctx.font_size * 0.06 + bar_thickness * 0.5
    hook_stroke := max(bar_thickness, bar_thickness * 1.25)

    rl.DrawLineEx(rl.Vector2{hook_flag_x, hook_start_y},
        rl.Vector2{hook_start_x, hook_start_y}, hook_stroke, radical_style.color)
    rl.DrawLineEx(rl.Vector2{hook_start_x, hook_start_y},
        rl.Vector2{root_low_x, root_low_y}, hook_stroke, radical_style.color)
    rl.DrawLineEx(rl.Vector2{root_low_x, root_low_y},
        rl.Vector2{root_rise_x, root_rise_y}, hook_stroke, radical_style.color)
    rl.DrawLineEx(rl.Vector2{root_rise_x, root_rise_y},
        rl.Vector2{root_high_x, root_high_y}, hook_stroke, radical_style.color)
    rl.DrawLineEx(rl.Vector2{root_high_x, root_high_y},
        rl.Vector2{bar_start_x, bar_y}, hook_stroke, radical_style.color)

    if len(index_text) > 0 {
        index_scale := max(0.75, item.script_scale)
        index_font_size := max(3.0, ctx.font_size * index_scale)
        index_ascent, _ := dynview.style_ascent_descent(script_style, index_font_size)
        index_cols :=
            max(1, dynview.text_codepoint_count_span(index_text, 0, len(index_text)))
        index_advance := dynview.effective_advance(script_style,
            ctx.runtime^.compile_cache.last_wrap_advance) * index_scale
        index_width := f32(index_cols) * index_advance
        index_right_limit := draw_x + front_padding + lead_width * 0.36
        index_x := index_right_limit - index_width
        index_y := baseline_y - child_program^.ascent * 0.62 - index_ascent * 0.50 -
            ctx.font_size * 0.25
        view_core.ui_text_f32(index_text, index_x, index_y, script_style.color,
            script_font, index_font_size)
    }
}

//   Resolve a style-specific font handle, falling back to provided font when state is nil.
resolve_font_for_style :: #force_inline proc(
    state: ^core.Euclid_General_State,
    style: Dynview_Text_Style,
    fallback_font: rl.Font) -> rl.Font {

    resolved := fallback_font
    if state == nil {
        return resolved
    }

    flags := style.font_flags
    if flags == .None {
        flags = view_core.font_flags_from_bold_italic(style.bold, style.italic)
    }

    resolved = view_core.font_runtime_resolve(
        state,
        flags,
        view_core.JULIA_MONO_FONT_LOAD_SIZE)
    return resolved
}

//   Resolve final draw-x for one text item, honoring centered first-column alignment.
text_item_draw_x :: #force_inline proc(
    panel: rl.Rectangle,
    style: Dynview_Text_Style,
    item: core.Dynview_Layout_Item,
    item_x: f32) -> f32 {

    if style.alignment == .Center && item.col_start == 0 {
        return panel.x + (panel.width - item.draw_width) * 0.5
    }
    return item_x
}

//   Script glyph rendering inputs: the base and script styles/fonts plus the
//   text and draw position, grouped so script composition passes one coherent
//   value.
Script_Draw_Params :: struct {
    runtime:      ^core.Dynview_System,
    item:         core.Dynview_Layout_Item,
    style:        Dynview_Text_Style,
    script_style: Dynview_Text_Style,
    script_font:  rl.Font,
    font_size:    f32,
    baseline_y:   f32,
    draw_x:       f32,
    base_text:    string,
    script_color: rl.Color,
}

//   Draw script children for ScriptAttach/AccentBar items and return composed extents.
draw_script_children :: #force_inline proc(
    params: Script_Draw_Params) -> (f32, f32) {

    runtime := params.runtime
    item := params.item
    style := params.style
    script_style := params.script_style
    script_font := params.script_font
    font_size := params.font_size
    baseline_y := params.baseline_y
    draw_x := params.draw_x
    base_text := params.base_text
    script_color := params.script_color

    script_scale := max(0.2, item.script_scale)
    script_offsets := dynview.script_draw_offsets(
        font_size,
        script_scale,
        item.script_sup_raise,
        item.script_sub_drop)
    base_ascent, base_descent := dynview.style_ascent_descent(style, font_size)
    script_ascent, script_descent :=
        dynview.style_ascent_descent(script_style, script_offsets.script_font_size)
    script_top_pad, script_bottom_pad :=
        dynview.script_visual_padding(script_offsets.script_font_size)

    sup_text := dynview.text_span_from_buffer(
        &runtime^.command_buffer,
        item.script_sup_text_offset,
        item.script_sup_text_len)
    sub_text := dynview.text_span_from_buffer(
        &runtime^.command_buffer,
        item.script_sub_text_offset,
        item.script_sub_text_len)

    base_cols := max(1, dynview.text_codepoint_count_span(base_text, 0, len(base_text)))
    base_advance := dynview.effective_advance(
        style, runtime^.compile_cache.last_wrap_advance)
    script_x := draw_x + f32(base_cols) * base_advance +
        max(1.0, item.script_gap * font_size)

    content_ascent := base_ascent
    content_descent := base_descent

    if len(sup_text) > 0 {
        sup_top := baseline_y - script_offsets.sup_raise_px - script_ascent
        view_core.ui_text_f32(sup_text, script_x, sup_top,
            script_color, script_font, script_offsets.script_font_size)
        content_ascent = max(content_ascent,
            script_ascent + script_offsets.sup_raise_px + script_top_pad)
    }

    if len(sub_text) > 0 {
        // Keep padding for layout/culling only; avoid shifting glyphs upward.
        sub_top := baseline_y + script_offsets.sub_drop_px - script_ascent
        view_core.ui_text_f32(sub_text, script_x, sub_top, script_color,
            script_font, script_offsets.script_font_size)
        content_descent = max(content_descent,
            script_descent + script_offsets.sub_drop_px + script_bottom_pad)
    }

    return content_ascent, content_descent
}

//   Draw one ScriptAttach item including raised/lowered script text.
draw_script_attach_item :: #force_inline proc(
    ctx: Layout_Draw_Context,
    style: Dynview_Text_Style,
    item: core.Dynview_Layout_Item,
    resolved_font: rl.Font,
    text: string,
    draw_x, item_y: f32) {

    font_size := ctx.font_size
    script_style := dynview.style_by_id(item.script_style_id)
    script_font := resolve_font_for_style(ctx.state, script_style, resolved_font)

    baseline_y := item_y + item.ascent
    base_ascent, _ := dynview.style_ascent_descent(style, font_size)
    base_top := baseline_y - base_ascent
    view_core.ui_text_f32(text, draw_x, base_top, style.color, resolved_font, font_size)

    _, _ = draw_script_children(Script_Draw_Params{
        runtime = ctx.runtime,
        item = item,
        style = style,
        script_style = script_style,
        script_font = script_font,
        font_size = font_size,
        baseline_y = baseline_y,
        draw_x = draw_x,
        base_text = text,
        script_color = style.color,
    })
}

//   Draw one recursive ScriptAttach wrapper by drawing a child program and script text.
draw_recursive_script_attach_item :: #force_inline proc(
    ctx: Layout_Draw_Context,
    item: core.Dynview_Layout_Item,
    draw_x, item_y: f32) {

    child_program, ok :=
        dynview.math_program_from_id(&ctx.runtime^.compile_cache, item.math_program_id)
    if !ok {
        return
    }

    baseline_y := item_y + item.ascent
    draw_math_program_at(ctx.state, ctx.runtime, ctx.panel, ctx.font, ctx.font_size,
        child_program^, draw_x, baseline_y)

    script_style := dynview.style_by_id(item.script_style_id)
    script_font := resolve_font_for_style(ctx.state, script_style, ctx.font)
    script_scale := max(0.2, item.script_scale)
    script_offsets := dynview.script_draw_offsets(
        ctx.font_size,
        script_scale,
        item.script_sup_raise,
        item.script_sub_drop)
    script_ascent, _ :=
        dynview.style_ascent_descent(script_style, script_offsets.script_font_size)

    sup_text := dynview.text_span_from_buffer(
        &ctx.runtime^.command_buffer,
        item.script_sup_text_offset,
        item.script_sup_text_len)
    sub_text := dynview.text_span_from_buffer(
        &ctx.runtime^.command_buffer,
        item.script_sub_text_offset,
        item.script_sub_text_len)

    script_x := draw_x + child_program^.draw_width +
        max(1.0, item.script_gap * ctx.font_size)
    if len(sup_text) > 0 {
        sup_top := baseline_y - script_offsets.sup_raise_px - script_ascent
        view_core.ui_text_f32(sup_text, script_x, sup_top,
            script_style.color, script_font, script_offsets.script_font_size)
    }

    if len(sub_text) > 0 {
        sub_top := baseline_y + script_offsets.sub_drop_px - script_ascent
        view_core.ui_text_f32(sub_text, script_x, sub_top, script_style.color,
            script_font, script_offsets.script_font_size)
    }
}

//   Draw one recursive fraction with centered numerator/denominator and center divider.
draw_recursive_fraction_item :: #force_inline proc(
    ctx: Layout_Draw_Context,
    style: Dynview_Text_Style,
    item: core.Dynview_Layout_Item,
    draw_x, item_y: f32) {

    numerator_program, ok :=
        dynview.math_program_from_id(&ctx.runtime^.compile_cache, item.math_program_id)
    if !ok {
        return
    }
    denominator_program, ok_den :=
        dynview.math_program_from_id(&ctx.runtime^.compile_cache,
            item.secondary_math_program_id)
    if !ok_den {
        return
    }

    baseline_y := item_y + item.ascent
    divider_thickness := max(1.0, item.accent_thickness * ctx.font_size)
    divider_half := divider_thickness * 0.5
    divider_gap := dynview.fraction_vertical_gap(ctx.font_size)

    numerator_x := draw_x + (item.draw_width - numerator_program^.draw_width) * 0.5
    denominator_x := draw_x + (item.draw_width - denominator_program^.draw_width) * 0.5
    numerator_baseline_y :=
        baseline_y - divider_half - divider_gap - numerator_program^.descent
    denominator_baseline_y :=
        baseline_y + divider_half + divider_gap + denominator_program^.ascent
    draw_math_program_at(ctx.state, ctx.runtime, ctx.panel, ctx.font, ctx.font_size,
        numerator_program^, numerator_x, numerator_baseline_y)
    draw_math_program_at(ctx.state, ctx.runtime, ctx.panel, ctx.font, ctx.font_size,
        denominator_program^, denominator_x, denominator_baseline_y)

    base_advance :=
        dynview.effective_advance(style, ctx.runtime^.compile_cache.last_wrap_advance)
    side_padding := dynview.fraction_side_padding(ctx.font_size, base_advance)
    divider_start_x := draw_x + side_padding
    divider_end_x := draw_x + item.draw_width - side_padding
    divider_color := dynview.style_by_id(item.accent_style_id).color
    if item.accent_style_id <= 0 {
        divider_color = style.color
    }
    rl.DrawLineEx(
        rl.Vector2{divider_start_x, baseline_y},
        rl.Vector2{divider_end_x, baseline_y},
        divider_thickness,
        divider_color)
}

//   Draw one normalized cubic Bezier segment as line samples in pixel space.
//   Control points are in [0,1] glyph coordinates; right delimiters mirror x
//   so family geometry is authored once for the left-hand form.
draw_normalized_cubic_segment :: #force_inline proc(
    geom: Stretch_Delimiter_Glyph_Geometry,
    thickness: f32,
    p0, p1, p2, p3: rl.Vector2,
    color: rl.Color,
    segment_count: int) {

    if segment_count <= 0 {
        return
    }

    x0_norm := p0.x
    if geom.right_side {
        x0_norm = 1.0 - x0_norm
    }
    prev := rl.Vector2{geom.draw_x + geom.width * x0_norm,
        geom.top_y + geom.height * p0.y}

    for i in 1..=segment_count {
        t := f32(i) / f32(segment_count)
        u := 1.0 - t
        x_norm := u * u * u * p0.x + 3.0 * u * u * t * p1.x +
            3.0 * u * t * t * p2.x + t * t * t * p3.x
        y_norm := u * u * u * p0.y + 3.0 * u * u * t * p1.y +
            3.0 * u * t * t * p2.y + t * t * t * p3.y
        if geom.right_side {
            x_norm = 1.0 - x_norm
        }

        current := rl.Vector2{geom.draw_x + geom.width * x_norm,
            geom.top_y + geom.height * y_norm}
        rl.DrawLineEx(prev, current, thickness, color)
        prev = current
    }
}

//   Build the common geometry frame consumed by every delimiter family renderer.
//   Converts baseline/ascent/descent metrics into top/bottom extents, derives a
//   stable stroke thickness, and records side orientation for mirroring logic.
build_stretch_delimiter_geometry :: #force_inline proc(
    params: Stretch_Delimiter_Glyph_Params,
    width: f32) -> Stretch_Delimiter_Glyph_Geometry {

    top_y := params.baseline_y - params.content_ascent
    bottom_y := params.baseline_y + params.content_descent
    return Stretch_Delimiter_Glyph_Geometry{
        draw_x = params.draw_x,
        baseline_y = params.baseline_y,
        top_y = top_y,
        bottom_y = bottom_y,
        center_y = (top_y + bottom_y) * 0.5,
        width = width,
        height = max(1.0, bottom_y - top_y),
        thickness = max(1.0, params.font_size * 0.09),
        right_side = dynview.delimiter_is_right(params.delimiter_kind),
    }
}

//   Render a single vertical bar centered in the glyph frame.
draw_delimiter_vert :: #force_inline proc(
    style: Dynview_Text_Style,
    geom: Stretch_Delimiter_Glyph_Geometry,
    family: dynview.Dynview_Delimiter_Family) {

    _ = family
    x := geom.draw_x + geom.width * 0.5
    rl.DrawLineEx(rl.Vector2{x, geom.top_y},
        rl.Vector2{x, geom.bottom_y}, geom.thickness, style.color)
}

//   Render a double vertical bar as two lanes centered in the glyph frame.
draw_delimiter_double_vert :: #force_inline proc(
    style: Dynview_Text_Style,
    geom: Stretch_Delimiter_Glyph_Geometry,
    family: dynview.Dynview_Delimiter_Family) {

    _ = family
    lane_gap := max(1.0, geom.width * 0.26)
    x1 := geom.draw_x + geom.width * 0.5 - lane_gap
    x2 := geom.draw_x + geom.width * 0.5 + lane_gap
    rl.DrawLineEx(rl.Vector2{x1, geom.top_y},
        rl.Vector2{x1, geom.bottom_y}, geom.thickness, style.color)
    rl.DrawLineEx(rl.Vector2{x2, geom.top_y},
        rl.Vector2{x2, geom.bottom_y}, geom.thickness, style.color)
}

//   Render a bracket/ceil/floor as a vertical stem plus optional top/bottom hooks.
//   Ceil omits the bottom hook; Floor omits the top hook.
draw_delimiter_bracket :: #force_inline proc(
    style: Dynview_Text_Style,
    geom: Stretch_Delimiter_Glyph_Geometry,
    family: dynview.Dynview_Delimiter_Family) {

    stem_x := geom.draw_x + geom.width * 0.28
    hook_x := geom.draw_x + geom.width * 0.88
    if geom.right_side {
        stem_x = geom.draw_x + geom.width * 0.72
        hook_x = geom.draw_x + geom.width * 0.12
    }
    rl.DrawLineEx(rl.Vector2{stem_x, geom.top_y},
        rl.Vector2{stem_x, geom.bottom_y}, geom.thickness, style.color)
    if family != .Floor {
        rl.DrawLineEx(rl.Vector2{stem_x, geom.top_y},
            rl.Vector2{hook_x, geom.top_y}, geom.thickness, style.color)
    }
    if family != .Ceil {
        rl.DrawLineEx(rl.Vector2{stem_x, geom.bottom_y},
            rl.Vector2{hook_x, geom.bottom_y}, geom.thickness, style.color)
    }
}

//   Render an angle bracket as two rails meeting at an apex on the glyph midline.
draw_delimiter_angle :: #force_inline proc(
    style: Dynview_Text_Style,
    geom: Stretch_Delimiter_Glyph_Geometry,
    family: dynview.Dynview_Delimiter_Family) {

    _ = family
    apex_x := geom.draw_x + geom.width * 0.14
    rail_x := geom.draw_x + geom.width * 0.86
    if geom.right_side {
        apex_x = geom.draw_x + geom.width * 0.86
        rail_x = geom.draw_x + geom.width * 0.14
    }
    rl.DrawLineEx(rl.Vector2{rail_x, geom.top_y},
        rl.Vector2{apex_x, geom.center_y}, geom.thickness, style.color)
    rl.DrawLineEx(rl.Vector2{apex_x, geom.center_y},
        rl.Vector2{rail_x, geom.bottom_y}, geom.thickness, style.color)
}

//   Render line-only delimiter families (no sampled curves or cubic segments).
//   Returns true when this proc handled the family so callers can short-circuit
//   curved renderers and fallback glyph paths.
draw_stretch_delimiter_line_family :: #force_inline proc(
    style: Dynview_Text_Style,
    family: dynview.Dynview_Delimiter_Family,
    geom: Stretch_Delimiter_Glyph_Geometry) -> bool {

    handlers := DELIMITER_LINE_HANDLERS
    handler := handlers[family]
    if handler == nil {
        return false
    }

    handler(style, geom, family)
    return true
}

//   Render stretched parentheses from a sinusoidal side profile.
//   The right side mirrors the same profile so both sides remain symmetric and
//   visually consistent across changing content heights.
draw_stretch_delimiter_paren :: #force_inline proc(
    style: Dynview_Text_Style,
    geom: Stretch_Delimiter_Glyph_Geometry) {

    segment_count := 12
    for i in 0..<segment_count {
        t0 := f32(i) / f32(segment_count)
        t1 := f32(i + 1) / f32(segment_count)
        y0 := geom.top_y + geom.height * t0
        y1 := geom.top_y + geom.height * t1
        curve0 := math.sin(t0 * math.PI)
        curve1 := math.sin(t1 * math.PI)

        x0 := geom.draw_x + geom.width * (0.78 - 0.46 * curve0)
        x1 := geom.draw_x + geom.width * (0.78 - 0.46 * curve1)
        if geom.right_side {
            x0 = geom.draw_x + geom.width * (0.22 + 0.46 * curve0)
            x1 = geom.draw_x + geom.width * (0.22 + 0.46 * curve1)
        }

        rl.DrawLineEx(rl.Vector2{x0, y0}, rl.Vector2{x1, y1}, geom.thickness, style.color)
    }
}

//   Render stretched braces from four cubic turns plus two optional stem runs.
//   Corner radius is kept stable while extra height stretches only the stems,
//   which prevents braces from becoming pointy or overly flat at large sizes.
draw_stretch_delimiter_brace :: #force_inline proc(
    style: Dynview_Text_Style,
    geom: Stretch_Delimiter_Glyph_Geometry,
    font_size: f32) {

    //   Left brace layout (mirrored automatically for right): tips point right
    //   toward the content, the vertical stem sits just left of center, and the
    //   middle cusp juts left away from the content. Four quarter-turn cubic
    //   curves join two straight stem runs; corner radius stays fixed while the
    //   stems absorb any extra height, matching how TeX stretches braces.
    segment_count := 16
    brace_thickness := max(1.0, geom.thickness * 0.85)

    half_height := geom.height * 0.5
    radius_px := min(max(2.0, font_size * 0.24), half_height * 0.5)
    stem_len := max(0.0, half_height - 2.0 * radius_px)

    r_norm := radius_px / geom.height
    tip_x := f32(0.88)
    stem_x := f32(0.45)
    cusp_x := f32(0.06)
    bend := f32(0.55)

    // Top hook: horizontal at the tip, vertical where it joins the stem.
    draw_normalized_cubic_segment(
        geom,
        brace_thickness,
        rl.Vector2{tip_x, 0.0},
        rl.Vector2{tip_x - bend * (tip_x - stem_x), 0.0},
        rl.Vector2{stem_x, r_norm * (1.0 - bend)},
        rl.Vector2{stem_x, r_norm},
        style.color,
        segment_count)

    if stem_len > 0.5 {
        x_stem := geom.draw_x + geom.width * stem_x
        if geom.right_side {
            x_stem = geom.draw_x + geom.width * (1.0 - stem_x)
        }
        rl.DrawLineEx(
            rl.Vector2{x_stem, geom.top_y + radius_px},
            rl.Vector2{x_stem, geom.center_y - radius_px},
            brace_thickness,
            style.color)
    }

    // Upper cusp curve: vertical at the stem, horizontal into the cusp point.
    draw_normalized_cubic_segment(
        geom,
        brace_thickness,
        rl.Vector2{stem_x, 0.5 - r_norm},
        rl.Vector2{stem_x, 0.5 - r_norm * (1.0 - bend)},
        rl.Vector2{cusp_x + bend * (stem_x - cusp_x), 0.5},
        rl.Vector2{cusp_x, 0.5},
        style.color,
        segment_count)

    // Lower cusp curve mirrors the upper one below the midline.
    draw_normalized_cubic_segment(
        geom,
        brace_thickness,
        rl.Vector2{cusp_x, 0.5},
        rl.Vector2{cusp_x + bend * (stem_x - cusp_x), 0.5},
        rl.Vector2{stem_x, 0.5 + r_norm * (1.0 - bend)},
        rl.Vector2{stem_x, 0.5 + r_norm},
        style.color,
        segment_count)

    if stem_len > 0.5 {
        x_stem := geom.draw_x + geom.width * stem_x
        if geom.right_side {
            x_stem = geom.draw_x + geom.width * (1.0 - stem_x)
        }
        rl.DrawLineEx(
            rl.Vector2{x_stem, geom.center_y + radius_px},
            rl.Vector2{x_stem, geom.bottom_y - radius_px},
            brace_thickness,
            style.color)
    }

    // Bottom hook mirrors the top hook.
    draw_normalized_cubic_segment(
        geom,
        brace_thickness,
        rl.Vector2{stem_x, 1.0 - r_norm},
        rl.Vector2{stem_x, 1.0 - r_norm * (1.0 - bend)},
        rl.Vector2{tip_x - bend * (tip_x - stem_x), 1.0},
        rl.Vector2{tip_x, 1.0},
        style.color,
        segment_count)
}

//   Draw a font glyph fallback when no procedural family renderer is used.
//   The fallback scales with content height while preserving baseline alignment
//   so mixed text/math lines remain vertically coherent.
draw_stretch_delimiter_text_fallback :: #force_inline proc(
    params: Stretch_Delimiter_Glyph_Params,
    width: f32) {

    delimiter := dynview.delimiter_text(params.delimiter_kind)
    if len(delimiter) == 0 {
        return
    }

    stretch_scale := max(1.0, params.content_height / max(1.0, params.font_size))
    delimiter_font_size := max(1.0, params.font_size * stretch_scale)
    delim_ascent, _ := dynview.style_ascent_descent(params.style, delimiter_font_size)
    resolved_font :=
        resolve_font_for_style(params.state, params.style, params.fallback_font)
    view_core.ui_text_f32(delimiter, params.draw_x, params.baseline_y - delim_ascent,
        params.style.color, resolved_font, delimiter_font_size)
    _ = width
}

//   Draw one stretched delimiter and return its advance width.
//   Dispatch order is deliberate: line-family fast path, curved family renderer,
//   then baseline-aligned text fallback when no procedural path applies.
draw_stretch_delimiter_glyph :: #force_inline proc(
    params: Stretch_Delimiter_Glyph_Params) -> f32 {

    if params.delimiter_kind == dynview.DELIMITER_KIND_NONE {
        return 0
    }

    family := dynview.delimiter_family(params.delimiter_kind)
    width := dynview.stretch_delimiter_width(
        params.style,
        params.wrap_advance,
        params.font_size,
        params.content_height,
        params.delimiter_kind)
    if family == .None || width <= 0 {
        return 0
    }

    geom := build_stretch_delimiter_geometry(params, width)
    if draw_stretch_delimiter_line_family(params.style, family, geom) {
        return width
    }

    switch family {
    case .Paren:
        draw_stretch_delimiter_paren(params.style, geom)
        return width
    case .Brace:
        draw_stretch_delimiter_brace(params.style, geom, params.font_size)
        return width
    case .Vert, .DoubleVert, .Bracket, .Ceil, .Floor, .Angle, .None:
    }

    draw_stretch_delimiter_text_fallback(params, width)
    return width
}

//   Draw one recursive stretch-delimiter wrapper around optional child content.
//   Left delimiter, child program, and right delimiter are laid out in-order
//   using runtime stretch metrics so both delimiters share the same baseline.
draw_recursive_stretch_delimiter_item :: #force_inline proc(
    ctx: Layout_Draw_Context,
    style: Dynview_Text_Style,
    item: core.Dynview_Layout_Item,
    draw_x, item_y: f32) {

    baseline_y := item_y + item.ascent
    base_advance :=
        dynview.effective_advance(style, ctx.runtime^.compile_cache.last_wrap_advance)
    side_padding := dynview.stretch_delimiter_side_padding(ctx.font_size, base_advance)
    content_height := item.ascent + item.descent

    left_draw_x := draw_x + side_padding
    left_width := draw_stretch_delimiter_glyph(Stretch_Delimiter_Glyph_Params{
        state = ctx.state,
        style = style,
        fallback_font = ctx.font,
        wrap_advance = ctx.runtime^.compile_cache.last_wrap_advance,
        font_size = ctx.font_size,
        content_height = content_height,
        content_ascent = item.ascent,
        content_descent = item.descent,
        delimiter_kind = item.accent_mode,
        draw_x = left_draw_x,
        baseline_y = baseline_y,
    })

    content_x := left_draw_x + left_width
    content_width: f32 = 0
    if item.math_program_id > 0 {
        child_program, ok := dynview.math_program_from_id(
            &ctx.runtime^.compile_cache, item.math_program_id)
        if ok {
            content_width = child_program^.draw_width
            draw_math_program_at(ctx.state, ctx.runtime, ctx.panel, ctx.font,
                ctx.font_size, child_program^, content_x, baseline_y)
        }
    }

    right_draw_x := content_x + content_width
    _ = draw_stretch_delimiter_glyph(Stretch_Delimiter_Glyph_Params{
        state = ctx.state,
        style = style,
        fallback_font = ctx.font,
        wrap_advance = ctx.runtime^.compile_cache.last_wrap_advance,
        font_size = ctx.font_size,
        content_height = content_height,
        content_ascent = item.ascent,
        content_descent = item.descent,
        delimiter_kind = item.radical_mode,
        draw_x = right_draw_x,
        baseline_y = baseline_y,
    })
}

//   Draw one recursive matrix wrapper by centering cells per column and baselining per row.
draw_recursive_matrix_item :: #force_inline proc(
    ctx: Layout_Draw_Context,
    style: Dynview_Text_Style,
    item: core.Dynview_Layout_Item,
    draw_x, item_y: f32) {

    rows := int(item.accent_mode)
    cols := int(item.radical_mode)
    if rows <= 0 || cols <= 0 || rows > 16 || cols > 16 {
        return
    }

    cell_program, ok :=
        dynview.math_program_from_id(&ctx.runtime^.compile_cache, item.math_program_id)
    if !ok || cell_program^.command_count < rows * cols {
        return
    }

    cells := Matrix_Draw_Cells{}
    if !measure_matrix_draw_cells(ctx.runtime, cell_program, rows, cols,
        ctx.font_size, &cells) {
        return
    }

    alignments, _ := dynview.decode_matrix_column_alignments(
        &ctx.runtime^.command_buffer,
        core.Dynview_Command{
            script_sub_text_offset = item.script_sub_text_offset,
            script_sub_text_len = item.script_sub_text_len,
        },
        cols)

    base_advance :=
        dynview.effective_advance(style, ctx.runtime^.compile_cache.last_wrap_advance)
    geometry := Matrix_Draw_Geometry{
        alignments = alignments,
        rows = rows,
        cols = cols,
        column_gap = dynview.matrix_column_gap(ctx.font_size, base_advance),
        row_gap = dynview.matrix_row_gap(ctx.font_size),
    }

    draw_matrix_cells(ctx, cell_program, &cells, geometry, draw_x, item_y)
}

//   Draw every measured matrix cell at its aligned position.
draw_matrix_cells :: proc(
    ctx: Layout_Draw_Context,
    cell_program: ^core.Dynview_Math_Program,
    cells: ^Matrix_Draw_Cells,
    geometry: Matrix_Draw_Geometry,
    draw_x, item_y: f32) {

    row_top := item_y
    for row in 0..<geometry.rows {
        row_baseline := row_top + cells.row_ascents[row]
        col_x := draw_x
        for col in 0..<geometry.cols {
            cell_index := row * geometry.cols + col
            cell_item := cells.items[cell_index]
            cell_x := dynview.matrix_aligned_cell_x(
                col_x,
                cells.col_widths[col],
                cell_item.draw_width,
                geometry.alignments[col])
            command_start := cell_program^.command_start + cell_index
            cell_single_program := core.Dynview_Math_Program{
                valid = true,
                command_start = command_start,
                command_count = 1,
                draw_width = cell_item.draw_width,
                ascent = cell_item.ascent,
                descent = cell_item.descent,
            }
            draw_math_program_at(
                ctx.state,
                ctx.runtime,
                ctx.panel,
                ctx.font,
                ctx.font_size,
                cell_single_program,
                cell_x,
                row_baseline)

            col_x += cells.col_widths[col]
            if col + 1 < geometry.cols {
                col_x += geometry.column_gap
            }
        }

        row_top += cells.row_ascents[row] + cells.row_descents[row]
        if row + 1 < geometry.rows {
            row_top += geometry.row_gap
        }
    }
}

//   Measure every matrix cell, accumulating items, column widths, row extents.
measure_matrix_draw_cells :: proc(
    runtime: ^core.Dynview_System,
    cell_program: ^core.Dynview_Math_Program,
    rows, cols: int,
    font_size: f32,
    cells: ^Matrix_Draw_Cells) -> bool {

    for row in 0..<rows {
        for col in 0..<cols {
            cell_index := row * cols + col
            cmd_index := cell_program^.command_start + cell_index
            cell_cmd := runtime^.compile_cache.math_commands[cmd_index]
            cell_item, cell_ok := dynview.math_program_item(
                &runtime^.compile_cache,
                &runtime^.command_buffer,
                cell_cmd,
                font_size)
            if !cell_ok {
                return false
            }

            cells.items[cell_index] = cell_item
            cells.col_widths[col] = max(cells.col_widths[col], cell_item.draw_width)
            cells.row_ascents[row] = max(cells.row_ascents[row], cell_item.ascent)
            cells.row_descents[row] = max(cells.row_descents[row], cell_item.descent)
        }
    }
    return true
}

//   Draw one recursive structured math item variant routed by layout item kind.
draw_recursive_structured_item :: #force_inline proc(
    ctx: Layout_Draw_Context,
    style: Dynview_Text_Style,
    item: core.Dynview_Layout_Item,
    resolved_font: rl.Font,
    text: string,
    draw_x, item_y: f32) {

    switch item.kind {
    case .ScriptAttachRecursive:
        draw_recursive_script_attach_item(ctx, item, draw_x, item_y)
    case .FracRecursive:
        draw_recursive_fraction_item(ctx, style, item, draw_x, item_y)
    case .StretchDelimiterRecursive:
        draw_recursive_stretch_delimiter_item(ctx, style, item, draw_x, item_y)
    case .MatrixRecursive:
        draw_recursive_matrix_item(ctx, style, item, draw_x, item_y)
    case .LargeOpRecursive:
        draw_large_op_recursive_item(ctx, style, item, resolved_font, text,
            draw_x, item_y)
    case .AccentBarRecursive:
        draw_recursive_accent_item(ctx, style, item, draw_x, item_y)
    case .RadicalBarRecursive:
        draw_recursive_radical_item(ctx, item, draw_x, item_y)
    case .TextRun, .MathGlyphRun, .MathBlock,
        .InlineLine, .InlineBox, .InlineCircle, .InlineFilledBox, .InlineFilledCircle,
        .InlinePieSection, .InlinePerpendicular, .InlineTriangle, .InlinePentagon:
    }
}

//   Draw one display-style large operator with stacked limits above and below.
draw_large_op_recursive_item :: #force_inline proc(
    ctx: Layout_Draw_Context,
    style: Dynview_Text_Style,
    item: core.Dynview_Layout_Item,
    resolved_font: rl.Font,
    text: string,
    draw_x, item_y: f32) {

    glyph_scale := dynview.large_op_glyph_scale(item.large_op_kind)
    glyph_font_size := max(1.0, ctx.font_size * glyph_scale)
    glyph_ascent, glyph_descent := dynview.style_ascent_descent(style, glyph_font_size)
    glyph_cols := max(1, dynview.text_codepoint_count_span(text, 0, len(text)))
    glyph_advance := dynview.effective_advance(style,
        ctx.runtime^.compile_cache.last_wrap_advance) * glyph_scale
    glyph_width := f32(glyph_cols) * glyph_advance

    script_style := dynview.style_by_id(item.script_style_id)
    script_font := resolve_font_for_style(ctx.state, script_style, resolved_font)
    limit_scale := dynview.large_op_limit_scale(max(0.2, item.script_scale))
    limit_font_size := max(1.0, ctx.font_size * limit_scale)
    limit_ascent, limit_descent :=
    dynview.style_ascent_descent(script_style, limit_font_size)
    limit_advance := dynview.effective_advance(script_style,
        ctx.runtime^.compile_cache.last_wrap_advance) * limit_scale

    sup_text := dynview.text_span_from_buffer(
        &ctx.runtime^.command_buffer,
        item.script_sup_text_offset,
        item.script_sup_text_len)
    sub_text := dynview.text_span_from_buffer(
        &ctx.runtime^.command_buffer,
        item.script_sub_text_offset,
        item.script_sub_text_len)
    sup_cols := dynview.text_codepoint_count_span(sup_text, 0, len(sup_text))
    sub_cols := dynview.text_codepoint_count_span(sub_text, 0, len(sub_text))

    upper_height: f32 = 0
    if sup_cols > 0 {
        upper_height = limit_ascent + limit_descent
    }
    lower_height: f32 = 0
    if sub_cols > 0 {
        lower_height = limit_ascent + limit_descent
    }

    limit_gap := dynview.large_op_limit_gap_for_kind(
        item.large_op_kind, ctx.font_size, item.script_gap)
    glyph_top := item_y
    if sup_cols > 0 {
        glyph_top += upper_height + limit_gap
    }
    glyph_x := draw_x + (item.draw_width - glyph_width) * 0.5
    view_core.ui_text_f32(text, glyph_x, glyph_top, style.color,
        resolved_font, glyph_font_size)

    if sup_cols > 0 {
        sup_width := f32(sup_cols) * limit_advance
        sup_x := draw_x + (item.draw_width - sup_width) * 0.5
        sup_top := glyph_top - limit_gap - upper_height
        view_core.ui_text_f32(sup_text, sup_x, sup_top, script_style.color,
            script_font, limit_font_size)
    }

    if sub_cols > 0 {
        sub_width := f32(sub_cols) * limit_advance
        sub_x := draw_x + (item.draw_width - sub_width) * 0.5
        sub_top := glyph_top + glyph_ascent + glyph_descent + limit_gap
        view_core.ui_text_f32(sub_text, sub_x, sub_top, script_style.color,
            script_font, limit_font_size)
    }
}

//   Draw one AccentBar item including optional script children and accent stroke.
draw_accent_bar_item :: #force_inline proc(
    ctx: Layout_Draw_Context,
    style: Dynview_Text_Style,
    item: core.Dynview_Layout_Item,
    resolved_font: rl.Font,
    text: string,
    draw_x, item_y: f32) {

    font_size := ctx.font_size
    script_style := dynview.style_by_id(item.script_style_id)
    script_font := resolve_font_for_style(ctx.state, script_style, resolved_font)

    baseline_y := item_y + item.ascent
    base_ascent, _ := dynview.style_ascent_descent(style, font_size)
    base_top := baseline_y - base_ascent
    view_core.ui_text_f32(text, draw_x, base_top, style.color, resolved_font, font_size)

    content_ascent, content_descent := draw_script_children(Script_Draw_Params{
        runtime = ctx.runtime,
        item = item,
        style = style,
        script_style = script_style,
        script_font = script_font,
        font_size = font_size,
        baseline_y = baseline_y,
        draw_x = draw_x,
        base_text = text,
        script_color = script_style.color,
    })

    accent_style := dynview.style_by_id(item.accent_style_id)
    bar_thickness := max(1.0, item.accent_thickness * font_size)
    has_scripts := item.script_sup_text_len > 0 || item.script_sub_text_len > 0
    bar_offset := max(0.0, item.accent_offset * font_size) +
        dynview.accent_script_clearance(font_size, item.script_scale, has_scripts)

    bar_y := baseline_y + content_descent + bar_offset
    if item.accent_mode == 1 {
        bar_y = baseline_y - content_ascent - bar_offset
    }

    rl.DrawLineEx(
        rl.Vector2{draw_x, bar_y},
        rl.Vector2{draw_x + item.draw_width, bar_y},
        bar_thickness,
        accent_style.color)
}

//   Draw one RadicalBar item including optional script children and root marker stroke.
draw_radical_bar_item :: #force_inline proc(
    ctx: Layout_Draw_Context,
    style: Dynview_Text_Style,
    item: core.Dynview_Layout_Item,
    resolved_font: rl.Font,
    text: string,
    draw_x, item_y: f32) {

    runtime := ctx.runtime
    font_size := ctx.font_size
    script_style := dynview.style_by_id(item.script_style_id)
    script_font := resolve_font_for_style(ctx.state, script_style, resolved_font)

    baseline_y := item_y + item.ascent
    base_ascent, _ := dynview.style_ascent_descent(style, font_size)
    base_advance :=
        dynview.effective_advance(style, runtime^.compile_cache.last_wrap_advance)
    lead_width := dynview.radical_lead_width(font_size, base_advance)
    front_padding, back_padding := dynview.radical_side_paddings(font_size, base_advance)
    content_x := draw_x + front_padding + lead_width
    base_top := baseline_y - base_ascent
    view_core.ui_text_f32(text, content_x, base_top, style.color,
        resolved_font, font_size)

    content_ascent, content_descent := draw_script_children(Script_Draw_Params{
        runtime = runtime,
        item = item,
        style = style,
        script_style = script_style,
        script_font = script_font,
        font_size = font_size,
        baseline_y = baseline_y,
        draw_x = content_x,
        base_text = text,
        script_color = script_style.color,
    })

    index_text := dynview.text_span_from_buffer(
        &runtime^.command_buffer,
        item.radical_index_text_offset,
        item.radical_index_text_len)

    radical_style := dynview.style_by_id(item.accent_style_id)
    bar_thickness := max(1.0, item.accent_thickness * font_size)
    bar_offset := max(0.0, item.accent_offset * font_size)

    bar_y := baseline_y - content_ascent - bar_offset
    bar_start_x := draw_x + front_padding + lead_width * 0.84
    bar_end_x := draw_x + item.draw_width - back_padding
    rl.DrawLineEx(
        rl.Vector2{bar_start_x, bar_y},
        rl.Vector2{bar_end_x, bar_y},
        bar_thickness,
        radical_style.color)

    hook_start_x := draw_x + front_padding - lead_width * 0.20
    hook_start_y := baseline_y - font_size * 0.3
    hook_flag_x := hook_start_x - 2.5
    root_low_x := draw_x + front_padding + lead_width * 0.26
    root_low_offset := dynview.radical_root_low_offset(font_size, content_descent)
    root_low_y := baseline_y + root_low_offset
    root_rise_x := draw_x + front_padding + lead_width * 0.88
    root_rise_y := bar_y - font_size * 0.14
    root_high_x := draw_x + front_padding + lead_width * 1.24
    root_high_y := bar_y - font_size * 0.06 + bar_thickness * 0.5
    hook_stroke := max(bar_thickness, bar_thickness * 1.25)

    rl.DrawLineEx(
        rl.Vector2{hook_flag_x, hook_start_y},
        rl.Vector2{hook_start_x, hook_start_y},
        hook_stroke,
        radical_style.color)
    rl.DrawLineEx(
        rl.Vector2{hook_start_x, hook_start_y},
        rl.Vector2{root_low_x, root_low_y},
        hook_stroke,
        radical_style.color)
    rl.DrawLineEx(
        rl.Vector2{root_low_x, root_low_y},
        rl.Vector2{root_rise_x, root_rise_y},
        hook_stroke,
        radical_style.color)
    rl.DrawLineEx(
        rl.Vector2{root_rise_x, root_rise_y},
        rl.Vector2{root_high_x, root_high_y},
        hook_stroke,
        radical_style.color)
    rl.DrawLineEx(
        rl.Vector2{root_high_x, root_high_y},
        rl.Vector2{bar_start_x, bar_y},
        hook_stroke,
        radical_style.color)

    if len(index_text) > 0 {
        index_scale := max(0.75, item.script_scale)
        index_font_size := max(3.0, font_size * index_scale)
        index_ascent, _ := dynview.style_ascent_descent(script_style, index_font_size)
        index_cols :=
            max(1, dynview.text_codepoint_count_span(index_text, 0, len(index_text)))
        index_advance := dynview.effective_advance(script_style,
            runtime^.compile_cache.last_wrap_advance) * index_scale
        index_width := f32(index_cols) * index_advance
        index_right_limit := draw_x + front_padding + lead_width * 0.36
        index_x := index_right_limit - index_width
        index_y := baseline_y - content_ascent * 0.62 -
            index_ascent * 0.50 - font_size * 0.25
        view_core.ui_text_f32(index_text, index_x, index_y,
            script_style.color, script_font, index_font_size)
    }
}

//   Draw one cached text item.
draw_cached_text_item :: proc(
    ctx: Layout_Draw_Context,
    style: Dynview_Text_Style,
    item: core.Dynview_Layout_Item,
    item_x, item_y: f32) {

    state := ctx.state
    runtime := ctx.runtime
    panel := ctx.panel
    font := ctx.font
    font_size := ctx.font_size

    text_end := item.text_offset + item.text_len
    if item.text_offset < 0 || item.text_len < 0 {
        return
    }
    if text_end > runtime^.command_buffer.text_bytes_len {
        return
    }

    text := string(runtime^.command_buffer.text_bytes[item.text_offset:text_end])
    resolved_font := resolve_font_for_style(state, style, font)
    draw_x := text_item_draw_x(panel, style, item, item_x)
    text_color := item.has_brush_color ? item.brush_color : style.color

    switch item.kind {
    case .ScriptAttachRecursive, .FracRecursive, .StretchDelimiterRecursive,
        .MatrixRecursive, .LargeOpRecursive, .AccentBarRecursive, .RadicalBarRecursive:
        draw_recursive_structured_item(ctx, style, item, resolved_font, text,
            draw_x, item_y)
    case .MathBlock:
        draw_math_block_item(state, runtime, panel, font, font_size, item, draw_x, item_y)
    case .TextRun, .MathGlyphRun:
        draw_text_run_item(Text_Run_Draw_Params{
            runtime = runtime,
            font_size = font_size,
            style = style,
            item = item,
            text = text,
            resolved_font = resolved_font,
            text_color = text_color,
            draw_x = draw_x,
            item_y = item_y,
        })
    case .InlineLine, .InlineBox, .InlineCircle, .InlineFilledBox, .InlineFilledCircle,
        .InlinePieSection, .InlinePerpendicular, .InlineTriangle, .InlinePentagon:
    }
}

//   Draw inputs for one text-run item: the runtime, style, resolved font,
//   colors, and draw position, grouped so the renderer passes one coherent value.
Text_Run_Draw_Params :: struct {
    runtime:       ^core.Dynview_System,
    font_size:     f32,
    style:         Dynview_Text_Style,
    item:          core.Dynview_Layout_Item,
    text:          string,
    resolved_font: rl.Font,
    text_color:    rl.Color,
    draw_x:        f32,
    item_y:        f32,
}

//   Draw one cached text-run item with optional underline.
draw_text_run_item :: proc(params: Text_Run_Draw_Params) {

    runtime := params.runtime
    font_size := params.font_size
    style := params.style
    item := params.item
    text := params.text
    resolved_font := params.resolved_font
    text_color := params.text_color
    draw_x := params.draw_x
    item_y := params.item_y

    view_core.ui_text(text, int(draw_x), int(item_y), text_color,
        resolved_font, font_size)
    if !style.underline {
        return
    }

    underline_width := f32(item.col_span) * dynview.effective_advance(
        style, runtime^.compile_cache.last_wrap_advance)
    underline_y := item_y + font_size + 1
    rl.DrawLineEx(
        rl.Vector2{draw_x, underline_y},
        rl.Vector2{draw_x + underline_width, underline_y},
        1,
        text_color)
}

//   Draw one cached inline shape item.
draw_cached_inline_basic_item :: #force_inline proc(
    style: Dynview_Text_Style,
    item: core.Dynview_Layout_Item,
    item_x, item_y: f32,
    color: rl.Color) {

    switch item.kind {
    case .InlineLine:
        center_y := item_y + item.draw_height * 0.5
        rl.DrawLineEx(
            rl.Vector2{item_x, center_y},
            rl.Vector2{item_x + item.draw_width, center_y},
            max(1.0, item.inline_atom_stroke),
            color)
    case .InlineBox:
        top_left := rl.Vector2{item_x, item_y}
        top_right := rl.Vector2{item_x + item.draw_width, item_y}
        bottom_left := rl.Vector2{item_x, item_y + item.draw_height}
        bottom_right := rl.Vector2{item_x + item.draw_width, item_y + item.draw_height}
        edge1 := shape_edge_color_or(item.shape_edge_color_1, color)
        edge2 := shape_edge_color_or(item.shape_edge_color_2, color)
        edge3 := shape_edge_color_or(item.shape_edge_color_3, color)
        edge4 := shape_edge_color_or(item.shape_edge_color_4, color)
        stroke := max(1.0, item.inline_atom_stroke)
        rl.DrawLineEx(top_left, top_right, stroke, edge1)
        rl.DrawLineEx(top_right, bottom_right, stroke, edge2)
        rl.DrawLineEx(bottom_right, bottom_left, stroke, edge3)
        rl.DrawLineEx(bottom_left, top_left, stroke, edge4)
    case .InlineCircle:
        center := rl.Vector2{item_x + item.draw_width * 0.5,
            item_y + item.draw_height * 0.5}
        rl.DrawCircleLines(i32(center.x), i32(center.y), item.draw_height * 0.5, color)
        if item.inline_atom_stroke > 1 {
            rl.DrawCircleLines(
                i32(center.x),
                i32(center.y),
                max(1.0, item.draw_height * 0.5 - 1),
                color)
        }
    case .TextRun, .MathGlyphRun, .MathBlock, .ScriptAttachRecursive, .FracRecursive,
         .StretchDelimiterRecursive, .MatrixRecursive, .LargeOpRecursive,
         .AccentBarRecursive, .RadicalBarRecursive, .InlineFilledBox, .InlineFilledCircle,
            .InlinePieSection, .InlinePerpendicular, .InlineTriangle, .InlinePentagon:
    }
}

//   Draw one cached filled inline shape item.
draw_cached_inline_filled_item :: #force_inline proc(
    style: Dynview_Text_Style,
    item: core.Dynview_Layout_Item,
    item_x, item_y: f32,
    color: rl.Color) {

    switch item.kind {
    case .InlineFilledBox:
        rect := rl.Rectangle{item_x, item_y, item.draw_width, item.draw_height}
        rl.DrawRectangleRec(rect, color)
        if item.inline_outline_stroke > 0 {
            rl.DrawRectangleLinesEx(
                rect, max(1.0, item.inline_outline_stroke), style.color)
        }
    case .InlineFilledCircle:
        center := rl.Vector2{item_x + item.draw_width * 0.5,
            item_y + item.draw_height * 0.5}
        radius := item.draw_height * 0.5
        rl.DrawCircleV(center, radius, color)
        if item.inline_outline_stroke > 0 {
            stroke := max(1.0, item.inline_outline_stroke)
            rl.DrawCircleLines(i32(center.x), i32(center.y), radius, style.color)
            if stroke > 1 {
                rl.DrawCircleLines(i32(center.x), i32(center.y),
                    max(1.0, radius - 1), style.color)
            }
        }
    case .TextRun, .MathGlyphRun, .MathBlock, .ScriptAttachRecursive, .FracRecursive,
         .StretchDelimiterRecursive, .MatrixRecursive, .LargeOpRecursive,
         .AccentBarRecursive, .RadicalBarRecursive, .InlineLine, .InlineBox,
            .InlineCircle, .InlinePieSection, .InlinePerpendicular, .InlineTriangle,
            .InlinePentagon:
    }
}

//   Draw one cached advanced inline shape item.
draw_cached_inline_advanced_item :: #force_inline proc(
    style: Dynview_Text_Style,
    item: core.Dynview_Layout_Item,
    item_x, item_y: f32,
    color: rl.Color) {

    switch item.kind {
    case .InlinePieSection:
        center := rl.Vector2{item_x + item.pie_center_offset_x,
            item_y + item.pie_center_offset_y}
        radius := max(
            max(item.pie_center_offset_x, item.draw_width - item.pie_center_offset_x),
            max(item.pie_center_offset_y, item.draw_height - item.pie_center_offset_y))
        outline_color := item.has_outline_color ? item.outline_color : style.color
        stroke := max(1.0, item.inline_outline_stroke)
        if item.pie_is_filled {
            draw_filled_pie_section(center, radius,
                item.pie_start_angle_degrees, item.pie_end_angle_degrees, color)
            if item.inline_outline_stroke > 0 {
                draw_pie_section_outline(center, radius,
                    item.pie_start_angle_degrees, item.pie_end_angle_degrees,
                    stroke, outline_color)
            }
        } else {
            draw_pie_section_outline(center, radius,
                item.pie_start_angle_degrees, item.pie_end_angle_degrees,
                stroke, outline_color)
        }
    case .InlinePerpendicular:
        rect := rl.Rectangle{item_x, item_y, item.draw_width, item.draw_height}
        draw_perpendicular_shape(
            rect,
            max(1.0, item.inline_atom_stroke),
            Perpendicular_Colors{item.brush_color, item.shape_edge_color_1})
    case .InlineTriangle:
        rect := rl.Rectangle{item_x, item_y, item.draw_width, item.draw_height}
        base_color := item.brush_color
        draw_triangle_shape(rect,
            item.shape_is_filled,
            Triangle_Colors{
                base_color,
                shape_edge_color_or(item.shape_edge_color_1, base_color),
                shape_edge_color_or(item.shape_edge_color_2, base_color),
                shape_edge_color_or(item.shape_edge_color_3, base_color),
            },
            max(1.0, item.inline_atom_stroke))
    case .InlinePentagon:
        rect := rl.Rectangle{item_x, item_y, item.draw_width, item.draw_height}
        base_color := item.brush_color
        draw_pentagon_shape(rect,
            item.shape_is_filled,
            Pentagon_Colors{
                base_color,
                shape_edge_color_or(item.shape_edge_color_1, base_color),
                shape_edge_color_or(item.shape_edge_color_2, base_color),
                shape_edge_color_or(item.shape_edge_color_3, base_color),
                shape_edge_color_or(item.shape_edge_color_4, base_color),
                shape_edge_color_or(item.shape_edge_color_5, base_color),
            },
            max(1.0, item.inline_atom_stroke))
    case .TextRun, .MathGlyphRun, .MathBlock, .ScriptAttachRecursive, .FracRecursive,
         .StretchDelimiterRecursive, .MatrixRecursive, .LargeOpRecursive,
         .AccentBarRecursive, .RadicalBarRecursive, .InlineLine, .InlineBox,
         .InlineCircle, .InlineFilledBox, .InlineFilledCircle:
    }
}

//   Draw one cached inline shape item.
draw_cached_inline_item :: proc(
    style: Dynview_Text_Style,
    item: core.Dynview_Layout_Item,
    item_x, item_y: f32) {

    color := dynview.inline_draw_color(style, item)
    switch item.kind {
    case .InlineLine, .InlineBox, .InlineCircle:
        draw_cached_inline_basic_item(style, item, item_x, item_y, color)
    case .InlineFilledBox, .InlineFilledCircle:
        draw_cached_inline_filled_item(style, item, item_x, item_y, color)
    case .InlinePieSection, .InlinePerpendicular, .InlineTriangle, .InlinePentagon:
        draw_cached_inline_advanced_item(style, item, item_x, item_y, color)
    case .TextRun, .MathGlyphRun, .MathBlock, .ScriptAttachRecursive, .FracRecursive,
        .StretchDelimiterRecursive, .MatrixRecursive, .LargeOpRecursive,
        .AccentBarRecursive, .RadicalBarRecursive:
    }
}

//   Draw one cached layout line and all its items.
draw_cached_line :: proc(
    state: ^core.Euclid_General_State,
    runtime: ^core.Dynview_System,
    panel: rl.Rectangle,
    line: core.Dynview_Layout_Line,
    line_top, text_padding, font_size: f32,
    font: rl.Font) {

    item_end := line.item_start + line.item_count
    ctx := Layout_Draw_Context{
        state = state,
        runtime = runtime,
        panel = panel,
        font = font,
        font_size = font_size,
    }
    for item_index in line.item_start..<item_end {
        item := runtime^.compile_cache.layout_items[item_index]
        style := dynview.style_by_id(item.style_id)
        item_x := panel.x + text_padding + item.x_offset
        item_y := line_top + item.y_offset

        if item.kind == .TextRun ||
            item.kind == .MathBlock ||
            item.kind == .MathGlyphRun ||
            item.kind == .ScriptAttachRecursive ||
            item.kind == .FracRecursive ||
            item.kind == .StretchDelimiterRecursive ||
            item.kind == .MatrixRecursive ||
            item.kind == .LargeOpRecursive {
            draw_cached_text_item(ctx, style, item, item_x, item_y)
            continue
        }

        draw_cached_inline_item(style, item, item_x, item_y)
    }
}

//   Draw the canonical layout cache using explicit per-line baselines and offsets.
draw_cached_layout :: proc(
    state: ^core.Euclid_General_State,
    runtime: ^core.Dynview_System,
    panel: rl.Rectangle,
    scroll_y, text_padding, font_size: f32,
    font: rl.Font) {

    if runtime == nil {
        return
    }

    cache := &runtime^.compile_cache
    if !cache^.layout_is_valid {
        return
    }

    panel_top := panel.y
    panel_bottom := panel.y + panel.height
    for line_index in 0..<cache^.layout_line_count {
        line := cache^.layout_lines[line_index]
        line_top := panel.y + text_padding + line.y_offset - scroll_y
        line_bottom := line_top + line.line_height
        top_pad, bottom_pad := line_visual_padding(cache, line, font_size)
        if layout_line_outside_panel(
            line_top - top_pad,
            line_bottom + bottom_pad,
            panel_top,
            panel_bottom) {
            continue
        }

        draw_cached_line(state, runtime, panel, line, line_top,
            text_padding, font_size, font)
    }
}


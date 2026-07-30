package dynview

import "../../../core"
import view_core "../../core"
import "core:math"

import rl "vendor:raylib"

layout_line_outside_panel :: #force_inline proc(
    line_top, line_bottom, panel_top, panel_bottom: f32) -> bool {

    return line_bottom < panel_top || line_top > panel_bottom
}

//   Return extra top/bottom culling margin for lines with script or accent items.
line_visual_padding :: #force_inline proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    line: core.Ui_Dynview_Layout_Line,
    font_size: f32) -> (f32, f32) {

    top_pad: f32 = 0
    bottom_pad: f32 = 0
    item_end := line.item_start + line.item_count
    for item_index in line.item_start..<item_end {
        item := cache^.layout_items[item_index]
        top_pad = max(top_pad, item.visual_padding_top)
        bottom_pad = max(bottom_pad, item.visual_padding_bottom)
        if item.kind != .ScriptAttach && item.kind != .AccentBar && item.kind != .RadicalBar {
            continue
        }

        script_font_size := max(1.0, font_size * max(0.2, item.script_scale))
        script_top_pad, script_bottom_pad := script_visual_padding(script_font_size)
        top_pad = max(top_pad, script_top_pad)
        bottom_pad = max(bottom_pad, script_bottom_pad)
        if item.kind == .AccentBar || item.kind == .RadicalBar {
            has_scripts := item.script_sup_text_len > 0 || item.script_sub_text_len > 0
            accent_pad := accent_script_clearance(font_size, item.script_scale, has_scripts)
            top_pad = max(top_pad, accent_pad)
            bottom_pad = max(bottom_pad, accent_pad)
        }
    }

    return top_pad, bottom_pad
}

//   Draw one cached math-block item from its precomputed program slot.
draw_math_block_item :: proc(
    state: ^core.Euclid_General_State,
    runtime: ^core.Ui_Dynview_Runtime,
    panel: rl.Rectangle,
    font: rl.Font,
    font_size: f32,
    item: core.Ui_Dynview_Layout_Item,
    item_x, item_y: f32) {

    program_id := int(item.math_program_id)
    if runtime == nil || program_id < 0 || program_id >= runtime^.compile_cache.math_program_count {
        return
    }

    program := runtime^.compile_cache.math_programs[program_id]
    if !program.valid {
        return
    }

    baseline_y := item_y + item.ascent
    draw_math_program_at(state, runtime, panel, font, font_size, program, item_x, baseline_y)
}

//   Draw one recursive accent wrapper by drawing the child math program first, then the line.
draw_recursive_accent_item :: proc(
    state: ^core.Euclid_General_State,
    runtime: ^core.Ui_Dynview_Runtime,
    panel: rl.Rectangle,
    font: rl.Font,
    font_size: f32,
    style: Dynview_Text_Style,
    item: core.Ui_Dynview_Layout_Item,
    draw_x, item_y: f32) {

    child_program, ok := math_program_from_id(&runtime^.compile_cache, item.math_program_id)
    if !ok {
        return
    }

    baseline_y := item_y + item.ascent
    draw_math_program_at(state, runtime, panel, font, font_size, child_program^, draw_x, baseline_y)

    accent_style := style_by_id(item.accent_style_id)
    bar_thickness := max(1.0, item.accent_thickness * font_size)
    bar_offset := max(0.0, item.accent_offset * font_size)
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
    state: ^core.Euclid_General_State,
    runtime: ^core.Ui_Dynview_Runtime,
    panel: rl.Rectangle,
    font: rl.Font,
    font_size: f32,
    item: core.Ui_Dynview_Layout_Item,
    draw_x, item_y: f32) {

    child_program, ok := math_program_from_id(&runtime^.compile_cache, item.math_program_id)
    if !ok {
        return
    }

    baseline_y := item_y + item.ascent
    style := style_by_id(item.style_id)
    script_style := style_by_id(item.script_style_id)
    script_font := resolve_font_for_style(state, script_style, font)
    base_advance := effective_advance(style, runtime^.compile_cache.last_wrap_advance)
    lead_width := radical_lead_width(font_size, base_advance)
    front_padding, back_padding := radical_side_paddings(font_size, base_advance)
    content_x := draw_x + front_padding + lead_width

    draw_math_program_at(state, runtime, panel, font, font_size, child_program^, content_x, baseline_y)

    index_text := text_span_from_buffer(
        &runtime^.command_buffer,
        item.radical_index_text_offset,
        item.radical_index_text_len)
    radical_style := style_by_id(item.accent_style_id)
    bar_thickness := max(1.0, item.accent_thickness * font_size)
    bar_offset := max(0.0, item.accent_offset * font_size)

    bar_y := baseline_y - child_program^.ascent - bar_offset
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
    root_low_offset := radical_root_low_offset(font_size, child_program^.descent)
    root_low_y := baseline_y + root_low_offset
    root_rise_x := draw_x + front_padding + lead_width * 0.88
    root_rise_y := bar_y - font_size * 0.14
    root_high_x := draw_x + front_padding + lead_width * 1.24
    root_high_y := bar_y - font_size * 0.06 + bar_thickness * 0.5
    hook_stroke := max(bar_thickness, bar_thickness * 1.25)

    rl.DrawLineEx(rl.Vector2{hook_flag_x, hook_start_y}, rl.Vector2{hook_start_x, hook_start_y}, hook_stroke, radical_style.color)
    rl.DrawLineEx(rl.Vector2{hook_start_x, hook_start_y}, rl.Vector2{root_low_x, root_low_y}, hook_stroke, radical_style.color)
    rl.DrawLineEx(rl.Vector2{root_low_x, root_low_y}, rl.Vector2{root_rise_x, root_rise_y}, hook_stroke, radical_style.color)
    rl.DrawLineEx(rl.Vector2{root_rise_x, root_rise_y}, rl.Vector2{root_high_x, root_high_y}, hook_stroke, radical_style.color)
    rl.DrawLineEx(rl.Vector2{root_high_x, root_high_y}, rl.Vector2{bar_start_x, bar_y}, hook_stroke, radical_style.color)

    if len(index_text) > 0 {
        index_scale := max(0.75, item.script_scale)
        index_font_size := max(3.0, font_size * index_scale)
        index_ascent, _ := style_ascent_descent(script_style, index_font_size)
        index_cols := max(1, view_core.text_codepoint_count(index_text))
        index_advance := effective_advance(script_style, runtime^.compile_cache.last_wrap_advance) * index_scale
        index_width := f32(index_cols) * index_advance
        index_right_limit := draw_x + front_padding + lead_width * 0.36
        index_x := index_right_limit - index_width
        index_y := baseline_y - child_program^.ascent * 0.62 - index_ascent * 0.50 - font_size * 0.25
        view_core.ui_text_f32(index_text, index_x, index_y, script_style.color, script_font, index_font_size)
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
    item: core.Ui_Dynview_Layout_Item,
    item_x: f32) -> f32 {

    if style.alignment == .Center && item.col_start == 0 {
        return panel.x + (panel.width - item.draw_width) * 0.5
    }
    return item_x
}

//   Draw script children for ScriptAttach/AccentBar items and return composed extents.
draw_script_children :: #force_inline proc(
    runtime: ^core.Ui_Dynview_Runtime,
    item: core.Ui_Dynview_Layout_Item,
    style: Dynview_Text_Style,
    script_style: Dynview_Text_Style,
    script_font: rl.Font,
    font_size, baseline_y, draw_x: f32,
    base_text: string,
    script_color: rl.Color) -> (f32, f32) {

    script_scale := max(0.2, item.script_scale)
    script_font_size, sup_raise_px, sub_drop_px := script_draw_offsets(
        font_size,
        script_scale,
        item.script_sup_raise,
        item.script_sub_drop)
    base_ascent, base_descent := style_ascent_descent(style, font_size)
    script_ascent, script_descent := style_ascent_descent(script_style, script_font_size)
    script_top_pad, script_bottom_pad := script_visual_padding(script_font_size)

    sup_text := text_span_from_buffer(
        &runtime^.command_buffer,
        item.script_sup_text_offset,
        item.script_sup_text_len)
    sub_text := text_span_from_buffer(
        &runtime^.command_buffer,
        item.script_sub_text_offset,
        item.script_sub_text_len)

    base_cols := max(1, view_core.text_codepoint_count(base_text))
    base_advance := effective_advance(style, runtime^.compile_cache.last_wrap_advance)
    script_x := draw_x + f32(base_cols) * base_advance + max(1.0, item.script_gap * font_size)

    content_ascent := base_ascent
    content_descent := base_descent

    if len(sup_text) > 0 {
        sup_top := baseline_y - sup_raise_px - script_ascent
        view_core.ui_text_f32(sup_text, script_x, sup_top, script_color, script_font, script_font_size)
        content_ascent = max(content_ascent, script_ascent + sup_raise_px + script_top_pad)
    }

    if len(sub_text) > 0 {
        // Keep padding for layout/culling only; avoid shifting glyphs upward.
        sub_top := baseline_y + sub_drop_px - script_ascent
        view_core.ui_text_f32(sub_text, script_x, sub_top, script_color, script_font, script_font_size)
        content_descent = max(content_descent, script_descent + sub_drop_px + script_bottom_pad)
    }

    return content_ascent, content_descent
}

//   Draw one ScriptAttach item including raised/lowered script text.
draw_script_attach_item :: #force_inline proc(
    state: ^core.Euclid_General_State,
    runtime: ^core.Ui_Dynview_Runtime,
    item: core.Ui_Dynview_Layout_Item,
    style: Dynview_Text_Style,
    resolved_font: rl.Font,
    text: string,
    font_size, draw_x, item_y: f32) {

    script_style := style_by_id(item.script_style_id)
    script_font := resolve_font_for_style(state, script_style, resolved_font)

    baseline_y := item_y + item.ascent
    base_ascent, _ := style_ascent_descent(style, font_size)
    base_top := baseline_y - base_ascent
    view_core.ui_text_f32(text, draw_x, base_top, style.color, resolved_font, font_size)

    _, _ = draw_script_children(
        runtime,
        item,
        style,
        script_style,
        script_font,
        font_size,
        baseline_y,
        draw_x,
        text,
        style.color)
}

//   Draw one recursive ScriptAttach wrapper by drawing a child program and script text.
draw_recursive_script_attach_item :: #force_inline proc(
    state: ^core.Euclid_General_State,
    runtime: ^core.Ui_Dynview_Runtime,
    panel: rl.Rectangle,
    font: rl.Font,
    font_size: f32,
    item: core.Ui_Dynview_Layout_Item,
    draw_x, item_y: f32) {

    child_program, ok := math_program_from_id(&runtime^.compile_cache, item.math_program_id)
    if !ok {
        return
    }

    baseline_y := item_y + item.ascent
    draw_math_program_at(state, runtime, panel, font, font_size, child_program^, draw_x, baseline_y)

    script_style := style_by_id(item.script_style_id)
    script_font := resolve_font_for_style(state, script_style, font)
    script_scale := max(0.2, item.script_scale)
    script_font_size, sup_raise_px, sub_drop_px := script_draw_offsets(
        font_size,
        script_scale,
        item.script_sup_raise,
        item.script_sub_drop)
    script_ascent, _ := style_ascent_descent(script_style, script_font_size)

    sup_text := text_span_from_buffer(
        &runtime^.command_buffer,
        item.script_sup_text_offset,
        item.script_sup_text_len)
    sub_text := text_span_from_buffer(
        &runtime^.command_buffer,
        item.script_sub_text_offset,
        item.script_sub_text_len)

    script_x := draw_x + child_program^.draw_width + max(1.0, item.script_gap * font_size)
    if len(sup_text) > 0 {
        sup_top := baseline_y - sup_raise_px - script_ascent
        view_core.ui_text_f32(sup_text, script_x, sup_top, script_style.color, script_font, script_font_size)
    }

    if len(sub_text) > 0 {
        sub_top := baseline_y + sub_drop_px - script_ascent
        view_core.ui_text_f32(sub_text, script_x, sub_top, script_style.color, script_font, script_font_size)
    }
}

//   Draw one recursive fraction with centered numerator/denominator and center divider.
draw_recursive_fraction_item :: #force_inline proc(
    state: ^core.Euclid_General_State,
    runtime: ^core.Ui_Dynview_Runtime,
    panel: rl.Rectangle,
    font: rl.Font,
    font_size: f32,
    item: core.Ui_Dynview_Layout_Item,
    style: Dynview_Text_Style,
    draw_x, item_y: f32) {

    numerator_program, ok := math_program_from_id(&runtime^.compile_cache, item.math_program_id)
    if !ok {
        return
    }
    denominator_program, ok_den := math_program_from_id(&runtime^.compile_cache, item.secondary_math_program_id)
    if !ok_den {
        return
    }

    baseline_y := item_y + item.ascent
    divider_thickness := max(1.0, item.accent_thickness * font_size)
    divider_half := divider_thickness * 0.5
    divider_gap := fraction_vertical_gap(font_size)

    numerator_x := draw_x + (item.draw_width - numerator_program^.draw_width) * 0.5
    denominator_x := draw_x + (item.draw_width - denominator_program^.draw_width) * 0.5
    numerator_baseline_y := baseline_y - divider_half - divider_gap - numerator_program^.descent
    denominator_baseline_y := baseline_y + divider_half + divider_gap + denominator_program^.ascent
    draw_math_program_at(state, runtime, panel, font, font_size, numerator_program^, numerator_x, numerator_baseline_y)
    draw_math_program_at(state, runtime, panel, font, font_size, denominator_program^, denominator_x, denominator_baseline_y)

    base_advance := effective_advance(style, runtime^.compile_cache.last_wrap_advance)
    side_padding := fraction_side_padding(font_size, base_advance)
    divider_start_x := draw_x + side_padding
    divider_end_x := draw_x + item.draw_width - side_padding
    divider_color := style_by_id(item.accent_style_id).color
    if item.accent_style_id <= 0 {
        divider_color = style.color
    }
    rl.DrawLineEx(
        rl.Vector2{divider_start_x, baseline_y},
        rl.Vector2{divider_end_x, baseline_y},
        divider_thickness,
        divider_color)
}

//   Draw one stretched delimiter glyph at the requested content height.
draw_stretch_delimiter_glyph :: #force_inline proc(
    state: ^core.Euclid_General_State,
    style: Dynview_Text_Style,
    fallback_font: rl.Font,
    wrap_advance, font_size, content_height, content_ascent, content_descent: f32,
    delimiter_kind: i32,
    draw_x, baseline_y: f32) -> f32 {

    if delimiter_kind == DELIMITER_KIND_NONE {
        return 0
    }

    family := delimiter_family(delimiter_kind)
    width := stretch_delimiter_width(style, wrap_advance, font_size, content_height, delimiter_kind)
    if family == .None || width <= 0 {
        return 0
    }

    top_y := baseline_y - content_ascent
    bottom_y := baseline_y + content_descent
    center_y := (top_y + bottom_y) * 0.5
    height := max(1.0, bottom_y - top_y)
    thickness := max(1.0, font_size * 0.09)
    right_side := delimiter_is_right(delimiter_kind)

    switch family {
    case .Vert:
        x := draw_x + width * 0.5
        rl.DrawLineEx(rl.Vector2{x, top_y}, rl.Vector2{x, bottom_y}, thickness, style.color)
        return width
    case .DoubleVert:
        lane_gap := max(1.0, width * 0.26)
        x1 := draw_x + width * 0.5 - lane_gap
        x2 := draw_x + width * 0.5 + lane_gap
        rl.DrawLineEx(rl.Vector2{x1, top_y}, rl.Vector2{x1, bottom_y}, thickness, style.color)
        rl.DrawLineEx(rl.Vector2{x2, top_y}, rl.Vector2{x2, bottom_y}, thickness, style.color)
        return width
    case .Bracket:
        stem_x := draw_x + width * 0.28
        hook_x := draw_x + width * 0.88
        if right_side {
            stem_x = draw_x + width * 0.72
            hook_x = draw_x + width * 0.12
        }
        rl.DrawLineEx(rl.Vector2{stem_x, top_y}, rl.Vector2{stem_x, bottom_y}, thickness, style.color)
        rl.DrawLineEx(rl.Vector2{stem_x, top_y}, rl.Vector2{hook_x, top_y}, thickness, style.color)
        rl.DrawLineEx(rl.Vector2{stem_x, bottom_y}, rl.Vector2{hook_x, bottom_y}, thickness, style.color)
        return width
    case .Ceil:
        stem_x := draw_x + width * 0.28
        hook_x := draw_x + width * 0.88
        if right_side {
            stem_x = draw_x + width * 0.72
            hook_x = draw_x + width * 0.12
        }
        rl.DrawLineEx(rl.Vector2{stem_x, top_y}, rl.Vector2{stem_x, bottom_y}, thickness, style.color)
        rl.DrawLineEx(rl.Vector2{stem_x, top_y}, rl.Vector2{hook_x, top_y}, thickness, style.color)
        return width
    case .Floor:
        stem_x := draw_x + width * 0.28
        hook_x := draw_x + width * 0.88
        if right_side {
            stem_x = draw_x + width * 0.72
            hook_x = draw_x + width * 0.12
        }
        rl.DrawLineEx(rl.Vector2{stem_x, top_y}, rl.Vector2{stem_x, bottom_y}, thickness, style.color)
        rl.DrawLineEx(rl.Vector2{stem_x, bottom_y}, rl.Vector2{hook_x, bottom_y}, thickness, style.color)
        return width
    case .Angle:
        apex_x := draw_x + width * 0.14
        rail_x := draw_x + width * 0.86
        if right_side {
            apex_x = draw_x + width * 0.86
            rail_x = draw_x + width * 0.14
        }
        rl.DrawLineEx(rl.Vector2{rail_x, top_y}, rl.Vector2{apex_x, center_y}, thickness, style.color)
        rl.DrawLineEx(rl.Vector2{apex_x, center_y}, rl.Vector2{rail_x, bottom_y}, thickness, style.color)
        return width
    case .Paren:
        segment_count := 12
        for i in 0..<segment_count {
            t0 := f32(i) / f32(segment_count)
            t1 := f32(i + 1) / f32(segment_count)
            y0 := top_y + height * t0
            y1 := top_y + height * t1
            curve0 := math.sin(t0 * math.PI)
            curve1 := math.sin(t1 * math.PI)

            x0 := draw_x + width * (0.78 - 0.46 * curve0)
            x1 := draw_x + width * (0.78 - 0.46 * curve1)
            if right_side {
                x0 = draw_x + width * (0.22 + 0.46 * curve0)
                x1 = draw_x + width * (0.22 + 0.46 * curve1)
            }

            rl.DrawLineEx(rl.Vector2{x0, y0}, rl.Vector2{x1, y1}, thickness, style.color)
        }
        return width
    case .Brace:
        //   Left brace layout (mirrored automatically for right): tips point right
        //   toward the content, the vertical stem sits just left of center, and the
        //   middle cusp juts left away from the content. Four quarter-turn cubic
        //   curves join two straight stem runs; corner radius stays fixed while the
        //   stems absorb any extra height, matching how TeX stretches braces.
        segment_count := 16
        brace_thickness := max(1.0, thickness * 0.85)

        half_height := height * 0.5
        radius_px := min(max(2.0, font_size * 0.24), half_height * 0.5)
        stem_len := max(0.0, half_height - 2.0 * radius_px)

        r_norm := radius_px / height
        tip_x := f32(0.88)
        stem_x := f32(0.45)
        cusp_x := f32(0.06)
        bend := f32(0.55)

        // Top hook: horizontal at the tip, vertical where it joins the stem.
        draw_normalized_cubic_segment(
            draw_x,
            top_y,
            width,
            height,
            brace_thickness,
            right_side,
            rl.Vector2{tip_x, 0.0},
            rl.Vector2{tip_x - bend * (tip_x - stem_x), 0.0},
            rl.Vector2{stem_x, r_norm * (1.0 - bend)},
            rl.Vector2{stem_x, r_norm},
            style.color,
            segment_count)

        if stem_len > 0.5 {
            x_stem := draw_x + width * stem_x
            if right_side {
                x_stem = draw_x + width * (1.0 - stem_x)
            }
            rl.DrawLineEx(
                rl.Vector2{x_stem, top_y + radius_px},
                rl.Vector2{x_stem, center_y - radius_px},
                brace_thickness,
                style.color)
        }

        // Upper cusp curve: vertical at the stem, horizontal into the cusp point.
        draw_normalized_cubic_segment(
            draw_x,
            top_y,
            width,
            height,
            brace_thickness,
            right_side,
            rl.Vector2{stem_x, 0.5 - r_norm},
            rl.Vector2{stem_x, 0.5 - r_norm * (1.0 - bend)},
            rl.Vector2{cusp_x + bend * (stem_x - cusp_x), 0.5},
            rl.Vector2{cusp_x, 0.5},
            style.color,
            segment_count)

        // Lower cusp curve mirrors the upper one below the midline.
        draw_normalized_cubic_segment(
            draw_x,
            top_y,
            width,
            height,
            brace_thickness,
            right_side,
            rl.Vector2{cusp_x, 0.5},
            rl.Vector2{cusp_x + bend * (stem_x - cusp_x), 0.5},
            rl.Vector2{stem_x, 0.5 + r_norm * (1.0 - bend)},
            rl.Vector2{stem_x, 0.5 + r_norm},
            style.color,
            segment_count)

        if stem_len > 0.5 {
            x_stem := draw_x + width * stem_x
            if right_side {
                x_stem = draw_x + width * (1.0 - stem_x)
            }
            rl.DrawLineEx(
                rl.Vector2{x_stem, center_y + radius_px},
                rl.Vector2{x_stem, bottom_y - radius_px},
                brace_thickness,
                style.color)
        }

        // Bottom hook mirrors the top hook.
        draw_normalized_cubic_segment(
            draw_x,
            top_y,
            width,
            height,
            brace_thickness,
            right_side,
            rl.Vector2{stem_x, 1.0 - r_norm},
            rl.Vector2{stem_x, 1.0 - r_norm * (1.0 - bend)},
            rl.Vector2{tip_x - bend * (tip_x - stem_x), 1.0},
            rl.Vector2{tip_x, 1.0},
            style.color,
            segment_count)
        return width
    case .None:
    }

    delimiter := delimiter_text(delimiter_kind)
    if len(delimiter) == 0 {
        return width
    }

    stretch_scale := max(1.0, content_height / max(1.0, font_size))
    delimiter_font_size := max(1.0, font_size * stretch_scale)
    delim_ascent, _ := style_ascent_descent(style, delimiter_font_size)
    resolved_font := resolve_font_for_style(state, style, fallback_font)
    view_core.ui_text_f32(delimiter, draw_x, baseline_y - delim_ascent, style.color, resolved_font, delimiter_font_size)
    return width
}

//   Draw one recursive stretch-delimiter wrapper with optional child content.
draw_recursive_stretch_delimiter_item :: #force_inline proc(
    state: ^core.Euclid_General_State,
    runtime: ^core.Ui_Dynview_Runtime,
    panel: rl.Rectangle,
    font: rl.Font,
    font_size: f32,
    item: core.Ui_Dynview_Layout_Item,
    style: Dynview_Text_Style,
    draw_x, item_y: f32) {

    baseline_y := item_y + item.ascent
    base_advance := effective_advance(style, runtime^.compile_cache.last_wrap_advance)
    side_padding := stretch_delimiter_side_padding(font_size, base_advance)
    content_height := item.ascent + item.descent

    left_draw_x := draw_x + side_padding
    left_width := draw_stretch_delimiter_glyph(
        state,
        style,
        font,
        runtime^.compile_cache.last_wrap_advance,
        font_size,
        content_height,
        item.ascent,
        item.descent,
        item.accent_mode,
        left_draw_x,
        baseline_y)

    content_x := left_draw_x + left_width
    content_width: f32 = 0
    if item.math_program_id > 0 {
        child_program, ok := math_program_from_id(&runtime^.compile_cache, item.math_program_id)
        if ok {
            content_width = child_program^.draw_width
            draw_math_program_at(state, runtime, panel, font, font_size, child_program^, content_x, baseline_y)
        }
    }

    right_draw_x := content_x + content_width
    _ = draw_stretch_delimiter_glyph(
        state,
        style,
        font,
        runtime^.compile_cache.last_wrap_advance,
        font_size,
        content_height,
        item.ascent,
        item.descent,
        item.radical_mode,
        right_draw_x,
        baseline_y)
}

//   Draw one recursive matrix wrapper by centering cells per column and baselining per row.
draw_recursive_matrix_item :: #force_inline proc(
    state: ^core.Euclid_General_State,
    runtime: ^core.Ui_Dynview_Runtime,
    panel: rl.Rectangle,
    font: rl.Font,
    font_size: f32,
    item: core.Ui_Dynview_Layout_Item,
    style: Dynview_Text_Style,
    draw_x, item_y: f32) {

    rows := int(item.accent_mode)
    cols := int(item.radical_mode)
    if rows <= 0 || cols <= 0 || rows > 16 || cols > 16 {
        return
    }

    cell_program, ok := math_program_from_id(&runtime^.compile_cache, item.math_program_id)
    if !ok || cell_program^.command_count < rows * cols {
        return
    }

    col_widths: [16]f32
    row_ascents: [16]f32
    row_descents: [16]f32
    cell_items: [256]core.Ui_Dynview_Layout_Item
    for row in 0..<rows {
        for col in 0..<cols {
            cell_index := row * cols + col
            cmd_index := cell_program^.command_start + cell_index
            cell_cmd := runtime^.compile_cache.math_commands[cmd_index]
            cell_item, cell_ok := math_program_item(
                &runtime^.compile_cache,
                &runtime^.command_buffer,
                cell_cmd,
                font_size)
            if !cell_ok {
                return
            }

            cell_items[cell_index] = cell_item
            col_widths[col] = max(col_widths[col], cell_item.draw_width)
            row_ascents[row] = max(row_ascents[row], cell_item.ascent)
            row_descents[row] = max(row_descents[row], cell_item.descent)
        }
    }

    alignments, _ := decode_matrix_column_alignments(
        &runtime^.command_buffer,
        core.Ui_Dynview_Command{
            script_sub_text_offset = item.script_sub_text_offset,
            script_sub_text_len = item.script_sub_text_len,
        },
        cols)

    base_advance := effective_advance(style, runtime^.compile_cache.last_wrap_advance)
    column_gap := matrix_column_gap(font_size, base_advance)
    row_gap := matrix_row_gap(font_size)

    row_top := item_y
    for row in 0..<rows {
        row_baseline := row_top + row_ascents[row]
        col_x := draw_x
        for col in 0..<cols {
            cell_index := row * cols + col
            cell_item := cell_items[cell_index]
            cell_x := matrix_aligned_cell_x(
                col_x,
                col_widths[col],
                cell_item.draw_width,
                alignments[col])
            command_start := cell_program^.command_start + cell_index
            cell_single_program := core.Ui_Dynview_Math_Program{
                valid = true,
                command_start = command_start,
                command_count = 1,
                draw_width = cell_item.draw_width,
                ascent = cell_item.ascent,
                descent = cell_item.descent,
            }
            draw_math_program_at(
                state,
                runtime,
                panel,
                font,
                font_size,
                cell_single_program,
                cell_x,
                row_baseline)

            col_x += col_widths[col]
            if col + 1 < cols {
                col_x += column_gap
            }
        }

        row_top += row_ascents[row] + row_descents[row]
        if row + 1 < rows {
            row_top += row_gap
        }
    }
}

//   Draw one recursive structured math item variant routed by layout item kind.
draw_recursive_structured_item :: #force_inline proc(
    state: ^core.Euclid_General_State,
    runtime: ^core.Ui_Dynview_Runtime,
    panel: rl.Rectangle,
    font: rl.Font,
    font_size: f32,
    style: Dynview_Text_Style,
    item: core.Ui_Dynview_Layout_Item,
    resolved_font: rl.Font,
    text: string,
    draw_x, item_y: f32) {

    switch item.kind {
    case .ScriptAttachRecursive:
        draw_recursive_script_attach_item(
            state,
            runtime,
            panel,
            font,
            font_size,
            item,
            draw_x,
            item_y)
    case .FracRecursive:
        draw_recursive_fraction_item(
            state,
            runtime,
            panel,
            font,
            font_size,
            item,
            style,
            draw_x,
            item_y)
    case .StretchDelimiterRecursive:
        draw_recursive_stretch_delimiter_item(
            state,
            runtime,
            panel,
            font,
            font_size,
            item,
            style,
            draw_x,
            item_y)
    case .MatrixRecursive:
        draw_recursive_matrix_item(
            state,
            runtime,
            panel,
            font,
            font_size,
            item,
            style,
            draw_x,
            item_y)
    case .LargeOpRecursive:
        draw_large_op_recursive_item(
            state,
            runtime,
            item,
            style,
            resolved_font,
            text,
            font_size,
            draw_x,
            item_y)
    case .AccentBarRecursive:
        draw_recursive_accent_item(
            state,
            runtime,
            panel,
            font,
            font_size,
            style,
            item,
            draw_x,
            item_y)
    case .RadicalBarRecursive:
        draw_recursive_radical_item(state, runtime, panel, font, font_size, item, draw_x, item_y)
    case .TextRun, .MathGlyphRun, .MathBlock, .ScriptAttach, .AccentBar, .RadicalBar,
        .InlineLine, .InlineBox, .InlineCircle, .InlineFilledBox, .InlineFilledCircle,
        .InlinePieSection:
    }
}

//   Draw one display-style large operator with stacked limits above and below.
draw_large_op_recursive_item :: #force_inline proc(
    state: ^core.Euclid_General_State,
    runtime: ^core.Ui_Dynview_Runtime,
    item: core.Ui_Dynview_Layout_Item,
    style: Dynview_Text_Style,
    resolved_font: rl.Font,
    text: string,
    font_size, draw_x, item_y: f32) {

    glyph_scale := large_op_glyph_scale(item.large_op_kind)
    glyph_font_size := max(1.0, font_size * glyph_scale)
    glyph_ascent, glyph_descent := style_ascent_descent(style, glyph_font_size)
    glyph_cols := max(1, view_core.text_codepoint_count(text))
    glyph_advance := effective_advance(style, runtime^.compile_cache.last_wrap_advance) * glyph_scale
    glyph_width := f32(glyph_cols) * glyph_advance

    script_style := style_by_id(item.script_style_id)
    script_font := resolve_font_for_style(state, script_style, resolved_font)
    limit_scale := large_op_limit_scale(max(0.2, item.script_scale))
    limit_font_size := max(1.0, font_size * limit_scale)
    limit_ascent, limit_descent := style_ascent_descent(script_style, limit_font_size)
    limit_advance := effective_advance(script_style, runtime^.compile_cache.last_wrap_advance) * limit_scale

    sup_text := text_span_from_buffer(
        &runtime^.command_buffer,
        item.script_sup_text_offset,
        item.script_sup_text_len)
    sub_text := text_span_from_buffer(
        &runtime^.command_buffer,
        item.script_sub_text_offset,
        item.script_sub_text_len)
    sup_cols := view_core.text_codepoint_count(sup_text)
    sub_cols := view_core.text_codepoint_count(sub_text)

    upper_height: f32 = 0
    if sup_cols > 0 {
        upper_height = limit_ascent + limit_descent
    }
    lower_height: f32 = 0
    if sub_cols > 0 {
        lower_height = limit_ascent + limit_descent
    }

    limit_gap := large_op_limit_gap_for_kind(item.large_op_kind, font_size, item.script_gap)
    glyph_top := item_y
    if sup_cols > 0 {
        glyph_top += upper_height + limit_gap
    }
    glyph_x := draw_x + (item.draw_width - glyph_width) * 0.5
    view_core.ui_text_f32(text, glyph_x, glyph_top, style.color, resolved_font, glyph_font_size)

    if sup_cols > 0 {
        sup_width := f32(sup_cols) * limit_advance
        sup_x := draw_x + (item.draw_width - sup_width) * 0.5
        sup_top := glyph_top - limit_gap - upper_height
        view_core.ui_text_f32(sup_text, sup_x, sup_top, script_style.color, script_font, limit_font_size)
    }

    if sub_cols > 0 {
        sub_width := f32(sub_cols) * limit_advance
        sub_x := draw_x + (item.draw_width - sub_width) * 0.5
        sub_top := glyph_top + glyph_ascent + glyph_descent + limit_gap
        view_core.ui_text_f32(sub_text, sub_x, sub_top, script_style.color, script_font, limit_font_size)
    }
}

//   Draw one AccentBar item including optional script children and accent stroke.
draw_accent_bar_item :: #force_inline proc(
    state: ^core.Euclid_General_State,
    runtime: ^core.Ui_Dynview_Runtime,
    item: core.Ui_Dynview_Layout_Item,
    style: Dynview_Text_Style,
    resolved_font: rl.Font,
    text: string,
    font_size, draw_x, item_y: f32) {

    script_style := style_by_id(item.script_style_id)
    script_font := resolve_font_for_style(state, script_style, resolved_font)

    baseline_y := item_y + item.ascent
    base_ascent, _ := style_ascent_descent(style, font_size)
    base_top := baseline_y - base_ascent
    view_core.ui_text_f32(text, draw_x, base_top, style.color, resolved_font, font_size)

    content_ascent, content_descent := draw_script_children(
        runtime,
        item,
        style,
        script_style,
        script_font,
        font_size,
        baseline_y,
        draw_x,
        text,
        script_style.color)

    accent_style := style_by_id(item.accent_style_id)
    bar_thickness := max(1.0, item.accent_thickness * font_size)
    has_scripts := item.script_sup_text_len > 0 || item.script_sub_text_len > 0
    bar_offset := max(0.0, item.accent_offset * font_size) +
        accent_script_clearance(font_size, item.script_scale, has_scripts)

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
    state: ^core.Euclid_General_State,
    runtime: ^core.Ui_Dynview_Runtime,
    item: core.Ui_Dynview_Layout_Item,
    style: Dynview_Text_Style,
    resolved_font: rl.Font,
    text: string,
    font_size, draw_x, item_y: f32) {

    script_style := style_by_id(item.script_style_id)
    script_font := resolve_font_for_style(state, script_style, resolved_font)

    baseline_y := item_y + item.ascent
    base_ascent, _ := style_ascent_descent(style, font_size)
    base_advance := effective_advance(style, runtime^.compile_cache.last_wrap_advance)
    lead_width := radical_lead_width(font_size, base_advance)
    front_padding, back_padding := radical_side_paddings(font_size, base_advance)
    content_x := draw_x + front_padding + lead_width
    base_top := baseline_y - base_ascent
    view_core.ui_text_f32(text, content_x, base_top, style.color, resolved_font, font_size)

    content_ascent, content_descent := draw_script_children(
        runtime,
        item,
        style,
        script_style,
        script_font,
        font_size,
        baseline_y,
        content_x,
        text,
        script_style.color)

    index_text := text_span_from_buffer(
        &runtime^.command_buffer,
        item.radical_index_text_offset,
        item.radical_index_text_len)

    radical_style := style_by_id(item.accent_style_id)
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
    root_low_offset := radical_root_low_offset(font_size, content_descent)
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
        index_ascent, _ := style_ascent_descent(script_style, index_font_size)
        index_cols := max(1, view_core.text_codepoint_count(index_text))
        index_advance := effective_advance(script_style, runtime^.compile_cache.last_wrap_advance) * index_scale
        index_width := f32(index_cols) * index_advance
        index_right_limit := draw_x + front_padding + lead_width * 0.36
        index_x := index_right_limit - index_width
        index_y := baseline_y - content_ascent * 0.62 - index_ascent * 0.50 - font_size * 0.25
        view_core.ui_text_f32(index_text, index_x, index_y, script_style.color, script_font, index_font_size)
    }
}

//   Draw one cached text item.
draw_cached_text_item :: proc(
    state: ^core.Euclid_General_State,
    runtime: ^core.Ui_Dynview_Runtime,
    panel: rl.Rectangle,
    font: rl.Font,
    font_size: f32,
    style: Dynview_Text_Style,
    item: core.Ui_Dynview_Layout_Item,
    item_x, item_y: f32) {

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

    switch item.kind {
    case .ScriptAttach:
        draw_script_attach_item(
            state,
            runtime,
            item,
            style,
            resolved_font,
            text,
            font_size,
            draw_x,
            item_y)
    case .AccentBar:
        draw_accent_bar_item(
            state,
            runtime,
            item,
            style,
            resolved_font,
            text,
            font_size,
            draw_x,
            item_y)
    case .RadicalBar:
        draw_radical_bar_item(
            state,
            runtime,
            item,
            style,
            resolved_font,
            text,
            font_size,
            draw_x,
            item_y)
    case .ScriptAttachRecursive, .FracRecursive, .StretchDelimiterRecursive,
        .MatrixRecursive, .LargeOpRecursive, .AccentBarRecursive, .RadicalBarRecursive:
        draw_recursive_structured_item(
            state,
            runtime,
            panel,
            font,
            font_size,
            style,
            item,
            resolved_font,
            text,
            draw_x,
            item_y)
    case .MathBlock:
        draw_math_block_item(state, runtime, panel, font, font_size, item, draw_x, item_y)
    case .TextRun, .MathGlyphRun:
        view_core.ui_text(text, int(draw_x), int(item_y), style.color, resolved_font, font_size)
    case .InlineLine, .InlineBox, .InlineCircle, .InlineFilledBox, .InlineFilledCircle, .InlinePieSection:
    }
}

//   Draw one cached inline shape item.
draw_cached_inline_item :: proc(
    style: Dynview_Text_Style,
    item: core.Ui_Dynview_Layout_Item,
    item_x, item_y: f32) {

    color := inline_draw_color(style, item)
    switch item.kind {
    case .InlineLine:
        center_y := item_y + item.draw_height * 0.5
        rl.DrawLineEx(
            rl.Vector2{item_x, center_y},
            rl.Vector2{item_x + item.draw_width, center_y},
            max(1.0, item.inline_atom_stroke),
            color)
    case .InlineBox:
        rl.DrawRectangleLinesEx(
            rl.Rectangle{item_x, item_y, item.draw_width, item.draw_height},
            max(1.0, item.inline_atom_stroke),
            color)
    case .InlineCircle:
        center := rl.Vector2{item_x + item.draw_width * 0.5, item_y + item.draw_height * 0.5}
        rl.DrawCircleLines(i32(center.x), i32(center.y), item.draw_height * 0.5, color)
        if item.inline_atom_stroke > 1 {
            rl.DrawCircleLines(
                i32(center.x),
                i32(center.y),
                max(1.0, item.draw_height * 0.5 - 1),
                color)
        }
    case .InlineFilledBox:
        rect := rl.Rectangle{item_x, item_y, item.draw_width, item.draw_height}
        rl.DrawRectangleRec(rect, color)
        if item.inline_outline_stroke > 0 {
            rl.DrawRectangleLinesEx(rect, max(1.0, item.inline_outline_stroke), style.color)
        }
    case .InlineFilledCircle:
        center := rl.Vector2{item_x + item.draw_width * 0.5, item_y + item.draw_height * 0.5}
        radius := item.draw_height * 0.5
        rl.DrawCircleV(center, radius, color)
        if item.inline_outline_stroke > 0 {
            stroke := max(1.0, item.inline_outline_stroke)
            rl.DrawCircleLines(i32(center.x), i32(center.y), radius, style.color)
            if stroke > 1 {
                rl.DrawCircleLines(i32(center.x), i32(center.y), max(1.0, radius - 1), style.color)
            }
        }
    case .InlinePieSection:
        center := rl.Vector2{item_x + item.draw_width * 0.5, item_y + item.draw_height * 0.5}
        radius := item.draw_height * 0.5
        draw_filled_pie_section(
            center,
            radius,
            item.pie_start_angle_degrees,
            item.pie_end_angle_degrees,
            color)
        if item.inline_outline_stroke > 0 {
            stroke := max(1.0, item.inline_outline_stroke)
            start_point := pie_point(center, radius, item.pie_start_angle_degrees)
            end_point := pie_point(center, radius, item.pie_end_angle_degrees)
            rl.DrawLineEx(center, start_point, stroke, style.color)
            rl.DrawLineEx(center, end_point, stroke, style.color)
        }
    case .TextRun, .MathGlyphRun, .MathBlock, .ScriptAttach, .ScriptAttachRecursive, .FracRecursive, .StretchDelimiterRecursive, .MatrixRecursive, .LargeOpRecursive, .AccentBar,
        .AccentBarRecursive, .RadicalBar, .RadicalBarRecursive:
    }
}

//   Draw one cached layout line and all its items.
draw_cached_line :: proc(
    state: ^core.Euclid_General_State,
    runtime: ^core.Ui_Dynview_Runtime,
    panel: rl.Rectangle,
    line: core.Ui_Dynview_Layout_Line,
    line_top, text_padding, font_size: f32,
    font: rl.Font) {

    item_end := line.item_start + line.item_count
    for item_index in line.item_start..<item_end {
        item := runtime^.compile_cache.layout_items[item_index]
        style := style_by_id(item.style_id)
        item_x := panel.x + text_padding + item.x_offset
        item_y := line_top + item.y_offset

        if item.kind == .TextRun ||
            item.kind == .MathBlock ||
            item.kind == .MathGlyphRun ||
            item.kind == .ScriptAttach ||
            item.kind == .ScriptAttachRecursive ||
            item.kind == .FracRecursive ||
            item.kind == .StretchDelimiterRecursive ||
            item.kind == .MatrixRecursive ||
            item.kind == .LargeOpRecursive ||
            item.kind == .AccentBar ||
            item.kind == .RadicalBar {
            draw_cached_text_item(state, runtime, panel, font, font_size, style, item, item_x, item_y)
            continue
        }

        draw_cached_inline_item(style, item, item_x, item_y)
    }
}

//   Draw the canonical layout cache using explicit per-line baselines and offsets.
draw_cached_layout :: proc(
    state: ^core.Euclid_General_State,
    runtime: ^core.Ui_Dynview_Runtime,
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

        draw_cached_line(state, runtime, panel, line, line_top, text_padding, font_size, font)
    }
}


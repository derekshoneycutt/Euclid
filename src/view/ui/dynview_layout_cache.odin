package ui

import "../../core"
import view_core "../core"

import rl "vendor:raylib"

Dynview_Layout_Line_Accumulator :: struct {
    item_start: int,
    item_count: int,
    max_ascent: f32,
    max_descent: f32,
}

Dynview_Block_Format :: struct {
    alignment: Dynview_Text_Alignment,
    indent_cols: int,
    paragraph_spacing_before: f32,
    paragraph_spacing_after: f32,
    line_height_multiplier: f32,
}

Dynview_Layout_State :: struct {
    line_index: int,
    col: int,
    y_offset: f32,
    line_gap: f32,
    active_block_id: i32,
    active_block_kind: i32,
    active_block_format: Dynview_Block_Format,
}

Dynview_Layout_Build_Context :: struct {
    cache: ^core.Ui_Dynview_Compile_Cache,
    buffer: ^core.Ui_Dynview_Command_Buffer,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    font_size: f32,
    base_ascent: f32,
    base_descent: f32,
}

//   Return style-aware ascent/descent estimates from active font size.
dynview_style_ascent_descent :: #force_inline proc(style: Dynview_Text_Style, font_size: f32) -> (f32, f32) {
    scale := max(0.8, style.wrap_scale)
    ascent := max(1.0, font_size * (0.74 + 0.06 * scale))
    descent := max(1.0, font_size * (0.22 + 0.02 * scale))

    if style.bold {
        ascent += font_size * 0.06
    }

    if style.italic {
        descent += font_size * 0.03
    }

    line_height_mult := max(0.6, style.line_height_multiplier)
    return ascent * line_height_mult, descent * line_height_mult
}

//   Resolve script draw offsets using one shared model for layout and rendering.
dynview_script_draw_offsets :: #force_inline proc(
    font_size, script_scale, sup_raise, sub_drop: f32) -> (f32, f32, f32) {

    script_font_size := max(1.0, font_size * max(0.2, script_scale))
    sup_vertical_bias := max(0.6, script_font_size * 0.08)
    sub_vertical_bias := max(0.9, script_font_size * 0.16)
    sub_lift_px := max(0.5, script_font_size * 0.06)
    sup_raise_px := max(0.0, sup_raise * font_size - sup_vertical_bias)
    sub_drop_px := max(0.0, sub_drop * font_size - sub_vertical_bias - sub_lift_px)
    return script_font_size, sup_raise_px, sub_drop_px
}

//   Return conservative script padding to avoid rasterized edge truncation.
dynview_script_visual_padding :: #force_inline proc(script_font_size: f32) -> (f32, f32) {
    top_pad := max(0.6, script_font_size * 0.10)
    bottom_pad := max(0.8, script_font_size * 0.14)
    return top_pad, bottom_pad
}

//   Add extra accent-bar clearance when script glyphs are present.
dynview_accent_script_clearance :: #force_inline proc(
    font_size, script_scale: f32,
    has_scripts: bool) -> f32 {

    if !has_scripts {
        return 0
    }

    script_font_size := max(1.0, font_size * max(0.2, script_scale))
    return max(0.5, script_font_size * 0.08)
}

//   Return reserved leading width for one rendered square-root marker.
dynview_radical_lead_width :: #force_inline proc(font_size, base_advance: f32) -> f32 {
    return max(base_advance * 1.48, font_size * 0.92)
}

//   Return asymmetric horizontal side padding for radical items.
dynview_radical_side_paddings :: #force_inline proc(font_size, base_advance: f32) -> (f32, f32) {
    front_padding := max(1.0, max(base_advance * 0.5, font_size * 0.5))
    back_padding := max(0.1, max(base_advance * 0.1, font_size * 0.075))
    return front_padding, back_padding
}

//   Return default block format values keyed by block kind.
dynview_block_format_for_kind :: #force_inline proc(block_kind: i32) -> Dynview_Block_Format {
    switch block_kind {
    case 1: // BRIDGE_DYNVIEW_BLOCK_INPUT
        return Dynview_Block_Format{
            indent_cols = 2,
            paragraph_spacing_before = 2,
            paragraph_spacing_after = 2,
            line_height_multiplier = 1.0,
        }
    case 2: // BRIDGE_DYNVIEW_BLOCK_OUTPUT
        return Dynview_Block_Format{
            paragraph_spacing_after = 1,
            line_height_multiplier = 1.0,
        }
    }

    return Dynview_Block_Format{
        line_height_multiplier = 1.0,
    }
}

//   Merge per-style values with active block format controls.
dynview_style_with_block_format :: #force_inline proc(
    style: Dynview_Text_Style,
    block_format: Dynview_Block_Format) -> Dynview_Text_Style {

    merged := style
    if merged.alignment == .Left && block_format.alignment != .Left {
        merged.alignment = block_format.alignment
    }

    merged.indent_cols = max(merged.indent_cols, block_format.indent_cols)
    merged.paragraph_spacing_before = max(merged.paragraph_spacing_before, block_format.paragraph_spacing_before)
    merged.paragraph_spacing_after = max(merged.paragraph_spacing_after, block_format.paragraph_spacing_after)
    merged.line_height_multiplier = max(merged.line_height_multiplier, block_format.line_height_multiplier)
    return merged
}

//   Reset canonical layout cache fields before rebuild.
dynview_layout_reset_cache :: proc(cache: ^core.Ui_Dynview_Compile_Cache) {
    cache^.layout_line_count = 0
    cache^.layout_item_count = 0
    cache^.layout_total_height = 0
    cache^.layout_average_line_height = 0
    cache^.layout_is_valid = false
}

//   Return one precomputed math program slot when the command references a valid id.
dynview_math_program_from_command :: #force_inline proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    cmd: core.Ui_Dynview_Command) -> (^core.Ui_Dynview_Math_Program, bool) {

    program_id := int(cmd.math_program_id)
    if cache == nil || program_id < 0 || program_id >= cache^.math_program_count {
        return nil, false
    }

    program := &cache^.math_programs[program_id]
    if !program^.valid {
        return nil, false
    }

    return program, true
}

//   Return one precomputed child math program slot from a math-command reference.
dynview_math_program_from_id :: #force_inline proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    program_id: i32) -> (^core.Ui_Dynview_Math_Program, bool) {

    index := int(program_id)
    if cache == nil || index < 0 || index >= cache^.math_program_count {
        return nil, false
    }

    program := &cache^.math_programs[index]
    if !program^.valid {
        return nil, false
    }

    return program, true
}

//   Build one layout-like item for a text or math-glyph child command inside a math block.
dynview_math_program_text_item :: #force_inline proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    buffer: ^core.Ui_Dynview_Command_Buffer,
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> core.Ui_Dynview_Layout_Item {

    text := dynview_text_for_command(buffer, cmd)
    cols := max(1, text_codepoint_count(text))
    ascent, descent := dynview_style_ascent_descent(style, font_size)
    kind := core.Ui_Dynview_Layout_Item_Kind.TextRun
    if cmd.kind == .MathGlyphRun {
        kind = .MathGlyphRun
    }

    return core.Ui_Dynview_Layout_Item{
        kind = kind,
        style_id = cmd.style_id,
        text_offset = cmd.text_offset,
        text_len = cmd.text_len,
        draw_width = f32(cols) * dynview_effective_advance(style, cache^.last_wrap_advance),
        draw_height = ascent + descent,
        ascent = ascent,
        descent = descent,
    }
}

//   Build one layout-like item for a script-attach child command inside a math block.
dynview_math_program_script_item :: #force_inline proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    buffer: ^core.Ui_Dynview_Command_Buffer,
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> core.Ui_Dynview_Layout_Item {

    base_text := dynview_text_span_from_buffer(
        buffer,
        cmd.script_base_text_offset,
        cmd.script_base_text_len)
    sup_text := dynview_text_span_from_buffer(
        buffer,
        cmd.script_sup_text_offset,
        cmd.script_sup_text_len)
    sub_text := dynview_text_span_from_buffer(
        buffer,
        cmd.script_sub_text_offset,
        cmd.script_sub_text_len)

    base_cols := max(1, text_codepoint_count(base_text))
    sup_cols := text_codepoint_count(sup_text)
    sub_cols := text_codepoint_count(sub_text)
    script_cols := max(sup_cols, sub_cols)

    text_ascent, text_descent := dynview_style_ascent_descent(style, font_size)
    script_style := dynview_style_by_id(cmd.script_style_id)
    script_scale := max(0.2, cmd.script_scale)
    script_font_size, sup_raise_px, sub_drop_px := dynview_script_draw_offsets(
        font_size,
        script_scale,
        cmd.script_sup_raise,
        cmd.script_sub_drop)
    script_ascent, script_descent := dynview_style_ascent_descent(script_style, script_font_size)
    script_top_pad, script_bottom_pad := dynview_script_visual_padding(script_font_size)

    ascent := text_ascent
    descent := text_descent
    if sup_cols > 0 {
        ascent = max(ascent, script_ascent + sup_raise_px + script_top_pad)
    }
    if sub_cols > 0 {
        descent = max(descent, script_descent + sub_drop_px + script_bottom_pad)
    }

    base_advance := dynview_effective_advance(style, cache^.last_wrap_advance)
    script_advance := dynview_effective_advance(script_style, cache^.last_wrap_advance) * script_scale
    gap_px := max(1.0, cmd.script_gap * font_size)
    base_width := f32(base_cols) * base_advance
    script_width := f32(script_cols) * script_advance
    draw_width := base_width
    if script_cols > 0 {
        draw_width += gap_px + script_width
    }

    return core.Ui_Dynview_Layout_Item{
        kind = .ScriptAttach,
        style_id = cmd.style_id,
        text_offset = cmd.script_base_text_offset,
        text_len = cmd.script_base_text_len,
        script_sup_text_offset = cmd.script_sup_text_offset,
        script_sup_text_len = cmd.script_sup_text_len,
        script_sub_text_offset = cmd.script_sub_text_offset,
        script_sub_text_len = cmd.script_sub_text_len,
        script_style_id = cmd.script_style_id,
        script_scale = script_scale,
        script_sup_raise = cmd.script_sup_raise,
        script_sub_drop = cmd.script_sub_drop,
        script_gap = cmd.script_gap,
        draw_width = draw_width,
        draw_height = ascent + descent,
        ascent = ascent,
        descent = descent,
        visual_padding_top = script_top_pad,
        visual_padding_bottom = script_bottom_pad,
    }
}

//   Build one layout-like item for a recursive script wrapper around a child math program.
dynview_math_program_recursive_script_item :: #force_inline proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    buffer: ^core.Ui_Dynview_Command_Buffer,
    cmd: core.Ui_Dynview_Command,
    font_size: f32) -> (core.Ui_Dynview_Layout_Item, bool) {

    child_program, ok := dynview_math_program_from_id(cache, cmd.math_program_id)
    if !ok || !dynview_measure_math_program(cache, buffer, child_program, font_size) {
        return core.Ui_Dynview_Layout_Item{}, false
    }

    sup_text := dynview_text_span_from_buffer(
        buffer,
        cmd.script_sup_text_offset,
        cmd.script_sup_text_len)
    sub_text := dynview_text_span_from_buffer(
        buffer,
        cmd.script_sub_text_offset,
        cmd.script_sub_text_len)

    sup_cols := text_codepoint_count(sup_text)
    sub_cols := text_codepoint_count(sub_text)
    script_cols := max(sup_cols, sub_cols)

    script_style := dynview_style_by_id(cmd.script_style_id)
    script_scale := max(0.2, cmd.script_scale)
    script_font_size, sup_raise_px, sub_drop_px := dynview_script_draw_offsets(
        font_size,
        script_scale,
        cmd.script_sup_raise,
        cmd.script_sub_drop)
    script_ascent, script_descent := dynview_style_ascent_descent(script_style, script_font_size)
    script_top_pad, script_bottom_pad := dynview_script_visual_padding(script_font_size)

    ascent := child_program^.ascent
    descent := child_program^.descent
    if sup_cols > 0 {
        ascent = max(ascent, script_ascent + sup_raise_px + script_top_pad)
    }
    if sub_cols > 0 {
        descent = max(descent, script_descent + sub_drop_px + script_bottom_pad)
    }

    script_advance := dynview_effective_advance(script_style, cache^.last_wrap_advance) * script_scale
    gap_px := max(1.0, cmd.script_gap * font_size)
    script_width := f32(script_cols) * script_advance
    draw_width := child_program^.draw_width
    if script_cols > 0 {
        draw_width += gap_px + script_width
    }

    return core.Ui_Dynview_Layout_Item{
        kind = .ScriptAttachRecursive,
        style_id = cmd.style_id,
        math_program_id = cmd.math_program_id,
        script_sup_text_offset = cmd.script_sup_text_offset,
        script_sup_text_len = cmd.script_sup_text_len,
        script_sub_text_offset = cmd.script_sub_text_offset,
        script_sub_text_len = cmd.script_sub_text_len,
        script_style_id = cmd.script_style_id,
        script_scale = script_scale,
        script_sup_raise = cmd.script_sup_raise,
        script_sub_drop = cmd.script_sub_drop,
        script_gap = cmd.script_gap,
        draw_width = draw_width,
        draw_height = ascent + descent,
        ascent = ascent,
        descent = descent,
        visual_padding_top = max(child_program^.visual_padding_top, script_top_pad),
        visual_padding_bottom = max(child_program^.visual_padding_bottom, script_bottom_pad),
    }, true
}

//   Build one layout-like item for an accent-bar child command inside a math block.
dynview_math_program_accent_item :: #force_inline proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    buffer: ^core.Ui_Dynview_Command_Buffer,
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> core.Ui_Dynview_Layout_Item {

    base_text := dynview_text_for_command(buffer, cmd)
    sup_text := dynview_text_span_from_buffer(
        buffer,
        cmd.script_sup_text_offset,
        cmd.script_sup_text_len)
    sub_text := dynview_text_span_from_buffer(
        buffer,
        cmd.script_sub_text_offset,
        cmd.script_sub_text_len)

    base_cols := max(1, text_codepoint_count(base_text))
    sup_cols := text_codepoint_count(sup_text)
    sub_cols := text_codepoint_count(sub_text)
    script_cols := max(sup_cols, sub_cols)

    text_ascent, text_descent := dynview_style_ascent_descent(style, font_size)
    script_style := dynview_style_by_id(cmd.script_style_id)
    script_scale := max(0.2, cmd.script_scale)
    script_font_size, sup_raise_px, sub_drop_px := dynview_script_draw_offsets(
        font_size,
        script_scale,
        cmd.script_sup_raise,
        cmd.script_sub_drop)
    script_ascent, script_descent := dynview_style_ascent_descent(script_style, script_font_size)
    script_top_pad, script_bottom_pad := dynview_script_visual_padding(script_font_size)

    ascent := text_ascent
    descent := text_descent
    if sup_cols > 0 {
        ascent = max(ascent, script_ascent + sup_raise_px + script_top_pad)
    }
    if sub_cols > 0 {
        descent = max(descent, script_descent + sub_drop_px + script_bottom_pad)
    }

    bar_thickness := max(1.0, cmd.accent_thickness * font_size)
    has_scripts := sup_cols > 0 || sub_cols > 0
    accent_pad := dynview_accent_script_clearance(font_size, script_scale, has_scripts)
    bar_offset := max(0.0, cmd.accent_offset * font_size) + accent_pad
    bar_half := bar_thickness * 0.5
    content_ascent := ascent
    content_descent := descent
    if cmd.accent_mode == 1 {
        ascent = max(ascent, content_ascent + bar_offset + bar_half)
    } else {
        descent = max(descent, content_descent + bar_offset + bar_half)
    }

    base_advance := dynview_effective_advance(style, cache^.last_wrap_advance)
    script_advance := dynview_effective_advance(script_style, cache^.last_wrap_advance) * script_scale
    gap_px := max(1.0, cmd.script_gap * font_size)
    base_width := f32(base_cols) * base_advance
    script_width := f32(script_cols) * script_advance
    draw_width := base_width
    if script_cols > 0 {
        draw_width += gap_px + script_width
    }

    return core.Ui_Dynview_Layout_Item{
        kind = .AccentBar,
        style_id = cmd.style_id,
        text_offset = cmd.text_offset,
        text_len = cmd.text_len,
        script_sup_text_offset = cmd.script_sup_text_offset,
        script_sup_text_len = cmd.script_sup_text_len,
        script_sub_text_offset = cmd.script_sub_text_offset,
        script_sub_text_len = cmd.script_sub_text_len,
        script_style_id = cmd.script_style_id,
        script_scale = script_scale,
        script_sup_raise = cmd.script_sup_raise,
        script_sub_drop = cmd.script_sub_drop,
        script_gap = cmd.script_gap,
        accent_mode = cmd.accent_mode,
        accent_style_id = cmd.accent_style_id,
        accent_thickness = cmd.accent_thickness,
        accent_offset = cmd.accent_offset,
        draw_width = draw_width,
        draw_height = ascent + descent,
        ascent = ascent,
        descent = descent,
        visual_padding_top = max(script_top_pad, accent_pad),
        visual_padding_bottom = max(script_bottom_pad, accent_pad),
    }
}

//   Build one layout-like item for a recursive accent wrapper around a child math program.
dynview_math_program_recursive_accent_item :: #force_inline proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    buffer: ^core.Ui_Dynview_Command_Buffer,
    cmd: core.Ui_Dynview_Command,
    font_size: f32) -> (core.Ui_Dynview_Layout_Item, bool) {

    child_program, ok := dynview_math_program_from_id(cache, cmd.math_program_id)
    if !ok || !dynview_measure_math_program(cache, buffer, child_program, font_size) {
        return core.Ui_Dynview_Layout_Item{}, false
    }

    bar_thickness := max(1.0, cmd.accent_thickness * font_size)
    bar_offset := max(0.0, cmd.accent_offset * font_size)
    bar_half := bar_thickness * 0.5
    ascent := child_program^.ascent
    descent := child_program^.descent
    if cmd.accent_mode == 1 {
        ascent = max(ascent, child_program^.ascent + bar_offset + bar_half)
    } else {
        descent = max(descent, child_program^.descent + bar_offset + bar_half)
    }

    return core.Ui_Dynview_Layout_Item{
        kind = .AccentBarRecursive,
        style_id = cmd.style_id,
        math_program_id = cmd.math_program_id,
        accent_mode = cmd.accent_mode,
        accent_style_id = cmd.accent_style_id,
        accent_thickness = cmd.accent_thickness,
        accent_offset = cmd.accent_offset,
        draw_width = child_program^.draw_width,
        draw_height = ascent + descent,
        ascent = ascent,
        descent = descent,
        visual_padding_top = max(child_program^.visual_padding_top, bar_half),
        visual_padding_bottom = max(child_program^.visual_padding_bottom, bar_half),
    }, true
}

//   Build one layout-like item for a recursive radical wrapper around a child math program.
dynview_math_program_recursive_radical_item :: #force_inline proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    buffer: ^core.Ui_Dynview_Command_Buffer,
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> (core.Ui_Dynview_Layout_Item, bool) {

    child_program, ok := dynview_math_program_from_id(cache, cmd.math_program_id)
    if !ok || !dynview_measure_math_program(cache, buffer, child_program, font_size) {
        return core.Ui_Dynview_Layout_Item{}, false
    }

    index_text := dynview_text_span_from_buffer(
        buffer,
        cmd.radical_index_text_offset,
        cmd.radical_index_text_len)
    index_cols := text_codepoint_count(index_text)

    script_style := dynview_style_by_id(cmd.script_style_id)
    script_scale := max(0.2, cmd.script_scale)
    script_font_size, _, _ := dynview_script_draw_offsets(
        font_size,
        script_scale,
        cmd.script_sup_raise,
        cmd.script_sub_drop)
    script_top_pad, script_bottom_pad := dynview_script_visual_padding(script_font_size)
    index_scale := max(0.2, script_scale)
    index_font_size := max(1.0, font_size * index_scale)
    index_ascent, index_descent := dynview_style_ascent_descent(script_style, index_font_size)

    content_ascent := child_program^.ascent
    content_descent := child_program^.descent
    bar_thickness := max(1.0, cmd.accent_thickness * font_size)
    bar_offset := max(0.0, cmd.accent_offset * font_size)
    ascent := max(content_ascent, content_ascent + bar_offset + bar_thickness * 0.5)
    if index_cols > 0 {
        index_top_from_baseline := content_ascent * 0.62 + index_ascent * 0.50
        ascent = max(ascent, index_top_from_baseline + script_top_pad)
    }
    descent := max(content_descent, font_size * 0.18)
    if index_cols > 0 {
        descent = max(descent, index_descent * 0.2)
    }

    base_advance := dynview_effective_advance(style, cache^.last_wrap_advance)
    index_advance := dynview_effective_advance(script_style, cache^.last_wrap_advance) * index_scale
    index_width := f32(index_cols) * index_advance
    lead_width := max(
        dynview_radical_lead_width(font_size, base_advance),
        index_width + max(1.0, base_advance * 1.05))
    front_padding, back_padding := dynview_radical_side_paddings(font_size, base_advance)
    draw_width := lead_width + child_program^.draw_width + front_padding + back_padding
    accent_pad := dynview_accent_script_clearance(font_size, script_scale, false)

    return core.Ui_Dynview_Layout_Item{
        kind = .RadicalBarRecursive,
        style_id = cmd.style_id,
        math_program_id = cmd.math_program_id,
        script_style_id = cmd.script_style_id,
        script_scale = script_scale,
        script_sup_raise = cmd.script_sup_raise,
        script_sub_drop = cmd.script_sub_drop,
        radical_mode = cmd.radical_mode,
        radical_index_text_offset = cmd.radical_index_text_offset,
        radical_index_text_len = cmd.radical_index_text_len,
        accent_style_id = cmd.accent_style_id,
        accent_thickness = cmd.accent_thickness,
        accent_offset = cmd.accent_offset,
        draw_width = draw_width,
        draw_height = ascent + descent,
        ascent = ascent,
        descent = descent,
        visual_padding_top = max(child_program^.visual_padding_top, max(script_top_pad, accent_pad)),
        visual_padding_bottom = max(child_program^.visual_padding_bottom, max(script_bottom_pad, accent_pad)),
    }, true
}

//   Build one layout-like item for a radical child command inside a math block.
dynview_math_program_radical_item :: #force_inline proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    buffer: ^core.Ui_Dynview_Command_Buffer,
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> core.Ui_Dynview_Layout_Item {

    base_text := dynview_text_for_command(buffer, cmd)
    sup_text := dynview_text_span_from_buffer(
        buffer,
        cmd.script_sup_text_offset,
        cmd.script_sup_text_len)
    sub_text := dynview_text_span_from_buffer(
        buffer,
        cmd.script_sub_text_offset,
        cmd.script_sub_text_len)
    index_text := dynview_text_span_from_buffer(
        buffer,
        cmd.radical_index_text_offset,
        cmd.radical_index_text_len)

    base_cols := max(1, text_codepoint_count(base_text))
    sup_cols := text_codepoint_count(sup_text)
    sub_cols := text_codepoint_count(sub_text)
    index_cols := text_codepoint_count(index_text)
    script_cols := max(sup_cols, sub_cols)

    text_ascent, text_descent := dynview_style_ascent_descent(style, font_size)
    script_style := dynview_style_by_id(cmd.script_style_id)
    script_scale := max(0.2, cmd.script_scale)
    script_font_size, sup_raise_px, sub_drop_px := dynview_script_draw_offsets(
        font_size,
        script_scale,
        cmd.script_sup_raise,
        cmd.script_sub_drop)
    script_ascent, script_descent := dynview_style_ascent_descent(script_style, script_font_size)
    script_top_pad, script_bottom_pad := dynview_script_visual_padding(script_font_size)
    index_scale := max(0.2, script_scale)
    index_font_size := max(1.0, font_size * index_scale)
    index_ascent, index_descent := dynview_style_ascent_descent(script_style, index_font_size)

    content_ascent := text_ascent
    content_descent := text_descent
    if sup_cols > 0 {
        content_ascent = max(content_ascent, script_ascent + sup_raise_px + script_top_pad)
    }
    if sub_cols > 0 {
        content_descent = max(content_descent, script_descent + sub_drop_px + script_bottom_pad)
    }

    bar_thickness := max(1.0, cmd.accent_thickness * font_size)
    bar_offset := max(0.0, cmd.accent_offset * font_size)
    ascent := max(content_ascent, content_ascent + bar_offset + bar_thickness * 0.5)
    if index_cols > 0 {
        index_top_from_baseline := content_ascent * 0.62 + index_ascent * 0.50
        ascent = max(ascent, index_top_from_baseline + script_top_pad)
    }
    descent := max(content_descent, font_size * 0.18)
    if index_cols > 0 {
        descent = max(descent, index_descent * 0.2)
    }

    base_advance := dynview_effective_advance(style, cache^.last_wrap_advance)
    script_advance := dynview_effective_advance(script_style, cache^.last_wrap_advance) * script_scale
    index_advance := dynview_effective_advance(script_style, cache^.last_wrap_advance) * index_scale
    gap_px := max(1.0, cmd.script_gap * font_size)
    base_width := f32(base_cols) * base_advance
    script_width := f32(script_cols) * script_advance
    index_width := f32(index_cols) * index_advance
    content_width := base_width
    if script_cols > 0 {
        content_width += gap_px + script_width
    }
    lead_width := max(
        dynview_radical_lead_width(font_size, base_advance),
        index_width + max(1.0, base_advance * 1.05))
    front_padding, back_padding := dynview_radical_side_paddings(font_size, base_advance)
    draw_width := lead_width + content_width + front_padding + back_padding
    accent_pad := dynview_accent_script_clearance(font_size, script_scale, sup_cols > 0 || sub_cols > 0)

    return core.Ui_Dynview_Layout_Item{
        kind = .RadicalBar,
        style_id = cmd.style_id,
        text_offset = cmd.text_offset,
        text_len = cmd.text_len,
        script_sup_text_offset = cmd.script_sup_text_offset,
        script_sup_text_len = cmd.script_sup_text_len,
        script_sub_text_offset = cmd.script_sub_text_offset,
        script_sub_text_len = cmd.script_sub_text_len,
        script_style_id = cmd.script_style_id,
        script_scale = script_scale,
        script_sup_raise = cmd.script_sup_raise,
        script_sub_drop = cmd.script_sub_drop,
        script_gap = cmd.script_gap,
        radical_mode = cmd.radical_mode,
        radical_index_text_offset = cmd.radical_index_text_offset,
        radical_index_text_len = cmd.radical_index_text_len,
        accent_style_id = cmd.accent_style_id,
        accent_thickness = cmd.accent_thickness,
        accent_offset = cmd.accent_offset,
        draw_width = draw_width,
        draw_height = ascent + descent,
        ascent = ascent,
        descent = descent,
        visual_padding_top = max(script_top_pad, accent_pad),
        visual_padding_bottom = max(script_bottom_pad, accent_pad),
    }
}

//   Build one layout-like child item for the command kinds supported inside math blocks.
dynview_math_program_item :: #force_inline proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    buffer: ^core.Ui_Dynview_Command_Buffer,
    cmd: core.Ui_Dynview_Command,
    font_size: f32) -> (core.Ui_Dynview_Layout_Item, bool) {

    style := dynview_style_by_id(cmd.style_id)
    switch cmd.kind {
    case .TextRun, .MathGlyphRun:
        return dynview_math_program_text_item(cache, buffer, cmd, style, font_size), true
    case .ScriptAttach:
        return dynview_math_program_script_item(cache, buffer, cmd, style, font_size), true
    case .ScriptAttachRecursive:
        return dynview_math_program_recursive_script_item(cache, buffer, cmd, font_size)
    case .AccentBar:
        return dynview_math_program_accent_item(cache, buffer, cmd, style, font_size), true
    case .AccentBarRecursive:
        return dynview_math_program_recursive_accent_item(cache, buffer, cmd, font_size)
    case .RadicalBar:
        return dynview_math_program_radical_item(cache, buffer, cmd, style, font_size), true
    case .RadicalBarRecursive:
        return dynview_math_program_recursive_radical_item(cache, buffer, cmd, style, font_size)
    case .MathBlock, .BeginBlock, .EndBlock, .CopyableTextRun, .LineBreak, .Divider,
        .InlineLine, .InlineBox, .InlineCircle, .InlineFilledBox, .InlineFilledCircle,
        .InlinePieSection:
    }

    return core.Ui_Dynview_Layout_Item{}, false
}

//   Draw one measured child math program with a shared baseline.
dynview_draw_math_program_at :: proc(
    state: ^core.Euclid_General_State,
    runtime: ^core.Ui_Dynview_Runtime,
    panel: rl.Rectangle,
    font: rl.Font,
    font_size: f32,
    program: core.Ui_Dynview_Math_Program,
    draw_x, baseline_y: f32) {

    child_x := draw_x
    command_end := program.command_start + program.command_count
    for command_index in program.command_start..<command_end {
        cmd := runtime^.compile_cache.math_commands[command_index]
        child_item, ok := dynview_math_program_item(
            &runtime^.compile_cache,
            &runtime^.command_buffer,
            cmd,
            font_size)
        if !ok {
            continue
        }

        child_y := baseline_y - child_item.ascent
        child_style := dynview_style_by_id(child_item.style_id)
        dynview_draw_cached_text_item(
            state,
            runtime,
            panel,
            font,
            font_size,
            child_style,
            child_item,
            child_x,
            child_y)
        child_x += child_item.draw_width
    }
}

//   Measure one flat child-command math program and cache its deterministic outer metrics.
dynview_measure_math_program :: proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    buffer: ^core.Ui_Dynview_Command_Buffer,
    program: ^core.Ui_Dynview_Math_Program,
    font_size: f32) -> bool {

    if cache == nil || buffer == nil || program == nil || !program^.valid {
        return false
    }
    if program^.command_start < 0 || program^.command_count <= 0 {
        return false
    }
    if program^.command_start + program^.command_count > cache^.math_command_count {
        return false
    }

    total_width: f32 = 0
    max_ascent: f32 = 0
    max_descent: f32 = 0
    max_top_pad: f32 = 0
    max_bottom_pad: f32 = 0
    command_end := program^.command_start + program^.command_count
    for command_index in program^.command_start..<command_end {
        cmd := cache^.math_commands[command_index]
        item, ok := dynview_math_program_item(cache, buffer, cmd, font_size)
        if !ok {
            return false
        }

        total_width += item.draw_width
        max_ascent = max(max_ascent, item.ascent)
        max_descent = max(max_descent, item.descent)
        max_top_pad = max(max_top_pad, item.visual_padding_top)
        max_bottom_pad = max(max_bottom_pad, item.visual_padding_bottom)
    }

    program^.draw_width = total_width
    program^.ascent = max(1.0, max_ascent)
    program^.descent = max(1.0, max_descent)
    program^.visual_padding_top = max_top_pad
    program^.visual_padding_bottom = max_bottom_pad
    return true
}

//   Start a new line accumulator seeded from base text metrics.
dynview_layout_seed_line_accumulator :: #force_inline proc(
    acc: ^Dynview_Layout_Line_Accumulator,
    item_start: int,
    base_ascent, base_descent: f32) {

    acc^.item_start = item_start
    acc^.item_count = 0
    acc^.max_ascent = base_ascent
    acc^.max_descent = base_descent
}

//   Return wrapped column capacity for one style in active panel.
dynview_layout_max_cols :: #force_inline proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    style: Dynview_Text_Style) -> int {

    max_cols := dynview_chars_per_row_for_style(
        cache^.last_panel_width,
        TEXT_PADDING,
        cache^.last_wrap_advance,
        style)
    return max(1, max_cols)
}

//   Enforce style-level line-start behavior before placing content.
dynview_layout_prepare_style_placement :: #force_inline proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    style: Dynview_Text_Style,
    font_size: f32) -> i32 {

    if style.force_line_start && state^.col > 0 {
        ascent, descent := dynview_style_ascent_descent(style, font_size)
        status := dynview_layout_finalize_line(cache, state, acc, ascent, descent)
        if status != DYNVIEW_STATUS_OK {
            return status
        }
    }

    if state^.col == 0 && style.indent_cols > 0 {
        state^.col = style.indent_cols
    }

    return DYNVIEW_STATUS_OK
}

//   Reserve a new layout item slot and append a prepared item.
dynview_layout_push_item :: proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    item: core.Ui_Dynview_Layout_Item) -> i32 {

    if cache^.layout_item_count >= len(cache^.layout_items) {
        return DYNVIEW_STATUS_OUT_OF_CAPACITY
    }

    item_slot := &cache^.layout_items[cache^.layout_item_count]
    item_slot^ = item
    item_slot^.block_id = state^.active_block_id
    item_slot^.line_index = state^.line_index
    item_slot^.col_start = state^.col
    item_slot^.x_offset = f32(state^.col) * dynview_effective_advance(
        dynview_style_by_id(item.style_id),
        cache^.last_wrap_advance)

    cache^.layout_item_count += 1
    state^.col += max(1, item.col_span)
    acc^.item_count += 1
    acc^.max_ascent = max(acc^.max_ascent, item.ascent)
    acc^.max_descent = max(acc^.max_descent, item.descent)
    return DYNVIEW_STATUS_OK
}

//   Apply per-item vertical offsets from finalized baseline metrics.
dynview_layout_apply_item_offsets :: proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    start_index, item_count: int,
    line_height: f32) {

    item_end := start_index + item_count
    for item_index in start_index..<item_end {
        item := &cache^.layout_items[item_index]
        item^.y_offset = (line_height - item^.draw_height) * 0.5
    }
}

//   Advance state after one line finalization.
dynview_layout_advance_after_line :: #force_inline proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    line_height, base_ascent, base_descent: f32) {

    cache^.layout_line_count += 1
    state^.line_index += 1
    state^.col = 0
    state^.y_offset += line_height + state^.line_gap
    dynview_layout_seed_line_accumulator(acc, cache^.layout_item_count, base_ascent, base_descent)
}

//   Finalize one layout line and compute y-offsets from per-item ascent/descent.
dynview_layout_finalize_line :: proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    base_ascent, base_descent: f32) -> i32 {

    if state^.line_index >= len(cache^.layout_lines) {
        return DYNVIEW_STATUS_OUT_OF_CAPACITY
    }

    line_height := max(1.0, acc^.max_ascent + acc^.max_descent)
    line := &cache^.layout_lines[state^.line_index]
    line^.item_start = acc^.item_start
    line^.item_count = acc^.item_count
    line^.y_offset = state^.y_offset
    line^.line_height = line_height
    line^.baseline = acc^.max_ascent
    line^.max_ascent = acc^.max_ascent
    line^.max_descent = acc^.max_descent

    dynview_layout_apply_item_offsets(cache, line^.item_start, line^.item_count, line^.line_height)
    dynview_layout_advance_after_line(cache, state, acc, line_height, base_ascent, base_descent)
    return DYNVIEW_STATUS_OK
}

//   Finalize current line when wrapping a multi-line item is required.
dynview_layout_finalize_for_wrap :: #force_inline proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    ascent, descent: f32) -> i32 {

    if state^.col < 0 {
        return DYNVIEW_STATUS_ILLEGAL_STATE
    }

    return dynview_layout_finalize_line(cache, state, acc, ascent, descent)
}

//   Build a text-run layout item for one wrapped line segment.
dynview_text_run_item :: #force_inline proc(
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style,
    wrap_advance: f32,
    line_start, line_byte_len, line_col_span: int,
    ascent, descent: f32) -> core.Ui_Dynview_Layout_Item {

    return core.Ui_Dynview_Layout_Item{
        kind = .TextRun,
        style_id = cmd.style_id,
        col_span = line_col_span,
        text_offset = cmd.text_offset + line_start,
        text_len = line_byte_len,
        draw_height = ascent + descent,
        ascent = ascent,
        descent = descent,
    }
}

//   Consume one wrapped text segment and optionally force a line break.
dynview_layout_push_wrapped_text_segment :: proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style,
    line_start, line_byte_len, line_col_span: int,
    should_break: bool,
    ascent, descent: f32) -> i32 {

    item := dynview_text_run_item(
        cmd,
        style,
        cache^.last_wrap_advance,
        line_start,
        line_byte_len,
        line_col_span,
        ascent,
        descent)

    status := dynview_layout_push_item(cache, state, acc, item)
    if status != DYNVIEW_STATUS_OK {
        return status
    }

    if should_break {
        return dynview_layout_finalize_for_wrap(cache, state, acc, ascent, descent)
    }

    return DYNVIEW_STATUS_OK
}

//   Lay out one wrapped text command and return the last line touched.
dynview_layout_consume_text_run :: proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    cmd: core.Ui_Dynview_Command,
    text: string,
    style: Dynview_Text_Style,
    font_size: f32) -> (i32, int) {

    if len(text) <= 0 {
        return DYNVIEW_STATUS_OK, -1
    }

    placement_status := dynview_layout_prepare_style_placement(
        cache,
        state,
        acc,
        style,
        font_size)
    if placement_status != DYNVIEW_STATUS_OK {
        return placement_status, -1
    }

    max_cols := dynview_layout_max_cols(cache, style)
    ascent, descent := dynview_style_ascent_descent(style, font_size)
    last_line := -1
    start := 0
    for start < len(text) {
        if state^.col >= max_cols {
            status := dynview_layout_finalize_for_wrap(cache, state, acc, ascent, descent)
            if status != DYNVIEW_STATUS_OK {
                return status, last_line
            }
        }

        available := max_cols - state^.col
        if available <= 0 {
            status := dynview_layout_finalize_for_wrap(cache, state, acc, ascent, descent)
            if status != DYNVIEW_STATUS_OK {
                return status, last_line
            }
            continue
        }

        line_start, line_end, next_start := next_wrapped_text_span(text, start, available)
        line_col_span := text_codepoint_count_span(text, line_start, line_end)
        line_byte_len := line_end - line_start
        if line_col_span <= 0 || line_byte_len <= 0 {
            break
        }

        status := dynview_layout_push_wrapped_text_segment(
            cache,
            state,
            acc,
            cmd,
            style,
            line_start,
            line_byte_len,
            line_col_span,
            next_start < len(text),
            ascent,
            descent)
        if status != DYNVIEW_STATUS_OK {
            return status, last_line
        }

        last_line = state^.line_index
        if next_start <= start {
            break
        }

        start = next_start
        if next_start < len(text) {
            last_line = state^.line_index - 1
        }
    }

    return DYNVIEW_STATUS_OK, last_line
}

//   Lay out one premeasured recursive math block as an atomic non-wrapping inline item.
dynview_layout_consume_math_block :: proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    buffer: ^core.Ui_Dynview_Command_Buffer,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> (i32, int) {

    placement_status := dynview_layout_prepare_style_placement(
        cache,
        state,
        acc,
        style,
        font_size)
    if placement_status != DYNVIEW_STATUS_OK {
        return placement_status, -1
    }

    program, ok := dynview_math_program_from_command(cache, cmd)
    if !ok {
        return DYNVIEW_STATUS_INVALID_ARGUMENT, -1
    }
    if !dynview_measure_math_program(cache, buffer, program, font_size) {
        return DYNVIEW_STATUS_INVALID_ARGUMENT, -1
    }

    max_cols := dynview_layout_max_cols(cache, style)
    text_ascent, text_descent := dynview_style_ascent_descent(style, font_size)
    cols := 1
    base_advance := dynview_effective_advance(style, cache^.last_wrap_advance)
    if base_advance > 0 {
        cols = max(cols, int(program^.draw_width / base_advance))
        if f32(cols) * base_advance < program^.draw_width {
            cols += 1
        }
    }
    cols = min(max_cols, max(1, cols))

    status := dynview_layout_wrap_before_inline(
        cache,
        state,
        acc,
        max_cols,
        cols,
        text_ascent,
        text_descent)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    item := core.Ui_Dynview_Layout_Item{
        kind = .MathBlock,
        style_id = cmd.style_id,
        math_program_id = cmd.math_program_id,
        col_span = cols,
        draw_width = program^.draw_width,
        draw_height = program^.ascent + program^.descent,
        ascent = program^.ascent,
        descent = program^.descent,
        visual_padding_top = program^.visual_padding_top,
        visual_padding_bottom = program^.visual_padding_bottom,
    }

    status = dynview_layout_push_item(cache, state, acc, item)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    return dynview_layout_finalize_after_inline_if_full(
        cache,
        state,
        acc,
        max_cols,
        text_ascent,
        text_descent)
}

//   Lay out one script-attach command as a single inline atom with stacked script metrics.
dynview_layout_consume_script_attach :: proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    buffer: ^core.Ui_Dynview_Command_Buffer,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> (i32, int) {

    placement_status := dynview_layout_prepare_style_placement(
        cache,
        state,
        acc,
        style,
        font_size)
    if placement_status != DYNVIEW_STATUS_OK {
        return placement_status, -1
    }

    base_text := dynview_text_span_from_buffer(
        buffer,
        cmd.script_base_text_offset,
        cmd.script_base_text_len)
    sup_text := dynview_text_span_from_buffer(
        buffer,
        cmd.script_sup_text_offset,
        cmd.script_sup_text_len)
    sub_text := dynview_text_span_from_buffer(
        buffer,
        cmd.script_sub_text_offset,
        cmd.script_sub_text_len)

    base_cols := max(1, text_codepoint_count(base_text))
    sup_cols := text_codepoint_count(sup_text)
    sub_cols := text_codepoint_count(sub_text)
    script_cols := max(sup_cols, sub_cols)

    max_cols := dynview_layout_max_cols(cache, style)
    cols := base_cols + script_cols
    if cols <= 0 {
        cols = 1
    }

    text_ascent, text_descent := dynview_style_ascent_descent(style, font_size)
    status := dynview_layout_wrap_before_inline(
        cache,
        state,
        acc,
        max_cols,
        cols,
        text_ascent,
        text_descent)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    script_style := dynview_style_by_id(cmd.script_style_id)
    script_scale := max(0.2, cmd.script_scale)
    script_font_size, sup_raise_px, sub_drop_px := dynview_script_draw_offsets(
        font_size,
        script_scale,
        cmd.script_sup_raise,
        cmd.script_sub_drop)
    script_ascent, script_descent := dynview_style_ascent_descent(script_style, script_font_size)
    script_top_pad, script_bottom_pad := dynview_script_visual_padding(script_font_size)
    ascent := text_ascent
    descent := text_descent
    if sup_cols > 0 {
        ascent = max(ascent, script_ascent + sup_raise_px + script_top_pad)
    }
    if sub_cols > 0 {
        descent = max(descent, script_descent + sub_drop_px + script_bottom_pad)
    }

    base_advance := dynview_effective_advance(style, cache^.last_wrap_advance)
    script_advance := dynview_effective_advance(script_style, cache^.last_wrap_advance) * script_scale
    gap_px := max(1.0, cmd.script_gap * font_size)
    base_width := f32(base_cols) * base_advance
    script_width := f32(script_cols) * script_advance
    draw_width := base_width
    if script_cols > 0 {
        draw_width += gap_px + script_width
    }

    item := core.Ui_Dynview_Layout_Item{
        kind = .ScriptAttach,
        style_id = cmd.style_id,
        col_span = cols,
        text_offset = cmd.script_base_text_offset,
        text_len = cmd.script_base_text_len,
        script_sup_text_offset = cmd.script_sup_text_offset,
        script_sup_text_len = cmd.script_sup_text_len,
        script_sub_text_offset = cmd.script_sub_text_offset,
        script_sub_text_len = cmd.script_sub_text_len,
        script_style_id = cmd.script_style_id,
        script_scale = script_scale,
        script_sup_raise = cmd.script_sup_raise,
        script_sub_drop = cmd.script_sub_drop,
        script_gap = cmd.script_gap,
        draw_width = draw_width,
        draw_height = ascent + descent,
        ascent = ascent,
        descent = descent,
    }

    status = dynview_layout_push_item(cache, state, acc, item)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    return dynview_layout_finalize_after_inline_if_full(
        cache,
        state,
        acc,
        max_cols,
        text_ascent,
        text_descent)
}

//   Lay out one accent-bar command as an atomic text span with over/underline metrics.
dynview_layout_consume_accent_bar :: proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    buffer: ^core.Ui_Dynview_Command_Buffer,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> (i32, int) {

    base_text := dynview_text_for_command(buffer, cmd)
    if len(base_text) <= 0 {
        return DYNVIEW_STATUS_OK, -1
    }

    sup_text := dynview_text_span_from_buffer(
        buffer,
        cmd.script_sup_text_offset,
        cmd.script_sup_text_len)
    sub_text := dynview_text_span_from_buffer(
        buffer,
        cmd.script_sub_text_offset,
        cmd.script_sub_text_len)

    placement_status := dynview_layout_prepare_style_placement(
        cache,
        state,
        acc,
        style,
        font_size)
    if placement_status != DYNVIEW_STATUS_OK {
        return placement_status, -1
    }

    base_cols := max(1, text_codepoint_count(base_text))
    sup_cols := text_codepoint_count(sup_text)
    sub_cols := text_codepoint_count(sub_text)
    script_cols := max(sup_cols, sub_cols)
    cols := base_cols + script_cols
    if cols <= 0 {
        cols = 1
    }
    max_cols := dynview_layout_max_cols(cache, style)
    text_ascent, text_descent := dynview_style_ascent_descent(style, font_size)
    status := dynview_layout_wrap_before_inline(
        cache,
        state,
        acc,
        max_cols,
        cols,
        text_ascent,
        text_descent)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    script_style := dynview_style_by_id(cmd.script_style_id)
    script_scale := max(0.2, cmd.script_scale)
    script_font_size, sup_raise_px, sub_drop_px := dynview_script_draw_offsets(
        font_size,
        script_scale,
        cmd.script_sup_raise,
        cmd.script_sub_drop)
    script_ascent, script_descent := dynview_style_ascent_descent(script_style, script_font_size)
    script_top_pad, script_bottom_pad := dynview_script_visual_padding(script_font_size)

    ascent := text_ascent
    descent := text_descent
    if sup_cols > 0 {
        ascent = max(ascent, script_ascent + sup_raise_px + script_top_pad)
    }
    if sub_cols > 0 {
        descent = max(descent, script_descent + sub_drop_px + script_bottom_pad)
    }

    bar_thickness := max(1.0, cmd.accent_thickness * font_size)
    has_scripts := sup_cols > 0 || sub_cols > 0
    bar_offset := max(0.0, cmd.accent_offset * font_size) +
        dynview_accent_script_clearance(font_size, script_scale, has_scripts)
    bar_half := bar_thickness * 0.5
    content_ascent := ascent
    content_descent := descent
    if cmd.accent_mode == 1 {
        ascent = max(ascent, content_ascent + bar_offset + bar_half)
    } else {
        descent = max(descent, content_descent + bar_offset + bar_half)
    }

    base_advance := dynview_effective_advance(style, cache^.last_wrap_advance)
    script_advance := dynview_effective_advance(script_style, cache^.last_wrap_advance) * script_scale
    gap_px := max(1.0, cmd.script_gap * font_size)
    base_width := f32(base_cols) * base_advance
    script_width := f32(script_cols) * script_advance
    draw_width := base_width
    if script_cols > 0 {
        draw_width += gap_px + script_width
    }

    item := core.Ui_Dynview_Layout_Item{
        kind = .AccentBar,
        style_id = cmd.style_id,
        col_span = cols,
        text_offset = cmd.text_offset,
        text_len = cmd.text_len,
        script_sup_text_offset = cmd.script_sup_text_offset,
        script_sup_text_len = cmd.script_sup_text_len,
        script_sub_text_offset = cmd.script_sub_text_offset,
        script_sub_text_len = cmd.script_sub_text_len,
        script_style_id = cmd.script_style_id,
        script_scale = script_scale,
        script_sup_raise = cmd.script_sup_raise,
        script_sub_drop = cmd.script_sub_drop,
        script_gap = cmd.script_gap,
        accent_mode = cmd.accent_mode,
        accent_style_id = cmd.accent_style_id,
        accent_thickness = cmd.accent_thickness,
        accent_offset = cmd.accent_offset,
        draw_width = draw_width,
        draw_height = ascent + descent,
        ascent = ascent,
        descent = descent,
    }

    status = dynview_layout_push_item(cache, state, acc, item)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    return dynview_layout_finalize_after_inline_if_full(
        cache,
        state,
        acc,
        max_cols,
        text_ascent,
        text_descent)
}

//   Lay out one radical-bar command as an atomic text span with square-root metrics.
dynview_layout_consume_radical_bar :: proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    buffer: ^core.Ui_Dynview_Command_Buffer,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> (i32, int) {

    base_text := dynview_text_for_command(buffer, cmd)
    if len(base_text) <= 0 {
        return DYNVIEW_STATUS_OK, -1
    }

    sup_text := dynview_text_span_from_buffer(
        buffer,
        cmd.script_sup_text_offset,
        cmd.script_sup_text_len)
    sub_text := dynview_text_span_from_buffer(
        buffer,
        cmd.script_sub_text_offset,
        cmd.script_sub_text_len)
    index_text := dynview_text_span_from_buffer(
        buffer,
        cmd.radical_index_text_offset,
        cmd.radical_index_text_len)

    placement_status := dynview_layout_prepare_style_placement(
        cache,
        state,
        acc,
        style,
        font_size)
    if placement_status != DYNVIEW_STATUS_OK {
        return placement_status, -1
    }

    base_cols := max(1, text_codepoint_count(base_text))
    sup_cols := text_codepoint_count(sup_text)
    sub_cols := text_codepoint_count(sub_text)
    index_cols := text_codepoint_count(index_text)
    script_cols := max(sup_cols, sub_cols)
    cols := base_cols + script_cols + max(1, index_cols)
    if cols <= 0 {
        cols = 1
    }

    max_cols := dynview_layout_max_cols(cache, style)
    text_ascent, text_descent := dynview_style_ascent_descent(style, font_size)

    script_style := dynview_style_by_id(cmd.script_style_id)
    script_scale := max(0.2, cmd.script_scale)
    script_font_size, sup_raise_px, sub_drop_px := dynview_script_draw_offsets(
        font_size,
        script_scale,
        cmd.script_sup_raise,
        cmd.script_sub_drop)
    script_ascent, script_descent := dynview_style_ascent_descent(script_style, script_font_size)
    script_top_pad, script_bottom_pad := dynview_script_visual_padding(script_font_size)
    index_scale := max(0.2, script_scale)
    index_font_size := max(1.0, font_size * index_scale)
    index_ascent, index_descent := dynview_style_ascent_descent(script_style, index_font_size)

    content_ascent := text_ascent
    content_descent := text_descent
    if sup_cols > 0 {
        content_ascent = max(content_ascent, script_ascent + sup_raise_px + script_top_pad)
    }
    if sub_cols > 0 {
        content_descent = max(content_descent, script_descent + sub_drop_px + script_bottom_pad)
    }

    bar_thickness := max(1.0, cmd.accent_thickness * font_size)
    bar_offset := max(0.0, cmd.accent_offset * font_size)
    ascent := max(content_ascent, content_ascent + bar_offset + bar_thickness * 0.5)
    if index_cols > 0 {
        // Keep index visible before the radical sign with explicit top clearance.
        index_top_from_baseline := content_ascent * 0.62 + index_ascent * 0.50
        ascent = max(ascent, index_top_from_baseline + script_top_pad)
    }
    root_descent := max(content_descent, font_size * 0.18)
    descent := root_descent
    if index_cols > 0 {
        descent = max(descent, index_descent * 0.2)
    }

    base_advance := dynview_effective_advance(style, cache^.last_wrap_advance)
    script_advance := dynview_effective_advance(script_style, cache^.last_wrap_advance) * script_scale
    index_advance := dynview_effective_advance(script_style, cache^.last_wrap_advance) * index_scale
    gap_px := max(1.0, cmd.script_gap * font_size)
    base_width := f32(base_cols) * base_advance
    script_width := f32(script_cols) * script_advance
    index_width := f32(index_cols) * index_advance
    content_width := base_width
    if script_cols > 0 {
        content_width += gap_px + script_width
    }
    lead_width := max(
        dynview_radical_lead_width(font_size, base_advance),
        index_width + max(1.0, base_advance * 1.05))
    front_padding, back_padding := dynview_radical_side_paddings(font_size, base_advance)
    draw_width := lead_width + content_width + front_padding + back_padding

    required_cols := cols
    if base_advance > 0 {
        required_cols = max(required_cols, int(draw_width / base_advance))
        if f32(required_cols) * base_advance < draw_width {
            required_cols += 1
        }
    }
    cols = min(max_cols, max(1, required_cols))

    status := dynview_layout_wrap_before_inline(
        cache,
        state,
        acc,
        max_cols,
        cols,
        text_ascent,
        text_descent)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    item := core.Ui_Dynview_Layout_Item{
        kind = .RadicalBar,
        style_id = cmd.style_id,
        col_span = cols,
        text_offset = cmd.text_offset,
        text_len = cmd.text_len,
        script_sup_text_offset = cmd.script_sup_text_offset,
        script_sup_text_len = cmd.script_sup_text_len,
        script_sub_text_offset = cmd.script_sub_text_offset,
        script_sub_text_len = cmd.script_sub_text_len,
        script_style_id = cmd.script_style_id,
        script_scale = script_scale,
        script_sup_raise = cmd.script_sup_raise,
        script_sub_drop = cmd.script_sub_drop,
        script_gap = cmd.script_gap,
        radical_mode = cmd.radical_mode,
        radical_index_text_offset = cmd.radical_index_text_offset,
        radical_index_text_len = cmd.radical_index_text_len,
        accent_style_id = cmd.accent_style_id,
        accent_thickness = cmd.accent_thickness,
        accent_offset = cmd.accent_offset,
        draw_width = draw_width,
        draw_height = ascent + descent,
        ascent = ascent,
        descent = descent,
    }

    status = dynview_layout_push_item(cache, state, acc, item)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    return dynview_layout_finalize_after_inline_if_full(
        cache,
        state,
        acc,
        max_cols,
        text_ascent,
        text_descent)
}

//   Compute line-style inline stroke metrics centered on baseline zone.
dynview_inline_line_metrics :: #force_inline proc(
    thickness, text_ascent, text_descent: f32) -> (f32, f32, f32) {

    center := (text_descent - text_ascent) * 0.5
    top := center - thickness * 0.5
    bottom := center + thickness * 0.5
    ascent := max(0.0, -top)
    descent := max(0.0, bottom)
    return ascent, descent, thickness
}

//   Finalize line before placing one inline item if current row overflows.
dynview_layout_wrap_before_inline :: #force_inline proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    max_cols, cols: int,
    text_ascent, text_descent: f32) -> i32 {

    if state^.col <= 0 || state^.col + cols <= max_cols {
        return DYNVIEW_STATUS_OK
    }

    return dynview_layout_finalize_line(cache, state, acc, text_ascent, text_descent)
}

//   Finalize line after placing one inline item when row reaches capacity.
dynview_layout_finalize_after_inline_if_full :: #force_inline proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    max_cols: int,
    text_ascent, text_descent: f32) -> (i32, int) {

    if state^.col < max_cols {
        return DYNVIEW_STATUS_OK, state^.line_index
    }

    status := dynview_layout_finalize_line(cache, state, acc, text_ascent, text_descent)
    if status != DYNVIEW_STATUS_OK {
        return status, state^.line_index - 1
    }

    return DYNVIEW_STATUS_OK, state^.line_index - 1
}

//   Lay out one inline-line command and return the line touched.
dynview_layout_consume_inline_line :: proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> (i32, int) {

    placement_status := dynview_layout_prepare_style_placement(
        cache,
        state,
        acc,
        style,
        font_size)
    if placement_status != DYNVIEW_STATUS_OK {
        return placement_status, -1
    }

    max_cols := dynview_layout_max_cols(cache, style)
    cols := dynview_inline_line_cols(cmd, style, cache^.last_wrap_advance, max_cols)
    text_ascent, text_descent := dynview_style_ascent_descent(style, font_size)

    status := dynview_layout_wrap_before_inline(
        cache,
        state,
        acc,
        max_cols,
        cols,
        text_ascent,
        text_descent)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    thickness := max(1.0, cmd.inline_atom_stroke)
    ascent, descent, draw_height := dynview_inline_line_metrics(thickness, text_ascent, text_descent)
    item := core.Ui_Dynview_Layout_Item{
        kind = .InlineLine,
        style_id = cmd.style_id,
        col_span = cols,
        inline_atom_dimension = cmd.inline_atom_dimension,
        inline_atom_stroke = thickness,
        has_brush_color = cmd.has_brush_color,
        brush_color = cmd.brush_color,
        draw_width = f32(cols) * dynview_effective_advance(style, cache^.last_wrap_advance),
        draw_height = draw_height,
        ascent = max(ascent, text_ascent * 0.08),
        descent = max(descent, text_descent * 0.08),
    }

    status = dynview_layout_push_item(cache, state, acc, item)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    return dynview_layout_finalize_after_inline_if_full(
        cache,
        state,
        acc,
        max_cols,
        text_ascent,
        text_descent)
}

//   Build a box inline item anchored around the text baseline zone.
dynview_inline_box_item :: #force_inline proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style,
    cols: int,
    text_ascent, text_descent: f32) -> core.Ui_Dynview_Layout_Item {

    effective_advance := dynview_effective_advance(style, cache^.last_wrap_advance)
    content_height := text_ascent + text_descent
    requested := cmd.inline_box_height * effective_advance
    box_height := max(2.0, min(content_height, requested))
    center := (text_descent - text_ascent) * 0.5

    return core.Ui_Dynview_Layout_Item{
        kind = .InlineBox,
        style_id = cmd.style_id,
        col_span = cols,
        inline_atom_dimension = cmd.inline_atom_dimension,
        inline_atom_stroke = max(1.0, cmd.inline_atom_stroke),
        inline_box_height = box_height,
        has_brush_color = cmd.has_brush_color,
        brush_color = cmd.brush_color,
        inline_outline_stroke = cmd.inline_outline_stroke,
        pie_start_angle_degrees = cmd.pie_start_angle_degrees,
        pie_end_angle_degrees = cmd.pie_end_angle_degrees,
        draw_width = f32(cols) * effective_advance,
        draw_height = box_height,
        ascent = max(0.0, -(center - box_height * 0.5)),
        descent = max(0.0, center + box_height * 0.5),
    }
}

//   Lay out one inline-box command and return the line touched.
dynview_layout_consume_inline_box :: proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> (i32, int) {

    placement_status := dynview_layout_prepare_style_placement(
        cache,
        state,
        acc,
        style,
        font_size)
    if placement_status != DYNVIEW_STATUS_OK {
        return placement_status, -1
    }

    max_cols := dynview_layout_max_cols(cache, style)
    cols := dynview_inline_box_cols(cmd, style, max_cols)
    text_ascent, text_descent := dynview_style_ascent_descent(style, font_size)

    status := dynview_layout_wrap_before_inline(
        cache,
        state,
        acc,
        max_cols,
        cols,
        text_ascent,
        text_descent)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    item := dynview_inline_box_item(cache, cmd, style, cols, text_ascent, text_descent)
    status = dynview_layout_push_item(cache, state, acc, item)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    return dynview_layout_finalize_after_inline_if_full(
        cache,
        state,
        acc,
        max_cols,
        text_ascent,
        text_descent)
}

//   Build a circle inline item centered in the text baseline zone.
dynview_inline_circle_item :: #force_inline proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style,
    cols: int,
    text_ascent, text_descent: f32) -> core.Ui_Dynview_Layout_Item {

    effective_advance := dynview_effective_advance(style, cache^.last_wrap_advance)
    atom_width := f32(cols) * effective_advance
    radius := max(2.0, min(atom_width * 0.5, (text_ascent + text_descent) * 0.5))
    center := (text_descent - text_ascent) * 0.5

    return core.Ui_Dynview_Layout_Item{
        kind = .InlineCircle,
        style_id = cmd.style_id,
        col_span = cols,
        inline_atom_dimension = cmd.inline_atom_dimension,
        inline_atom_stroke = max(1.0, cmd.inline_atom_stroke),
        has_brush_color = cmd.has_brush_color,
        brush_color = cmd.brush_color,
        inline_outline_stroke = cmd.inline_outline_stroke,
        pie_start_angle_degrees = cmd.pie_start_angle_degrees,
        pie_end_angle_degrees = cmd.pie_end_angle_degrees,
        draw_width = atom_width,
        draw_height = radius * 2,
        ascent = max(0.0, -(center - radius)),
        descent = max(0.0, center + radius),
    }
}

//   Lay out one inline-circle command and return the line touched.
dynview_layout_consume_inline_circle :: proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> (i32, int) {

    placement_status := dynview_layout_prepare_style_placement(
        cache,
        state,
        acc,
        style,
        font_size)
    if placement_status != DYNVIEW_STATUS_OK {
        return placement_status, -1
    }

    max_cols := dynview_layout_max_cols(cache, style)
    cols := dynview_inline_circle_cols(cmd, style, max_cols)
    text_ascent, text_descent := dynview_style_ascent_descent(style, font_size)

    status := dynview_layout_wrap_before_inline(
        cache,
        state,
        acc,
        max_cols,
        cols,
        text_ascent,
        text_descent)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    item := dynview_inline_circle_item(cache, cmd, style, cols, text_ascent, text_descent)
    status = dynview_layout_push_item(cache, state, acc, item)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    return dynview_layout_finalize_after_inline_if_full(
        cache,
        state,
        acc,
        max_cols,
        text_ascent,
        text_descent)
}

//   Build a filled-box inline item using the same geometry as outline boxes.
dynview_inline_filled_box_item :: #force_inline proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style,
    cols: int,
    text_ascent, text_descent: f32) -> core.Ui_Dynview_Layout_Item {

    item := dynview_inline_box_item(cache, cmd, style, cols, text_ascent, text_descent)
    item.kind = .InlineFilledBox
    return item
}

//   Lay out one inline-filled-box command and return the line touched.
dynview_layout_consume_inline_filled_box :: proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> (i32, int) {

    placement_status := dynview_layout_prepare_style_placement(
        cache,
        state,
        acc,
        style,
        font_size)
    if placement_status != DYNVIEW_STATUS_OK {
        return placement_status, -1
    }

    max_cols := dynview_layout_max_cols(cache, style)
    cols := dynview_inline_box_cols(cmd, style, max_cols)
    text_ascent, text_descent := dynview_style_ascent_descent(style, font_size)

    status := dynview_layout_wrap_before_inline(
        cache,
        state,
        acc,
        max_cols,
        cols,
        text_ascent,
        text_descent)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    item := dynview_inline_filled_box_item(cache, cmd, style, cols, text_ascent, text_descent)
    status = dynview_layout_push_item(cache, state, acc, item)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    return dynview_layout_finalize_after_inline_if_full(
        cache,
        state,
        acc,
        max_cols,
        text_ascent,
        text_descent)
}

//   Build a filled-circle inline item using the same geometry as outline circles.
dynview_inline_filled_circle_item :: #force_inline proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style,
    cols: int,
    text_ascent, text_descent: f32) -> core.Ui_Dynview_Layout_Item {

    item := dynview_inline_circle_item(cache, cmd, style, cols, text_ascent, text_descent)
    item.kind = .InlineFilledCircle
    return item
}

//   Lay out one inline-filled-circle command and return the line touched.
dynview_layout_consume_inline_filled_circle :: proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> (i32, int) {

    placement_status := dynview_layout_prepare_style_placement(
        cache,
        state,
        acc,
        style,
        font_size)
    if placement_status != DYNVIEW_STATUS_OK {
        return placement_status, -1
    }

    max_cols := dynview_layout_max_cols(cache, style)
    cols := dynview_inline_circle_cols(cmd, style, max_cols)
    text_ascent, text_descent := dynview_style_ascent_descent(style, font_size)

    status := dynview_layout_wrap_before_inline(
        cache,
        state,
        acc,
        max_cols,
        cols,
        text_ascent,
        text_descent)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    item := dynview_inline_filled_circle_item(cache, cmd, style, cols, text_ascent, text_descent)
    status = dynview_layout_push_item(cache, state, acc, item)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    return dynview_layout_finalize_after_inline_if_full(
        cache,
        state,
        acc,
        max_cols,
        text_ascent,
        text_descent)
}

//   Build a filled pie-section item using circle-equivalent geometry.
dynview_inline_pie_section_item :: #force_inline proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style,
    cols: int,
    text_ascent, text_descent: f32) -> core.Ui_Dynview_Layout_Item {

    item := dynview_inline_circle_item(cache, cmd, style, cols, text_ascent, text_descent)
    item.kind = .InlinePieSection
    item.pie_start_angle_degrees = cmd.pie_start_angle_degrees
    item.pie_end_angle_degrees = cmd.pie_end_angle_degrees
    item.inline_outline_stroke = max(0.0, cmd.inline_outline_stroke)
    return item
}

//   Lay out one inline pie-section command and return the line touched.
dynview_layout_consume_inline_pie_section :: proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> (i32, int) {

    placement_status := dynview_layout_prepare_style_placement(
        cache,
        state,
        acc,
        style,
        font_size)
    if placement_status != DYNVIEW_STATUS_OK {
        return placement_status, -1
    }

    max_cols := dynview_layout_max_cols(cache, style)
    cols := dynview_inline_circle_cols(cmd, style, max_cols)
    text_ascent, text_descent := dynview_style_ascent_descent(style, font_size)

    status := dynview_layout_wrap_before_inline(
        cache,
        state,
        acc,
        max_cols,
        cols,
        text_ascent,
        text_descent)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    item := dynview_inline_pie_section_item(cache, cmd, style, cols, text_ascent, text_descent)
    status = dynview_layout_push_item(cache, state, acc, item)
    if status != DYNVIEW_STATUS_OK {
        return status, -1
    }

    return dynview_layout_finalize_after_inline_if_full(
        cache,
        state,
        acc,
        max_cols,
        text_ascent,
        text_descent)
}

//   Fill a one-line layout cache for an empty command stream.
dynview_layout_set_empty_default :: proc(cache: ^core.Ui_Dynview_Compile_Cache) {
    cache^.layout_is_valid = true
    cache^.layout_line_count = 1
    cache^.layout_lines[0] = core.Ui_Dynview_Layout_Line{
        y_offset = 0,
        line_height = max(1.0, cache^.last_font_size),
        baseline = max(1.0, cache^.last_font_size * 0.8),
        max_ascent = max(1.0, cache^.last_font_size * 0.8),
        max_descent = max(1.0, cache^.last_font_size * 0.2),
    }
    cache^.layout_total_height = cache^.layout_lines[0].line_height
    cache^.layout_average_line_height = cache^.layout_lines[0].line_height
}

//   Seed layout context from cached panel/font metrics.
dynview_layout_build_context :: proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    buffer: ^core.Ui_Dynview_Command_Buffer,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator) -> Dynview_Layout_Build_Context {

    base_style := dynview_style_by_id(DYNVIEW_STYLE_OUTPUT)
    base_ascent, base_descent := dynview_style_ascent_descent(base_style, cache^.last_font_size)
    state^ = Dynview_Layout_State{
        line_gap = max(1.0, (base_ascent + base_descent) * 0.16),
        active_block_id = -1,
        active_block_kind = -1,
        active_block_format = dynview_block_format_for_kind(-1),
    }
    dynview_layout_seed_line_accumulator(acc, 0, base_ascent, base_descent)

    return Dynview_Layout_Build_Context{
        cache = cache,
        buffer = buffer,
        state = state,
        acc = acc,
        font_size = cache^.last_font_size,
        base_ascent = base_ascent,
        base_descent = base_descent,
    }
}

//   Apply before/after paragraph spacing at block boundaries.
dynview_layout_apply_block_spacing :: #force_inline proc(
    ctx: ^Dynview_Layout_Build_Context,
    spacing: f32) -> i32 {

    if spacing <= 0 {
        return DYNVIEW_STATUS_OK
    }

    if ctx^.acc^.item_count > 0 {
        status := dynview_layout_finalize_line(
            ctx^.cache,
            ctx^.state,
            ctx^.acc,
            ctx^.base_ascent,
            ctx^.base_descent)
        if status != DYNVIEW_STATUS_OK {
            return status
        }
    }

    ctx^.state^.y_offset += spacing
    return DYNVIEW_STATUS_OK
}

//   Update copy-span tracking for block lifecycle commands.
dynview_layout_handle_block_markers :: proc(
    ctx: ^Dynview_Layout_Build_Context,
    cmd: core.Ui_Dynview_Command) -> i32 {

    if cmd.kind == .BeginBlock {
        new_format := dynview_block_format_for_kind(cmd.style_id)
        spacing_status := dynview_layout_apply_block_spacing(ctx, new_format.paragraph_spacing_before)
        if spacing_status != DYNVIEW_STATUS_OK {
            return spacing_status
        }

        ctx^.state^.active_block_id = cmd.block_id
        ctx^.state^.active_block_kind = cmd.style_id
        ctx^.state^.active_block_format = new_format
        return DYNVIEW_STATUS_OK
    }

    if cmd.kind == .EndBlock {
        spacing_status := dynview_layout_apply_block_spacing(
            ctx,
            ctx^.state^.active_block_format.paragraph_spacing_after)
        if spacing_status != DYNVIEW_STATUS_OK {
            return spacing_status
        }

        ctx^.state^.active_block_id = -1
        ctx^.state^.active_block_kind = -1
        ctx^.state^.active_block_format = dynview_block_format_for_kind(-1)
        return DYNVIEW_STATUS_OK
    }

    return DYNVIEW_STATUS_OK
}

//   Consume one visible text-like command using normal wrapped text flow.
dynview_layout_consume_text_like_command :: #force_inline proc(
    ctx: ^Dynview_Layout_Build_Context,
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style) -> i32 {

    text := dynview_text_for_command(ctx^.buffer, cmd)
    status, _ := dynview_layout_consume_text_run(
        ctx^.cache, ctx^.state, ctx^.acc, cmd, text, style, ctx^.font_size)
    return status
}

//   Consume one visible math-structure command using the matching layout helper.
dynview_layout_consume_structured_math_command :: #force_inline proc(
    ctx: ^Dynview_Layout_Build_Context,
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style) -> i32 {

    switch cmd.kind {
    case .MathBlock:
        status, _ := dynview_layout_consume_math_block(
            ctx^.cache,
            ctx^.buffer,
            ctx^.state,
            ctx^.acc,
            cmd,
            style,
            ctx^.font_size)
        return status
    case .ScriptAttach:
        status, _ := dynview_layout_consume_script_attach(
            ctx^.cache,
            ctx^.buffer,
            ctx^.state,
            ctx^.acc,
            cmd,
            style,
            ctx^.font_size)
        return status
    case .ScriptAttachRecursive:
        return DYNVIEW_STATUS_INVALID_ARGUMENT
    case .AccentBar:
        status, _ := dynview_layout_consume_accent_bar(
            ctx^.cache,
            ctx^.buffer,
            ctx^.state,
            ctx^.acc,
            cmd,
            style,
            ctx^.font_size)
        return status
    case .RadicalBar:
        status, _ := dynview_layout_consume_radical_bar(
            ctx^.cache,
            ctx^.buffer,
            ctx^.state,
            ctx^.acc,
            cmd,
            style,
            ctx^.font_size)
        return status
    case .AccentBarRecursive:
        return DYNVIEW_STATUS_INVALID_ARGUMENT
    case .RadicalBarRecursive:
        return DYNVIEW_STATUS_INVALID_ARGUMENT
    case .BeginBlock, .EndBlock, .TextRun, .MathGlyphRun, .CopyableTextRun,
        .LineBreak, .Divider, .InlineLine, .InlineBox, .InlineCircle,
        .InlineFilledBox, .InlineFilledCircle, .InlinePieSection:
    }

    return DYNVIEW_STATUS_INVALID_ARGUMENT
}

//   Consume one visible inline-shape command using the matching layout helper.
dynview_layout_consume_inline_shape_command :: #force_inline proc(
    ctx: ^Dynview_Layout_Build_Context,
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style) -> i32 {

    switch cmd.kind {
    case .InlineLine:
        status, _ := dynview_layout_consume_inline_line(
            ctx^.cache, ctx^.state, ctx^.acc, cmd, style, ctx^.font_size)
        return status
    case .InlineBox:
        status, _ := dynview_layout_consume_inline_box(
            ctx^.cache, ctx^.state, ctx^.acc, cmd, style, ctx^.font_size)
        return status
    case .InlineCircle:
        status, _ := dynview_layout_consume_inline_circle(
            ctx^.cache, ctx^.state, ctx^.acc, cmd, style, ctx^.font_size)
        return status
    case .InlineFilledBox:
        status, _ := dynview_layout_consume_inline_filled_box(
            ctx^.cache, ctx^.state, ctx^.acc, cmd, style, ctx^.font_size)
        return status
    case .InlineFilledCircle:
        status, _ := dynview_layout_consume_inline_filled_circle(
            ctx^.cache, ctx^.state, ctx^.acc, cmd, style, ctx^.font_size)
        return status
    case .InlinePieSection:
        status, _ := dynview_layout_consume_inline_pie_section(
            ctx^.cache, ctx^.state, ctx^.acc, cmd, style, ctx^.font_size)
        return status
    case .BeginBlock, .EndBlock, .TextRun, .MathGlyphRun, .MathBlock,
        .ScriptAttach, .ScriptAttachRecursive, .AccentBar, .AccentBarRecursive, .RadicalBar,
        .RadicalBarRecursive,
        .CopyableTextRun, .LineBreak, .Divider:
    }

    return DYNVIEW_STATUS_INVALID_ARGUMENT
}

//   Consume one visible dynview command and update copy-row span.
dynview_layout_consume_visible_command :: proc(
    ctx: ^Dynview_Layout_Build_Context,
    cmd: core.Ui_Dynview_Command,
    style: Dynview_Text_Style) -> i32 {

    effective_style := dynview_style_with_block_format(style, ctx^.state^.active_block_format)
    switch cmd.kind {
    case .TextRun, .MathGlyphRun:
        return dynview_layout_consume_text_like_command(ctx, cmd, effective_style)
    case .MathBlock, .ScriptAttach, .ScriptAttachRecursive, .AccentBar, .AccentBarRecursive, .RadicalBar,
        .RadicalBarRecursive:
        return dynview_layout_consume_structured_math_command(ctx, cmd, effective_style)
    case .InlineLine, .InlineBox, .InlineCircle, .InlineFilledBox,
        .InlineFilledCircle, .InlinePieSection:
        return dynview_layout_consume_inline_shape_command(ctx, cmd, effective_style)
    case .LineBreak, .Divider:
        return dynview_layout_finalize_line(
            ctx^.cache,
            ctx^.state,
            ctx^.acc,
            ctx^.base_ascent,
            ctx^.base_descent)
    case .BeginBlock, .EndBlock, .CopyableTextRun:
    }

    return DYNVIEW_STATUS_OK
}

//   Resolve inline draw color using per-item brush override with style fallback.
dynview_inline_draw_color :: #force_inline proc(
    style: Dynview_Text_Style,
    item: core.Ui_Dynview_Layout_Item) -> rl.Color {

    if item.has_brush_color {
        return item.brush_color
    }
    return style.color
}

//   Finalize total layout metrics after all commands are consumed.
dynview_layout_finalize_metrics :: proc(ctx: ^Dynview_Layout_Build_Context) -> i32 {
    status := dynview_layout_finalize_line(
        ctx^.cache,
        ctx^.state,
        ctx^.acc,
        ctx^.base_ascent,
        ctx^.base_descent)
    if status != DYNVIEW_STATUS_OK {
        return status
    }

    if ctx^.cache^.layout_line_count <= 0 {
        return DYNVIEW_STATUS_ILLEGAL_STATE
    }

    last_line := ctx^.cache^.layout_lines[ctx^.cache^.layout_line_count - 1]
    ctx^.cache^.layout_total_height = last_line.y_offset + last_line.line_height
    ctx^.cache^.layout_average_line_height =
        ctx^.cache^.layout_total_height / f32(ctx^.cache^.layout_line_count)
    ctx^.cache^.layout_is_valid = true
    return DYNVIEW_STATUS_OK
}

//   Build deterministic line/item layout cache from current validated command stream.
dynview_rebuild_layout_cache :: proc(runtime: ^core.Ui_Dynview_Runtime) -> i32 {
    if runtime == nil {
        return DYNVIEW_STATUS_INVALID_ARGUMENT
    }

    cache := &runtime^.compile_cache
    buffer := &runtime^.command_buffer
    dynview_layout_reset_cache(cache)

    if buffer^.command_count <= 0 {
        dynview_layout_set_empty_default(cache)
        return DYNVIEW_STATUS_OK
    }

    state := Dynview_Layout_State{}
    acc := Dynview_Layout_Line_Accumulator{}
    ctx := dynview_layout_build_context(cache, buffer, &state, &acc)

    for i in 0..<buffer^.command_count {
        cmd := buffer^.commands[i]
        marker_status := dynview_layout_handle_block_markers(&ctx, cmd)
        if marker_status != DYNVIEW_STATUS_OK {
            return marker_status
        }

        style := dynview_style_by_id(cmd.style_id)
        status := dynview_layout_consume_visible_command(&ctx, cmd, style)
        if status != DYNVIEW_STATUS_OK {
            return status
        }
    }

    return dynview_layout_finalize_metrics(&ctx)
}

//   Return true when one layout line is outside the visible panel bounds.
dynview_layout_line_outside_panel :: #force_inline proc(
    line_top, line_bottom, panel_top, panel_bottom: f32) -> bool {

    return line_bottom < panel_top || line_top > panel_bottom
}

//   Return extra top/bottom culling margin for lines with script or accent items.
dynview_line_visual_padding :: #force_inline proc(
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
        script_top_pad, script_bottom_pad := dynview_script_visual_padding(script_font_size)
        top_pad = max(top_pad, script_top_pad)
        bottom_pad = max(bottom_pad, script_bottom_pad)
        if item.kind == .AccentBar || item.kind == .RadicalBar {
            has_scripts := item.script_sup_text_len > 0 || item.script_sub_text_len > 0
            accent_pad := dynview_accent_script_clearance(font_size, item.script_scale, has_scripts)
            top_pad = max(top_pad, accent_pad)
            bottom_pad = max(bottom_pad, accent_pad)
        }
    }

    return top_pad, bottom_pad
}

//   Draw one cached math-block item from its precomputed program slot.
dynview_draw_math_block_item :: proc(
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
    dynview_draw_math_program_at(state, runtime, panel, font, font_size, program, item_x, baseline_y)
}

//   Draw one recursive accent wrapper by drawing the child math program first, then the line.
dynview_draw_recursive_accent_item :: proc(
    state: ^core.Euclid_General_State,
    runtime: ^core.Ui_Dynview_Runtime,
    panel: rl.Rectangle,
    font: rl.Font,
    font_size: f32,
    style: Dynview_Text_Style,
    item: core.Ui_Dynview_Layout_Item,
    draw_x, item_y: f32) {

    child_program, ok := dynview_math_program_from_id(&runtime^.compile_cache, item.math_program_id)
    if !ok {
        return
    }

    baseline_y := item_y + item.ascent
    dynview_draw_math_program_at(state, runtime, panel, font, font_size, child_program^, draw_x, baseline_y)

    accent_style := dynview_style_by_id(item.accent_style_id)
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
dynview_draw_recursive_radical_item :: proc(
    state: ^core.Euclid_General_State,
    runtime: ^core.Ui_Dynview_Runtime,
    panel: rl.Rectangle,
    font: rl.Font,
    font_size: f32,
    item: core.Ui_Dynview_Layout_Item,
    draw_x, item_y: f32) {

    child_program, ok := dynview_math_program_from_id(&runtime^.compile_cache, item.math_program_id)
    if !ok {
        return
    }

    baseline_y := item_y + item.ascent
    style := dynview_style_by_id(item.style_id)
    script_style := dynview_style_by_id(item.script_style_id)
    script_font := dynview_resolve_font_for_style(state, script_style, font)
    base_advance := dynview_effective_advance(style, runtime^.compile_cache.last_wrap_advance)
    lead_width := dynview_radical_lead_width(font_size, base_advance)
    front_padding, back_padding := dynview_radical_side_paddings(font_size, base_advance)
    content_x := draw_x + front_padding + lead_width

    dynview_draw_math_program_at(state, runtime, panel, font, font_size, child_program^, content_x, baseline_y)

    index_text := dynview_text_span_from_buffer(
        &runtime^.command_buffer,
        item.radical_index_text_offset,
        item.radical_index_text_len)
    radical_style := dynview_style_by_id(item.accent_style_id)
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
    root_low_y := baseline_y + font_size * 0.375
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
        index_ascent, _ := dynview_style_ascent_descent(script_style, index_font_size)
        index_cols := max(1, text_codepoint_count(index_text))
        index_advance := dynview_effective_advance(script_style, runtime^.compile_cache.last_wrap_advance) * index_scale
        index_width := f32(index_cols) * index_advance
        index_right_limit := draw_x + front_padding + lead_width * 0.36
        index_x := index_right_limit - index_width
        index_y := baseline_y - child_program^.ascent * 0.62 - index_ascent * 0.50 - font_size * 0.25
        ui_text_f32(index_text, index_x, index_y, script_style.color, script_font, index_font_size)
    }
}

//   Resolve a style-specific font handle, falling back to provided font when state is nil.
dynview_resolve_font_for_style :: #force_inline proc(
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
dynview_text_item_draw_x :: #force_inline proc(
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
dynview_draw_script_children :: #force_inline proc(
    runtime: ^core.Ui_Dynview_Runtime,
    item: core.Ui_Dynview_Layout_Item,
    style: Dynview_Text_Style,
    script_style: Dynview_Text_Style,
    script_font: rl.Font,
    font_size, baseline_y, draw_x: f32,
    base_text: string,
    script_color: rl.Color) -> (f32, f32) {

    script_scale := max(0.2, item.script_scale)
    script_font_size, sup_raise_px, sub_drop_px := dynview_script_draw_offsets(
        font_size,
        script_scale,
        item.script_sup_raise,
        item.script_sub_drop)
    base_ascent, base_descent := dynview_style_ascent_descent(style, font_size)
    script_ascent, script_descent := dynview_style_ascent_descent(script_style, script_font_size)
    script_top_pad, script_bottom_pad := dynview_script_visual_padding(script_font_size)

    sup_text := dynview_text_span_from_buffer(
        &runtime^.command_buffer,
        item.script_sup_text_offset,
        item.script_sup_text_len)
    sub_text := dynview_text_span_from_buffer(
        &runtime^.command_buffer,
        item.script_sub_text_offset,
        item.script_sub_text_len)

    base_cols := max(1, text_codepoint_count(base_text))
    base_advance := dynview_effective_advance(style, runtime^.compile_cache.last_wrap_advance)
    script_x := draw_x + f32(base_cols) * base_advance + max(1.0, item.script_gap * font_size)

    content_ascent := base_ascent
    content_descent := base_descent

    if len(sup_text) > 0 {
        sup_top := baseline_y - sup_raise_px - script_ascent
        ui_text_f32(sup_text, script_x, sup_top, script_color, script_font, script_font_size)
        content_ascent = max(content_ascent, script_ascent + sup_raise_px + script_top_pad)
    }

    if len(sub_text) > 0 {
        // Keep padding for layout/culling only; avoid shifting glyphs upward.
        sub_top := baseline_y + sub_drop_px - script_ascent
        ui_text_f32(sub_text, script_x, sub_top, script_color, script_font, script_font_size)
        content_descent = max(content_descent, script_descent + sub_drop_px + script_bottom_pad)
    }

    return content_ascent, content_descent
}

//   Draw one ScriptAttach item including raised/lowered script text.
dynview_draw_script_attach_item :: #force_inline proc(
    state: ^core.Euclid_General_State,
    runtime: ^core.Ui_Dynview_Runtime,
    item: core.Ui_Dynview_Layout_Item,
    style: Dynview_Text_Style,
    resolved_font: rl.Font,
    text: string,
    font_size, draw_x, item_y: f32) {

    script_style := dynview_style_by_id(item.script_style_id)
    script_font := dynview_resolve_font_for_style(state, script_style, resolved_font)

    baseline_y := item_y + item.ascent
    base_ascent, _ := dynview_style_ascent_descent(style, font_size)
    base_top := baseline_y - base_ascent
    ui_text_f32(text, draw_x, base_top, style.color, resolved_font, font_size)

    _, _ = dynview_draw_script_children(
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
dynview_draw_recursive_script_attach_item :: #force_inline proc(
    state: ^core.Euclid_General_State,
    runtime: ^core.Ui_Dynview_Runtime,
    panel: rl.Rectangle,
    font: rl.Font,
    font_size: f32,
    item: core.Ui_Dynview_Layout_Item,
    draw_x, item_y: f32) {

    child_program, ok := dynview_math_program_from_id(&runtime^.compile_cache, item.math_program_id)
    if !ok {
        return
    }

    baseline_y := item_y + item.ascent
    dynview_draw_math_program_at(state, runtime, panel, font, font_size, child_program^, draw_x, baseline_y)

    script_style := dynview_style_by_id(item.script_style_id)
    script_font := dynview_resolve_font_for_style(state, script_style, font)
    script_scale := max(0.2, item.script_scale)
    script_font_size, sup_raise_px, sub_drop_px := dynview_script_draw_offsets(
        font_size,
        script_scale,
        item.script_sup_raise,
        item.script_sub_drop)
    script_ascent, _ := dynview_style_ascent_descent(script_style, script_font_size)

    sup_text := dynview_text_span_from_buffer(
        &runtime^.command_buffer,
        item.script_sup_text_offset,
        item.script_sup_text_len)
    sub_text := dynview_text_span_from_buffer(
        &runtime^.command_buffer,
        item.script_sub_text_offset,
        item.script_sub_text_len)

    script_x := draw_x + child_program^.draw_width + max(1.0, item.script_gap * font_size)
    if len(sup_text) > 0 {
        sup_top := baseline_y - sup_raise_px - script_ascent
        ui_text_f32(sup_text, script_x, sup_top, script_style.color, script_font, script_font_size)
    }

    if len(sub_text) > 0 {
        sub_top := baseline_y + sub_drop_px - script_ascent
        ui_text_f32(sub_text, script_x, sub_top, script_style.color, script_font, script_font_size)
    }
}

//   Draw one AccentBar item including optional script children and accent stroke.
dynview_draw_accent_bar_item :: #force_inline proc(
    state: ^core.Euclid_General_State,
    runtime: ^core.Ui_Dynview_Runtime,
    item: core.Ui_Dynview_Layout_Item,
    style: Dynview_Text_Style,
    resolved_font: rl.Font,
    text: string,
    font_size, draw_x, item_y: f32) {

    script_style := dynview_style_by_id(item.script_style_id)
    script_font := dynview_resolve_font_for_style(state, script_style, resolved_font)

    baseline_y := item_y + item.ascent
    base_ascent, _ := dynview_style_ascent_descent(style, font_size)
    base_top := baseline_y - base_ascent
    ui_text_f32(text, draw_x, base_top, style.color, resolved_font, font_size)

    content_ascent, content_descent := dynview_draw_script_children(
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

    accent_style := dynview_style_by_id(item.accent_style_id)
    bar_thickness := max(1.0, item.accent_thickness * font_size)
    has_scripts := item.script_sup_text_len > 0 || item.script_sub_text_len > 0
    bar_offset := max(0.0, item.accent_offset * font_size) +
        dynview_accent_script_clearance(font_size, item.script_scale, has_scripts)

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
dynview_draw_radical_bar_item :: #force_inline proc(
    state: ^core.Euclid_General_State,
    runtime: ^core.Ui_Dynview_Runtime,
    item: core.Ui_Dynview_Layout_Item,
    style: Dynview_Text_Style,
    resolved_font: rl.Font,
    text: string,
    font_size, draw_x, item_y: f32) {

    script_style := dynview_style_by_id(item.script_style_id)
    script_font := dynview_resolve_font_for_style(state, script_style, resolved_font)

    baseline_y := item_y + item.ascent
    base_ascent, _ := dynview_style_ascent_descent(style, font_size)
    base_advance := dynview_effective_advance(style, runtime^.compile_cache.last_wrap_advance)
    lead_width := dynview_radical_lead_width(font_size, base_advance)
    front_padding, back_padding := dynview_radical_side_paddings(font_size, base_advance)
    content_x := draw_x + front_padding + lead_width
    base_top := baseline_y - base_ascent
    ui_text_f32(text, content_x, base_top, style.color, resolved_font, font_size)

    content_ascent, _ := dynview_draw_script_children(
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

    index_text := dynview_text_span_from_buffer(
        &runtime^.command_buffer,
        item.radical_index_text_offset,
        item.radical_index_text_len)

    radical_style := dynview_style_by_id(item.accent_style_id)
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
    root_low_y := baseline_y + font_size * 0.375
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
        index_ascent, _ := dynview_style_ascent_descent(script_style, index_font_size)
        index_cols := max(1, text_codepoint_count(index_text))
        index_advance := dynview_effective_advance(script_style, runtime^.compile_cache.last_wrap_advance) * index_scale
        index_width := f32(index_cols) * index_advance
        index_right_limit := draw_x + front_padding + lead_width * 0.36
        index_x := index_right_limit - index_width
        index_y := baseline_y - content_ascent * 0.62 - index_ascent * 0.50 - font_size * 0.25
        ui_text_f32(index_text, index_x, index_y, script_style.color, script_font, index_font_size)
    }
}

//   Draw one cached text item.
dynview_draw_cached_text_item :: proc(
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
    resolved_font := dynview_resolve_font_for_style(state, style, font)
    draw_x := dynview_text_item_draw_x(panel, style, item, item_x)

    switch item.kind {
    case .ScriptAttach:
        dynview_draw_script_attach_item(
            state,
            runtime,
            item,
            style,
            resolved_font,
            text,
            font_size,
            draw_x,
            item_y)
    case .ScriptAttachRecursive:
        dynview_draw_recursive_script_attach_item(
            state,
            runtime,
            panel,
            font,
            font_size,
            item,
            draw_x,
            item_y)
    case .AccentBar:
        dynview_draw_accent_bar_item(
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
        dynview_draw_recursive_accent_item(
            state,
            runtime,
            panel,
            font,
            font_size,
            style,
            item,
            draw_x,
            item_y)
    case .RadicalBar:
        dynview_draw_radical_bar_item(
            state,
            runtime,
            item,
            style,
            resolved_font,
            text,
            font_size,
            draw_x,
            item_y)
    case .RadicalBarRecursive:
        dynview_draw_recursive_radical_item(state, runtime, panel, font, font_size, item, draw_x, item_y)
    case .MathBlock:
        dynview_draw_math_block_item(state, runtime, panel, font, font_size, item, draw_x, item_y)
    case .TextRun, .MathGlyphRun:
        ui_text(text, int(draw_x), int(item_y), style.color, resolved_font, font_size)
    case .InlineLine, .InlineBox, .InlineCircle, .InlineFilledBox, .InlineFilledCircle, .InlinePieSection:
    }
}

//   Draw one cached inline shape item.
dynview_draw_cached_inline_item :: proc(
    style: Dynview_Text_Style,
    item: core.Ui_Dynview_Layout_Item,
    item_x, item_y: f32) {

    color := dynview_inline_draw_color(style, item)
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
        dynview_draw_filled_pie_section(
            center,
            radius,
            item.pie_start_angle_degrees,
            item.pie_end_angle_degrees,
            color)
        if item.inline_outline_stroke > 0 {
            stroke := max(1.0, item.inline_outline_stroke)
            start_point := dynview_pie_point(center, radius, item.pie_start_angle_degrees)
            end_point := dynview_pie_point(center, radius, item.pie_end_angle_degrees)
            rl.DrawLineEx(center, start_point, stroke, style.color)
            rl.DrawLineEx(center, end_point, stroke, style.color)
        }
    case .TextRun, .MathGlyphRun, .MathBlock, .ScriptAttach, .ScriptAttachRecursive, .AccentBar,
        .AccentBarRecursive, .RadicalBar, .RadicalBarRecursive:
    }
}

//   Draw one cached layout line and all its items.
dynview_draw_cached_line :: proc(
    state: ^core.Euclid_General_State,
    runtime: ^core.Ui_Dynview_Runtime,
    panel: rl.Rectangle,
    line: core.Ui_Dynview_Layout_Line,
    line_top, text_padding, font_size: f32,
    font: rl.Font) {

    item_end := line.item_start + line.item_count
    for item_index in line.item_start..<item_end {
        item := runtime^.compile_cache.layout_items[item_index]
        style := dynview_style_by_id(item.style_id)
        item_x := panel.x + text_padding + item.x_offset
        item_y := line_top + item.y_offset

        if item.kind == .TextRun ||
            item.kind == .MathBlock ||
            item.kind == .MathGlyphRun ||
            item.kind == .ScriptAttach ||
            item.kind == .ScriptAttachRecursive ||
            item.kind == .AccentBar ||
            item.kind == .RadicalBar {
            dynview_draw_cached_text_item(state, runtime, panel, font, font_size, style, item, item_x, item_y)
            continue
        }

        dynview_draw_cached_inline_item(style, item, item_x, item_y)
    }
}

//   Draw the canonical layout cache using explicit per-line baselines and offsets.
dynview_draw_cached_layout :: proc(
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
        top_pad, bottom_pad := dynview_line_visual_padding(cache, line, font_size)
        if dynview_layout_line_outside_panel(
            line_top - top_pad,
            line_bottom + bottom_pad,
            panel_top,
            panel_bottom) {
            continue
        }

        dynview_draw_cached_line(state, runtime, panel, line, line_top, text_padding, font_size, font)
    }
}

//   Return fallback wrapped row count for plain-text rendering.
dynview_fallback_row_count :: #force_inline proc(
    panel: rl.Rectangle,
    wrap_advance: f32,
    fallback_text: string) -> int {

    max_cols := chars_per_text_row(panel.width - TEXT_PADDING * 2, wrap_advance)
    return count_wrapped_text_rows(fallback_text, max_cols)
}

//   Return total content height using cached line metrics, else fallback row math.
dynview_scratchpad_content_height_or_fallback :: proc(
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    panel: rl.Rectangle,
    text_padding, wrap_advance, fallback_row_height: f32,
    fallback_text: string) -> f32 {

    fallback_rows := dynview_fallback_row_count(panel, wrap_advance, fallback_text)
    fallback_height := text_padding * 2 + f32(fallback_rows) * fallback_row_height
    if ui_runtime == nil {
        return fallback_height
    }

    runtime := &ui_runtime^.dynview_runtime
    if !runtime^.enabled ||
        !runtime^.compile_cache.layout_is_valid ||
        runtime^.command_buffer.has_stream_error ||
        runtime^.command_buffer.command_count <= 0 {
        return fallback_height
    }

    return text_padding * 2 + runtime^.compile_cache.layout_total_height
}

//   Return scroll step derived from cached line metrics, else fallback to fixed row height.
dynview_scratchpad_scroll_step_or_fallback :: proc(
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    fallback_row_height: f32) -> f32 {

    if ui_runtime == nil {
        return fallback_row_height
    }

    runtime := &ui_runtime^.dynview_runtime
    if !runtime^.enabled ||
        !runtime^.compile_cache.layout_is_valid ||
        runtime^.command_buffer.has_stream_error ||
        runtime^.command_buffer.command_count <= 0 {
        return fallback_row_height
    }

    return max(1.0, runtime^.compile_cache.layout_average_line_height)
}

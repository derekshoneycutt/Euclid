package dynview

import "../core"

layout_reset_cache :: proc(cache: ^core.Dynview_Compile_Cache) {
    cache^.layout_line_count = 0
    cache^.layout_item_count = 0
    cache^.layout_total_height = 0
    cache^.layout_average_line_height = 0
    cache^.layout_is_valid = false
}

//   Return one precomputed math program slot when the command references a valid id.
math_program_from_command :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    cmd: core.Dynview_Command) -> (^core.Dynview_Math_Program, bool) {

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
math_program_from_id :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    program_id: i32) -> (^core.Dynview_Math_Program, bool) {

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

//   Return one secondary child math program from a command reference.
secondary_math_program_from_command :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    cmd: core.Dynview_Command) -> (^core.Dynview_Math_Program, bool) {

    return math_program_from_id(cache, cmd.secondary_math_program_id)
}

//   Build one layout-like item for a text or math-glyph child command inside a math block.
math_program_text_item :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    buffer: ^core.Dynview_Command_Buffer,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> core.Dynview_Layout_Item {

    text := text_for_command(buffer, cmd)
    cols := max(1, text_codepoint_count_span(text, 0, len(text)))
    ascent, descent := style_ascent_descent(style, font_size)
    kind := core.Dynview_Layout_Item_Kind.TextRun
    if cmd.kind == .MathGlyphRun {
        kind = .MathGlyphRun
    }

    return core.Dynview_Layout_Item{
        kind = kind,
        style_id = cmd.style_id,
        text_offset = cmd.text_offset,
        text_len = cmd.text_len,
        draw_width = f32(cols) * effective_advance(style, cache^.last_wrap_advance),
        draw_height = ascent + descent,
        ascent = ascent,
        descent = descent,
    }
}

//   Build one layout-like item for a recursive script wrapper around a child math program.
math_program_recursive_script_item :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    buffer: ^core.Dynview_Command_Buffer,
    cmd: core.Dynview_Command,
    font_size: f32) -> (core.Dynview_Layout_Item, bool) {

    child_program, ok := math_program_from_id(cache, cmd.math_program_id)
    if !ok || !measure_math_program(cache, buffer, child_program, font_size) {
        return core.Dynview_Layout_Item{}, false
    }

    sup_text := text_span_from_buffer(
        buffer,
        cmd.script_sup_text_offset,
        cmd.script_sup_text_len)
    sub_text := text_span_from_buffer(
        buffer,
        cmd.script_sub_text_offset,
        cmd.script_sub_text_len)

    sup_cols := text_codepoint_count_span(sup_text, 0, len(sup_text))
    sub_cols := text_codepoint_count_span(sub_text, 0, len(sub_text))
    script_cols := max(sup_cols, sub_cols)

    script_style := style_by_id(cmd.script_style_id)
    script_scale := max(0.2, cmd.script_scale)
    script_font_size, sup_raise_px, sub_drop_px := script_draw_offsets(
        font_size,
        script_scale,
        cmd.script_sup_raise,
        cmd.script_sub_drop)
    script_ascent, script_descent := style_ascent_descent(script_style, script_font_size)
    script_top_pad, script_bottom_pad := script_visual_padding(script_font_size)

    ascent := child_program^.ascent
    descent := child_program^.descent
    if sup_cols > 0 {
        ascent = max(ascent, script_ascent + sup_raise_px + script_top_pad)
    }
    if sub_cols > 0 {
        descent = max(descent, script_descent + sub_drop_px + script_bottom_pad)
    }

    script_advance := effective_advance(script_style, cache^.last_wrap_advance) *
        script_scale
    gap_px := max(1.0, cmd.script_gap * font_size)
    script_width := f32(script_cols) * script_advance
    draw_width := child_program^.draw_width
    if script_cols > 0 {
        draw_width += gap_px + script_width
    }

    return core.Dynview_Layout_Item{
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
        visual_padding_bottom =
            max(child_program^.visual_padding_bottom, script_bottom_pad),
    }, true
}

//   Build one layout-like item for a display-style large operator with stacked limits.
math_program_large_op_item :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    buffer: ^core.Dynview_Command_Buffer,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> core.Dynview_Layout_Item {

    base_text := text_for_command(buffer, cmd)
    sup_text := text_span_from_buffer(
        buffer,
        cmd.script_sup_text_offset,
        cmd.script_sup_text_len)
    sub_text := text_span_from_buffer(
        buffer,
        cmd.script_sub_text_offset,
        cmd.script_sub_text_len)

    glyph_cols := max(1, text_codepoint_count_span(base_text, 0, len(base_text)))
    sup_cols := text_codepoint_count_span(sup_text, 0, len(sup_text))
    sub_cols := text_codepoint_count_span(sub_text, 0, len(sub_text))

    glyph_scale := large_op_glyph_scale(cmd.large_op_kind)
    glyph_font_size := max(1.0, font_size * glyph_scale)
    glyph_ascent, glyph_descent := style_ascent_descent(style, glyph_font_size)
    glyph_advance := effective_advance(style, cache^.last_wrap_advance) * glyph_scale
    glyph_width := f32(glyph_cols) * glyph_advance

    script_style := style_by_id(cmd.script_style_id)
    limit_scale := large_op_limit_scale(max(0.2, cmd.script_scale))
    limit_font_size := max(1.0, font_size * limit_scale)
    limit_ascent, limit_descent := style_ascent_descent(script_style, limit_font_size)
    limit_top_pad, limit_bottom_pad := script_visual_padding(limit_font_size)
    limit_advance :=
        effective_advance(script_style, cache^.last_wrap_advance) * limit_scale
    sup_width := f32(sup_cols) * limit_advance
    sub_width := f32(sub_cols) * limit_advance

    upper_height: f32 = 0
    if sup_cols > 0 {
        upper_height = limit_ascent + limit_descent
    }
    lower_height: f32 = 0
    if sub_cols > 0 {
        lower_height = limit_ascent + limit_descent
    }

    limit_gap := large_op_limit_gap_for_kind(cmd.large_op_kind, font_size, cmd.script_gap)
    ascent := glyph_ascent
    descent := glyph_descent
    if sup_cols > 0 {
        ascent += upper_height + limit_gap
    }
    if sub_cols > 0 {
        descent += lower_height + limit_gap
    }

    draw_width := max(glyph_width, max(sup_width, sub_width))
    return core.Dynview_Layout_Item{
        kind = .LargeOpRecursive,
        style_id = cmd.style_id,
        text_offset = cmd.text_offset,
        text_len = cmd.text_len,
        script_sup_text_offset = cmd.script_sup_text_offset,
        script_sup_text_len = cmd.script_sup_text_len,
        script_sub_text_offset = cmd.script_sub_text_offset,
        script_sub_text_len = cmd.script_sub_text_len,
        script_style_id = cmd.script_style_id,
        script_scale = limit_scale,
        script_gap = cmd.script_gap,
        large_op_kind = cmd.large_op_kind,
        draw_width = draw_width,
        draw_height = ascent + descent,
        ascent = ascent,
        descent = descent,
        visual_padding_top = limit_top_pad,
        visual_padding_bottom = limit_bottom_pad,
    }
}

//   Build one layout-like item for a recursive fraction with centered numerator and denominator.
math_program_recursive_fraction_item :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    buffer: ^core.Dynview_Command_Buffer,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> (core.Dynview_Layout_Item, bool) {

    numerator_program, ok := math_program_from_command(cache, cmd)
    if !ok || !measure_math_program(cache, buffer, numerator_program, font_size) {
        return core.Dynview_Layout_Item{}, false
    }

    denominator_program, ok_den := secondary_math_program_from_command(cache, cmd)
    if !ok_den || !measure_math_program(cache, buffer, denominator_program, font_size) {
        return core.Dynview_Layout_Item{}, false
    }

    base_advance := effective_advance(style, cache^.last_wrap_advance)
    side_padding := fraction_side_padding(font_size, base_advance)
    divider_gap := fraction_vertical_gap(font_size)
    divider_thickness := max(1.0, cmd.accent_thickness * font_size)
    divider_half := divider_thickness * 0.5

    content_width := max(numerator_program^.draw_width, denominator_program^.draw_width)
    draw_width := max(content_width + side_padding * 2.0, base_advance)
    ascent := numerator_program^.ascent +
        numerator_program^.descent + divider_gap + divider_half
    descent := denominator_program^.ascent + denominator_program^.descent +
        divider_gap + divider_half
    visual_pad := max(0.6, divider_thickness * 0.5)

    return core.Dynview_Layout_Item{
        kind = .FracRecursive,
        style_id = cmd.style_id,
        math_program_id = cmd.math_program_id,
        secondary_math_program_id = cmd.secondary_math_program_id,
        accent_style_id = cmd.accent_style_id,
        accent_thickness = cmd.accent_thickness,
        draw_width = draw_width,
        draw_height = ascent + descent,
        ascent = ascent,
        descent = descent,
        visual_padding_top = max(max(numerator_program^.visual_padding_top,
            denominator_program^.visual_padding_top), visual_pad),
        visual_padding_bottom = max(max(numerator_program^.visual_padding_bottom,
            denominator_program^.visual_padding_bottom), visual_pad),
    }, true
}

//   Build one layout-like item for a recursive stretch-delimiter wrapper.
math_program_recursive_stretch_delimiter_item :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    buffer: ^core.Dynview_Command_Buffer,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> (core.Dynview_Layout_Item, bool) {

    content_width: f32 = 0
    content_ascent, content_descent := style_ascent_descent(style, font_size)
    top_pad: f32 = 0
    bottom_pad: f32 = 0

    if cmd.math_program_id > 0 {
        child_program, ok := math_program_from_command(cache, cmd)
        if !ok || !measure_math_program(cache, buffer, child_program, font_size) {
            return core.Dynview_Layout_Item{}, false
        }
        content_width = child_program^.draw_width
        content_ascent = child_program^.ascent
        content_descent = child_program^.descent
        top_pad = child_program^.visual_padding_top
        bottom_pad = child_program^.visual_padding_bottom
    }

    content_height := content_ascent + content_descent
    base_advance := effective_advance(style, cache^.last_wrap_advance)
    side_padding := stretch_delimiter_side_padding(font_size, base_advance)
    left_width := stretch_delimiter_width(
        style,
        cache^.last_wrap_advance,
        font_size,
        content_height,
        cmd.accent_mode)
    right_width := stretch_delimiter_width(
        style,
        cache^.last_wrap_advance,
        font_size,
        content_height,
        cmd.radical_mode)

    draw_width := max(content_width + left_width + right_width + side_padding * 2.0,
        base_advance)
    return core.Dynview_Layout_Item{
        kind = .StretchDelimiterRecursive,
        style_id = cmd.style_id,
        math_program_id = cmd.math_program_id,
        accent_mode = cmd.accent_mode,
        radical_mode = cmd.radical_mode,
        draw_width = draw_width,
        draw_height = content_height,
        ascent = content_ascent,
        descent = content_descent,
        visual_padding_top = top_pad,
        visual_padding_bottom = bottom_pad,
    }, true
}

//   Aggregated per-column and per-row cell metrics for one matrix layout.
Matrix_Cell_Dims :: struct {
    col_widths:  [16]f32,
    row_ascents: [16]f32,
    row_descents: [16]f32,
    top_pad:     f32,
    bottom_pad:  f32,
}

//   Measure every matrix cell, accumulating column widths and row extents.
measure_matrix_cells :: proc(
    cache: ^core.Dynview_Compile_Cache,
    buffer: ^core.Dynview_Command_Buffer,
    cell_program: ^core.Dynview_Math_Program,
    rows, cols: int,
    font_size: f32,
    dims: ^Matrix_Cell_Dims) -> bool {

    for row in 0..<rows {
        for col in 0..<cols {
            cell_index := row * cols + col
            cmd_index := cell_program^.command_start + cell_index
            cell_cmd := cache^.math_commands[cmd_index]
            cell_item, cell_ok := math_program_item(cache, buffer, cell_cmd, font_size)
            if !cell_ok {
                return false
            }

            dims.col_widths[col] = max(dims.col_widths[col], cell_item.draw_width)
            dims.row_ascents[row] = max(dims.row_ascents[row], cell_item.ascent)
            dims.row_descents[row] = max(dims.row_descents[row], cell_item.descent)
            dims.top_pad = max(dims.top_pad, cell_item.visual_padding_top)
            dims.bottom_pad = max(dims.bottom_pad, cell_item.visual_padding_bottom)
        }
    }
    return true
}

//   Aggregate matrix draw width and total height from per-column/row cell metrics.
matrix_aggregate_dims :: proc(
    dims: ^Matrix_Cell_Dims,
    rows, cols: int,
    font_size: f32,
    base_advance: f32) -> (draw_width, total_height: f32) {

    column_gap := matrix_column_gap(font_size, base_advance)
    row_gap := matrix_row_gap(font_size)

    for col in 0..<cols {
        draw_width += dims.col_widths[col]
    }
    if cols > 1 {
        draw_width += f32(cols - 1) * column_gap
    }

    for row in 0..<rows {
        total_height += dims.row_ascents[row] + dims.row_descents[row]
    }
    if rows > 1 {
        total_height += f32(rows - 1) * row_gap
    }

    return draw_width, total_height
}

//   Build one layout-like item for a recursive matrix with row-major child cells.
math_program_recursive_matrix_item :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    buffer: ^core.Dynview_Command_Buffer,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> (core.Dynview_Layout_Item, bool) {

    rows, cols, dims_ok := matrix_dims_from_command(buffer, cmd)
    if !dims_ok || rows > 16 || cols > 16 {
        return core.Dynview_Layout_Item{}, false
    }

    cell_program, ok := math_program_from_command(cache, cmd)
    if !ok || !measure_math_program(cache, buffer, cell_program, font_size) {
        return core.Dynview_Layout_Item{}, false
    }

    cell_count := rows * cols
    if cell_program^.command_count != cell_count {
        return core.Dynview_Layout_Item{}, false
    }

    dims := Matrix_Cell_Dims{}
    if !measure_matrix_cells(cache, buffer, cell_program, rows, cols,
        font_size, &dims) {
        return core.Dynview_Layout_Item{}, false
    }
    top_pad := dims.top_pad
    bottom_pad := dims.bottom_pad

    base_advance := effective_advance(style, cache^.last_wrap_advance)
    draw_width, total_height := matrix_aggregate_dims(&dims, rows, cols,
        font_size, base_advance)

    ascent := total_height * 0.5
    descent := total_height - ascent
    return core.Dynview_Layout_Item{
        kind = .MatrixRecursive,
        style_id = cmd.style_id,
        math_program_id = cmd.math_program_id,
        script_sub_text_offset = cmd.script_sub_text_offset,
        script_sub_text_len = cmd.script_sub_text_len,
        accent_mode = i32(rows),
        radical_mode = i32(cols),
        draw_width = max(draw_width, base_advance),
        draw_height = total_height,
        ascent = ascent,
        descent = descent,
        visual_padding_top = top_pad,
        visual_padding_bottom = bottom_pad,
    }, true
}

//   Build one layout-like item for a recursive accent wrapper around a child math program.
math_program_recursive_accent_item :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    buffer: ^core.Dynview_Command_Buffer,
    cmd: core.Dynview_Command,
    font_size: f32) -> (core.Dynview_Layout_Item, bool) {

    child_program, ok := math_program_from_id(cache, cmd.math_program_id)
    if !ok || !measure_math_program(cache, buffer, child_program, font_size) {
        return core.Dynview_Layout_Item{}, false
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

    return core.Dynview_Layout_Item{
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
math_program_recursive_radical_item :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    buffer: ^core.Dynview_Command_Buffer,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> (core.Dynview_Layout_Item, bool) {

    child_program, ok := math_program_from_id(cache, cmd.math_program_id)
    if !ok || !measure_math_program(cache, buffer, child_program, font_size) {
        return core.Dynview_Layout_Item{}, false
    }

    index_text := text_span_from_buffer(
        buffer,
        cmd.radical_index_text_offset,
        cmd.radical_index_text_len)
    index_cols := text_codepoint_count_span(index_text, 0, len(index_text))

    script_style := style_by_id(cmd.script_style_id)
    script_scale := max(0.2, cmd.script_scale)
    script_font_size, _, _ := script_draw_offsets(
        font_size,
        script_scale,
        cmd.script_sup_raise,
        cmd.script_sub_drop)
    script_top_pad, script_bottom_pad := script_visual_padding(script_font_size)
    index_scale := max(0.2, script_scale)
    index_font_size := max(1.0, font_size * index_scale)
    index_ascent, index_descent := style_ascent_descent(script_style, index_font_size)

    content_ascent := child_program^.ascent
    content_descent := child_program^.descent
    bar_thickness := max(1.0, cmd.accent_thickness * font_size)
    bar_offset := max(0.0, cmd.accent_offset * font_size)
    ascent := max(content_ascent, content_ascent + bar_offset + bar_thickness * 0.5)
    if index_cols > 0 {
        index_top_from_baseline := content_ascent * 0.62 + index_ascent * 0.50
        ascent = max(ascent, index_top_from_baseline + script_top_pad)
    }
    root_low_offset := radical_root_low_offset(font_size, content_descent)
    hook_stroke := max(bar_thickness, bar_thickness * 1.25)
    descent := max(content_descent, root_low_offset + hook_stroke * 0.5)
    if index_cols > 0 {
        descent = max(descent, index_descent * 0.2)
    }

    base_advance := effective_advance(style, cache^.last_wrap_advance)
    index_advance :=
        effective_advance(script_style, cache^.last_wrap_advance) * index_scale
    index_width := f32(index_cols) * index_advance
    lead_width := max(
        radical_lead_width(font_size, base_advance),
        index_width + max(1.0, base_advance * 1.05))
    front_padding, back_padding := radical_side_paddings(font_size, base_advance)
    draw_width := lead_width + child_program^.draw_width + front_padding + back_padding
    accent_pad := accent_script_clearance(font_size, script_scale, false)

    return core.Dynview_Layout_Item{
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
        visual_padding_top = max(child_program^.visual_padding_top,
            max(script_top_pad, accent_pad)),
        visual_padding_bottom = max(child_program^.visual_padding_bottom,
            max(script_bottom_pad, accent_pad)),
    }, true
}

//   Build one layout-like child item for the command kinds supported inside math blocks.
//   Uniform handler shape for building one math-program layout item.
Math_Program_Item_Handler :: proc(
    cache: ^core.Dynview_Compile_Cache,
    buffer: ^core.Dynview_Command_Buffer,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> (core.Dynview_Layout_Item, bool)

//   Adapt the text-run item builder (no style-independent result) to the table.
math_program_text_item_entry :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    buffer: ^core.Dynview_Command_Buffer,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> (core.Dynview_Layout_Item, bool) {
    return math_program_text_item(cache, buffer, cmd, style, font_size), true
}

//   Adapt the script-attach item builder (resolves its own style) to the table.
math_program_script_item_entry :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    buffer: ^core.Dynview_Command_Buffer,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> (core.Dynview_Layout_Item, bool) {
    return math_program_recursive_script_item(cache, buffer, cmd, font_size)
}

//   Adapt the accent-bar item builder (resolves its own style) to the table.
math_program_accent_item_entry :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    buffer: ^core.Dynview_Command_Buffer,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> (core.Dynview_Layout_Item, bool) {
    return math_program_recursive_accent_item(cache, buffer, cmd, font_size)
}

//   Adapt the large-op item builder (returns no bool) to the table shape.
math_program_large_op_item_entry :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    buffer: ^core.Dynview_Command_Buffer,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> (core.Dynview_Layout_Item, bool) {
    return math_program_large_op_item(cache, buffer, cmd, style, font_size), true
}

//   Dispatch table mapping each recursive math command kind to its item builder.
//   Non-math kinds map to nil and are rejected by the caller.
MATH_PROGRAM_ITEM_HANDLERS :: [core.Dynview_Command_Kind]Math_Program_Item_Handler{
    .BeginBlock = nil, .EndBlock = nil, .CopyableTextRun = nil, .LineBreak = nil,
    .Divider = nil, .MathBlock = nil, .InlineLine = nil, .InlineBox = nil,
    .InlineCircle = nil, .InlineFilledBox = nil, .InlineFilledCircle = nil,
    .InlinePieSection = nil, .InlinePerpendicular = nil, .InlineTriangle = nil,
    .InlinePentagon = nil,
    .TextRun = math_program_text_item_entry,
    .MathGlyphRun = math_program_text_item_entry,
    .ScriptAttachRecursive = math_program_script_item_entry,
    .FracRecursive = math_program_recursive_fraction_item,
    .StretchDelimiterRecursive = math_program_recursive_stretch_delimiter_item,
    .MatrixRecursive = math_program_recursive_matrix_item,
    .LargeOpRecursive = math_program_large_op_item_entry,
    .AccentBarRecursive = math_program_accent_item_entry,
    .RadicalBarRecursive = math_program_recursive_radical_item,
}

//   Build one layout item for a math-program command using the matching builder.
math_program_item :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    buffer: ^core.Dynview_Command_Buffer,
    cmd: core.Dynview_Command,
    font_size: f32) -> (core.Dynview_Layout_Item, bool) {

    handlers := MATH_PROGRAM_ITEM_HANDLERS
    handler := handlers[cmd.kind]
    if handler == nil {
        return core.Dynview_Layout_Item{}, false
    }
    style := style_by_id(cmd.style_id)
    return handler(cache, buffer, cmd, style, font_size)
}

//   Measure one flat child-command math program and cache its deterministic outer metrics.
measure_math_program :: proc(
    cache: ^core.Dynview_Compile_Cache,
    buffer: ^core.Dynview_Command_Buffer,
    program: ^core.Dynview_Math_Program,
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
        item, ok := math_program_item(cache, buffer, cmd, font_size)
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

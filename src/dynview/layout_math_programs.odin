package dynview

import "../core"

//   Build one layout-like child item for the command kinds supported inside math blocks.
//   Uniform handler shape for building one math-program layout item.
Math_Program_Item_Handler :: #type proc(
    cache: ^core.Dynview_Compile_Cache,
    buffer: ^core.Dynview_Command_Buffer,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> (core.Dynview_Layout_Item, bool)

//   Dispatch table mapping each recursive math command kind to its item builder.
//   Non-math kinds map to nil and are rejected by the caller.
MATH_PROGRAM_ITEM_HANDLERS :: [core.Dynview_Command_Kind]Math_Program_Item_Handler{
    .Begin_Block = nil, .End_Block = nil, .Copyable_Text_Run = nil, .Line_Break = nil,
    .Divider = nil, .Math_Block = nil, .Inline_Line = nil, .Inline_Box = nil,
    .Inline_Circle = nil, .Inline_Filled_Box = nil, .Inline_Filled_Circle = nil,
    .Inline_Pie_Section = nil, .Inline_Perpendicular = nil, .Inline_Triangle = nil,
    .Inline_Pentagon = nil,
    .Text_Run = math_program_text_item_entry,
    .Math_Glyph_Run = math_program_text_item_entry,
    .Script_Attach = math_program_script_item_entry,
    .Frac = math_program_recursive_fraction_item,
    .Stretch_Delimiter = math_program_recursive_stretch_delimiter_item,
    .Matrix = math_program_recursive_matrix_item,
    .Large_Op = math_program_large_op_item_entry,
    .Accent_Bar = math_program_accent_item_entry,
    .Radical_Bar = math_program_recursive_radical_item,
}

//   Aggregated per-column and per-row cell metrics for one matrix layout.
Matrix_Cell_Dims :: struct {
    col_widths:  [16]f32,
    row_ascents: [16]f32,
    row_descents: [16]f32,
    top_pad:     f32,
    bottom_pad:  f32,
}

Script_Metrics :: struct {
    cols: int,
    scale, ascent, descent, top_pad, bottom_pad, advance: f32,
}

Math_Measure_Context :: struct {
    cache: ^core.Dynview_Compile_Cache,
    buffer: ^core.Dynview_Command_Buffer,
    font_size: f32,
}

Stretch_Delimiter_Content :: struct {
    width, ascent, descent, top_pad, bottom_pad: f32,
}

Radical_Geometry :: struct {
    draw_width, ascent, descent, top_pad, bottom_pad: f32,
}

Fraction_Item_Metrics :: struct {
    numerator, denominator: ^core.Dynview_Math_Program,
    draw_width, ascent, descent, visual_pad: f32,
}

Script_Attach_Metrics :: struct {
    scale, draw_width, ascent, descent, top_pad, bottom_pad: f32,
}

Large_Op_Metrics :: struct {
    scale, draw_width, ascent, descent, top_pad, bottom_pad: f32,
}

Matrix_Item_Metrics :: struct {
    rows, cols: int,
    draw_width, total_height, top_pad, bottom_pad: f32,
}

Stretch_Delimiter_Dimensions :: struct {
    font_size, content_height, content_width: f32,
}

Matrix_Program :: struct {
    program: ^core.Dynview_Math_Program,
    rows, cols: int,
}

Radical_Geometry_Context :: struct {
    cache: ^core.Dynview_Compile_Cache,
    buffer: ^core.Dynview_Command_Buffer,
    child: ^core.Dynview_Math_Program,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32,
}

//   Measure script text and its scaled typography for a recursive math item.
script_metrics :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    text: string,
    style_id: i32,
    scale, font_size: f32) -> Script_Metrics {

    resolved_scale := max(0.2, scale)
    style := style_by_id(style_id)
    scaled_font_size := max(1.0, font_size * resolved_scale)
    ascent, descent := style_ascent_descent(style, scaled_font_size)
    top_pad, bottom_pad := script_visual_padding(scaled_font_size)
    return Script_Metrics{
        cols = text_codepoint_count_span(text, 0, len(text)),
        scale = resolved_scale,
        ascent = ascent,
        descent = descent,
        top_pad = top_pad,
        bottom_pad = bottom_pad,
        advance = effective_advance(style, cache^.last_wrap_advance) * resolved_scale,
    }
}

// Reset a cache structure for the dynview layout engine
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
    kind := core.Dynview_Layout_Item_Kind.Text_Run
    if cmd.kind == .Math_Glyph_Run {
        kind = .Math_Glyph_Run
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
script_attach_item :: #force_inline proc(
    cmd: core.Dynview_Command,
    metrics: Script_Attach_Metrics) -> core.Dynview_Layout_Item {

    return core.Dynview_Layout_Item{
        kind = .Script_Attach,
        style_id = cmd.style_id,
        math_program_id = cmd.math_program_id,
        script_sup_text_offset = cmd.script_sup_text_offset,
        script_sup_text_len = cmd.script_sup_text_len,
        script_sub_text_offset = cmd.script_sub_text_offset,
        script_sub_text_len = cmd.script_sub_text_len,
        script_style_id = cmd.script_style_id, script_scale = metrics.scale,
        script_sup_raise = cmd.script_sup_raise, script_sub_drop = cmd.script_sub_drop,
        script_gap = cmd.script_gap, draw_width = metrics.draw_width,
        draw_height = metrics.ascent + metrics.descent,
        ascent = metrics.ascent, descent = metrics.descent,
        visual_padding_top = metrics.top_pad,
        visual_padding_bottom = metrics.bottom_pad,
    }
}

//   Calculate script placement dimensions around an already measured child program.
script_attach_metrics :: proc(
    cache: ^core.Dynview_Compile_Cache,
    buffer: ^core.Dynview_Command_Buffer,
    child: ^core.Dynview_Math_Program,
    cmd: core.Dynview_Command,
    font_size: f32) -> Script_Attach_Metrics {

    script_scale := max(0.2, cmd.script_scale)
    offsets := script_draw_offsets(
        font_size, script_scale, cmd.script_sup_raise, cmd.script_sub_drop)
    sup := script_metrics(cache, text_span_from_buffer(
        buffer, cmd.script_sup_text_offset, cmd.script_sup_text_len),
        cmd.script_style_id, script_scale, font_size)
    sub := script_metrics(cache, text_span_from_buffer(
        buffer, cmd.script_sub_text_offset, cmd.script_sub_text_len),
        cmd.script_style_id, script_scale, font_size)
    ascent := child^.ascent
    descent := child^.descent
    if sup.cols > 0 {
        ascent = max(ascent, sup.ascent + offsets.sup_raise_px + sup.top_pad)
    }
    if sub.cols > 0 {
        descent = max(descent, sub.descent + offsets.sub_drop_px + sub.bottom_pad)
    }
    cols := max(sup.cols, sub.cols)
    draw_width := child^.draw_width
    if cols > 0 {
        draw_width += max(1.0, cmd.script_gap * font_size) +
            f32(cols) * max(sup.advance, sub.advance)
    }
    return {
        scale = script_scale, draw_width = draw_width, ascent = ascent,
        descent = descent,
        top_pad = max(child^.visual_padding_top, sup.top_pad),
        bottom_pad = max(child^.visual_padding_bottom, sub.bottom_pad),
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

    return script_attach_item(
        cmd, script_attach_metrics(cache, buffer, child_program, cmd, font_size)), true
}

//   Build one layout-like item for a display-style large operator with stacked limits.
large_op_item :: #force_inline proc(
    cmd: core.Dynview_Command,
    metrics: Large_Op_Metrics) -> core.Dynview_Layout_Item {

    return core.Dynview_Layout_Item{
        kind = .Large_Op, style_id = cmd.style_id, text_offset = cmd.text_offset,
        text_len = cmd.text_len, script_sup_text_offset = cmd.script_sup_text_offset,
        script_sup_text_len = cmd.script_sup_text_len,
        script_sub_text_offset = cmd.script_sub_text_offset,
        script_sub_text_len = cmd.script_sub_text_len,
        script_style_id = cmd.script_style_id, script_scale = metrics.scale,
        script_gap = cmd.script_gap, large_op_kind = cmd.large_op_kind,
        draw_width = metrics.draw_width, draw_height = metrics.ascent + metrics.descent,
        ascent = metrics.ascent, descent = metrics.descent,
        visual_padding_top = metrics.top_pad, visual_padding_bottom = metrics.bottom_pad,
    }
}

//   Calculate glyph and stacked-limit dimensions for one large operator.
large_op_metrics :: proc(
    cache: ^core.Dynview_Compile_Cache,
    buffer: ^core.Dynview_Command_Buffer,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> Large_Op_Metrics {

    limit_scale := large_op_limit_scale(max(0.2, cmd.script_scale))
    sup := script_metrics(cache, text_span_from_buffer(
        buffer, cmd.script_sup_text_offset, cmd.script_sup_text_len),
        cmd.script_style_id, limit_scale, font_size)
    sub := script_metrics(cache, text_span_from_buffer(
        buffer, cmd.script_sub_text_offset, cmd.script_sub_text_len),
        cmd.script_style_id, limit_scale, font_size)
    glyph_scale := large_op_glyph_scale(cmd.large_op_kind)
    glyph_ascent, glyph_descent := style_ascent_descent(
        style, max(1.0, font_size * glyph_scale))
    glyph_cols := max(1, text_codepoint_count_span(
        text_for_command(buffer, cmd), 0, len(text_for_command(buffer, cmd))))
    glyph_width := f32(glyph_cols) *
        effective_advance(style, cache^.last_wrap_advance) * glyph_scale
    gap := large_op_limit_gap_for_kind(cmd.large_op_kind, font_size, cmd.script_gap)
    ascent := glyph_ascent if sup.cols == 0 else
        glyph_ascent + sup.ascent + sup.descent + gap
    descent := glyph_descent if sub.cols == 0 else
        glyph_descent + sub.ascent + sub.descent + gap
    return {
        scale = limit_scale,
        draw_width = max(glyph_width, max(f32(sup.cols) * sup.advance,
            f32(sub.cols) * sub.advance)),
        ascent = ascent, descent = descent,
        top_pad = sup.top_pad, bottom_pad = sub.bottom_pad,
    }
}

//   Build one layout-like item for a display-style large operator with stacked limits.
//   Build one layout-like item for a display-style large operator with stacked limits.
math_program_large_op_item :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    buffer: ^core.Dynview_Command_Buffer,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> core.Dynview_Layout_Item {

    return large_op_item(cmd, large_op_metrics(cache, buffer, cmd, style, font_size))
}

//   Build one layout-like item for a recursive fraction with centered numerator and denominator.
fraction_item :: #force_inline proc(
    cmd: core.Dynview_Command,
    metrics: Fraction_Item_Metrics) -> core.Dynview_Layout_Item {

    return core.Dynview_Layout_Item{
        kind = .Frac,
        style_id = cmd.style_id,
        math_program_id = cmd.math_program_id,
        secondary_math_program_id = cmd.secondary_math_program_id,
        accent_style_id = cmd.accent_style_id,
        accent_thickness = cmd.accent_thickness,
        draw_width = metrics.draw_width,
        draw_height = metrics.ascent + metrics.descent,
        ascent = metrics.ascent,
        descent = metrics.descent,
        visual_padding_top = max(max(metrics.numerator^.visual_padding_top,
            metrics.denominator^.visual_padding_top), metrics.visual_pad),
        visual_padding_bottom = max(max(metrics.numerator^.visual_padding_bottom,
            metrics.denominator^.visual_padding_bottom), metrics.visual_pad),
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

    return fraction_item(cmd, {
        numerator = numerator_program,
        denominator = denominator_program,
        draw_width = draw_width,
        ascent = ascent,
        descent = descent,
        visual_pad = visual_pad,
    }), true
}

//   Build one layout-like item for a recursive stretch-delimiter wrapper.
stretch_delimiter_content :: proc(
    cache: ^core.Dynview_Compile_Cache,
    buffer: ^core.Dynview_Command_Buffer,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> (Stretch_Delimiter_Content, bool) {

    ascent, descent := style_ascent_descent(style, font_size)
    content := Stretch_Delimiter_Content{ascent = ascent, descent = descent}
    if cmd.math_program_id <= 0 {
        return content, true
    }

    child_program, ok := math_program_from_command(cache, cmd)
    if !ok || !measure_math_program(cache, buffer, child_program, font_size) {
        return {}, false
    }
    return Stretch_Delimiter_Content{
        width = child_program^.draw_width,
        ascent = child_program^.ascent,
        descent = child_program^.descent,
        top_pad = child_program^.visual_padding_top,
        bottom_pad = child_program^.visual_padding_bottom,
    }, true
}

//   Calculate the combined width of delimiter glyphs and their content padding.
stretch_delimiter_widths :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    dimensions: Stretch_Delimiter_Dimensions) -> f32 {

    base_advance := effective_advance(style, cache^.last_wrap_advance)
    side_padding := stretch_delimiter_side_padding(dimensions.font_size, base_advance)
    left_width := stretch_delimiter_width(
        style, cache^.last_wrap_advance, dimensions.font_size,
        dimensions.content_height, cmd.accent_mode)
    right_width := stretch_delimiter_width(
        style, cache^.last_wrap_advance, dimensions.font_size,
        dimensions.content_height, cmd.radical_mode)
    return max(dimensions.content_width + left_width + right_width + side_padding * 2.0,
        base_advance)
}

//   Build one layout-like item for a recursive stretch-delimiter wrapper.
math_program_recursive_stretch_delimiter_item :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    buffer: ^core.Dynview_Command_Buffer,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> (core.Dynview_Layout_Item, bool) {

    content, ok := stretch_delimiter_content(cache, buffer, cmd, style, font_size)
    if !ok {
        return core.Dynview_Layout_Item{}, false
    }

    content_height := content.ascent + content.descent
    draw_width := stretch_delimiter_widths(
        cache, cmd, style, {font_size, content_height, content.width})
    return core.Dynview_Layout_Item{
        kind = .Stretch_Delimiter,
        style_id = cmd.style_id,
        math_program_id = cmd.math_program_id,
        accent_mode = cmd.accent_mode,
        radical_mode = cmd.radical_mode,
        draw_width = draw_width,
        draw_height = content_height,
        ascent = content.ascent,
        descent = content.descent,
        visual_padding_top = content.top_pad,
        visual_padding_bottom = content.bottom_pad,
    }, true
}

//   Measure every matrix cell, accumulating column widths and row extents.
measure_matrix_cells :: proc(
    ctx: Math_Measure_Context,
    cell_program: ^core.Dynview_Math_Program,
    rows, cols: int,
    dims: ^Matrix_Cell_Dims) -> bool {

    for row in 0..<rows {
        for col in 0..<cols {
            cell_index := row * cols + col
            cmd_index := cell_program^.command_start + cell_index
            cell_cmd := ctx.cache^.math_commands[cmd_index]
            cell_item, cell_ok := math_program_item(
                ctx.cache, ctx.buffer, cell_cmd, ctx.font_size)
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
matrix_item :: #force_inline proc(
    cmd: core.Dynview_Command,
    metrics: Matrix_Item_Metrics) -> core.Dynview_Layout_Item {

    ascent := metrics.total_height * 0.5
    return core.Dynview_Layout_Item{
        kind = .Matrix, style_id = cmd.style_id, math_program_id = cmd.math_program_id,
        script_sub_text_offset = cmd.script_sub_text_offset,
        script_sub_text_len = cmd.script_sub_text_len,
        accent_mode = i32(metrics.rows), radical_mode = i32(metrics.cols),
        draw_width = metrics.draw_width, draw_height = metrics.total_height,
        ascent = ascent, descent = metrics.total_height - ascent,
        visual_padding_top = metrics.top_pad, visual_padding_bottom = metrics.bottom_pad,
    }
}

//   Resolve and measure a matrix child program with a matching row-major cell count.
matrix_program_from_command :: proc(
    cache: ^core.Dynview_Compile_Cache,
    buffer: ^core.Dynview_Command_Buffer,
    cmd: core.Dynview_Command,
    font_size: f32) -> (Matrix_Program, bool) {

    dims := matrix_dims_from_command(buffer, cmd)
    if !dims.ok || dims.rows > 16 || dims.cols > 16 {
        return {}, false
    }
    program, ok := math_program_from_command(cache, cmd)
    if !ok || !measure_math_program(cache, buffer, program, font_size) ||
        program^.command_count != dims.rows * dims.cols {
        return {}, false
    }
    return {program, dims.rows, dims.cols}, true
}

//   Build one layout-like item for a recursive matrix with row-major child cells.
math_program_recursive_matrix_item :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    buffer: ^core.Dynview_Command_Buffer,
    cmd: core.Dynview_Command,
    style: Dynview_Text_Style,
    font_size: f32) -> (core.Dynview_Layout_Item, bool) {

    matrix_info, ok := matrix_program_from_command(cache, buffer, cmd, font_size)
    if !ok {
        return core.Dynview_Layout_Item{}, false
    }

    cell_dims := Matrix_Cell_Dims{}
    if !measure_matrix_cells({cache, buffer, font_size}, matrix_info.program,
        matrix_info.rows, matrix_info.cols, &cell_dims) {
        return core.Dynview_Layout_Item{}, false
    }
    top_pad := cell_dims.top_pad
    bottom_pad := cell_dims.bottom_pad

    base_advance := effective_advance(style, cache^.last_wrap_advance)
    draw_width, total_height := matrix_aggregate_dims(
        &cell_dims,
        matrix_info.rows,
        matrix_info.cols,
        font_size, base_advance)

    return matrix_item(cmd, {
        rows = matrix_info.rows,
        cols = matrix_info.cols,
        draw_width = max(draw_width, base_advance),
        total_height = total_height,
        top_pad = top_pad,
        bottom_pad = bottom_pad,
    }), true
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
        kind = .Accent_Bar,
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
radical_item :: #force_inline proc(
    cmd: core.Dynview_Command,
    geometry: Radical_Geometry,
    script_scale: f32) -> core.Dynview_Layout_Item {

    return core.Dynview_Layout_Item{
        kind = .Radical_Bar,
        style_id = cmd.style_id,
        math_program_id = cmd.math_program_id,
        script_style_id = cmd.script_style_id, script_scale = script_scale,
        script_sup_raise = cmd.script_sup_raise, script_sub_drop = cmd.script_sub_drop,
        radical_mode = cmd.radical_mode,
        radical_index_text_offset = cmd.radical_index_text_offset,
        radical_index_text_len = cmd.radical_index_text_len,
        accent_style_id = cmd.accent_style_id, accent_thickness = cmd.accent_thickness,
        accent_offset = cmd.accent_offset, draw_width = geometry.draw_width,
        draw_height = geometry.ascent + geometry.descent,
        ascent = geometry.ascent, descent = geometry.descent,
        visual_padding_top = geometry.top_pad,
        visual_padding_bottom = geometry.bottom_pad,
    }
}

//   Calculate radical bar, root hook, and optional index geometry around a child.
radical_geometry :: proc(
    ctx: Radical_Geometry_Context) -> Radical_Geometry {

    scale := max(0.2, ctx.cmd.script_scale)
    index := script_metrics(ctx.cache, text_span_from_buffer(
        ctx.buffer, ctx.cmd.radical_index_text_offset, ctx.cmd.radical_index_text_len),
        ctx.cmd.script_style_id, scale, ctx.font_size)
    offsets := script_draw_offsets(ctx.font_size, scale, ctx.cmd.script_sup_raise,
        ctx.cmd.script_sub_drop)
    script_top, script_bottom := script_visual_padding(offsets.script_font_size)
    stroke := max(1.0, ctx.cmd.accent_thickness * ctx.font_size)
    ascent := max(ctx.child^.ascent, ctx.child^.ascent +
        max(0.0, ctx.cmd.accent_offset * ctx.font_size) + stroke * 0.5)
    root_low := radical_root_low_offset(ctx.font_size, ctx.child^.descent)
    descent := max(ctx.child^.descent, root_low +
        max(stroke, stroke * 1.25) * 0.5)
    if index.cols > 0 {
        ascent = max(ascent, ctx.child^.ascent * 0.62 + index.ascent * 0.50 + script_top)
        descent = max(descent, index.descent * 0.2)
    }
    advance := effective_advance(ctx.style, ctx.cache^.last_wrap_advance)
    lead := max(radical_lead_width(ctx.font_size, advance),
        f32(index.cols) * index.advance + max(1.0, advance * 1.05))
    front, back := radical_side_paddings(ctx.font_size, advance)
    accent_pad := accent_script_clearance(ctx.font_size, scale, false)
    return {
        draw_width = lead + ctx.child^.draw_width + front + back,
        ascent = ascent, descent = descent,
        top_pad = max(ctx.child^.visual_padding_top, max(script_top, accent_pad)),
        bottom_pad = max(
            ctx.child^.visual_padding_bottom, max(script_bottom, accent_pad)),
    }
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

    script_scale := max(0.2, cmd.script_scale)
    return radical_item(
        cmd, radical_geometry({cache, buffer, child_program, cmd, style, font_size}),
        script_scale), true
}

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
math_program_is_measurable :: #force_inline proc(
    cache: ^core.Dynview_Compile_Cache,
    buffer: ^core.Dynview_Command_Buffer,
    program: ^core.Dynview_Math_Program) -> bool {

    return cache != nil && buffer != nil && program != nil && program^.valid &&
        program^.command_start >= 0 && program^.command_count > 0 &&
        program^.command_start + program^.command_count <= cache^.math_command_count
}

//   Measure one flat child-command math program and cache its deterministic outer metrics.
measure_math_program :: proc(
    cache: ^core.Dynview_Compile_Cache,
    buffer: ^core.Dynview_Command_Buffer,
    program: ^core.Dynview_Math_Program,
    font_size: f32) -> bool {

    if !math_program_is_measurable(cache, buffer, program) {
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

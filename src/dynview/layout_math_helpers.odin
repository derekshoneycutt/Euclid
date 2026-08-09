package dynview

import "../core"

Dynview_Matrix_Column_Alignment :: core.Dynview_Matrix_Column_Alignment

//   Return style-adjusted horizontal advance for one column unit.
effective_advance :: #force_inline proc(style: Dynview_Text_Style, wrap_advance: f32) -> f32 {
    return max(1.0, wrap_advance * max(0.5, style.wrap_scale))
}

//   Return style-aware ascent/descent estimates from active font size.
style_ascent_descent :: #force_inline proc(style: Dynview_Text_Style, font_size: f32) -> (f32, f32) {
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
script_draw_offsets :: #force_inline proc(
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
script_visual_padding :: #force_inline proc(script_font_size: f32) -> (f32, f32) {
    top_pad := max(0.6, script_font_size * 0.10)
    bottom_pad := max(0.8, script_font_size * 0.14)
    return top_pad, bottom_pad
}

//   Add extra accent-bar clearance when script glyphs are present.
accent_script_clearance :: #force_inline proc(
    font_size, script_scale: f32,
    has_scripts: bool) -> f32 {

    if !has_scripts {
        return 0
    }

    script_font_size := max(1.0, font_size * max(0.2, script_scale))
    return max(0.5, script_font_size * 0.08)
}

//   Return reserved leading width for one rendered square-root marker.
radical_lead_width :: #force_inline proc(font_size, base_advance: f32) -> f32 {
    return max(base_advance * 1.48, font_size * 0.92)
}

//   Return asymmetric horizontal side padding for radical items.
radical_side_paddings :: #force_inline proc(font_size, base_advance: f32) -> (f32, f32) {
    front_padding := max(1.0, max(base_advance * 0.5, font_size * 0.5))
    back_padding := max(0.1, max(base_advance * 0.1, font_size * 0.075))
    return front_padding, back_padding
}

//   Return baseline-to-hook-low offset for one radical sign, scaled by content depth.
radical_root_low_offset :: #force_inline proc(font_size, content_descent: f32) -> f32 {
    base_offset := font_size * 0.375
    stretched_offset := content_descent * 0.72 + font_size * 0.04
    return max(base_offset, stretched_offset)
}

//   Return small horizontal side padding for fraction composition.
fraction_side_padding :: #force_inline proc(font_size, base_advance: f32) -> f32 {
    return max(0.5, max(base_advance * 0.12, font_size * 0.08))
}

//   Return small vertical gap between fraction divider and child blocks.
fraction_vertical_gap :: #force_inline proc(font_size: f32) -> f32 {
    return max(0.5, font_size * 0.10)
}

//   Return small horizontal side padding for stretch-delimiter wrappers.
stretch_delimiter_side_padding :: #force_inline proc(font_size, base_advance: f32) -> f32 {
    return max(0.5, max(base_advance * 0.12, font_size * 0.08))
}

//   Return horizontal gap used between matrix columns.
matrix_column_gap :: #force_inline proc(font_size, base_advance: f32) -> f32 {
    return max(1.0, max(base_advance * 0.38, font_size * 0.34))
}

//   Return vertical gap used between matrix rows.
matrix_row_gap :: #force_inline proc(font_size: f32) -> f32 {
    return max(0.8, font_size * 0.28)
}

//   Parse one positive decimal integer from text.
parse_positive_int :: #force_inline proc(text: string) -> (int, bool) {
    if len(text) <= 0 {
        return 0, false
    }

    value := 0
    for c in text {
        if c < '0' || c > '9' {
            return 0, false
        }
        value = value * 10 + int(c - '0')
    }
    return value, value > 0
}

//   Read matrix row/column metadata from command text fields.
matrix_dims_from_command :: #force_inline proc(
    buffer: ^core.Dynview_Command_Buffer,
    cmd: core.Dynview_Command) -> (int, int, bool) {

    rows_text := text_span_from_buffer(
        buffer,
        cmd.radical_index_text_offset,
        cmd.radical_index_text_len)
    cols_text := text_span_from_buffer(
        buffer,
        cmd.script_sup_text_offset,
        cmd.script_sup_text_len)
    rows, rows_ok := parse_positive_int(rows_text)
    cols, cols_ok := parse_positive_int(cols_text)
    return rows, cols, rows_ok && cols_ok
}

//   Decode strict array alignment metadata; return all-center on any invalid shape.
decode_matrix_column_alignments :: #force_inline proc(
    buffer: ^core.Dynview_Command_Buffer,
    cmd: core.Dynview_Command,
    cols: int) -> ([16]Dynview_Matrix_Column_Alignment, bool) {

    alignments: [16]Dynview_Matrix_Column_Alignment
    if cols <= 0 || cols > 16 {
        return alignments, false
    }

    for col in 0..<cols {
        alignments[col] = .Center
    }

    preamble := text_span_from_buffer(
        buffer,
        cmd.script_sub_text_offset,
        cmd.script_sub_text_len)
    if len(preamble) <= 0 {
        return alignments, true
    }
    if len(preamble) != cols {
        return alignments, false
    }

    for col in 0..<cols {
        switch preamble[col] {
        case 'l':
            alignments[col] = .Left
        case 'c':
            alignments[col] = .Center
        case 'r':
            alignments[col] = .Right
        case:
            for idx in 0..<cols {
                alignments[idx] = .Center
            }
            return alignments, false
        }
    }

    return alignments, true
}

//   Resolve one cell x-position within a matrix column using l/c/r alignment rules.
matrix_aligned_cell_x :: #force_inline proc(
    col_x, column_width, cell_width: f32,
    alignment: Dynview_Matrix_Column_Alignment) -> f32 {

    switch alignment {
    case .Left:
        return col_x
    case .Right:
        return col_x + column_width - cell_width
    case .Center:
    }
    return col_x + (column_width - cell_width) * 0.5
}

//   Return delimiter draw text for one supported delimiter kind.
delimiter_text :: #force_inline proc(delimiter_kind: i32) -> string {
    switch delimiter_kind {
    case DELIMITER_KIND_LEFT_PAREN:
        return "("
    case DELIMITER_KIND_RIGHT_PAREN:
        return ")"
    case DELIMITER_KIND_LEFT_BRACKET:
        return "["
    case DELIMITER_KIND_RIGHT_BRACKET:
        return "]"
    case DELIMITER_KIND_LEFT_BRACE:
        return "{"
    case DELIMITER_KIND_RIGHT_BRACE:
        return "}"
    case DELIMITER_KIND_VERT:
        return "|"
    case DELIMITER_KIND_DOUBLE_VERT:
        return "‖"
    case DELIMITER_KIND_LEFT_CEIL:
        return "⌈"
    case DELIMITER_KIND_RIGHT_CEIL:
        return "⌉"
    case DELIMITER_KIND_LEFT_FLOOR:
        return "⌊"
    case DELIMITER_KIND_RIGHT_FLOOR:
        return "⌋"
    case DELIMITER_KIND_LEFT_ANGLE:
        return "⟨"
    case DELIMITER_KIND_RIGHT_ANGLE:
        return "⟩"
    }
    return ""
}

//   Return family type for one delimiter kind.
delimiter_family :: #force_inline proc(delimiter_kind: i32) -> Dynview_Delimiter_Family {
    switch delimiter_kind {
    case DELIMITER_KIND_LEFT_PAREN, DELIMITER_KIND_RIGHT_PAREN:
        return .Paren
    case DELIMITER_KIND_LEFT_BRACKET, DELIMITER_KIND_RIGHT_BRACKET:
        return .Bracket
    case DELIMITER_KIND_LEFT_BRACE, DELIMITER_KIND_RIGHT_BRACE:
        return .Brace
    case DELIMITER_KIND_VERT:
        return .Vert
    case DELIMITER_KIND_DOUBLE_VERT:
        return .DoubleVert
    case DELIMITER_KIND_LEFT_CEIL, DELIMITER_KIND_RIGHT_CEIL:
        return .Ceil
    case DELIMITER_KIND_LEFT_FLOOR, DELIMITER_KIND_RIGHT_FLOOR:
        return .Floor
    case DELIMITER_KIND_LEFT_ANGLE, DELIMITER_KIND_RIGHT_ANGLE:
        return .Angle
    }
    return .None
}

//   Return true when delimiter kind is a right-side shape.
delimiter_is_right :: #force_inline proc(delimiter_kind: i32) -> bool {
    switch delimiter_kind {
    case DELIMITER_KIND_RIGHT_PAREN,
        DELIMITER_KIND_RIGHT_BRACKET,
        DELIMITER_KIND_RIGHT_BRACE,
        DELIMITER_KIND_RIGHT_CEIL,
        DELIMITER_KIND_RIGHT_FLOOR,
        DELIMITER_KIND_RIGHT_ANGLE:
        return true
    }
    return false
}

//   Return one recipe-like base width factor keyed by delimiter family.
delimiter_base_width_factor :: #force_inline proc(family: Dynview_Delimiter_Family) -> f32 {
    switch family {
    case .Paren:
        return 0.42
    case .Bracket:
        return 0.40
    case .Brace:
        return 0.34
    case .Vert:
        return 0.24
    case .DoubleVert:
        return 0.34
    case .Ceil, .Floor:
        return 0.40
    case .Angle:
        return 0.46
    case .None:
    }
    return 0
}

//   Return scaled delimiter width from one child content-height target.
stretch_delimiter_width :: #force_inline proc(
    style: Dynview_Text_Style,
    wrap_advance, font_size, content_height: f32,
    delimiter_kind: i32) -> f32 {

    if delimiter_kind == DELIMITER_KIND_NONE {
        return 0
    }

    family := delimiter_family(delimiter_kind)
    if family == .None {
        return 0
    }

    base_advance := effective_advance(style, wrap_advance)
    base_width := max(base_advance * 0.2, font_size * delimiter_base_width_factor(family))
    raw_scale := max(1.0, content_height / max(1.0, font_size))
    width_scale := min(1.7, 1.0 + (raw_scale - 1.0) * 0.28)
    return max(1.0, base_width * width_scale)
}

//   Return glyph scale factor for display-style large operators.
large_op_glyph_scale :: #force_inline proc(large_op_kind: i32) -> f32 {
    switch large_op_kind {
    case LARGE_OP_KIND_SUM, LARGE_OP_KIND_PROD:
        return 1.35
    case LARGE_OP_KIND_INT:
        return 1.65
    case LARGE_OP_KIND_LIM:
        return 1.10
    }
    return 1.28
}

//   Return limit text scale factor for display-style large operators.
large_op_limit_scale :: #force_inline proc(script_scale: f32) -> f32 {
    return max(0.68, script_scale * 1.12)
}

//   Return vertical gap between large-operator glyph and stacked limits.
large_op_limit_gap :: #force_inline proc(font_size, script_gap: f32) -> f32 {
    return max(0.75, font_size * 0.12 + script_gap * font_size * 0.85)
}

//   Return the stacked-limit gap for one large operator kind.
large_op_limit_gap_for_kind :: #force_inline proc(
    large_op_kind: i32,
    font_size, script_gap: f32) -> f32 {

    gap := large_op_limit_gap(font_size, script_gap)
    if large_op_kind == LARGE_OP_KIND_INT {
        return max(0.01, gap * 0.22)
    }
    return gap
}

//   Return default block format values keyed by block kind.
block_format_for_kind :: #force_inline proc(block_kind: i32) -> Dynview_Block_Format {
    switch block_kind {
    case 1: // BRIDGE_DYNVIEW_BLOCK_INPUT
        return Dynview_Block_Format{
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
style_with_block_format :: #force_inline proc(
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

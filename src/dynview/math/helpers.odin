package dynview_math

import app_core "../../core"
import dyncore "../core"

//   Draw text for each delimiter kind, indexed by kind minus one.
DELIMITER_TEXTS :: [DELIMITER_KIND_COUNT]string{
    "(", ")", "[", "]", "{", "}", "|", "‖", "⌈", "⌉", "⌊", "⌋", "⟨", "⟩",
}

Dynview_Matrix_Column_Alignment :: app_core.Dynview_Matrix_Column_Alignment

Script_Draw_Offsets :: struct {
    script_font_size: f32,
    sup_raise_px:     f32,
    sub_drop_px:      f32,
}

//   Resolve script draw offsets using one shared model for layout and rendering.
script_draw_offsets :: #force_inline proc(
    font_size, script_scale, sup_raise, sub_drop: f32) -> Script_Draw_Offsets {

    script_font_size := max(1.0, font_size * max(0.2, script_scale))
    sup_vertical_bias := max(0.6, script_font_size * 0.08)
    sub_vertical_bias := max(0.9, script_font_size * 0.16)
    sub_lift_px := max(0.5, script_font_size * 0.06)
    sup_raise_px := max(0.0, sup_raise * font_size - sup_vertical_bias)
    sub_drop_px := max(0.0, sub_drop * font_size - sub_vertical_bias - sub_lift_px)
    return Script_Draw_Offsets{script_font_size, sup_raise_px, sub_drop_px}
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

//   Return content clearance for one visible vertical delimiter or table rule.
vertical_math_content_clearance :: #force_inline proc(
    font_size, base_advance: f32) -> f32 {

    return max(2.0, max(base_advance * 0.60, font_size * 0.32))
}

//   Return horizontal gap used between matrix columns.
matrix_column_gap :: #force_inline proc(font_size, base_advance: f32) -> f32 {
    return max(1.0, max(base_advance * 0.38, font_size * 0.34))
}

//   Return vertical gap used between matrix rows.
matrix_row_gap :: #force_inline proc(font_size: f32) -> f32 {
    return max(0.8, font_size * 0.28)
}

//   Return the environment-selected default gap between table rows.
math_table_default_row_gap :: #force_inline proc(
    spacing: app_core.Dynview_Math_Table_Row_Spacing, font_size: f32) -> f32 {

    switch spacing {
    case .Matrix: return matrix_row_gap(font_size)
    case .Tight: return max(0.6, font_size * 0.18)
    case .Cases: return max(0.8, font_size * 0.32)
    case .Alignment: return max(0.8, font_size * 0.34)
    }
    return matrix_row_gap(font_size)
}

//   Return minimum ascent and descent for one table row strut policy.
math_table_row_strut :: #force_inline proc(
    spacing: app_core.Dynview_Math_Table_Row_Spacing,
    font_size: f32) -> (ascent, descent: f32) {

    switch spacing {
    case .Tight: return font_size * 0.60, font_size * 0.20
    case .Cases: return font_size * 0.75, font_size * 0.30
    case .Alignment: return font_size * 0.80, font_size * 0.30
    case .Matrix: return font_size * 0.70, font_size * 0.30
    }
    return font_size * 0.70, font_size * 0.30
}

//   Resolve one typed table length against the active math font size.
math_table_length_px :: #force_inline proc(
    length: app_core.Dynview_Math_Length, font_size, default_value: f32) -> f32 {

    switch length.unit {
    case .Default: return default_value
    case .Zero: return 0
    case .Em: return length.value * font_size
    case .Ex: return length.value * font_size * 0.5
    case .Point: return length.value * 96.0 / 72.0
    }
    return 0
}

//   Return the stroke thickness used by table boundary rules.
math_table_rule_thickness :: #force_inline proc(font_size: f32) -> f32 {
    return max(1.0, font_size * 0.045)
}

//   Return the separation between paired table boundary rules.
math_table_rule_separation :: #force_inline proc(font_size: f32) -> f32 {
    return max(1.0, font_size * 0.12)
}

//   Resolve one complete column-boundary span including rules.
math_table_column_boundary_width :: #force_inline proc(
    descriptor: ^app_core.Dynview_Math_Table_Descriptor,
    boundary: int,
    font_size, base_advance: f32) -> f32 {

    default_gap: f32
    if boundary > 0 && boundary < descriptor^.columns {
        default_gap = matrix_column_gap(font_size, base_advance)
    }
    width := math_table_length_px(
        descriptor^.column_boundary_gaps[boundary], font_size, default_gap)
    count := int(descriptor^.vertical_rule_counts[boundary])
    if count > 0 {
        adjacent_cells := 2
        if boundary == 0 || boundary == descriptor^.columns {
            adjacent_cells = 1
        }
        clearance := vertical_math_content_clearance(font_size, base_advance)
        width = max(width, f32(adjacent_cells) * clearance)
        width += f32(count) * math_table_rule_thickness(font_size)
        width += f32(count - 1) * math_table_rule_separation(font_size)
    }
    return width
}

//   Resolve one row-boundary span including row additions and rules.
math_table_row_boundary_height :: #force_inline proc(
    descriptor: ^app_core.Dynview_Math_Table_Descriptor,
    boundary: int,
    font_size: f32) -> f32 {

    default_gap: f32
    if boundary > 0 && boundary < descriptor^.rows {
        default_gap = math_table_default_row_gap(descriptor^.row_spacing, font_size)
    }
    height := default_gap
    if boundary > 0 {
        height += math_table_length_px(
            descriptor^.row_extra_gaps[boundary - 1], font_size, 0)
    }
    count := int(descriptor^.horizontal_rule_counts[boundary])
    if count > 0 {
        height += f32(count) * math_table_rule_thickness(font_size)
        height += f32(count - 1) * math_table_rule_separation(font_size)
    }
    return max(0, height)
}

//   Resolve one matrix command's bounded native table descriptor.
matrix_descriptor_from_command :: #force_inline proc(
    cache: ^app_core.Dynview_Compile_Cache,
    cmd: app_core.Dynview_Command) -> (^app_core.Dynview_Math_Table_Descriptor, bool) {

    index := int(cmd.table_descriptor_index)
    if cache == nil || index < 0 || index >= cache^.math_table_descriptor_count {
        return nil, false
    }
    descriptor := &cache^.math_table_descriptors[index]
    return descriptor, descriptor^.rows > 0 && descriptor^.rows <= 16 &&
        descriptor^.columns > 0 && descriptor^.columns <= 16
}

//   Map one l/c/r alignment character to its matrix column alignment.
matrix_alignment_from_char :: #force_inline proc(
    ch: u8) -> (Dynview_Matrix_Column_Alignment, bool) {

    switch ch {
    case 'l':
        return .Left, true
    case 'c':
        return .Center, true
    case 'r':
        return .Right, true
    }
    return .Center, false
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
    if delimiter_kind < 1 || delimiter_kind > DELIMITER_KIND_COUNT {
        return ""
    }
    texts := DELIMITER_TEXTS
    return texts[delimiter_kind - 1]
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
        return .Double_Vert
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
delimiter_base_width_factor :: #force_inline proc(
    family: Dynview_Delimiter_Family) -> f32 {
    switch family {
    case .Paren:
        return 0.42
    case .Bracket:
        return 0.40
    case .Brace:
        return 0.34
    case .Vert:
        return 0.24
    case .Double_Vert:
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
    style: dyncore.Dynview_Text_Style,
    wrap_advance, font_size, content_height: f32,
    delimiter_kind: i32) -> f32 {

    if delimiter_kind == DELIMITER_KIND_NONE {
        return 0
    }

    family := delimiter_family(delimiter_kind)
    if family == .None {
        return 0
    }

    base_advance := dyncore.effective_advance(style, wrap_advance)
    base_width := max(base_advance * 0.2, font_size * delimiter_base_width_factor(family))
    raw_scale := max(1.0, content_height / max(1.0, font_size))
    width_scale := min(1.7, 1.0 + (raw_scale - 1.0) * 0.28)
    return max(1.0, base_width * width_scale)
}

//   Return glyph scale factor for display-style large operators.
large_op_glyph_scale :: #force_inline proc(large_op_kind: i32) -> f32 {
    switch large_op_kind {
    case LARGE_OP_KIND_SUM, LARGE_OP_KIND_PROD, LARGE_OP_KIND_NARY:
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

package dynview_layout

import dyncore "../core"

//   Return default block format values keyed by block kind.
block_format_for_kind :: #force_inline proc(block_kind: i32) -> Dynview_Block_Format {
    switch block_kind {
    case 1, 2:
        return Dynview_Block_Format{line_height_multiplier = 1.0}
    }
    return Dynview_Block_Format{line_height_multiplier = 1.0}
}

//   Merge per-style values with active block format controls.
style_with_block_format :: #force_inline proc(
    style: dyncore.Dynview_Text_Style,
    block_format: Dynview_Block_Format) -> dyncore.Dynview_Text_Style {

    merged := style
    if merged.alignment == .Left && block_format.alignment != .Left {
        merged.alignment = block_format.alignment
    }
    merged.indent_cols = max(merged.indent_cols, block_format.indent_cols)
    merged.paragraph_spacing_before =
        max(merged.paragraph_spacing_before, block_format.paragraph_spacing_before)
    merged.paragraph_spacing_after =
        max(merged.paragraph_spacing_after, block_format.paragraph_spacing_after)
    merged.line_height_multiplier =
        max(merged.line_height_multiplier, block_format.line_height_multiplier)
    return merged
}
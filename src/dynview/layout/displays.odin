package dynview_layout

import app_core "../../core"

// Retain one resolved block measure for composition and final placement.
Document_Block_Measure :: struct {
    origin: f32,
    width: f32,
    label_above: bool,
}

// Bind one block's resolved horizontal placement inputs.
Document_Horizontal_Placement :: struct {
    available_width: f32,
    first_line_indent: f32,
    content_origin: f32,
}

// Resolve one block's content origin and width from semantic margin levels.
document_block_measure :: #force_inline proc(
    block: app_core.Dynview_Document_Block,
    available_width, font_size: f32,
    label_column: f32 = 0,
    label_width: f32 = 0) -> Document_Block_Measure {

    result: Document_Block_Measure
    margin_unit := max(0, font_size*2)
    left_levels := int(block.left_margin_levels)
    right := f32(block.right_margin_levels)*margin_unit
    if block.list_kind != .None && left_levels > 0 {
        list_origin := f32(left_levels-1)*margin_unit
        body_origin := list_origin+max(margin_unit, label_column+font_size*0.5)
        if block.kind == .List_Item {
            result.label_above = block.list_kind == .Description &&
                label_width > label_column
            result.origin = body_origin if result.label_above else list_origin
            result.width = max(1, available_width-result.origin-right) if
                result.label_above else
                max(1, body_origin-list_origin-font_size*0.5)
            return result
        }
        result.origin = body_origin
        result.width = max(1, available_width-result.origin-right)
        return result
    }
    result.origin = f32(left_levels)*margin_unit
    result.width = max(1, available_width-result.origin-right)
    return result
}

// Resolve the first-line indent supported by one semantic paragraph format.
document_block_first_line_indent :: #force_inline proc(
    block: app_core.Dynview_Document_Block,
    font_size: f32) -> f32 {

    if block.kind != .Paragraph || block.no_indent || block.alignment != .Left {
        return 0
    }
    return max(0, font_size)
}

// Resolve one semantic line's horizontal origin within the document content width.
document_line_horizontal_offset :: #force_inline proc(
    block: app_core.Dynview_Document_Block,
    line_width, available_width: f32) -> f32 {

    remaining := max(0, available_width-line_width)
    if block.kind == .Display || block.alignment == .Center {
        return remaining*0.5
    }
    if block.kind == .List_Item && block.list_kind != .Description {
        return remaining
    }
    if block.alignment == .Right {
        return remaining
    }
    return 0
}

// Place paragraph alignment and dedicated display centering without changing widths.
document_place_block_horizontally :: proc(
    block: app_core.Dynview_Document_Block,
    lines: []app_core.Dynview_Document_Layout_Line,
    display_rows: []app_core.Dynview_Document_Display_Row,
    placement: Document_Horizontal_Placement) {

    for &line, line_index in lines {
        line_width := placement.available_width
        if line.display_content_width > 0 {
            line_width = line.display_content_width
        }
        alignment_block := block
        if block.display_kind == .Multline && line.display_row_index >= 0 &&
            line.display_row_index < len(display_rows) {
            alignment_block.kind = .Paragraph
            alignment_block.alignment = display_rows[line.display_row_index].alignment
        }
        line.x = placement.content_origin+document_line_horizontal_offset(
            alignment_block, line.width, line_width)
        if line.display_number > 0 {
            line.display_number_x += placement.content_origin
        }
        if line_index == 0 {
            line.x += placement.first_line_indent
        }
    }
}
package dynview_layout

import app_core "../../core"
import "../../grid"
import "core:testing"

// Verify document spacing remains proportional to the active prose size.
@(test)
document_vertical_style_scales_list_boundaries :: proc(t: ^testing.T) {
    style, ok := document_vertical_style(16)

    testing.expect(t, ok)
    testing.expect_value(t, style.paragraph_spacing, f32(8))
    testing.expect_value(t, style.list_spacing, f32(8))
}

// Verify tall/deep neighbors use fallback line skip and remain non-overlapping.
@(test)
document_vertical_lines_fall_back_without_overlap :: proc(t: ^testing.T) {
    lines := [2]app_core.Dynview_Document_Layout_Line{
        {ascent = 10, descent = 8},
        {ascent = 18, descent = 7},
    }
    style := Document_Vertical_Style{
        baseline_skip = 20, line_skip_limit = 0, line_skip = 2}

    bottom, ok := document_place_block_lines(lines[:], 5, style)

    testing.expect(t, ok)
    testing.expect_value(t, lines[0].top, f32(5))
    testing.expect_value(t, lines[0].bottom, f32(23))
    testing.expect_value(t, lines[1].top, f32(25))
    testing.expect_value(t, lines[1].baseline, f32(43))
    testing.expect_value(t, bottom, f32(50))
}

// Verify completed exact block height rounds outward with trailing padding only.
@(test)
document_vertical_block_reservation_contains_ink :: proc(t: ^testing.T) {
    reservation, ok := grid.reserve_vertical_extent(2, 45, 20)

    testing.expect(t, ok)
    testing.expect_value(t, reservation.row_start, 2)
    testing.expect_value(t, reservation.row_count, 3)
    testing.expect_value(t, reservation.top, f32(40))
    testing.expect_value(t, reservation.bottom, f32(100))
    testing.expect_value(t, reservation.trailing_padding, f32(15))
}

// Verify first blocks have no leading glue and display adjacency uses display glue.
@(test)
document_vertical_block_spacing_respects_document_edges :: proc(t: ^testing.T) {
    blocks := [4]app_core.Dynview_Document_Block{
        {kind = .Display}, {kind = .Paragraph},
        {kind = .Paragraph}, {kind = .Paragraph}}
    documents := [2]app_core.Dynview_Document{
        {block_start = 0, block_count = 3}, {block_start = 3, block_count = 1}}
    style := Document_Vertical_Style{
        paragraph_spacing = 8, display_spacing = 12, list_spacing = 16}

    first, first_ok := document_block_spacing_before(
        documents[:], blocks[:], 0, style)
    after_display, display_ok := document_block_spacing_before(
        documents[:], blocks[:], 1, style)
    paragraph, paragraph_ok := document_block_spacing_before(
        documents[:], blocks[:], 2, style)
    next_document, next_document_ok := document_block_spacing_before(
        documents[:], blocks[:], 3, style)

    testing.expect(t, first_ok && display_ok && paragraph_ok && next_document_ok)
    testing.expect_value(t, first, f32(0))
    testing.expect_value(t, after_display, f32(12))
    testing.expect_value(t, paragraph, f32(8))
    testing.expect_value(t, next_document, f32(0))
}

// Verify complete lists receive outer spacing without adding space between items.
@(test)
document_vertical_list_boundaries_use_list_spacing :: proc(t: ^testing.T) {
    blocks := [6]app_core.Dynview_Document_Block{
        {kind = .Paragraph},
        {kind = .List_Item, list_kind = .Enumerate, list_id = 1, item_ordinal = 1},
        {kind = .Paragraph, list_kind = .Enumerate, list_id = 1,
            item_ordinal = 1, item_first_block = true},
        {kind = .List_Item, list_kind = .Enumerate, list_id = 1, item_ordinal = 2},
        {kind = .Paragraph, list_kind = .Enumerate, list_id = 1,
            item_ordinal = 2, item_first_block = true},
        {kind = .Paragraph},
    }
    documents := [1]app_core.Dynview_Document{
        {block_start = 0, block_count = len(blocks)}}
    style := Document_Vertical_Style{
        paragraph_spacing = 8, display_spacing = 12, list_spacing = 16}

    before, before_ok := document_block_spacing_before(
        documents[:], blocks[:], 1, style)
    between, between_ok := document_block_spacing_before(
        documents[:], blocks[:], 3, style)
    after, after_ok := document_block_spacing_before(
        documents[:], blocks[:], 5, style)

    testing.expect(t, before_ok && between_ok && after_ok)
    testing.expect_value(t, before, f32(16))
    testing.expect_value(t, between, f32(0))
    testing.expect_value(t, after, f32(16))
}

// Verify adjacent items stay compact while paragraphs within one item retain spacing.
@(test)
document_vertical_list_items_do_not_add_paragraph_spacing :: proc(t: ^testing.T) {
    blocks := [5]app_core.Dynview_Document_Block{
        {kind = .List_Item, list_kind = .Enumerate, list_id = 1, item_ordinal = 1},
        {kind = .Paragraph, list_kind = .Enumerate, list_id = 1,
            item_ordinal = 1, item_first_block = true},
        {kind = .List_Item, list_kind = .Enumerate, list_id = 1, item_ordinal = 2},
        {kind = .Paragraph, list_kind = .Enumerate, list_id = 1,
            item_ordinal = 2, item_first_block = true},
        {kind = .Paragraph, list_kind = .Enumerate, list_id = 1,
            item_ordinal = 2},
    }
    documents := [1]app_core.Dynview_Document{
        {block_start = 0, block_count = len(blocks)}}
    style := Document_Vertical_Style{
        paragraph_spacing = 8, display_spacing = 12, list_spacing = 16}

    next_item, next_item_ok := document_block_spacing_before(
        documents[:], blocks[:], 2, style)
    same_item, same_item_ok := document_block_spacing_before(
        documents[:], blocks[:], 4, style)

    testing.expect(t, next_item_ok && same_item_ok)
    testing.expect_value(t, next_item, f32(0))
    testing.expect_value(t, same_item, f32(8))
}

// Verify tall item ink does not force the following item onto another full grid row.
@(test)
document_vertical_list_rows_use_exact_interline_glue :: proc(t: ^testing.T) {
    source_blocks := [2]app_core.Dynview_Document_Block{
        {kind = .Paragraph, list_kind = .Enumerate, list_id = 1,
            item_ordinal = 1, item_first_block = true},
        {kind = .List_Item, list_kind = .Enumerate, list_id = 1,
            item_ordinal = 2},
    }
    layout_blocks := [2]app_core.Dynview_Document_Layout_Block{
        {source_block_index = 0, line_start = 0, line_count = 1},
        {source_block_index = 1, line_start = 1, line_count = 1},
    }
    lines := [2]app_core.Dynview_Document_Layout_Line{
        {top = 0, baseline = 20, bottom = 24, ascent = 20, descent = 4},
        {ascent = 10, descent = 3},
    }
    builders := Document_Layout_Builders{}
    builders.blocks.storage = layout_blocks[:]
    builders.blocks.count = len(layout_blocks)
    builders.lines.storage = lines[:]
    builders.lines.count = len(lines)
    style := Document_Vertical_Style{baseline_skip = 20, line_skip = 2}

    top := document_list_block_top(
        &builders, source_blocks[:], style, 1, 40)

    testing.expect_value(t, top, f32(30))
}

// Verify shapes share the prose visual center regardless of sibling shape height.
@(test)
document_vertical_shapes_use_stable_content_center :: proc(t: ^testing.T) {
    items := [3]app_core.Dynview_Document_Layout_Item{
        {box_kind = .Prose, ascent = 12, descent = 3},
        {box_kind = .Shape, ascent = 2, descent = 2},
        {box_kind = .Shape, ascent = 16, descent = 16},
    }
    builders := Document_Layout_Builders{}
    builders.items.storage = items[:]
    builders.items.count = len(items)
    line := app_core.Dynview_Document_Layout_Line{
        item_count = len(items), top = 13.5, baseline = 30, bottom = 46.5}

    testing.expect(t, document_place_line_contents(&builders, 0, line))
    testing.expect_value(t, items[0].top, f32(18))
    testing.expect_value(t, items[1].top, f32(23.5))
    testing.expect_value(t, items[2].top, f32(9.5))
}

// Verify vertical placement rejects incomplete source and line ranges.
@(test)
document_vertical_block_ranges_reject_malformed_records :: proc(t: ^testing.T) {
    valid := app_core.Dynview_Document_Layout_Block{
        source_block_index = 1, line_start = 2, line_count = 3}
    missing_source := valid
    missing_source.source_block_index = 2
    negative_line := valid
    negative_line.line_start = -1
    overflowing_lines := valid
    overflowing_lines.line_count = 4

    testing.expect(t, document_vertical_block_ranges_valid(valid, 2, 5))
    testing.expect(t, !document_vertical_block_ranges_valid(missing_source, 2, 5))
    testing.expect(t, !document_vertical_block_ranges_valid(negative_line, 2, 5))
    testing.expect(t, !document_vertical_block_ranges_valid(overflowing_lines, 2, 5))
}
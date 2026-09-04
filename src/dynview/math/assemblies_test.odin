package dynview_math

import app_core "../../core"
import "core:testing"

//   Build one deterministic variant and symmetric three-part assembly fixture.
math_stretch_test_records :: proc() -> (
    app_core.Font_Math_Glyph_Variants,
    app_core.Font_Math_Glyph_Assembly) {

    variants := app_core.Font_Math_Glyph_Variants{
        valid = true, generation = 9, base_glyph_id = 1, count = 2}
    variants.values[0] = {
        glyph_id = 10, advance = 800,
        extents = {y_bearing = 700, height = -800}}
    variants.values[1] = {
        glyph_id = 11, advance = 1200,
        extents = {y_bearing = 900, height = -1000}}
    assembly := app_core.Font_Math_Glyph_Assembly{
        valid = true, generation = 9, base_glyph_id = 1,
        min_connector_overlap = 100, count = 3}
    assembly.values[0] = {
        glyph_id = 20, end_connector_length = 200, full_advance = 500}
    assembly.values[1] = {
        glyph_id = 21, start_connector_length = 200,
        end_connector_length = 200, full_advance = 400, extender = true}
    assembly.values[2] = {
        glyph_id = 22, start_connector_length = 200, full_advance = 500}
    return variants, assembly
}

//   Verify ready-made variants win when the smallest adequate glyph exists.
@(test)
math_stretch_selects_smallest_ready_variant :: proc(t: ^testing.T) {
    variants, assembly := math_stretch_test_records()
    selected := math_stretch_select(variants, assembly, 9, 1000)
    testing.expect(t, selected.valid && !selected.assembled)
    testing.expect_value(t, selected.parts[0].glyph_id, u32(11))
    testing.expect_value(t, selected.advance, f32(1200))
}

//   Verify extenders repeat symmetrically and connector growth is distributed.
@(test)
math_stretch_constructs_minimal_symmetric_assembly :: proc(t: ^testing.T) {
    variants, assembly := math_stretch_test_records()
    selected := math_stretch_select(variants, assembly, 9, 1700)
    testing.expect(t, selected.valid && selected.assembled)
    testing.expect_value(t, selected.count, 5)
    testing.expect_value(t, selected.parts[0].glyph_id, u32(20))
    testing.expect_value(t, selected.parts[1].glyph_id, u32(21))
    testing.expect_value(t, selected.parts[2].glyph_id, u32(21))
    testing.expect_value(t, selected.parts[3].glyph_id, u32(21))
    testing.expect_value(t, selected.parts[4].glyph_id, u32(22))
    testing.expect_value(t, selected.advance, f32(1700))
    testing.expect_value(t, selected.parts[4].advance_offset, f32(1200))
}

//   Verify stale and over-capacity constructions fail transactionally.
@(test)
math_stretch_rejects_stale_and_over_capacity_records :: proc(t: ^testing.T) {
    variants, assembly := math_stretch_test_records()
    stale := math_stretch_select(variants, assembly, 8, 1700)
    oversized := math_stretch_select(variants, assembly, 9, 100000)
    testing.expect(t, !stale.valid && !oversized.valid)
}

//   Verify invisible delimiter sides need no font record and remain zero width.
@(test)
math_stretch_preserves_invisible_delimiter :: proc(t: ^testing.T) {
    sources: [2]app_core.Font_Math_Stretch_Source
    variants, assembly := math_stretch_test_records()
    sources[0] = {
        raster_ascent = 24, variants = variants, assembly = assembly}
    selected := math_stretch_select_delimiters(
        sources, {accent_mode = DELIMITER_KIND_LEFT_PAREN,
            radical_mode = DELIMITER_KIND_NONE}, 9, 0.01, 1000)
    testing.expect(t, selected.ok)
    testing.expect(t, selected.constructions[0].valid)
    testing.expect(t, !selected.constructions[1].valid)
    testing.expect_value(t, selected.widths[1], f32(0))
}

//   Verify narrow standalone delimiter ink does not reserve a full text cell.
@(test)
stretch_delimiter_item_uses_ink_width_without_trailing_cell_space :: proc(
    t: ^testing.T) {

    item: app_core.Dynview_Layout_Item
    selected := Stretch_Delimiter_Selection{ok = true}
    selected.widths[0] = 3
    stretch_delimiter_apply_item(&item, {
        selected = selected, axis = 2, generation = 9, scale = 0.01})
    testing.expect_value(t, item.draw_width, f32(3))
    testing.expect_value(t, item.math_stretch_content_x, f32(3))
}

//   Verify a stale second side rejects without returning a partial construction.
@(test)
math_stretch_rejects_partial_delimiter_selection :: proc(t: ^testing.T) {
    sources: [2]app_core.Font_Math_Stretch_Source
    variants, assembly := math_stretch_test_records()
    sources[0] = {variants = variants, assembly = assembly}
    variants.generation = 8
    assembly.generation = 8
    sources[1] = {variants = variants, assembly = assembly}
    selected := math_stretch_select_delimiters(
        sources, {accent_mode = DELIMITER_KIND_LEFT_PAREN,
            radical_mode = DELIMITER_KIND_RIGHT_PAREN}, 9, 0.01, 1000)
    testing.expect(t, !selected.ok)
    testing.expect(t, !selected.constructions[0].valid)
}

//   Verify cumulative assembly advances position later parts toward the ink top.
@(test)
math_stretch_ink_bounds_follow_bottom_up_part_offsets :: proc(t: ^testing.T) {
    construction := app_core.Font_Math_Stretch_Construction{
        valid = true, assembled = true, count = 2}
    construction.parts[0] = {
        glyph_id = 20, extents = {y_bearing = 200, height = -300}}
    construction.parts[1] = {
        glyph_id = 22, advance_offset = 400,
        extents = {y_bearing = 250, height = -350}}

    bounds := math_stretch_ink_vertical_bounds(construction, 0.01)
    testing.expect(t, bounds.valid)
    testing.expect_value(t, bounds.top, f32(-6.5))
    testing.expect_value(t, bounds.bottom, f32(1))
}

//   Verify each visible delimiter seals its own extent-derived vertical center.
@(test)
math_stretch_centers_delimiter_sides_independently :: proc(t: ^testing.T) {
    sources: [2]app_core.Font_Math_Stretch_Source
    variants, assembly := math_stretch_test_records()
    variants.values[1].extents = {y_bearing = 900, height = -1000}
    sources[0] = {variants = variants, assembly = assembly}
    variants.values[1].extents = {y_bearing = 700, height = -1200}
    sources[1] = {variants = variants, assembly = assembly}

    selected := math_stretch_select_delimiters(
        sources, {accent_mode = DELIMITER_KIND_LEFT_PAREN,
            radical_mode = DELIMITER_KIND_RIGHT_PAREN}, 9, 0.01, 1000)
    testing.expect(t, selected.ok)
    testing.expect_value(t, selected.vertical_origins[0], f32(4))
    testing.expect_value(t, selected.vertical_origins[1], f32(1))
    testing.expect_value(t, selected.half_heights[0], f32(5))
    testing.expect_value(t, selected.half_heights[1], f32(6))
}

//   Verify degree raise remains a percentage while radical kerns scale as positions.
@(test)
radical_math_metrics_preserve_degree_constant_units :: proc(t: ^testing.T) {
    constants := app_core.Font_Math_Constants{
        valid = true, generation = 9, base_pixel_size = 32}
    constants.values[int(Math_Constant.Radical_Display_Style_Vertical_Gap)] = 128
    constants.values[int(Math_Constant.Radical_Rule_Thickness)] = 64
    constants.values[int(Math_Constant.Radical_Extra_Ascender)] = 32
    constants.values[int(Math_Constant.Radical_Kern_Before_Degree)] = 96
    constants.values[int(Math_Constant.Radical_Kern_After_Degree)] = -32
    constants.values[int(Math_Constant.Radical_Degree_Bottom_Raise_Percent)] = 60
    metrics := radical_math_metrics(constants, 9, 32, {.Display, false})
    testing.expect(t, metrics.ok)
    testing.expect_value(t, metrics.gap, f32(2))
    testing.expect_value(t, metrics.before_degree, f32(1.5))
    testing.expect_value(t, metrics.after_degree, f32(-0.5))
    testing.expect_value(t, metrics.degree_raise_percent, f32(60))
}
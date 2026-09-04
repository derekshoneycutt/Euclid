package dynview_math

import app_core "../../core"
import "core:testing"

//   Build deterministic accent constants at the 32-pixel shaping size.
math_accent_test_constants :: proc() -> app_core.Font_Math_Constants {
    constants := app_core.Font_Math_Constants{
        valid = true, generation = 23, base_pixel_size = 32}
    constants.values[int(Math_Constant.Accent_Base_Height)] = 10*64
    constants.values[int(Math_Constant.Flattened_Accent_Base_Height)] = 12*64
    return constants
}

//   Build one ready horizontal accent source with exact metrics.
math_accent_test_ready_source :: proc(
    glyph_id: u32) -> app_core.Font_Math_Stretch_Source {
    source := app_core.Font_Math_Stretch_Source{raster_ascent = 24}
    source.variants = {
        valid = true, generation = 23, base_glyph_id = glyph_id, count = 1}
    source.variants.values[0] = {
        glyph_id = glyph_id, advance = 640,
        extents = {x_bearing = 0, y_bearing = 320, width = 512, height = -128},
        top_accent_attachment = 256,
    }
    return source
}

//   Build one combining-mark source with degenerate reported horizontal ink.
math_accent_test_degenerate_source :: proc(
    glyph_id: u32) -> app_core.Font_Math_Stretch_Source {

    source := math_accent_test_ready_source(glyph_id)
    source.variants.values[0].advance = 1
    source.variants.values[0].extents.width = 0
    source.variants.values[0].top_accent_attachment = 0
    return source
}

//   Build one two-part horizontal assembly source.
math_accent_test_assembly_source :: proc(
    glyph_id: u32) -> app_core.Font_Math_Stretch_Source {
    source := math_accent_test_ready_source(glyph_id)
    source.assembly = {
        valid = true, generation = 23, base_glyph_id = glyph_id,
        min_connector_overlap = 64, count = 2}
    source.assembly.values[0] = {
        glyph_id = glyph_id, end_connector_length = 100, full_advance = 700,
        extents = {0, 320, 700, -128}}
    source.assembly.values[1] = {
        glyph_id = glyph_id+1, start_connector_length = 100, full_advance = 700,
        extents = {0, 320, 700, -128}}
    return source
}

//   Verify a narrow accent aligns font attachment points and preserves ink bounds.
@(test)
math_glyph_accent_aligns_narrow_attachment_points :: proc(t: ^testing.T) {
    sources := [2]app_core.Font_Math_Stretch_Source{
        math_accent_test_ready_source(40), math_accent_test_ready_source(41)}
    geometry := math_glyph_accent_geometry({
        constants = math_accent_test_constants(), generation = 23, font_size = 32,
        child_width = 8, child_ascent = 8, child_descent = 2,
        base_attachment = 3, sources = sources,
    })
    testing.expect(t, geometry.valid && !geometry.flattened)
    testing.expect_value(t, geometry.child_x, f32(1))
    testing.expect_value(t, geometry.accent_x, f32(0))
    testing.expect_value(t, geometry.top_accent_attachment, f32(4))
    testing.expect_value(t, geometry.ascent, f32(12))
}

//   Verify zero-width combining metrics still produce finite visible geometry.
@(test)
math_glyph_accent_recovers_degenerate_combining_bounds :: proc(t: ^testing.T) {
    sources := [2]app_core.Font_Math_Stretch_Source{
        math_accent_test_degenerate_source(42),
        math_accent_test_degenerate_source(43)}
    geometry := math_glyph_accent_geometry({
        constants = math_accent_test_constants(), generation = 23, font_size = 32,
        child_width = 8, child_ascent = 8, child_descent = 2,
        base_attachment = 4, sources = sources,
    })
    testing.expect(t, geometry.valid)
    testing.expect(t, geometry.construction.valid)
    testing.expect(t, geometry.width >= 8 && geometry.ascent > 8)
    testing.expect(t, geometry.accent_line_top == geometry.accent_line_top)
}

//   Verify wide and high bases select assemblies and the flattened source.
@(test)
math_glyph_accent_selects_wide_flattened_assembly :: proc(t: ^testing.T) {
    sources := [2]app_core.Font_Math_Stretch_Source{
        math_accent_test_assembly_source(50),
        math_accent_test_assembly_source(60)}
    geometry := math_glyph_accent_geometry({
        constants = math_accent_test_constants(), generation = 23, font_size = 32,
        child_width = 20, child_ascent = 14, child_descent = 3,
        sources = sources,
    })
    testing.expect(t, geometry.valid && geometry.flattened)
    testing.expect(t, geometry.construction.assembled)
    testing.expect_value(t, geometry.construction.base_glyph_id, u32(60))
    testing.expect(t, geometry.width >= 20 && geometry.ascent > 14)
}

//   Verify an underbrace expands descent while preserving the base ascent.
@(test)
math_glyph_accent_places_underbrace_below_base :: proc(t: ^testing.T) {
    constants := math_accent_test_constants()
    constants.values[int(Math_Constant.Stretch_Stack_Gap_Below_Min)] = 3*64
    sources := [2]app_core.Font_Math_Stretch_Source{
        math_accent_test_assembly_source(70), math_accent_test_assembly_source(80)}
    geometry := math_glyph_accent_geometry({
        constants = constants, generation = 23, font_size = 32,
        child_width = 12, child_ascent = 7, child_descent = 2,
        base_attachment = 6, sources = sources, brace_mode = 15,
    })
    testing.expect(t, geometry.valid)
    testing.expect_value(t, geometry.ascent, f32(7))
    testing.expect(t, geometry.descent > 5)
    testing.expect(t, geometry.construction.assembled)
    testing.expect(t, geometry.accent_line_top == geometry.accent_line_top)
}

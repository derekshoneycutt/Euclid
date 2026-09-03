package dynview_math

import app_core "../../core"
import "core:testing"

//   Build deterministic display-operator constants at the native test size.
math_operator_test_constants :: proc() -> app_core.Font_Math_Constants {
    constants := app_core.Font_Math_Constants{
        valid = true, generation = 17, base_pixel_size = 32}
    constants.values[int(Math_Constant.Display_Operator_Min_Height)] = 20 * 64
    constants.values[int(Math_Constant.Axis_Height)] = 4 * 64
    constants.values[int(Math_Constant.Upper_Limit_Gap_Min)] = 3 * 64
    constants.values[int(Math_Constant.Upper_Limit_Baseline_Rise_Min)] = 8 * 64
    constants.values[int(Math_Constant.Lower_Limit_Gap_Min)] = 2 * 64
    constants.values[int(Math_Constant.Lower_Limit_Baseline_Drop_Min)] = 7 * 64
    return constants
}

//   Verify the smallest variant meeting the display threshold is selected exactly.
@(test)
math_operator_variant_selects_exact_threshold_glyph :: proc(t: ^testing.T) {
    variants := Math_Glyph_Variants{
        valid = true, generation = 17, base_glyph_id = 4,
        extended_shape = true, count = 4}
    variants.values[0] = {glyph_id = 4, advance = 12 * 64}
    variants.values[1] = {glyph_id = 41, advance = 18 * 64}
    variants.values[2] = {glyph_id = 42, advance = 20 * 64}
    variants.values[3] = {glyph_id = 43, advance = 28 * 64}

    selected := math_operator_select_variant(
        variants, math_operator_test_constants(), 17, 32)

    testing.expect(t, selected.valid && selected.extended_shape)
    testing.expect_value(t, selected.glyph_id, u32(42))
    testing.expect_value(t, selected.advance, f32(20))
}

//   Verify the largest bounded variant is selected when none reaches the threshold.
@(test)
math_operator_variant_uses_largest_available_glyph :: proc(t: ^testing.T) {
    variants := Math_Glyph_Variants{
        valid = true, generation = 17, base_glyph_id = 4, count = 2}
    variants.values[0] = {glyph_id = 4, advance = 8 * 64}
    variants.values[1] = {glyph_id = 51, advance = 16 * 64}

    selected := math_operator_select_variant(
        variants, math_operator_test_constants(), 17, 32)

    testing.expect_value(t, selected.glyph_id, u32(51))
}

//   Verify stale variant generations reject selection atomically.
@(test)
math_operator_variant_rejects_stale_generation :: proc(t: ^testing.T) {
    variants := Math_Glyph_Variants{
        valid = true, generation = 16, base_glyph_id = 4, count = 1}
    variants.values[0] = {glyph_id = 4, advance = 20 * 64}
    selected := math_operator_select_variant(
        variants, math_operator_test_constants(), 17, 32)
    testing.expect(t, !selected.valid)
}

//   Verify axis centering, MATH limit constraints, and opposite italic offsets.
@(test)
math_operator_stacked_geometry_uses_math_constants :: proc(t: ^testing.T) {
    variant := Math_Operator_Variant{
        valid = true, glyph_id = 42, advance = 20,
        extents = {0, 14 * 64, 16 * 64, -20 * 64},
        italic_correction = 4,
    }
    geometry := math_operator_geometry({
        constants = math_operator_test_constants(), generation = 17,
        font_size = 32, style = {.Display, false}, variant = variant,
        superscript = {10, 10, 4, 2}, subscript = {8, 8, 3, 2},
        has_superscript = true, has_subscript = true,
        limits_policy = OPERATOR_LIMITS_STACKED,
    })
    testing.expect(t, geometry.valid)
    testing.expect_value(t, geometry.glyph_ascent, f32(14))
    testing.expect_value(t, geometry.glyph_descent, f32(6))
    testing.expect_value(t, geometry.superscript_x, f32(5))
    testing.expect_value(t, geometry.subscript_x, f32(2))
    testing.expect_value(t, geometry.superscript_baseline, f32(-19))
    testing.expect_value(t, geometry.subscript_baseline, f32(11))
    testing.expect_value(t, geometry.ascent, f32(23))
    testing.expect_value(t, geometry.descent, f32(13))
    testing.expect_value(t, geometry.width, f32(16))
}
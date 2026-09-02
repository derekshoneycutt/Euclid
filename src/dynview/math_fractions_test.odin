package dynview

import "../core"
import "core:testing"

//   Build deterministic fraction constants whose 26.6 values map directly at 32 px.
math_fraction_test_constants :: proc() -> core.Font_Math_Constants {
    constants := core.Font_Math_Constants{
        valid = true, generation = 13, base_pixel_size = 32}
    constants.values[int(Math_Constant.Axis_Height)] = 4 * 64
    constants.values[int(Math_Constant.Fraction_Rule_Thickness)] = 2 * 64
    constants.values[int(
        Math_Constant.Fraction_Numerator_Display_Style_Shift_Up)] = 8 * 64
    constants.values[int(
        Math_Constant.Fraction_Denominator_Display_Style_Shift_Down)] = 7 * 64
    constants.values[int(Math_Constant.Fraction_Num_Display_Style_Gap_Min)] = 5 * 64
    constants.values[int(Math_Constant.Fraction_Denom_Display_Style_Gap_Min)] = 6 * 64
    constants.values[int(Math_Constant.Fraction_Numerator_Shift_Up)] = 6 * 64
    constants.values[int(Math_Constant.Fraction_Denominator_Shift_Down)] = 5 * 64
    constants.values[int(Math_Constant.Fraction_Numerator_Gap_Min)] = 2 * 64
    constants.values[int(Math_Constant.Fraction_Denominator_Gap_Min)] = 3 * 64
    return constants
}

//   Verify display fractions center the rule on the axis and enforce both ink gaps.
@(test)
math_fraction_geometry_enforces_display_clearances :: proc(t: ^testing.T) {
    geometry := math_fraction_geometry({
        constants = math_fraction_test_constants(), generation = 13, font_size = 32,
        style = {.Display, false}, numerator = {width = 12, ascent = 7, descent = 3},
        denominator = {width = 8, ascent = 6, descent = 2}, side_padding = 2,
        minimum_width = 10,
    })

    numerator_gap := geometry.rule_center - geometry.rule_thickness * 0.5 -
        (geometry.numerator_baseline + 3)
    denominator_gap := geometry.denominator_baseline - 6 -
        (geometry.rule_center + geometry.rule_thickness * 0.5)
    testing.expect(t, geometry.valid)
    testing.expect_value(t, geometry.rule_center, f32(-4))
    testing.expect_value(t, numerator_gap, f32(5))
    testing.expect_value(t, denominator_gap, f32(6))
    testing.expect_value(t, geometry.width, f32(16))
    testing.expect_value(t, geometry.numerator_x, f32(2))
    testing.expect_value(t, geometry.denominator_x, f32(4))
}

//   Verify nested text-style fractions use non-display shifts and clearances.
@(test)
math_fraction_geometry_uses_nested_style_constants :: proc(t: ^testing.T) {
    geometry := math_fraction_geometry({
        constants = math_fraction_test_constants(), generation = 13, font_size = 32,
        style = {.Text, false}, numerator = {width = 5, ascent = 4, descent = 1},
        denominator = {width = 5, ascent = 3, descent = 1}, side_padding = 1,
    })

    testing.expect_value(t, geometry.numerator_baseline, f32(-8))
    testing.expect_value(t, geometry.denominator_baseline, f32(5))
}

//   Verify stale MATH generations reject complete fraction geometry.
@(test)
math_fraction_geometry_rejects_stale_constants :: proc(t: ^testing.T) {
    geometry := math_fraction_geometry({
        constants = math_fraction_test_constants(), generation = 14, font_size = 32,
        numerator = {width = 5, ascent = 4, descent = 1},
        denominator = {width = 5, ascent = 3, descent = 1},
    })
    testing.expect(t, !geometry.valid)
}
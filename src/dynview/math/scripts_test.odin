package dynview_math

import app_core "../../core"
import "core:testing"

//   Build deterministic script constants whose 26.6 values map directly at 32 px.
math_script_test_constants :: proc() -> app_core.Font_Math_Constants {
    constants := app_core.Font_Math_Constants{
        valid = true,
        generation = 11,
        base_pixel_size = 32,
    }
    constants.values[int(Math_Constant.Superscript_Shift_Up)] = 8 * 64
    constants.values[int(Math_Constant.Superscript_Shift_Up_Cramped)] = 10 * 64
    constants.values[int(Math_Constant.Superscript_Bottom_Min)] = 3 * 64
    constants.values[int(Math_Constant.Superscript_Baseline_Drop_Max)] = 7 * 64
    constants.values[int(Math_Constant.Subscript_Shift_Down)] = 5 * 64
    constants.values[int(Math_Constant.Subscript_Top_Max)] = 4 * 64
    constants.values[int(Math_Constant.Subscript_Baseline_Drop_Min)] = 2 * 64
    constants.values[int(Math_Constant.Sub_Superscript_Gap_Min)] = 6 * 64
    constants.values[int(
        Math_Constant.Superscript_Bottom_Max_With_Subscript)] = 5 * 64
    constants.values[int(Math_Constant.Space_After_Script)] = 2 * 64
    return constants
}

//   Build one two-range table in the test generation.
math_script_test_kern_table :: proc(
    corner: u8,
    maximum, low, high: i32) -> app_core.Font_Math_Kern_Table {

    table := app_core.Font_Math_Kern_Table{
        valid = true, generation = 11, glyph_id = 9, corner = corner, count = 2}
    table.entries[0] = {maximum, low}
    table.entries[1] = {maximum+1, high}
    return table
}

//   Verify both physical heights and independent base/script scales compose exactly.
@(test)
math_script_kerns_choose_minimum_scaled_height_sum :: proc(t: ^testing.T) {
    input := Math_Script_Geometry_Input{
        constants = math_script_test_constants(), generation = 11,
        font_size = 32, script_font_size = 16,
        base = {ascent = 18, descent = 6},
        superscript = {descent = 2}, subscript = {ascent = 12},
        base_top_right = math_script_test_kern_table(0, 600, 64, 128),
        superscript_bottom_left = math_script_test_kern_table(3, 0, 192, 256),
        base_bottom_right = math_script_test_kern_table(2, 0, -64, 64),
        subscript_top_left = math_script_test_kern_table(1, 500, 128, 256),
        has_superscript = true, has_subscript = true,
    }
    superscript, subscript := math_script_kern_adjustments(input, 11, 8)
    testing.expect_value(t, superscript, f32(2.5))
    testing.expect_value(t, subscript, f32(0))
}

//   Verify single superscripts honor ink/drop bounds and asymmetric italic correction.
@(test)
math_script_geometry_resolves_superscript_bounds :: proc(t: ^testing.T) {
    geometry := math_script_geometry({
        constants = math_script_test_constants(), generation = 11, font_size = 32,
        base = {width = 12, ascent = 18, descent = 4},
        superscript = {width = 7, ascent = 6, descent = 2},
        italic_correction = 3, has_superscript = true,
    })

    testing.expect(t, geometry.valid)
    testing.expect_value(t, geometry.superscript_baseline, f32(-11))
    testing.expect_value(t, geometry.superscript_x, f32(15))
    testing.expect_value(t, geometry.width, f32(24))
    testing.expect_value(t, geometry.ascent, f32(18))
}

//   Verify visual overhang changes outer width without moving the attachment advance.
@(test)
math_script_geometry_attaches_at_base_advance :: proc(t: ^testing.T) {
    geometry := math_script_geometry({
        constants = math_script_test_constants(), generation = 11, font_size = 32,
        base = {width = 16, advance = 12, ascent = 18, descent = 4},
        superscript = {width = 7, ascent = 6, descent = 2},
        italic_correction = 3, has_superscript = true,
    })

    testing.expect_value(t, geometry.superscript_x, f32(15))
    testing.expect_value(t, geometry.width, f32(24))
}

//   Verify cramped superscripts and subscript ink/drop constraints use MATH values.
@(test)
math_script_geometry_resolves_cramped_and_subscript_bounds :: proc(t: ^testing.T) {
    constants := math_script_test_constants()
    cramped := math_script_geometry({
        constants = constants, generation = 11, font_size = 32,
        style = {.Script, true}, base = {width = 10, ascent = 8, descent = 3},
        superscript = {width = 4, ascent = 5, descent = 1},
        has_superscript = true,
    })
    subscript := math_script_geometry({
        constants = constants, generation = 11, font_size = 32,
        base = {width = 10, ascent = 8, descent = 6},
        subscript = {width = 4, ascent = 12, descent = 2}, has_subscript = true,
    })

    testing.expect_value(t, cramped.superscript_baseline, f32(-10))
    testing.expect_value(t, subscript.subscript_baseline, f32(8))
    testing.expect_value(t, subscript.subscript_x, f32(10))
}

//   Verify combined scripts satisfy minimum gap and preferred superscript bottom.
@(test)
math_script_geometry_enforces_combined_clearance :: proc(t: ^testing.T) {
    geometry := math_script_geometry({
        constants = math_script_test_constants(), generation = 11, font_size = 32,
        base = {width = 10, ascent = 8, descent = 3},
        superscript = {width = 5, ascent = 6, descent = 4},
        subscript = {width = 6, ascent = 8, descent = 2},
        italic_correction = 2, has_superscript = true, has_subscript = true,
    })

    sup_raise := -geometry.superscript_baseline
    gap := sup_raise + geometry.subscript_baseline - 4 - 8
    testing.expect(t, geometry.valid)
    testing.expect(t, sup_raise - 4 >= 5)
    testing.expect(t, gap >= 6)
    testing.expect_value(t, geometry.subscript_x, f32(10))
    testing.expect_value(t, geometry.superscript_x, f32(12))
}

//   Verify stale constants reject geometry instead of mixing generations.
@(test)
math_script_geometry_rejects_stale_constants :: proc(t: ^testing.T) {
    geometry := math_script_geometry({
        constants = math_script_test_constants(), generation = 12, font_size = 32,
        base = {width = 10, ascent = 8, descent = 3},
        superscript = {width = 5, ascent = 6, descent = 2},
        has_superscript = true,
    })
    testing.expect(t, !geometry.valid)
}
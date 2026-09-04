package dynview_math

import app_core "../../core"
import "core:testing"

//   Build deterministic stack constants whose 26.6 values map directly at 32 px.
math_stack_test_constants :: proc() -> app_core.Font_Math_Constants {
    constants := app_core.Font_Math_Constants{
        valid = true, generation = 17, base_pixel_size = 32}
    constants.values[int(Math_Constant.Stack_Top_Display_Style_Shift_Up)] = 5 * 64
    constants.values[int(Math_Constant.Stack_Bottom_Display_Style_Shift_Down)] = 4 * 64
    constants.values[int(Math_Constant.Stack_Display_Style_Gap_Min)] = 6 * 64
    return constants
}

//   Verify ruleless stacks center both children and enforce the MATH minimum gap.
@(test)
math_stack_geometry_enforces_display_gap :: proc(t: ^testing.T) {
    geometry := math_stack_geometry({
        constants = math_stack_test_constants(), generation = 17, font_size = 32,
        style = {.Display, false},
        top = {width = 12, ascent = 7, descent = 3},
        bottom = {width = 8, ascent = 4, descent = 2},
    })
    gap := geometry.bottom_baseline - 4 -
        (geometry.top_baseline + 3)
    testing.expect(t, geometry.valid)
    testing.expect_value(t, gap, f32(6))
    testing.expect_value(t, geometry.width, f32(12))
    testing.expect_value(t, geometry.top_x, f32(0))
    testing.expect_value(t, geometry.bottom_x, f32(2))
}

//   Verify over annotations retain the base baseline and satisfy the MATH gap.
@(test)
math_over_under_geometry_keeps_base_baseline :: proc(t: ^testing.T) {
    constants := math_stack_test_constants()
    constants.values[int(Math_Constant.Stretch_Stack_Top_Shift_Up)] = 4*64
    constants.values[int(Math_Constant.Stretch_Stack_Gap_Above_Min)] = 3*64
    geometry := math_over_under_geometry({
        constants = constants, generation = 17, font_size = 32, over = true,
        annotation = {width = 4, ascent = 2, descent = 1},
        base = {width = 10, ascent = 6, descent = 2},
    })
    gap := -geometry.top_baseline-1-6
    testing.expect(t, geometry.valid)
    testing.expect_value(t, geometry.bottom_baseline, f32(0))
    testing.expect_value(t, gap, f32(3))
    testing.expect_value(t, geometry.top_x, f32(3))
}
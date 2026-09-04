package dynview_math

import app_core "../../core"

// Stack_Geometry_Input describes two measured children and their enclosing style.
Stack_Geometry_Input :: struct {
    constants: app_core.Font_Math_Constants,
    generation: u64,
    font_size: f32,
    style: Math_Style,
    top, bottom: Fraction_Box_Metrics,
}

// Stack_Geometry stores centered child positions for one ruleless stack.
Stack_Geometry :: struct {
    valid: bool,
    top_x, top_baseline: f32,
    bottom_x, bottom_baseline: f32,
    width, ascent, descent: f32,
}

//   Resolve font-driven positions for one ruleless two-part stack.
math_stack_geometry :: proc(input: Stack_Geometry_Input) -> Stack_Geometry {
    top_key := Math_Constant.Stack_Top_Shift_Up
    bottom_key := Math_Constant.Stack_Bottom_Shift_Down
    gap_key := Math_Constant.Stack_Gap_Min
    if input.style.level == .Display {
        top_key = .Stack_Top_Display_Style_Shift_Up
        bottom_key = .Stack_Bottom_Display_Style_Shift_Down
        gap_key = .Stack_Display_Style_Gap_Min
    }
    top_shift, top_ok := math_constant_position_px(
        input.constants, input.generation, top_key, input.font_size)
    bottom_shift, bottom_ok := math_constant_position_px(
        input.constants, input.generation, bottom_key, input.font_size)
    minimum_gap, gap_ok := math_constant_position_px(
        input.constants, input.generation, gap_key, input.font_size)
    if !top_ok || !bottom_ok || !gap_ok || input.font_size <= 0 {
        return {}
    }
    actual_gap := top_shift + bottom_shift -
        input.top.descent - input.bottom.ascent
    adjustment := max(0, minimum_gap - actual_gap) * 0.5
    top_shift += adjustment
    bottom_shift += adjustment
    width := max(input.top.width, input.bottom.width)
    return {
        valid = true,
        top_x = (width - input.top.width) * 0.5,
        top_baseline = -top_shift,
        bottom_x = (width - input.bottom.width) * 0.5,
        bottom_baseline = bottom_shift,
        width = width,
        ascent = top_shift + input.top.ascent,
        descent = bottom_shift + input.bottom.descent,
    }
}
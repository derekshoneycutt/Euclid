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

// Over_Under_Geometry_Input describes an annotation and base at one placement side.
Over_Under_Geometry_Input :: struct {
    constants: app_core.Font_Math_Constants,
    generation: u64,
    font_size: f32,
    annotation, base: Fraction_Box_Metrics,
    over: bool,
}

//   Place an annotation around a base using OpenType stretch-stack constants.
math_over_under_geometry :: proc(input: Over_Under_Geometry_Input) -> Stack_Geometry {
    shift_key := Math_Constant.Stretch_Stack_Bottom_Shift_Down
    gap_key := Math_Constant.Stretch_Stack_Gap_Below_Min
    if input.over {
        shift_key = .Stretch_Stack_Top_Shift_Up
        gap_key = .Stretch_Stack_Gap_Above_Min
    }
    shift, shift_ok := math_constant_position_px(
        input.constants, input.generation, shift_key, input.font_size)
    gap, gap_ok := math_constant_position_px(
        input.constants, input.generation, gap_key, input.font_size)
    if !shift_ok || !gap_ok || input.font_size <= 0 {
        return {}
    }
    width := max(input.annotation.width, input.base.width)
    annotation_x := (width-input.annotation.width)*0.5
    base_x := (width-input.base.width)*0.5
    if input.over {
        annotation_shift := max(shift,
            input.base.ascent+gap+input.annotation.descent)
        return {true, annotation_x, -annotation_shift, base_x, 0, width,
            max(input.base.ascent, annotation_shift+input.annotation.ascent),
            input.base.descent}
    }
    annotation_shift := max(shift,
        input.base.descent+gap+input.annotation.ascent)
    return {true, base_x, 0, annotation_x, annotation_shift, width,
        input.base.ascent,
        max(input.base.descent, annotation_shift+input.annotation.descent)}
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
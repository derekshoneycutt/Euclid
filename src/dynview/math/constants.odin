package dynview_math

import app_core "../../core"

LARGE_OP_KIND_NONE :: 0
LARGE_OP_KIND_SUM :: 1
LARGE_OP_KIND_PROD :: 2
LARGE_OP_KIND_INT :: 3
LARGE_OP_KIND_LIM :: 4
LARGE_OP_KIND_NARY :: 5

OPERATOR_GROWTH_NONE :: 0
OPERATOR_GROWTH_DISPLAY :: 1
OPERATOR_LIMITS_NONE :: 0
OPERATOR_LIMITS_SIDE :: 1
OPERATOR_LIMITS_STACKED :: 2

DELIMITER_KIND_NONE :: 0
DELIMITER_KIND_LEFT_PAREN :: 1
DELIMITER_KIND_RIGHT_PAREN :: 2
DELIMITER_KIND_LEFT_BRACKET :: 3
DELIMITER_KIND_RIGHT_BRACKET :: 4
DELIMITER_KIND_LEFT_BRACE :: 5
DELIMITER_KIND_RIGHT_BRACE :: 6
DELIMITER_KIND_VERT :: 7
DELIMITER_KIND_DOUBLE_VERT :: 8
DELIMITER_KIND_LEFT_CEIL :: 9
DELIMITER_KIND_RIGHT_CEIL :: 10
DELIMITER_KIND_LEFT_FLOOR :: 11
DELIMITER_KIND_RIGHT_FLOOR :: 12
DELIMITER_KIND_LEFT_ANGLE :: 13
DELIMITER_KIND_RIGHT_ANGLE :: 14
DELIMITER_KIND_COUNT :: 14

Dynview_Delimiter_Family :: enum {
    None,
    Paren,
    Bracket,
    Brace,
    Vert,
    Double_Vert,
    Ceil,
    Floor,
    Angle,
}

// Math_Constant names all OpenType MATH constants in HarfBuzz enum order.
Math_Constant :: enum u8 {
    Script_Percent_Scale_Down = 0,
    Script_Script_Percent_Scale_Down,
    Delimited_Sub_Formula_Min_Height,
    Display_Operator_Min_Height,
    Math_Leading,
    Axis_Height,
    Accent_Base_Height,
    Flattened_Accent_Base_Height,
    Subscript_Shift_Down,
    Subscript_Top_Max,
    Subscript_Baseline_Drop_Min,
    Superscript_Shift_Up,
    Superscript_Shift_Up_Cramped,
    Superscript_Bottom_Min,
    Superscript_Baseline_Drop_Max,
    Sub_Superscript_Gap_Min,
    Superscript_Bottom_Max_With_Subscript,
    Space_After_Script,
    Upper_Limit_Gap_Min,
    Upper_Limit_Baseline_Rise_Min,
    Lower_Limit_Gap_Min,
    Lower_Limit_Baseline_Drop_Min,
    Stack_Top_Shift_Up,
    Stack_Top_Display_Style_Shift_Up,
    Stack_Bottom_Shift_Down,
    Stack_Bottom_Display_Style_Shift_Down,
    Stack_Gap_Min,
    Stack_Display_Style_Gap_Min,
    Stretch_Stack_Top_Shift_Up,
    Stretch_Stack_Bottom_Shift_Down,
    Stretch_Stack_Gap_Above_Min,
    Stretch_Stack_Gap_Below_Min,
    Fraction_Numerator_Shift_Up,
    Fraction_Numerator_Display_Style_Shift_Up,
    Fraction_Denominator_Shift_Down,
    Fraction_Denominator_Display_Style_Shift_Down,
    Fraction_Numerator_Gap_Min,
    Fraction_Num_Display_Style_Gap_Min,
    Fraction_Rule_Thickness,
    Fraction_Denominator_Gap_Min,
    Fraction_Denom_Display_Style_Gap_Min,
    Skewed_Fraction_Horizontal_Gap,
    Skewed_Fraction_Vertical_Gap,
    Overbar_Vertical_Gap,
    Overbar_Rule_Thickness,
    Overbar_Extra_Ascender,
    Underbar_Vertical_Gap,
    Underbar_Rule_Thickness,
    Underbar_Extra_Descender,
    Radical_Vertical_Gap,
    Radical_Display_Style_Vertical_Gap,
    Radical_Rule_Thickness,
    Radical_Extra_Ascender,
    Radical_Kern_Before_Degree,
    Radical_Kern_After_Degree,
    Radical_Degree_Bottom_Raise_Percent,
}

//   Report whether one immutable constants snapshot matches its requested generation.
math_constants_are_current :: #force_inline proc(
    constants: app_core.Font_Math_Constants,
    generation: u64) -> bool {

    return constants.valid && generation != 0 &&
        constants.generation == generation && constants.base_pixel_size > 0
}

//   Return one raw MATH constant from a generation-matched snapshot.
math_constant_raw :: #force_inline proc(
    constants: app_core.Font_Math_Constants,
    generation: u64,
    constant: Math_Constant) -> (i32, bool) {

    if !math_constants_are_current(constants, generation) {
        return 0, false
    }
    return constants.values[int(constant)], true
}

//   Scale one positional 26.6 MATH constant to the requested pixel size.
math_constant_position_px :: #force_inline proc(
    constants: app_core.Font_Math_Constants,
    generation: u64,
    constant: Math_Constant,
    requested_size: f32) -> (f32, bool) {

    value, ok := math_constant_raw(constants, generation, constant)
    if !ok || requested_size <= 0 {
        return 0, false
    }
    return f32(value)/64.0*requested_size/constants.base_pixel_size, true
}

//   Resolve font-provided scaling for one recursive math style level.
math_style_scale :: proc(
    constants: app_core.Font_Math_Constants,
    generation: u64,
    style: Math_Style) -> (f32, bool) {

    constant: Math_Constant
    switch style.level {
    case .Display, .Text:
        return 1, math_constants_are_current(constants, generation)
    case .Script:
        constant = .Script_Percent_Scale_Down
    case .Script_Script:
        constant = .Script_Script_Percent_Scale_Down
    }
    percent, ok := math_constant_raw(constants, generation, constant)
    if !ok || percent <= 0 {
        return 0, false
    }
    return f32(percent)/100.0, true
}
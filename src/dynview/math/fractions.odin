package dynview_math

import app_core "../../core"

// Fraction_Box_Metrics describes one measured fraction child relative to its baseline.
Fraction_Box_Metrics :: struct {
    width: f32,
    ascent: f32,
    descent: f32,
}

// Math_Fraction_Geometry_Input contains measured children and one resolved style.
Math_Fraction_Geometry_Input :: struct {
    constants: app_core.Font_Math_Constants,
    generation: u64,
    font_size: f32,
    style: Math_Style,
    numerator: Fraction_Box_Metrics,
    denominator: Fraction_Box_Metrics,
    side_padding: f32,
    minimum_width: f32,
}

// Math_Fraction_Geometry stores child baselines and complete rule geometry.
Math_Fraction_Geometry :: struct {
    valid: bool,
    numerator_x: f32,
    numerator_baseline: f32,
    denominator_x: f32,
    denominator_baseline: f32,
    rule_left: f32,
    rule_right: f32,
    rule_center: f32,
    rule_thickness: f32,
    width: f32,
    ascent: f32,
    descent: f32,
}

Math_Fraction_Constants :: struct {
    valid: bool,
    axis, thickness: f32,
    numerator_shift, numerator_gap: f32,
    denominator_shift, denominator_gap: f32,
}

//   Read one required positional MATH constant for fraction geometry.
math_fraction_constant :: #force_inline proc(
    input: Math_Fraction_Geometry_Input,
    constant: Math_Constant) -> (f32, bool) {

    return math_constant_position_px(
        input.constants, input.generation, constant, input.font_size)
}

//   Select style-specific numerator shift and minimum rule gap constants.
math_fraction_numerator_constants :: #force_inline proc(
    style: Math_Style) -> (Math_Constant, Math_Constant) {

    if style.level == .Display {
        return .Fraction_Numerator_Display_Style_Shift_Up,
            .Fraction_Num_Display_Style_Gap_Min
    }
    return .Fraction_Numerator_Shift_Up, .Fraction_Numerator_Gap_Min
}

//   Select style-specific denominator shift and minimum rule gap constants.
math_fraction_denominator_constants :: #force_inline proc(
    style: Math_Style) -> (Math_Constant, Math_Constant) {

    if style.level == .Display {
        return .Fraction_Denominator_Display_Style_Shift_Down,
            .Fraction_Denom_Display_Style_Gap_Min
    }
    return .Fraction_Denominator_Shift_Down, .Fraction_Denominator_Gap_Min
}

//   Resolve all style-specific MATH constants required by fraction geometry.
math_fraction_resolve_constants :: proc(
    input: Math_Fraction_Geometry_Input) -> Math_Fraction_Constants {

    numerator_shift_key, numerator_gap_key :=
        math_fraction_numerator_constants(input.style)
    denominator_shift_key, denominator_gap_key :=
        math_fraction_denominator_constants(input.style)
    result: Math_Fraction_Constants
    axis_ok, thickness_ok, numerator_shift_ok, numerator_gap_ok: bool
    denominator_shift_ok, denominator_gap_ok: bool
    result.axis, axis_ok = math_fraction_constant(input, .Axis_Height)
    result.thickness, thickness_ok = math_fraction_constant(
        input, .Fraction_Rule_Thickness)
    result.numerator_shift, numerator_shift_ok = math_fraction_constant(
        input, numerator_shift_key)
    result.numerator_gap, numerator_gap_ok = math_fraction_constant(
        input, numerator_gap_key)
    result.denominator_shift, denominator_shift_ok = math_fraction_constant(
        input, denominator_shift_key)
    result.denominator_gap, denominator_gap_ok = math_fraction_constant(
        input, denominator_gap_key)
    result.valid = axis_ok && thickness_ok && numerator_shift_ok &&
        numerator_gap_ok && denominator_shift_ok && denominator_gap_ok
    return result
}

//   Resolve axis-aware fraction child baselines and rule dimensions.
math_fraction_geometry :: proc(
    input: Math_Fraction_Geometry_Input) -> Math_Fraction_Geometry {

    constants := math_fraction_resolve_constants(input)
    if input.font_size <= 0 || !constants.valid {
        return {}
    }
    rule_thickness := max(1.0, constants.thickness)
    rule_half := rule_thickness * 0.5
    numerator_raise := max(constants.numerator_shift,
        constants.axis + rule_half + constants.numerator_gap + input.numerator.descent)
    denominator_drop := max(constants.denominator_shift,
        input.denominator.ascent - constants.axis + rule_half +
            constants.denominator_gap)
    content_width := max(input.numerator.width, input.denominator.width)
    width := max(input.minimum_width, content_width + input.side_padding * 2)
    return {
        valid = true,
        numerator_x = (width - input.numerator.width) * 0.5,
        numerator_baseline = -numerator_raise,
        denominator_x = (width - input.denominator.width) * 0.5,
        denominator_baseline = denominator_drop,
        rule_left = input.side_padding,
        rule_right = width - input.side_padding,
        rule_center = -constants.axis,
        rule_thickness = rule_thickness,
        width = width,
        ascent = max(
            numerator_raise + input.numerator.ascent, constants.axis + rule_half),
        descent = max(denominator_drop + input.denominator.descent,
            -constants.axis + rule_half),
    }
}
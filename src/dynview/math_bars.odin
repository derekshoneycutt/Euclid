package dynview

import "../core"

// Math_Bar_Kind selects the OpenType MATH overbar or underbar constants.
Math_Bar_Kind :: enum u8 {
    Overbar,
    Underbar,
}

Math_Bar_Constants :: struct {
    gap: Math_Constant,
    thickness: Math_Constant,
    extra: Math_Constant,
}

// Math_Bar_Geometry_Input contains one measured child and font snapshot.
Math_Bar_Geometry_Input :: struct {
    constants: core.Font_Math_Constants,
    generation: u64,
    font_size: f32,
    kind: Math_Bar_Kind,
    child_width: f32,
    child_ascent: f32,
    child_descent: f32,
}

// Math_Bar_Geometry stores a child's baseline and complete rule-box dimensions.
Math_Bar_Geometry :: struct {
    valid: bool,
    child_baseline: f32,
    rule_center: f32,
    rule_thickness: f32,
    width: f32,
    ascent: f32,
    descent: f32,
}

//   Select the vertical gap, thickness, and outer extent constants for one bar.
math_bar_constants :: #force_inline proc(
    kind: Math_Bar_Kind) -> Math_Bar_Constants {

    if kind == .Overbar {
        return {.Overbar_Vertical_Gap, .Overbar_Rule_Thickness,
            .Overbar_Extra_Ascender}
    }
    return {.Underbar_Vertical_Gap, .Underbar_Rule_Thickness,
        .Underbar_Extra_Descender}
}

//   Resolve MATH-driven overbar or underbar placement around measured child ink.
math_bar_geometry :: proc(input: Math_Bar_Geometry_Input) -> Math_Bar_Geometry {
    constants := math_bar_constants(input.kind)
    gap, gap_ok := math_constant_position_px(
        input.constants, input.generation, constants.gap, input.font_size)
    thickness, thickness_ok := math_constant_position_px(
        input.constants, input.generation, constants.thickness, input.font_size)
    extra, extra_ok := math_constant_position_px(
        input.constants, input.generation, constants.extra, input.font_size)
    if input.font_size <= 0 || !gap_ok || !thickness_ok || !extra_ok {
        return {}
    }
    rule_thickness := max(1.0, thickness)
    half := rule_thickness * 0.5
    result := Math_Bar_Geometry{
        valid = true,
        rule_thickness = rule_thickness,
        width = input.child_width,
        ascent = input.child_ascent,
        descent = input.child_descent,
    }
    if input.kind == .Overbar {
        result.rule_center = -input.child_ascent - gap - half
        result.ascent = input.child_ascent + gap + rule_thickness + extra
    } else {
        result.rule_center = input.child_descent + gap + half
        result.descent = input.child_descent + gap + rule_thickness + extra
    }
    return result
}
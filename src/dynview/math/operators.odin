package dynview_math

import app_core "../../core"

Math_Glyph_Variant :: app_core.Font_Math_Glyph_Variant
Math_Glyph_Variants :: app_core.Font_Math_Glyph_Variants

// Math_Operator_Variant stores one selected display glyph and scaled advance.
Math_Operator_Variant :: struct {
    valid: bool,
    glyph_id: u32,
    advance: f32,
    extended_shape: bool,
    extents: app_core.Font_Glyph_Extents,
    italic_correction: f32,
}

// Math_Operator_Geometry_Input groups one selected body and its semantic limits.
Math_Operator_Geometry_Input :: struct {
    constants: app_core.Font_Math_Constants,
    generation: u64,
    font_size: f32,
    style: Math_Style,
    variant: Math_Operator_Variant,
    superscript: Script_Box_Metrics,
    subscript: Script_Box_Metrics,
    has_superscript: bool,
    has_subscript: bool,
    limits_policy: i32,
}

// Math_Operator_Geometry stores body and limit positions relative to its baseline.
Math_Operator_Geometry :: struct {
    valid: bool,
    glyph_ascent, glyph_descent: f32,
    glyph_x: f32,
    superscript_x, superscript_baseline: f32,
    subscript_x, subscript_baseline: f32,
    width, ascent, descent: f32,
}

//   Select the smallest vertical variant meeting the font's display threshold.
math_operator_select_variant :: proc(
    variants: Math_Glyph_Variants,
    constants: app_core.Font_Math_Constants,
    generation: u64,
    font_size: f32) -> Math_Operator_Variant {

    threshold, threshold_ok := math_constant_position_px(
        constants, generation, .Display_Operator_Min_Height, font_size)
    if !variants.valid || variants.generation != generation ||
        variants.count <= 0 || variants.count > len(variants.values) ||
        constants.base_pixel_size <= 0 || !threshold_ok {
        return {}
    }
    scale := font_size / constants.base_pixel_size
    selected := variants.values[variants.count-1]
    for index in 0..<variants.count {
        variant := variants.values[index]
        selected = variant
        if f32(variant.advance) / 64.0 * scale >= threshold {
            break
        }
    }
    if selected.glyph_id == 0 || selected.advance <= 0 {
        return {}
    }
    return {
        valid = true,
        glyph_id = selected.glyph_id,
        advance = f32(selected.advance) / 64.0 * scale,
        extended_shape = variants.extended_shape,
        extents = selected.extents,
        italic_correction = f32(selected.italic_correction) / 64.0 * scale,
    }
}

//   Scale selected glyph extents and center their vertical box on the math axis.
math_operator_glyph_box :: proc(
    input: Math_Operator_Geometry_Input) -> (Script_Box_Metrics, bool) {

    axis, axis_ok := math_constant_position_px(
        input.constants, input.generation, .Axis_Height, input.font_size)
    if !input.variant.valid || !axis_ok || input.constants.base_pixel_size <= 0 {
        return {}, false
    }
    scale := input.font_size / input.constants.base_pixel_size / 64.0
    height := max(0, -f32(input.variant.extents.height) * scale)
    width := max(0, f32(input.variant.extents.width) * scale)
    if height <= 0 || width <= 0 {
        return {}, false
    }
    ascent := height * 0.5 + axis
    return {
        width = width,
        advance = width,
        ascent = ascent,
        descent = max(0, height - ascent),
    }, true
}

//   Resolve OpenType MATH stacked-limit positions around one operator body.
math_operator_stacked_geometry :: proc(
    input: Math_Operator_Geometry_Input,
    glyph: Script_Box_Metrics) -> Math_Operator_Geometry {

    upper_gap, upper_gap_ok := math_constant_position_px(
        input.constants, input.generation, .Upper_Limit_Gap_Min, input.font_size)
    upper_rise, upper_rise_ok := math_constant_position_px(
        input.constants, input.generation, .Upper_Limit_Baseline_Rise_Min,
        input.font_size)
    lower_gap, lower_gap_ok := math_constant_position_px(
        input.constants, input.generation, .Lower_Limit_Gap_Min, input.font_size)
    lower_drop, lower_drop_ok := math_constant_position_px(
        input.constants, input.generation, .Lower_Limit_Baseline_Drop_Min,
        input.font_size)
    if !upper_gap_ok || !upper_rise_ok || !lower_gap_ok || !lower_drop_ok {
        return {}
    }
    sup_raise := max(upper_rise,
        glyph.ascent + input.superscript.descent + upper_gap)
    sub_drop := max(lower_drop,
        glyph.descent + input.subscript.ascent + lower_gap)
    half_italic := input.variant.italic_correction * 0.5
    sup_x := (glyph.width - input.superscript.width) * 0.5 + half_italic
    sub_x := (glyph.width - input.subscript.width) * 0.5 - half_italic
    left := min(0, min(sup_x, sub_x))
    right := max(glyph.width, max(
        sup_x + input.superscript.width, sub_x + input.subscript.width))
    ascent := glyph.ascent
    descent := glyph.descent
    if input.has_superscript {
        ascent = max(ascent, sup_raise + input.superscript.ascent)
    }
    if input.has_subscript {
        descent = max(descent, sub_drop + input.subscript.descent)
    }
    return {true, glyph.ascent, glyph.descent, -left, sup_x-left, -sup_raise,
        sub_x-left, sub_drop, right-left, ascent, descent}
}

//   Resolve axis-centered body and semantic limit placement for one operator.
math_operator_geometry :: proc(
    input: Math_Operator_Geometry_Input) -> Math_Operator_Geometry {

    glyph, glyph_ok := math_operator_glyph_box(input)
    if !glyph_ok {
        return {}
    }
    if input.limits_policy == OPERATOR_LIMITS_STACKED {
        return math_operator_stacked_geometry(input, glyph)
    }
    if !input.has_superscript && !input.has_subscript {
        return {true, glyph.ascent, glyph.descent, 0, 0, 0, 0, 0,
            glyph.width, glyph.ascent, glyph.descent}
    }
    geometry := math_script_geometry({
        constants = input.constants, generation = input.generation,
        font_size = input.font_size, style = input.style, base = glyph,
        superscript = input.superscript, subscript = input.subscript,
        italic_correction = input.variant.italic_correction,
        has_superscript = input.has_superscript,
        has_subscript = input.has_subscript,
    })
    return {geometry.valid, glyph.ascent, glyph.descent, 0,
        geometry.superscript_x, geometry.superscript_baseline,
        geometry.subscript_x, geometry.subscript_baseline,
        geometry.width, geometry.ascent, geometry.descent}
}
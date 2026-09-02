package dynview

import "../core"

// Script_Box_Metrics describes one measured box relative to its baseline.
Script_Box_Metrics :: struct {
    width: f32,
    advance: f32,
    ascent: f32,
    descent: f32,
}

// Math_Script_Geometry_Input contains measured boxes and style for one attachment.
Math_Script_Geometry_Input :: struct {
    constants: core.Font_Math_Constants,
    generation: u64,
    font_size: f32,
    script_font_size: f32,
    style: Math_Style,
    base: Script_Box_Metrics,
    superscript: Script_Box_Metrics,
    subscript: Script_Box_Metrics,
    italic_correction: f32,
    base_top_right: core.Font_Math_Kern_Table,
    base_bottom_right: core.Font_Math_Kern_Table,
    superscript_bottom_left: core.Font_Math_Kern_Table,
    subscript_top_left: core.Font_Math_Kern_Table,
    has_superscript: bool,
    has_subscript: bool,
}

// Math_Script_Geometry stores authoritative positions relative to the base baseline.
Math_Script_Geometry :: struct {
    valid: bool,
    superscript_x: f32,
    superscript_baseline: f32,
    subscript_x: f32,
    subscript_baseline: f32,
    space_after: f32,
    width: f32,
    ascent: f32,
    descent: f32,
}

//   Sum one base/script corner pair at their independent glyph scales.
math_script_kern_sum :: proc(
    input: Math_Script_Geometry_Input,
    base_table, script_table: core.Font_Math_Kern_Table,
    base_height, script_height: f32) -> f32 {

    base_size := input.constants.base_pixel_size
    base_kern := math_kern_value_px(base_table, input.generation,
        base_height, input.font_size, base_size)
    script_kern := math_kern_value_px(script_table, input.generation,
        script_height, input.script_font_size, base_size)
    return base_kern + script_kern
}

//   Resolve OpenType's minimum of two physical-height sums for both scripts.
math_script_kern_adjustments :: proc(
    input: Math_Script_Geometry_Input,
    superscript_raise, subscript_drop: f32) -> (f32, f32) {

    superscript_kern, subscript_kern: f32
    if input.has_superscript {
        at_script_bottom := math_script_kern_sum(input, input.base_top_right,
            input.superscript_bottom_left,
            superscript_raise-input.superscript.descent,
            -input.superscript.descent)
        at_base_top := math_script_kern_sum(input, input.base_top_right,
            input.superscript_bottom_left, input.base.ascent,
            input.base.ascent-superscript_raise)
        superscript_kern = min(at_script_bottom, at_base_top)
    }
    if input.has_subscript {
        at_script_top := math_script_kern_sum(input, input.base_bottom_right,
            input.subscript_top_left,
            input.subscript.ascent-subscript_drop, input.subscript.ascent)
        at_base_bottom := math_script_kern_sum(input, input.base_bottom_right,
            input.subscript_top_left, -input.base.descent,
            subscript_drop-input.base.descent)
        subscript_kern = min(at_script_top, at_base_bottom)
    }
    return superscript_kern, subscript_kern
}

//   Read one required positional MATH constant for a script geometry input.
math_script_constant :: #force_inline proc(
    input: Math_Script_Geometry_Input,
    constant: Math_Constant) -> (f32, bool) {

    return math_constant_position_px(
        input.constants, input.generation, constant, input.font_size)
}

//   Resolve the preferred superscript baseline raise from all required bounds.
math_superscript_raise :: proc(
    input: Math_Script_Geometry_Input) -> (f32, bool) {

    shift_constant := Math_Constant.Superscript_Shift_Up
    if input.style.cramped {
        shift_constant = .Superscript_Shift_Up_Cramped
    }
    shift, shift_ok := math_script_constant(input, shift_constant)
    bottom_min, bottom_ok := math_script_constant(input, .Superscript_Bottom_Min)
    drop_max, drop_ok := math_script_constant(
        input, .Superscript_Baseline_Drop_Max)
    if !shift_ok || !bottom_ok || !drop_ok {
        return 0, false
    }
    return max(shift, max(input.superscript.descent + bottom_min,
        input.base.ascent - drop_max)), true
}

//   Resolve the preferred subscript baseline drop from all required bounds.
math_subscript_drop :: proc(
    input: Math_Script_Geometry_Input) -> (f32, bool) {

    shift, shift_ok := math_script_constant(input, .Subscript_Shift_Down)
    top_max, top_ok := math_script_constant(input, .Subscript_Top_Max)
    drop_min, drop_ok := math_script_constant(input, .Subscript_Baseline_Drop_Min)
    if !shift_ok || !top_ok || !drop_ok {
        return 0, false
    }
    return max(shift, max(input.subscript.ascent - top_max,
        input.base.descent + drop_min)), true
}

//   Enforce combined-script clearance and superscript-bottom constraints.
math_combined_script_shifts :: proc(
    input: Math_Script_Geometry_Input,
    superscript_raise, subscript_drop: ^f32) -> bool {

    gap_min, gap_ok := math_script_constant(input, .Sub_Superscript_Gap_Min)
    bottom_max, bottom_ok := math_script_constant(
        input, .Superscript_Bottom_Max_With_Subscript)
    if !gap_ok || !bottom_ok {
        return false
    }
    resolved_raise := max(
        superscript_raise^, input.superscript.descent + bottom_max)
    gap := resolved_raise + subscript_drop^ -
        input.superscript.descent - input.subscript.ascent
    superscript_raise^ = resolved_raise
    subscript_drop^ += max(0, gap_min - gap)
    return true
}

//   Resolve MATH-constrained script positions and complete outer dimensions.
math_script_geometry :: proc(
    input: Math_Script_Geometry_Input) -> Math_Script_Geometry {

    if input.font_size <= 0 ||
        (!input.has_superscript && !input.has_subscript) {
        return {}
    }
    space_after, space_ok := math_script_constant(input, .Space_After_Script)
    if !space_ok {
        return {}
    }
    sup_raise, sup_ok := math_superscript_raise(input)
    sub_drop, sub_ok := math_subscript_drop(input)
    if (input.has_superscript && !sup_ok) || (input.has_subscript && !sub_ok) {
        return {}
    }
    if input.has_superscript && input.has_subscript {
        sup_ok = math_combined_script_shifts(input, &sup_raise, &sub_drop)
        if !sup_ok {
            return {}
        }
    }
    base_advance := input.base.advance
    if base_advance <= 0 {
        base_advance = input.base.width
    }
    sup_kern, sub_kern := math_script_kern_adjustments(
        input, sup_raise, sub_drop)
    sup_x := base_advance + max(0, input.italic_correction) + sup_kern
    sub_x := base_advance + sub_kern
    width := input.base.width
    ascent := input.base.ascent
    descent := input.base.descent
    if input.has_superscript {
        width = max(width, sup_x + input.superscript.width)
        ascent = max(ascent, sup_raise + input.superscript.ascent)
    }
    if input.has_subscript {
        width = max(width, sub_x + input.subscript.width)
        descent = max(descent, sub_drop + input.subscript.descent)
    }
    return {true, sup_x, -sup_raise, sub_x, sub_drop, space_after,
        width + space_after, ascent, descent}
}
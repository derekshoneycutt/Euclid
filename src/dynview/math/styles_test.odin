package dynview_math

import "core:testing"

import app_core "../../core"

//   Verify every recursive level advances once and saturates at script-script.
@(test)
math_style_next_level_saturates :: proc(t: ^testing.T) {
    expected := [Math_Style_Level]Math_Style_Level{
        .Display = .Text,
        .Text = .Script,
        .Script = .Script_Script,
        .Script_Script = .Script_Script,
    }
    for level in Math_Style_Level {
        testing.expect_value(t, math_style_next_level(level), expected[level])
    }
}

//   Verify fractions and scripts shrink once while preserving or forcing cramped state.
@(test)
math_child_style_resolves_fraction_and_script_transitions :: proc(t: ^testing.T) {
    for level in Math_Style_Level {
        next := math_style_next_level(level)
        script := math_style_script_level(level)
        testing.expect_value(t, math_child_style({level, false},
            .Fraction_Numerator), Math_Style{next, false})
        testing.expect_value(t, math_child_style({level, true},
            .Superscript), Math_Style{script, true})
        testing.expect_value(t, math_child_style({level, false},
            .Fraction_Denominator), Math_Style{next, true})
        testing.expect_value(t, math_child_style({level, false},
            .Subscript), Math_Style{script, true})
    }
}

//   Verify radical content is cramped in place and degrees use script-script.
@(test)
math_child_style_resolves_radical_transitions :: proc(t: ^testing.T) {
    for level in Math_Style_Level {
        testing.expect_value(t, math_child_style({level, false},
            .Radical_Radicand), Math_Style{level, true})
        testing.expect_value(t, math_child_style({level, true},
            .Radical_Degree), Math_Style{.Script_Script, false})
    }
}

//   Verify positional and percentage constants use their distinct scaling rules.
@(test)
math_constants_scale_fake_metrics_exactly :: proc(t: ^testing.T) {
    constants := app_core.Font_Math_Constants{
        valid = true,
        generation = 9,
        base_pixel_size = 32,
    }
    constants.values[int(Math_Constant.Axis_Height)] = 640
    constants.values[int(Math_Constant.Script_Percent_Scale_Down)] = 80
    constants.values[int(Math_Constant.Script_Script_Percent_Scale_Down)] = 60

    axis, axis_ok := math_constant_position_px(
        constants, 9, .Axis_Height, 16)
    script, script_ok := math_style_scale(constants, 9, {.Script, false})
    script_script, ss_ok := math_style_scale(
        constants, 9, {.Script_Script, true})

    testing.expect(t, axis_ok && script_ok && ss_ok)
    testing.expect_value(t, axis, f32(5))
    testing.expect_value(t, script, f32(0.8))
    testing.expect_value(t, script_script, f32(0.6))
}

//   Verify the text match scale is generation-gated and falls back to identity.
@(test)
math_text_match_scale_requires_current_generation :: proc(t: ^testing.T) {
    constants := app_core.Font_Math_Constants{
        valid = true,
        generation = 9,
        base_pixel_size = 32,
        text_match_scale = 1.25,
    }
    unmeasured := constants
    unmeasured.text_match_scale = 0

    testing.expect_value(t, math_text_match_scale(constants, 9), f32(1.25))
    testing.expect_value(t, math_text_match_scale(constants, 10), f32(1))
    testing.expect_value(t, math_text_match_scale(constants, 0), f32(1))
    testing.expect_value(t, math_text_match_scale(unmeasured, 9), f32(1))
}

//   Verify stale or unavailable snapshots fail without returning partial values.
@(test)
math_constants_reject_stale_or_unavailable_generations :: proc(t: ^testing.T) {
    constants := app_core.Font_Math_Constants{
        valid = true,
        generation = 4,
        base_pixel_size = 32,
    }
    constants.values[int(Math_Constant.Script_Percent_Scale_Down)] = 80
    _, stale_position := math_constant_position_px(
        constants, 3, .Axis_Height, 16)
    _, stale_scale := math_style_scale(constants, 3, {.Script, false})
    constants.valid = false
    _, unavailable := math_constant_raw(constants, 4, .Axis_Height)

    testing.expect(t, !stale_position && !stale_scale && !unavailable)
}
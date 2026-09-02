package dynview

import "../core"
import "core:testing"

//   Build deterministic overbar and underbar constants at the native test size.
math_bar_test_constants :: proc() -> core.Font_Math_Constants {
    constants := core.Font_Math_Constants{
        valid = true, generation = 15, base_pixel_size = 32}
    constants.values[int(Math_Constant.Overbar_Vertical_Gap)] = 3 * 64
    constants.values[int(Math_Constant.Overbar_Rule_Thickness)] = 2 * 64
    constants.values[int(Math_Constant.Overbar_Extra_Ascender)] = 4 * 64
    constants.values[int(Math_Constant.Underbar_Vertical_Gap)] = 5 * 64
    constants.values[int(Math_Constant.Underbar_Rule_Thickness)] = 2 * 64
    constants.values[int(Math_Constant.Underbar_Extra_Descender)] = 6 * 64
    return constants
}

//   Verify overbar rule clearance and extra ascender contribute exactly once.
@(test)
math_bar_geometry_resolves_overbar_extent :: proc(t: ^testing.T) {
    geometry := math_bar_geometry({
        constants = math_bar_test_constants(), generation = 15, font_size = 32,
        kind = .Overbar, child_width = 12, child_ascent = 8, child_descent = 2,
    })

    rule_bottom := geometry.rule_center + geometry.rule_thickness * 0.5
    testing.expect(t, geometry.valid)
    testing.expect_value(t, -8-rule_bottom, f32(3))
    testing.expect_value(t, geometry.rule_center, f32(-12))
    testing.expect_value(t, geometry.ascent, f32(17))
    testing.expect_value(t, geometry.descent, f32(2))
}

//   Verify underbar rule clearance and extra descender contribute exactly once.
@(test)
math_bar_geometry_resolves_underbar_extent :: proc(t: ^testing.T) {
    geometry := math_bar_geometry({
        constants = math_bar_test_constants(), generation = 15, font_size = 32,
        kind = .Underbar, child_width = 12, child_ascent = 8, child_descent = 2,
    })

    rule_top := geometry.rule_center - geometry.rule_thickness * 0.5
    testing.expect_value(t, rule_top-2, f32(5))
    testing.expect_value(t, geometry.rule_center, f32(8))
    testing.expect_value(t, geometry.ascent, f32(8))
    testing.expect_value(t, geometry.descent, f32(15))
}

//   Verify stale snapshots reject bar geometry atomically.
@(test)
math_bar_geometry_rejects_stale_constants :: proc(t: ^testing.T) {
    geometry := math_bar_geometry({
        constants = math_bar_test_constants(), generation = 16, font_size = 32,
        kind = .Overbar, child_width = 12, child_ascent = 8, child_descent = 2,
    })
    testing.expect(t, !geometry.valid)
}
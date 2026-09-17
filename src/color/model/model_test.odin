package color_model

import "core:testing"

// Verify shared color constants preserve exact RGBA8 channel values.
@(test)
color_rgba8_constants_match_contract :: proc(t: ^testing.T) {
    testing.expect_value(t, BLACK, Color_RGBA8{0, 0, 0, 255})
    testing.expect_value(t, WHITE, Color_RGBA8{255, 255, 255, 255})
    testing.expect_value(t, TRANSPARENT, Color_RGBA8{0, 0, 0, 0})
}
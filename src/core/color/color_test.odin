package color

import "core:testing"

// Verify RGBA channels preserve declaration order and exact byte values.
@(test)
color_rgba8_preserves_channels :: proc(t: ^testing.T) {
    value := Color_RGBA8{0x12, 0x34, 0x56, 0x78}
    testing.expect_value(t, value, Color_RGBA8{0x12, 0x34, 0x56, 0x78})
    testing.expect_value(t, BLACK, Color_RGBA8{0, 0, 0, 255})
    testing.expect_value(t, WHITE, Color_RGBA8{255, 255, 255, 255})
    testing.expect_value(t, TRANSPARENT, Color_RGBA8{})
}

// Verify generated and project names resolve exactly and deterministically.
@(test)
named_colors_resolve_exact_values :: proc(t: ^testing.T) {
    testing.expect_value(t, len(NAMED_COLORS), 666)
    cases := [?]struct {
        name: string,
        expected: Color_RGBA8,
    }{
        {"aliceblue", {240, 248, 255, 255}},
        {"gray0", {0, 0, 0, 255}},
        {"rebeccapurple", {102, 51, 153, 255}},
        {"yellowgreen", {154, 205, 50, 255}},
        {"julia_blue", {64, 99, 216, 255}},
        {"julia_green", {56, 152, 38, 255}},
        {"julia_purple", {149, 88, 178, 255}},
        {"julia_red", {203, 60, 51, 255}},
    }
    for test_case in cases {
        actual, found := resolve_named_color(test_case.name)
        testing.expect(t, found)
        testing.expect_value(t, actual, test_case.expected)
    }
    _, uppercase_found := resolve_named_color("AliceBlue")
    _, unknown_found := resolve_named_color("not-a-color")
    testing.expect(t, !uppercase_found)
    testing.expect(t, !unknown_found)
}
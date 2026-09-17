package color_names

import "core:testing"
import colormodel "../model"

// Verify generated Colors.jl names and Euclid palette aliases share one resolver.
@(test)
named_color_registry_matches_source_contract :: proc(t: ^testing.T) {
    testing.expect_value(t, len(NAMED_COLORS), 670)
    cases := [?]struct {
        name: string,
        expected: colormodel.Color_RGBA8,
    }{
        {"aliceblue", {240, 248, 255, 255}},
        {"rebeccapurple", {102, 51, 153, 255}},
        {"julia_blue", {64, 99, 216, 255}},
        {"julia_green", {56, 152, 38, 255}},
        {"julia_purple", {149, 88, 178, 255}},
        {"julia_red", {203, 60, 51, 255}},
    }
    for test_case in cases {
        actual, ok := resolve_named_color(test_case.name)
        testing.expect(t, ok)
        testing.expect_value(t, actual, test_case.expected)
    }
    _, ok := resolve_named_color("not_a_euclid_color")
    testing.expect(t, !ok)
}
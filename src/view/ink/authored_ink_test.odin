package ink

import "core:testing"

import color "../../core/color"

// Verify the stable authored palette assignments in both contrast modes.
@(test)
authored_ink_palette_uses_fixed_grays :: proc(t: ^testing.T) {
    cases := [?]struct {
        original: color.Color_RGBA8,
        normal: u8,
        increased: u8,
    }{
        {{70, 130, 180, 255}, 185, 212},
        {{255, 130, 171, 255}, 230, 246},
        {{205, 198, 115, 255}, 210, 230},
        {{153, 153, 153, 255}, 165, 200},
        {{255, 187, 255, 255}, 245, 255},
        {{144, 238, 144, 255}, 220, 240},
        {{178, 34, 34, 255}, 190, 220},
    }
    for test_case in cases {
        expected_normal: color.Color_RGBA8 = {
            test_case.normal, test_case.normal, test_case.normal, 255,
        }
        expected_increased: color.Color_RGBA8 = {
            test_case.increased, test_case.increased, test_case.increased, 255,
        }
        testing.expect_value(t, resolve_content_ink(test_case.original, true, false),
            expected_normal)
        testing.expect_value(t, resolve_content_ink(test_case.original, true, true),
            expected_increased)
    }
}

// Verify known palette identity ignores alpha and preserves its exact coverage.
@(test)
authored_ink_palette_preserves_alpha :: proc(t: ^testing.T) {
    alphas := [?]u8{0, 1, 127, 255}
    for alpha in alphas {
        original: color.Color_RGBA8 = {70, 130, 180, alpha}
        actual := resolve_content_ink(original, true, false)
        testing.expect_value(t, actual, color.Color_RGBA8{185, 185, 185, alpha})
    }
}

// Verify custom sRGB colors follow the documented linear-luminance fallback.
@(test)
authored_ink_custom_colors_use_luminance_ranges :: proc(t: ^testing.T) {
    cases := [?]struct {
        original: color.Color_RGBA8,
        normal: u8,
        increased: u8,
    }{
        {{12, 200, 40, 33}, 190, 223},
        {{120, 80, 200, 127}, 164, 205},
        {{0, 0, 0, 0}, 149, 196},
        {{255, 255, 255, 255}, 234, 255},
    }
    for test_case in cases {
        normal := resolve_content_ink(test_case.original, true, false)
        increased := resolve_content_ink(test_case.original, true, true)
        testing.expect_value(t, normal[0], test_case.normal)
        testing.expect_value(t, normal[1], test_case.normal)
        testing.expect_value(t, normal[2], test_case.normal)
        testing.expect_value(t, normal[3], test_case.original[3])
        testing.expect_value(t, increased[0], test_case.increased)
        testing.expect_value(t, increased[1], test_case.increased)
        testing.expect_value(t, increased[2], test_case.increased)
        testing.expect_value(t, increased[3], test_case.original[3])
    }
}

// Verify either authored surface receives the same result from the shared policy.
@(test)
authored_ink_resolution_is_deterministic_for_shared_callers :: proc(t: ^testing.T) {
    original: color.Color_RGBA8 = {120, 80, 200, 96}
    animation_ink := resolve_content_ink(original, true, true)
    dynview_ink := resolve_content_ink(original, true, true)
    testing.expect_value(t, animation_ink, dynview_ink)
}

// Verify disabled mode returns every original channel unchanged.
@(test)
authored_ink_disabled_is_exact_passthrough :: proc(t: ^testing.T) {
    cases := [?]color.Color_RGBA8{
        {0, 0, 0, 0},
        {12, 200, 40, 33},
        {70, 130, 180, 127},
        {255, 255, 255, 255},
    }
    for original in cases {
        testing.expect_value(t, resolve_content_ink(original, false, false), original)
        testing.expect_value(t, resolve_content_ink(original, false, true), original)
    }
}

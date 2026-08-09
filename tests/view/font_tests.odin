package view_tests

import "core:testing"

import app_view_core "../../src/view/core"

// Verifies representative bundled language scripts and composed/decomposed accents remain loaded.
@(test)
font_codepoint_policy_covers_languages_and_diacritics :: proc(t: ^testing.T) {
    codepoints := []rune {
        'ä',
        0x0308,
        0x1eb0,
        'α',
        'Ж',
        'Ա',
        'א',
        'ش',
        'ა',
    }

    for codepoint in codepoints {
        testing.expect(t, app_view_core.font_codepoint_is_supported(codepoint))
    }
}

// Verifies current and planned math notation spans both BMP and supplemental Unicode planes.
@(test)
font_codepoint_policy_covers_core_and_supplemental_math :: proc(t: ^testing.T) {
    codepoints := []rune {
        '∞',
        '∫',
        '⌈',
        '⟨',
        0x27f6,
        0x2a0c,
        0x1d6fc,
        0x1ee00,
    }

    for codepoint in codepoints {
        testing.expect(t, app_view_core.font_codepoint_is_supported(codepoint))
    }
}

// Verifies the policy remains comprehensive without returning to a contiguous Unicode sweep.
@(test)
font_codepoint_policy_is_broad_but_bounded :: proc(t: ^testing.T) {
    codepoint_set := app_view_core.font_codepoint_set()

    testing.expect(t, codepoint_set.count > 7000)
    testing.expect(t, codepoint_set.count < app_view_core.FONT_CODEPOINT_CAPACITY)
    testing.expect(t, app_view_core.font_codepoint_is_supported(0x2500))
    testing.expect(t, !app_view_core.font_codepoint_is_supported(0x2502))
    testing.expect(t, !app_view_core.font_codepoint_is_supported('漢'))
}
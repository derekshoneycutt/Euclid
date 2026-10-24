#+test
package coretext

import "core:testing"

// Verify UAX #29 clusters for combining, emoji, flags, Hangul, and Indic text.
@(test)
text_grapheme_boundaries_cover_unicode_sequences :: proc(t: ^testing.T) {
    cases := [?]struct {
        text: string,
        clusters: int,
    }{
        {"e\u0301x", 2},
        {"✈️x", 2},
        {"👩🏽‍💻x", 2},
        {"🇺🇳x", 2},
        {"각x", 2},
        {"क्\u200dषx", 2},
    }
    for item in cases {
        count := 0
        offset := 0
        for offset < len(item.text) {
            next := text_grapheme_next_boundary(item.text, offset)
            testing.expect(t, next > offset)
            testing.expect_value(t,
                text_grapheme_previous_boundary(item.text, next), offset)
            offset = next
            count += 1
        }
        testing.expect_value(t, count, item.clusters)
    }
}

// Verify cluster navigation and columns retain source byte offsets and cell widths.
@(test)
text_grapheme_width_and_boundaries_are_consistent :: proc(t: ^testing.T) {
    text := "e\u0301界👩‍💻"
    testing.expect_value(t, text_grapheme_next_boundary(text, 0), len("e\u0301"))
    testing.expect_value(t,
        text_grapheme_next_boundary(text, len("e\u0301")), len("e\u0301界"))
    testing.expect_value(t,
        text_grapheme_previous_boundary(text, len(text)),
        len("e\u0301界"))
    testing.expect_value(t, text_grapheme_column(text, len("e\u0301界")), 3)
    testing.expect_value(t, text_grapheme_column(text, len(text)), 5)
    testing.expect_value(t, text_grapheme_boundary_for_column(text, 1), len("e\u0301"))
    testing.expect_value(t, text_grapheme_boundary_for_column(text, 2), len("e\u0301界"))
    testing.expect_value(t, text_grapheme_clamp_boundary(text, 2), 0)
    testing.expect_value(t,
        text_grapheme_clamp_boundary(text, len("e\u0301")), len("e\u0301"))
    testing.expect_value(t,
        text_grapheme_clamp_boundary(text, len("e\u0301界")),
        len("e\u0301界"))
}

// Verify emoji presentation and paired regional indicators occupy two cells.
@(test)
text_grapheme_emoji_sequences_have_two_cell_width :: proc(t: ^testing.T) {
    variation_selector := "✈️"
    flag := "🇺🇳"
    testing.expect_value(t,
        text_grapheme_width(variation_selector, 0, len(variation_selector)), 2)
    testing.expect_value(t, text_grapheme_width(flag, 0, len(flag)), 2)
}

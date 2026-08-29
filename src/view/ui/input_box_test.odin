#+test
package ui

import "core:testing"

// Verify an ASCII cursor character separates contextual-alternate neighbors.
@(test)
input_box_test_cursor_segments_ascii :: proc(t: ^testing.T) {
    source: string = "a=>b"
    text := transmute([]u8)source
    segments, valid := input_box_cursor_segments(text, 0, len(text), 1)

    testing.expect(t, valid)
    testing.expect_value(t, segments.before, "a")
    testing.expect_value(t, segments.cursor, "=")
    testing.expect_value(t, segments.after, ">b")
}

// Verify cursor splitting preserves multibyte UTF-8 boundaries.
@(test)
input_box_test_cursor_segments_multibyte :: proc(t: ^testing.T) {
    source: string = "alpha: α=>"
    text := transmute([]u8)source
    caret := len("alpha: α")
    segments, valid := input_box_cursor_segments(text, 0, len(text), caret)

    testing.expect(t, valid)
    testing.expect_value(t, segments.before, "alpha: α")
    testing.expect_value(t, segments.cursor, "=")
    testing.expect_value(t, segments.after, ">")

    _, trailing_valid := input_box_cursor_segments(
        text, 0, len(text), len("alpha: ") + 1)
    testing.expect(t, !trailing_valid)
}
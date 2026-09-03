package dynview_core

import "core:testing"

//   Verify text wrapping handles empty input and over-long tokens.
@(test)
text_wrapping_handles_empty_and_long_tokens :: proc(t: ^testing.T) {
    testing.expect_value(t, chars_per_text_row(0, 8), 1)
    testing.expect_value(t, count_wrapped_text_rows("", 20), 1)

    text := "supercalifragilistic"
    span := next_wrapped_text_span(text, 0, 4)

    testing.expect_value(t, span.line_start, 0)
    testing.expect(t, span.line_end > span.line_start)
    testing.expect(t, span.next_start > span.line_start)
    testing.expect(t, count_wrapped_text_rows("aaaa bbbb cccc", 4) >= 3)
}

//   Verify UTF-8 helpers count complete codepoints and clamp malformed tails.
@(test)
text_utf8_helpers_handle_multibyte_and_truncated_sequences :: proc(t: ^testing.T) {
    text := "A\xc3\xa9"

    testing.expect_value(t, text_utf8_sequence_len(text, 0), 1)
    testing.expect_value(t, text_utf8_sequence_len(text, 1), 2)
    testing.expect_value(t, text_codepoint_count_span(text, 0, len(text)), 2)
    testing.expect_value(t, text_utf8_sequence_len("\xc3", 0), 1)
    testing.expect_value(t, text_utf8_sequence_len(text, len(text)), 0)
}
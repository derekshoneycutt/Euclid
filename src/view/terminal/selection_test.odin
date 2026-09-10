#+test
package terminalview

import "../../core"

import "core:testing"

// Verify anchor/head ordering picks the earlier position first, either order.
@(test)
terminal_test_selection_ordered :: proc(t: ^testing.T) {
    a := core.Terminal_View_Position{line = 1, byte_offset = 3}
    b := core.Terminal_View_Position{line = 2, byte_offset = 0}

    start, end := terminal_selection_ordered(a, b)
    testing.expect_value(t, start, a)
    testing.expect_value(t, end, b)

    start, end = terminal_selection_ordered(b, a)
    testing.expect_value(t, start, a)
    testing.expect_value(t, end, b)
}

// Verify same-line ordering compares byte offsets when lines are equal.
@(test)
terminal_test_selection_ordered_same_line :: proc(t: ^testing.T) {
    a := core.Terminal_View_Position{line = 0, byte_offset = 5}
    b := core.Terminal_View_Position{line = 0, byte_offset = 2}

    start, end := terminal_selection_ordered(a, b)
    testing.expect_value(t, start, b)
    testing.expect_value(t, end, a)
}

// Verify a single-line selection composes the exact byte sub-range.
@(test)
terminal_test_compose_selection_text_single_line :: proc(t: ^testing.T) {
    lines := []string{"hello world"}
    start := core.Terminal_View_Position{line = 0, byte_offset = 6}
    end := core.Terminal_View_Position{line = 0, byte_offset = 11}

    testing.expect_value(t, terminal_compose_selection_text(lines, start, end), "world")
}

// Verify a multi-line selection joins partial first/last lines and full middle lines.
@(test)
terminal_test_compose_selection_text_multi_line :: proc(t: ^testing.T) {
    lines := []string{"first line", "middle", "last line"}
    start := core.Terminal_View_Position{line = 0, byte_offset = 6}
    end := core.Terminal_View_Position{line = 2, byte_offset = 4}

    testing.expect_value(
        t, terminal_compose_selection_text(lines, start, end), "line\nmiddle\nlast")
}

// Verify out-of-range byte offsets clamp instead of producing invalid slices.
@(test)
terminal_test_compose_selection_text_clamps_offsets :: proc(t: ^testing.T) {
    lines := []string{"abc"}
    start := core.Terminal_View_Position{line = 0, byte_offset = -5}
    end := core.Terminal_View_Position{line = 0, byte_offset = 99}

    testing.expect_value(t, terminal_compose_selection_text(lines, start, end), "abc")
}

// Verify leading blank/virtual lines are skipped so copied text starts at
// the first real content, rather than including empty leading lines.
@(test)
terminal_test_compose_selection_text_skips_leading_blank :: proc(t: ^testing.T) {
    lines := []string{"", "", "hello", "world"}
    start := core.Terminal_View_Position{line = 0, byte_offset = 0}
    end := core.Terminal_View_Position{line = 3, byte_offset = 5}

    testing.expect_value(
        t, terminal_compose_selection_text(lines, start, end), "hello\nworld")
}

// Verify a selection made entirely of blank/virtual lines composes to empty text.
@(test)
terminal_test_compose_selection_text_entirely_blank :: proc(t: ^testing.T) {
    lines := []string{"real", "", ""}
    start := core.Terminal_View_Position{line = 1, byte_offset = 0}
    end := core.Terminal_View_Position{line = 2, byte_offset = 0}

    testing.expect_value(t, terminal_compose_selection_text(lines, start, end), "")
}

// Verify a partial last-line span does not reach that line's end.
@(test)
terminal_test_selection_span_for_line_partial :: proc(t: ^testing.T) {
    start := core.Terminal_View_Position{line = 0, byte_offset = 0}
    end := core.Terminal_View_Position{line = 0, byte_offset = 3}

    span := terminal_selection_span_for_line(start, end, 0, 11)
    testing.expect(t, span.has_selection)
    testing.expect(t, !span.covers_trailing_gap)
}

// Verify a middle line spanning a multi-line selection reaches its own end.
@(test)
terminal_test_selection_span_for_line_middle_reaches_end :: proc(t: ^testing.T) {
    start := core.Terminal_View_Position{line = 0, byte_offset = 3}
    end := core.Terminal_View_Position{line = 2, byte_offset = 2}

    span := terminal_selection_span_for_line(start, end, 1, 6)
    testing.expect(t, span.has_selection)
    testing.expect(t, span.covers_trailing_gap)
    testing.expect_value(t, span.start, 0)
    testing.expect_value(t, span.end, 6)
}

// Verify a fully-covered blank interior line still highlights as selected.
@(test)
terminal_test_selection_span_for_line_blank_interior :: proc(t: ^testing.T) {
    start := core.Terminal_View_Position{line = 0, byte_offset = 3}
    end := core.Terminal_View_Position{line = 2, byte_offset = 2}

    span := terminal_selection_span_for_line(start, end, 1, 0)
    testing.expect(t, span.has_selection)
    testing.expect(t, span.covers_trailing_gap)
}

// Verify a non-last line whose own start is past its real end (virtual
// blank space) still selects and extends onward, rather than collapsing.
@(test)
terminal_test_selection_span_for_line_virtual_start_non_last :: proc(t: ^testing.T) {
    start := core.Terminal_View_Position{line = 2, byte_offset = 10}
    end := core.Terminal_View_Position{line = 5, byte_offset = 3}

    span := terminal_selection_span_for_line(start, end, 2, 5)
    testing.expect(t, span.has_selection)
    testing.expect(t, span.covers_trailing_gap)
    testing.expect_value(t, span.start, 10)
}

// Verify the final line stops exactly at its own end offset, even virtual,
// rather than being forced to the full viewport width.
@(test)
terminal_test_selection_span_for_line_virtual_end_last_line :: proc(t: ^testing.T) {
    start := core.Terminal_View_Position{line = 2, byte_offset = 10}
    end := core.Terminal_View_Position{line = 5, byte_offset = 12}

    span := terminal_selection_span_for_line(start, end, 5, 8)
    testing.expect(t, span.has_selection)
    testing.expect(t, !span.covers_trailing_gap)
    testing.expect_value(t, span.end, 12)
}

// Verify a line entirely outside the selection's line range is unselected.
@(test)
terminal_test_selection_span_for_line_outside_range :: proc(t: ^testing.T) {
    start := core.Terminal_View_Position{line = 1, byte_offset = 0}
    end := core.Terminal_View_Position{line = 2, byte_offset = 2}

    span := terminal_selection_span_for_line(start, end, 0, 5)
    testing.expect(t, !span.has_selection)
}

// Verify the selection's final line never covers the trailing gap below it.
@(test)
terminal_test_selection_span_for_line_last_line_no_gap :: proc(t: ^testing.T) {
    start := core.Terminal_View_Position{line = 0, byte_offset = 3}
    end := core.Terminal_View_Position{line = 2, byte_offset = 2}

    span := terminal_selection_span_for_line(start, end, 2, 6)
    testing.expect(t, span.has_selection)
    testing.expect(t, !span.covers_trailing_gap)
}

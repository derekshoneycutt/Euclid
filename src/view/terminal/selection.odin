package terminalview

import "../../core"

import "core:math"
import "core:strings"

// One line's selected byte span and optional trailing virtual-space highlight.
Terminal_Line_Selection :: struct {
    // Half-open UTF-8 byte range clamped by the drawing/composition caller.
    start : int,
    end : int,
    has_selection : bool,

    // Multi-line continuation highlight extending through the viewport's right edge.
    covers_trailing_gap : bool,
    right_edge_x : f32,
}

// Ordered multi-line selection endpoints plus the viewport edge used for full-line spans.
Terminal_Selection_Bounds :: struct {
    start : core.Terminal_View_Position,
    end : core.Terminal_View_Position,
    right_edge_x : f32,
}

//   Normalize a view-selection anchor/head pair into ordered start/end positions.
//
// Parameters:
//   - anchor: The position where the selection drag began.
//   - head: The position the selection currently extends to.
//
// Returns:
//   - The earlier position first, the later position second.
terminal_selection_ordered :: proc(
    anchor, head: core.Terminal_View_Position) -> (
    core.Terminal_View_Position, core.Terminal_View_Position) {
    if anchor.line < head.line ||
        (anchor.line == head.line && anchor.byte_offset <= head.byte_offset) {
        return anchor, head
    }
    return head, anchor
}

//   Compose the plain-text contents of an ordered multi-line view selection.
//
// Notes:
//   - Leading lines with no real text (blank interior lines or virtual space
//     before any real content) are skipped entirely rather than emitted as
//     empty leading lines, so copied text starts at the first real content.
//
// Parameters:
//   - lines: The full text of every line spanned by the selection, indexed by
//     the same line numbers as start/end; lines beyond real content should be
//     empty strings representing blank virtual space.
//   - start: The selection's ordered start position.
//   - end: The selection's ordered end position.
//
// Returns:
//   - The selected text, with lines beyond the first joined by "\n".
terminal_compose_selection_text :: proc(
    lines: []string, start, end: core.Terminal_View_Position) -> string {
    builder := strings.builder_make(context.temp_allocator)
    started := false

    for line := start.line; line <= end.line; line += 1 {
        if line < 0 || line >= len(lines) {
            continue
        }

        line_text := lines[line]
        line_start := line == start.line ? start.byte_offset : 0
        line_end := line == end.line ? end.byte_offset : len(line_text)

        line_start = math.clamp(line_start, 0, len(line_text))
        line_end = math.clamp(line_end, line_start, len(line_text))

        segment := line_text[line_start:line_end]
        if !started && len(segment) == 0 {
            continue
        }

        if started {
            strings.write_byte(&builder, '\n')
        }
        strings.write_string(&builder, segment)
        started = true
    }

    return strings.to_string(builder)
}

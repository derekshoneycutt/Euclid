package dynview

//   Return whether one byte is a UTF-8 continuation byte (10xxxxxx).
text_is_utf8_trailing_byte :: #force_inline proc(b: u8) -> bool {
    return (b & 0xC0) == 0x80
}

//   Return UTF-8 sequence length from one byte index, clamped to available bytes.
text_utf8_sequence_len :: #force_inline proc(text: string, start: int) -> int {
    if start < 0 || start >= len(text) {
        return 0
    }

    b := text[start]
    if (b & 0x80) == 0x00 {
        return 1
    }
    if (b & 0xE0) == 0xC0 {
        if start + 1 < len(text) && text_is_utf8_trailing_byte(text[start + 1]) {
            return 2
        }
        return 1
    }
    if (b & 0xF0) == 0xE0 {
        if start + 2 < len(text) &&
            text_is_utf8_trailing_byte(text[start + 1]) &&
            text_is_utf8_trailing_byte(text[start + 2]) {
            return 3
        }
        return 1
    }
    if (b & 0xF8) == 0xF0 {
        if start + 3 < len(text) &&
            text_is_utf8_trailing_byte(text[start + 1]) &&
            text_is_utf8_trailing_byte(text[start + 2]) &&
            text_is_utf8_trailing_byte(text[start + 3]) {
            return 4
        }
        return 1
    }

    return 1
}

//   Count UTF-8 codepoints in the byte range [start, end) of a string.
text_codepoint_count_span :: #force_inline proc(text: string, start, end: int) -> int {
    if end <= start {
        return 0
    }

    clamped_start := max(0, start)
    clamped_end := min(len(text), end)
    if clamped_end <= clamped_start {
        return 0
    }

    count := 0
    for i := clamped_start; i < clamped_end; i += 1 {
        if !text_is_utf8_trailing_byte(text[i]) {
            count += 1
        }
    }
    return count
}

//   Estimate visible character capacity for one wrapped text row.
chars_per_text_row :: #force_inline proc(width, wrap_advance: f32) -> int {
    count := int(width / wrap_advance)
    if count < 1 {
        return 1
    }
    return count
}

//   Compute the next wrapped line span and next-start index.
next_wrapped_text_span :: proc(
    text: string, start: int, max_chars: int) -> (int, int, int) {

    if start >= len(text) {
        return start, start, start
    }

    line_end := start
    chars_used := 0
    last_space := -1

    for line_end < len(text) && text[line_end] != '\n' {
        if text[line_end] == ' ' || text[line_end] == '\t' {
            last_space = line_end
        }

        seq_len := text_utf8_sequence_len(text, line_end)
        if seq_len <= 0 {
            seq_len = 1
        }

        chars_used += 1
        if chars_used > max_chars {
            if last_space >= start {
                line_end = last_space
            }
            break
        }

        line_end += seq_len
    }

    if line_end == start && line_end < len(text) && text[line_end] != '\n' {
        seq_len := text_utf8_sequence_len(text, line_end)
        if seq_len <= 0 {
            seq_len = 1
        }
        line_end += seq_len
    }

    next_start := line_end
    if next_start < len(text) && text[next_start] == '\n' {
        next_start += 1
    } else {
        for next_start < len(text) && (text[next_start] == ' ' ||
            text[next_start] == '\t') {
            next_start += 1
        }
    }

    return start, line_end, next_start
}

//   Count wrapped line rows needed for given text and width.
count_wrapped_text_rows :: proc(text: string, max_chars: int) -> int {
    if len(text) == 0 {
        return 1
    }

    rows := 0
    start := 0
    for start < len(text) {
        _, _, next_start := next_wrapped_text_span(text, start, max_chars)
        rows += 1
        if next_start <= start {
            break
        }
        start = next_start
    }

    return rows
}

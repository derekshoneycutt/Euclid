package uiterminal

import coretext "../../../core/text"
import "core:unicode"
import "core:unicode/utf8"

// One bounded presentation row; source offsets always refer to the unchanged source.
Terminal_Explorer_Text_Row :: struct {
    text: string,
    source_start: int,
    source_end: int,
    next: int,
    columns: int,
    hard_break: bool,
}

// One sanitized display cluster mapped to its unchanged source-byte interval.
Terminal_Explorer_Text_Fragment :: struct {
    text: string,
    source_start: int,
    source_end: int,
    next: int,
    columns: int,
    synthetic: bool,
    hard_break: bool,
}

// Replace controls for display only; never feed retained source through the interpreter.
terminal_explorer_safe_cluster :: proc(
    source: string, start, end: int) -> (string, int) {
    value, _ := utf8.decode_rune(source[start:end])
    if value == '\n' || value == '\r' {
        return " ↵ ", 3
    }
    if value == '\t' {
        return "    ", 4
    }
    if value < ' ' || value >= 0x7f && value <= 0x9f ||
       value >= 0x202a && value <= 0x202e ||
       value >= 0x2066 && value <= 0x2069 {
        return "?", 1
    }
    return source[start:end], max(1, coretext.text_grapheme_width(source, start, end))
}

// Map one complete source grapheme to its safe display fragment.
terminal_explorer_text_fragment :: proc(
    source: string, offset: int,
    flatten: bool = false) -> Terminal_Explorer_Text_Fragment {
    if offset < 0 || offset >= len(source) {
        return {}
    }
    end := coretext.text_grapheme_next_boundary(source, offset)
    if !flatten && (source[offset] == '\r' || source[offset] == '\n') {
        return {
            source_start = offset,
            source_end = end,
            next = end,
            hard_break = true,
        }
    }
    text, width := terminal_explorer_safe_cluster(source, offset, end)
    if flatten && (source[offset] == '\r' || source[offset] == '\n') {
        for end < len(source) {
            value, _ := utf8.decode_rune(source[end:])
            if !unicode.is_space(value) {
                break
            }
            end = coretext.text_grapheme_next_boundary(source, end)
        }
    }
    return {
        text = text,
        source_start = offset,
        source_end = end,
        next = end,
        columns = width,
        synthetic = source[offset] == '\r' || source[offset] == '\n',
    }
}

// Copy complete graphemes into one clipped summary or soft-wrapped preview row.
terminal_explorer_text_row :: proc(
    source: string, start, columns: int, storage: []u8,
    flatten: bool = false) -> Terminal_Explorer_Text_Row {
    result: Terminal_Explorer_Text_Row = {
        source_start = start,
        source_end = start,
        next = start,
    }
    length := 0
    for result.next < len(source) {
        fragment := terminal_explorer_text_fragment(
            source, result.next, flatten)
        if fragment.hard_break {
            result.next = fragment.next
            result.hard_break = true
            break
        }
        if fragment.columns > columns && result.columns == 0 {
            fragment.text, fragment.columns = "?", 1
        }
        if result.columns + fragment.columns > columns ||
            length + len(fragment.text) > len(storage) {
            break
        }
        copy(storage[length:], fragment.text)
        length += len(fragment.text)
        result.columns += fragment.columns
        result.source_end = fragment.source_end
        result.next = fragment.next
    }
    result.text = string(storage[:length])
    return result
}

// Count bounded source wraps using the same iterator and width as visible drawing.
terminal_explorer_preview_line_count :: proc(source: string, columns: int) -> int {
    buffer: [4096]u8
    offset := 0
    count := 0
    for offset < len(source) {
        row := terminal_explorer_text_row(source, offset, columns, buffer[:])
        if row.next <= offset {
            break
        }
        offset = row.next
        count += 1
    }
    if len(source) > 0 && (source[len(source) - 1] == '\r' ||
        source[len(source) - 1] == '\n') {
        count += 1
    }
    return max(1, count)
}

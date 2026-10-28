package uiterminal

import coretext "../../../core/text"
import "core:unicode/utf8"

// One bounded presentation row; source offsets always refer to the unchanged source.
Terminal_Explorer_Text_Row :: struct {
    text: string,
    next: int,
    columns: int,
}

// Replace controls for display only; never feed retained source through the interpreter.
terminal_explorer_safe_cluster :: proc(
    source: string, start, end: int) -> (string, int) {
    value, _ := utf8.decode_rune(source[start:end])
    if value == '\n' || value == '\r' {
        return " \\ ", 3
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

// Copy complete graphemes into one clipped summary or soft-wrapped preview row.
terminal_explorer_text_row :: proc(
    source: string, start, columns: int, storage: []u8,
    flatten: bool = false) -> Terminal_Explorer_Text_Row {
    result: Terminal_Explorer_Text_Row = {
        next = start,
    }
    length := 0
    for result.next < len(source) {
        offset := result.next
        end := coretext.text_grapheme_next_boundary(source, offset)
        if !flatten && (source[offset] == '\r' || source[offset] == '\n') {
            result.next = end
            break
        }
        text, width := terminal_explorer_safe_cluster(source, offset, end)
        if width > columns && length == 0 {
            text, width = "?", 1
        }
        if result.columns + width > columns || length + len(text) > len(storage) {
            break
        }
        copy(storage[length:], text)
        length += len(text)
        result.columns += width
        result.next = end
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

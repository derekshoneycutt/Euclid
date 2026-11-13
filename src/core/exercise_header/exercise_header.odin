package exerciseheader

import "core:unicode"
import "core:unicode/utf8"
import "core:strings"

EXERCISE_HEADER_MAX_TEXT_BYTES :: 32 * 1024

// State owns the bounded plain-text exercise header for the application lifetime.
State :: struct {
    text: [EXERCISE_HEADER_MAX_TEXT_BYTES]u8,
    count: int,
    revision: u64,
    last_request_id: u64,
    visible: bool,
    expanded: bool,
    scroll_y: f32,
    scroll_max: f32,
    scroll_dragging: bool,
    scroll_drag_off: f32,
}

// Accept nonempty, valid UTF-8 text that contains no NUL or Unicode-whitespace-only value.
text_is_valid :: proc(source: []u8) -> bool {
    if len(source) == 0 || len(source) > EXERCISE_HEADER_MAX_TEXT_BYTES {
        return false
    }
    value := transmute(string)source
    if !utf8.valid_string(value) || strings.contains(value, "\x00") {
        return false
    }
    for offset := 0; offset < len(source); {
        character, width := utf8.decode_rune(source[offset:])
        if !unicode.is_space(character) {
            return true
        }
        offset += width
    }
    return false
}

// Replace the visible header only after the complete source passes validation.
show :: proc(state: ^State, source: []u8) -> bool {
    if state == nil || !text_is_valid(source) {
        return false
    }
    copy(state^.text[:], source)
    state^.count = len(source)
    state^.visible = true
    state^.expanded = false
    state^.scroll_y = 0
    state^.scroll_max = 0
    state^.scroll_dragging = false
    state^.scroll_drag_off = 0
    state^.revision = next_revision(state^.revision)
    return true
}

// Dismiss the header without affecting Terminal or construction state.
hide :: proc(state: ^State) {
    if state == nil || !state^.visible && state^.count == 0 {
        return
    }
    state^.visible = false
    state^.count = 0
    state^.expanded = false
    state^.scroll_y = 0
    state^.scroll_max = 0
    state^.scroll_dragging = false
    state^.scroll_drag_off = 0
    state^.revision = next_revision(state^.revision)
}

// Advance a revision while reserving zero for the never-updated state.
next_revision :: #force_inline proc(revision: u64) -> u64 {
    result := revision + 1
    return 1 if result == 0 else result
}

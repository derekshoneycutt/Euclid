package termhist

import "core:mem"
import utf8 "core:unicode/utf8"

// Termhist_Entry stores one committed UTF-8 line snapshot.
//
// Notes:
//   - `tag` is opaque caller metadata (e.g. which input mode produced the
//     entry) restored verbatim when browsing back to this entry.
Termhist_Entry :: struct {
    text: []u8,
    tag: int,
}

// Termhist_Font_Weight selects a supplied JuliaMono weight for one text run.
Termhist_Font_Weight :: enum {
    Regular,
    Light,
    Medium,
    Semi_Bold,
    Bold,
    Extra_Bold,
    Black,
}

// Termhist_Text_Style stores render style metadata for one output run.
Termhist_Text_Style :: struct {
    color_rgba: u32,
    font_weight: Termhist_Font_Weight,
    is_bold: bool,
    is_italic: bool,
    is_underline: bool,
}

// Termhist_State stores the current editable line plus committed history.
//
// Notes:
//   - Retains one free-capable allocator for all long-lived text storage.
//   - Treats the active line as UTF-8 bytes with its cursor measured in byte
//     offsets on codepoint boundaries.
Termhist_State :: struct {
    allocator: mem.Allocator,

    text: []u8,
    text_len: int,

    backup: []u8,
    backup_len: int,

    history: []Termhist_Entry,
    history_len: int,
    history_index: int,

    cursor: int,
}

//   Allocate every slice required by one history state.
//
// Returns:
//   - True after all slices are assigned; false after the first allocation failure.
termhist_allocate_storage :: proc(
    state: ^Termhist_State, text_capacity, history_capacity: int) -> bool {
    text, text_err := make([]u8, text_capacity, state.allocator)
    if text_err != nil {
        return false
    }
    state.text = text
    backup, backup_err := make([]u8, text_capacity, state.allocator)
    if backup_err != nil {
        return false
    }
    state.backup = backup
    history, history_err := make(
        []Termhist_Entry, history_capacity, state.allocator)
    if history_err != nil {
        return false
    }
    state.history = history
    return true
}

//   Initialize caller-owned UTF-8 editing state with explicit storage ownership.
//
// Parameters:
//   - state: Zero-valued destination owned by the caller.
//   - initial_text_capacity: Initial byte capacity reserved for the live line.
//   - initial_history_capacity: Initial entry capacity reserved for committed history.
//
// Returns:
//   - True after initialization; false for nil state or allocation failure.
//
// Side effects:
//   - Allocates initial editable and history storage from `allocator`.
termhist_init_with_allocator :: proc(
    state: ^Termhist_State,
    initial_text_capacity, initial_history_capacity: int,
    allocator: mem.Allocator) -> bool {
    if state == nil {
        return false
    }
    text_capacity := initial_text_capacity
    if text_capacity < 1 {
        text_capacity = 1
    }

    history_capacity := initial_history_capacity
    if history_capacity < 1 {
        history_capacity = 1
    }

    state^ = {allocator = allocator}

    if !termhist_allocate_storage(state, text_capacity, history_capacity) {
        termhist_destroy(state)
        return false
    }
    state.text_len = 0
    state.backup_len = 0
    state.history_len = 0
    state.history_index = 0
    state.cursor = 0

    return true
}

//   Release all persistent storage owned by a term history state.
//
// Parameters:
//   - state: Caller-owned state initialized by termhist_init.
//
// Side effects:
//   - Releases every owned entry and backing slice, then clears the state.
termhist_destroy :: proc(state: ^Termhist_State) {
    if state == nil {
        return
    }

    for entry in state.history[:state.history_len] {
        delete(entry.text, state.allocator)
    }
    delete(state.history, state.allocator)
    delete(state.backup, state.allocator)
    delete(state.text, state.allocator)
    state^ = {}
}

//   Return the current editable line as a UTF-8 string view.
//
// Parameters:
//   - state: The active term history state.
//
// Returns:
//   - The current line contents.
termhist_current_text :: proc(state: ^Termhist_State) -> string {
    return string(state.text[:state.text_len])
}

//   Return the active UTF-8 cursor byte offset.
//
// Parameters:
//   - state: The active term history state.
//
// Returns:
//   - The cursor position on a codepoint boundary.
termhist_cursor :: proc(state: ^Termhist_State) -> int {
    return state.cursor
}

//   Clear the active line without modifying history.
//
// Parameters:
//   - state: The active term history state.
//
// Side effects:
//   - Clears the live buffer and resets the cursor.
termhist_clear :: proc(state: ^Termhist_State) {
    state.text_len = 0
    state.cursor = 0
    state.history_index = state.history_len
}

//   Insert UTF-8 text at the cursor.
//
// Parameters:
//   - state: The active term history state.
//   - text: UTF-8 bytes to insert.
//
// Returns:
//   - true if the insertion succeeded.
termhist_insert_text :: proc(state: ^Termhist_State, text: string) -> bool {
    if len(text) == 0 {
        return true
    }

    termhist_end_history_browse(state)
    return termhist_replace_range(state, state.cursor, state.cursor, text)
}

//   Replace an explicit UTF-8 codepoint-aligned byte range in the live input.
//
// Parameters:
//   - state: The active term history state.
//   - start: Inclusive byte offset at a UTF-8 codepoint boundary.
//   - end: Exclusive byte offset at a UTF-8 codepoint boundary.
//   - replacement: UTF-8 text to insert.
//
// Returns:
//   - true if the aligned range was replaced and the cursor now follows it.
termhist_replace_input_range :: proc(
    state: ^Termhist_State, start, end: int, replacement: string) -> bool {
    if state == nil || start < 0 || end < start || end > state.text_len {
        return false
    }
    if start > 0 && start < state.text_len && utf8_is_continuation(state.text[start]) {
        return false
    }
    if end > 0 && end < state.text_len && utf8_is_continuation(state.text[end]) {
        return false
    }

    termhist_end_history_browse(state)
    return termhist_replace_range(state, start, end, replacement)
}

//   Delete the UTF-8 codepoint before the cursor.
//
// Parameters:
//   - state: The active term history state.
//
// Returns:
//   - true if anything was deleted.
termhist_backspace :: proc(state: ^Termhist_State) -> bool {
    termhist_end_history_browse(state)

    if state.cursor == 0 {
        return false
    }

    start := utf8_prev_boundary(state.text, state.cursor)
    return termhist_replace_range(state, start, state.cursor, "")
}

//   Delete the UTF-8 codepoint at the cursor.
//
// Parameters:
//   - state: The active term history state.
//
// Returns:
//   - true if anything was deleted.
termhist_delete_forward :: proc(state: ^Termhist_State) -> bool {
    termhist_end_history_browse(state)

    if state.cursor >= state.text_len {
        return false
    }

    end := utf8_next_boundary(state.text, state.cursor, state.text_len)
    return termhist_replace_range(state, state.cursor, end, "")
}

//   Move the cursor one UTF-8 codepoint to the left.
//
// Parameters:
//   - state: The active term history state.
//
// Returns:
//   - true if the cursor moved.
termhist_move_left :: proc(state: ^Termhist_State) -> bool {
    termhist_end_history_browse(state)

    if state.cursor == 0 {
        return false
    }

    state.cursor = utf8_prev_boundary(state.text, state.cursor)
    return true
}

//   Move the cursor one UTF-8 codepoint to the right.
//
// Parameters:
//   - state: The active term history state.
//
// Returns:
//   - true if the cursor moved.
termhist_move_right :: proc(state: ^Termhist_State) -> bool {
    termhist_end_history_browse(state)

    if state.cursor >= state.text_len {
        return false
    }

    state.cursor = utf8_next_boundary(state.text, state.cursor, state.text_len)
    return true
}

//   Move the cursor to the start of the active line.
//
// Parameters:
//   - state: The active term history state.
//
// Returns:
//   - true if the cursor moved.
termhist_move_home :: proc(state: ^Termhist_State) -> bool {
    termhist_end_history_browse(state)

    moved := state.cursor != 0
    state.cursor = 0
    return moved
}

//   Move the cursor to the end of the active line.
//
// Parameters:
//   - state: The active term history state.
//
// Returns:
//   - true if the cursor moved.
termhist_move_end :: proc(state: ^Termhist_State) -> bool {
    termhist_end_history_browse(state)

    moved := state.cursor != state.text_len
    state.cursor = state.text_len
    return moved
}

//   Accept the current line into committed history and clear the editor.
//
// Parameters:
//   - state: The active term history state.
//   - tag: Opaque caller metadata recorded with the committed entry.
//   - replace_latest: Replace the newest provisional entry instead of appending.
//
// Returns:
//   - true if a non-empty line was committed.
termhist_accept_current :: proc(
    state: ^Termhist_State, tag: int = 0, replace_latest: bool = false) -> bool {
    termhist_end_history_browse(state)

    if state.text_len == 0 {
        termhist_clear(state)
        return false
    }

    text := string(state.text[:state.text_len])
    if replace_latest && state.history_len > 0 {
        entry_text, ok := termhist_clone_text(state.allocator, text)
        if !ok {
            return false
        }
        old_text := state.history[state.history_len - 1].text
        state.history[state.history_len - 1] =
            Termhist_Entry{text = entry_text, tag = tag}
        delete(old_text, state.allocator)
        termhist_clear(state)
        return true
    }

    if !termhist_history_push(state, text, tag) {
        return false
    }

    termhist_clear(state)
    return true
}

//   Step to the previous committed entry and load it into the editor.
//
// Parameters:
//   - state: The active term history state.
//
// Returns:
//   - true if a previous entry was loaded.
termhist_history_prev :: proc(state: ^Termhist_State) -> bool {
    if state.history_len == 0 {
        return false
    }

    if state.history_index == state.history_len {
        if !termhist_backup_current(state) {
            return false
        }
    }

    if state.history_index <= 0 {
        return false
    }

    state.history_index -= 1
    return termhist_load_entry(state, state.history[state.history_index].text)
}

//   Step to the next committed entry or return to the preserved draft.
//
// Parameters:
//   - state: The active term history state.
//
// Returns:
//   - true if the editor contents changed.
termhist_history_next :: proc(state: ^Termhist_State) -> bool {
    if state.history_len == 0 {
        return false
    }

    if state.history_index == state.history_len {
        return false
    }

    if state.history_index + 1 < state.history_len {
        state.history_index += 1
        return termhist_load_entry(state, state.history[state.history_index].text)
    }

    state.history_index = state.history_len
    return termhist_load_entry(state, state.backup[:state.backup_len])
}

//   Return the editor to browsing mode after mutation.
//
// Parameters:
//   - state: The active term history state.
termhist_end_history_browse :: proc(state: ^Termhist_State) {
    if state.history_index == state.history_len {
        return
    }

    state.history_index = state.history_len
}

//   Append a committed UTF-8 snapshot to the growing history store.
//
// Parameters:
//   - state: The active term history state.
//   - text: UTF-8 bytes to clone into persistent history storage.
//   - tag: Opaque caller metadata recorded with the entry.
//
// Returns:
//   - true if the snapshot was cloned and recorded.
termhist_history_push :: proc(
    state: ^Termhist_State, text: string, tag: int = 0) -> bool {
    if !termhist_ensure_history_capacity(state, state.history_len + 1) {
        return false
    }

    entry_text, ok := termhist_clone_text(state.allocator, text)
    if !ok {
        return false
    }

    state.history[state.history_len] = Termhist_Entry{text = entry_text, tag = tag}
    state.history_len += 1
    state.history_index = state.history_len
    return true
}

//   Preserve the current line so browsing back to history can restore it later.
//
// Parameters:
//   - state: The active term history state.
//
// Returns:
//   - true if the draft was copied into backup storage.
termhist_backup_current :: proc(state: ^Termhist_State) -> bool {
    if !termhist_ensure_u8_capacity(state, &state.backup,
        state.text_len, state.backup_len) {
        return false
    }

    if state.text_len > 0 {
        copy(state.backup[:state.text_len], state.text[:state.text_len])
    }

    state.backup_len = state.text_len
    state.history_index = state.history_len
    return true
}

//   Load a UTF-8 byte slice into the live editor buffer.
//
// Parameters:
//   - state: The active term history state.
//   - text: UTF-8 bytes to copy into the live editor buffer.
//
// Returns:
//   - true if the live buffer was resized and updated.
termhist_load_entry :: proc(state: ^Termhist_State, text: []u8) -> bool {
    if !termhist_ensure_u8_capacity(state, &state.text, len(text), state.text_len) {
        return false
    }

    if len(text) > 0 {
        copy(state.text[:len(text)], text)
    }

    state.text_len = len(text)
    state.cursor = state.text_len
    return true
}

//   Replace a byte range in the live line with new UTF-8 bytes.
//
// Parameters:
//   - state: The active term history state.
//   - start: Inclusive byte index for the replacement range.
//   - end: Exclusive byte index for the replacement range.
//   - replacement: UTF-8 bytes to splice into the range.
//
// Returns:
//   - true if the replacement succeeded.
termhist_replace_range :: proc(
    state: ^Termhist_State, start, end: int, replacement: string) -> bool {
    if start < 0 || end < start || end > state.text_len {
        return false
    }

    delete_len := end - start
    insert_len := len(replacement)
    new_len := state.text_len - delete_len + insert_len

    if !termhist_ensure_u8_capacity(state, &state.text, new_len, state.text_len) {
        return false
    }

    if insert_len > delete_len {
        shift := insert_len - delete_len
        i := state.text_len
        for i > end {
            i -= 1
            state.text[i + shift] = state.text[i]
        }
    } else if insert_len < delete_len {
        tail_count := state.text_len - end
        for i := 0; i < tail_count; i += 1 {
            state.text[start + insert_len + i] = state.text[end + i]
        }
    }

    if insert_len > 0 {
        copy(state.text[start:start + insert_len], replacement)
    }

    state.text_len = new_len
    state.cursor = start + insert_len
    return true
}

//   Grow the history entry slice when another committed line is appended.
//
// Parameters:
//   - state: The active term history state.
//   - needed: The minimum number of committed entries required.
//
// Returns:
//   - true if storage was already large enough or could be grown.
termhist_ensure_history_capacity :: proc(state: ^Termhist_State, needed: int) -> bool {
    if needed <= len(state.history) {
        return true
    }

    new_capacity := len(state.history) * 2
    if new_capacity < needed {
        new_capacity = needed
    }

    new_history, history_err := make(
        []Termhist_Entry, new_capacity, state.allocator)
    if history_err != nil {
        return false
    }

    if state.history_len > 0 {
        copy(new_history[:state.history_len], state.history[:state.history_len])
    }

    delete(state.history, state.allocator)
    state.history = new_history
    return true
}

//   Grow a mutable UTF-8 byte buffer while preserving the requested prefix.
//
// Parameters:
//   - state: The active term history state.
//   - buffer: The buffer field to resize.
//   - needed: The minimum byte capacity required.
//   - copy_len: The number of bytes to preserve from the current buffer.
//
// Returns:
//   - true if the buffer was already large enough or could be grown.
termhist_ensure_u8_capacity :: proc(
    state: ^Termhist_State, buffer: ^[]u8, needed, copy_len: int) -> bool {
    current := buffer^
    if needed <= len(current) {
        return true
    }

    new_capacity := len(current) * 2
    if new_capacity < needed {
        new_capacity = needed
    }

    new_buffer, buffer_err := make([]u8, new_capacity, state.allocator)
    if buffer_err != nil {
        return false
    }

    if copy_len > 0 {
        copy(new_buffer[:copy_len], current[:copy_len])
    }

    delete(current, state.allocator)
    buffer^ = new_buffer
    return true
}

//   Clone UTF-8 text into allocator-backed persistent storage.
//
// Parameters:
//   - allocator: Free-capable allocator that owns the cloned bytes.
//   - text: UTF-8 bytes to duplicate.
//
// Returns:
//   - A fresh byte slice and true on success.
//   - nil and false on allocation failure.
termhist_clone_text :: proc(
    allocator: mem.Allocator, text: string) -> ([]u8, bool) {
    cloned, clone_err := make([]u8, len(text), allocator)
    if clone_err != nil {
        return nil, false
    }

    if len(text) > 0 {
        copy(cloned[:len(text)], text)
    }

    return cloned, true
}

//   Step left to the previous UTF-8 codepoint boundary.
//
// Parameters:
//   - text: The UTF-8 byte slice being edited.
//   - index: Current byte offset.
//
// Returns:
//   - The preceding UTF-8 boundary, clamped to the buffer start.
utf8_prev_boundary :: proc(text: []u8, index: int) -> int {
    if index <= 0 {
        return 0
    }

    _, width := utf8.decode_last_rune_in_bytes(text[:index])
    return index - width
}

//   Step right to the next UTF-8 codepoint boundary.
//
// Parameters:
//   - text: The UTF-8 byte slice being edited.
//   - index: Current byte offset.
//   - limit: Upper byte bound for the active buffer.
//
// Returns:
//   - The next UTF-8 boundary, clamped to the provided limit.
utf8_next_boundary :: proc(text: []u8, index, limit: int) -> int {
    if index >= limit {
        return limit
    }

    _, width := utf8.decode_rune_in_bytes(text[index:limit])
    next := index + width
    if next > limit {
        next = limit
    }

    return next
}

//   Report whether a byte is a UTF-8 continuation byte.
//
// Parameters:
//   - b: The byte to classify.
//
// Returns:
//   - true when the byte has UTF-8 continuation-bit form.
utf8_is_continuation :: proc(b: u8) -> bool {
    return (b & 0xC0) == 0x80
}

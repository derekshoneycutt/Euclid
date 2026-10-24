package termhist

import "core:mem"
import coretext "../../core/text"
import "core:unicode"
import utf8 "core:unicode/utf8"

// Termhist_Entry stores one committed UTF-8 line snapshot.
//
// Notes:
//   - `tag` is opaque caller metadata (e.g. which input mode produced the
//     entry) restored verbatim when browsing back to this entry.
Termhist_Entry :: struct {
    text: []u8,
    tag: int,
    id: u64,
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

// Termhist_Visual_Row_Bounds stores one row's byte interval and lookup status.
Termhist_Visual_Row_Bounds :: struct {
    start: int,
    end: int,
    found: bool,
}

// Termhist_State stores the current editable line plus committed history.
//
// Notes:
//   - Manages editor buffers and retained history through a borrowed allocation domain.
//   - Treats the active line as UTF-8 bytes with its cursor measured in byte
//     offsets on extended-grapheme boundaries.
Termhist_State :: struct {
    // Production normally borrows the animation-generation arena.
    // History issues release calls on replacement and teardown; actual reclamation
    // follows allocator policy. The domain must remain valid through teardown.
    borrowed_allocator: mem.Allocator,

    text: []u8,
    text_len: int,

    backup: []u8,
    backup_len: int,
    backup_cursor: int,
    backup_anchor: int,
    backup_preferred_column: int,

    history: []Termhist_Entry,
    history_len: int,
    history_index: int,

    cursor: int,
    anchor: int,
    preferred_column: int,
    content_revision: u64,
    reset_revision: u64,
    next_entry_id: u64,
    preedit: [32]u8,
    preedit_length: int,
    preedit_selection_start: int,
    preedit_selection_end: int,
    preedit_replace_cursor: int,
    preedit_replace_anchor: int,
    preedit_content_revision: u64,
    preedit_active: bool,
}

//   Allocate every slice required by one history state.
//
// Returns:
//   - True after all slices are assigned; false after the first allocation failure.
termhist_allocate_storage :: proc(
    state: ^Termhist_State, text_capacity, history_capacity: int) -> bool {
    text, text_err := make([]u8, text_capacity, state.borrowed_allocator)
    if text_err != nil {
        return false
    }
    state.text = text
    backup, backup_err := make([]u8, text_capacity, state.borrowed_allocator)
    if backup_err != nil {
        return false
    }
    state.backup = backup
    history, history_err := make(
        []Termhist_Entry, history_capacity, state.borrowed_allocator)
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

    state^ = {borrowed_allocator = allocator}

    if !termhist_allocate_storage(state, text_capacity, history_capacity) {
        termhist_destroy(state)
        return false
    }
    state.text_len = 0
    state.backup_len = 0
    state.history_len = 0
    state.history_index = 0
    state.cursor = 0
    state.anchor = 0
    state.preferred_column = -1
    state.backup_preferred_column = -1

    return true
}

//   Release all persistent storage owned by a term history state.
//
// Parameters:
//   - state: Caller-owned state initialized by termhist_init.
//
// Side effects:
//   - Issues release calls for every owned entry and backing slice, then clears state.
//     The borrowed allocator determines when backing memory is reclaimed.
termhist_destroy :: proc(state: ^Termhist_State) {
    if state == nil {
        return
    }

    for entry in state.history[:state.history_len] {
        delete(entry.text, state.borrowed_allocator)
    }
    delete(state.history, state.borrowed_allocator)
    delete(state.backup, state.borrowed_allocator)
    delete(state.text, state.borrowed_allocator)
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
//   - The cursor position on an extended-grapheme boundary.
termhist_cursor :: proc(state: ^Termhist_State) -> int {
    return state.cursor
}

// Return the live draft's selection anchor byte offset.
termhist_anchor :: proc(state: ^Termhist_State) -> int {
    if state == nil {
        return 0
    }
    return state.anchor
}

// termhist_content_revision returns the live input's monotonic content generation.
termhist_content_revision :: proc(state: ^Termhist_State) -> u64 {
    if state == nil {
       return 0
    }
    return state.content_revision
}

// termhist_clear_preedit discards uncommitted IME text without editing the draft.
termhist_clear_preedit :: proc(state: ^Termhist_State) {
    if state == nil {
        return
    }
    state.preedit_active = false
    state.preedit_length = 0
}

// termhist_preedit_byte_offset maps a codepoint offset into bounded UTF-8 text.
termhist_preedit_byte_offset :: proc(text: string, codepoints: int) -> int {
    if codepoints <= 0 {
        return 0
    }
    offset, remaining := 0, codepoints
    for offset < len(text) && remaining > 0 {
        _, width := utf8.decode_rune(text[offset:])
        offset += width
        remaining -= 1
    }
    return offset
}

// termhist_update_preedit retains a bounded composition snapshot at the live cursor.
termhist_update_preedit :: proc(
    state: ^Termhist_State,
    text: string,
    selection_start, selection_length: i32) -> bool {
    if state == nil || !utf8.valid_string(text) || len(text) > len(state.preedit) {
        return false
    }
    if len(text) == 0 {
        termhist_clear_preedit(state)
        return true
    }
    if !state.preedit_active {
        state.preedit_replace_cursor = state.cursor
        state.preedit_replace_anchor = state.anchor
        state.preedit_content_revision = state.content_revision
        state.preedit_active = true
    }
    copy(state.preedit[:len(text)], transmute([]u8)text)
    state.preedit_length = len(text)
    source := string(state.preedit[:state.preedit_length])
    rune_count := utf8.rune_count(source)
    first_codepoint := clamp(int(selection_start), 0, rune_count)
    selection_count := clamp(
        int(selection_length), 0, rune_count - first_codepoint)
    first := termhist_preedit_byte_offset(source, first_codepoint)
    last := termhist_preedit_byte_offset(
        source, first_codepoint + selection_count)
    state.preedit_selection_start =
        coretext.text_grapheme_clamp_boundary(source, first)
    state.preedit_selection_end =
        coretext.text_grapheme_clamp_boundary(source, last)
    return true
}

// termhist_commit_text atomically replaces the captured preedit anchor or live cursor.
termhist_commit_text :: proc(state: ^Termhist_State, text: string) -> bool {
    if state == nil || !utf8.valid_string(text) {
        return false
    }
    start, end := termhist_selection_range(state)
    if state.preedit_active {
        if state.preedit_content_revision != state.content_revision ||
            state.preedit_replace_cursor != state.cursor ||
            state.preedit_replace_anchor != state.anchor {
            termhist_clear_preedit(state)
            return false
        }
    }
    termhist_clear_preedit(state)
    changed := termhist_replace_normalized_range(state, start, end, text)
    if changed {
        termhist_end_history_browse(state)
    }
    return changed
}

// Identify whole-buffer resets independently of ordinary range edits.
termhist_reset_revision :: proc(state: ^Termhist_State) -> u64 {
    if state == nil {
        return 0
    }
    return state.reset_revision
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
    state.anchor = 0
    state.preferred_column = -1
    state.history_index = state.history_len
    state.content_revision += 1
    state.reset_revision += 1
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
    if !utf8.valid_string(text) {
        return false
    }
    start, end := termhist_selection_range(state)
    changed := termhist_replace_normalized_range(state, start, end, text)
    if changed {
        termhist_end_history_browse(state)
    }
    return changed
}

// termhist_replace_normalized_range atomically replaces after normalizing CR line endings.
termhist_replace_normalized_range :: proc(
    state: ^Termhist_State, start, end: int, replacement: string) -> bool {
    if !termhist_contains_carriage_return(replacement) {
        return termhist_replace_range(state, start, end, replacement)
    }
    normalized_length := termhist_normalized_newline_length(replacement)
    normalized, allocation_error := make(
        []u8, normalized_length, state.borrowed_allocator)
    if allocation_error != nil {
        return false
    }
    defer delete(normalized, state.borrowed_allocator)
    termhist_copy_normalized_newlines(normalized, replacement)
    return termhist_replace_range(
        state, start, end, string(normalized))
}

// Report whether input needs line-ending normalization.
termhist_contains_carriage_return :: proc(text: string) -> bool {
    for byte in text {
        if byte == '\r' {
            return true
        }
    }
    return false
}

// Count bytes after converting CRLF and CR newline forms to LF.
termhist_normalized_newline_length :: proc(text: string) -> int {
    length := 0
    offset := 0
    for offset < len(text) {
        if text[offset] == '\r' {
            length += 1
            offset += 1
            if offset < len(text) && text[offset] == '\n' {
                offset += 1
            }
        } else {
            length += 1
            offset += 1
        }
    }
    return length
}

// Copy text into caller-owned storage while normalizing terminal line endings.
termhist_copy_normalized_newlines :: proc(destination: []u8, text: string) {
    target := 0
    offset := 0
    for offset < len(text) {
        if text[offset] == '\r' {
            destination[target] = '\n'
            target += 1
            offset += 1
            if offset < len(text) && text[offset] == '\n' {
                offset += 1
            }
        } else {
            destination[target] = text[offset]
            target += 1
            offset += 1
        }
    }
}

//   Replace an explicit grapheme-aligned byte range in the live input.
//
// Parameters:
//   - state: The active term history state.
//   - start: Inclusive byte offset at a grapheme boundary.
//   - end: Exclusive byte offset at a grapheme boundary.
//   - replacement: UTF-8 text to insert.
//
// Returns:
//   - true if the aligned range was replaced and the cursor now follows it.
termhist_replace_input_range :: proc(
    state: ^Termhist_State, start, end: int, replacement: string) -> bool {
    if state == nil || start < 0 || end < start || end > state.text_len ||
        !utf8.valid_string(string(state.text[:state.text_len])) ||
        !utf8.valid_string(replacement) {
        return false
    }
    source := string(state.text[:state.text_len])
    if coretext.text_grapheme_clamp_boundary(source, start) != start ||
        coretext.text_grapheme_clamp_boundary(source, end) != end {
        return false
    }

    changed := termhist_replace_normalized_range(
        state, start, end, replacement)
    if changed {
        termhist_end_history_browse(state)
    }
    return changed
}

//   Delete the grapheme before the cursor.
//
// Parameters:
//   - state: The active term history state.
//
// Returns:
//   - true if anything was deleted.
termhist_backspace :: proc(state: ^Termhist_State) -> bool {
    if start, end := termhist_selection_range(state); start != end {
        changed := termhist_replace_range(state, start, end, "")
        if changed {
            termhist_end_history_browse(state)
        }
        return changed
    }
    if state.cursor == 0 {
        return false
    }

    start := coretext.text_grapheme_previous_boundary(
        string(state.text[:state.text_len]), state.cursor)
    changed := termhist_replace_range(state, start, state.cursor, "")
    if changed {
        termhist_end_history_browse(state)
    }
    return changed
}

//   Delete the grapheme at the cursor.
//
// Parameters:
//   - state: The active term history state.
//
// Returns:
//   - true if anything was deleted.
termhist_delete_forward :: proc(state: ^Termhist_State) -> bool {
    if start, end := termhist_selection_range(state); start != end {
        changed := termhist_replace_range(state, start, end, "")
        if changed {
            termhist_end_history_browse(state)
        }
        return changed
    }
    if state.cursor >= state.text_len {
        return false
    }

    end := coretext.text_grapheme_next_boundary(
        string(state.text[:state.text_len]), state.cursor)
    changed := termhist_replace_range(state, state.cursor, end, "")
    if changed {
        termhist_end_history_browse(state)
    }
    return changed
}

//   Move the cursor one grapheme to the left.
//
// Parameters:
//   - state: The active term history state.
//
// Returns:
//   - true if the cursor moved.
termhist_move_left :: proc(state: ^Termhist_State, extend := false) -> bool {
    termhist_end_history_browse(state)

    if !extend && state.anchor != state.cursor {
        state.cursor = min(state.anchor, state.cursor)
        state.anchor = state.cursor
        state.preferred_column = -1
        return true
    }
    if state.cursor == 0 {
        return false
    }

    if !extend {
        state.anchor = state.cursor
    }
    state.cursor = coretext.text_grapheme_previous_boundary(
        string(state.text[:state.text_len]), state.cursor)
    if !extend {
        state.anchor = state.cursor
    }
    state.preferred_column = -1
    return true
}

//   Move the cursor one grapheme to the right.
//
// Parameters:
//   - state: The active term history state.
//
// Returns:
//   - true if the cursor moved.
termhist_move_right :: proc(state: ^Termhist_State, extend := false) -> bool {
    termhist_end_history_browse(state)

    if !extend && state.anchor != state.cursor {
        state.cursor = max(state.anchor, state.cursor)
        state.anchor = state.cursor
        state.preferred_column = -1
        return true
    }
    if state.cursor >= state.text_len {
        return false
    }

    if !extend {
        state.anchor = state.cursor
    }
    state.cursor = coretext.text_grapheme_next_boundary(
        string(state.text[:state.text_len]), state.cursor)
    if !extend {
        state.anchor = state.cursor
    }
    state.preferred_column = -1
    return true
}

//   Move the cursor to the start of the active line.
//
// Parameters:
//   - state: The active term history state.
//
// Returns:
//   - true if the cursor moved.
termhist_move_home :: proc(state: ^Termhist_State, extend := false) -> bool {
    termhist_end_history_browse(state)
    text := string(state.text[:state.text_len])
    start := state.cursor
    for start > 0 && text[start - 1] != '\n' {
        start -= 1
    }
    moved := state.cursor != start
    state.cursor = start
    if !extend {
        state.anchor = start
    }
    state.preferred_column = -1
    return moved
}

//   Move the cursor to the end of the active line.
//
// Parameters:
//   - state: The active term history state.
//
// Returns:
//   - true if the cursor moved.
termhist_move_end :: proc(state: ^Termhist_State, extend := false) -> bool {
    termhist_end_history_browse(state)
    text := string(state.text[:state.text_len])
    end := state.cursor
    for end < len(text) && text[end] != '\n' {
        end += 1
    }
    moved := state.cursor != end
    state.cursor = end
    if !extend {
        state.anchor = end
    }
    state.preferred_column = -1
    return moved
}

// Return the ordered byte range currently selected in the editable draft.
termhist_selection_range :: proc(state: ^Termhist_State) -> (int, int) {
    return min(state.cursor, state.anchor), max(state.cursor, state.anchor)
}

// Set the cursor to a grapheme boundary, optionally extending the current selection.
termhist_set_cursor :: proc(
    state: ^Termhist_State, cursor: int, extend := false) -> bool {
    text := string(state.text[:state.text_len])
    target := coretext.text_grapheme_clamp_boundary(text, clamp(cursor, 0, len(text)))
    if !extend || state.anchor == state.cursor {
        state.anchor = state.cursor if extend else target
    }
    moved := target != state.cursor
    state.cursor = target
    state.preferred_column = -1
    termhist_end_history_browse(state)
    return moved
}

// Move to the start of the entire draft.
termhist_move_buffer_home :: proc(state: ^Termhist_State, extend := false) -> bool {
    termhist_end_history_browse(state)
    moved := termhist_set_cursor(state, 0, extend)
    state.preferred_column = -1
    return moved
}

// Move to the end of the entire draft.
termhist_move_buffer_end :: proc(state: ^Termhist_State, extend := false) -> bool {
    termhist_end_history_browse(state)
    moved := termhist_set_cursor(state, state.text_len, extend)
    state.preferred_column = -1
    return moved
}

// Resolve a whitespace-delimited grapheme boundary in the requested direction.
termhist_word_boundary :: proc(text: string, cursor: int, left: bool) -> int {
    return termhist_word_boundary_left(text, cursor) if left else
        termhist_word_boundary_right(text, cursor)
}

// Resolve the start of the whitespace-delimited word before the cursor.
termhist_word_boundary_left :: proc(text: string, cursor: int) -> int {
    position := cursor
    for position > 0 {
        end := position
        position = coretext.text_grapheme_previous_boundary(text, position)
        if text[position] == '\n' {
            position = end
            break
        }
        if !termhist_grapheme_is_space(text, position, end) {
            break
        }
    }
    for position > 0 {
        end := position
        previous := coretext.text_grapheme_previous_boundary(text, position)
        if text[previous] == '\n' ||
            termhist_grapheme_is_space(text, previous, end) {
            break
        }
        position = previous
    }
    return position
}

// Resolve the end of the whitespace-delimited word after the cursor.
termhist_word_boundary_right :: proc(text: string, cursor: int) -> int {
    position := cursor
    for position < len(text) {
        if text[position] == '\n' {
            break
        }
        end := coretext.text_grapheme_next_boundary(text, position)
        if termhist_grapheme_is_space(text, position, end) {
            break
        }
        position = end
    }
    for position < len(text) {
        if text[position] == '\n' {
            break
        }
        end := coretext.text_grapheme_next_boundary(text, position)
        if !termhist_grapheme_is_space(text, position, end) {
            break
        }
        position = end
    }
    return position
}

// Move by a whitespace-delimited word, extending selection when requested.
termhist_move_word :: proc(
    state: ^Termhist_State, left: bool, extend := false) -> bool {
    text := string(state.text[:state.text_len])
    if !extend && state.anchor != state.cursor {
        target := min(state.anchor, state.cursor) if left else
            max(state.anchor, state.cursor)
        return termhist_set_cursor(state, target)
    }
    target := termhist_word_boundary(text, state.cursor, left)
    return termhist_set_cursor(state, target, extend)
}

// Delete from the cursor to its whitespace-delimited word boundary.
termhist_delete_word :: proc(state: ^Termhist_State, left: bool) -> bool {
    if start, end := termhist_selection_range(state); start != end {
        return termhist_replace_input_range(state, start, end, "")
    }
    target := termhist_word_boundary(
        string(state.text[:state.text_len]), state.cursor, left)
    start, end := min(target, state.cursor), max(target, state.cursor)
    return start != end && termhist_replace_input_range(state, start, end, "")
}

// Return the first rune of a grapheme's whitespace classification.
termhist_grapheme_is_space :: proc(text: string, start, end: int) -> bool {
    if start >= end {
        return false
    }
    value, _ := utf8.decode_rune_in_string(text[start:end])
    return unicode.is_space(value)
}

// Move to the previous or next displayed draft row, retaining the preferred column.
termhist_move_vertical :: proc(
    state: ^Termhist_State, direction, columns: int, extend := false) -> bool {
    if direction == 0 {
        return false
    }
    text := string(state.text[:state.text_len])
    width := max(1, columns)
    row, column := termhist_visual_cursor_row(text, state.cursor, width)
    if state.preferred_column < 0 {
        state.preferred_column = column
    }
    target_row := termhist_visual_row_bounds(
        text, row + (1 if direction > 0 else -1), width)
    if !target_row.found {
        return false
    }
    target := target_row.start + coretext.text_grapheme_boundary_for_column(
        text[target_row.start:target_row.end], state.preferred_column)
    if extend && state.anchor == state.cursor {
        state.anchor = state.cursor
    }
    state.cursor = target
    if !extend {
        state.anchor = target
    }
    termhist_end_history_browse(state)
    return true
}

// Find the visual row and display column containing a grapheme cursor boundary.
termhist_visual_cursor_row :: proc(
    text: string, cursor, columns: int) -> (int, int) {
    row, column := 0, 0
    for position := 0; position < len(text); {
        end := coretext.text_grapheme_next_boundary(text, position)
        if text[position] == '\n' {
            if position == cursor {
                break
            }
            row += 1
            column = 0
            position = end
            continue
        }
        cell_width := coretext.text_grapheme_width(text, position, end)
        if column > 0 && column + cell_width > columns {
            row += 1
            column = 0
        }
        if position == cursor {
            break
        }
        if end > cursor {
            break
        }
        column += cell_width
        position = end
    }
    return row, column
}

// Find the byte bounds of a visual draft row, including soft wrapping.
termhist_visual_row_bounds :: proc(
    text: string, target_row, columns: int) -> Termhist_Visual_Row_Bounds {
    if target_row < 0 {
        return {}
    }
    row, row_start, column := 0, 0, 0
    for position := 0; position < len(text); {
        end := coretext.text_grapheme_next_boundary(text, position)
        if text[position] == '\n' {
            if row == target_row {
                return {start = row_start, end = position, found = true}
            }
            row += 1
            row_start = end
            column = 0
            position = end
            continue
        }
        cell_width := coretext.text_grapheme_width(text, position, end)
        if column > 0 && column + cell_width > columns {
            if row == target_row {
                return {start = row_start, end = position, found = true}
            }
            row += 1
            row_start = position
            column = 0
        }
        column += cell_width
        position = end
    }
    if row == target_row {
        return {start = row_start, end = len(text), found = true}
    }
    return {}
}

// Delete from the cursor to the current logical line start or end.
termhist_delete_to_line_edge :: proc(state: ^Termhist_State, right: bool) -> bool {
    if start, end := termhist_selection_range(state); start != end {
        return termhist_replace_input_range(state, start, end, "")
    }
    text := string(state.text[:state.text_len])
    edge := state.cursor
    if right {
        for edge < len(text) && text[edge] != '\n' {
            edge += 1
        }
    } else {
        for edge > 0 && text[edge - 1] != '\n' {
            edge -= 1
        }
    }
    start, end := min(edge, state.cursor), max(edge, state.cursor)
    return start != end && termhist_replace_input_range(state, start, end, "")
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
        entry_text, ok := termhist_clone_text(state.borrowed_allocator, text)
        if !ok {
            return false
        }
        old_text := state.history[state.history_len - 1].text
        state.next_entry_id += 1
        state.history[state.history_len - 1] =
            Termhist_Entry{text = entry_text, tag = tag, id = state.next_entry_id}
        delete(old_text, state.borrowed_allocator)
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
    if !termhist_load_entry(state, state.backup[:state.backup_len]) {
        return false
    }
    state.cursor = coretext.text_grapheme_clamp_boundary(
        string(state.text[:state.text_len]), state.backup_cursor)
    state.anchor = coretext.text_grapheme_clamp_boundary(
        string(state.text[:state.text_len]), state.backup_anchor)
    state.preferred_column = state.backup_preferred_column
    return true
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

    entry_text, ok := termhist_clone_text(state.borrowed_allocator, text)
    if !ok {
        return false
    }

    state.next_entry_id += 1
    state.history[state.history_len] = Termhist_Entry{
        text = entry_text, tag = tag, id = state.next_entry_id}
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
    state.backup_cursor = state.cursor
    state.backup_anchor = state.anchor
    state.backup_preferred_column = state.preferred_column
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
    state.anchor = state.cursor
    state.preferred_column = -1
    state.content_revision += 1
    state.reset_revision += 1
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
    source := string(state.text[:state.text_len])
    if start < 0 || end < start || end > state.text_len ||
        !utf8.valid_string(source) || !utf8.valid_string(replacement) ||
        coretext.text_grapheme_clamp_boundary(source, start) != start ||
        coretext.text_grapheme_clamp_boundary(source, end) != end {
        return false
    }

    delete_len := end - start
    insert_len := len(replacement)
    new_len := state.text_len - delete_len + insert_len
    if !termhist_ensure_u8_capacity(state, &state.text, new_len, state.text_len) {
        return false
    }
    termhist_shift_replacement_tail(state, start, end, insert_len, delete_len)
    if insert_len > 0 {
        copy(state.text[start:start + insert_len], replacement)
    }
    state.text_len = new_len
    state.cursor = start + insert_len
    state.anchor = state.cursor
    state.preferred_column = -1
    state.content_revision += 1
    return true
}

// Shift the retained input tail to make room for one replacement.
termhist_shift_replacement_tail :: proc(
    state: ^Termhist_State, start, end, insert_len, delete_len: int) {
    if insert_len > delete_len {
        shift := insert_len - delete_len
        for index := state.text_len; index > end; {
            index -= 1
            state.text[index + shift] = state.text[index]
        }
    } else if insert_len < delete_len {
        tail_count := state.text_len - end
        for index in 0..<tail_count {
            state.text[start + insert_len + index] = state.text[end + index]
        }
    }
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
        []Termhist_Entry, new_capacity, state.borrowed_allocator)
    if history_err != nil {
        return false
    }

    if state.history_len > 0 {
        copy(new_history[:state.history_len], state.history[:state.history_len])
    }

    delete(state.history, state.borrowed_allocator)
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

    new_buffer, buffer_err := make([]u8, new_capacity, state.borrowed_allocator)
    if buffer_err != nil {
        return false
    }

    if copy_len > 0 {
        copy(new_buffer[:copy_len], current[:copy_len])
    }

    delete(current, state.borrowed_allocator)
    buffer^ = new_buffer
    return true
}

//   Clone UTF-8 text into allocator-backed persistent storage.
//
// Parameters:
//   - allocator: Borrowed allocation domain for the cloned bytes.
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

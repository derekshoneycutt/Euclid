#+test
package termhist

import "core:testing"

// Resets distinguish identical recalled commands from edits and cursor movement.
@(test)
termhist_test_reset_revision :: proc(t: ^testing.T) {
    state: Termhist_State
    testing.expect(t, termhist_init_with_allocator(
        &state, 8, 1, context.allocator))
    defer termhist_destroy(&state)
    testing.expect(t, termhist_insert_text(&state, "αx"))
    testing.expect(t, termhist_move_left(&state))
    testing.expect(t, termhist_replace_input_range(&state, 2, 3, "y"))
    testing.expect(t, !termhist_replace_input_range(&state, 1, 2, "z"))
    testing.expect_value(t, termhist_reset_revision(&state), u64(0))
    testing.expect(t, termhist_load_entry(&state, state.text[:state.text_len]))
    testing.expect_value(t, termhist_reset_revision(&state), u64(1))
    testing.expect(t, termhist_accept_current(&state))
    testing.expect_value(t, termhist_reset_revision(&state), u64(2))
    testing.expect(t, termhist_insert_text(&state, "draft"))
    testing.expect(t, termhist_history_prev(&state))
    testing.expect_value(t, termhist_reset_revision(&state), u64(3))
    testing.expect(t, termhist_history_next(&state))
    testing.expect_value(t, termhist_current_text(&state), "draft")
    testing.expect_value(t, termhist_reset_revision(&state), u64(4))
    termhist_clear(&state)
    testing.expect(t, termhist_insert_text(&state, "draft"))
    testing.expect_value(t, termhist_reset_revision(&state), u64(5))
}

// Verify initialization normalizes capacities and establishes empty state.
@(test)
termhist_test_initialization :: proc(t: ^testing.T) {
    state: Termhist_State
    testing.expect(t, termhist_init_with_allocator(
        &state, 0, -1, context.allocator))
    defer termhist_destroy(&state)

    testing.expect_value(t, state.borrowed_allocator, context.allocator)
    testing.expect_value(t, len(state.text), 1)
    testing.expect_value(t, len(state.history), 1)
    testing.expect_value(t, termhist_current_text(&state), "")
    testing.expect_value(t, termhist_cursor(&state), 0)
}

// Verify editing operations move and delete complete UTF-8 grapheme clusters.
@(test)
termhist_test_utf8_editing :: proc(t: ^testing.T) {
    state: Termhist_State
    testing.expect(t, termhist_init_with_allocator(
        &state, 1, 1, context.allocator))
    state_ptr := &state
    defer termhist_destroy(state_ptr)

    testing.expect(t, termhist_insert_text(state_ptr, "Aé🙂"))
    testing.expect_value(t, termhist_current_text(state_ptr), "Aé🙂")
    testing.expect_value(t, termhist_cursor(state_ptr), len("Aé🙂"))
    testing.expect(t, termhist_move_left(state_ptr))
    testing.expect_value(t, termhist_cursor(state_ptr), len("Aé"))
    testing.expect(t, termhist_backspace(state_ptr))
    testing.expect_value(t, termhist_current_text(state_ptr), "A🙂")
    testing.expect_value(t, termhist_cursor(state_ptr), 1)
    testing.expect(t, termhist_delete_forward(state_ptr))
    testing.expect_value(t, termhist_current_text(state_ptr), "A")
}

// Verify combined marks, flags, and joined emoji remain indivisible in the draft.
@(test)
termhist_test_grapheme_editing :: proc(t: ^testing.T) {
    state: Termhist_State
    testing.expect(t, termhist_init_with_allocator(
        &state, 1, 1, context.allocator))
    defer termhist_destroy(&state)
    text := "e\u0301🇺🇳👩‍💻"
    testing.expect(t, termhist_insert_text(&state, text))
    testing.expect(t, termhist_move_left(&state))
    testing.expect_value(t, termhist_cursor(&state), len("e\u0301🇺🇳"))
    testing.expect(t, termhist_delete_forward(&state))
    testing.expect_value(t, termhist_current_text(&state), "e\u0301🇺🇳")
    testing.expect(t, termhist_backspace(&state))
    testing.expect_value(t, termhist_current_text(&state), "e\u0301")
}

// Verify draft selection replaces whole graphemes and deletion consumes the range.
@(test)
termhist_test_selection_replacement_and_deletion :: proc(t: ^testing.T) {
    state: Termhist_State
    testing.expect(t, termhist_init_with_allocator(
        &state, 16, 1, context.allocator))
    defer termhist_destroy(&state)
    testing.expect(t, termhist_insert_text(&state, "Aé🙂Z"))
    testing.expect(t, termhist_set_cursor(&state, len("A")))
    testing.expect(t, termhist_set_cursor(&state, len("Aé🙂"), true))
    selected_start, selected_end := termhist_selection_range(&state)
    testing.expect_value(t, selected_start, len("A"))
    testing.expect_value(t, selected_end, len("Aé🙂"))
    testing.expect(t, termhist_insert_text(&state, "X"))
    testing.expect_value(t, termhist_current_text(&state), "AXZ")
    testing.expect(t, termhist_set_cursor(&state, len("A")))
    testing.expect(t, termhist_set_cursor(&state, len("AX"), true))
    testing.expect(t, termhist_backspace(&state))
    testing.expect_value(t, termhist_current_text(&state), "AZ")
}

// Verify word movement, line deletion, and preferred-column wrapped-row navigation.
@(test)
termhist_test_word_line_and_vertical_editing :: proc(t: ^testing.T) {
    state: Termhist_State
    testing.expect(t, termhist_init_with_allocator(
        &state, 16, 1, context.allocator))
    defer termhist_destroy(&state)
    testing.expect(t, termhist_insert_text(&state, "one two\n界x\nlong"))
    testing.expect(t, termhist_move_buffer_home(&state))
    testing.expect(t, termhist_move_word(&state, false))
    testing.expect_value(t, termhist_cursor(&state), len("one "))
    testing.expect(t, termhist_delete_word(&state, false))
    testing.expect_value(t, termhist_current_text(&state), "one \n界x\nlong")
    testing.expect(t, termhist_move_buffer_end(&state))
    testing.expect(t, termhist_move_vertical(&state, -1, 4))
    testing.expect_value(t, termhist_cursor(&state), len("one \n界x"))
    testing.expect(t, termhist_move_vertical(&state, -1, 4))
    testing.expect_value(t, termhist_cursor(&state), len("one "))
    testing.expect(t, termhist_delete_to_line_edge(&state, false))
    testing.expect_value(t, termhist_current_text(&state), "\n界x\nlong")
}

// Verify preedit stays transient and a matching commit replaces at its captured cursor.
@(test)
termhist_test_preedit_commit_and_stale_rejection :: proc(t: ^testing.T) {
    state: Termhist_State
    testing.expect(t, termhist_init_with_allocator(
        &state, 16, 1, context.allocator))
    defer termhist_destroy(&state)
    testing.expect(t, termhist_insert_text(&state, "ab"))
    testing.expect(t, termhist_move_left(&state))
    testing.expect(t, termhist_update_preedit(&state, "に", 0, 1))
    testing.expect_value(t, termhist_current_text(&state), "ab")
    testing.expect(t, termhist_commit_text(&state, "日本"))
    testing.expect_value(t, termhist_current_text(&state), "a日本b")
    testing.expect_value(t, termhist_cursor(&state), len("a日本"))
    testing.expect(t, termhist_update_preedit(&state, "仮", 0, 1))
    testing.expect(t, termhist_insert_text(&state, "x"))
    testing.expect(t, !termhist_commit_text(&state, "確定"))
    testing.expect_value(t, termhist_current_text(&state), "a日本xb")
}

// Verify terminal text normalizes line endings and rejects malformed UTF-8 atomically.
@(test)
termhist_test_insert_normalizes_newlines_and_rejects_invalid_text :: proc(
    t: ^testing.T) {
    state: Termhist_State
    testing.expect(t, termhist_init_with_allocator(
        &state, 1, 1, context.allocator))
    defer termhist_destroy(&state)
    testing.expect(t, termhist_insert_text(&state, "a\r\nb\rc"))
    testing.expect_value(t, termhist_current_text(&state), "a\nb\nc")
    testing.expect_value(t, termhist_content_revision(&state), u64(1))
    testing.expect(t, termhist_replace_input_range(&state, 2, 3, "B\r\n"))
    testing.expect_value(t, termhist_current_text(&state), "a\nB\n\nc")
    testing.expect_value(t, termhist_content_revision(&state), u64(2))
    revision := termhist_content_revision(&state)
    cursor := termhist_cursor(&state)
    testing.expect(t, !termhist_insert_text(&state, "\xff"))
    testing.expect_value(t, termhist_current_text(&state), "a\nB\n\nc")
    testing.expect_value(t, termhist_content_revision(&state), revision)
    testing.expect_value(t, termhist_cursor(&state), cursor)
}

// Verify completion ranges replace UTF-8 source safely and reject split glyphs.
@(test)
termhist_test_completion_range_replacement :: proc(t: ^testing.T) {
    state_storage: Termhist_State
    testing.expect(t, termhist_init_with_allocator(
        &state_storage, 8, 1, context.allocator))
    state := &state_storage
    defer termhist_destroy(state)

    testing.expect(t, termhist_insert_text(state, "x=\\alpha"))
    testing.expect(t, termhist_replace_input_range(
        state, len("x="), len("x=\\alpha"), "α"))
    testing.expect_value(t, termhist_current_text(state), "x=α")
    testing.expect_value(t, termhist_cursor(state), len("x=α"))

    testing.expect(t, !termhist_replace_input_range(state, 3, len("x=α"), "a"))
    testing.expect_value(t, termhist_current_text(state), "x=α")

    termhist_clear(state)
    source := "e\u0301x"
    testing.expect(t, termhist_insert_text(state, source))
    revision := termhist_content_revision(state)
    cursor := termhist_cursor(state)
    testing.expect(t, !termhist_replace_input_range(state, 1, len("e\u0301"), "X"))
    testing.expect_value(t, termhist_current_text(state), source)
    testing.expect_value(t, termhist_content_revision(state), revision)
    testing.expect_value(t, termhist_cursor(state), cursor)
}

// Verify history traversal restores the draft that preceded browsing.
@(test)
termhist_test_history_restores_draft :: proc(t: ^testing.T) {
    state_storage: Termhist_State
    testing.expect(t, termhist_init_with_allocator(
        &state_storage, 8, 1, context.allocator))
    state := &state_storage
    defer termhist_destroy(state)

    testing.expect(t, termhist_insert_text(state, "first"))
    testing.expect(t, termhist_accept_current(state))
    testing.expect(t, termhist_insert_text(state, "second"))
    testing.expect(t, termhist_accept_current(state))
    testing.expect(t, termhist_insert_text(state, "draft"))
    testing.expect(t, termhist_move_left(state))
    testing.expect(t, termhist_move_left(state, true))
    draft_cursor := state.cursor
    draft_anchor := state.anchor

    testing.expect(t, termhist_history_prev(state))
    testing.expect_value(t, termhist_current_text(state), "second")
    testing.expect(t, termhist_history_prev(state))
    testing.expect_value(t, termhist_current_text(state), "first")
    testing.expect(t, termhist_history_next(state))
    testing.expect_value(t, termhist_current_text(state), "second")
    testing.expect(t, termhist_history_next(state))
    testing.expect_value(t, termhist_current_text(state), "draft")
    testing.expect_value(t, state.cursor, draft_cursor)
    testing.expect_value(t, state.anchor, draft_anchor)
}

// Verify a completed multiline submission replaces its provisional history entry.
@(test)
termhist_test_history_replaces_provisional_entry :: proc(t: ^testing.T) {
    state_storage: Termhist_State
    testing.expect(t, termhist_init_with_allocator(
        &state_storage, 8, 1, context.allocator))
    state := &state_storage
    defer termhist_destroy(state)

    testing.expect(t, termhist_insert_text(state, "begin"))
    testing.expect(t, termhist_accept_current(state, 7))
    testing.expect(t, termhist_insert_text(state, "begin\nvalue\nend"))
    testing.expect(t, termhist_accept_current(state, 7, true))

    testing.expect_value(t, state.history_len, 1)
    testing.expect_value(t, state.history[0].tag, 7)
    testing.expect(t, termhist_history_prev(state))
    testing.expect_value(t, termhist_current_text(state), "begin\nvalue\nend")
}

// Verify Home/End jump the cursor to the line boundaries.
@(test)
termhist_test_move_home_end :: proc(t: ^testing.T) {
    state_storage: Termhist_State
    testing.expect(t, termhist_init_with_allocator(
        &state_storage, 8, 1, context.allocator))
    state := &state_storage
    defer termhist_destroy(state)

    testing.expect(t, termhist_insert_text(state, "abcdef"))
    testing.expect(t, termhist_move_home(state))
    testing.expect_value(t, termhist_cursor(state), 0)
    testing.expect(t, !termhist_move_home(state))

    testing.expect(t, termhist_move_end(state))
    testing.expect_value(t, termhist_cursor(state), len("abcdef"))
    testing.expect(t, !termhist_move_end(state))
}
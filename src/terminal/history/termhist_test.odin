#+test
package termhist

import "core:testing"

// Verify initialization normalizes capacities and establishes empty state.
@(test)
termhist_test_initialization :: proc(t: ^testing.T) {
    state: Termhist_State
    testing.expect(t, termhist_init_with_allocator(
        &state, 0, -1, context.allocator))
    defer termhist_destroy(&state)

    testing.expect_value(t, len(state.text), 1)
    testing.expect_value(t, len(state.history), 1)
    testing.expect_value(t, termhist_current_text(&state), "")
    testing.expect_value(t, termhist_cursor(&state), 0)
}

// Verify editing operations move and delete along UTF-8 codepoint boundaries.
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

    testing.expect(t, termhist_history_prev(state))
    testing.expect_value(t, termhist_current_text(state), "second")
    testing.expect(t, termhist_history_prev(state))
    testing.expect_value(t, termhist_current_text(state), "first")
    testing.expect(t, termhist_history_next(state))
    testing.expect_value(t, termhist_current_text(state), "second")
    testing.expect(t, termhist_history_next(state))
    testing.expect_value(t, termhist_current_text(state), "draft")
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
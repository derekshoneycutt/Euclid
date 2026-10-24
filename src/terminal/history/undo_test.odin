#+test
package termhist

import "core:mem"
import "core:testing"

// Each insertion/deletion has its own snapshot and redo retains the final endpoint.
@(test)
termhist_test_undo_operation_order :: proc(t: ^testing.T) {
    state: Termhist_State
    testing.expect(t, termhist_init_with_allocator(&state, 2, 1, context.allocator))
    defer termhist_destroy(&state)
    testing.expect(t, !termhist_undo(&state))
    for text in ([]string{"a", "β", "👩‍💻"}) {
        testing.expect(t, termhist_insert_text(&state, text))
    }
    testing.expect(t, termhist_backspace(&state))
    for text in ([]string{"aβ👩‍💻", "aβ", "a", ""}) {
        testing.expect(t, termhist_undo(&state))
        testing.expect_value(t, termhist_current_text(&state), text)
    }
    testing.expect(t, !termhist_undo(&state))
    for text in ([]string{"a", "aβ", "aβ👩‍💻", "aβ"}) {
        testing.expect(t, termhist_redo(&state))
        testing.expect_value(t, termhist_current_text(&state), text)
    }
    testing.expect(t, !termhist_redo(&state))
}

// Restoration includes selection/vertical affinity and never rewinds revisions.
@(test)
termhist_test_undo_editor_metadata :: proc(t: ^testing.T) {
    state: Termhist_State
    testing.expect(t, termhist_init_with_allocator(&state, 32, 4, context.allocator))
    defer termhist_destroy(&state)
    testing.expect(t, termhist_insert_text(&state, "e\u0301β\nlast"))
    testing.expect(t, termhist_set_cursor(&state, 3))
    testing.expect(t, termhist_set_cursor(&state, 5, true))
    state.preferred_column = 7
    testing.expect(t, termhist_commit_text(&state, "日本"))
    revision := state.content_revision
    testing.expect(t, termhist_undo(&state))
    testing.expect_value(t, termhist_current_text(&state), "e\u0301β\nlast")
    testing.expect_value(t, state.cursor, 5)
    testing.expect_value(t, state.anchor, 3)
    testing.expect_value(t, state.preferred_column, 7)
    testing.expect_value(t, state.content_revision, revision + 1)
    testing.expect(t, termhist_redo(&state))
    testing.expect_value(t, termhist_current_text(&state), "e\u0301日本\nlast")
    testing.expect_value(t, state.cursor, 9)
    testing.expect_value(t, state.anchor, 9)
}

// Movement ends redo; a later undo replaces that branch with the moved endpoint.
@(test)
termhist_test_undo_movement_and_branch :: proc(t: ^testing.T) {
    state: Termhist_State
    testing.expect(t, termhist_init_with_allocator(&state, 32, 4, context.allocator))
    defer termhist_destroy(&state)
    testing.expect(t, termhist_insert_text(&state, "abc"))
    testing.expect(t, termhist_insert_text(&state, "d"))
    testing.expect(t, termhist_undo(&state))
    testing.expect(t, termhist_move_left(&state))
    testing.expect(t, !termhist_redo(&state))
    testing.expect(t, termhist_undo(&state))
    testing.expect_value(t, termhist_current_text(&state), "")
    testing.expect(t, termhist_redo(&state))
    testing.expect_value(t, termhist_current_text(&state), "abc")
    testing.expect_value(t, state.cursor, 2)
    testing.expect(t, !termhist_redo(&state))
    testing.expect(t, termhist_insert_text(&state, "X"))
    testing.expect(t, termhist_undo(&state))
    testing.expect_value(t, termhist_current_text(&state), "abc")
    testing.expect(t, termhist_redo(&state))
    testing.expect_value(t, termhist_current_text(&state), "abXc")
}

// No-op/invalid edits and preedit leave the timeline intact; commit is one operation.
@(test)
termhist_test_undo_noops_and_composition :: proc(t: ^testing.T) {
    state: Termhist_State
    testing.expect(t, termhist_init_with_allocator(&state, 32, 4, context.allocator))
    defer termhist_destroy(&state)
    testing.expect(t, termhist_insert_text(&state, "β"))
    testing.expect(t, termhist_undo(&state))
    testing.expect(t, !termhist_backspace(&state))
    testing.expect(t, !termhist_move_left(&state))
    testing.expect(t, termhist_insert_text(&state, ""))
    testing.expect(t, !termhist_replace_input_range(&state, 1, 1, "x"))
    testing.expect(t, termhist_update_preedit(&state, "仮", 0, 1))
    testing.expect(t, !termhist_redo(&state))
    termhist_clear_preedit(&state)
    testing.expect(t, termhist_redo(&state))
    testing.expect(t, termhist_update_preedit(&state, "仮", 0, 1))
    testing.expect(t, termhist_commit_text(&state, "日本\r\nx"))
    testing.expect(t, termhist_undo(&state))
    testing.expect_value(t, termhist_current_text(&state), "β")
    testing.expect(t, termhist_redo(&state))
    testing.expect_value(t, termhist_current_text(&state), "β日本\nx")
}

// Resets and history recall discard edit history without discarding retained capacity.
@(test)
termhist_test_undo_reset_reuse :: proc(t: ^testing.T) {
    state: Termhist_State
    testing.expect(t, termhist_init_with_allocator(&state, 32, 4, context.allocator))
    defer termhist_destroy(&state)
    testing.expect(t, termhist_insert_text(&state, "saved"))
    testing.expect(t, termhist_accept_current(&state))
    testing.expect(t, !termhist_undo(&state))
    snapshots := raw_data(state.undo.snapshots)
    bytes := raw_data(state.undo.bytes)
    for _ in 0..<10 {
        testing.expect(t, termhist_insert_text(&state, "draft"))
        testing.expect(t, termhist_undo(&state))
        testing.expect(t, termhist_redo(&state))
        termhist_clear(&state)
    }
    testing.expect_value(t, raw_data(state.undo.snapshots), snapshots)
    testing.expect_value(t, raw_data(state.undo.bytes), bytes)
    testing.expect(t, termhist_insert_text(&state, "draft"))
    testing.expect(t, termhist_history_prev(&state))
    testing.expect(t, !termhist_undo(&state))
    testing.expect(t, termhist_history_next(&state))
    testing.expect_value(t, termhist_current_text(&state), "draft")
    testing.expect(t, !termhist_undo(&state))
}

// Each failed initialization releases all partially admitted snapshot backing.
@(test)
termhist_test_undo_initialization_failures :: proc(t: ^testing.T) {
    storage: [128]u64
    bytes := transmute([]u8)storage[:]
    alignment := align_of(Termhist_Entry)
    history_start := (2 + alignment - 1) / alignment * alignment
    history_end := history_start + size_of(Termhist_Entry)
    capacities := [?]int{
        0, 1, 2, history_end, history_end + size_of(Termhist_Snapshot),
    }
    for capacity in capacities {
        arena: mem.Arena
        mem.arena_init(&arena, bytes[:capacity])
        state: Termhist_State
        testing.expect(t, !termhist_init_with_allocator(
            &state, 1, 1, mem.arena_allocator(&arena)))
        testing.expect_value(t, state.borrowed_allocator, mem.Allocator{})
        testing.expect_value(t, len(state.text), 0)
        testing.expect_value(t, len(state.undo.snapshots), 0)
        testing.expect_value(t, len(state.undo.bytes), 0)
    }
}

// Live-text, descriptor, and byte failures do not publish edits or truncate branches.
@(test)
termhist_test_undo_edit_allocation_failures :: proc(t: ^testing.T) {
    for stage in 0..<3 {
        state: Termhist_State
        testing.expect(t, termhist_init_with_allocator(
            &state, 1, 1, context.allocator))
        testing.expect(t, termhist_insert_text(&state, "ab"))
        if stage >= 1 {
            testing.expect(t, termhist_ensure_u8_capacity(
                &state, &state.text, 6, state.text_len))
        }
        if stage >= 2 {
            testing.expect(t, termhist_reserve_undo(&state, 2, 1))
        }
        before := state
        storage: [1]u8
        arena: mem.Arena
        mem.arena_init(&arena, storage[:])
        state.borrowed_allocator = mem.arena_allocator(&arena)
        testing.expect(t, !termhist_insert_text(&state, "long"))
        state.borrowed_allocator = context.allocator
        testing.expect_value(t, termhist_current_text(&state), "ab")
        testing.expect_value(t, state.cursor, before.cursor)
        testing.expect_value(t, state.content_revision, before.content_revision)
        testing.expect_value(t, state.undo.count, before.undo.count)
        testing.expect_value(t, state.undo.position, before.undo.position)
        testing.expect(t, state.allocation_failed)
        termhist_destroy(&state)
    }
}

// A rejected first-undo endpoint leaves the current edit and timeline retryable.
@(test)
termhist_test_undo_endpoint_allocation_failure :: proc(t: ^testing.T) {
    state: Termhist_State
    testing.expect(t, termhist_init_with_allocator(&state, 1, 1, context.allocator))
    defer termhist_destroy(&state)
    testing.expect(t, termhist_insert_text(&state, "long"))
    storage: [1]u8
    arena: mem.Arena
    mem.arena_init(&arena, storage[:])
    state.borrowed_allocator = mem.arena_allocator(&arena)
    testing.expect(t, !termhist_undo(&state))
    state.borrowed_allocator = context.allocator
    testing.expect_value(t, termhist_current_text(&state), "long")
    testing.expect_value(t, state.undo.position, 1)
    testing.expect(t, !state.undo.sequence)
    testing.expect(t, termhist_undo(&state))
    testing.expect_value(t, termhist_current_text(&state), "")
    testing.expect(t, termhist_redo(&state))
    testing.expect_value(t, termhist_current_text(&state), "long")
}

// Reused storage needs no allocator, and a failed branch edit preserves redo.
@(test)
termhist_test_undo_reuse_and_rejected_branch :: proc(t: ^testing.T) {
    state: Termhist_State
    testing.expect(t, termhist_init_with_allocator(&state, 32, 4, context.allocator))
    defer termhist_destroy(&state)
    storage: [1]u8
    arena: mem.Arena
    mem.arena_init(&arena, storage[:])
    state.borrowed_allocator = mem.arena_allocator(&arena)
    for _ in 0..<10 {
        testing.expect(t, termhist_insert_text(&state, "abc"))
        testing.expect(t, termhist_insert_text(&state, "d"))
        testing.expect(t, termhist_undo(&state))
        too_large: [64]u8
        for &byte in too_large {
            byte = 'x'
        }
        testing.expect(t, !termhist_insert_text(&state, string(too_large[:])))
        testing.expect(t, state.undo.sequence)
        testing.expect_value(t, termhist_current_text(&state), "abc")
        testing.expect(t, termhist_redo(&state))
        testing.expect_value(t, termhist_current_text(&state), "abcd")
        termhist_clear(&state)
    }
    state.borrowed_allocator = context.allocator
}

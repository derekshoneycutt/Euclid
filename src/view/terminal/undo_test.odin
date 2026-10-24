#+test
package terminalview

import viewterminalmodel "model"
import termhist "../../terminal/history"
import "../../core/protocol"
import "../input"
import "core:mem"
import "core:log"
import "core:testing"

// Deliver a portable shortcut through ordinary focus/evaluation/composition routing.
terminal_test_undo_key :: proc(
    term: ^viewterminalmodel.Terminal_State, key: input.Input_Key,
    modifiers: input.Input_Modifiers) -> Terminal_Keyboard_Update {
    return terminal_update_keyboard(term, {
        events = []input.Input_Event{{kind = .Press, key = key, modifiers = modifiers}},
    })
}

// Count expected allocation diagnostics without forwarding them as test failures.
terminal_test_undo_log :: proc(
    data: rawptr, level: log.Level, text: string, _: log.Options,
    _ := #caller_location) {
    if level == .Error && text == "terminal_edit_rejected reason=allocation_failed" {
        (cast(^int)data)^ += 1
    }
}

// Julia and desktop aliases restore the same timeline and invalidate old completion.
@(test)
terminal_test_undo_bindings :: proc(t: ^testing.T) {
    term: viewterminalmodel.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term, context.allocator)
    term.banner_ready = true
    keys := [?]input.Input_Key{.Z, .Slash, .Minus}
    modifiers := [?]input.Input_Modifiers{
        {.Control}, {.Control}, {.Control, .Shift},
    }
    for key, index in keys {
        termhist.termhist_clear(term.history)
        testing.expect(t, terminal_insert_clipboard_text(&term, "pasted\nβ"))
        request := terminal_request_completion(&term)
        testing.expect(t, terminal_test_undo_key(
            &term, key, modifiers[index]).cursor_moved)
        testing.expect_value(t, termhist.termhist_current_text(term.history), "")
        testing.expect_value(t, term.pending_completion_request_id, 0)
        testing.expect(t, !terminal_set_completion_preview(&term, {
            request_id = request.request_id, found = true, insertion = "stale",
        }))
        redo_modifiers := input.Input_Modifiers{.Control, .Shift} if index == 0 else
            input.Input_Modifiers{.Super, .Shift}
        redo_key := input.Input_Key.Z if index == 0 else input.Input_Key.Minus
        testing.expect(t, terminal_test_undo_key(
            &term, redo_key, redo_modifiers).cursor_moved)
        testing.expect_value(t,
            termhist.termhist_current_text(term.history), "pasted\nβ")
    }
}

// Ordered text, undo, redo and repeat events remain individual editor transactions.
@(test)
terminal_test_undo_order_and_repeat :: proc(t: ^testing.T) {
    term: viewterminalmodel.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term, context.allocator)
    term.banner_ready = true
    events := [?]input.Input_Event{
        {kind = .Text, codepoint = 'a'},
        {kind = .Text, codepoint = 'b'},
        {kind = .Press, key = .Z, modifiers = {.Control}},
        {kind = .Repeat, key = .Z, modifiers = {.Control}},
        {kind = .Press, key = .Z, modifiers = {.Control, .Shift}},
        {kind = .Text, codepoint = 'x'},
    }
    _ = terminal_update_keyboard(&term, {events = events[:]})
    testing.expect_value(t, termhist.termhist_current_text(term.history), "ax")
    testing.expect(t,
        !terminal_test_undo_key(&term, .Z, {.Control, .Shift}).cursor_moved)
    testing.expect(t, terminal_test_undo_key(&term, .Z, {.Control}).cursor_moved)
    testing.expect_value(t, termhist.termhist_current_text(term.history), "a")
}

// Composition is transient; one native commit is undone in one step.
@(test)
terminal_test_undo_ime_and_input_gates :: proc(t: ^testing.T) {
    term: viewterminalmodel.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term, context.allocator)
    testing.expect(t, termhist.termhist_insert_text(term.history, "base"))
    testing.expect(t, !terminal_test_undo_key(&term, .Z, {.Control}).cursor_moved)
    term.banner_ready = true
    testing.expect(t, termhist.termhist_update_preedit(term.history, "仮", 0, 1))
    testing.expect(t, !terminal_test_undo_key(&term, .Z, {.Control}).cursor_moved)
    testing.expect_value(t, termhist.termhist_current_text(term.history), "base")
    commit := input.Input_Event{kind = .Text_Commit, text_length = 6}
    copy(commit.text[:], "日本")
    _ = terminal_update_keyboard_event(&term, commit, "")
    testing.expect(t, terminal_test_undo_key(&term, .Z, {.Control}).cursor_moved)
    testing.expect_value(t, termhist.termhist_current_text(term.history), "base")
    term.awaiting_eval = true
    testing.expect(t, !terminal_test_undo_key(&term, .Z, {.Control}).cursor_moved)
    term.awaiting_eval = false
    _ = terminal_update_keyboard(&term, {
        events = []input.Input_Event{{kind = .Press, key = .Z, modifiers = {.Control}}},
    }, false)
    testing.expect_value(t, termhist.termhist_current_text(term.history), "base")
}

// AltGr/Option and unrelated modifier combinations never claim undo/redo.
@(test)
terminal_test_undo_exact_modifiers :: proc(t: ^testing.T) {
    term: viewterminalmodel.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term, context.allocator)
    testing.expect(t, termhist.termhist_insert_text(term.history, "draft"))
    modifier_sets := [?]input.Input_Modifiers{
        {}, {.Alt}, {.Control, .Alt}, {.Super}, {.Control, .Super},
    }
    for modifiers in modifier_sets {
        _, handled := terminal_update_undo_key(
            &term, {kind = .Press, key = .Z, modifiers = modifiers})
        testing.expect(t, !handled)
    }
    _, handled := terminal_update_undo_key(
        &term, {kind = .Release, key = .Z, modifiers = {.Control}})
    testing.expect(t, !handled)
    testing.expect_value(t, termhist.termhist_current_text(term.history), "draft")
}

// Existing completion acceptance creates one edit; receiving a preview does not.
@(test)
terminal_test_undo_existing_completion :: proc(t: ^testing.T) {
    term: viewterminalmodel.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term, context.allocator)
    term.banner_ready = true
    testing.expect(t, termhist.termhist_insert_text(term.history, "pri"))
    request := terminal_request_completion(&term)
    testing.expect(t, terminal_set_completion_preview(&term, {
        request_id = request.request_id, found = true,
        replacement_end = 3, insertion = "println",
    }))
    testing.expect_value(t, term.history.undo.position, 1)
    testing.expect(t, terminal_accept_completion_preview(&term))
    testing.expect(t, terminal_test_undo_key(&term, .Z, {.Control}).cursor_moved)
    testing.expect_value(t,
        termhist.termhist_current_text(term.history), "pri")
    testing.expect(t,
        terminal_test_undo_key(&term, .Z, {.Control, .Shift}).cursor_moved)
    testing.expect_value(t,
        termhist.termhist_current_text(term.history), "println")
}

// Successful keyboard/pointer selection ends redo; background preview does not.
@(test)
terminal_test_undo_action_boundaries :: proc(t: ^testing.T) {
    term: viewterminalmodel.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term, context.allocator)
    term.banner_ready = true
    testing.expect(t, termhist.termhist_insert_text(term.history, "abc"))
    testing.expect(t, termhist.termhist_insert_text(term.history, "d"))
    _ = terminal_test_undo_key(&term, .Z, {.Control})
    request := terminal_request_completion(&term, false)
    testing.expect(t, terminal_set_completion_preview(&term, {
        request_id = request.request_id, found = true,
        replacement_end = 3, insertion = "other",
    }))
    testing.expect(t, term.history.undo.sequence)
    _ = terminal_test_undo_key(&term, .Left, {})
    testing.expect(t,
        !terminal_test_undo_key(&term, .Z, {.Control, .Shift}).cursor_moved)
    testing.expect(t, termhist.termhist_undo(term.history))
    testing.expect(t, termhist.termhist_redo(term.history))
    testing.expect(t, termhist.termhist_set_cursor(term.history, 1, true))
    testing.expect(t, !termhist.termhist_redo(term.history))
}

// Incomplete evaluation retains prior edits and adds newline/indent in one step.
@(test)
terminal_test_undo_continuation_lifecycle :: proc(t: ^testing.T) {
    term: viewterminalmodel.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term, context.allocator)
    term.banner_ready = true
    testing.expect(t, termhist.termhist_insert_text(term.history, "begin\n    "))
    testing.expect(t, termhist.termhist_insert_text(term.history, "value"))
    testing.expect(t, termhist.termhist_set_cursor(term.history, 6))
    source := terminal_submit(&term)
    testing.expect(t, terminal_begin_eval(&term, source))
    terminal_continue_eval(&term)
    testing.expect_value(t,
        termhist.termhist_current_text(term.history), "begin\n    value\n    ")
    testing.expect(t, termhist.termhist_undo(term.history))
    testing.expect_value(t,
        termhist.termhist_current_text(term.history), "begin\n    value")
    testing.expect_value(t, term.history.cursor, 6)
    testing.expect(t, termhist.termhist_undo(term.history))
    testing.expect_value(t, termhist.termhist_current_text(term.history), "begin\n    ")
    testing.expect(t, termhist.termhist_redo(term.history))
    testing.expect(t, termhist.termhist_redo(term.history))
    source = terminal_submit(&term)
    testing.expect(t, terminal_begin_eval(&term, source))
    terminal_continue_eval(&term)
    testing.expect(t, termhist.termhist_undo(term.history))
    testing.expect_value(t,
        termhist.termhist_current_text(term.history), "begin\n    value\n    ")
    terminal_complete_eval(&term)
    testing.expect(t, !termhist.termhist_undo(term.history))
    testing.expect(t, !term.pending_draft_valid)
}

// Cancellation clears edit history; prompt mode changes are not restored by undo.
@(test)
terminal_test_undo_cancel_and_mode :: proc(t: ^testing.T) {
    term: viewterminalmodel.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term, context.allocator)
    term.banner_ready = true
    testing.expect(t, terminal_enter_help_mode_on_question_mark(&term, '?'))
    testing.expect(t, termhist.termhist_insert_text(term.history, "println"))
    _ = terminal_test_undo_key(&term, .Z, {.Control})
    testing.expect_value(t, term.input_mode, protocol.Evaluation_Mode.Help)
    _ = terminal_test_undo_key(&term, .C, {.Control})
    testing.expect_value(t, term.input_mode, protocol.Evaluation_Mode.Normal)
    testing.expect(t, !termhist.termhist_redo(term.history))
    testing.expect(t, !termhist.termhist_undo(term.history))
}

// Failed endpoint admission rejects undo and surfaces one error without losing text.
@(test)
terminal_test_undo_failure_is_reported :: proc(t: ^testing.T) {
    errors := 0
    previous_logger := context.logger
    context.logger = {procedure = terminal_test_undo_log, data = &errors}
    defer context.logger = previous_logger
    term: viewterminalmodel.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term, context.allocator)
    termhist.termhist_destroy(term.history)
    testing.expect(t, termhist.termhist_init_with_allocator(
        term.history, 8, 1, context.allocator))
    testing.expect(t, termhist.termhist_insert_text(term.history, "draft"))
    term.banner_ready = true
    storage: [1]u8
    arena: mem.Arena
    mem.arena_init(&arena, storage[:])
    term.history.borrowed_allocator = mem.arena_allocator(&arena)
    update := terminal_test_undo_key(&term, .Z, {.Control})
    testing.expect(t, !terminal_insert_clipboard_text(&term, "X"))
    term.history.borrowed_allocator = context.allocator
    testing.expect(t, !update.cursor_moved)
    testing.expect_value(t, termhist.termhist_current_text(term.history), "draft")
    testing.expect(t, !term.history.allocation_failed)
    testing.expect_value(t, terminal_line_text(&term, 0),
        "Terminal edit rejected: unable to allocate edit history storage.")
    testing.expect(t, terminal_test_undo_key(&term, .Z, {.Control}).cursor_moved)
    testing.expect_value(t, errors, 2)
}

// Continuation allocation failure recovers the submitted draft, never a stuck request.
@(test)
terminal_test_undo_continuation_failure_recovers :: proc(t: ^testing.T) {
    errors := 0
    previous_logger := context.logger
    context.logger = {procedure = terminal_test_undo_log, data = &errors}
    defer context.logger = previous_logger
    term: viewterminalmodel.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term, context.allocator)
    termhist.termhist_destroy(term.history)
    testing.expect(t, termhist.termhist_init_with_allocator(
        term.history, 32, 1, context.allocator))
    testing.expect(t, termhist.termhist_insert_text(term.history, "begin"))
    testing.expect(t, terminal_begin_eval(&term, terminal_submit(&term)))
    storage: [1]u8
    arena: mem.Arena
    mem.arena_init(&arena, storage[:])
    term.history.borrowed_allocator = mem.arena_allocator(&arena)
    terminal_continue_eval(&term)
    term.history.borrowed_allocator = context.allocator
    testing.expect_value(t, termhist.termhist_current_text(term.history), "begin")
    testing.expect(t, !term.awaiting_eval && term.collecting_continuation)
    testing.expect(t, termhist.termhist_undo(term.history))
    testing.expect_value(t, termhist.termhist_current_text(term.history), "")
    testing.expect_value(t, errors, 1)
}

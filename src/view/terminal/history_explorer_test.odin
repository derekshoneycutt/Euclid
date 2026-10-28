#+test
package terminalview

import viewterminalmodel "model"
import termhist "../../terminal/history"
import termhiststore "../../terminal/history/store"
import historyruntime "../../terminal/history/runtime"
import protocol "../../core/protocol"
import "core:testing"

// Opening and cancelling must leave the ordinary draft and edit timeline untouched.
@(test)
terminal_history_explorer_cancel_preserves_draft :: proc(t: ^testing.T) {
    term: viewterminalmodel.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term, context.allocator)
    term.banner_ready = true
    term.history_explorer_open_allowed = true
    term.input_mode = .Pkg
    testing.expect(t, termhist.termhist_insert_text(term.history, "draft"))
    term.history_navigation_epoch = 4
    term.history_navigation_pending_id = 22
    term.history_navigation_intent_count = 1
    term.history_navigation_active = true
    _ = termhist.termhist_set_cursor(term.history, 2)
    _ = termhist.termhist_set_cursor(term.history, 1, true)
    cursor := term.history.cursor
    anchor := term.history.anchor
    undo_count := term.history.undo.count
    undo_position := term.history.undo.position

    terminal_history_explorer_test_open(&term)
    testing.expect(t, term.history_explorer.active)
    testing.expect_value(t, term.history_navigation_epoch, u64(5))
    testing.expect_value(t, term.history_navigation_pending_id, u64(0))
    testing.expect(t, term.history_navigation_active)
    testing.expect_value(t,
        termhist.termhist_current_text(&term.history_explorer.query_editor), "")
    terminal_history_explorer_test_type(&term, 'q')
    terminal_history_explorer_test_cancel(&term)

    testing.expect(t, !term.history_explorer.active)
    testing.expect_value(t, termhist.termhist_current_text(term.history), "draft")
    testing.expect_value(t, term.history.cursor, cursor)
    testing.expect_value(t, term.history.anchor, anchor)
    testing.expect_value(t, term.input_mode, protocol.Evaluation_Mode.Pkg)
    testing.expect_value(t, term.history.undo.count, undo_count)
    testing.expect_value(t, term.history.undo.position, undo_position)
    testing.expect(t, !term.awaiting_eval)
}

// Exercise the public open shortcut through the ordinary Terminal key path.
terminal_history_explorer_test_open :: proc(term: ^viewterminalmodel.Terminal_State) {
    _ = terminal_update_keyboard_event(term, {
        kind = .Press,
        key = .R,
        modifiers = {.Control},
    }, "")
}

// Insert one committed test scalar through the ordinary Terminal key path.
terminal_history_explorer_test_type :: proc(
    term: ^viewterminalmodel.Terminal_State, codepoint: rune) {
    _ = terminal_update_keyboard_event(term, {
        kind = .Text,
        codepoint = codepoint,
    }, "")
}

// Cancel through the ordinary Terminal key path without touching the draft.
terminal_history_explorer_test_cancel :: proc(
    term: ^viewterminalmodel.Terminal_State) {
    _ = terminal_update_keyboard_event(term, {
        kind = .Press,
        key = .Escape,
    }, "")
}

// Search pages keep chronological order and reject completions from a retired query.
@(test)
terminal_history_explorer_page_order_and_stale_query :: proc(t: ^testing.T) {
    term: viewterminalmodel.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term, context.allocator)
    term.banner_ready = true
    term.history_explorer_open_allowed = true
    testing.expect(t, history_explorer_open(&term))
    explorer := &term.history_explorer
    identity: historyruntime.History_Explorer_Identity = {
        terminal_generation = 1,
        opening_generation = explorer^.opening_generation,
        query_generation = explorer^.query_generation,
        visibility_epoch = 1,
        runtime_epoch = 3,
    }
    explorer^.identity = identity
    terminal_history_explorer_test_page_order(t, explorer, identity)
    terminal_history_explorer_test_reject_stale_search(t, explorer, identity)
}

// Publish one out-of-order page and verify chronological order and selection.
terminal_history_explorer_test_page_order :: proc(
    t: ^testing.T, explorer: ^viewterminalmodel.History_Explorer_State,
    identity: historyruntime.History_Explorer_Identity) {
    explorer^.search_request_id = 1
    older: termhiststore.History_Record = {
        scope = .Session,
        source_id = 1,
        source_revision = 1,
        submitted_at_unix_ms = 10,
    }
    newer := older
    newer.source_id = 2
    newer.submitted_at_unix_ms = 20
    explorer^.rows[0].record = newer
    explorer^.rows[1].record = older
    history_explorer_publish_search(explorer, {
        ready = true,
        request = {
            identity = identity,
            request_id = 1,
        },
        result = {
            outcome = .Scanned,
            row_count = 2,
            cursor = {
                submitted_at_unix_ms = 5,
                scope = .Session,
                source_id = 3,
            },
            cursor_valid = true,
        },
    })
    testing.expect_value(t, explorer^.rows[0].record.source_id, u64(1))
    testing.expect_value(t, explorer^.rows[1].record.source_id, u64(2))
    testing.expect_value(t, explorer^.selected_index, 1)
    testing.expect(t, explorer^.older_available && !explorer^.newer_available)
}

// Ignore results retired by a new page request or query identity.
terminal_history_explorer_test_reject_stale_search :: proc(
    t: ^testing.T, explorer: ^viewterminalmodel.History_Explorer_State,
    identity: historyruntime.History_Explorer_Identity) {
    explorer^.search_request_id = 2
    explorer^.search_pending = true
    history_explorer_request_edge(explorer, .Older)
    history_explorer_publish_search(explorer, {
        ready = true,
        request = {
            identity = identity,
            request_id = 2,
        },
        result = {
            outcome = .Scanned,
            row_count = 1,
        },
    })
    testing.expect_value(t, explorer^.row_count, 0)
    testing.expect(t, explorer^.status == .Searching)

    retired_identity := identity
    retired_identity.query_generation += 1
    explorer^.row_count = 2
    explorer^.identity = retired_identity
    explorer^.search_request_id = 3
    history_explorer_publish_search(explorer, {
        ready = true,
        request = {
            identity = identity,
            request_id = 3,
        },
        result = {
            outcome = .Scanned,
            row_count = 1,
        },
    })
    testing.expect_value(t, explorer^.row_count, 2)
    testing.expect_value(t, explorer^.identity.query_generation, u64(2))
}

// Opening guards reject every conflicting Terminal or child-input owner.
@(test)
terminal_history_explorer_open_guards :: proc(t: ^testing.T) {
    term: viewterminalmodel.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term, context.allocator)
    term.banner_ready = true
    term.history_explorer_open_allowed = true

    term.history_explorer_open_allowed = false
    testing.expect(t, !history_explorer_open(&term))
    term.history_explorer_open_allowed = true
    term.awaiting_eval = true
    testing.expect(t, !history_explorer_open(&term))
    term.awaiting_eval = false
    term.collecting_continuation = true
    testing.expect(t, !history_explorer_open(&term))
    term.collecting_continuation = false
    term.interactive_input_request_id = 1
    testing.expect(t, !history_explorer_open(&term))
    term.interactive_input_request_id = 0
    term.history.preedit_active = true
    testing.expect(t, !history_explorer_open(&term))
    term.history.preedit_active = false
    term.banner_ready = false
    testing.expect(t, !history_explorer_open(&term))
}

// Query paste is one line, and grapheme backspace removes a complete cluster.
@(test)
terminal_history_explorer_query_editing_is_bounded_and_grapheme_safe :: proc(
    t: ^testing.T) {
    term: viewterminalmodel.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term, context.allocator)
    term.banner_ready = true
    term.history_explorer_open_allowed = true
    testing.expect(t, history_explorer_open(&term))

    _ = history_explorer_update_event(&term, {
        kind = .Press,
        key = .V,
        modifiers = {.Control, .Shift},
    }, "first\r\nsecond\nthird")
    testing.expect_value(
        t, termhist.termhist_current_text(&term.history_explorer.query_editor),
        "first second third")
    _ = history_explorer_update_event(&term, {
        kind = .Text,
        codepoint = 'e',
    }, "")
    _ = history_explorer_update_event(&term, {
        kind = .Text,
        codepoint = '\u0301',
    }, "")
    _ = history_explorer_update_event(&term, {
        kind = .Text,
        codepoint = 'x',
    }, "")
    _ = history_explorer_update_event(&term, {
        kind = .Press,
        key = .Backspace,
    }, "")
    _ = history_explorer_update_event(&term, {
        kind = .Press,
        key = .Backspace,
    }, "")
    testing.expect_value(
        t, termhist.termhist_current_text(&term.history_explorer.query_editor),
        "first second third")
    testing.expect_value(t, term.history_explorer.query_generation, u64(7))
    history_explorer_close(&term)
}

// A stale preview cannot publish or be recalled; a current preview recalls exact source only.
@(test)
terminal_history_explorer_preview_identity_and_recall :: proc(t: ^testing.T) {
    term: viewterminalmodel.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term, context.allocator)
    term.banner_ready = true
    term.history_explorer_open_allowed = true
    term.input_mode = .Normal
    testing.expect(t, termhist.termhist_insert_text(term.history, "original prompt"))
    testing.expect(t, history_explorer_open(&term))

    explorer := &term.history_explorer
    identity: historyruntime.History_Explorer_Identity = {
        terminal_generation = 1,
        opening_generation = explorer^.opening_generation,
        query_generation = explorer^.query_generation,
        visibility_epoch = 1,
        runtime_epoch = 1,
    }
    explorer^.identity = identity
    explorer^.preview_request_id = 1
    record: termhiststore.History_Record = {
        scope = .Persistent,
        source_id = 7,
        persistent_entry_id = 7,
        source_revision = 3,
        mode = .Help,
        submitted_at_unix_ms = 10,
    }
    explorer^.rows[0] = {
        record = record,
    }
    explorer^.row_count = 1
    explorer^.selected_index = 0
    explorer^.preview_status = .Loading
    history_explorer_publish_preview(explorer, {
        ready = true,
        request = {
            identity = identity,
            request_id = 1,
            scope = .Persistent,
            source_id = 8,
            source_revision = 3,
        },
        result = {
            outcome = .Found,
            record = record,
            source_length = 6,
        },
    })
    testing.expect(t, explorer^.preview_status == .Failed)
    testing.expect(t, !explorer^.accept_requested)
    testing.expect_value(t, termhist.termhist_current_text(term.history), "original prompt")

    explorer^.preview_status = .Loading
    copy(explorer^.preview_source[:], "exact\nsource")
    explorer^.preview_request_id = 2
    history_explorer_publish_preview(explorer, {
        ready = true,
        request = {
            identity = identity,
            request_id = 2,
            scope = .Persistent,
            source_id = 7,
            source_revision = 3,
        },
        result = {
            outcome = .Found,
            record = record,
            source_length = len("exact\nsource"),
        },
    })
    testing.expect(t, explorer^.preview_status == .Ready)
    explorer^.accept_requested = true
    testing.expect(t, history_explorer_accept(&term, identity))
    testing.expect_value(t, termhist.termhist_current_text(term.history), "exact\nsource")
    testing.expect_value(t, term.history.cursor, len("exact\nsource"))
    testing.expect_value(t, term.input_mode, protocol.Evaluation_Mode.Help)
    testing.expect(t, !term.awaiting_eval && !term.history_explorer.active)
}

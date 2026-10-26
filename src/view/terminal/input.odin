package terminalview

import viewterminalmodel "model"

import geometry "../../core/geometry"
import "../../core/protocol"
import coretext "../../core/text"
import termemulator "../../terminal/emulator"
import termgrid "../../terminal/grid"
import termhist "../../terminal/history"
import termshellintegration "../../terminal/shell_integration"
import "../font"
import "../input"

import "core:unicode/utf8"
import "core:log"

// Arm or expire the synchronized-output safety deadline on the display clock.
terminal_update_synchronized_output :: proc(
    term: ^viewterminalmodel.Terminal_State, now: f64) {
    synchronized := term.synchronized_output
    if !synchronized.active {
        return
    }
    if !synchronized.deadline_armed {
        synchronized.deadline_armed = true
        synchronized.deadline = now +
            TERMINAL_SYNCHRONIZED_OUTPUT_DEADLINE_SECONDS
        return
    }
    if now >= synchronized.deadline {
        termemulator.interpreter_publish_synchronized_output(
            &term.output_interpreter, true)
    }
}

//   Consume keyboard input from the active frame and apply it to the live input line.
//
// Parameters:
//   - term: The terminal state field owned by the caller.
//   - frame: This frame's polled keyboard state.
//
// Returns:
//   - Submission, completion, and cursor-movement details for this frame.
//
// Side effects:
//   - Mutates the live input line, cursor, and committed scrollback via termhist.
terminal_update_keyboard :: proc(
    term: ^viewterminalmodel.Terminal_State, frame: input.Input_Frame,
    focused: bool = true) -> Terminal_Keyboard_Update {
    if !focused {
        termhist.termhist_clear_preedit(term.history)
        return {}
    }
    if term.awaiting_eval || !term.banner_ready {
        termhist.termhist_clear_preedit(term.history)
        return {}
    }

    update: Terminal_Keyboard_Update
    for event in frame.events {
        event_frame: input.Input_Frame = {
            events = []input.Input_Event{event},
        }
        clipboard_text := ""
        if terminal_clipboard_paste_requested(event_frame) {
            clipboard_text = input.input_get_clipboard_text()
        }
        event_update := terminal_update_keyboard_event(term, event, clipboard_text)
        update.cursor_moved = update.cursor_moved || event_update.cursor_moved
        if event_update.completion.requested {
            update.completion = event_update.completion
        }
        if event_update.submission.submitted {
            update.submission = event_update.submission
            break
        }
    }
    return update
}

// Apply one key, committed-text, or paste fact without reordering its draft mutation.
terminal_update_keyboard_event :: proc(
    term: ^viewterminalmodel.Terminal_State, event: input.Input_Event,
    clipboard_text: string) -> Terminal_Keyboard_Update {
    defer terminal_report_edit_failure(term)
    if !terminal_history_navigation_event(event) {
        terminal_history_navigation_invalidate(term)
    }
    composing := term.history != nil && term.history.preedit_active
    if input.input_event_composition_owns_key(event, &composing) {
        return {}
    }
    if update, handled := terminal_update_undo_key(term, event); handled {
        return update
    }
    if event.kind == .Text {
        return {
            cursor_moved = terminal_update_char_input_event(term, event),
        }
    }
    if event.text_target.kind != .None &&
        event.text_target.kind != .Terminal {
        return {}
    }
    if event.kind == .Text_Preedit || event.kind == .Text_Cancel ||
        event.kind == .Text_Commit {
        return terminal_update_composition_event(term, event)
    }
    event_frame: input.Input_Frame = {
        events = []input.Input_Event{event},
    }
    if terminal_clipboard_paste_requested(event_frame) {
        return {
            cursor_moved = terminal_insert_clipboard_text(term, clipboard_text),
        }
    }
    return terminal_update_navigation_keys(term, event_frame)
}

// Apply native text lifecycle facts without routing them as application commands.
terminal_update_composition_event :: proc(
    term: ^viewterminalmodel.Terminal_State,
    event: input.Input_Event) -> Terminal_Keyboard_Update {
    if (event.kind == .Text_Commit || event.kind == .Text_Preedit) &&
        int(event.text_length) > len(event.text) {
        return {}
    }
    if event.kind == .Text_Preedit {
        terminal_clear_completion(term)
        payload := event
        _ = termhist.termhist_update_preedit(
            term.history, input.input_event_text_payload(&payload),
            event.preedit_start, event.preedit_length)
        return {}
    }
    if event.kind == .Text_Cancel {
        termhist.termhist_clear_preedit(term.history)
        return {}
    }
    if event.kind == .Text_Commit {
        payload := event
        return {
            cursor_moved = terminal_update_text_commit(
                term, input.input_event_text_payload(&payload)),
        }
    }
    return {}
}

// terminal_update_text_commit preserves prompt triggers while inserting a whole commit.
terminal_update_text_commit :: proc(
    term: ^viewterminalmodel.Terminal_State, text: string) -> bool {
    if len(text) == 0 || !utf8.valid_string(text) {
        return false
    }
    offset := 0
    first, width := utf8.decode_rune(text)
    if terminal_enter_help_mode_on_question_mark(term, first) ||
        terminal_enter_pkg_mode_on_bracket(term, first) ||
        terminal_enter_shell_mode_on_semicolon(term, first) {
        offset = width
    }
    if offset >= len(text) {
        termhist.termhist_clear_preedit(term.history)
        return true
    }
    return termhist.termhist_commit_text(term.history, text[offset:])
}

// Apply one committed Unicode text event and consume eligible leading mode triggers.
terminal_update_char_input_event :: proc(
    term: ^viewterminalmodel.Terminal_State, event: input.Input_Event) -> bool {
    codepoint := event.codepoint
    if terminal_enter_help_mode_on_question_mark(term, codepoint) ||
        terminal_enter_pkg_mode_on_bracket(term, codepoint) ||
        terminal_enter_shell_mode_on_semicolon(term, codepoint) {
        return true
    }
    buffer, buffer_len := utf8.encode_rune(codepoint)
    termhist.termhist_insert_text(term.history, string(buffer[:buffer_len]))
    return true
}

//   Switch to a mode's prompt when its trigger character is typed at the
//   start of a non-continuation line while still in the normal mode,
//   keeping any text already typed after it.
//
// Parameters:
//   - term: Terminal state whose prompt mode may change.
//   - mode: Target non-normal evaluation mode.
//
// Returns:
//   - true if the mode switch applied.
//
// Side effects:
//   - Replaces Normal mode only at byte-zero of a non-continuation input line.
terminal_try_enter_mode :: proc(
    term: ^viewterminalmodel.Terminal_State, mode: protocol.Evaluation_Mode) -> bool {
    if term.input_mode != .Normal || term.collecting_continuation {
        return false
    }
    if termhist.termhist_cursor(term.history) != 0 {
        return false
    }
    term.input_mode = mode
    term.history.undo.sequence = false
    return true
}

// Consume exact undo/redo chords without capturing AltGr or other modified text.
terminal_update_undo_key :: proc(
    term: ^viewterminalmodel.Terminal_State,
    event: input.Input_Event) -> (Terminal_Keyboard_Update, bool) {
    if event.kind != .Press && event.kind != .Repeat {
        return {}, false
    }
    control := event.modifiers == {.Control}
    control_shift := event.modifiers == {.Control, .Shift}
    redo := event.key == .Z && control_shift ||
        event.key == .Minus && event.modifiers == {.Super, .Shift}
    undo := event.key == .Z && control || event.key == .Slash && control ||
        event.key == .Minus && control_shift
    if !undo && !redo {
        return {}, false
    }
    changed := termhist.termhist_redo(term.history) if redo else
        termhist.termhist_undo(term.history)
    if changed {
        terminal_clear_completion(term)
        term.draft_selection_dragging = false
    }
    return {
        cursor_moved = changed,
    }, true
}

//   Switch to the `help?>` prompt when `?` is typed at the start of a
//   non-continuation line, keeping any text already typed after it.
//
// Parameters:
//   - term: Terminal state whose prompt mode may change.
//   - codepoint: Typed Unicode scalar to test for the help trigger.
//
// Returns:
//   - true if the codepoint was consumed as a mode switch instead of being inserted.
//
// Side effects:
//   - May replace Normal mode with Help when the trigger is valid at byte zero.
terminal_enter_help_mode_on_question_mark :: proc(
    term: ^viewterminalmodel.Terminal_State, codepoint: rune) -> bool {
    if codepoint != '?' {
        return false
    }
    return terminal_try_enter_mode(term, .Help)
}

//   Switch to the `pkg>` prompt when `]` is typed at the start of a
//   non-continuation line, keeping any text already typed after it.
//
// Parameters:
//   - term: Terminal state whose prompt mode may change.
//   - codepoint: Typed Unicode scalar to test for the package trigger.
//
// Returns:
//   - true if the codepoint was consumed as a mode switch instead of being inserted.
//
// Side effects:
//   - May replace Normal mode with Pkg when the trigger is valid at byte zero.
terminal_enter_pkg_mode_on_bracket :: proc(
    term: ^viewterminalmodel.Terminal_State, codepoint: rune) -> bool {
    if codepoint != ']' {
        return false
    }
    return terminal_try_enter_mode(term, .Pkg)
}

//   Switch to `shell>` when `;` starts a normal non-continuation line.
//
// Parameters:
//   - term: Terminal state whose prompt mode may change.
//   - codepoint: Typed Unicode scalar to test for the shell trigger.
//
// Returns:
//   - True when the semicolon was consumed as a mode switch instead of inserted.
//
// Side effects:
//   - May replace Normal mode with Shell when the trigger is valid at byte zero.
terminal_enter_shell_mode_on_semicolon :: proc(
    term: ^viewterminalmodel.Terminal_State, codepoint: rune) -> bool {
    if codepoint != ';' {
        return false
    }
    return terminal_try_enter_mode(term, .Shell)
}

//   Release the terminal-owned preview insertion and its replacement range.
//
// Parameters:
//   - term: Terminal state whose preview may be retained; nil is a no-op.
//
// Side effects:
//   - Releases the borrowed preview view and zeros its replacement bounds.
terminal_clear_completion_preview :: proc(term: ^viewterminalmodel.Terminal_State) {
    if term == nil {
        return
    }
    if len(term.completion_preview_insertion) > 0 {
        term.completion_preview_insertion = ""
    }
    term.completion_preview_start = 0
    term.completion_preview_end = 0
}

//   Clear an in-flight completion snapshot and any rendered preview.
//
// Parameters:
//   - term: Terminal state whose completion transaction is cleared; nil is a no-op.
//
// Side effects:
//   - Releases retained source and preview views, clears correlation and debounce state,
//     and permits a later completion transaction.
terminal_clear_completion :: proc(term: ^viewterminalmodel.Terminal_State) {
    if term == nil {
        return
    }
    if len(term.pending_completion_source) > 0 {
        term.pending_completion_source = ""
    }
    term.pending_completion_request_id = 0
    term.pending_completion_cursor = 0
    term.completion_result_received = false
    term.completion_request_scheduled = false
    term.completion_request_due = 0
    terminal_clear_completion_preview(term)
}

//   Schedule a completion request after the editor has been idle briefly.
//
// Parameters:
//   - term: Terminal state whose current input may need completion; nil is a no-op.
//   - now: Current monotonic frame time in seconds.
//
// Side effects:
//   - Records one debounce deadline only for nonempty editable input outside evaluation.
terminal_schedule_completion :: proc(term: ^viewterminalmodel.Terminal_State, now: f64) {
    if term == nil || term.awaiting_eval || term.history == nil ||
        term.history.preedit_active ||
        len(termhist.termhist_current_text(term.history)) == 0 {
        return
    }
    term.completion_request_scheduled = true
    term.completion_request_due = now + TERMINAL_COMPLETION_DEBOUNCE_SECONDS
}

//   Emit a delayed completion request once its debounce deadline has passed.
//
// Parameters:
//   - term: Terminal state containing scheduled and in-flight completion state.
//   - now: Current monotonic frame time in seconds.
//
// Returns:
//   - A correlated request when due and no request is active; otherwise an empty value.
//
// Side effects:
//   - May snapshot current input and begin a completion transaction.
terminal_take_scheduled_completion :: proc(
    term: ^viewterminalmodel.Terminal_State, now: f64) -> Terminal_Completion_Request {
    if term == nil || !term.completion_request_scheduled ||
        now < term.completion_request_due || term.pending_completion_request_id != 0 {
        return {}
    }
    return terminal_request_completion(term, false)
}

//   Snapshot the live input for a Julia completion request.
//
// Parameters:
//   - term: Terminal state owning current input and bounded snapshot storage.
//   - show_candidates: Whether Julia should include a visible candidate list.
//
// Returns:
//   - A correlated request borrowing retained source storage, or empty when oversized.
//
// Side effects:
//   - Clears older completion state, copies current input, advances request identity, and
//     records the exact source and cursor snapshot required for response validation.
terminal_request_completion :: proc(
    term: ^viewterminalmodel.Terminal_State,
    show_candidates := true) -> Terminal_Completion_Request {
    if term == nil || term.history == nil || term.history.preedit_active {
        return {}
    }
    source := termhist.termhist_current_text(term.history)
    if len(source) > len(term.pending_completion_storage) {
        terminal_reject_completion(term, "source_capacity")
        return {}
    }
    terminal_clear_completion(term)
    if len(source) > 0 {
        copy(term.pending_completion_storage[:len(source)], transmute([]u8)source)
    }
    term.next_completion_request_id += 1
    term.pending_completion_request_id = term.next_completion_request_id
    term.pending_completion_cursor = termhist.termhist_cursor(term.history)
    term.pending_completion_source = string(
        term.pending_completion_storage[:len(source)])
    return {
        requested = true,
        request_id = term.pending_completion_request_id,
        code = term.pending_completion_source,
        cursor_byte = termhist.termhist_cursor(term.history),
        show_candidates = show_candidates,
    }
}

//   Retain a completion preview only when its input snapshot still matches.
//
// Parameters:
//   - term: Terminal state owning the in-flight completion snapshot.
//   - preview: Correlated replacement range and insertion returned by Julia.
//
// Returns:
//   - True when the response was current and consumed; false for stale, duplicate, or
//     oversized responses.
//
// Side effects:
//   - Marks the response received, copies valid insertion bytes into retained storage,
//     or clears the completion transaction when no result or invalid size is returned.
terminal_set_completion_preview :: proc(
    term: ^viewterminalmodel.Terminal_State,
    preview: Terminal_Completion_Preview) -> bool {
    if term == nil || term.history == nil ||
        term.history.preedit_active ||
        term.completion_result_received ||
        term.pending_completion_request_id == 0 ||
        preview.request_id != term.pending_completion_request_id ||
        termhist.termhist_cursor(term.history) != term.pending_completion_cursor ||
        termhist.termhist_current_text(term.history) != term.pending_completion_source {
        return false
    }
    term.completion_result_received = true
    if len(preview.insertion) > len(term.completion_preview_storage) {
        terminal_reject_completion(term, "result_capacity")
        return false
    }
    if !preview.found {
        terminal_clear_completion(term)
        return true
    }
    if !terminal_completion_replacement_valid(
        termhist.termhist_current_text(term.history), preview) {
        terminal_reject_completion(term, "replacement_range")
        return false
    }
    terminal_clear_completion_preview(term)
    if len(preview.insertion) > 0 {
        copy(term.completion_preview_storage[:len(preview.insertion)],
            transmute([]u8)preview.insertion)
    }
    term.completion_preview_start = preview.replacement_start
    term.completion_preview_end = preview.replacement_end
    term.completion_preview_insertion = string(
        term.completion_preview_storage[:len(preview.insertion)])
    return true
}

// Admit only valid UTF-8 replacements whose source range follows grapheme boundaries.
terminal_completion_replacement_valid :: proc(
    source: string, preview: Terminal_Completion_Preview) -> bool {
    start, end := preview.replacement_start, preview.replacement_end
    return start >= 0 && end >= start && end <= len(source) &&
        utf8.valid_string(preview.insertion) &&
        coretext.text_grapheme_clamp_boundary(source, start) == start &&
        coretext.text_grapheme_clamp_boundary(source, end) == end
}

//   Consume a current completion failure without disturbing newer input.
//
// Parameters:
//   - term: Terminal state owning the in-flight completion snapshot.
//   - request_id: Correlation identity of the failed request.
//
// Returns:
//   - True when the failure matches the still-current source and cursor snapshot.
//
// Side effects:
//   - Clears completion state only for the matching current transaction.
terminal_fail_completion :: proc(
    term: ^viewterminalmodel.Terminal_State, request_id: protocol.Request_Id) -> bool {
    if term == nil || term.history == nil || term.completion_result_received ||
        request_id == 0 ||
        request_id != term.pending_completion_request_id ||
        termhist.termhist_cursor(term.history) != term.pending_completion_cursor ||
        termhist.termhist_current_text(term.history) != term.pending_completion_source {
        return false
    }
    terminal_clear_completion(term)
    return true
}

//   Apply the retained completion preview to the live UTF-8 input.
//
// Parameters:
//   - term: Terminal state owning current input and retained preview state.
//
// Returns:
//   - True when a still-current preview replacement is applied; otherwise false.
//
// Side effects:
//   - Replaces the preview range in termhist and clears the completion transaction.
terminal_accept_completion_preview :: proc(
    term: ^viewterminalmodel.Terminal_State) -> bool {
    if term == nil || term.history == nil ||
        term.history.preedit_active ||
        len(term.completion_preview_insertion) == 0 ||
        termhist.termhist_cursor(term.history) != term.pending_completion_cursor ||
        termhist.termhist_current_text(term.history) != term.pending_completion_source {
        return false
    }
    applied := termhist.termhist_replace_input_range(
        term.history, term.completion_preview_start,
        term.completion_preview_end, term.completion_preview_insertion)
    terminal_clear_completion(term)
    terminal_report_edit_failure(term)
    if applied {
        term.view_selection_active = false
        term.view_selection_dragging = false
        term.draft_selection_dragging = false
    }
    return applied
}

// Retire a rejected transaction visibly without changing the editable draft.
terminal_reject_completion :: proc(
    term: ^viewterminalmodel.Terminal_State, reason: string) {
    terminal_clear_completion(term)
    log.warnf("terminal_completion_rejected reason=%s", reason)
    terminal_append_output_line(
        term, "Terminal completion unavailable: request failed or exceeded supported limits.")
}

//   Exit the active help/pkg mode on an empty line instead of backspacing,
//   returning true if a mode exit was applied.
//
// Parameters:
//   - term: Terminal state whose non-normal mode may be active.
//
// Returns:
//   - True when empty input caused a return to Normal mode; otherwise false.
//
// Side effects:
//   - Restores Normal mode when the guard conditions hold.
terminal_try_exit_mode_on_empty_backspace :: proc(
    term: ^viewterminalmodel.Terminal_State) -> bool {
    if term.input_mode != .Normal &&
       len(termhist.termhist_current_text(term.history)) == 0 {
        term.input_mode = .Normal
        term.history.undo.sequence = false
        return true
    }
    return false
}

//   Apply deletion and horizontal cursor keys for one input frame.
//
// Parameters:
//   - term: Terminal state owning the editable input and completion preview.
//   - frame: Polled input frame containing editing key edges and repeats.
//
// Returns:
//   - True when any supported horizontal editing action was attempted.
//
// Side effects:
//   - May change prompt mode, delete text, move the cursor, or accept a completion.
terminal_update_horizontal_editing :: proc(
    term: ^viewterminalmodel.Terminal_State, frame: input.Input_Frame) -> bool {
    handled := terminal_update_word_arrow_keys(term, frame)
    handled = terminal_update_deletion_keys(term, frame) || handled
    handled = terminal_update_character_arrow_keys(term, frame) || handled
    handled = terminal_update_emacs_movement_keys(term, frame) || handled
    return terminal_update_word_and_line_deletion_keys(term, frame) || handled
}

// Apply Ctrl/Meta word movement on the horizontal arrow keys.
terminal_update_word_arrow_keys :: proc(
    term: ^viewterminalmodel.Terminal_State, frame: input.Input_Frame) -> bool {
    handled := false
    if terminal_input_chord(frame, .Left, {.Control}) ||
        terminal_input_chord(frame, .Left, {.Super}) {
        termhist.termhist_move_word(
            term.history, true, terminal_input_chord(frame, .Left, {.Shift}))
        handled = true
    }
    if terminal_input_chord(frame, .Right, {.Control}) ||
        terminal_input_chord(frame, .Right, {.Super}) {
        termhist.termhist_move_word(
            term.history, false, terminal_input_chord(frame, .Right, {.Shift}))
        handled = true
    }
    return handled
}

// Apply Backspace, Delete, and contentful Ctrl+D editing.
terminal_update_deletion_keys :: proc(
    term: ^viewterminalmodel.Terminal_State, frame: input.Input_Frame) -> bool {
    handled := false
    if input.input_key_pressed_or_repeat(frame, .Backspace) {
        if terminal_input_chord(frame, .Backspace, {.Super}) {
            termhist.termhist_delete_word(term.history, true)
        } else if !terminal_try_exit_mode_on_empty_backspace(term) {
            termhist.termhist_backspace(term.history)
        }
        handled = true
    }
    if input.input_key_pressed_or_repeat(frame, .Delete) {
        if terminal_input_chord(frame, .Delete, {.Super}) {
            termhist.termhist_delete_word(term.history, false)
        } else {
            termhist.termhist_delete_forward(term.history)
        }
        handled = true
    }
    if terminal_input_chord(frame, .D, {.Control}) &&
        len(termhist.termhist_current_text(term.history)) > 0 {
        termhist.termhist_delete_forward(term.history)
        return true
    }
    return handled
}

// Apply unmodified Left and Right grapheme movement.
terminal_update_character_arrow_keys :: proc(
    term: ^viewterminalmodel.Terminal_State, frame: input.Input_Frame) -> bool {
    handled := false
    if input.input_key_pressed_or_repeat(frame, .Left) &&
        !terminal_input_chord(frame, .Left, {.Control}) &&
        !terminal_input_chord(frame, .Left, {.Super}) {
        termhist.termhist_move_left(
            term.history, terminal_input_chord(frame, .Left, {.Shift}))
        handled = true
    }
    if input.input_key_pressed_or_repeat(frame, .Right) &&
        !terminal_input_chord(frame, .Right, {.Control}) &&
        !terminal_input_chord(frame, .Right, {.Super}) {
        if !terminal_accept_completion_preview(term) {
            termhist.termhist_move_right(
                term.history, terminal_input_chord(frame, .Right, {.Shift}))
        }
        handled = true
    }
    return handled
}

// Apply Ctrl+B/F and Meta+B/F editor movement aliases.
terminal_update_emacs_movement_keys :: proc(
    term: ^viewterminalmodel.Terminal_State, frame: input.Input_Frame) -> bool {
    handled := false
    if terminal_input_chord(frame, .B, {.Control}) {
        termhist.termhist_move_left(
            term.history, terminal_input_chord(frame, .B, {.Shift}))
        handled = true
    }
    if terminal_input_chord(frame, .F, {.Control}) {
        termhist.termhist_move_right(
            term.history, terminal_input_chord(frame, .F, {.Shift}))
        handled = true
    }
    if terminal_input_chord(frame, .B, {.Super}) {
        termhist.termhist_move_word(
            term.history, true, terminal_input_chord(frame, .B, {.Shift}))
        handled = true
    }
    if terminal_input_chord(frame, .F, {.Super}) {
        termhist.termhist_move_word(
            term.history, false, terminal_input_chord(frame, .F, {.Shift}))
        handled = true
    }
    return handled
}

// Apply whitespace-word and logical-line deletion shortcuts.
terminal_update_word_and_line_deletion_keys :: proc(
    term: ^viewterminalmodel.Terminal_State, frame: input.Input_Frame) -> bool {
    handled := false
    if terminal_input_chord(frame, .W, {.Control}) {
        termhist.termhist_delete_word(term.history, true)
        handled = true
    }
    if terminal_input_chord(frame, .D, {.Super}) {
        termhist.termhist_delete_word(term.history, false)
        handled = true
    }
    if terminal_input_chord(frame, .U, {.Control}) {
        termhist.termhist_delete_to_line_edge(term.history, false)
        handled = true
    }
    if terminal_input_chord(frame, .K, {.Control}) {
        termhist.termhist_delete_to_line_edge(term.history, true)
        handled = true
    }
    return handled
}

// Match a press or repeat carrying every requested modifier.
terminal_input_chord :: proc(
    frame: input.Input_Frame, key: input.Input_Key,
    required: input.Input_Modifiers) -> bool {
    for event in frame.events {
        if (event.kind == .Press || event.kind == .Repeat) &&
            event.key == key && required & event.modifiers == required {
            return true
        }
    }
    return false
}

//   Apply absolute cursor keys for one input frame.
//
// Parameters:
//   - term: Terminal state owning the editable draft.
//   - frame: Polled input frame containing navigation key edges and repeats.
//
// Returns:
//   - True when any supported absolute cursor action was attempted.
//
// Side effects:
//   - May browse history, restore prompt metadata, or move to input start or end.
terminal_update_history_navigation :: proc(
    term: ^viewterminalmodel.Terminal_State, frame: input.Input_Frame) -> bool {
    handled := terminal_update_line_navigation(term, frame)
    handled = terminal_update_buffer_navigation(term, frame) || handled
    return terminal_update_async_history_navigation(term, frame) || handled
}

// Apply Home/End and Ctrl+A/E logical-line movement.
terminal_update_line_navigation :: proc(
    term: ^viewterminalmodel.Terminal_State, frame: input.Input_Frame) -> bool {
    handled := false
    if input.input_key_pressed(frame, .Home) {
        termhist.termhist_move_home(
            term.history, terminal_input_chord(frame, .Home, {.Shift}))
        handled = true
    }
    if input.input_key_pressed(frame, .End) {
        termhist.termhist_move_end(
            term.history, terminal_input_chord(frame, .End, {.Shift}))
        handled = true
    }
    if terminal_input_chord(frame, .A, {.Control}) {
        termhist.termhist_move_home(
            term.history, terminal_input_chord(frame, .A, {.Shift}))
        handled = true
    }
    if terminal_input_chord(frame, .E, {.Control}) {
        termhist.termhist_move_end(
            term.history, terminal_input_chord(frame, .E, {.Shift}))
        handled = true
    }
    return handled
}

// Apply Ctrl+Home/End movement across the complete draft.
terminal_update_buffer_navigation :: proc(
    term: ^viewterminalmodel.Terminal_State, frame: input.Input_Frame) -> bool {
    handled := false
    if terminal_input_chord(frame, .Home, {.Control}) {
        termhist.termhist_move_buffer_home(
            term.history, terminal_input_chord(frame, .Home, {.Shift}))
        handled = true
    }
    if terminal_input_chord(frame, .End, {.Control}) {
        termhist.termhist_move_buffer_end(
            term.history, terminal_input_chord(frame, .End, {.Shift}))
        handled = true
    }
    return handled
}

// Keep browsing history once active; otherwise preserve multiline editor movement.
terminal_update_async_history_navigation :: proc(
    term: ^viewterminalmodel.Terminal_State, frame: input.Input_Frame) -> bool {
    handled := false
    if input.input_key_pressed_or_repeat(frame, .Up) {
        if term.history_navigation_active ||
           !terminal_hist_vertical_move(term, frame, -1) {
            terminal_history_navigation_queue(term, -1)
        } else {
            terminal_history_navigation_invalidate(term)
        }
        handled = true
    }
    if input.input_key_pressed_or_repeat(frame, .Down) {
        if term.history_navigation_active ||
           !terminal_hist_vertical_move(term, frame, 1) {
            terminal_history_navigation_queue(term, 1)
        } else {
            terminal_history_navigation_invalidate(term)
        }
        handled = true
    }
    return handled
}

// Preserve navigation state across every Up/Down event, including key release.
terminal_history_navigation_event :: proc(event: input.Input_Event) -> bool {
    navigation_key := event.key == .Up || event.key == .Down
    navigation_event := event.kind == .Press || event.kind == .Repeat ||
        event.kind == .Release
    return navigation_key && navigation_event
}

// Invalidate asynchronous recall before a user action can change its editor target.
terminal_history_navigation_invalidate :: proc(
    term: ^viewterminalmodel.Terminal_State) {
    if term == nil {
        return
    }
    term.history_navigation_epoch += 1
    if term.history_navigation_epoch == 0 {
        term.history_navigation_epoch = 1
    }
    term.history_navigation_intent_count = 0
    term.history_navigation_pending_id = 0
    term.history_navigation_admission_reported = false
    term.history_navigation_active = false
    term.history_navigation_anchor_id = 0
}

// Queue one ordered boundary-navigation intent and preserve the full unsent draft once.
terminal_history_navigation_queue :: proc(
    term: ^viewterminalmodel.Terminal_State, direction: int) {
    if direction != -1 && direction != 1 {
        return
    }
    if direction > 0 && !term.history_navigation_active {
        return
    }
    if !term.history_navigation_active {
        if !termhist.termhist_backup_current(term.history) {
            log.warn("terminal_history_navigation_rejected reason=draft_capacity")
            return
        }
        term.history_navigation_epoch += 1
        term.history_navigation_active = true
        term.history_navigation_anchor_id = max(u64)
        term.history_navigation_draft_mode = term.input_mode
        term.input_mode_backup = term.input_mode
    }
    if term.history_navigation_intent_count >=
       len(term.history_navigation_intents) {
        log.warn("terminal_history_navigation_rejected reason=intent_queue_full")
        return
    }
    term.history_navigation_intents[term.history_navigation_intent_count] = direction
    term.history_navigation_intent_count += 1
}

// Apply vertical movement, leaving unshifted boundary presses for history browsing.
terminal_hist_vertical_move :: proc(
    term: ^viewterminalmodel.Terminal_State, frame: input.Input_Frame,
    direction: int) -> bool {
    key := input.Input_Key.Up if direction < 0 else input.Input_Key.Down
    extend := terminal_input_chord(frame, key, {.Shift})
    columns := terminal_live_input_wrap_columns(
        term, termhist.termhist_current_text(term.history))
    preferred := term.history.preferred_column
    if extend {
        moved := termhist.termhist_move_vertical(
            term.history, direction, columns, true)
        if !moved {
            term.history.preferred_column = preferred
        }
        return true
    }
    moved := termhist.termhist_move_vertical(term.history, direction, columns)
    if !moved {
        term.history.preferred_column = preferred
    }
    return moved
}

//   Apply editing and cursor-navigation keys for one input frame.
//
// Parameters:
//   - term: Terminal state owning editable history and completion state.
//   - frame: Polled input frame containing key edges and repeats.
//
// Returns:
//   - True when any supported editing/navigation action was attempted.
//
// Side effects:
//   - Mutates termhist, may accept a completion preview, or leave an
//     empty non-normal mode.
terminal_update_editing_keys :: proc(
    term: ^viewterminalmodel.Terminal_State, frame: input.Input_Frame) -> bool {
    horizontal := terminal_update_horizontal_editing(term, frame)
    history := terminal_update_history_navigation(term, frame)
    return horizontal || history
}


//   Report whether Ctrl+D on the live line should submit `exit()`, matching
//   a shell's EOF-on-empty-line convention.
//
// Parameters:
//   - term: Terminal state whose current prompt and input are inspected.
//
// Returns:
//   - True only for an empty, non-continuation Normal-mode line with history present.
terminal_can_exit_on_ctrl_d :: proc(term: ^viewterminalmodel.Terminal_State) -> bool {
    return term.history != nil && term.input_mode == .Normal &&
           !term.collecting_continuation &&
           len(termhist.termhist_current_text(term.history)) == 0
}

//   Consume editing, navigation, completion, and submission keys for one frame.
//
// Parameters:
//   - term: The terminal state field owned by the caller.
//   - frame: This frame's polled keyboard state.
//
// Returns:
//   - Submission, completion, and cursor-movement details for this frame.
//
// Side effects:
//   - Applies editing before shortcut priority, may cancel package mode, request/accept
//     completion, synthesize `exit()` for Ctrl+D, or commit input on Enter.
terminal_update_navigation_keys :: proc(
    term: ^viewterminalmodel.Terminal_State,
    frame: input.Input_Frame) -> Terminal_Keyboard_Update {
    cursor_moved := terminal_update_editing_keys(term, frame)
    update, handled := terminal_update_editor_shortcuts(term, frame, cursor_moved)
    if handled {
        return update
    }
    update, handled = terminal_update_submission_shortcuts(
        term, frame, cursor_moved)
    return update if handled else {
        cursor_moved = cursor_moved,
    }
}

// Handle cancel, clear, focus-traversal, and completion shortcuts.
terminal_update_editor_shortcuts :: proc(
    term: ^viewterminalmodel.Terminal_State, frame: input.Input_Frame,
    cursor_moved: bool) -> (Terminal_Keyboard_Update, bool) {
    if terminal_input_chord(frame, .C, {.Control}) &&
        !terminal_input_chord(frame, .C, {.Shift}) {
        terminal_cancel_draft(term)
        return {
            cursor_moved = true,
        }, true
    }
    if terminal_input_chord(frame, .L, {.Control}) {
        terminal_clear_console(term)
        term.history.undo.sequence = false
        return {
            cursor_moved = true,
        }, true
    }
    if terminal_input_chord(frame, .Tab, {.Control}) {
        return {
            cursor_moved = cursor_moved,
        }, true
    }
    if input.input_key_pressed(frame, .Tab) {
        if terminal_accept_completion_preview(term) {
            return {
                cursor_moved = true,
            }, true
        }
        completion := terminal_request_completion(term, true)
        if completion.requested {
            term.history.undo.sequence = false
        }
        return {
            completion = completion,
            cursor_moved = completion.requested,
        }, true
    }
    return {}, false
}

// Handle explicit newline and submit/EOF shortcuts.
terminal_update_submission_shortcuts :: proc(
    term: ^viewterminalmodel.Terminal_State, frame: input.Input_Frame,
    cursor_moved: bool) -> (Terminal_Keyboard_Update, bool) {
    if input.input_chord_pressed(frame, .D, {.Control}) &&
        terminal_can_exit_on_ctrl_d(term) {
        termhist.termhist_insert_text(term.history, "exit()")
        submitted_text := terminal_submit(term)
        return {
            submission = {
                text = submitted_text,
                mode = term.input_mode,
                continuation = term.collecting_continuation,
                submitted = true,
            },
            cursor_moved = true,
        }, true
    }
    if terminal_input_chord(frame, .Enter, {.Alt}) {
        termhist.termhist_insert_text(term.history, "\n")
        return {
            cursor_moved = true,
        }, true
    }
    if terminal_input_chord(frame, .J, {.Control}) {
        submitted_text := terminal_submit(term)
        return {
            submission = {
                text = submitted_text,
                mode = term.input_mode,
                continuation = term.collecting_continuation,
                submitted = true,
            },
            cursor_moved = true,
        }, true
    }
    if input.input_key_pressed(frame, .Enter) ||
        input.input_key_pressed(frame, .Keypad_Enter) {
        submitted_text := terminal_submit(term)
        return {
            submission = {
                text = submitted_text,
                mode = term.input_mode,
                continuation = term.collecting_continuation,
                submitted = true,
            },
            cursor_moved = true,
        }, true
    }
    return {
        cursor_moved = cursor_moved,
    }, false
}

// Cancel draft work without interrupting an evaluation already owned by Julia.
terminal_cancel_draft :: proc(term: ^viewterminalmodel.Terminal_State) {
    terminal_history_navigation_invalidate(term)
    if term.collecting_continuation {
        terminal_restore_output_checkpoint(term)
        term.output_checkpoint.valid = false
    }
    termhist.termhist_clear(term.history)
    termhist.termhist_clear_preedit(term.history)
    terminal_clear_completion(term)
    term.collecting_continuation = false
    term.input_mode = .Normal
    term.input_mode_backup = .Normal
    term.pending_draft_valid = false
}

// Clear the visible Terminal output through its owned grid and scrollback state.
terminal_clear_console :: proc(term: ^viewterminalmodel.Terminal_State) {
    if term == nil {
        return
    }
    termemulator.interpreter_publish_synchronized_output(
        &term.output_interpreter, true)
    termgrid.scrollback_clear(&term.output_scrollback)
    terminal_clear_shell_rows(term, &term.output_grid)
    terminal_clear_shell_rows(term, &term.output_alternate_grid)
    termemulator.interpreter_clear_display(&term.output_interpreter)
    term.view_selection_active = false
    term.view_selection_dragging = false
    term.draft_selection_dragging = false
    term.view_selection_anchor = {}
    term.view_selection_head = {}
    term.scroll_offset_y = 0
    term.output_started = false
    if term.collecting_continuation {
        term.output_checkpoint_started = false
        if !termgrid.display_checkpoint_capture(
            term.output_checkpoint, &term.output_grid, &term.output_scrollback) {
            term.output_checkpoint.valid = false
        }
    }
}

// Remove semantic command blocks whose rendered rows are cleared from a screen.
terminal_clear_shell_rows :: proc(
    term: ^viewterminalmodel.Terminal_State, grid: ^termgrid.Grid) {
    if term == nil || grid == nil || grid.editing == nil ||
        grid.editing.screen != .Primary || term.shell_integration == nil {
        return
    }
    for row in grid.rows {
        termshellintegration.shell_command_evict_through(
            term.shell_integration, i64(row.logical_line_id))
    }
}

// Resolve negotiated child pointer ownership, including the local Shift override.
terminal_mouse_reporting_owns_pointer :: proc(
    term: ^viewterminalmodel.Terminal_State, frame: input.Input_Frame) -> bool {
    mode := termemulator.interpreter_input_mode(&term.output_interpreter)
    return mode.mouse_tracking != .None && mode.mouse_sgr_encoding &&
        .Shift not_in frame.mouse_modifiers
}

//   Track a left-mouse drag over the terminal view as a highlight selection.
//
// Parameters:
//   - term: The terminal state field owned by the caller.
//   - frame: This frame's polled mouse state.
//   - font: The monospace font used for hit-testing.
//   - bounds: The rectangle the terminal is drawn within, matching terminal_draw.
//
// Side effects:
//   - Starts, extends, or releases the mouse-driven view selection.
terminal_update_mouse_selection :: proc(
    term: ^viewterminalmodel.Terminal_State, frame: input.Input_Frame,
    font: font.Font_Face, bounds: geometry.Rectangle) {
    if terminal_mouse_reporting_owns_pointer(term, frame) {
        return
    }
    if term.hyperlink_pressed != 0 {
        return
    }
    if terminal_update_draft_mouse_selection(term, frame, bounds) {
        return
    }
    mouse: geometry.Vector2 = {frame.mouse_position.x, frame.mouse_position.y}
    if .Left in frame.mouse_pressed {
        if term.shell_integration != nil {
            term.shell_integration.search_match_generation = 0
        }
        if position, ok := terminal_hit_test(term, font, bounds, mouse);
            ok {
            term.view_selection_anchor = position
            term.view_selection_head = position
            term.view_selection_dragging = true
            term.view_selection_active = false
        }
    }

    if !term.view_selection_dragging {
        return
    }

    if position, ok := terminal_hit_test(term, font, bounds, mouse); ok {
        term.view_selection_head = position
        head := term.view_selection_head
        term.view_selection_active = head != term.view_selection_anchor
    }

    if .Left in frame.mouse_released {
        term.view_selection_dragging = false
    }
}

// Route pointer selection inside the visible prompt to the editable draft.
terminal_update_draft_mouse_selection :: proc(
    term: ^viewterminalmodel.Terminal_State, frame: input.Input_Frame,
    bounds: geometry.Rectangle) -> bool {
    if term.history == nil || term.geometry.column_width <= 0 ||
        term.geometry.line_height <= 0 {
        return false
    }
    mouse: geometry.Vector2 = {frame.mouse_position.x, frame.mouse_position.y}
    padded := terminal_padded_bounds(bounds)
    prompt_y := padded.y - term.scroll_offset_y +
        f32(terminal_line_count(term)) * term.geometry.line_height
    rows := terminal_live_input_line_count(term)
    prompt_bounds: geometry.Rectangle = {
        padded.x, prompt_y, padded.width,
        f32(rows) * term.geometry.line_height,
    }
    if .Left in frame.mouse_pressed &&
        geometry.rectangle_contains(prompt_bounds, mouse) {
        target, _ := terminal_draft_offset_at_point(term, padded, mouse)
        _ = termhist.termhist_set_cursor(term.history, target)
        term.draft_selection_dragging = true
        term.view_selection_dragging = false
        term.view_selection_active = false
    }
    if !term.draft_selection_dragging {
        return false
    }
    target, _ := terminal_draft_offset_at_point(term, padded, mouse)
    _ = termhist.termhist_set_cursor(term.history, target, true)
    if .Left in frame.mouse_released {
        term.draft_selection_dragging = false
    }
    return true
}

// Map a screen point in the prompt to the nearest grapheme cursor boundary.
terminal_draft_offset_at_point :: proc(
    term: ^viewterminalmodel.Terminal_State, bounds: geometry.Rectangle,
    point: geometry.Vector2) -> (int, bool) {
    text := termhist.termhist_current_text(term.history)
    row_count := terminal_live_input_line_count(term)
    if row_count <= 0 {
        return 0, false
    }
    prompt_y := bounds.y - term.scroll_offset_y +
        f32(terminal_line_count(term)) * term.geometry.line_height
    row := clamp(int((point.y - prompt_y) / term.geometry.line_height), 0, row_count - 1)
    row_bounds := terminal_live_input_visual_row_bounds(term, text, row)
    if !row_bounds.found {
        return 0, false
    }
    prefix := TERMINAL_CONTINUATION_PROMPT
    if row == 0 {
        prefix = terminal_primary_prompt_prefix(term)
    }
    prefix_width := coretext.text_grapheme_column(prefix, len(prefix))
    screen_column := int((point.x - bounds.x) / term.geometry.column_width)
    offset := coretext.text_grapheme_boundary_for_column(
        text[row_bounds.start:row_bounds.end], max(0, screen_column - prefix_width))
    return row_bounds.start + offset, true
}

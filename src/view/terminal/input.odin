package terminalview

import "../../core"
import "../../core/protocol"
import termemulator "../../terminal/emulator"
import termhist "../../terminal/history"
import "../input"

import "core:unicode/utf8"

import rl "vendor:raylib"

// Arm or expire the synchronized-output safety deadline on the display clock.
terminal_update_synchronized_output :: proc(
    term: ^core.Terminal_State, now: f64) {
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

//   Poll keyboard input for the active frame and apply it to the live input line.
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
    term: ^core.Terminal_State, frame: input.Input_Frame) -> Terminal_Keyboard_Update {
    if term.awaiting_eval || !term.banner_ready {
        return {}
    }

    typed := terminal_update_char_input(term, frame)
    update := terminal_update_navigation_keys(term, frame)
    update.cursor_moved = typed || update.cursor_moved
    return update
}

//   Insert this frame's already-polled typed characters.
//
// Parameters:
//   - term: The terminal state field owned by the caller.
//   - frame: This frame's polled keyboard state.
//
// Returns:
//   - true if any character was inserted.
//
// Side effects:
//   - Consumes leading mode triggers or inserts complete UTF-8 codepoints into termhist.
terminal_update_char_input :: proc(
    term: ^core.Terminal_State, frame: input.Input_Frame) -> bool {
    if terminal_clipboard_paste_requested(frame) {
        return terminal_insert_clipboard_text(term, input.input_get_clipboard_text())
    }

    typed := false

    for event in frame.events {
        if event.kind != .Text {
            continue
        }
        codepoint := event.codepoint
        if terminal_enter_help_mode_on_question_mark(term, codepoint) {
            typed = true
            continue
        }
        if terminal_enter_pkg_mode_on_bracket(term, codepoint) {
            typed = true
            continue
        }
        if terminal_enter_shell_mode_on_semicolon(term, codepoint) {
            typed = true
            continue
        }

        buffer, buffer_len := utf8.encode_rune(codepoint)
        termhist.termhist_insert_text(term.history, string(buffer[:buffer_len]))
        typed = true
    }

    return typed
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
    term: ^core.Terminal_State, mode: protocol.Evaluation_Mode) -> bool {
    if term.input_mode != .Normal || term.collecting_continuation {
        return false
    }
    if termhist.termhist_cursor(term.history) != 0 {
        return false
    }
    term.input_mode = mode
    return true
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
    term: ^core.Terminal_State, codepoint: rune) -> bool {
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
    term: ^core.Terminal_State, codepoint: rune) -> bool {
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
    term: ^core.Terminal_State, codepoint: rune) -> bool {
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
terminal_clear_completion_preview :: proc(term: ^core.Terminal_State) {
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
terminal_clear_completion :: proc(term: ^core.Terminal_State) {
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
terminal_schedule_completion :: proc(term: ^core.Terminal_State, now: f64) {
    if term == nil || term.awaiting_eval || term.history == nil ||
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
    term: ^core.Terminal_State, now: f64) -> Terminal_Completion_Request {
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
    term: ^core.Terminal_State, show_candidates := true) -> Terminal_Completion_Request {
    source := termhist.termhist_current_text(term.history)
    if len(source) > len(term.pending_completion_storage) {
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
    term: ^core.Terminal_State, preview: Terminal_Completion_Preview) -> bool {
    if term == nil || term.history == nil ||
        term.completion_result_received ||
        preview.request_id != term.pending_completion_request_id ||
        termhist.termhist_cursor(term.history) != term.pending_completion_cursor ||
        termhist.termhist_current_text(term.history) != term.pending_completion_source {
        return false
    }
    term.completion_result_received = true
    if !preview.found {
        terminal_clear_completion(term)
        return true
    }
    if len(preview.insertion) > len(term.completion_preview_storage) {
        terminal_clear_completion(term)
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
    term: ^core.Terminal_State, request_id: protocol.Request_Id) -> bool {
    if term == nil || term.history == nil || term.completion_result_received ||
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
terminal_accept_completion_preview :: proc(term: ^core.Terminal_State) -> bool {
    if term == nil || term.history == nil ||
        len(term.completion_preview_insertion) == 0 ||
        termhist.termhist_cursor(term.history) != term.pending_completion_cursor ||
        termhist.termhist_current_text(term.history) != term.pending_completion_source {
        return false
    }
    applied := termhist.termhist_replace_input_range(
        term.history, term.completion_preview_start,
        term.completion_preview_end, term.completion_preview_insertion)
    terminal_clear_completion(term)
    return applied
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
terminal_try_exit_mode_on_empty_backspace :: proc(term: ^core.Terminal_State) -> bool {
    if term.input_mode != .Normal &&
       len(termhist.termhist_current_text(term.history)) == 0 {
        term.input_mode = .Normal
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
    term: ^core.Terminal_State, frame: input.Input_Frame) -> bool {
    handled := false
    if input.input_key_pressed_or_repeat(frame, .Backspace) {
        if !terminal_try_exit_mode_on_empty_backspace(term) {
            termhist.termhist_backspace(term.history)
        }
        handled = true
    }
    if input.input_key_pressed_or_repeat(frame, .Delete) {
        termhist.termhist_delete_forward(term.history)
        handled = true
    }
    if input.input_key_pressed_or_repeat(frame, .Left) {
        termhist.termhist_move_left(term.history)
        handled = true
    }
    if input.input_key_pressed_or_repeat(frame, .Right) {
        if !terminal_accept_completion_preview(term) {
            termhist.termhist_move_right(term.history)
        }
        handled = true
    }
    return handled
}

//   Apply history and absolute cursor keys for one input frame.
//
// Parameters:
//   - term: Terminal state owning editable history and prompt mode.
//   - frame: Polled input frame containing navigation key edges and repeats.
//
// Returns:
//   - True when any supported history or absolute cursor action was attempted.
//
// Side effects:
//   - May browse history, restore prompt metadata, or move to input start or end.
terminal_update_history_navigation :: proc(
    term: ^core.Terminal_State, frame: input.Input_Frame) -> bool {
    handled := false
    if input.input_key_pressed_or_repeat(frame, .Up) {
        terminal_history_browse_prev(term)
        handled = true
    }
    if input.input_key_pressed_or_repeat(frame, .Down) {
        terminal_history_browse_next(term)
        handled = true
    }
    if input.input_key_pressed(frame, .Home) {
        termhist.termhist_move_home(term.history)
        handled = true
    }
    if input.input_key_pressed(frame, .End) {
        termhist.termhist_move_end(term.history)
        handled = true
    }
    return handled
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
//   - Mutates termhist, may accept a completion preview, browse history, or leave an
//     empty non-normal mode.
terminal_update_editing_keys :: proc(
    term: ^core.Terminal_State, frame: input.Input_Frame) -> bool {
    horizontal := terminal_update_horizontal_editing(term, frame)
    history := terminal_update_history_navigation(term, frame)
    return horizontal || history
}

//   Step to the previous history entry, restoring its recorded prompt mode.
//
// Parameters:
//   - term: Terminal state owning history position and prompt-mode metadata.
//
// Side effects:
//   - Snapshots the live prompt mode as the draft's mode on first browse.
terminal_history_browse_prev :: proc(term: ^core.Terminal_State) {
    if term.history.history_index == term.history.history_len {
        term.input_mode_backup = term.input_mode
    }
    if !termhist.termhist_history_prev(term.history) {
        return
    }
    entry := term.history.history[term.history.history_index]
    term.input_mode = terminal_mode_for_history_tag(entry.tag)
}

//   Step to the next history entry, or restore the draft's prompt mode.
//
// Parameters:
//   - term: Terminal state owning history position and prompt-mode metadata.
//
// Side effects:
//   - Restores the pre-browse mode at the history tail; otherwise applies the selected
//     entry's recorded prompt mode.
terminal_history_browse_next :: proc(term: ^core.Terminal_State) {
    if !termhist.termhist_history_next(term.history) {
        return
    }
    if term.history.history_index == term.history.history_len {
        term.input_mode = term.input_mode_backup
        return
    }
    entry := term.history.history[term.history.history_index]
    term.input_mode = terminal_mode_for_history_tag(entry.tag)
}

//   Map a stored history-entry tag back to the prompt mode it recorded.
//
// Parameters:
//   - tag: Integer metadata stored with one accepted history entry.
//
// Returns:
//   - The corresponding prompt mode, defaulting to Normal for unknown tags.
terminal_mode_for_history_tag :: proc(tag: int) -> protocol.Evaluation_Mode {
    if tag == TERMINAL_HISTORY_TAG_PKG {
        return .Pkg
    }
    if tag == TERMINAL_HISTORY_TAG_HELP {
        return .Help
    }
    if tag == TERMINAL_HISTORY_TAG_SHELL {
        return .Shell
    }
    return .Normal
}

//   Map the active prompt mode to its stored history-entry tag.
//
// Parameters:
//   - mode: Evaluation mode to persist with one accepted history entry.
//
// Returns:
//   - The stable history tag for the mode, defaulting to the Normal tag.
terminal_history_tag_for_mode :: proc(mode: protocol.Evaluation_Mode) -> int {
    switch mode {
    case .Pkg:
        return TERMINAL_HISTORY_TAG_PKG
    case .Help:
        return TERMINAL_HISTORY_TAG_HELP
    case .Shell:
        return TERMINAL_HISTORY_TAG_SHELL
    case .Normal:
        return TERMINAL_HISTORY_TAG_NORMAL
    }
    return TERMINAL_HISTORY_TAG_NORMAL
}

//   Report whether Ctrl+D on the live line should submit `exit()`, matching
//   a shell's EOF-on-empty-line convention.
//
// Parameters:
//   - term: Terminal state whose current prompt and input are inspected.
//
// Returns:
//   - True only for an empty, non-continuation Normal-mode line with history present.
terminal_can_exit_on_ctrl_d :: proc(term: ^core.Terminal_State) -> bool {
    return term.history != nil && term.input_mode == .Normal &&
           !term.collecting_continuation &&
           len(termhist.termhist_current_text(term.history)) == 0
}

//   Poll editing, navigation, completion, and submission keys for one frame.
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
    term: ^core.Terminal_State, frame: input.Input_Frame) -> Terminal_Keyboard_Update {
    cursor_moved := terminal_update_editing_keys(term, frame)
    if input.input_chord_pressed(frame, .C, {.Control}) &&
        terminal_cancel_pkg_mode(term) {
        return {cursor_moved = true}
    }
    if input.input_key_pressed(frame, .Tab) {
        if terminal_accept_completion_preview(term) {
            return {cursor_moved = true}
        }
        return {
            completion = terminal_request_completion(term, true),
            cursor_moved = true,
        }
    }
    if input.input_chord_pressed(frame, .D, {.Control}) &&
        terminal_can_exit_on_ctrl_d(term) {
        termhist.termhist_insert_text(term.history, "exit()")
        submitted_text := terminal_submit(term)
        return {
            submission = {text = submitted_text, submitted = true},
            cursor_moved = true,
        }
    }
    if input.input_key_pressed(frame, .Enter) ||
        input.input_key_pressed(frame, .Keypad_Enter) {
        submitted_text := terminal_submit(term)
        return {
            submission = {text = submitted_text, submitted = true},
            cursor_moved = true,
        }
    }

    return {cursor_moved = cursor_moved}
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
    term: ^core.Terminal_State, frame: input.Input_Frame,
    font: rl.Font, bounds: rl.Rectangle) {
    mode := termemulator.interpreter_input_mode(&term.output_interpreter)
    if mode.mouse_tracking != .None && mode.mouse_sgr_encoding &&
        .Shift not_in frame.mouse_modifiers {
        return
    }
    if term.hyperlink_pressed != 0 {
        return
    }
    mouse := rl.Vector2{frame.mouse_position.x, frame.mouse_position.y}
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

package terminalview

import "../../core"
import termclipboard "../../terminal/clipboard"
import termhist "../../terminal/history"
import termmodel "../../terminal/model"
import "../input"

import "core:log"
import "core:math"

// Publish queued clipboard actions belonging to the current output producer.
//
// Parameters:
//   - term: Terminal owning validated queued actions.
//   - producer: Last producer accepted by terminal output ingress.
//   - sink: Synchronous display-thread clipboard destination.
//
// Returns:
//   - Number of values accepted by the destination.
//
// Side effects:
//   - Discards stale actions, invokes the sink for matching actions, clears all
//     consumed content, and updates content-free publication diagnostics.
terminal_publish_clipboard_actions :: proc(
    term: ^core.Terminal_State, producer: termmodel.Terminal_Producer,
    sink: Terminal_Clipboard_Write_Sink) -> int {
    if term == nil || term.clipboard_actions == nil || sink.write == nil {
        return 0
    }
    queue := term.clipboard_actions
    published := 0
    for {
        action, found := termclipboard.clipboard_action_queue_peek(queue)
        if !found {
            break
        }
        if producer.kind == .None || action.producer != producer {
            queue.stale_discard_count += 1
            queue.stale_discard_byte_count += u64(action.byte_count)
            termclipboard.clipboard_action_queue_pop(queue)
            continue
        }
        if sink.write(
            sink.user_data, string(action.bytes[:action.byte_count])) {
            queue.publication_count += 1
            queue.published_byte_count += u64(action.byte_count)
            published += 1
        } else {
            queue.publication_rejection_count += 1
        }
        termclipboard.clipboard_action_queue_pop(queue)
    }
    return published
}

// Report content-free clipboard action outcomes before retained storage is released.
terminal_log_clipboard_teardown :: proc(term: ^core.Terminal_State) {
    queue := term.clipboard_actions
    if queue.acceptance_count == 0 && queue.rejection_count == 0 {
        return
    }
    log.debugf(
        "terminal clipboard accepts=%d accepted_bytes=%d rejects=%d " +
        "rejected_bytes=%d stale_discards=%d stale_bytes=%d " +
        "publications=%d published_bytes=%d publication_rejects=%d",
        queue.acceptance_count, queue.accepted_byte_count,
        queue.rejection_count, queue.rejected_byte_count,
        queue.stale_discard_count, queue.stale_discard_byte_count,
        queue.publication_count, queue.published_byte_count,
        queue.publication_rejection_count)
}

//   Return whether this frame requests terminal clipboard paste.
//
// Parameters:
//   - frame: Polled input frame containing physical key events and modifiers.
//
// Returns:
//   - True when the frame contains a Ctrl+Shift+V press chord.
terminal_clipboard_paste_requested :: proc(frame: input.Input_Frame) -> bool {
    return input.input_chord_pressed(frame, .V, {.Control, .Shift})
}

//   Insert clipboard text at the live input cursor.
//
// Parameters:
//   - term: Terminal state owning the editable history buffer.
//   - text: Clipboard bytes to insert without interpretation.
//
// Returns:
//   - True when nonempty text is accepted by termhist; false otherwise.
//
// Side effects:
//   - Inserts text into the live editable input and advances its cursor.
terminal_insert_clipboard_text :: proc(
    term: ^core.Terminal_State, text: string) -> bool {
    if len(text) == 0 {
        return false
    }
    return termhist.termhist_insert_text(term.history, text)
}

//   Return whether this frame requests terminal clipboard copy.
//
// Notes:
//   - Shift distinguishes Ctrl+Shift+C from the foreground-session Ctrl+C interrupt.
//
// Parameters:
//   - frame: Polled input frame containing physical key events and modifiers.
//
// Returns:
//   - True when the frame contains a Ctrl+Shift+C press chord.
terminal_clipboard_copy_requested :: proc(frame: input.Input_Frame) -> bool {
    return input.input_chord_pressed(frame, .C, {.Control, .Shift})
}

// Extract the active view selection as plain text for clipboard publication.
terminal_view_selection_text :: proc(term: ^core.Terminal_State) -> string {
    if term == nil || !term.view_selection_active { return "" }
    start, end := terminal_selection_ordered(
        term.view_selection_anchor, term.view_selection_head)
    line_count := terminal_line_count(term)
    total_lines := math.max(line_count, end.line) + 1
    lines := make([]string, total_lines, context.temp_allocator)
    for line in 0..<total_lines {
        lines[line] = terminal_line_text(term, line)
    }
    return terminal_compose_selection_text(lines, start, end)
}

//   Copy the active view selection's plain text on Ctrl+Shift+C.
//
// Parameters:
//   - term: The terminal state field owned by the caller.
//   - frame: This frame's polled keyboard state.
//
// Side effects:
//   - Writes to the system clipboard via the input package; leaves the selection active.
terminal_update_clipboard_copy :: proc(
    term: ^core.Terminal_State, frame: input.Input_Frame) {
    if !term.view_selection_active {
        return
    }

    if !terminal_clipboard_copy_requested(frame) {
        return
    }

    input.input_set_clipboard_text(terminal_view_selection_text(term))
}

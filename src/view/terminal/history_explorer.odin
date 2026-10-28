package terminalview

import viewterminalmodel "model"
import historyruntime "../../terminal/history/runtime"
import termhist "../../terminal/history"
import termhiststore "../../terminal/history/store"
import protocol "../../core/protocol"
import input "../input"
import mem "core:mem"
import utf8 "core:unicode/utf8"

HISTORY_EXPLORER_INITIAL_QUERY_CAPACITY :: termhiststore.HISTORY_SEARCH_QUERY_MAX_BYTES
HISTORY_EXPLORER_PAGE_CAPACITY :: historyruntime.HISTORY_RUNTIME_SEARCH_ROW_CAPACITY
HISTORY_EXPLORER_SUMMARY_CAPACITY :: historyruntime.HISTORY_RUNTIME_SEARCH_SUMMARY_BYTES
HISTORY_EXPLORER_PREVIEW_CAPACITY :: protocol.TERMINAL_RETAINED_TEXT_MAX_BYTES

History_Explorer_Query_Key_Effect :: struct {
    moved: bool,
    edited: bool,
    handled: bool,
}

// Allocate a complete bounded explorer owner before publishing it to Terminal state.
history_explorer_init :: proc(
    explorer: ^viewterminalmodel.History_Explorer_State,
    allocator: mem.Allocator) -> bool {
    if explorer == nil || allocator.procedure == nil || explorer^.initialized {
        return false
    }
    if !termhist.termhist_init_with_allocator(
        &explorer^.query_editor, HISTORY_EXPLORER_INITIAL_QUERY_CAPACITY, allocator) {
        termhist.termhist_destroy(&explorer^.query_editor)
        return false
    }
    if !history_explorer_allocate_buffers(explorer, allocator) {
        termhist.termhist_destroy(&explorer^.query_editor)
        return false
    }
    explorer^.status = .Closed
    explorer^.preview_status = .Idle
    explorer^.initialized = true
    return true
}

// Allocate and publish explorer buffers transactionally.
history_explorer_allocate_buffers :: proc(
    explorer: ^viewterminalmodel.History_Explorer_State,
    allocator: mem.Allocator) -> bool {
    rows, rows_error := make(
        []termhiststore.History_Candidate_Summary,
        HISTORY_EXPLORER_PAGE_CAPACITY, allocator)
    summaries, summaries_error := make(
        []u8, HISTORY_EXPLORER_SUMMARY_CAPACITY, allocator)
    preview, preview_error := make(
        []u8, HISTORY_EXPLORER_PREVIEW_CAPACITY, allocator)
    if rows_error != nil || summaries_error != nil || preview_error != nil {
        if preview_error == nil {
            delete(preview, allocator)
        }
        if summaries_error == nil {
            delete(summaries, allocator)
        }
        if rows_error == nil {
            delete(rows, allocator)
        }
        return false
    }
    explorer^.rows = rows
    explorer^.summaries = summaries
    explorer^.preview_source = preview
    return true
}

// Release every transient explorer owner before its Terminal generation allocator retires.
history_explorer_destroy :: proc(
    explorer: ^viewterminalmodel.History_Explorer_State,
    allocator: mem.Allocator) {
    if explorer == nil || !explorer^.initialized {
        return
    }
    termhist.termhist_destroy(&explorer^.query_editor)
    delete(explorer^.rows, allocator)
    delete(explorer^.summaries, allocator)
    delete(explorer^.preview_source, allocator)
    explorer^ = {}
}

// Open only a ready non-continuation Terminal with no active input or composition owner.
history_explorer_open :: proc(term: ^viewterminalmodel.Terminal_State) -> bool {
    if term == nil || !term^.initialized || !term^.history_explorer.initialized ||
       !term^.history_explorer_open_allowed || term^.awaiting_eval ||
       !term^.banner_ready || term^.collecting_continuation ||
       term^.interactive_input_request_id != 0 || term^.history == nil ||
       term^.history.preedit_active {
        return false
    }
    explorer := &term^.history_explorer
    termhist.termhist_clear(&explorer^.query_editor)
    history_explorer_reset_for_open(explorer)
    explorer^.opening_generation += 1
    if explorer^.opening_generation == 0 {
        explorer^.opening_generation = 1
    }
    explorer^.query_generation = 1
    terminal_clear_completion(term)
    history_explorer_retire_navigation_requests(term)
    term^.view_selection_dragging = false
    term^.draft_selection_dragging = false
    return true
}

// Reset bounded transient data and activate a fresh empty query session.
history_explorer_reset_for_open :: proc(
    explorer: ^viewterminalmodel.History_Explorer_State) {
    explorer^.identity = {}
    explorer^.active = true
    explorer^.close_requested = false
    explorer^.accept_requested = false
    explorer^.query_dirty = true
    explorer^.search_pending = false
    explorer^.preview_pending = false
    explorer^.search_request_id = 0
    explorer^.preview_request_id = 0
    explorer^.row_count = 0
    explorer^.selected_index = -1
    explorer^.preview_length = 0
    explorer^.preview_record = {}
    explorer^.scan_direction = .Older
    explorer^.scan_cursor = {}
    explorer^.scan_cursor_valid = false
    explorer^.page_older_cursor = {}
    explorer^.page_older_cursor_valid = false
    explorer^.page_newer_cursor = {}
    explorer^.page_newer_cursor_valid = false
    explorer^.older_available = true
    explorer^.newer_available = false
    explorer^.page_request = .None
    explorer^.list_scroll_rows = 0
    explorer^.list_visible_selection = -1
    explorer^.query_pointer_selecting = false
    explorer^.preview_scroll_lines = 0
    explorer^.status_failure = {}
    explorer^.status = .Searching
    explorer^.preview_status = .Idle
    termhist.termhist_reset_undo(&explorer^.query_editor)
}

// Close transient state without changing the ordinary draft or its undo timeline.
history_explorer_close :: proc(term: ^viewterminalmodel.Terminal_State) {
    if term == nil || !term^.history_explorer.active {
        return
    }
    explorer := &term^.history_explorer
    explorer^.active = false
    explorer^.close_requested = true
    explorer^.accept_requested = false
    explorer^.status = .Closed
    explorer^.preview_status = .Idle
    explorer^.preview_length = 0
    explorer^.row_count = 0
    explorer^.identity = {}
    explorer^.search_request_id = 0
    explorer^.preview_request_id = 0
}

// Retire ordinary navigation replies without erasing a suspended history draft.
history_explorer_retire_navigation_requests :: proc(
    term: ^viewterminalmodel.Terminal_State) {
    term^.history_navigation_epoch += 1
    if term^.history_navigation_epoch == 0 {
        term^.history_navigation_epoch = 1
    }
    term^.history_navigation_intent_count = 0
    term^.history_navigation_pending_id = 0
    term^.history_navigation_admission_reported = false
}

// Start a new query identity and discard candidates from the prior literal query.
history_explorer_query_changed :: proc(
    explorer: ^viewterminalmodel.History_Explorer_State) {
    if explorer == nil || !explorer^.active {
        return
    }
    termhist.termhist_reset_undo(&explorer^.query_editor)
    explorer^.query_generation += 1
    if explorer^.query_generation == 0 {
        explorer^.query_generation = 1
    }
    explorer^.identity = {}
    explorer^.query_dirty = true
    explorer^.accept_requested = false
    explorer^.search_pending = false
    explorer^.preview_pending = false
    explorer^.search_request_id = 0
    explorer^.preview_request_id = 0
    explorer^.row_count = 0
    explorer^.selected_index = -1
    explorer^.preview_length = 0
    explorer^.preview_record = {}
    explorer^.scan_direction = .Older
    explorer^.scan_cursor = {}
    explorer^.scan_cursor_valid = false
    explorer^.page_older_cursor = {}
    explorer^.page_older_cursor_valid = false
    explorer^.page_newer_cursor = {}
    explorer^.page_newer_cursor_valid = false
    explorer^.older_available = true
    explorer^.newer_available = false
    explorer^.page_request = .None
    explorer^.status_failure = {}
    explorer^.status = .Searching
    explorer^.preview_status = .Idle
}

// Select one current candidate by its stable page position without fetching its source.
history_explorer_select_candidate :: proc(
    explorer: ^viewterminalmodel.History_Explorer_State, index: int) -> bool {
    if explorer == nil || !explorer^.active || index < 0 ||
       index >= explorer^.row_count || explorer^.selected_index == index {
        return false
    }
    explorer^.selected_index = index
    explorer^.accept_requested = false
    explorer^.preview_pending = true
    explorer^.preview_request_id = 0
    explorer^.preview_length = 0
    explorer^.preview_record = {}
    explorer^.preview_status = .Loading
    explorer^.preview_scroll_lines = 0
    return true
}

// Request an adjacent bounded page in chronology without accumulating history.
history_explorer_request_page :: proc(
    explorer: ^viewterminalmodel.History_Explorer_State,
    direction: viewterminalmodel.History_Explorer_Page_Direction) -> bool {
    if explorer == nil || !explorer^.active || explorer^.row_count == 0 ||
       explorer^.search_pending || explorer^.page_request != .None {
        return false
    }
    if direction == .Older && !explorer^.older_available ||
       direction == .Newer && !explorer^.newer_available {
        return false
    }
    cursor_valid := explorer^.page_older_cursor_valid if direction == .Older else
        explorer^.page_newer_cursor_valid
    if !cursor_valid {
        return false
    }
    explorer^.page_request = direction
    explorer^.accept_requested = false
    explorer^.search_request_id = 0
    explorer^.scan_direction = direction
    explorer^.scan_cursor_valid = true
    explorer^.scan_cursor = explorer^.page_older_cursor if direction == .Older else
        explorer^.page_newer_cursor
    explorer^.search_pending = false
    explorer^.status = .Searching
    return true
}

// Select the stable cursor associated with one scope-qualified history record.
history_explorer_record_cursor :: proc(
    record: termhiststore.History_Record) -> termhiststore.History_Browse_Cursor {
    return {
        submitted_at_unix_ms = record.submitted_at_unix_ms,
        scope = record.scope,
        source_id = record.source_id,
    }
}

// Publish one joined search result, preserving progress across empty scan windows.
history_explorer_publish_search :: proc(
    explorer: ^viewterminalmodel.History_Explorer_State,
    completion: historyruntime.History_Search_Completion) {
    if explorer == nil || !explorer^.active ||
       completion.request.identity != explorer^.identity ||
       completion.request.request_id != explorer^.search_request_id {
        return
    }
    explorer^.search_pending = false
    explorer^.search_request_id = 0
    result := completion.result
    if result.outcome != .Scanned {
        explorer^.status_failure = result.failure
        explorer^.status = .Capacity if result.failure.kind == .Capacity else .Failed
        explorer^.page_request = .None
        return
    }
    if result.row_count > 0 {
        history_explorer_publish_search_rows(explorer, result)
        return
    }
    history_explorer_publish_empty_window(explorer, result)
}

// Publish one complete page and select its nearest candidate to the prior page.
history_explorer_publish_search_rows :: proc(
    explorer: ^viewterminalmodel.History_Explorer_State,
    result: termhiststore.History_Search_Result) {
    initial_page := !explorer^.page_older_cursor_valid &&
        !explorer^.page_newer_cursor_valid
    explorer^.row_count = result.row_count
    explorer^.list_visible_selection = -1
    explorer^.preview_scroll_lines = 0
    if explorer^.scan_direction == .Older {
        history_explorer_reverse_rows(explorer)
        explorer^.selected_index = explorer^.row_count - 1
    } else {
        explorer^.selected_index = 0
    }
    explorer^.preview_pending = true
    explorer^.preview_request_id = 0
    explorer^.preview_status = .Loading
    explorer^.preview_length = 0
    explorer^.preview_record = {}
    explorer^.status = .Ready
    explorer^.scan_cursor = result.cursor
    explorer^.scan_cursor_valid = result.cursor_valid
    history_explorer_update_page_cursors(explorer, result, initial_page)
    explorer^.page_request = .None
}

// Retain the independent boundaries for adjacent older and newer page requests.
history_explorer_update_page_cursors :: proc(
    explorer: ^viewterminalmodel.History_Explorer_State,
    result: termhiststore.History_Search_Result, initial_page: bool) {
    if explorer^.scan_direction == .Older {
        explorer^.page_older_cursor = result.cursor
        explorer^.page_older_cursor_valid = result.cursor_valid
        explorer^.page_newer_cursor =
            history_explorer_record_cursor(explorer^.rows[explorer^.row_count - 1].record)
        explorer^.page_newer_cursor_valid = true
        explorer^.older_available = !result.exhausted || result.output_full
        explorer^.newer_available = !initial_page
    } else {
        explorer^.page_newer_cursor = result.cursor
        explorer^.page_newer_cursor_valid = result.cursor_valid
        explorer^.page_older_cursor =
            history_explorer_record_cursor(explorer^.rows[0].record)
        explorer^.page_older_cursor_valid = true
        explorer^.newer_available = !result.exhausted || result.output_full
        explorer^.older_available = true
    }
}

// Preserve cursor progress through empty windows until the directional scan ends.
history_explorer_publish_empty_window :: proc(
    explorer: ^viewterminalmodel.History_Explorer_State,
    result: termhiststore.History_Search_Result) {
    explorer^.scan_cursor = result.cursor
    explorer^.scan_cursor_valid = result.cursor_valid
    if !result.exhausted {
        explorer^.status = .Searching
        return
    }
    if explorer^.scan_direction == .Older {
        explorer^.older_available = false
    } else {
        explorer^.newer_available = false
    }
    explorer^.page_request = .None
    explorer^.status = .Empty if explorer^.row_count == 0 else .Ready
}

// Reverse row descriptors so candidate lists always read oldest-to-newest.
history_explorer_reverse_rows :: proc(
    explorer: ^viewterminalmodel.History_Explorer_State) {
    for index in 0..<explorer^.row_count / 2 {
        opposite := explorer^.row_count - index - 1
        row := explorer^.rows[index]
        explorer^.rows[index] = explorer^.rows[opposite]
        explorer^.rows[opposite] = row
    }
}

// Publish a complete exact-source result only for the currently selected identity.
history_explorer_publish_preview :: proc(
    explorer: ^viewterminalmodel.History_Explorer_State,
    completion: historyruntime.History_Preview_Completion) {
    if explorer == nil || !explorer^.active ||
       completion.request.identity != explorer^.identity ||
       completion.request.request_id != explorer^.preview_request_id ||
       explorer^.selected_index < 0 ||
       explorer^.selected_index >= explorer^.row_count {
        return
    }
    explorer^.preview_request_id = 0
    row := explorer^.rows[explorer^.selected_index]
    record := completion.result.record
    request := completion.request
    if completion.result.outcome != .Found ||
       request.scope != row.record.scope || request.source_id != row.record.source_id ||
       request.source_revision != row.record.source_revision ||
       record.scope != row.record.scope || record.source_id != row.record.source_id ||
       record.source_revision != row.record.source_revision {
        explorer^.preview_status = .Failed
        explorer^.status_failure = completion.result.failure
        return
    }
    explorer^.preview_record = record
    explorer^.preview_length = completion.result.source_length
    explorer^.preview_status = .Ready
}

// Accept the current preview into the ordinary editor without executing it.
history_explorer_accept :: proc(
    term: ^viewterminalmodel.Terminal_State,
    identity: historyruntime.History_Explorer_Identity) -> bool {
    if !history_explorer_accept_is_ready(term, identity) {
        return false
    }
    explorer := &term^.history_explorer
    row := explorer^.rows[explorer^.selected_index]
    record := explorer^.preview_record
    if !history_explorer_preview_matches(explorer, row.record) {
        return false
    }
    if !termhist.termhist_load_entry(
        term^.history, explorer^.preview_source[:explorer^.preview_length]) {
        explorer^.status = .Capacity
        explorer^.status_failure.kind = .Capacity
        return false
    }
    term^.input_mode = record.mode
    term^.collecting_continuation = false
    term^.pending_draft_valid = false
    terminal_clear_completion(term)
    terminal_history_navigation_invalidate(term)
    history_explorer_close(term)
    return true
}

// Revalidate Terminal readiness and the selected preview before any prompt mutation.
history_explorer_accept_is_ready :: proc(
    term: ^viewterminalmodel.Terminal_State,
    identity: historyruntime.History_Explorer_Identity) -> bool {
    return term != nil && term^.history_explorer.active &&
        term^.history_explorer.accept_requested &&
        term^.history_explorer.identity == identity && !term^.awaiting_eval &&
        term^.banner_ready && !term^.collecting_continuation &&
        term^.interactive_input_request_id == 0 && term^.history != nil &&
        !term^.history.preedit_active &&
        term^.history_explorer.preview_status == .Ready &&
        term^.history_explorer.selected_index >= 0 &&
        term^.history_explorer.selected_index < term^.history_explorer.row_count
}

// Require the preview's scope, ID, revision, and complete byte range to match its row.
history_explorer_preview_matches :: proc(
    explorer: ^viewterminalmodel.History_Explorer_State,
    row: termhiststore.History_Record) -> bool {
    record := explorer^.preview_record
    return explorer^.preview_length >= 0 &&
        explorer^.preview_length <= len(explorer^.preview_source) &&
        record.scope == row.scope && record.source_id == row.source_id &&
        record.source_revision == row.source_revision
}

// Insert a bounded valid UTF-8 string into the single-line literal query.
history_explorer_insert_query :: proc(
    explorer: ^viewterminalmodel.History_Explorer_State, text: string) -> bool {
    if explorer == nil || !explorer^.active || !utf8.valid_string(text) {
        return false
    }
    start, end := termhist.termhist_selection_range(&explorer^.query_editor)
    next_length := explorer^.query_editor.text_len - (end - start) + len(text)
    if next_length > termhiststore.HISTORY_SEARCH_QUERY_MAX_BYTES {
        explorer^.status = .Capacity
        explorer^.status_failure.kind = .Capacity
        return false
    }
    changed := termhist.termhist_insert_text(&explorer^.query_editor, text)
    if changed {
        history_explorer_query_changed(explorer)
    }
    return changed
}

// Commit IME text within the query bound and preserve termhist replacement semantics.
history_explorer_commit_query :: proc(
    explorer: ^viewterminalmodel.History_Explorer_State, text: string) -> bool {
    if explorer == nil || !explorer^.active || !utf8.valid_string(text) {
        return false
    }
    start := explorer^.query_editor.cursor
    end := explorer^.query_editor.anchor
    if explorer^.query_editor.preedit_active {
        start = explorer^.query_editor.preedit_replace_cursor
        end = explorer^.query_editor.preedit_replace_anchor
    }
    next_length := explorer^.query_editor.text_len -
        (max(start, end) - min(start, end)) + len(text)
    if next_length > termhiststore.HISTORY_SEARCH_QUERY_MAX_BYTES {
        explorer^.status = .Capacity
        explorer^.status_failure.kind = .Capacity
        return false
    }
    changed := termhist.termhist_commit_text(&explorer^.query_editor, text)
    if changed {
        history_explorer_query_changed(explorer)
    }
    return changed
}

// Replace CR, LF, and CRLF with one space while copying a bounded paste payload.
history_explorer_normalize_paste :: proc(
    source: string, destination: []u8) -> (string, bool) {
    if !utf8.valid_string(source) || len(source) > len(destination) {
        return "", false
    }
    output := 0
    for index := 0; index < len(source); index += 1 {
        if source[index] == '\r' {
            destination[output] = ' '
            output += 1
            if index + 1 < len(source) && source[index + 1] == '\n' {
                index += 1
            }
        } else if source[index] == '\n' {
            destination[output] = ' '
            output += 1
        } else {
            destination[output] = source[index]
            output += 1
        }
    }
    return string(destination[:output]), true
}

// Apply query editing, navigation, preview selection, and close commands.
history_explorer_update_event :: proc(
    term: ^viewterminalmodel.Terminal_State,
    event: input.Input_Event, clipboard_text: string) -> Terminal_Keyboard_Update {
    explorer := &term^.history_explorer
    if event.text_target.kind != .None &&
       event.text_target.kind != .Terminal {
        return {}
    }
    composing := explorer^.query_editor.preedit_active
    if input.input_event_composition_owns_key(event, &composing) {
        return {}
    }
    if event.kind == .Text || event.kind == .Text_Commit ||
       event.kind == .Text_Preedit || event.kind == .Text_Cancel {
        return history_explorer_update_text_event(explorer, event)
    }
    if event.kind != .Press && event.kind != .Repeat {
        return {}
    }
    return history_explorer_update_key(term, event, clipboard_text)
}

// Keep committed text and IME lifecycle inside the single-line query editor.
history_explorer_update_text_event :: proc(
    explorer: ^viewterminalmodel.History_Explorer_State,
    event: input.Input_Event) -> Terminal_Keyboard_Update {
    if event.kind == .Text_Preedit {
        return history_explorer_update_preedit(explorer, event)
    }
    if event.kind == .Text_Cancel {
        termhist.termhist_clear_preedit(&explorer^.query_editor)
        return {}
    }
    if event.kind == .Text_Commit {
        return history_explorer_commit_text_event(explorer, event)
    }
    return history_explorer_insert_text_event(explorer, event)
}

// Retain a newline-normalized bounded IME preview without touching ordinary input.
history_explorer_update_preedit :: proc(
    explorer: ^viewterminalmodel.History_Explorer_State,
    event: input.Input_Event) -> Terminal_Keyboard_Update {
    if int(event.text_length) > len(event.text) {
        return {}
    }
    payload := event
    buffer: [input.INPUT_TEXT_EVENT_CAPACITY]u8
    normalized, valid := history_explorer_normalize_paste(
        input.input_event_text_payload(&payload), buffer[:])
    if valid {
        _ = termhist.termhist_update_preedit(
            &explorer^.query_editor, normalized,
            event.preedit_start, event.preedit_length)
    }
    return {}
}

// Commit bounded IME text with termhist's replace-range semantics.
history_explorer_commit_text_event :: proc(
    explorer: ^viewterminalmodel.History_Explorer_State,
    event: input.Input_Event) -> Terminal_Keyboard_Update {
    if int(event.text_length) > len(event.text) {
        return {}
    }
    payload := event
    buffer: [input.INPUT_TEXT_EVENT_CAPACITY]u8
    normalized, valid := history_explorer_normalize_paste(
        input.input_event_text_payload(&payload), buffer[:])
    if valid {
        _ = history_explorer_commit_query(explorer, normalized)
    }
    return history_explorer_keyboard_effect(valid)
}

// Insert a committed Unicode scalar, normalizing physical line breaks to spaces.
history_explorer_insert_text_event :: proc(
    explorer: ^viewterminalmodel.History_Explorer_State,
    event: input.Input_Event) -> Terminal_Keyboard_Update {
    codepoint := ' ' if event.codepoint == '\n' || event.codepoint == '\r' else
        event.codepoint
    buffer, length := utf8.encode_rune(codepoint)
    changed := history_explorer_insert_query(explorer, string(buffer[:length]))
    return history_explorer_keyboard_effect(changed)
}

// Build one keyboard update without exposing explorer internals to the caller.
history_explorer_keyboard_effect :: proc(cursor_moved: bool) -> Terminal_Keyboard_Update {
    return {
        cursor_moved = cursor_moved,
    }
}

// Consume one explorer command so no key can leak into the hidden prompt or child.
history_explorer_update_key :: proc(
    term: ^viewterminalmodel.Terminal_State,
    event: input.Input_Event, clipboard_text: string) -> Terminal_Keyboard_Update {
    explorer := &term^.history_explorer
    if update, handled := history_explorer_handle_close_key(term, event); handled {
        return update
    }
    if update, handled := history_explorer_handle_paste_key(
        explorer, event, clipboard_text); handled {
        return update
    }
    if update, handled := history_explorer_handle_candidate_key(
        explorer, event); handled {
        return update
    }
    if update, handled := history_explorer_handle_page_key(explorer, event); handled {
        return update
    }
    return history_explorer_edit_query(explorer, event)
}

// Handle close, copy, accept, save-suppression, and focus traversal commands.
history_explorer_handle_close_key :: proc(
    term: ^viewterminalmodel.Terminal_State,
    event: input.Input_Event) -> (Terminal_Keyboard_Update, bool) {
    explorer := &term^.history_explorer
    if history_explorer_copy_chord(event) {
        if start, end := termhist.termhist_selection_range(&explorer^.query_editor);
            start != end {
            _ = input.input_set_clipboard_text(
                string(explorer^.query_editor.text[start:end]))
        }
        return {}, true
    }
    if event.key == .Escape ||
       event.modifiers == {.Control} &&
            (event.key == .C || event.key == .G || event.key == .D) {
        termhist.termhist_clear_preedit(&explorer^.query_editor)
        history_explorer_close(term)
        return history_explorer_keyboard_effect(true), true
    }
    if event.key == .Enter || event.key == .Keypad_Enter {
        if explorer^.row_count > 0 && explorer^.selected_index >= 0 &&
           explorer^.selected_index < explorer^.row_count {
            explorer^.accept_requested = true
        }
        return history_explorer_keyboard_effect(explorer^.accept_requested), true
    }
    return {}, event.key == .Tab ||
        event.modifiers == {.Control} && event.key == .S
}

// Recognize the existing explicit clipboard-copy chord for query selection.
history_explorer_copy_chord :: proc(event: input.Input_Event) -> bool {
    return (event.modifiers == {.Control, .Shift} ||
        event.modifiers == {.Super, .Shift}) && event.key == .C
}

// Normalize and insert one supported clipboard paste without partial admission.
history_explorer_handle_paste_key :: proc(
    explorer: ^viewterminalmodel.History_Explorer_State,
    event: input.Input_Event, clipboard_text: string) ->
        (Terminal_Keyboard_Update, bool) {
    chord := event.key == .V &&
        (event.modifiers == {.Control, .Shift} ||
         event.modifiers == {.Super, .Shift})
    if !chord {
        return {}, false
    }
    buffer: [termhiststore.HISTORY_SEARCH_QUERY_MAX_BYTES]u8
    normalized, valid := history_explorer_normalize_paste(clipboard_text, buffer[:])
    if !valid {
        explorer^.status = .Capacity
        explorer^.status_failure.kind = .Capacity
        return {}, true
    }
    return history_explorer_keyboard_effect(
        history_explorer_insert_query(explorer, normalized)), true
}

// Route Up/Down and Ctrl+P/N to candidate selection only.
history_explorer_handle_candidate_key :: proc(
    explorer: ^viewterminalmodel.History_Explorer_State,
    event: input.Input_Event) -> (Terminal_Keyboard_Update, bool) {
    if event.key == .Up && event.modifiers == {} ||
       event.key == .P && event.modifiers == {.Control} {
        return history_explorer_keyboard_effect(
            history_explorer_move_selection(explorer, -1)), true
    }
    if event.key == .Down && event.modifiers == {} ||
       event.key == .N && event.modifiers == {.Control} {
        return history_explorer_keyboard_effect(
            history_explorer_move_selection(explorer, 1)), true
    }
    return {}, false
}

// Route page, preview-scroll, and oldest/newest bindings without changing the query.
history_explorer_handle_page_key :: proc(
    explorer: ^viewterminalmodel.History_Explorer_State,
    event: input.Input_Event) -> (Terminal_Keyboard_Update, bool) {
    if event.modifiers == {.Alt} &&
       (event.key == .Page_Up || event.key == .Page_Down) {
        delta := -1 if event.key == .Page_Up else 1
        explorer^.preview_scroll_lines = max(0, explorer^.preview_scroll_lines + delta)
        return history_explorer_keyboard_effect(true), true
    }
    if event.key == .Page_Up && event.modifiers == {} ||
       event.key == .V && event.modifiers == {.Alt} {
        return history_explorer_keyboard_effect(
            history_explorer_request_page(explorer, .Older)), true
    }
    if event.key == .Page_Down && event.modifiers == {} ||
       event.key == .V && event.modifiers == {.Control} {
        return history_explorer_keyboard_effect(
            history_explorer_request_page(explorer, .Newer)), true
    }
    if event.modifiers == {.Alt, .Shift} && event.key == .Comma {
        history_explorer_request_edge(explorer, .Newer)
        return history_explorer_keyboard_effect(true), true
    }
    if event.modifiers == {.Alt, .Shift} && event.key == .Period {
        history_explorer_request_edge(explorer, .Older)
        return history_explorer_keyboard_effect(true), true
    }
    return {}, false
}

// Move the candidate selection and request an adjacent page at a loaded boundary.
history_explorer_move_selection :: proc(
    explorer: ^viewterminalmodel.History_Explorer_State, direction: int) -> bool {
    if explorer^.row_count == 0 || explorer^.selected_index < 0 {
        return false
    }
    next := explorer^.selected_index + direction
    if next < 0 {
        return history_explorer_request_page(explorer, .Older)
    }
    if next >= explorer^.row_count {
        return history_explorer_request_page(explorer, .Newer)
    }
    return history_explorer_select_candidate(explorer, next)
}

// Restart a query scan from the oldest or newest eligible end.
history_explorer_request_edge :: proc(
    explorer: ^viewterminalmodel.History_Explorer_State,
    direction: viewterminalmodel.History_Explorer_Page_Direction) {
    if explorer == nil || !explorer^.active {
        return
    }
    explorer^.row_count = 0
    explorer^.selected_index = -1
    explorer^.preview_length = 0
    explorer^.preview_record = {}
    explorer^.preview_pending = false
    explorer^.accept_requested = false
    explorer^.preview_request_id = 0
    explorer^.preview_status = .Idle
    explorer^.scan_direction = direction
    explorer^.scan_cursor = {}
    explorer^.scan_cursor_valid = false
    explorer^.page_older_cursor = {}
    explorer^.page_older_cursor_valid = false
    explorer^.page_newer_cursor = {}
    explorer^.page_newer_cursor_valid = false
    explorer^.page_request = direction
    explorer^.search_pending = false
    explorer^.search_request_id = 0
    explorer^.status_failure = {}
    explorer^.status = .Searching
    explorer^.older_available = direction == .Older
    explorer^.newer_available = direction == .Newer
}

// Apply grapheme-safe query edits and reset search only after accepted mutations.
history_explorer_edit_query :: proc(
    explorer: ^viewterminalmodel.History_Explorer_State,
    event: input.Input_Event) -> Terminal_Keyboard_Update {
    effect := history_explorer_apply_query_key(&explorer^.query_editor, event)
    if effect.edited {
        history_explorer_query_changed(explorer)
    }
    if !effect.handled {
        return {}
    }
    return history_explorer_keyboard_effect(effect.moved || effect.edited)
}

// Apply one grapheme-aware query navigation or deletion key.
history_explorer_apply_query_key :: proc(
    query: ^termhist.Termhist_State,
    event: input.Input_Event) -> History_Explorer_Query_Key_Effect {
    shift := .Shift in event.modifiers
    control := .Control in event.modifiers
    effect: History_Explorer_Query_Key_Effect = {
        handled = true,
    }
    #partial switch event.key {
    case .Backspace:
        effect.edited = termhist.termhist_delete_word(query, true) if control else
            termhist.termhist_backspace(query)
    case .Delete:
        effect.edited = termhist.termhist_delete_word(query, false) if control else
            termhist.termhist_delete_forward(query)
    case .Left:
        effect.moved = termhist.termhist_move_word(query, true, shift) if control else
            termhist.termhist_move_left(query, shift)
    case .Right:
        effect.moved = termhist.termhist_move_word(query, false, shift) if control else
            termhist.termhist_move_right(query, shift)
    case .Home:
        effect.moved = termhist.termhist_move_buffer_home(query, shift)
    case .End:
        effect.moved = termhist.termhist_move_buffer_end(query, shift)
    case .A:
        if control {
            effect.moved = query^.anchor != 0 || query^.cursor != query^.text_len
            query^.anchor = 0
            query^.cursor = query^.text_len
            query^.preferred_column = -1
        } else {
            effect.handled = false
        }
    }
    return effect
}

package terminalview

import protocol "../../core/protocol"
import termhist "../../terminal/history"
import model "model"
import "core:log"
import "core:mem"
import "core:unicode/utf8"

// Allocate the fixed cache once in the Terminal generation, never on an edit or frame.
terminal_highlight_init :: proc(
    term: ^model.Terminal_State, allocator: mem.Allocator) -> bool {
    storage, err := new(model.Terminal_Highlighting, allocator)
    if err != nil {
        return false
    }
    storage.face_generation = 1
    term.highlighting = storage
    return true
}

// Release storage before the enclosing generation allocator is reset.
terminal_highlight_destroy :: proc(
    term: ^model.Terminal_State, allocator: mem.Allocator) {
    if term.highlighting == nil {
        return
    }
    h := term.highlighting
    log.debugf("terminal highlights rejected=%d stale=%d failed=%d evicted=%d",
        h.rejected_count, h.stale_count, h.failure_count, h.eviction_count)
    free(h, allocator)
    term.highlighting = nil
}

// Invalidate decorative state without forgetting already-sent requests awaiting return.
terminal_highlight_invalidate :: proc(term: ^model.Terminal_State) {
    h := term.highlighting
    if h == nil {
        return
    }
    h.live.phase = .Empty
    terminal_highlight_clear_presentation(term)
    for &slot in h.cache {
        slot.phase = .Empty
    }
    h.observed_editable = false
}

// Install an owner-supplied face token; this is not a faces.toml filesystem watcher.
terminal_highlight_set_face_generation :: proc(
    term: ^model.Terminal_State, generation: u64) -> bool {
    if term == nil || term.highlighting == nil || generation == 0 {
        return false
    }
    if term.highlighting.face_generation != generation {
        term.highlighting.face_generation = generation
        terminal_highlight_invalidate(term)
    }
    return true
}

// Build a reusable exact-source slot; invalid source stays plain until the next mutation.
terminal_highlight_schedule :: proc(
    term: ^model.Terminal_State, slot: ^model.Terminal_Highlight_Slot,
    source: string, identity: protocol.Highlight_Identity, due: f64) {
    slot.phase = .Failed
    if len(source) > len(slot.source) || !utf8.valid_string(source) {
        term.highlighting.rejected_count += 1
        log.warn("terminal highlight source exceeds capacity or is invalid UTF-8")
        return
    }
    copy(slot.source[:], transmute([]u8)source)
    slot.source_length = len(source)
    slot.run_count = 0
    slot.identity = identity
    slot.due = due
    slot.phase = .Scheduled
}

// Observe actual text revision and mode, including paste, recall, completion, and continuations.
terminal_highlight_observe_live :: proc(term: ^model.Terminal_State, now: f64) {
    h := term.highlighting
    if h == nil || term.history == nil {
        return
    }
    revision := termhist.termhist_content_revision(term.history) + 1
    reset_revision := termhist.termhist_reset_revision(term.history)
    editable := terminal_prompt_visible(term) && term.input_mode == .Normal
    if h.observed_revision == revision && h.observed_mode == term.input_mode &&
        h.observed_editable == editable && h.observed_reset_revision == reset_revision &&
        h.observed_animation_generation == term.animation_generation {
        return
    }
    h.live.phase = .Empty
    h.observed_revision = revision
    h.observed_reset_revision = reset_revision
    h.observed_animation_generation = term.animation_generation
    h.observed_mode = term.input_mode
    h.observed_editable = editable
    if !editable {
        terminal_highlight_clear_presentation(term)
        return
    }
    source := termhist.termhist_current_text(term.history)
    terminal_highlight_observe_presentation(term, source, revision, reset_revision)
    if len(source) == 0 {
        return
    }
    terminal_highlight_schedule(term, &h.live, source, {
        animation_generation = term.animation_generation,
        source_revision = revision, face_generation = h.face_generation,
        target_kind = .Live_Input,
    }, now + model.TERMINAL_HIGHLIGHT_DEBOUNCE_SECONDS)
}

// Check that a retained submission still names the same authoritative history source.
terminal_highlight_history_current :: proc(
    term: ^model.Terminal_State, entry: ^model.Terminal_Highlight_History) -> bool {
    if entry.id == 0 || term.history == nil ||
        entry.history_index < 0 || entry.history_index >= term.history.history_len {
        return false
    }
    source := &term.history.history[entry.history_index]
    return source.tag == TERMINAL_HISTORY_TAG_NORMAL && source.id == entry.id
}

// Resolve one retained submission by its monotonic display identity.
terminal_highlight_history_find :: proc(
    term: ^model.Terminal_State, id: u64) -> ^model.Terminal_Highlight_History {
    for &entry in term.highlighting.history {
        if entry.id == id && terminal_highlight_history_current(term, &entry) {
            return &entry
        }
    }
    return nil
}

// Reject stale slots even between mutation and the next scheduling frame.
terminal_highlight_slot_current :: proc(
    term: ^model.Terminal_State, slot: ^model.Terminal_Highlight_Slot) -> bool {
    id := slot.identity
    h := term.highlighting
    if id.animation_generation != term.animation_generation ||
        id.face_generation != h.face_generation ||
        (id.target_kind == .Live_Input && id.mode != i32(term.input_mode)) {
        return false
    }
    source := string(slot.source[:slot.source_length])
    if id.target_kind == .Live_Input {
        return terminal_prompt_visible(term) && term.input_mode == .Normal &&
            id.source_revision == termhist.termhist_content_revision(term.history) + 1 &&
            source == termhist.termhist_current_text(term.history)
    }
    entry := terminal_highlight_history_find(term, id.target_id)
    return entry != nil && id.source_revision == entry.id &&
        source == string(term.history.history[entry.history_index].text)
}

// Borrow current decoration independently of pending exact classification.
terminal_live_highlight_runs :: proc(
    term: ^model.Terminal_State) -> []protocol.Highlight_Run {
    if term == nil || term.highlighting == nil {
        return nil
    }
    if !terminal_highlight_presentation_current(term) {
        return nil
    }
    p := &term.highlighting.presentation
    return p.runs[:p.run_count]
}

// Select live work first, then visible historical work, with a fixed outstanding limit.
terminal_highlight_next_slot :: proc(
    term: ^model.Terminal_State, now: f64) -> ^model.Terminal_Highlight_Slot {
    h := term.highlighting
    if h.live.phase == .Scheduled && now >= h.live.due &&
        terminal_highlight_slot_current(term, &h.live) {
        return &h.live
    }
    for &slot in h.cache {
        if slot.phase == .Scheduled && slot.visible_epoch == h.epoch &&
            terminal_highlight_slot_current(term, &slot) {
            return &slot
        }
    }
    return nil
}

// Reserve one transaction and return a snapshot borrowed only until transport copies it.
terminal_highlight_take_request :: proc(
    term: ^model.Terminal_State, now: f64) -> (protocol.Highlight_Requested, bool) {
    if term == nil || term.highlighting == nil || !term.julia_session_ready {
        return {}, false
    }
    h := term.highlighting
    for &pending in h.pending {
        if pending.request_id != 0 {
            continue
        }
        slot := terminal_highlight_next_slot(term, now)
        if slot == nil {
            return {}, false
        }
        h.next_request_id += 1
        slot.identity.request_id = h.next_request_id
        pending = slot.identity
        slot.phase = .Pending
        return {slot.identity, string(slot.source[:slot.source_length])}, true
    }
    return {}, false
}

// Retire exactly the issued transaction; stale replies cannot release newer work.
terminal_highlight_retire :: proc(
    term: ^model.Terminal_State, id: protocol.Highlight_Identity) -> bool {
    for &pending in term.highlighting.pending {
        if pending == id && id.request_id != 0 {
            pending = {}
            return true
        }
    }
    return false
}

// Find the full correlated slot, never matching a result by source text alone.
terminal_highlight_pending_slot :: proc(
    term: ^model.Terminal_State,
    id: protocol.Highlight_Identity) -> ^model.Terminal_Highlight_Slot {
    h := term.highlighting
    if h.live.phase == .Pending && h.live.identity == id {
        return &h.live
    }
    for &slot in h.cache {
        if slot.phase == .Pending && slot.identity == id {
            return &slot
        }
    }
    return nil
}

// Copy a complete validated result before its producer-owned envelope is returned.
terminal_highlight_publish :: proc(
    term: ^model.Terminal_State, result: protocol.Highlight_Result) -> bool {
    if term == nil || term.highlighting == nil ||
        !terminal_highlight_retire(term, result.identity) {
        return false
    }
    h := term.highlighting
    slot := terminal_highlight_pending_slot(term, result.identity)
    if slot == nil || !terminal_highlight_slot_current(term, slot) {
        h.stale_count += 1
        return false
    }
    slot.phase = .Failed
    if result.source != string(slot.source[:slot.source_length]) ||
        !protocol.highlight_result_valid(result) {
        h.rejected_count += 1
        log.warn("terminal rejected malformed or source-mismatched highlight result")
        return false
    }
    copy(slot.runs[:], result.runs)
    slot.run_count = len(result.runs)
    slot.phase = .Ready
    if result.identity.target_kind == .Live_Input {
        terminal_highlight_publish_presentation(term, result)
    }
    return true
}

// Record explicit service or transport failure without retrying unchanged source each frame.
terminal_highlight_fail :: proc(
    term: ^model.Terminal_State, failure: protocol.Highlight_Failed) -> bool {
    if term == nil || term.highlighting == nil ||
        !terminal_highlight_retire(term, failure.identity) {
        return false
    }
    slot := terminal_highlight_pending_slot(term, failure.identity)
    if slot == nil || !terminal_highlight_slot_current(term, slot) {
        term.highlighting.stale_count += 1
        return false
    }
    slot.phase = .Failed
    term.highlighting.failure_count += 1
    log.warnf("terminal highlight request=%d failed reason=%d",
        failure.identity.request_id, failure.reason)
    return true
}

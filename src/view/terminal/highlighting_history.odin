package terminalview

import model "model"
import protocol "../../core/protocol"
import "core:log"
import "core:unicode/utf8"

Terminal_Highlight_Source_Request :: struct {
    submission_id: u64,
    source_revision: u64,
}

// Remove all output anchors and cached sources for one continued submission.
terminal_highlight_remove_submission :: proc(
    term: ^model.Terminal_State, id: u64) {
    if id == 0 || term.highlighting == nil {
        return
    }
    h := term.highlighting
    for &entry in h.history {
        if entry.id == id {
            entry.id = 0
        }
    }
    for &slot in h.cache {
        if slot.identity.target_id == id {
            slot.phase = .Empty
            slot.source_length = 0
            slot.source_fetch_request_id = 0
        }
    }
}

// Invalidate anchors and cached source for one rejected SQLite revision.
terminal_highlight_remove_revision :: proc(
    term: ^model.Terminal_State, id, revision: u64) {
    if id == 0 || revision == 0 || term.highlighting == nil {
        return
    }
    h := term.highlighting
    for &entry in h.history {
        if entry.id == id && entry.source_revision == revision {
            entry.id = 0
        }
    }
    for &slot in h.cache {
        if slot.identity.target_id == id &&
            slot.identity.source_revision == revision {
            slot.phase = .Empty
            slot.source_length = 0
            slot.source_fetch_request_id = 0
        }
    }
}

// Begin bounded hard-line provenance recording before the editor is cleared.
terminal_highlight_begin_submission :: proc(
    term: ^model.Terminal_State, source: string) {
    h := term.highlighting
    if h == nil {
        return
    }
    h.live.phase = .Empty
    h.recording = false
    if term.collecting_continuation {
        terminal_highlight_remove_submission(term, term.provisional_submission_id)
    }
    if term.input_mode != .Normal || len(source) == 0 {
        return
    }
    lines := 1
    for byte in source {
        if byte == '\n' {
            lines += 1
        }
    }
    if len(source) > protocol.TERMINAL_HIGHLIGHT_SOURCE_MAX_BYTES ||
        lines > model.TERMINAL_HIGHLIGHT_LINE_CAPACITY ||
        !utf8.valid_string(source) {
        h.rejected_count += 1
        log.warn("terminal submitted highlight source exceeds bounded storage")
        return
    }
    h.recording = true
    h.recording_line_count = 0
    h.recording_offset = 0
}

// Anchor each submitted hard line to its output provenance before writing it.
terminal_highlight_record_line :: proc(term: ^model.Terminal_State, line: string) {
    h := term.highlighting
    if h == nil || !h.recording {
        return
    }
    row := &term.output_grid.rows[term.output_grid.cursor.row]
    h.recording_lines[h.recording_line_count] = {
        logical_line_id = row.logical_line_id,
        grapheme_offset = row.grapheme_offset,
        source_start = h.recording_offset,
        source_end = h.recording_offset + len(line),
    }
    h.recording_line_count += 1
    h.recording_offset += len(line) + 1
}

// Publish recorded anchors and seed their bounded source cache by stable identity.
terminal_highlight_end_submission :: proc(
    term: ^model.Terminal_State, id, revision: u64, source: string) {
    h := term.highlighting
    if h == nil || !h.recording {
        return
    }
    h.recording = false
    if id == 0 || revision == 0 || len(source) == 0 ||
        len(source) > protocol.TERMINAL_HIGHLIGHT_SOURCE_MAX_BYTES ||
        !utf8.valid_string(source) {
        h.rejected_count += 1
        return
    }
    terminal_highlight_store_submission_anchors(term, id, revision)
    slot := terminal_highlight_cache_slot(term, id, revision)
    if slot == nil {
        return
    }
    terminal_highlight_schedule(term, slot, source, {
        animation_generation = term.animation_generation,
        target_kind = .History_Entry,
        target_id = id,
        source_revision = revision,
        face_generation = h.face_generation,
        mode = i32(protocol.Evaluation_Mode.Normal),
    }, 0)
}

// Publish every recorded hard-line anchor under one submission revision.
terminal_highlight_store_submission_anchors :: proc(
    term: ^model.Terminal_State, id, revision: u64) {
    h := term.highlighting
    for line in h.recording_lines[:h.recording_line_count] {
        entry := &h.history[h.next_history_anchor]
        if entry.id != 0 {
            h.eviction_count += 1
        }
        entry^ = {
            id = id,
            source_revision = revision,
            terminal_generation = term.animation_generation,
            line = line,
        }
        h.next_history_anchor = (h.next_history_anchor + 1) % len(h.history)
    }
}

// Match one physical row to its geometry-independent submitted hard-line anchor.
terminal_highlight_line_for_row :: proc(
    entry: ^model.Terminal_Highlight_History,
    row: Terminal_Output_Semantic_Row) -> ^model.Terminal_Highlight_Line {
    if !row.present {
        return nil
    }
    line := &entry.line
    if line.logical_line_id == row.logical_line_id &&
        row.grapheme_offset >= line.grapheme_offset {
        return line
    }
    return nil
}

// Mark visible anchors before selecting bounded cache victims.
terminal_highlight_mark_visible :: proc(
    term: ^model.Terminal_State, first_line, end_line: int) {
    h := term.highlighting
    h.epoch += 1
    first := max(first_line, 0)
    end := min(end_line, terminal_line_count(term))
    for &entry in h.history {
        if !terminal_highlight_history_current(term, &entry) {
            entry.id = 0
            continue
        }
        terminal_highlight_mark_anchor_visible(term, &entry, first, end)
    }
    for &slot in h.cache {
        entry := terminal_highlight_history_find(
            term, slot.identity.target_id, slot.identity.source_revision)
        if entry == nil || slot.identity.face_generation != h.face_generation {
            slot.phase = .Empty
            continue
        }
        visible := false
        for &anchor in h.history {
            if anchor.id == slot.identity.target_id &&
                anchor.source_revision == slot.identity.source_revision &&
                anchor.visible_epoch == h.epoch {
                visible = true
                break
            }
        }
        if visible {
            slot.visible_epoch = h.epoch
        }
    }
}

// Record the visibility epoch when any displayed row matches one hard-line anchor.
terminal_highlight_mark_anchor_visible :: proc(
    term: ^model.Terminal_State, entry: ^model.Terminal_Highlight_History,
    first, end: int) {
    for line in first..<end {
        if terminal_highlight_line_for_row(
            entry, terminal_output_semantic_row(term, line)) != nil {
            entry.visible_epoch = term.highlighting.epoch
            return
        }
    }
}

// Reuse an exact identity or evict the least-recently-visible inactive source slot.
terminal_highlight_cache_slot :: proc(
    term: ^model.Terminal_State, id, revision: u64) ->
        ^model.Terminal_Highlight_Slot {
    h := term.highlighting
    victim: ^model.Terminal_Highlight_Slot
    for &slot in h.cache {
        if slot.identity.target_id == id &&
            slot.identity.source_revision == revision {
            return &slot
        }
        if slot.phase == .Empty && slot.source_fetch_request_id == 0 {
            victim = &slot
        } else if slot.phase != .Pending && slot.visible_epoch != h.epoch &&
            (victim == nil || victim.phase != .Empty &&
             slot.visible_epoch < victim.visible_epoch) {
            victim = &slot
        }
    }
    if victim != nil && victim.phase != .Empty {
        h.eviction_count += 1
    }
    return victim
}

// Schedule visible cache hits; uncached identities are fetched asynchronously.
terminal_highlight_observe_history :: proc(
    term: ^model.Terminal_State, first_line, end_line: int) {
    if term == nil || term.highlighting == nil {
        return
    }
    h := term.highlighting
    terminal_highlight_mark_visible(term, first_line, end_line)
    saturated := false
    for &entry in h.history {
        if entry.id == 0 || entry.visible_epoch != h.epoch {
            continue
        }
        if !terminal_highlight_observe_history_anchor(term, &entry) {
            saturated = true
        }
    }
    if saturated && !h.cache_saturated {
        h.rejected_count += 1
        log.debug("terminal visible highlight cache full; uncached source stays plain")
    }
    h.cache_saturated = saturated
}

// Prepare one visible source cache slot, scheduling only already-cached text.
terminal_highlight_observe_history_anchor :: proc(
    term: ^model.Terminal_State,
    entry: ^model.Terminal_Highlight_History) -> bool {
    h := term.highlighting
    slot := terminal_highlight_cache_slot(
        term, entry.id, entry.source_revision)
    if slot == nil {
        return false
    }
    if slot.identity.target_id != entry.id ||
        slot.identity.source_revision != entry.source_revision {
        slot.phase = .Empty
        slot.source_length = 0
        slot.run_count = 0
        slot.source_fetch_request_id = 0
        slot.identity = {
            animation_generation = term.animation_generation,
            target_kind = .History_Entry,
            target_id = entry.id,
            source_revision = entry.source_revision,
            face_generation = h.face_generation,
            mode = i32(protocol.Evaluation_Mode.Normal),
        }
    }
    slot.identity.animation_generation = term.animation_generation
    slot.identity.face_generation = h.face_generation
    if slot.source_length > 0 && slot.phase == .Empty {
        terminal_highlight_schedule(term, slot,
            string(slot.source[:slot.source_length]), slot.identity, 0)
    }
    slot.visible_epoch = h.epoch
    return true
}

// Select one visible uncached source identity for a speculative SQLite read.
terminal_highlight_source_request_next :: proc(
    term: ^model.Terminal_State) ->
        (Terminal_Highlight_Source_Request, bool) {
    if term == nil || term.highlighting == nil {
        return {}, false
    }
    for &entry in term.highlighting.history {
        if entry.id == 0 || entry.visible_epoch != term.highlighting.epoch {
            continue
        }
        slot := terminal_highlight_cache_slot(
            term, entry.id, entry.source_revision)
        if slot != nil && slot.source_length == 0 &&
            slot.source_fetch_request_id == 0 && slot.phase != .Failed {
            return {
                submission_id = entry.id,
                source_revision = entry.source_revision,
            }, true
        }
    }
    return {}, false
}

// Bind one admitted speculative history request to its source cache slot.
terminal_highlight_source_fetch_begin :: proc(
    term: ^model.Terminal_State, id, revision, request_id: u64) -> bool {
    slot := terminal_highlight_cache_slot(term, id, revision)
    if slot == nil || slot.source_length > 0 ||
        terminal_highlight_history_find(term, id, revision) == nil {
        return false
    }
    slot.identity = {
        animation_generation = term.animation_generation,
        target_kind = .History_Entry,
        target_id = id,
        source_revision = revision,
        face_generation = term.highlighting.face_generation,
        mode = i32(protocol.Evaluation_Mode.Normal),
    }
    slot.source_fetch_request_id = request_id
    return true
}

// Resolve the destination source array for one completed asynchronous lookup.
terminal_highlight_source_fetch_slot :: proc(
    term: ^model.Terminal_State, request_id: u64) ->
        ^model.Terminal_Highlight_Slot {
    if term == nil || term.highlighting == nil || request_id == 0 {
        return nil
    }
    for &slot in term.highlighting.cache {
        if slot.source_fetch_request_id == request_id {
            return &slot
        }
    }
    return nil
}

// Validate a fetched source revision before scheduling Julia classification.
terminal_highlight_source_fetch_publish :: proc(
    term: ^model.Terminal_State, identity: protocol.Highlight_Identity,
    found: bool, source_length: int) {
    slot := terminal_highlight_source_fetch_slot(term, u64(identity.request_id))
    if slot == nil {
        return
    }
    slot.source_fetch_request_id = 0
    if identity.animation_generation != term.animation_generation ||
        identity.face_generation != term.highlighting.face_generation ||
        slot.identity.target_id != identity.target_id ||
        slot.identity.source_revision != identity.source_revision ||
        terminal_highlight_history_find(
            term, identity.target_id, identity.source_revision) == nil {
        slot.phase = .Empty
        return
    }
    if !found || source_length <= 0 || source_length > len(slot.source) {
        slot.phase = .Failed
        term.highlighting.failure_count += 1
        log.warnf(
            "terminal_history_highlight_unavailable submission_id=%d revision=%d",
            identity.target_id, identity.source_revision)
        return
    }
    slot.source_length = source_length
    slot.run_count = 0
    slot.identity = {
        animation_generation = identity.animation_generation,
        target_kind = .History_Entry,
        target_id = identity.target_id,
        source_revision = identity.source_revision,
        face_generation = identity.face_generation,
        mode = i32(protocol.Evaluation_Mode.Normal),
    }
    slot.phase = .Scheduled
}

// Borrow complete source-relative styles for one retained visible command.
terminal_history_highlight_slot :: proc(
    term: ^model.Terminal_State,
    entry: ^model.Terminal_Highlight_History) -> ^model.Terminal_Highlight_Slot {
    if term == nil || term.highlighting == nil || entry == nil {
        return nil
    }
    for &slot in term.highlighting.cache {
        if slot.phase == .Ready && slot.identity.target_id == entry.id &&
            slot.identity.source_revision == entry.source_revision &&
            terminal_highlight_slot_current(term, &slot) {
            return &slot
        }
    }
    return nil
}

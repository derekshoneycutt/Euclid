package terminalview

import model "model"
import protocol "../../core/protocol"
import termhiststore "../../persistence/userdata/history"
import "core:log"
import "core:unicode/utf8"

Terminal_Highlight_Source_Request :: struct {
    submission_id: u64,
    source_revision: u64,
    target_kind: protocol.Highlight_Target,
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
        if slot.identity.target_kind == .History_Entry &&
            slot.identity.target_id == id {
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
        if slot.identity.target_kind == .History_Entry &&
            slot.identity.target_id == id &&
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
        terminal_highlight_mark_slot_visible(term, &slot)
    }
}

// Keep a cached style live only while its scope-qualified source remains admissible.
terminal_highlight_mark_slot_visible :: proc(
    term: ^model.Terminal_State, slot: ^model.Terminal_Highlight_Slot) {
    h := term.highlighting
    entry: ^model.Terminal_Highlight_History
    if slot.identity.target_kind == .History_Entry {
        entry = terminal_highlight_history_find(
            term, slot.identity.target_id, slot.identity.source_revision)
    }
    candidate := terminal_highlight_explorer_candidate(
        h, slot.identity.target_kind, slot.identity.target_id,
        slot.identity.source_revision)
    if (entry == nil && candidate == nil) ||
        slot.identity.face_generation != h.face_generation {
        slot.phase = .Empty
        return
    }
    visible := candidate != nil
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

// Reuse one session-history identity or evict an inactive source slot.
terminal_highlight_cache_slot :: proc(
    term: ^model.Terminal_State, id, revision: u64) ->
        ^model.Terminal_Highlight_Slot {
    return terminal_highlight_cache_slot_scoped(
        term, .History_Entry, id, revision)
}

// Keep session and persistent identities distinct even when their numeric IDs match.
terminal_highlight_cache_slot_scoped :: proc(
    term: ^model.Terminal_State, target_kind: protocol.Highlight_Target,
    id, revision: u64) -> ^model.Terminal_Highlight_Slot {
    h := term.highlighting
    victim: ^model.Terminal_Highlight_Slot
    for &slot in h.cache {
        if slot.identity.target_kind == target_kind &&
            slot.identity.target_id == id &&
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

// Find a candidate admitted by the current explorer opening and query.
terminal_highlight_explorer_candidate :: proc(
    h: ^model.Terminal_Highlighting, target_kind: protocol.Highlight_Target,
    id, revision: u64) -> ^model.Terminal_Highlight_Explorer_Candidate {
    for &candidate in h.explorer_candidates[:h.explorer_candidate_count] {
        if candidate.target_kind == target_kind &&
            candidate.target_id == id &&
            candidate.source_revision == revision {
            return &candidate
        }
    }
    return nil
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
    slot := terminal_highlight_cache_slot(
        term, entry.id, entry.source_revision)
    if slot == nil {
        return false
    }
    terminal_highlight_prepare_history_slot(term, entry, slot)
    return true
}

// Refresh one anchor's scoped identity and schedule its retained exact source.
terminal_highlight_prepare_history_slot :: proc(
    term: ^model.Terminal_State, entry: ^model.Terminal_Highlight_History,
    slot: ^model.Terminal_Highlight_Slot) {
    h := term.highlighting
    if slot.identity.target_kind != .History_Entry ||
        slot.identity.target_id != entry.id ||
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
}

// Retire explorer-only cache entries when its opening or query identity changes.
terminal_highlight_retire_explorer_candidates :: proc(
    term: ^model.Terminal_State) {
    h := term.highlighting
    for &slot in h.cache {
        if slot.identity.target_kind == .Persistent_History_Entry ||
            (slot.identity.target_kind == .History_Entry &&
             terminal_highlight_history_find(
                 term, slot.identity.target_id,
                 slot.identity.source_revision) == nil) {
            slot.identity = {}
            slot.phase = .Empty
            slot.source_length = 0
            slot.run_count = 0
            slot.source_fetch_request_id = 0
        }
    }
    h.explorer_candidate_count = 0
}

// Observe the explorer's bounded candidate page and reuse an exact selected preview.
terminal_highlight_observe_explorer :: proc(
    term: ^model.Terminal_State, explorer: ^model.History_Explorer_State) {
    if term == nil || term.highlighting == nil || explorer == nil {
        return
    }
    h := term.highlighting
    active := explorer.active
    lifecycle_changed := h.explorer_active != active ||
        active && (h.explorer_opening_generation != explorer.opening_generation ||
        h.explorer_query_generation != explorer.query_generation ||
        h.explorer_runtime_epoch != explorer.identity.runtime_epoch)
    if lifecycle_changed {
        terminal_highlight_retire_explorer_candidates(term)
        h.explorer_active = active
        h.explorer_opening_generation = explorer.opening_generation
        h.explorer_query_generation = explorer.query_generation
        h.explorer_runtime_epoch = explorer.identity.runtime_epoch
    }
    if !active {
        return
    }
    h.explorer_candidate_count = 0
    selected := explorer.selected_index
    if selected >= 0 && selected < explorer.row_count {
        terminal_highlight_explorer_add_candidate(
            term, explorer, selected, true)
    }
    for index in 0..<explorer.row_count {
        if index != selected {
            terminal_highlight_explorer_add_candidate(
                term, explorer, index, false)
        }
    }
}

// Register one Normal-mode row and schedule it from source already owned by preview.
terminal_highlight_explorer_add_candidate :: proc(
    term: ^model.Terminal_State, explorer: ^model.History_Explorer_State,
    index: int, selected: bool) {
    if index < 0 || index >= explorer.row_count ||
        term.highlighting.explorer_candidate_count >=
            len(term.highlighting.explorer_candidates) {
        return
    }
    record := explorer.rows[index].record
    if record.mode != .Normal || record.source_id == 0 ||
        record.source_revision == 0 {
        return
    }
    target_kind: protocol.Highlight_Target = .History_Entry
    if record.scope == .Persistent {
        target_kind = .Persistent_History_Entry
    }
    if terminal_highlight_explorer_register_candidate(
        term, explorer, record, target_kind, selected) == nil {
        return
    }
    slot := terminal_highlight_cache_slot_scoped(
        term, target_kind, record.source_id, record.source_revision)
    if slot == nil {
        return
    }
    terminal_highlight_prepare_explorer_slot(term, record, target_kind, slot)
    if selected && slot.source_length == 0 &&
        terminal_highlight_explorer_preview_matches(explorer, record) {
        slot.source_fetch_request_id = 0
        terminal_highlight_schedule(
            term, slot, string(explorer.preview_source[:explorer.preview_length]),
            slot.identity, 0)
    }
}

// Register one scoped source in the bounded current-query candidate set.
terminal_highlight_explorer_register_candidate :: proc(
    term: ^model.Terminal_State, explorer: ^model.History_Explorer_State,
    record: termhiststore.History_Record,
    target_kind: protocol.Highlight_Target, selected: bool) ->
        ^model.Terminal_Highlight_Explorer_Candidate {
    h := term.highlighting
    if terminal_highlight_explorer_candidate(
        h, target_kind, record.source_id, record.source_revision) != nil {
        return nil
    }
    candidate := &h.explorer_candidates[h.explorer_candidate_count]
    candidate^ = {
        target_kind = target_kind,
        target_id = record.source_id,
        source_revision = record.source_revision,
        visible_epoch = h.epoch,
        selected = selected,
        awaiting_preview = selected &&
            explorer.preview_status == .Loading,
    }
    h.explorer_candidate_count += 1
    return candidate
}

// Refresh scoped slot identity while retaining pending request correlation.
terminal_highlight_prepare_explorer_slot :: proc(
    term: ^model.Terminal_State, record: termhiststore.History_Record,
    target_kind: protocol.Highlight_Target, slot: ^model.Terminal_Highlight_Slot) {
    h := term.highlighting
    if slot.identity.target_kind != target_kind ||
        slot.identity.target_id != record.source_id ||
        slot.identity.source_revision != record.source_revision {
        slot.identity = {}
        slot.phase = .Empty
        slot.source_length = 0
        slot.run_count = 0
        slot.source_fetch_request_id = 0
    }
    request_id := protocol.Request_Id(0)
    if slot.phase == .Pending {
        request_id = slot.identity.request_id
    }
    slot.identity = {
        request_id = request_id,
        animation_generation = term.animation_generation,
        target_kind = target_kind,
        target_id = record.source_id,
        source_revision = record.source_revision,
        face_generation = h.face_generation,
        mode = i32(protocol.Evaluation_Mode.Normal),
    }
    slot.visible_epoch = h.epoch
    if slot.source_length > 0 && slot.phase == .Empty {
        terminal_highlight_schedule(
            term, slot, string(slot.source[:slot.source_length]), slot.identity, 0)
    }
}

// Match the exact ready Normal-mode preview to its selected candidate identity.
terminal_highlight_explorer_preview_matches :: proc(
    explorer: ^model.History_Explorer_State,
    record: termhiststore.History_Record) -> bool {
    return explorer.preview_status == .Ready &&
        explorer.preview_record.scope == record.scope &&
        explorer.preview_record.source_id == record.source_id &&
        explorer.preview_record.source_revision == record.source_revision &&
        explorer.preview_record.mode == .Normal &&
        explorer.preview_length > 0
}

// Select one visible uncached source identity for a speculative SQLite read.
terminal_highlight_source_request_next :: proc(
    term: ^model.Terminal_State) ->
        (Terminal_Highlight_Source_Request, bool) {
    if term == nil || term.highlighting == nil {
        return {}, false
    }
    h := term.highlighting
    for &candidate in h.explorer_candidates[:h.explorer_candidate_count] {
        if candidate.visible_epoch != h.epoch || candidate.awaiting_preview {
            continue
        }
        slot := terminal_highlight_cache_slot_scoped(
            term, candidate.target_kind, candidate.target_id,
            candidate.source_revision)
        if slot != nil && slot.source_length == 0 &&
            slot.source_fetch_request_id == 0 && slot.phase != .Failed {
            return {
                submission_id = candidate.target_id,
                source_revision = candidate.source_revision,
                target_kind = candidate.target_kind,
            }, true
        }
    }
    for &entry in h.history {
        if entry.id == 0 || entry.visible_epoch != h.epoch {
            continue
        }
        slot := terminal_highlight_cache_slot(
            term, entry.id, entry.source_revision)
        if slot != nil && slot.source_length == 0 &&
            slot.source_fetch_request_id == 0 && slot.phase != .Failed {
            return {
                submission_id = entry.id,
                source_revision = entry.source_revision,
                target_kind = .History_Entry,
            }, true
        }
    }
    return {}, false
}

// Bind one admitted speculative history request to its source cache slot.
terminal_highlight_source_fetch_begin :: proc(
    term: ^model.Terminal_State, id, revision, request_id: u64) -> bool {
    return terminal_highlight_source_fetch_begin_scoped(
        term, .History_Entry, id, revision, request_id)
}

// Bind a keyed session or persistent lookup to its exact visible candidate.
terminal_highlight_source_fetch_begin_scoped :: proc(
    term: ^model.Terminal_State, target_kind: protocol.Highlight_Target,
    id, revision, request_id: u64) -> bool {
    slot := terminal_highlight_cache_slot_scoped(
        term, target_kind, id, revision)
    candidate := terminal_highlight_explorer_candidate(
        term.highlighting, target_kind, id, revision)
    anchored := target_kind == .History_Entry &&
        terminal_highlight_history_find(term, id, revision) != nil
    if slot == nil || slot.source_length > 0 ||
        (candidate == nil && !anchored) {
        return false
    }
    slot.identity = {
        animation_generation = term.animation_generation,
        target_kind = target_kind,
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
        slot.identity.target_kind != identity.target_kind ||
        slot.identity.target_id != identity.target_id ||
        slot.identity.source_revision != identity.source_revision ||
        (terminal_highlight_explorer_candidate(
            term.highlighting, identity.target_kind, identity.target_id,
            identity.source_revision) == nil &&
         (identity.target_kind != .History_Entry ||
          terminal_highlight_history_find(
              term, identity.target_id, identity.source_revision) == nil)) {
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
        target_kind = identity.target_kind,
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
        if slot.phase == .Ready &&
            slot.identity.target_kind == .History_Entry &&
            slot.identity.target_id == entry.id &&
            slot.identity.source_revision == entry.source_revision &&
            terminal_highlight_slot_current(term, &slot) {
            return &slot
        }
    }
    return nil
}

package terminalview

import model "model"
import protocol "../../core/protocol"
import "core:log"
import "core:unicode/utf8"

// Remove a provisional command before checkpoint restoration can reuse its row identities.
terminal_highlight_remove_latest :: proc(term: ^model.Terminal_State) {
    h := term.highlighting
    if h == nil || term.history == nil {
        return
    }
    for &entry in h.history {
        if entry.id != 0 && entry.history_index == term.history.history_len - 1 {
            entry.id = 0
        }
    }
}

// Start a bounded source/provenance recording before grid submission clears editable text.
terminal_highlight_begin_submission :: proc(
    term: ^model.Terminal_State, source: string) {
    h := term.highlighting
    if h == nil {
        return
    }
    h.live.phase = .Empty
    h.recording = false
    if term.collecting_continuation {
        terminal_highlight_remove_latest(term)
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
        lines > model.TERMINAL_HIGHLIGHT_LINE_CAPACITY || !utf8.valid_string(source) {
        h.rejected_count += 1
        log.warn("terminal submitted highlight source exceeds bounded storage")
        return
    }
    h.recording = true
    h.recording_line_count = 0
    h.recording_offset = 0
}

// Anchor each hard source row before its prefix is written; soft wrapping preserves this ID.
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

// End recording and suppress a snapshot if authoritative history admission failed.
terminal_highlight_end_submission :: proc(term: ^model.Terminal_State) {
    h := term.highlighting
    if h == nil || !h.recording {
        return
    }
    h.recording = false
    index := term.history.history_len - 1
    if index < 0 {
        return
    }
    source := &term.history.history[index]
    for line in h.recording_lines[:h.recording_line_count] {
        entry := &h.history[h.next_history_anchor]
        if entry.id != 0 {
            h.eviction_count += 1
        }
        entry^ = {id = source.id, history_index = index, line = line}
        h.next_history_anchor =
            (h.next_history_anchor + 1) % len(h.history)
    }
}

// Match a physical row to a submitted hard line, independent of scroll and reflow.
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

// Mark visible submissions before choosing victims, avoiding visible-cache thrash.
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
        for line in first..<end {
            if terminal_highlight_line_for_row(
                &entry, terminal_output_semantic_row(term, line)) != nil {
                entry.visible_epoch = h.epoch
                break
            }
        }
    }
    for &slot in h.cache {
        entry := terminal_highlight_history_find(term, slot.identity.target_id)
        for &anchor in h.history {
            if anchor.id != 0 && anchor.id == slot.identity.target_id &&
                anchor.visible_epoch == h.epoch {
                slot.visible_epoch = h.epoch
                break
            }
        }
        if slot.phase != .Empty && (entry == nil ||
            slot.identity.face_generation != h.face_generation) {
            slot.phase = .Empty
        }
    }
}

// Reuse an exact entry slot or evict the least recently visible non-visible slot.
terminal_highlight_cache_slot :: proc(
    term: ^model.Terminal_State, id: u64) -> ^model.Terminal_Highlight_Slot {
    h := term.highlighting
    victim: ^model.Terminal_Highlight_Slot
    for &slot in h.cache {
        if slot.phase != .Empty && slot.identity.target_id == id {
            return &slot
        }
        if slot.phase == .Empty {
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

// Schedule only visible uncached source, bounded independently of history storage.
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
        slot := terminal_highlight_cache_slot(term, entry.id)
        if slot == nil {
            saturated = true
            continue
        }
        if slot.phase == .Empty || slot.identity.target_id != entry.id {
            terminal_highlight_schedule(term, slot,
                string(term.history.history[entry.history_index].text), {
                    animation_generation = term.animation_generation,
                    target_kind = .History_Entry, target_id = entry.id,
                    source_revision = entry.id, face_generation = h.face_generation,
                }, 0)
        }
        slot.visible_epoch = h.epoch
    }
    if saturated && !h.cache_saturated {
        h.rejected_count += 1
        log.debug("terminal visible highlight cache full; uncached source stays plain")
    }
    h.cache_saturated = saturated
}

// Borrow the complete source-relative styles for one retained visible command.
terminal_history_highlight_slot :: proc(
    term: ^model.Terminal_State,
    entry: ^model.Terminal_Highlight_History) -> ^model.Terminal_Highlight_Slot {
    if term == nil || term.highlighting == nil || entry == nil {
        return nil
    }
    for &slot in term.highlighting.cache {
        if slot.phase == .Ready && slot.identity.target_id == entry.id &&
            terminal_highlight_slot_current(term, &slot) {
            return &slot
        }
    }
    return nil
}

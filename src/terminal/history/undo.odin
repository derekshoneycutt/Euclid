package termhist

// Termhist_Snapshot locates packed text and retains the draft's editing position.
Termhist_Snapshot :: struct {
    offset: int,
    length: int,
    cursor: int,
    anchor: int,
    preferred_column: int,
}

// Termhist_Undo reuses generation-owned backing through prompt and branch resets.
Termhist_Undo :: struct {
    snapshots: []Termhist_Snapshot,
    bytes: []u8,
    count: int,
    used: int,
    position: int,
    sequence: bool,
}

// Reset logical edit history while retaining backing capacity for the next prompt.
termhist_reset_undo :: proc(state: ^Termhist_State) {
    state.undo.count = 0
    state.undo.used = 0
    state.undo.position = 0
    state.undo.sequence = false
}

// Reserve both snapshot stores without publishing changes to the logical timeline.
termhist_reserve_undo :: proc(state: ^Termhist_State, count, bytes: int) -> bool {
    undo := &state.undo
    if count > len(undo.snapshots) {
        capacity := max(count, max(1, len(undo.snapshots) * 2))
        snapshots, err := make(
            []Termhist_Snapshot, capacity, state.borrowed_allocator)
        if err != nil {
            state.allocation_failed = true
            return false
        }
        copy(snapshots, undo.snapshots[:undo.count])
        delete(undo.snapshots, state.borrowed_allocator)
        undo.snapshots = snapshots
    }
    if !termhist_ensure_u8_capacity(state, &undo.bytes, bytes, undo.used) {
        state.allocation_failed = true
        return false
    }
    return true
}

// Return the packed prefix retained when the current redo branch is replaced.
termhist_undo_prefix :: proc(state: ^Termhist_State) -> int {
    undo := &state.undo
    if undo.position < undo.count {
        return undo.snapshots[undo.position].offset
    }
    return undo.used
}

// Reserve a snapshot of the current draft before any text or timeline mutation.
termhist_prepare_undo :: proc(state: ^Termhist_State) -> bool {
    return termhist_reserve_undo(
        state, state.undo.position + 1, termhist_undo_prefix(state) + state.text_len)
}

// Copy one draft into reserved storage, truncating redo only after preparation.
termhist_capture_undo :: proc(state: ^Termhist_State, advance: bool) {
    undo := &state.undo
    offset := termhist_undo_prefix(state)
    undo.snapshots[undo.position] = {
        offset = offset, length = state.text_len,
        cursor = state.cursor, anchor = state.anchor,
        preferred_column = state.preferred_column,
    }
    copy(undo.bytes[offset:offset + state.text_len], state.text[:state.text_len])
    undo.used = offset + state.text_len
    undo.count = undo.position + 1
    if advance {
        undo.position += 1
        undo.sequence = false
    }
}

// Restore a reserved snapshot without recursively recording edits or old revisions.
termhist_restore_undo :: proc(state: ^Termhist_State, position: int) {
    undo := &state.undo
    snapshot := undo.snapshots[position]
    copy(state.text[:snapshot.length],
        undo.bytes[snapshot.offset:snapshot.offset + snapshot.length])
    state.text_len = snapshot.length
    state.cursor = snapshot.cursor
    state.anchor = snapshot.anchor
    state.preferred_column = snapshot.preferred_column
    state.content_revision += 1
    state.reset_revision += 1
    termhist_clear_preedit(state)
    termhist_end_history_browse(state)
    undo.position = position
    undo.sequence = true
}

// Undo one operation, saving the current endpoint only outside an undo/redo sequence.
termhist_undo :: proc(state: ^Termhist_State) -> bool {
    undo := &state.undo
    if undo.position == 0 || state.preedit_active {
        return false
    }
    target := undo.snapshots[undo.position - 1]
    if !termhist_ensure_u8_capacity(state, &state.text, target.length, state.text_len) {
        state.allocation_failed = true
        return false
    }
    if !undo.sequence {
        if !termhist_prepare_undo(state) {
            return false
        }
        termhist_capture_undo(state, false)
    }
    termhist_restore_undo(state, undo.position - 1)
    return true
}

// Redo only during an uninterrupted undo/redo sequence with a retained endpoint.
termhist_redo :: proc(state: ^Termhist_State) -> bool {
    undo := &state.undo
    if !undo.sequence || undo.position + 1 >= undo.count || state.preedit_active {
        return false
    }
    target := undo.snapshots[undo.position + 1]
    if !termhist_ensure_u8_capacity(state, &state.text, target.length, state.text_len) {
        state.allocation_failed = true
        return false
    }
    termhist_restore_undo(state, undo.position + 1)
    return true
}

// Finish acceptance with either a fresh prompt or a suspended edit timeline.
termhist_finish_accept :: proc(state: ^Termhist_State, preserve_undo: bool) {
    if preserve_undo {
        termhist_clear_draft(state)
    } else {
        termhist_clear(state)
    }
}

// Recover a provisionally accepted draft without recording temporary rebuild states.
termhist_resume_draft :: proc(
    state: ^Termhist_State, source: string, snapshot: Termhist_Snapshot) -> bool {
    if !termhist_ensure_u8_capacity(state, &state.text, len(source), state.text_len) {
        state.allocation_failed = true
        return false
    }
    copy(state.text[:len(source)], transmute([]u8)source)
    state.text_len = len(source)
    state.cursor = snapshot.cursor
    state.anchor = snapshot.anchor
    state.preferred_column = snapshot.preferred_column
    state.content_revision += 1
    state.reset_revision += 1
    state.undo.sequence = false
    return true
}

// Append an incomplete prompt's newline and indentation as one atomic undoable edit.
termhist_continue_draft :: proc(state: ^Termhist_State, indent: string) -> bool {
    needed := state.text_len + 1 + len(indent)
    if !termhist_ensure_u8_capacity(state, &state.text, needed, state.text_len) {
        state.allocation_failed = true
        return false
    }
    if !termhist_prepare_undo(state) {
        return false
    }
    termhist_capture_undo(state, true)
    state.text[state.text_len] = '\n'
    copy(state.text[state.text_len + 1:needed], transmute([]u8)indent)
    state.text_len = needed
    state.cursor = needed
    state.anchor = needed
    state.preferred_column = -1
    state.content_revision += 1
    return true
}

package uilibrary

import core "../../../core"
import collections "../../../collections"
import bridgemodel "../../../bridge/model"
import viewmodel "../model"
import viewpreferences "../../preferences"
import uuid "core:encoding/uuid"
import log "core:log"

LIBRARY_COLLECTION_NOTE_DEBOUNCE_SECONDS :: 0.4

// Advance note debounce and reload a clean active note after generation changes.
library_collection_note_service :: proc(
    state: ^core.Euclid_General_State, delta_seconds: f32) {
    if state == nil {
        return
    }
    note := &state^.ui_runtime.library.collection_note
    if note^.pending_selection_entry_id != (uuid.Identifier{}) &&
        note^.generation == state^.animation_memory.generation &&
        note^.status == .Ready {
        tree_collection_note_apply_pending_selection(state)
        if note^.pending_selection_entry_id == (uuid.Identifier{}) {
            return
        }
    }
    if note^.status == .Idle {
        return
    }
    if note^.generation != state^.animation_memory.generation {
        library_collection_note_refresh_generation(state, note)
        return
    }
    if !note^.dirty || !note^.editing || note^.save_failed {
        return
    }
    note^.debounce_remaining_seconds = max(
        f64(0), note^.debounce_remaining_seconds - max(0, f64(delta_seconds)))
    if note^.debounce_remaining_seconds > 0 ||
        library_collection_note_write_is_in_flight(state, note) ||
        state^.preferences_runtime.note_request_kind == .Write {
        return
    }
    _ = viewpreferences.settings_save_collection_note_queue_write(state)
}

// Reload only a clean note whose placement still owns the active animation.
library_collection_note_refresh_generation :: proc(
    state: ^core.Euclid_General_State,
    note: ^viewmodel.Ui_Library_Collection_Note) {
    if note^.dirty {
        note^.status = .Failed
        note^.save_failed = true
        log.error("collection_note_generation_retired_with_dirty_text")
        return
    }
    animation: ^bridgemodel.Euclid_Julia_Animation_Interface
    if state^.julia_interface != nil {
        animation = state^.julia_interface.current_animation
    }
    if animation == nil || animation^.stable_id != note^.animation_id ||
       note^.identity.entry_id !=
            state^.ui_runtime.library.tree.selected_item_id {
        _ = viewpreferences.settings_save_collection_note_clear(state)
        return
    }
    identity := note^.identity
    request_edit := note^.editing || note^.edit_requested
    _ = viewpreferences.settings_save_collection_note_load(
        state, identity, request_edit)
}

// Keep the active animation generation alive until its latest note revision is durable.
library_collection_note_prepare_retirement :: proc(
    state: ^core.Euclid_General_State) -> bool {
    if state == nil {
        return true
    }
    note := &state^.ui_runtime.library.collection_note
    if note^.status == .Idle {
        return true
    }
    if note^.generation != state^.animation_memory.generation {
        if note^.dirty {
            log.error("collection_note_retirement_generation_mismatch")
            return false
        }
        return true
    }
    if note^.dirty {
        note^.leave_editing_after_save = true
        note^.debounce_remaining_seconds = 0
        _ = viewpreferences.settings_save_collection_note_flush(state)
        return false
    }
    note^.editing = false
    note^.edit_requested = false
    return true
}

// Avoid submitting a duplicate revision while its immutable snapshot is active.
library_collection_note_write_is_in_flight :: proc(
    state: ^core.Euclid_General_State,
    note: ^viewmodel.Ui_Library_Collection_Note) -> bool {
    runtime := &state^.preferences_runtime
    task := &runtime^.settings_save_payload
    return runtime^.settings_save_active &&
        task^.kind == .Collection_Note_Write &&
        task^.note_revision == note^.revision &&
        task^.note_request_id == note^.request_id &&
        task^.note_generation == note^.generation &&
        task^.note_identity.collection_id == note^.identity.collection_id &&
        task^.note_identity.entry_id == note^.identity.entry_id
}

// Begin editing the exact user-collection animation placement selected in Library.
library_collection_note_begin_editing :: proc(
    state: ^core.Euclid_General_State, entry_id: uuid.Identifier) -> bool {
    if state == nil {
        return false
    }
    identity, failure := collections.placement_identity_for_entry(
        &state^.preferences_runtime.collections_state, entry_id)
    if failure != .None {
        return false
    }
    return viewpreferences.settings_save_collection_note_load(
        state, identity, true)
}

// Request a durable flush before the authoring surface is retired.
library_collection_note_done :: proc(state: ^core.Euclid_General_State) -> bool {
    return viewpreferences.settings_save_collection_note_flush(state)
}

// Record one accepted active-editor text revision with the shared save owner.
library_collection_note_edit :: proc(state: ^core.Euclid_General_State) -> bool {
    return viewpreferences.settings_save_collection_note_edit(state)
}

// Persist a changed reading-order preference through the same note revision.
library_collection_note_toggle_order :: proc(
    state: ^core.Euclid_General_State) -> bool {
    if state == nil {
        return false
    }
    note := &state^.ui_runtime.library.collection_note
    if note^.status != .Ready || !note^.editing {
        return false
    }
    note^.notes_on_top = !note^.notes_on_top
    return viewpreferences.settings_save_collection_note_edit(state)
}

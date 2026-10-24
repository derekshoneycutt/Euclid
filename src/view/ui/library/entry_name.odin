package uilibrary

import core "../../../core"
import collections "../../../collections"
import viewmodel "../model"
import viewpreferences "../../preferences"
import log "core:log"
import unicode "core:unicode"
import utf8 "core:unicode/utf8"
import uuid "core:encoding/uuid"
import geometry "../../../core/geometry"
import input "../../input"
import uiwidgets "../widgets"
import theme "../theme"
import viewmessages "../../messages"

LIBRARY_ENTRY_NAME_DEBOUNCE_SECONDS :: 0.4
LIBRARY_ENTRY_NAME_DEBOUNCE_EPSILON_SECONDS :: 0.000001
LIBRARY_ENTRY_NAME_INPUT_TRAVERSAL_ORDER :: u32(5)

Library_Entry_Name_Prefill :: struct {
    target_kind: viewmodel.Ui_Library_Name_Target_Kind,
    identity: collections.Placement_Identity,
    accepted_name: []u8,
    accepted_name_length: int,
    valid: bool,
}

// library_entry_name_visible exposes only the selected, logically open Library field.
library_entry_name_visible :: #force_inline proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State) -> bool {
    if runtime == nil {
        return false
    }
    draft := &runtime^.library.entry_name
    return draft^.active && draft^.rect.width > 0 && draft^.clip_rect.width > 0 &&
        runtime^.layout.active_accordion_section == .Library &&
        runtime^.library.actions.drawer.open &&
        runtime^.library.actions.drawer.entry_id == draft^.entry_id &&
        runtime^.library.tree.selected_item_id == draft^.entry_id &&
        !runtime^.library.search.active
}

// library_entry_name_input_params binds the single editor to its placement-owned draft.
library_entry_name_input_params :: proc(
    params: Tree_List_Params, entry_id: uuid.Identifier,
    rect, clip_rect: geometry.Rectangle,
    frame: input.Input_Frame) -> uiwidgets.Input_Box_Params {
    draft := &params.ui_runtime^.library.entry_name
    focus := params.ui_runtime^.input.interaction_frame.effective_focus
    target := params.ui_runtime^.input.interaction_frame.pointer_target
    descriptor := library_entry_name_semantic_descriptor(params, entry_id, draft)
    text_percent :=
        params.general_state^.ui_runtime.preferences.values.interface.text_size_percent
    return {
        rect = rect,
        clip_rect = clip_rect,
        descriptor = descriptor,
        controls = tree_semantic_id(),
        semantic_focus = params.ui_runtime^.semantic_focus,
        state = &draft^.input,
        frame = frame,
        text_input_id = TREE_ENTRY_NAME_INPUT_ID,
        focused = focus.kind == .Input_Box &&
            focus.id == TREE_ENTRY_NAME_INPUT_ID,
        pointer_routed = target.focus.kind == .Input_Box &&
            target.id == TREE_ENTRY_NAME_INPUT_ID,
        padding = .Compact,
        column_advance = theme.ui_scaled_metric(theme.TEXT_WRAP_ADVANCE, text_percent),
        font_size = theme.ui_font_size(text_percent),
        font = params.font,
        resolver = params.font_resolver,
        edit_target = {draft^.value[:], &draft^.value_length},
        edit_policy = {unicode_completion = true},
        defer_semantics = true,
    }
}

// library_entry_name_semantic_descriptor binds text actions to one placement identity.
library_entry_name_semantic_descriptor :: proc(
    params: Tree_List_Params, entry_id: uuid.Identifier,
    draft: ^viewmodel.Ui_Library_Entry_Name_Draft) ->
        viewmodel.Ui_Editable_Text_Descriptor {
    id := tree_actions_semantic_id(params, entry_id, TREE_ENTRY_NAME_INPUT)
    text_run_id := id
    text_run_id.local_id = TREE_ENTRY_NAME_TEXT_RUN
    return {
        id = id, text_run_id = text_run_id,
        parent = tree_actions_semantic_id(params, entry_id, TREE_ACTION_DRAWER),
        region = .Accordion_Content,
        traversal_order = LIBRARY_ENTRY_NAME_INPUT_TRAVERSAL_ORDER,
        label = viewmessages.shell_message(params.general_state, .Library_Entry_Name),
        text = string(draft^.value[:draft^.value_length]),
        mode = .Editable,
        cursor_byte = draft^.input.cursor_byte,
        anchor_byte = draft^.input.anchor_byte,
        content_revision = draft^.input.content_revision,
    }
}

// Begin editing a custom head or writable Library placement without resetting its draft.
library_entry_name_begin :: proc(
    state: ^core.Euclid_General_State,
    entry_id: uuid.Identifier,
    prefill: string) -> bool {
    if state == nil {
        return false
    }
    prefill_result := library_entry_name_resolve_prefill(state, entry_id, prefill)
    if !prefill_result.valid {
        return false
    }
    draft := &state^.ui_runtime.library.entry_name
    if draft^.active && draft^.entry_id == entry_id &&
        draft^.target_kind == prefill_result.target_kind &&
        draft^.placement == prefill_result.identity {
        return true
    }
    if draft^.active && !library_entry_name_flush(state) {
        return false
    }
    library_entry_name_initialize_draft(
        draft, entry_id, prefill_result, prefill)
    return true
}

// Initialize the single editor from an owner-resolved typed name target.
library_entry_name_initialize_draft :: proc(
    draft: ^viewmodel.Ui_Library_Entry_Name_Draft,
    entry_id: uuid.Identifier,
    prefill_result: Library_Entry_Name_Prefill,
    prefill: string) {
    revision := draft^.revision + 1
    draft^ = {
        target_kind = prefill_result.target_kind,
        entry_id = entry_id,
        placement = prefill_result.identity,
        accepted_name_length = prefill_result.accepted_name_length,
        revision = revision,
        active = true,
    }
    if prefill_result.accepted_name_length > 0 {
        copy(
            draft^.accepted_name[:prefill_result.accepted_name_length],
            prefill_result.accepted_name[:prefill_result.accepted_name_length])
    }
    if len(prefill) > 0 {
        copy(draft^.value[:len(prefill)], transmute([]u8)prefill)
    }
    draft^.value_length = len(prefill)
    draft^.input.cursor_byte = len(prefill)
    draft^.input.content_revision = 1
}

// Validate the prefill and resolve mandatory collection or optional placement text.
library_entry_name_resolve_prefill :: proc(
    state: ^core.Euclid_General_State,
    entry_id: uuid.Identifier,
    prefill: string) -> Library_Entry_Name_Prefill {
    if entry_id == (uuid.Identifier{}) ||
        len(prefill) > collections.ENTRY_NAME_MAX_BYTES ||
        !collections.entry_name_bytes_are_valid(
            transmute([]u8)prefill, len(prefill)) {
        log.error("library_entry_name_begin_rejected_invalid_prefill")
        return {}
    }
    set := &state^.preferences_runtime.collections_state
    collection_index := collections.find_collection(set, entry_id)
    if collection_index >= 0 {
        return library_collection_name_prefill(set, entry_id)
    }
    return library_placement_name_prefill(set, entry_id)
}

// Resolve accepted placement text only for an editable qualified owner.
library_placement_name_prefill :: proc(
    set: ^collections.Set,
    entry_id: uuid.Identifier) -> Library_Entry_Name_Prefill {
    identity, identity_error :=
        collections.placement_identity_for_entry(set, entry_id)
    if identity_error != .None {
        log.error("library_entry_name_begin_rejected_missing_placement")
        return {}
    }
    if identity.collection_id != collections.FAVORITES_COLLECTION_ID {
        _, edit_error := collections.collection_edit_index(set, identity.collection_id)
        if edit_error != .None {
            log.errorf("library_entry_name_begin_rejected policy=%v", edit_error)
            return {}
        }
    }
    if identity.collection_id == collections.FAVORITES_COLLECTION_ID &&
        identity.parent_entry_id != (uuid.Identifier{}) {
        log.error("library_entry_name_begin_rejected_invalid_favorite_parent")
        return {}
    }
    placement, placement_error := collections.placement_resolve(set, identity)
    if placement_error != .None {
        log.errorf("library_entry_name_begin_rejected policy=%v", placement_error)
        return {}
    }
    return {identity = identity, accepted_name = placement.custom_name,
        accepted_name_length = placement.custom_name_length, valid = true}
}

// Replace the owned text immediately and restart its idle-admission deadline.
library_entry_name_edit :: proc(
    state: ^core.Euclid_General_State,
    entry_id: uuid.Identifier,
    value: string) -> bool {
    if state == nil || len(value) > collections.ENTRY_NAME_MAX_BYTES ||
        !collections.entry_name_bytes_are_valid(transmute([]u8)value, len(value)) {
        log.error("library_entry_name_edit_rejected_invalid_value")
        return false
    }
    draft := &state^.ui_runtime.library.entry_name
    if !draft^.active || draft^.entry_id != entry_id {
        log.error("library_entry_name_edit_rejected_stale_owner")
        return false
    }
    changed := value != string(draft^.value[:draft^.value_length])
    if changed {
        draft^.value = {}
        if len(value) > 0 {
            copy(draft^.value[:len(value)], transmute([]u8)value)
        }
        draft^.value_length = len(value)
        draft^.input.content_revision += 1
        draft^.input.cursor_byte = min(draft^.input.cursor_byte, len(value))
        draft^.input.anchor_byte = min(draft^.input.anchor_byte, len(value))
    }
    draft^.revision += 1
    draft^.edit_intent = true
    draft^.dirty = true
    draft^.admission_failed = false
    draft^.last_admission_error = .None
    draft^.debounce_remaining_seconds = LIBRARY_ENTRY_NAME_DEBOUNCE_SECONDS
    return true
}

// Admit an edited draft now while keeping its placement and input state alive.
library_entry_name_flush :: proc(
    state: ^core.Euclid_General_State,
    expected_entry_id: uuid.Identifier = {}) -> bool {
    if state == nil {
        return false
    }
    draft := &state^.ui_runtime.library.entry_name
    if !draft^.active || !draft^.dirty ||
        expected_entry_id != (uuid.Identifier{}) &&
            draft^.entry_id != expected_entry_id {
        return true
    }
    set := &state^.preferences_runtime.collections_state
    placement_error := library_entry_name_target_error(set, draft)
    if placement_error != .None {
        if placement_error != .Missing_Entry {
            log.warnf("library_entry_name_draft_discarded policy=%v", placement_error)
        }
        draft^ = {}
        return true
    }
    start, end := library_entry_name_trimmed_range(
        string(draft^.value[:draft^.value_length]))
    normalized := string(draft^.value[start:end])
    return library_entry_name_commit(state, draft, normalized)
}

// Commit one normalized value and retain failures without changing accepted state.
library_entry_name_commit :: proc(
    state: ^core.Euclid_General_State,
    draft: ^viewmodel.Ui_Library_Entry_Name_Draft,
    normalized: string) -> bool {
    if library_entry_name_matches_accepted(draft, normalized) {
        library_entry_name_accept_local(draft, normalized)
        return true
    }
    mutation, mutation_error := library_entry_name_mutation(state, draft, normalized)
    if mutation_error == .None {
        mutation_error = viewpreferences.settings_save_collection_mutation(
            state, mutation)
    }
    if mutation_error != .None {
        draft^.last_admission_error = mutation_error
        draft^.debounce_remaining_seconds = LIBRARY_ENTRY_NAME_DEBOUNCE_SECONDS
        if !draft^.admission_failed {
            log.warnf("library_entry_name_admission_rejected error=%v", mutation_error)
        }
        draft^.admission_failed = true
        return false
    }
    library_entry_name_accept_local(draft, normalized)
    return true
}

// Service idle time independently of Library drawing and flush at the deadline.
library_entry_name_service :: proc(
    state: ^core.Euclid_General_State, elapsed_seconds: f32) {
    if state == nil {
        return
    }
    draft := &state^.ui_runtime.library.entry_name
    if !draft^.active || !draft^.dirty {
        return
    }
    draft^.debounce_remaining_seconds -= f64(max(elapsed_seconds, 0))
    if draft^.debounce_remaining_seconds >
        LIBRARY_ENTRY_NAME_DEBOUNCE_EPSILON_SECONDS {
        return
    }
    _ = library_entry_name_flush(state)
}

// Trim Unicode whitespace at both ends without allocating or splitting UTF-8.
library_entry_name_trimmed_range :: proc(value: string) -> (int, int) {
    first := len(value)
    last := 0
    for offset := 0; offset < len(value); {
        character, width := utf8.decode_rune_in_string(value[offset:])
        if width <= 0 {
            return 0, len(value)
        }
        if !unicode.is_space(character) {
            first = min(first, offset)
            last = offset + width
        }
        offset += width
    }
    if first == len(value) {
        return 0, 0
    }
    return first, last
}

// Compare normalized text to the last locally accepted optional override.
library_entry_name_matches_accepted :: proc(
    draft: ^viewmodel.Ui_Library_Entry_Name_Draft,
    normalized: string) -> bool {
    return normalized == string(
        draft^.accepted_name[:draft^.accepted_name_length])
}

// Retain the normalized draft after a no-op or successful local admission.
library_entry_name_accept_local :: proc(
    draft: ^viewmodel.Ui_Library_Entry_Name_Draft,
    normalized: string) {
    draft^.accepted_name = {}
    if len(normalized) > 0 {
        copy(draft^.accepted_name[:len(normalized)], transmute([]u8)normalized)
    }
    draft^.value = {}
    if len(normalized) > 0 {
        copy(draft^.value[:len(normalized)],
            draft^.accepted_name[:len(normalized)])
    }
    draft^.accepted_name_length = len(normalized)
    draft^.value_length = len(normalized)
    draft^.input.cursor_byte = min(draft^.input.cursor_byte, len(normalized))
    draft^.input.anchor_byte = min(draft^.input.anchor_byte, len(normalized))
    draft^.input.content_revision += 1
    draft^.dirty = false
    draft^.admission_failed = false
    draft^.last_admission_error = .None
    draft^.debounce_remaining_seconds = 0
}

package uilibrary

import core "../../../core"
import collections "../../../collections"
import viewmodel "../model"
import uuid "core:encoding/uuid"
import log "core:log"

// Borrow accepted mandatory text only from the current writable collection owner.
library_collection_name_prefill :: proc(
    set: ^collections.Set, id: uuid.Identifier) -> Library_Entry_Name_Prefill {
    index, failure := collections.collection_edit_index(set, id)
    if failure != .None {
        log.errorf("library_collection_name_begin_rejected policy=%v", failure)
        return {}
    }
    collection := set^.collections[index]
    return {
        target_kind = .Collection,
        valid = true,
        accepted_name = collection.name,
        accepted_name_length = collection.name_length,
    }
}

// Build a scope-qualified placement move or an adjacent custom-head swap.
tree_actions_move_mutation :: proc(
    set: ^collections.Set, id: uuid.Identifier,
    direction: collections.Move_Direction) -> (
        collections.Mutation, collections.Policy_Error) {
    if collections.find_collection(set, id) >= 0 {
        return collections.make_collection_move(set, id, direction)
    }
    identity, failure := collections.placement_identity_for_entry(set, id)
    if failure != .None {
        return {}, failure
    }
    return collections.make_placement_move(set, identity, direction)
}

// Revalidate the typed editor owner without interpreting a collection UUID as a placement.
library_entry_name_target_error :: proc(
    set: ^collections.Set,
    draft: ^viewmodel.Ui_Library_Entry_Name_Draft) -> collections.Policy_Error {
    if draft^.target_kind == .Collection {
        _, failure := collections.collection_edit_index(set, draft^.entry_id)
        return failure
    }
    _, failure := collections.placement_resolve(set, draft^.placement)
    if failure != .None || draft^.placement.collection_id ==
        collections.FAVORITES_COLLECTION_ID {
        return failure
    }
    _, failure = collections.collection_edit_index(
        set, draft^.placement.collection_id)
    return failure
}

// Build the owner's immutable rename, retaining the mandatory-name head policy.
library_entry_name_mutation :: proc(
    state: ^core.Euclid_General_State,
    draft: ^viewmodel.Ui_Library_Entry_Name_Draft,
    normalized: string) -> (collections.Mutation, collections.Mutation_Error) {
    if draft^.target_kind == .Placement {
        return collections.make_placement_name_mutation(draft^.placement, normalized)
    }
    mutation, failure := collections.make_collection_name_mutation(
        &state^.preferences_runtime.collections_state, draft^.entry_id, normalized)
    if failure == .Invalid_Name {
        return {}, .Invalid_Name
    }
    if failure != .None {
        return {}, .Policy
    }
    return mutation, .None
}

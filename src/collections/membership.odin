package collections

import uuid "core:encoding/uuid"
import storage "../core/storage"

// Resolve membership across all supported parents without imposing edit policy.
collection_animation_identity :: proc(
    set: ^Set, collection_id,
    animation_id: uuid.Identifier) -> (Placement_Identity, Policy_Error) {
    if set == nil || !set.initialized {
        return {}, .Invalid_Set
    }
    if animation_id == (uuid.Identifier{}) {
        return {}, .Invalid_Identity
    }
    if find_collection(set, collection_id) < 0 {
        return {}, .Missing_Collection
    }
    for entry in set.entries[:set.entry_count] {
        if entry.collection_id == collection_id && entry.kind == .Animation &&
            entry.animation_id == animation_id {
            return {collection_id, entry.parent_entry_id, entry.id}, .None
        }
    }
    return {}, .Not_In_Collection
}

// Capture a fresh, unnamed root placement for one writable custom destination.
make_collection_animation_add_mutation :: proc(
    set: ^Set, collection_id, entry_id,
    animation_id: uuid.Identifier) -> (Mutation, Policy_Error) {
    _, failure := collection_edit_index(set, collection_id)
    if failure != .None {
        return {}, failure
    }
    if entry_id == (uuid.Identifier{}) || animation_id == (uuid.Identifier{}) ||
        find_entry(set, entry_id) >= 0 {
        return {}, .Invalid_Identity
    }
    if collection_animation_exists(set, collection_id, animation_id, -1) {
        return {}, .Already_In_Collection
    }
    if maximum_collection_root_order(set, collection_id) == max(i64) {
        return {}, .Order_Overflow
    }
    return {
        kind = .Add_Collection_Animation,
        placement = {
            collection_id = collection_id,
            entry_id = entry_id,
        },
        entry_id = entry_id,
        animation_id = animation_id,
    }, .None
}

// Capture the exact extant animation placement, including a supported nested parent.
make_collection_animation_remove_mutation :: proc(
    set: ^Set, identity: Placement_Identity) -> (Mutation, Policy_Error) {
    _, failure := collection_edit_index(set, identity.collection_id)
    if failure != .None {
        return {}, failure
    }
    placement, policy := placement_resolve(set, identity)
    if policy != .None {
        return {}, policy
    }
    if placement.kind != .Animation {
        return {}, .Invalid_Identity
    }
    return {
        kind = .Remove_Collection_Animation,
        placement = identity,
        entry_id = identity.entry_id,
        animation_id = placement.animation_id,
    }, .None
}

// Append after the last live root without borrowing a nested child's order.
maximum_collection_root_order :: proc(
    set: ^Set, collection_id: uuid.Identifier) -> i64 {
    maximum_order: i64 = -1
    for entry in set.entries[:set.entry_count] {
        if entry.collection_id == collection_id &&
            entry.parent_entry_id == (uuid.Identifier{}) &&
            entry.sibling_order > maximum_order {
            maximum_order = entry.sibling_order
        }
    }
    return maximum_order
}

// Revalidate immutable add scope and acquire a new placement with no historical alias.
apply_collection_animation_add_mutation :: proc(
    set: ^Set, mutation: Mutation) -> Mutation_Error {
    if mutation.placement.entry_id != mutation.entry_id ||
        mutation.placement.parent_entry_id != (uuid.Identifier{}) {
        return .Invalid_Entry
    }
    _, failure := make_collection_animation_add_mutation(
        set, mutation.placement.collection_id, mutation.entry_id, mutation.animation_id)
    if failure != .None {
        return .Policy
    }
    appended := append_entry(set, {
        id = mutation.entry_id,
        collection_id = mutation.placement.collection_id,
        sibling_order = maximum_collection_root_order(
            set, mutation.placement.collection_id) + 1,
        kind = .Animation,
        animation_id = mutation.animation_id,
    })
    if appended == .Allocation_Failed || appended == .Capacity {
        return .Allocation_Failed
    }
    if appended != .None {
        return .Policy
    }
    return .None
}

// Remove only the captured animation placement; never retarget a stale membership toggle.
apply_collection_animation_remove_mutation :: proc(
    set: ^Set, mutation: Mutation) -> Mutation_Error {
    if mutation.entry_id != mutation.placement.entry_id ||
        mutation.animation_id == (uuid.Identifier{}) {
        return .Invalid_Entry
    }
    current, failure := make_collection_animation_remove_mutation(
        set, mutation.placement)
    if failure != .None || current.animation_id != mutation.animation_id {
        return .Policy
    }
    index := find_entry(set, mutation.entry_id)
    if placement_remove_at(set, index) != .None {
        return .Policy
    }
    return .None
}

// Retire one leaf's owned labels and repair lookup positions without allocation.
placement_remove_at :: proc(set: ^Set, index: int) -> Policy_Error {
    allocator := storage.tlsf_owner_allocator(&set.allocator)
    delete(set.entries[index].custom_name, allocator)
    delete(set.entries[index].canonical_name, allocator)
    for move in index..<(set.entry_count - 1) {
        set.entries[move] = set.entries[move + 1]
    }
    set.entry_count -= 1
    set.entries[set.entry_count] = {}
    if !entry_index_rebuild(set) {
        return .Invalid_Set
    }
    return .None
}

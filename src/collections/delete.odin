package collections

import uuid "core:encoding/uuid"
import storage "../core/storage"

// Capture deletion of one writable custom owner, never the protected system destination.
make_collection_delete_mutation :: proc(
    set: ^Set, id: uuid.Identifier) -> (Mutation, Policy_Error) {
    _, failure := collection_edit_index(set, id)
    if failure != .None {
        return {}, failure
    }
    return {
        kind = .Delete_Collection,
        collection_id = id,
    }, .None
}

// Retire every owned placement and label before compacting the head; no allocation occurs.
apply_collection_delete_mutation :: proc(
    set: ^Set, mutation: Mutation) -> Mutation_Error {
    index, failure := collection_edit_index(set, mutation.collection_id)
    if failure != .None {
        return .Policy
    }
    collection_delete_entries(set, mutation.collection_id)
    allocator := storage.tlsf_owner_allocator(&set.allocator)
    delete(set.collections[index].name, allocator)
    for move in index..<set.collection_count - 1 {
        set.collections[move] = set.collections[move + 1]
    }
    set.collection_count -= 1
    set.collections[set.collection_count] = {}
    for &slot in set.collection_index {
        slot = {}
    }
    for head, position in set.collections[:set.collection_count] {
        inserted := collection_index_insert(set, head.id, position)
        assert(inserted)
    }
    rebuilt := entry_index_rebuild(set)
    assert(rebuilt)
    return .None
}

// Compact all placements of the deleted owner, including groups and unavailable animations.
collection_delete_entries :: proc(set: ^Set, id: uuid.Identifier) {
    allocator := storage.tlsf_owner_allocator(&set.allocator)
    retained := 0
    previous := set.entry_count
    for entry in set.entries[:previous] {
        if entry.collection_id == id {
            delete(entry.custom_name, allocator)
            delete(entry.canonical_name, allocator)
        } else {
            set.entries[retained] = entry
            retained += 1
        }
    }
    for index in retained..<previous {
        set.entries[index] = {}
    }
    set.entry_count = retained
}

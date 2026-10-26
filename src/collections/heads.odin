package collections

import uuid "core:encoding/uuid"
import storage "../core/storage"

// Resolve a writable custom head without granting management rights to Favorites.
collection_edit_index :: proc(
    set: ^Set, id: uuid.Identifier) -> (int, Policy_Error) {
    if validate(set) != .None {
        return -1, .Invalid_Set
    }
    index := find_collection(set, id)
    if index < 0 {
        return -1, .Missing_Collection
    }
    if set.collections[index].role != .User || set.collections[index].is_read_only {
        return -1, .Read_Only
    }
    return index, .None
}

// Capture a mandatory bounded name, copying bytes for ordered asynchronous replay.
make_collection_name_mutation :: proc(
    set: ^Set, id: uuid.Identifier, name: string) -> (Mutation, Policy_Error) {
    _, failure := collection_edit_index(set, id)
    if failure != .None {
        return {}, failure
    }
    if !collection_name_bytes_are_valid(transmute([]u8)name, len(name)) {
        return {}, .Invalid_Name
    }
    mutation: Mutation = {
        kind = .Set_Collection_Name,
        collection_id = id,
        collection_name_length = len(name),
    }
    copy(mutation.collection_name[:], transmute([]u8)name)
    return mutation, .None
}

// Find the adjacent custom head in durable order, excluding the protected system head.
collection_neighbor :: proc(
    set: ^Set, id: uuid.Identifier,
    direction: Move_Direction) -> (uuid.Identifier, Policy_Error) {
    if !move_direction_is_valid(direction) {
        return {}, .Invalid_Direction
    }
    index, failure := collection_edit_index(set, id)
    if failure != .None {
        return {}, failure
    }
    neighbor := -1
    order := set.collections[index].order
    for candidate, position in set.collections[:set.collection_count] {
        if candidate.role != .User || position == index {
            continue
        }
        if direction == .Up && candidate.order < order &&
            (neighbor < 0 || candidate.order > set.collections[neighbor].order) ||
            direction == .Down && candidate.order > order &&
            (neighbor < 0 || candidate.order < set.collections[neighbor].order) {
            neighbor = position
        }
    }
    if neighbor < 0 {
        return {}, .No_Neighbor
    }
    if set.collections[neighbor].is_read_only {
        return {}, .Read_Only
    }
    return set.collections[neighbor].id, .None
}

// Capture the exact adjacent UUID so stale or reordered replays cannot move another head.
make_collection_move :: proc(
    set: ^Set, id: uuid.Identifier,
    direction: Move_Direction) -> (Mutation, Policy_Error) {
    sibling, failure := collection_neighbor(set, id, direction)
    if failure != .None {
        return {}, failure
    }
    return {
        kind = .Reorder_Collections,
        collection_id = id,
        sibling_collection_id = sibling,
        direction = direction,
    }, .None
}

// Allocate replacement text before retiring the accepted label or changing its owner.
apply_collection_name_mutation :: proc(
    set: ^Set, mutation: Mutation) -> Mutation_Error {
    name := mutation.collection_name
    if !collection_name_bytes_are_valid(name[:], mutation.collection_name_length) {
        return .Invalid_Name
    }
    index, failure := collection_edit_index(set, mutation.collection_id)
    if failure != .None {
        return .Policy
    }
    collection := &set.collections[index]
    value := name[:mutation.collection_name_length]
    if string(collection.name[:collection.name_length]) == string(value) {
        return .None
    }
    allocator := storage.tlsf_owner_allocator(&set.allocator)
    replacement, allocation_error := make([]u8, len(value), allocator)
    if allocation_error != nil {
        return .Allocation_Failed
    }
    copy(replacement, value)
    delete(collection.name, allocator)
    collection.name, collection.name_length = replacement, len(value)
    return .None
}

// Swap existing positive orders without arithmetic, overflow, or identity replacement.
apply_collection_move_mutation :: proc(
    set: ^Set, mutation: Mutation) -> Mutation_Error {
    sibling, failure := collection_neighbor(
        set, mutation.collection_id, mutation.direction)
    if failure != .None || sibling != mutation.sibling_collection_id {
        return .Policy
    }
    index := find_collection(set, mutation.collection_id)
    other := find_collection(set, sibling)
    set.collections[index].order, set.collections[other].order =
        set.collections[other].order, set.collections[index].order
    return .None
}

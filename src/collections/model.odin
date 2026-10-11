package collections

import uuid "core:encoding/uuid"

COLLECTION_CAPACITY :: 512
ENTRY_CAPACITY :: 512
MUTATION_CAPACITY :: 512
COLLECTION_NAME_MAX_BYTES :: 256
FAVORITES_COLLECTION_ID :: uuid.Identifier{
    0x45, 0x55, 0x43, 0x4c, 0x49, 0x44, 0x00, 0x00,
    0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
}

Role :: enum u8 {
    User,
    Favorites,
}

Entry_Kind :: enum u8 {
    Group,
    Animation,
}

Collection :: struct {
    id: uuid.Identifier,
    role: Role,
    name: [COLLECTION_NAME_MAX_BYTES]u8,
    name_length: int,
    order: i64,
    is_read_only: bool,
}

Entry :: struct {
    id: uuid.Identifier,
    collection_id: uuid.Identifier,
    parent_entry_id: uuid.Identifier,
    sibling_order: i64,
    kind: Entry_Kind,
    animation_id: uuid.Identifier,
}

// Bounded, pointer-free snapshot of user collection placements.
Set :: struct {
    collections: [COLLECTION_CAPACITY]Collection,
    collection_count: int,
    entries: [ENTRY_CAPACITY]Entry,
    entry_count: int,
}

Validation_Error :: enum u8 {
    None,
    Capacity,
    Missing_Favorites,
    Duplicate_Favorites,
    Invalid_Collection,
    Duplicate_Collection,
    Invalid_Entry,
    Duplicate_Entry,
    Missing_Collection,
    Missing_Parent,
    Cross_Collection_Parent,
    Duplicate_Order,
    Cycle,
    Duplicate_Favorite_Animation,
}

Policy_Error :: enum u8 {
    None,
    Invalid_Set,
    Missing_Favorites,
    Read_Only,
    Invalid_Identity,
    Already_Favorited,
    Not_Favorited,
    Capacity,
    Order_Overflow,
}

Mutation_Kind :: enum u8 {
    Add_Favorite,
    Remove_Favorite,
}

// One ordered Favorites operation retaining entry identity across retry.
Mutation :: struct {
    kind: Mutation_Kind,
    entry_id: uuid.Identifier,
    animation_id: uuid.Identifier,
}

Mutation_Error :: enum u8 {
    None,
    Invalid_Kind,
    Invalid_Entry,
    Policy,
    Capacity,
}

// Validate identifiers, hierarchy, sibling order, and Favorites-specific invariants.
validate :: proc(set: ^Set) -> Validation_Error {
    if set == nil || set.collection_count < 0 ||
        set.collection_count > COLLECTION_CAPACITY ||
        set.entry_count < 0 || set.entry_count > ENTRY_CAPACITY {
        return .Capacity
    }
    for index in 0..<set.collection_count {
        error := validate_collection(set, index)
        if error != .None {
            return error
        }
    }
    favorites_index := find_favorites(set)
    if favorites_index < 0 {
        return .Missing_Favorites
    }
    for index in 0..<set.entry_count {
        error := validate_entry(set, index)
        if error != .None {
            return error
        }
    }
    return .None
}

// Validate one collection record and its stable identity.
validate_collection :: proc(set: ^Set, index: int) -> Validation_Error {
    collection := &set.collections[index]
    if collection.id == (uuid.Identifier{}) || collection.order < 0 {
        return .Invalid_Collection
    }
    error := validate_collection_fields(collection)
    if error != .None {
        return error
    }
    for other in 0..<index {
        if set.collections[other].id == collection.id {
            return .Duplicate_Collection
        }
        if set.collections[other].role == .Favorites &&
            collection.role == .Favorites {
            return .Duplicate_Favorites
        }
    }
    return .None
}

// Enforce role-specific names and keep Favorites permanently editable.
validate_collection_fields :: proc(collection: ^Collection) -> Validation_Error {
    if collection^.role == .Favorites {
        if collection^.id != FAVORITES_COLLECTION_ID ||
            collection^.is_read_only || collection^.name_length != 0 {
            return .Invalid_Collection
        }
    } else if collection^.role == .User {
        if collection^.name_length < 1 ||
            collection^.name_length > COLLECTION_NAME_MAX_BYTES {
            return .Invalid_Collection
        }
        for character in collection^.name[:collection^.name_length] {
            if character == 0 {
                return .Invalid_Collection
            }
        }
    } else {
        return .Invalid_Collection
    }
    return .None
}

// Validate one placement, its parent chain, and collection-specific policy.
validate_entry :: proc(set: ^Set, index: int) -> Validation_Error {
    entry := &set.entries[index]
    if entry.id == (uuid.Identifier{}) || entry.sibling_order < 0 ||
        !entry_kind_is_valid(entry^) {
        return .Invalid_Entry
    }
    collection_index := find_collection(set, entry.collection_id)
    if collection_index < 0 {
        return .Missing_Collection
    }
    if !entry_has_unique_position(set, index) {
        return .Duplicate_Order
    }
    for other in 0..<index {
        if set.entries[other].id == entry.id {
            return .Duplicate_Entry
        }
    }
    if entry.parent_entry_id != (uuid.Identifier{}) {
        parent_error := validate_parent_link(set, index)
        if parent_error != .None {
            return parent_error
        }
    }
    if set.collections[collection_index].role == .Favorites {
        return validate_favorite_entry(set, index)
    }
    return .None
}

// Validate one parent relationship and detect cycles through its ancestors.
validate_parent_link :: proc(set: ^Set, index: int) -> Validation_Error {
    entry := set.entries[index]
    parent_index := find_entry(set, entry.parent_entry_id)
    if parent_index < 0 {
        return .Missing_Parent
    }
    if set.entries[parent_index].collection_id != entry.collection_id {
        return .Cross_Collection_Parent
    }
    if has_parent_cycle(set, index) {
        return .Cycle
    }
    return .None
}

// Enforce Favorites leaf placement and unique animation membership.
validate_favorite_entry :: proc(set: ^Set, index: int) -> Validation_Error {
    entry := set.entries[index]
    if entry.kind != .Animation ||
        entry.parent_entry_id != (uuid.Identifier{}) {
        return .Invalid_Entry
    }
    if favorites_animation_exists(set, entry.animation_id, index) {
        return .Duplicate_Favorite_Animation
    }
    return .None
}

// Add one unique animation placement at the end of flat Favorites.
favorites_add :: proc(
    set: ^Set, entry_id, animation_id: uuid.Identifier) -> Policy_Error {
    if validate(set) != .None {
        return .Invalid_Set
    }
    favorites_index := find_favorites(set)
    if favorites_index < 0 {
        return .Missing_Favorites
    }
    if set.collections[favorites_index].is_read_only {
        return .Read_Only
    }
    if entry_id == (uuid.Identifier{}) || animation_id == (uuid.Identifier{}) ||
        find_entry(set, entry_id) >= 0 {
        return .Invalid_Identity
    }
    if favorites_animation_exists(set, animation_id, -1) {
        return .Already_Favorited
    }
    if set.entry_count >= ENTRY_CAPACITY {
        return .Capacity
    }
    maximum_order := maximum_favorites_order(set)
    if maximum_order == max(i64) {
        return .Order_Overflow
    }
    set.entries[set.entry_count] = {
        id = entry_id,
        collection_id = FAVORITES_COLLECTION_ID,
        sibling_order = maximum_order + 1,
        kind = .Animation,
        animation_id = animation_id,
    }
    set.entry_count += 1
    return .None
}

// Find the highest extant Favorites root position for append semantics.
maximum_favorites_order :: proc(set: ^Set) -> i64 {
    maximum_order: i64 = -1
    for entry in set.entries[:set.entry_count] {
        if entry.collection_id == FAVORITES_COLLECTION_ID &&
            entry.parent_entry_id == (uuid.Identifier{}) &&
            entry.sibling_order > maximum_order {
            maximum_order = entry.sibling_order
        }
    }
    return maximum_order
}

// Remove one Favorites placement by entry identity without changing playback identity.
favorites_remove :: proc(set: ^Set, entry_id: uuid.Identifier) -> Policy_Error {
    if validate(set) != .None {
        return .Invalid_Set
    }
    favorites_index := find_favorites(set)
    if favorites_index < 0 {
        return .Missing_Favorites
    }
    if set.collections[favorites_index].is_read_only {
        return .Read_Only
    }
    for index in 0..<set.entry_count {
        if set.entries[index].id == entry_id &&
            set.entries[index].collection_id == FAVORITES_COLLECTION_ID {
            for move in index..<(set.entry_count - 1) {
                set.entries[move] = set.entries[move + 1]
            }
            set.entry_count -= 1
            set.entries[set.entry_count] = {}
            return .None
        }
    }
    return .Not_Favorited
}

// Replay one accepted structural operation against a validated snapshot.
apply_mutation :: proc(set: ^Set, mutation: Mutation) -> Mutation_Error {
    switch mutation.kind {
    case .Add_Favorite:
        if mutation.entry_id == (uuid.Identifier{}) ||
            mutation.animation_id == (uuid.Identifier{}) {
            return .Invalid_Entry
        }
        if favorites_add(set, mutation.entry_id, mutation.animation_id) != .None {
            return .Policy
        }
        return .None
    case .Remove_Favorite:
        if mutation.entry_id == (uuid.Identifier{}) {
            return .Invalid_Entry
        }
        if favorites_remove(set, mutation.entry_id) != .None {
            return .Policy
        }
        return .None
    }
    return .Invalid_Kind
}

// Initialize a valid empty snapshot containing the system Favorites collection.
initialize :: proc(set: ^Set) {
    set^ = {}
    set^.collections[0] = {
        id = FAVORITES_COLLECTION_ID,
        role = .Favorites,
    }
    set^.collection_count = 1
}

// Find the collection carrying the stable Favorites system role.
find_favorites :: proc(set: ^Set) -> int {
    for index in 0..<set.collection_count {
        if set.collections[index].role == .Favorites {
            return index
        }
    }
    return -1
}

// Find a collection by its persisted UUID, or return -1.
find_collection :: proc(set: ^Set, id: uuid.Identifier) -> int {
    for index in 0..<set.collection_count {
        if set.collections[index].id == id {
            return index
        }
    }
    return -1
}

// Find an entry by its placement UUID, or return -1.
find_entry :: proc(set: ^Set, id: uuid.Identifier) -> int {
    for index in 0..<set.entry_count {
        if set.entries[index].id == id {
            return index
        }
    }
    return -1
}

// Enforce the storage shape associated with a placement kind.
entry_kind_is_valid :: proc(entry: Entry) -> bool {
    if entry.kind == .Animation {
        return entry.animation_id != (uuid.Identifier{})
    }
    if entry.kind == .Group {
        return entry.animation_id == (uuid.Identifier{})
    }
    return false
}

// Reject sibling positions duplicated within one collection parent scope.
entry_has_unique_position :: proc(set: ^Set, index: int) -> bool {
    entry := set.entries[index]
    for other in 0..<index {
        candidate := set.entries[other]
        if candidate.collection_id == entry.collection_id &&
            candidate.parent_entry_id == entry.parent_entry_id &&
            candidate.sibling_order == entry.sibling_order {
            return false
        }
    }
    return true
}

// Follow ancestors with a bounded walk and reject any cycle.
has_parent_cycle :: proc(set: ^Set, index: int) -> bool {
    current := set.entries[index].parent_entry_id
    for _ in 0..<set.entry_count {
        if current == set.entries[index].id {
            return true
        }
        parent_index := find_entry(set, current)
        if parent_index < 0 {
            return false
        }
        current = set.entries[parent_index].parent_entry_id
        if current == (uuid.Identifier{}) {
            return false
        }
    }
    return true
}

// Check Favorites uniqueness by animation identity, not placement identity.
favorites_animation_exists :: proc(
    set: ^Set, animation_id: uuid.Identifier, except_index: int) -> bool {
    for index in 0..<set.entry_count {
        entry := set.entries[index]
        if index != except_index && entry.collection_id == FAVORITES_COLLECTION_ID &&
            entry.animation_id == animation_id {
            return true
        }
    }
    return false
}

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

Move_Direction :: enum u8 {
    Up,
    Down,
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
    Missing_Entry,
    Missing_Sibling,
    Missing_Collection,
    Different_Scope,
    Not_Adjacent,
    No_Neighbor,
    Invalid_Direction,
}

Mutation_Kind :: enum u8 {
    Add_Favorite,
    Remove_Favorite,
    Reorder_Siblings,
}

// One immutable structural operation retaining placement identities across retry.
Mutation :: struct {
    kind: Mutation_Kind,
    entry_id: uuid.Identifier,
    animation_id: uuid.Identifier,
    sibling_entry_id: uuid.Identifier,
    direction: Move_Direction,
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

// Find the immediate editable sibling above or below a placement.
sibling_neighbor :: proc(
    set: ^Set, entry_id: uuid.Identifier,
    direction: Move_Direction) -> (uuid.Identifier, Policy_Error) {
    if validate(set) != .None {
        return {}, .Invalid_Set
    }
    if entry_id == (uuid.Identifier{}) {
        return {}, .Invalid_Identity
    }
    if !move_direction_is_valid(direction) {
        return {}, .Invalid_Direction
    }
    entry_index := find_entry(set, entry_id)
    if entry_index < 0 {
        return {}, .Missing_Entry
    }
    entry := set.entries[entry_index]
    collection_index := find_collection(set, entry.collection_id)
    if set.collections[collection_index].is_read_only {
        return {}, .Read_Only
    }
    neighbor_index := sibling_neighbor_index(set, entry, direction)
    if neighbor_index < 0 {
        return {}, .No_Neighbor
    }
    return set.entries[neighbor_index].id, .None
}

// Capture one immutable move of a placement into its current adjacent position.
make_sibling_move :: proc(
    set: ^Set, entry_id: uuid.Identifier,
    direction: Move_Direction) -> (Mutation, Policy_Error) {
    sibling_id, failure := sibling_neighbor(set, entry_id, direction)
    if failure != .None {
        return {}, failure
    }
    return Mutation{
        kind = .Reorder_Siblings,
        entry_id = entry_id,
        sibling_entry_id = sibling_id,
        direction = direction,
    }, .None
}

// Enumerate ordered backing-array indexes into caller-owned storage.
ordered_siblings :: proc(
    set: ^Set,
    collection_id, parent_entry_id: uuid.Identifier,
    destination: []int) -> (int, Policy_Error) {
    if validate(set) != .None {
        return 0, .Invalid_Set
    }
    scope_failure := ordered_siblings_scope_validate(
        set, collection_id, parent_entry_id)
    if scope_failure != .None {
        return 0, scope_failure
    }
    sibling_count := count_siblings(set, collection_id, parent_entry_id)
    if sibling_count > len(destination) {
        return 0, .Capacity
    }
    count := 0
    for index in 0..<set.entry_count {
        entry := set.entries[index]
        if entry.collection_id == collection_id &&
            entry.parent_entry_id == parent_entry_id {
            destination[count] = index
            count += 1
        }
    }
    sort_siblings_by_order(set, destination[:count])
    return count, .None
}

// Validate a requested collection-parent scope before ordered enumeration.
ordered_siblings_scope_validate :: proc(
    set: ^Set, collection_id, parent_entry_id: uuid.Identifier) -> Policy_Error {
    if collection_id == (uuid.Identifier{}) {
        return .Invalid_Identity
    }
    if find_collection(set, collection_id) < 0 {
        return .Missing_Collection
    }
    if parent_entry_id == (uuid.Identifier{}) {
        return .None
    }
    parent_index := find_entry(set, parent_entry_id)
    if parent_index < 0 {
        return .Missing_Entry
    }
    if set.entries[parent_index].collection_id != collection_id {
        return .Different_Scope
    }
    return .None
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
    case .Reorder_Siblings:
        if mutation.entry_id == (uuid.Identifier{}) ||
            mutation.sibling_entry_id == (uuid.Identifier{}) {
            return .Invalid_Entry
        }
        if sibling_move_apply(set, mutation) != .None {
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

// Find the nearest sibling index in one validated collection-parent scope.
sibling_neighbor_index :: proc(
    set: ^Set, entry: Entry, direction: Move_Direction) -> int {
    neighbor_index := -1
    for index in 0..<set.entry_count {
        candidate := set.entries[index]
        if candidate.collection_id != entry.collection_id ||
            candidate.parent_entry_id != entry.parent_entry_id {
            continue
        }
        if direction == .Up && candidate.sibling_order < entry.sibling_order &&
            (neighbor_index < 0 ||
                candidate.sibling_order > set.entries[neighbor_index].sibling_order) {
            neighbor_index = index
        } else if direction == .Down &&
            candidate.sibling_order > entry.sibling_order &&
            (neighbor_index < 0 ||
                candidate.sibling_order < set.entries[neighbor_index].sibling_order) {
            neighbor_index = index
        }
    }
    return neighbor_index
}

// Apply an immutable move only while its recorded placements remain adjacent.
sibling_move_apply :: proc(set: ^Set, mutation: Mutation) -> Policy_Error {
    if validate(set) != .None {
        return .Invalid_Set
    }
    if !move_direction_is_valid(mutation.direction) {
        return .Invalid_Direction
    }
    if mutation.entry_id == mutation.sibling_entry_id {
        return .Invalid_Identity
    }
    entry_index := find_entry(set, mutation.entry_id)
    sibling_index := find_entry(set, mutation.sibling_entry_id)
    if entry_index < 0 {
        return .Missing_Entry
    }
    if sibling_index < 0 {
        return .Missing_Sibling
    }
    entry := set.entries[entry_index]
    sibling := set.entries[sibling_index]
    if entry.collection_id != sibling.collection_id ||
        entry.parent_entry_id != sibling.parent_entry_id {
        return .Different_Scope
    }
    collection_index := find_collection(set, entry.collection_id)
    if set.collections[collection_index].is_read_only {
        return .Read_Only
    }
    if sibling_neighbor_index(set, entry, mutation.direction) != sibling_index {
        return .Not_Adjacent
    }
    set.entries[entry_index].sibling_order = sibling.sibling_order
    set.entries[sibling_index].sibling_order = entry.sibling_order
    return .None
}

// Count siblings without depending on their backing-array arrangement.
count_siblings :: proc(
    set: ^Set, collection_id, parent_entry_id: uuid.Identifier) -> int {
    count := 0
    for entry in set.entries[:set.entry_count] {
        if entry.collection_id == collection_id &&
            entry.parent_entry_id == parent_entry_id {
            count += 1
        }
    }
    return count
}

// Sort bounded backing-array indexes by their authoritative order values.
sort_siblings_by_order :: proc(set: ^Set, indexes: []int) {
    if len(indexes) < 2 {
        return
    }
    for index in 1..<len(indexes) {
        entry_index := indexes[index]
        position := index
        for position > 0 &&
            set.entries[indexes[position - 1]].sibling_order >
                set.entries[entry_index].sibling_order {
            indexes[position] = indexes[position - 1]
            position -= 1
        }
        indexes[position] = entry_index
    }
}

// Reject enum values outside the two supported ordering directions.
move_direction_is_valid :: proc(direction: Move_Direction) -> bool {
    return direction == .Up || direction == .Down
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

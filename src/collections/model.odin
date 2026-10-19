package collections

import uuid "core:encoding/uuid"
import storage "../core/storage"
import "base:runtime"
import "core:unicode/utf8"

// Transitional caller scratch bound; the collection model itself is unbounded.
ENTRY_INDEX_BUFFER_CAPACITY :: 512
MUTATION_CAPACITY :: 512
COLLECTION_NAME_MAX_BYTES :: 256
ENTRY_NAME_MAX_BYTES :: 256
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
    name: []u8,
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
    custom_name: []u8,
    custom_name_length: int,
    canonical_name: []u8,
    canonical_name_length: int,
}

Placement_Identity :: struct {
    collection_id: uuid.Identifier,
    parent_entry_id: uuid.Identifier,
    entry_id: uuid.Identifier,
}

Placement_View :: struct {
    identity: Placement_Identity,
    kind: Entry_Kind,
    animation_id: uuid.Identifier,
    sibling_order: i64,
    custom_name: []u8,
    custom_name_length: int,
    canonical_name: []u8,
    canonical_name_length: int,
}

Index_Slot :: struct {
    id: uuid.Identifier,
    value_index: int,
    occupied: bool,
}

// Owned collection records and reusable lookup storage for one Library lifetime.
Set :: struct {
    allocator: storage.Tlsf_Owner,
    collections: []Collection,
    collection_count: int,
    entries: []Entry,
    entry_count: int,
    collection_index: []Index_Slot,
    entry_index: []Index_Slot,
    initialized: bool,
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
    Duplicate_Collection_Animation,
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
    Invalid_Name,
    Allocation_Failed,
    Already_In_Collection,
    Not_In_Collection,
}

Mutation_Kind :: enum u8 {
    Add_Favorite,
    Remove_Favorite,
    Reorder_Siblings,
    Set_Entry_Name,
    Create_Collection,
    Set_Collection_Name,
    Reorder_Collections,
    Delete_Collection,
    Add_Collection_Animation,
    Remove_Collection_Animation,
}

// One immutable collection operation retaining placement identity across retry.
Mutation :: struct {
    kind: Mutation_Kind,
    placement: Placement_Identity,
    entry_id: uuid.Identifier,
    animation_id: uuid.Identifier,
    sibling_entry_id: uuid.Identifier,
    direction: Move_Direction,
    custom_name: [ENTRY_NAME_MAX_BYTES]u8,
    custom_name_length: int,
    collection_id: uuid.Identifier,
    collection_name: [COLLECTION_NAME_MAX_BYTES]u8,
    collection_name_length: int,
    sibling_collection_id: uuid.Identifier,
}

Mutation_Error :: enum u8 {
    None,
    Invalid_Kind,
    Invalid_Entry,
    Invalid_Name,
    Policy,
    Capacity,
    Allocation_Failed,
}

Sibling_Move_Resolution :: struct {
    entry_index: int,
    sibling_index: int,
    failure: Policy_Error,
}

// Validate identifiers, hierarchy, sibling order, and collection-wide membership.
validate :: proc(set: ^Set) -> Validation_Error {
    if set == nil || !set.initialized || set.collection_count < 0 ||
        set.collection_count > len(set.collections) ||
        set.entry_count < 0 || set.entry_count > len(set.entries) {
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
        if set.collections[other].order == collection.order {
            return .Duplicate_Order
        }
    }
    return .None
}

// Enforce role-specific names and keep Favorites permanently editable.
validate_collection_fields :: proc(collection: ^Collection) -> Validation_Error {
    if collection^.role == .Favorites {
        if collection^.id != FAVORITES_COLLECTION_ID ||
            collection^.is_read_only || collection^.name_length != 0 ||
            collection^.order != 0 {
            return .Invalid_Collection
        }
    } else if collection^.role == .User {
        if collection^.id == FAVORITES_COLLECTION_ID || collection^.order <= 0 ||
            !collection_name_bytes_are_valid(
                collection^.name, collection^.name_length) {
            return .Invalid_Collection
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
        !entry_kind_is_valid(entry^) || !entry_custom_name_is_valid(entry) {
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
    if entry.kind == .Animation &&
        collection_animation_exists(
            set, entry.collection_id, entry.animation_id, index) {
        return .Duplicate_Collection_Animation
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
    maximum_order := maximum_favorites_order(set)
    if maximum_order == max(i64) {
        return .Order_Overflow
    }
    return append_entry(set, Entry{
        id = entry_id,
        collection_id = FAVORITES_COLLECTION_ID,
        sibling_order = maximum_order + 1,
        kind = .Animation,
        animation_id = animation_id,
    })
}

// Find the highest extant Favorites root position for append semantics.
maximum_favorites_order :: proc(set: ^Set) -> i64 {
    return maximum_collection_root_order(set, FAVORITES_COLLECTION_ID)
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
            return placement_remove_at(set, index)
        }
    }
    return .Not_Favorited
}

// Capture the parent and collection scope associated with one placement UUID.
placement_identity_for_entry :: proc(
    set: ^Set, entry_id: uuid.Identifier) -> (Placement_Identity, Policy_Error) {
    if set == nil || !set^.initialized {
        return {}, .Invalid_Set
    }
    entry_index := find_entry(set, entry_id)
    if entry_index < 0 {
        return {}, .Missing_Entry
    }
    entry := set.entries[entry_index]
    if find_collection(set, entry.collection_id) < 0 {
        return {}, .Missing_Collection
    }
    return Placement_Identity{entry.collection_id, entry.parent_entry_id, entry.id}, .None
}

// Resolve one placement only while its collection and parent identity still match.
placement_resolve :: proc(
    set: ^Set, identity: Placement_Identity) -> (Placement_View, Policy_Error) {
    entry_index, failure := placement_resolve_index(set, identity)
    if failure != .None {
        return {}, failure
    }
    entry := set.entries[entry_index]
    return Placement_View{
        identity = identity,
        kind = entry.kind,
        animation_id = entry.animation_id,
        sibling_order = entry.sibling_order,
        custom_name = entry.custom_name,
        custom_name_length = entry.custom_name_length,
        canonical_name = entry.canonical_name,
        canonical_name_length = entry.canonical_name_length,
    }, .None
}

// Validate one indexed placement's captured scope without scanning the full Set.
placement_resolve_index :: proc(
    set: ^Set, identity: Placement_Identity) -> (int, Policy_Error) {
    if set == nil || !set^.initialized {
        return -1, .Invalid_Set
    }
    if identity.entry_id == (uuid.Identifier{}) ||
        identity.collection_id == (uuid.Identifier{}) {
        return -1, .Invalid_Identity
    }
    entry_index := find_entry(set, identity.entry_id)
    if entry_index < 0 {
        return -1, .Missing_Entry
    }
    entry := set.entries[entry_index]
    if entry.collection_id != identity.collection_id ||
        entry.parent_entry_id != identity.parent_entry_id {
        return -1, .Different_Scope
    }
    if !entry_custom_name_is_valid(&entry) {
        return -1, .Invalid_Set
    }
    if find_collection(set, entry.collection_id) < 0 {
        return -1, .Missing_Collection
    }
    if entry.parent_entry_id != (uuid.Identifier{}) {
        parent_index := find_entry(set, entry.parent_entry_id)
        if parent_index < 0 {
            return -1, .Missing_Entry
        }
        if set.entries[parent_index].collection_id != entry.collection_id {
            return -1, .Different_Scope
        }
    }
    return entry_index, .None
}

// Find one name/order action neighbor through its placement-qualified scope.
placement_sibling_neighbor :: proc(
    set: ^Set, identity: Placement_Identity,
    direction: Move_Direction) -> (uuid.Identifier, Policy_Error) {
    if !move_direction_is_valid(direction) {
        return {}, .Invalid_Direction
    }
    _, failure := placement_resolve(set, identity)
    if failure != .None {
        return {}, failure
    }
    entry_index := find_entry(set, identity.entry_id)
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

// Capture one immutable move against exact collection and parent identity.
make_placement_move :: proc(
    set: ^Set, identity: Placement_Identity,
    direction: Move_Direction) -> (Mutation, Policy_Error) {
    sibling_id, failure := placement_sibling_neighbor(set, identity, direction)
    if failure != .None {
        return {}, failure
    }
    return Mutation{
        kind = .Reorder_Siblings,
        placement = identity,
        entry_id = identity.entry_id,
        sibling_entry_id = sibling_id,
        direction = direction,
    }, .None
}

// Capture a bounded optional name update against exact placement scope.
make_placement_name_mutation :: proc(
    identity: Placement_Identity, name: string) -> (Mutation, Mutation_Error) {
    if identity.collection_id == (uuid.Identifier{}) ||
        identity.entry_id == (uuid.Identifier{}) {
        return {}, .Invalid_Entry
    }
    name_bytes := transmute([]u8)name
    if !entry_name_bytes_are_valid(name_bytes, len(name)) {
        return {}, .Invalid_Name
    }
    mutation := Mutation{
        kind = .Set_Entry_Name,
        placement = identity,
        entry_id = identity.entry_id,
        custom_name_length = len(name),
    }
    if len(name) > 0 {
        copy(mutation.custom_name[:len(name)], name_bytes)
    }
    return mutation, .None
}

// Capture a creation with owned bounded text; names are labels, never identity keys.
make_collection_create_mutation :: proc(
    set: ^Set, id: uuid.Identifier, name: string) -> (Mutation, Policy_Error) {
    if validate(set) != .None {
        return {}, .Invalid_Set
    }
    if id == (uuid.Identifier{}) || id == FAVORITES_COLLECTION_ID ||
        find_collection(set, id) >= 0 {
        return {}, .Invalid_Identity
    }
    name_bytes := transmute([]u8)name
    if !collection_name_bytes_are_valid(name_bytes, len(name)) {
        return {}, .Invalid_Name
    }
    if maximum_collection_order(set) == max(i64) {
        return {}, .Order_Overflow
    }
    mutation := Mutation{
        kind = .Create_Collection,
        collection_id = id,
        collection_name_length = len(name),
    }
    copy(mutation.collection_name[:], name_bytes)
    return mutation, .None
}

// Find the append position without compacting accepted custom collection orders.
maximum_collection_order :: proc(set: ^Set) -> i64 {
    maximum: i64
    for collection in set^.collections[:set^.collection_count] {
        maximum = max(maximum, collection.order)
    }
    return maximum
}

// Require a nonempty UTF-8 label with no embedded NUL and the collection byte bound.
collection_name_bytes_are_valid :: proc(name: []u8, name_length: int) -> bool {
    if name_length < 1 || name_length > COLLECTION_NAME_MAX_BYTES ||
        name_length > len(name) || !utf8.valid_string(string(name[:name_length])) {
        return false
    }
    for character in name[:name_length] {
        if character == 0 {
            return false
        }
    }
    return true
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
        return apply_add_favorite_mutation(set, mutation)
    case .Remove_Favorite:
        return apply_remove_favorite_mutation(set, mutation)
    case .Reorder_Siblings:
        return apply_reorder_mutation(set, mutation)
    case .Set_Entry_Name:
        return apply_entry_name_mutation(set, mutation)
    case .Create_Collection, .Set_Collection_Name,
        .Reorder_Collections, .Delete_Collection:
        return apply_collection_head_mutation(set, mutation)
    case .Add_Collection_Animation:
        return apply_collection_animation_add_mutation(set, mutation)
    case .Remove_Collection_Animation:
        return apply_collection_animation_remove_mutation(set, mutation)
    }
    return .Invalid_Kind
}

// Route custom head lifecycle edits independently of placement membership and naming.
apply_collection_head_mutation :: proc(
    set: ^Set, mutation: Mutation) -> Mutation_Error {
    #partial switch mutation.kind {
    case .Create_Collection:
        return apply_collection_create_mutation(set, mutation)
    case .Set_Collection_Name:
        return apply_collection_name_mutation(set, mutation)
    case .Reorder_Collections:
        return apply_collection_move_mutation(set, mutation)
    case .Delete_Collection:
        return apply_collection_delete_mutation(set, mutation)
    }
    return .Invalid_Kind
}

// Revalidate replay against current ownership and append only after storage admission.
apply_collection_create_mutation :: proc(
    set: ^Set, mutation: Mutation) -> Mutation_Error {
    name_bytes := mutation.collection_name
    if !collection_name_bytes_are_valid(
        name_bytes[:], mutation.collection_name_length) {
        return .Invalid_Name
    }
    name := string(name_bytes[:mutation.collection_name_length])
    _, policy := make_collection_create_mutation(set, mutation.collection_id, name)
    if policy != .None {
        return .Policy
    }
    failure := append_collection(set, {
        id = mutation.collection_id,
        role = .User,
        name = name_bytes[:mutation.collection_name_length],
        name_length = mutation.collection_name_length,
        order = maximum_collection_order(set) + 1,
    })
    if failure == .Allocation_Failed || failure == .Capacity {
        return .Allocation_Failed
    }
    if failure != .None {
        return .Policy
    }
    return .None
}

// Apply one validated Favorites addition mutation.
apply_add_favorite_mutation :: proc(
    set: ^Set, mutation: Mutation) -> Mutation_Error {
    if mutation.entry_id == (uuid.Identifier{}) ||
        mutation.animation_id == (uuid.Identifier{}) ||
        mutation.placement.collection_id != FAVORITES_COLLECTION_ID ||
        mutation.placement.entry_id != mutation.entry_id ||
        mutation.placement.parent_entry_id != (uuid.Identifier{}) {
        return .Invalid_Entry
    }
    if favorites_add(set, mutation.entry_id, mutation.animation_id) != .None {
        return .Policy
    }
    return .None
}

// Apply one Favorites removal mutation.
apply_remove_favorite_mutation :: proc(
    set: ^Set, mutation: Mutation) -> Mutation_Error {
    if mutation.entry_id == (uuid.Identifier{}) ||
        mutation.placement.entry_id != mutation.entry_id ||
        mutation.placement.collection_id != FAVORITES_COLLECTION_ID ||
        mutation.placement.parent_entry_id != (uuid.Identifier{}) {
        return .Invalid_Entry
    }
    _, identity_error := placement_resolve(set, mutation.placement)
    if identity_error != .None {
        return .Policy
    }
    if favorites_remove(set, mutation.entry_id) != .None {
        return .Policy
    }
    return .None
}

// Apply one sibling reorder mutation.
apply_reorder_mutation :: proc(
    set: ^Set, mutation: Mutation) -> Mutation_Error {
    if mutation.entry_id == (uuid.Identifier{}) ||
        mutation.sibling_entry_id == (uuid.Identifier{}) {
        return .Invalid_Entry
    }
    if sibling_move_apply(set, mutation) != .None {
        return .Policy
    }
    return .None
}

// Validate and apply one placement-name mutation.
apply_entry_name_mutation :: proc(
    set: ^Set, mutation: Mutation) -> Mutation_Error {
    if mutation.entry_id == (uuid.Identifier{}) ||
        mutation.placement.entry_id != mutation.entry_id {
        return .Invalid_Entry
    }
    name := mutation.custom_name
    if !entry_name_bytes_are_valid(name[:], mutation.custom_name_length) {
        return .Invalid_Name
    }
    name_error := placement_entry_name_set(
        set, mutation.placement, name[:], mutation.custom_name_length)
    if name_error == .Allocation_Failed {
        return .Allocation_Failed
    }
    if name_error != .None {
        return .Policy
    }
    return .None
}

// Set or clear a placement name only while its captured scope remains current.
placement_entry_name_set :: proc(
    set: ^Set, identity: Placement_Identity,
    name: []u8, name_length: int) -> Policy_Error {
    if set == nil || !set^.initialized {
        return .Invalid_Set
    }
    if !entry_name_bytes_are_valid(name, name_length) {
        return .Invalid_Name
    }
    _, failure := placement_resolve(set, identity)
    if failure != .None {
        return failure
    }
    entry_index := find_entry(set, identity.entry_id)
    collection_index := find_collection(set, set.entries[entry_index].collection_id)
    if set.collections[collection_index].is_read_only {
        return .Read_Only
    }
    return placement_custom_name_replace(
        set, entry_index, name, name_length)
}

// Replace one custom label after validation, preserving it on allocation failure.
placement_custom_name_replace :: proc(
    set: ^Set, entry_index: int, name: []u8, name_length: int) -> Policy_Error {
    entry := &set^.entries[entry_index]
    if entry^.custom_name_length == name_length &&
        (name_length == 0 ||
            string(entry^.custom_name[:name_length]) == string(name[:name_length])) {
        return .None
    }
    replacement: []u8
    allocation_error: runtime.Allocator_Error
    allocator := storage.tlsf_owner_allocator(&set^.allocator)
    if name_length > 0 {
        replacement, allocation_error = make(
            []u8,
            name_length,
            allocator)
        if allocation_error != nil || len(replacement) != name_length {
            return .Allocation_Failed
        }
        copy(replacement, name[:name_length])
    }
    delete(entry^.custom_name, allocator)
    entry^.custom_name = replacement
    entry^.custom_name_length = name_length
    return .None
}

// Replace one copied catalogue label while preserving the prior label on failure.
placement_canonical_name_set :: proc(
    set: ^Set, identity: Placement_Identity, name: string) -> Policy_Error {
    if set == nil || !set^.initialized {
        return .Invalid_Set
    }
    name_bytes := transmute([]u8)name
    if !canonical_label_bytes_are_valid(name_bytes, len(name)) {
        return .Invalid_Name
    }
    _, failure := placement_resolve(set, identity)
    if failure != .None {
        return failure
    }
    entry_index := find_entry(set, identity.entry_id)
    entry := &set^.entries[entry_index]
    if name == string(entry^.canonical_name[:entry^.canonical_name_length]) {
        return .None
    }
    replacement: []u8
    allocation_error: runtime.Allocator_Error
    allocator := storage.tlsf_owner_allocator(&set^.allocator)
    if len(name) > 0 {
        replacement, allocation_error = make([]u8, len(name), allocator)
        if allocation_error != nil || len(replacement) != len(name) {
            return .Allocation_Failed
        }
        copy(replacement, name_bytes)
    }
    delete(entry^.canonical_name, allocator)
    entry^.canonical_name = replacement
    entry^.canonical_name_length = len(name)
    return .None
}

// Validate an optional entry name's bounded UTF-8 byte representation.
entry_name_bytes_are_valid :: proc(
    name: []u8, name_length: int) -> bool {
    if name_length < 0 || name_length > ENTRY_NAME_MAX_BYTES ||
        name_length > len(name) {
        return false
    }
    if name_length == 0 {
        return true
    }
    value := string(name[:name_length])
    if !utf8.valid_string(value) {
        return false
    }
    for character in name[:name_length] {
        if character == 0 {
            return false
        }
    }
    return true
}

// Validate a copied catalogue label without imposing the user-name byte limit.
canonical_label_bytes_are_valid :: proc(
    name: []u8, name_length: int) -> bool {
    if name_length < 0 || name_length > len(name) {
        return false
    }
    if name_length == 0 {
        return true
    }
    if !utf8.valid_string(string(name[:name_length])) {
        return false
    }
    for character in name[:name_length] {
        if character == 0 {
            return false
        }
    }
    return true
}

// Copy one collection record and its optional name into owned storage.
append_collection :: proc(set: ^Set, value: Collection) -> Policy_Error {
    if set == nil || !set^.initialized ||
        value.name_length < 0 ||
        value.name_length > COLLECTION_NAME_MAX_BYTES ||
        value.name_length > len(value.name) {
        return .Invalid_Name
    }
    if !collections_ensure_capacity(set, set^.collection_count + 1) ||
        !collection_index_ensure_capacity(set, set^.collection_count + 1) {
        return .Capacity
    }
    copied_name: []u8
    allocation_error: runtime.Allocator_Error
    allocator := storage.tlsf_owner_allocator(&set^.allocator)
    if value.name_length > 0 {
        copied_name, allocation_error = make(
            []u8,
            value.name_length,
            allocator)
        if allocation_error != nil || len(copied_name) != value.name_length {
            return .Allocation_Failed
        }
        copy(copied_name, value.name[:value.name_length])
    }
    copied := value
    copied.name = copied_name
    set^.collections[set^.collection_count] = copied
    if !collection_index_insert(
        set, copied.id, set^.collection_count) {
        delete(copied.name, allocator)
        set^.collections[set^.collection_count] = {}
        return .Capacity
    }
    set^.collection_count += 1
    return .None
}

// Copy one placement record and its optional name into owned storage.
append_entry :: proc(set: ^Set, value: Entry) -> Policy_Error {
    if set == nil || !set^.initialized {
        return .Invalid_Name
    }
    if value.kind == .Animation &&
        collection_animation_exists(set, value.collection_id, value.animation_id, -1) {
        if value.collection_id == FAVORITES_COLLECTION_ID {
            return .Already_Favorited
        }
        return .Already_In_Collection
    }
    if !entries_ensure_capacity(set, set^.entry_count + 1) ||
        !entry_index_ensure_capacity(set, set^.entry_count + 1) {
        return .Capacity
    }
    copied, copy_error := entry_copy_owned(set, value)
    if copy_error != .None {
        return copy_error
    }
    set^.entries[set^.entry_count] = copied
    if !entry_index_insert(set, copied.id, set^.entry_count) {
        allocator := storage.tlsf_owner_allocator(&set^.allocator)
        delete(copied.custom_name, allocator)
        delete(copied.canonical_name, allocator)
        set^.entries[set^.entry_count] = {}
        return .Capacity
    }
    set^.entry_count += 1
    return .None
}

// Validate and deep-copy one placement's optional labels into the Set owner.
entry_copy_owned :: proc(set: ^Set, value: Entry) -> (Entry, Policy_Error) {
    if !entry_optional_text_is_valid(value) {
        return {}, .Invalid_Name
    }
    custom_name, custom_error := copy_owned_label(
        set, value.custom_name, value.custom_name_length)
    if custom_error != .None {
        return {}, custom_error
    }
    canonical_name, canonical_error := copy_owned_label(
        set, value.canonical_name, value.canonical_name_length)
    if canonical_error != .None {
        delete(custom_name, storage.tlsf_owner_allocator(&set^.allocator))
        return {}, canonical_error
    }
    copied := value
    copied.custom_name = custom_name
    copied.canonical_name = canonical_name
    return copied, .None
}

// Copy one optional text slice into the initialized Set's TLSF domain.
copy_owned_label :: proc(
    set: ^Set, source: []u8, source_length: int) -> ([]u8, Policy_Error) {
    if source_length == 0 {
        return nil, .None
    }
    allocator := storage.tlsf_owner_allocator(&set^.allocator)
    copied, allocation_error := make([]u8, source_length, allocator)
    if allocation_error != nil || len(copied) != source_length {
        return nil, .Allocation_Failed
    }
    copy(copied, source[:source_length])
    return copied, .None
}

// Validate both optional text fields before acquiring owner storage.
entry_optional_text_is_valid :: proc(value: Entry) -> bool {
    return entry_name_bytes_are_valid(value.custom_name, value.custom_name_length) &&
        canonical_label_bytes_are_valid(
            value.canonical_name, value.canonical_name_length)
}

// Initialize reusable storage and the required editable Favorites collection.
initialize :: proc(set: ^Set) -> bool {
    if set == nil {
        return false
    }
    if set^.initialized {
        return initialize_existing_set(set)
    }
    set^ = {}
    heap_allocator := runtime.Allocator{procedure = runtime.heap_allocator_proc}
    if storage.tlsf_owner_init(&set^.allocator, heap_allocator) != .Ok {
        return false
    }
    if !initialize_storage_arrays(set) {
        storage.tlsf_owner_destroy(&set^.allocator)
        set^ = {}
        return false
    }
    set^.initialized = true
    if !initialize_favorites(set) {
        destroy(set)
        return false
    }
    return true
}

// Reuse the initialized TLSF and arrays while restoring the required Favorites row.
initialize_existing_set :: proc(set: ^Set) -> bool {
    clear(set)
    return initialize_favorites(set)
}

// Allocate the initial dynamic records and indexes through this Set's owner.
initialize_storage_arrays :: proc(set: ^Set) -> bool {
    set^.collections = collections_allocate_array(set, 4)
    set^.entries = entries_allocate_array(set, 8)
    set^.collection_index = index_allocate_array(set, 8)
    set^.entry_index = index_allocate_array(set, 16)
    return len(set^.collections) == 4 && len(set^.entries) == 8 &&
        len(set^.collection_index) == 8 && len(set^.entry_index) == 16
}

// Publish the required editable Favorites collection into the empty Set.
initialize_favorites :: proc(set: ^Set) -> bool {
    set^.collections[0] = {
        id = FAVORITES_COLLECTION_ID,
        role = .Favorites,
    }
    set^.collection_count = 1
    return collection_index_insert(set, FAVORITES_COLLECTION_ID, 0)
}

// Reclaim records and their optional text while retaining reusable table capacity.
clear :: proc(set: ^Set) {
    if set == nil || !set^.initialized {
        return
    }
    allocator := storage.tlsf_owner_allocator(&set^.allocator)
    for &collection in set.collections[:set.collection_count] {
        delete(collection.name, allocator)
        collection = {}
    }
    for &entry in set.entries[:set.entry_count] {
        delete(entry.custom_name, allocator)
        delete(entry.canonical_name, allocator)
        entry = {}
    }
    for &slot in set.collection_index {
        slot = {}
    }
    for &slot in set.entry_index {
        slot = {}
    }
    set.collection_count = 0
    set.entry_count = 0
}

// Release all Library records, indexes, and TLSF backing pools.
destroy :: proc(set: ^Set) {
    if set == nil || !set^.initialized {
        return
    }
    clear(set)
    allocator := storage.tlsf_owner_allocator(&set^.allocator)
    delete(set^.collections, allocator)
    delete(set^.entries, allocator)
    delete(set^.collection_index, allocator)
    delete(set^.entry_index, allocator)
    storage.tlsf_owner_destroy(&set^.allocator)
    set^ = {}
}

// Copy canonical records atomically into independently owned storage.
clone :: proc(destination, source: ^Set) -> bool {
    if destination == nil || source == nil || destination == source ||
        !source^.initialized {
        return false
    }
    staged: Set
    if !initialize(&staged) {
        return false
    }
    clear(&staged)
    for value in source.collections[:source.collection_count] {
        if append_collection(&staged, value) != .None {
            destroy(&staged)
            return false
        }
    }
    for value in source.entries[:source.entry_count] {
        if append_entry(&staged, value) != .None {
            destroy(&staged)
            return false
        }
    }
    old := destination^
    destination^ = staged
    staged = old
    destroy(&staged)
    return true
}

// Allocate an actual-sized collection table from the owner TLSF domain.
collections_allocate_array :: proc(set: ^Set, capacity: int) -> []Collection {
    if capacity <= 0 {
        return nil
    }
    allocator := storage.tlsf_owner_allocator(&set^.allocator)
    return make([]Collection, capacity, allocator)
}

// Allocate an actual-sized placement table from the owner TLSF domain.
entries_allocate_array :: proc(set: ^Set, capacity: int) -> []Entry {
    if capacity <= 0 {
        return nil
    }
    allocator := storage.tlsf_owner_allocator(&set^.allocator)
    return make([]Entry, capacity, allocator)
}

// Allocate a UUID lookup table in this Set's reusable owner domain.
index_allocate_array :: proc(set: ^Set, capacity: int) -> []Index_Slot {
    allocator := storage.tlsf_owner_allocator(&set^.allocator)
    return make([]Index_Slot, capacity, allocator)
}

// Keep collection UUID lookup below a one-half load factor.
collection_index_ensure_capacity :: proc(set: ^Set, required: int) -> bool {
    if required <= len(set^.collection_index)/2 {
        return true
    }
    capacity := max(8, len(set^.collection_index))
    for required > capacity/2 {
        if capacity > max(int)/2 {
            return false
        }
        capacity *= 2
    }
    replacement := index_allocate_array(set, capacity)
    if len(replacement) != capacity {
        return false
    }
    for index in 0..<set^.collection_count {
        if !index_insert(replacement, set^.collections[index].id, index) {
            delete(replacement, storage.tlsf_owner_allocator(&set^.allocator))
            return false
        }
    }
    allocator := storage.tlsf_owner_allocator(&set^.allocator)
    delete(set^.collection_index, allocator)
    set^.collection_index = replacement
    return true
}

// Keep placement UUID lookup below a one-half load factor.
entry_index_ensure_capacity :: proc(set: ^Set, required: int) -> bool {
    if required <= len(set^.entry_index)/2 {
        return true
    }
    capacity := max(16, len(set^.entry_index))
    for required > capacity/2 {
        if capacity > max(int)/2 {
            return false
        }
        capacity *= 2
    }
    replacement := index_allocate_array(set, capacity)
    if len(replacement) != capacity {
        return false
    }
    for index in 0..<set^.entry_count {
        if !index_insert(replacement, set^.entries[index].id, index) {
            delete(replacement, storage.tlsf_owner_allocator(&set^.allocator))
            return false
        }
    }
    allocator := storage.tlsf_owner_allocator(&set^.allocator)
    delete(set^.entry_index, allocator)
    set^.entry_index = replacement
    return true
}

// Insert one UUID without replacing the first row for a duplicate identity.
index_insert :: proc(table: []Index_Slot, id: uuid.Identifier, value_index: int) -> bool {
    if id == (uuid.Identifier{}) || len(table) == 0 ||
        len(table) & (len(table) - 1) != 0 {
        return false
    }
    slot_index := int(index_hash(id) & u64(len(table) - 1))
    for _ in 0..<len(table) {
        slot := &table[slot_index]
        if !slot^.occupied {
            slot^ = {id, value_index, true}
            return true
        }
        if slot^.id == id {
            return true
        }
        slot_index = (slot_index + 1) & (len(table) - 1)
    }
    return false
}

// Insert one collection identity into its retained UUID index.
collection_index_insert :: proc(
    set: ^Set, id: uuid.Identifier, value_index: int) -> bool {
    return index_insert(set^.collection_index, id, value_index)
}

// Insert one placement identity into its retained UUID index.
entry_index_insert :: proc(
    set: ^Set, id: uuid.Identifier, value_index: int) -> bool {
    return index_insert(set^.entry_index, id, value_index)
}

// Find one UUID's stored backing-array index without scanning active records.
index_lookup :: proc(table: []Index_Slot, id: uuid.Identifier) -> int {
    if id == (uuid.Identifier{}) || len(table) == 0 {
        return -1
    }
    slot_index := int(index_hash(id) & u64(len(table) - 1))
    for _ in 0..<len(table) {
        slot := table[slot_index]
        if !slot.occupied {
            return -1
        }
        if slot.id == id {
            return slot.value_index
        }
        slot_index = (slot_index + 1) & (len(table) - 1)
    }
    return -1
}

// Hash a UUID with rotation and xor so arithmetic cannot overflow.
index_hash :: proc(id: uuid.Identifier) -> u64 {
    hash: u64 = 0x9e3779b97f4a7c15
    for value in id {
        hash = (hash << 7) | (hash >> 57)
        hash ~= u64(value)
    }
    return hash
}

// Grow the collection table without relocating separately owned text.
collections_ensure_capacity :: proc(set: ^Set, required: int) -> bool {
    if required <= len(set^.collections) {
        return true
    }
    capacity := max(4, len(set^.collections))
    for capacity < required {
        if capacity > max(int)/2 {
            return false
        }
        capacity *= 2
    }
    replacement := collections_allocate_array(set, capacity)
    if len(replacement) == 0 {
        return false
    }
    copy(replacement, set^.collections[:set^.collection_count])
    allocator := storage.tlsf_owner_allocator(&set^.allocator)
    delete(set^.collections, allocator)
    set^.collections = replacement
    return true
}

// Grow the placement table without relocating separately owned text.
entries_ensure_capacity :: proc(set: ^Set, required: int) -> bool {
    if required <= len(set^.entries) {
        return true
    }
    capacity := max(8, len(set^.entries))
    for capacity < required {
        if capacity > max(int)/2 {
            return false
        }
        capacity *= 2
    }
    replacement := entries_allocate_array(set, capacity)
    if len(replacement) == 0 {
        return false
    }
    copy(replacement, set^.entries[:set^.entry_count])
    allocator := storage.tlsf_owner_allocator(&set^.allocator)
    delete(set^.entries, allocator)
    set^.entries = replacement
    return true
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
    if set == nil || !set.initialized {
        return -1
    }
    index := index_lookup(set.collection_index, id)
    if index >= 0 && index < set.collection_count &&
        set.collections[index].id == id {
        return index
    }
    return -1
}

// Find an entry by its placement UUID, or return -1.
find_entry :: proc(set: ^Set, id: uuid.Identifier) -> int {
    if set == nil || !set.initialized {
        return -1
    }
    index := index_lookup(set.entry_index, id)
    if index >= 0 && index < set.entry_count &&
        set.entries[index].id == id {
        return index
    }
    return -1
}

// Rebuild the entry UUID map after records shift in the backing slice.
entry_index_rebuild :: proc(set: ^Set) -> bool {
    for &slot in set.entry_index {
        slot = {}
    }
    for index in 0..<set.entry_count {
        if !index_insert(set.entry_index, set.entries[index].id, index) {
            return false
        }
    }
    return true
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
    resolution := sibling_move_resolve_indexes(set, mutation)
    if resolution.failure != .None {
        return resolution.failure
    }
    entry := set.entries[resolution.entry_index]
    sibling := set.entries[resolution.sibling_index]
    set.entries[resolution.entry_index].sibling_order = sibling.sibling_order
    set.entries[resolution.sibling_index].sibling_order = entry.sibling_order
    return .None
}

// Resolve and validate one move against indexed placements and their current scope.
sibling_move_resolve_indexes :: proc(
    set: ^Set, mutation: Mutation) -> Sibling_Move_Resolution {
    if set == nil || !set^.initialized {
        return {failure = .Invalid_Set}
    }
    if !move_direction_is_valid(mutation.direction) {
        return {failure = .Invalid_Direction}
    }
    if mutation.entry_id == mutation.sibling_entry_id {
        return {failure = .Invalid_Identity}
    }
    return sibling_move_resolve_records(set, mutation)
}

// Validate the indexed records, identity scope, policy, and current adjacency.
sibling_move_resolve_records :: proc(
    set: ^Set, mutation: Mutation) -> Sibling_Move_Resolution {
    entry_index := find_entry(set, mutation.entry_id)
    sibling_index := find_entry(set, mutation.sibling_entry_id)
    if entry_index < 0 {
        return {failure = .Missing_Entry}
    }
    if sibling_index < 0 {
        return {failure = .Missing_Sibling}
    }
    entry := set.entries[entry_index]
    sibling := set.entries[sibling_index]
    if mutation.placement.entry_id != entry.id ||
        mutation.placement.collection_id != entry.collection_id ||
        mutation.placement.parent_entry_id != entry.parent_entry_id {
        return {failure = .Different_Scope}
    }
    if entry.collection_id != sibling.collection_id ||
        entry.parent_entry_id != sibling.parent_entry_id {
        return {failure = .Different_Scope}
    }
    collection_index := find_collection(set, entry.collection_id)
    if collection_index < 0 {
        return {failure = .Missing_Collection}
    }
    if set.collections[collection_index].is_read_only {
        return {failure = .Read_Only}
    }
    if sibling_neighbor_index(set, entry, mutation.direction) != sibling_index {
        return {failure = .Not_Adjacent}
    }
    return {entry_index, sibling_index, .None}
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

// Validate the optional custom name stored on one entry record.
entry_custom_name_is_valid :: proc(entry: ^Entry) -> bool {
    return len(entry^.custom_name) == entry^.custom_name_length &&
        entry_name_bytes_are_valid(
            entry^.custom_name, entry^.custom_name_length) &&
        len(entry^.canonical_name) == entry^.canonical_name_length &&
        canonical_label_bytes_are_valid(
            entry^.canonical_name, entry^.canonical_name_length)
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
    return collection_animation_exists(
        set, FAVORITES_COLLECTION_ID, animation_id, except_index)
}

// Check whole-collection animation membership independently of placement parentage.
collection_animation_exists :: proc(
    set: ^Set, collection_id, animation_id: uuid.Identifier,
    except_index: int) -> bool {
    for index in 0..<set.entry_count {
        entry := set.entries[index]
        if index != except_index && entry.collection_id == collection_id &&
            entry.kind == .Animation &&
            entry.animation_id == animation_id {
            return true
        }
    }
    return false
}

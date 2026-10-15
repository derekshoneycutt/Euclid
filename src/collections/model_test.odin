#+test
package collections

import uuid "core:encoding/uuid"
import "core:testing"

// Create a deterministic nonzero test UUID.
collections_test_id :: proc(value: u8) -> uuid.Identifier {
    identifier: uuid.Identifier
    identifier[15] = value
    return identifier
}

// Start with the one required editable system collection.
collections_test_set :: proc() -> Set {
    set: Set
    set.collections[0] = {
        id = FAVORITES_COLLECTION_ID,
        role = .Favorites,
    }
    set.collection_count = 1
    return set
}

// Build shuffled Favorites storage with order gaps and a maximum order value.
collections_test_shuffled_set :: proc() -> Set {
    set := collections_test_set()
    set.entries[0] = {
        id = collections_test_id(42),
        collection_id = FAVORITES_COLLECTION_ID,
        sibling_order = max(i64),
        kind = .Animation,
        animation_id = collections_test_id(52),
    }
    set.entries[1] = {
        id = collections_test_id(40),
        collection_id = FAVORITES_COLLECTION_ID,
        sibling_order = 7,
        kind = .Animation,
        animation_id = collections_test_id(50),
    }
    set.entries[2] = {
        id = collections_test_id(41),
        collection_id = FAVORITES_COLLECTION_ID,
        sibling_order = 2,
        kind = .Animation,
        animation_id = collections_test_id(51),
    }
    set.entry_count = 3
    return set
}

// Preserve flat Favorites ordering and allocate a new placement on re-add.
@(test)
collections_favorites_toggle_policy_preserves_placement_order :: proc(t: ^testing.T) {
    set := collections_test_set()
    first_animation := collections_test_id(1)
    second_animation := collections_test_id(2)
    first_entry := collections_test_id(11)
    second_entry := collections_test_id(12)
    replacement_entry := collections_test_id(13)

    testing.expect_value(t, favorites_add(&set, first_entry, first_animation),
        Policy_Error.None)
    testing.expect_value(t, favorites_add(&set, second_entry, second_animation),
        Policy_Error.None)
    testing.expect_value(t, favorites_add(
        &set, collections_test_id(14), first_animation), Policy_Error.Already_Favorited)
    testing.expect_value(t, favorites_remove(&set, first_entry), Policy_Error.None)
    testing.expect_value(t, favorites_add(&set, replacement_entry, first_animation),
        Policy_Error.None)

    testing.expect_value(t, set.entry_count, 2)
    testing.expect_value(t, set.entries[0].id, second_entry)
    testing.expect_value(t, set.entries[0].sibling_order, i64(1))
    testing.expect_value(t, set.entries[1].id, replacement_entry)
    testing.expect_value(t, set.entries[1].sibling_order, i64(2))
    testing.expect_value(t, validate(&set), Validation_Error.None)
}

// Verify ordered enumeration and bounded neighbor queries ignore storage layout.
@(test)
collections_sibling_queries_use_authoritative_order :: proc(t: ^testing.T) {
    set := collections_test_shuffled_set()
    ordered: [ENTRY_CAPACITY]int
    count, failure := ordered_siblings(
        &set, FAVORITES_COLLECTION_ID, {}, ordered[:])
    testing.expect_value(t, failure, Policy_Error.None)
    testing.expect_value(t, count, 3)
    testing.expect_value(t, set.entries[ordered[0]].id, collections_test_id(41))
    testing.expect_value(t, set.entries[ordered[1]].id, collections_test_id(40))
    testing.expect_value(t, set.entries[ordered[2]].id, collections_test_id(42))
    testing.expect_value(t, set.entries[ordered[2]].sibling_order, max(i64))

    neighbor: uuid.Identifier
    neighbor, failure = sibling_neighbor(
        &set, collections_test_id(40), .Up)
    testing.expect_value(t, failure, Policy_Error.None)
    testing.expect_value(t, neighbor, collections_test_id(41))
    neighbor, failure = sibling_neighbor(&set, collections_test_id(40), .Down)
    testing.expect_value(t, failure, Policy_Error.None)
    testing.expect_value(t, neighbor, collections_test_id(42))
    _, failure = sibling_neighbor(&set, collections_test_id(41), .Up)
    testing.expect_value(t, failure, Policy_Error.No_Neighbor)
    _, failure = sibling_neighbor(&set, collections_test_id(42), .Down)
    testing.expect_value(t, failure, Policy_Error.No_Neighbor)
}

// Verify immutable moves swap only order values and replay deterministically.
@(test)
collections_sibling_moves_preserve_placement_identity :: proc(t: ^testing.T) {
    set := collections_test_shuffled_set()
    mutation: Mutation
    failure: Policy_Error
    mutation, failure = make_sibling_move(&set, collections_test_id(40), .Up)
    testing.expect_value(t, failure, Policy_Error.None)
    replay := set
    testing.expect_value(t, apply_mutation(&set, mutation), Mutation_Error.None)
    testing.expect_value(t, apply_mutation(&replay, mutation), Mutation_Error.None)
    testing.expect_value(t, set.entries[1].id, collections_test_id(40))
    testing.expect_value(t, set.entries[1].sibling_order, i64(2))
    testing.expect_value(t, set.entries[1].animation_id, collections_test_id(50))
    testing.expect_value(t, set.entries[2].id, collections_test_id(41))
    testing.expect_value(t, set.entries[2].sibling_order, i64(7))
    testing.expect_value(t, replay.entries[1].sibling_order, i64(2))
    testing.expect_value(t, replay.entries[2].sibling_order, i64(7))

    mutation, failure = make_sibling_move(&set, collections_test_id(40), .Down)
    testing.expect_value(t, failure, Policy_Error.None)
    testing.expect_value(t, apply_mutation(&set, mutation), Mutation_Error.None)
    testing.expect_value(t, set.entries[1].sibling_order, i64(7))
    testing.expect_value(t, set.entries[2].sibling_order, i64(2))
    testing.expect_value(t, validate(&set), Validation_Error.None)
}

// Reject a replay that no longer refers to the immediate sibling.
@(test)
collections_sibling_moves_reject_stale_operations :: proc(t: ^testing.T) {
    set := collections_test_shuffled_set()
    stale, failure := make_sibling_move(&set, collections_test_id(40), .Up)
    testing.expect_value(t, failure, Policy_Error.None)
    intervening: Mutation
    intervening, failure = make_sibling_move(&set, collections_test_id(42), .Up)
    testing.expect_value(t, failure, Policy_Error.None)
    testing.expect_value(t, apply_mutation(&set, intervening), Mutation_Error.None)
    stale_result := set
    testing.expect_value(t, sibling_move_apply(&set, stale), Policy_Error.Not_Adjacent)
    testing.expect_value(t, set.entries[0].sibling_order,
        stale_result.entries[0].sibling_order)
    testing.expect_value(t, set.entries[1].sibling_order,
        stale_result.entries[1].sibling_order)
    testing.expect_value(t, set.entries[2].sibling_order,
        stale_result.entries[2].sibling_order)
}

// Reject read-only and cross-parent moves without changing collection order.
@(test)
collections_sibling_moves_reject_read_only_and_cross_parent :: proc(t: ^testing.T) {
    set := collections_test_nested_set()
    neighbor: uuid.Identifier
    failure: Policy_Error
    neighbor, failure = sibling_neighbor(&set, collections_test_id(22), .Down)
    testing.expect_value(t, failure, Policy_Error.Read_Only)
    set.collections[1].is_read_only = false
    set.entries[3] = {
        id = collections_test_id(25),
        collection_id = collections_test_id(20),
        parent_entry_id = collections_test_id(21),
        sibling_order = 8,
        kind = .Group,
    }
    set.entry_count = 4
    neighbor, failure = sibling_neighbor(&set, collections_test_id(22), .Down)
    testing.expect_value(t, failure, Policy_Error.None)
    testing.expect_value(t, neighbor, collections_test_id(25))
    cross_scope := Mutation{
        kind = .Reorder_Siblings,
        entry_id = collections_test_id(21),
        sibling_entry_id = collections_test_id(22),
        direction = .Down,
    }
    testing.expect_value(t, sibling_move_apply(&set, cross_scope),
        Policy_Error.Different_Scope)
    testing.expect_value(t, validate(&set), Validation_Error.None)
}

// Reject malformed immutable moves with a precise policy error and no mutation.
@(test)
collections_sibling_moves_reject_malformed_operations :: proc(t: ^testing.T) {
    set := collections_test_shuffled_set()
    malformed := Mutation{
        kind = .Reorder_Siblings,
        entry_id = collections_test_id(40),
        sibling_entry_id = collections_test_id(40),
        direction = .Up,
    }
    testing.expect_value(t, sibling_move_apply(&set, malformed),
        Policy_Error.Invalid_Identity)
    malformed.sibling_entry_id = collections_test_id(99)
    testing.expect_value(t, sibling_move_apply(&set, malformed),
        Policy_Error.Missing_Sibling)
    malformed.sibling_entry_id = collections_test_id(41)
    malformed.direction = Move_Direction(255)
    testing.expect_value(t, sibling_move_apply(&set, malformed),
        Policy_Error.Invalid_Direction)
    testing.expect_value(t, set.entries[1].sibling_order, i64(7))
    testing.expect_value(t, set.entries[2].sibling_order, i64(2))
}

// Reject insufficient output space, empty scopes, and malformed move requests.
@(test)
collections_sibling_queries_reject_invalid_and_bounded_requests :: proc(t: ^testing.T) {
    set := collections_test_shuffled_set()
    small: [1]int
    count, failure := ordered_siblings(
        &set, FAVORITES_COLLECTION_ID, {}, small[:])
    testing.expect_value(t, count, 0)
    testing.expect_value(t, failure, Policy_Error.Capacity)
    _, failure = sibling_neighbor(
        &set, collections_test_id(40), Move_Direction(255))
    testing.expect_value(t, failure, Policy_Error.Invalid_Direction)
    _, failure = sibling_neighbor(&set, collections_test_id(99), .Up)
    testing.expect_value(t, failure, Policy_Error.Missing_Entry)

    empty := collections_test_set()
    empty_count: int
    empty_count, failure = ordered_siblings(
        &empty, FAVORITES_COLLECTION_ID, {}, small[:])
    testing.expect_value(t, empty_count, 0)
    testing.expect_value(t, failure, Policy_Error.None)

    single := collections_test_set()
    testing.expect_value(t, favorites_add(
        &single, collections_test_id(60), collections_test_id(61)),
        Policy_Error.None)
    _, failure = sibling_neighbor(&single, collections_test_id(60), .Up)
    testing.expect_value(t, failure, Policy_Error.No_Neighbor)
    _, failure = make_sibling_move(&single, collections_test_id(60), .Down)
    testing.expect_value(t, failure, Policy_Error.No_Neighbor)
}

// Build a valid collection fixture containing nested group and animation rows.
collections_test_nested_set :: proc() -> Set {
    set := collections_test_set()
    collection_id := collections_test_id(20)
    collections_test_add_nested_collection(&set, collection_id)
    collections_test_add_nested_entries(&set, collection_id)
    return set
}

// Add a read-only named collection fixture record.
collections_test_add_nested_collection :: proc(
    set: ^Set, collection_id: uuid.Identifier) {
    set^.collections[1] = {
        id = collection_id,
        role = .User,
        name_length = 4,
        order = 1,
        is_read_only = true,
    }
    set^.collections[1].name[0] = 'W'
    set^.collections[1].name[1] = 'o'
    set^.collections[1].name[2] = 'r'
    set^.collections[1].name[3] = 'k'
    set^.collection_count = 2
}

// Add one group root, a nested group, and a nested animation placement.
collections_test_add_nested_entries :: proc(set: ^Set, collection_id: uuid.Identifier) {
    root_group_id := collections_test_id(21)
    child_group_id := collections_test_id(22)
    animation_entry_id := collections_test_id(23)
    set^.entries[0] = {
        id = root_group_id,
        collection_id = collection_id,
        kind = .Group,
    }
    set^.entries[1] = {
        id = child_group_id,
        collection_id = collection_id,
        parent_entry_id = root_group_id,
        sibling_order = 0,
        kind = .Group,
    }
    set^.entries[2] = {
        id = animation_entry_id,
        collection_id = collection_id,
        parent_entry_id = child_group_id,
        sibling_order = 0,
        kind = .Animation,
        animation_id = collections_test_id(24),
    }
    set^.entry_count = 3
}

// Admit nested general collection entries and reject parent cycles.
@(test)
collections_validate_general_nested_topology :: proc(t: ^testing.T) {
    set := collections_test_nested_set()
    testing.expect_value(t, validate(&set), Validation_Error.None)

    set.entries[0].parent_entry_id = collections_test_id(22)
    testing.expect_value(t, validate(&set), Validation_Error.Cycle)
}

// Reject duplicate Favorites membership and the forbidden read-only role.
@(test)
collections_validate_favorites_role_and_unique_animation :: proc(t: ^testing.T) {
    set := collections_test_set()
    animation_id := collections_test_id(31)
    testing.expect_value(t, favorites_add(
        &set, collections_test_id(32), animation_id), Policy_Error.None)
    set.entries[1] = set.entries[0]
    set.entries[1].id = collections_test_id(33)
    set.entries[1].sibling_order = 1
    set.entry_count = 2
    testing.expect_value(t, validate(&set),
        Validation_Error.Duplicate_Favorite_Animation)

    set.entry_count = 0
    set.collections[0].is_read_only = true
    testing.expect_value(t, validate(&set), Validation_Error.Invalid_Collection)
}

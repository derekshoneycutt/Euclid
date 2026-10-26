#+test
package collections

import uuid "core:encoding/uuid"
import "core:testing"

// Resolve a test placement or construct a qualified missing Favorites identity.
collections_test_identity :: proc(
    set: ^Set, entry_id: uuid.Identifier) -> Placement_Identity {
    identity, failure := placement_identity_for_entry(set, entry_id)
    if failure == .None {
        return identity
    }
    return Placement_Identity{
        collection_id = FAVORITES_COLLECTION_ID,
        entry_id = entry_id,
    }
}

// Create a name mutation using the placement scope present in the fixture.
collections_test_name_mutation :: proc(
    set: ^Set, entry_id: uuid.Identifier, name: string) -> (Mutation, Mutation_Error) {
    return make_placement_name_mutation(
        collections_test_identity(set, entry_id), name)
}

// Create a reorder mutation using the placement scope present in the fixture.
collections_test_move :: proc(
    set: ^Set, entry_id: uuid.Identifier,
    direction: Move_Direction) -> (Mutation, Policy_Error) {
    return make_placement_move(
        set, collections_test_identity(set, entry_id), direction)
}

// Resolve a neighbor with a placement-qualified identity.
collections_test_neighbor :: proc(
    set: ^Set, entry_id: uuid.Identifier,
    direction: Move_Direction) -> (uuid.Identifier, Policy_Error) {
    return placement_sibling_neighbor(
        set, collections_test_identity(set, entry_id), direction)
}

// Create a deterministic nonzero test UUID.
collections_test_id :: proc(value: u8) -> uuid.Identifier {
    identifier: uuid.Identifier
    identifier[15] = value
    return identifier
}

// Create a deterministic UUID suitable for fixtures exceeding one byte.
collections_test_index_id :: proc(value: u32) -> uuid.Identifier {
    identifier: uuid.Identifier
    identifier[12] = u8(value >> 24)
    identifier[13] = u8(value >> 16)
    identifier[14] = u8(value >> 8)
    identifier[15] = u8(value)
    return identifier
}

// Start with the one required editable system collection.
collections_test_set :: proc() -> ^Set {
    set := new(Set, context.allocator)
    if !initialize(set) {
        free(set, context.allocator)
        return nil
    }
    set^.collections[0] = {
        id = FAVORITES_COLLECTION_ID,
        role = .Favorites,
    }
    set^.collection_count = 1
    return set
}

// Release test collection storage and its heap-allocated owner record.
collections_test_destroy :: proc(set: ^Set) {
    if set != nil {
        destroy(set)
        free(set, context.allocator)
    }
}

// Build shuffled Favorites storage with order gaps and a maximum order value.
collections_test_shuffled_set :: proc() -> ^Set {
    set := collections_test_set()
    assert(append_entry(set, {
        id = collections_test_id(42),
        collection_id = FAVORITES_COLLECTION_ID,
        sibling_order = max(i64),
        kind = .Animation,
        animation_id = collections_test_id(52),
    }) == .None)
    assert(append_entry(set, {
        id = collections_test_id(40),
        collection_id = FAVORITES_COLLECTION_ID,
        sibling_order = 7,
        kind = .Animation,
        animation_id = collections_test_id(50),
    }) == .None)
    assert(append_entry(set, {
        id = collections_test_id(41),
        collection_id = FAVORITES_COLLECTION_ID,
        sibling_order = 2,
        kind = .Animation,
        animation_id = collections_test_id(51),
    }) == .None)
    return set
}

// Preserve flat Favorites ordering and allocate a new placement on re-add.
@(test)
collections_favorites_toggle_policy_preserves_placement_order :: proc(t: ^testing.T) {
    set := collections_test_set()
    defer collections_test_destroy(set)
    first_animation := collections_test_id(1)
    second_animation := collections_test_id(2)
    first_entry := collections_test_id(11)
    second_entry := collections_test_id(12)
    replacement_entry := collections_test_id(13)

    testing.expect_value(t, favorites_add(set, first_entry, first_animation),
        Policy_Error.None)
    testing.expect_value(t, favorites_add(set, second_entry, second_animation),
        Policy_Error.None)
    testing.expect_value(t, favorites_add(
        set, collections_test_id(14), first_animation), Policy_Error.Already_Favorited)
    testing.expect_value(t, favorites_remove(set, first_entry), Policy_Error.None)
    testing.expect_value(t, favorites_add(set, replacement_entry, first_animation),
        Policy_Error.None)

    testing.expect_value(t, set^.entry_count, 2)
    testing.expect_value(t, set^.entries[0].id, second_entry)
    testing.expect_value(t, set^.entries[0].sibling_order, i64(1))
    testing.expect_value(t, set^.entries[1].id, replacement_entry)
    testing.expect_value(t, set^.entries[1].sibling_order, i64(2))
    testing.expect_value(t, validate(set), Validation_Error.None)
}

// Set, replay, reorder, and clear names without changing placement identity.
@(test)
collections_entry_name_mutations_preserve_placement_and_order :: proc(t: ^testing.T) {
    set := collections_test_shuffled_set()
    defer collections_test_destroy(set)
    entry_id := collections_test_id(40)
    mutation, failure := collections_test_name_mutation(set, entry_id, "Compare these")
    testing.expect_value(t, failure, Mutation_Error.None)
    replay := new(Set, context.allocator)
    defer collections_test_destroy(replay)
    testing.expect(t, clone(replay, set))
    testing.expect_value(t, validate(set), Validation_Error.None)
    testing.expect_value(t, apply_mutation(set, mutation), Mutation_Error.None)

    index := find_entry(set, entry_id)
    testing.expect_value(t, set^.entries[index].custom_name_length, 13)
    testing.expect_value(t, len(set^.entries[index].custom_name), 13)
    testing.expect_value(t,
        string(set^.entries[index].custom_name[:13]), "Compare these")
    testing.expect_value(t, apply_mutation(replay, mutation), Mutation_Error.None)
    testing.expect_value(t, replay^.entries[index].custom_name_length, 13)
    testing.expect_value(t, set^.entries[index].animation_id, collections_test_id(50))
    testing.expect_value(t, set^.entries[index].sibling_order, i64(7))

    move, move_error := collections_test_move(set, entry_id, .Up)
    testing.expect_value(t, move_error, Policy_Error.None)
    testing.expect_value(t, apply_mutation(set, move), Mutation_Error.None)
    index = find_entry(set, entry_id)
    testing.expect_value(t, set^.entries[index].custom_name_length, 13)
    testing.expect_value(t, set^.entries[index].sibling_order, i64(2))

    clear, clear_error := collections_test_name_mutation(set, entry_id, "")
    testing.expect_value(t, clear_error, Mutation_Error.None)
    testing.expect_value(t, apply_mutation(set, clear), Mutation_Error.None)
    index = find_entry(set, entry_id)
    testing.expect_value(t, set^.entries[index].custom_name_length, 0)
    testing.expect_value(t, validate(set), Validation_Error.None)
}

// Keep UUID lookup correct across growth, removal compaction, and owner reuse.
@(test)
collections_uuid_indexes_grow_rebuild_and_reinitialize :: proc(t: ^testing.T) {
    set := collections_test_set()
    defer collections_test_destroy(set)
    collections_test_append_index_collections(t, set)
    for index in 1..=600 {
        entry_id := collections_test_index_id(u32(index))
        result := append_entry(set, {
            id = entry_id,
            collection_id = FAVORITES_COLLECTION_ID,
            sibling_order = i64(index - 1),
            kind = .Animation,
            animation_id = collections_test_index_id(u32(index + 1000)),
        })
        testing.expect_value(t, result, Policy_Error.None)
    }
    collections_test_expect_entry_indexes(t, set, 1, 600)
    testing.expect_value(t,
        favorites_remove(set, collections_test_index_id(1)), Policy_Error.None)
    testing.expect_value(t, find_entry(set, collections_test_index_id(1)), -1)
    collections_test_expect_entry_indexes(t, set, 2, 600)
    testing.expect(t, initialize(set))
    testing.expect_value(t, find_collection(set, FAVORITES_COLLECTION_ID), 0)
    testing.expect_value(t, find_entry(set, collections_test_index_id(600)), -1)
}

// Grow and verify the collection UUID index beyond its initial table.
collections_test_append_index_collections :: proc(t: ^testing.T, set: ^Set) {
    collection_name: [4]u8 = {'W', 'o', 'r', 'k'}
    for index in 1..=600 {
        result := append_collection(set, {
            id = collections_test_index_id(u32(index + 2000)),
            role = .User,
            name = collection_name[:],
            name_length = len(collection_name),
            order = i64(index),
            is_read_only = true,
        })
        testing.expect_value(t, result, Policy_Error.None)
    }
    for index in 1..=600 {
        testing.expect_value(t,
            find_collection(set, collections_test_index_id(u32(index + 2000))),
            index)
    }
}

// Assert that every active placement UUID resolves to its shifted record index.
collections_test_expect_entry_indexes :: proc(
    t: ^testing.T, set: ^Set, first, last: int) {
    for index in first..=last {
        testing.expect_value(t,
            find_entry(set, collections_test_index_id(u32(index))), index - first)
    }
}

// Copy canonical labels into the Set owner and preserve them through a deep clone.
@(test)
collections_canonical_labels_are_owned_and_clone_independently :: proc(
    t: ^testing.T) {
    set := collections_test_set()
    defer collections_test_destroy(set)
    entry_id := collections_test_id(70)
    testing.expect_value(t,
        favorites_add(set, entry_id, collections_test_id(71)), Policy_Error.None)
    identity, identity_error := placement_identity_for_entry(set, entry_id)
    testing.expect_value(t, identity_error, Policy_Error.None)
    source: [300]u8
    for index in 0..<len(source) {
        source[index] = 'a'
    }
    testing.expect_value(t, placement_canonical_name_set(
        set, identity, string(source[:])), Policy_Error.None)
    source[0] = 'b'
    placement, resolve_error := placement_resolve(set, identity)
    testing.expect_value(t, resolve_error, Policy_Error.None)
    testing.expect_value(t, placement.canonical_name_length, len(source))
    testing.expect_value(t, placement.canonical_name[0], u8('a'))

    clone_set := new(Set, context.allocator)
    defer collections_test_destroy(clone_set)
    testing.expect(t, clone(clone_set, set))
    testing.expect_value(t, placement_canonical_name_set(
        set, identity, ""), Policy_Error.None)
    cloned, clone_error := placement_resolve(clone_set, identity)
    testing.expect_value(t, clone_error, Policy_Error.None)
    testing.expect_value(t, cloned.canonical_name_length, len(source))
    testing.expect_value(t, cloned.canonical_name[0], u8('a'))
}

// Reject queued placement operations after collection or parent scope changes.
@(test)
collections_placement_mutations_reject_stale_scope :: proc(t: ^testing.T) {
    set := collections_test_set()
    defer collections_test_destroy(set)
    entry_id := collections_test_id(71)
    sibling_id := collections_test_id(72)
    animation_id := collections_test_id(73)
    testing.expect_value(t,
        favorites_add(set, entry_id, animation_id), Policy_Error.None)
    testing.expect_value(t,
        favorites_add(set, sibling_id, collections_test_id(74)), Policy_Error.None)
    identity, identity_error := placement_identity_for_entry(set, entry_id)
    testing.expect_value(t, identity_error, Policy_Error.None)
    name_mutation, name_error := make_placement_name_mutation(identity, "Named")
    testing.expect_value(t, name_error, Mutation_Error.None)
    move_mutation, move_error := make_placement_move(set, identity, .Down)
    testing.expect_value(t, move_error, Policy_Error.None)

    changed_index := find_entry(set, entry_id)
    set.entries[changed_index].parent_entry_id = collections_test_id(75)
    _, resolve_error := placement_resolve(set, identity)
    testing.expect_value(t, resolve_error, Policy_Error.Different_Scope)
    testing.expect_value(t, apply_mutation(set, name_mutation), Mutation_Error.Policy)
    testing.expect_value(t, set.entries[changed_index].custom_name_length, 0)
    testing.expect_value(t, apply_mutation(set, move_mutation), Mutation_Error.Policy)
    testing.expect_value(t, set.entries[changed_index].sibling_order, i64(0))
}

// Require captured placement identity for every replayable mutation kind.
@(test)
collections_replay_mutations_require_qualified_identity :: proc(t: ^testing.T) {
    set := collections_test_set()
    defer collections_test_destroy(set)
    entry_id := collections_test_id(76)
    animation_id := collections_test_id(77)
    testing.expect_value(t, favorites_add(set, entry_id, animation_id), Policy_Error.None)
    identity, identity_error := placement_identity_for_entry(set, entry_id)
    testing.expect_value(t, identity_error, Policy_Error.None)
    name, name_error := make_placement_name_mutation(identity, "Qualified")
    testing.expect_value(t, name_error, Mutation_Error.None)
    unqualified_name := name
    unqualified_name.placement = {}
    testing.expect_value(t, apply_mutation(set, unqualified_name),
        Mutation_Error.Invalid_Entry)
    unqualified_remove: Mutation = {
        kind = .Remove_Favorite,
        entry_id = entry_id,
    }
    testing.expect_value(t, apply_mutation(set, unqualified_remove),
        Mutation_Error.Invalid_Entry)
    unqualified_add: Mutation = {
        kind = .Add_Favorite,
        entry_id = collections_test_id(78),
        animation_id = collections_test_id(79),
    }
    testing.expect_value(t, apply_mutation(set, unqualified_add),
        Mutation_Error.Invalid_Entry)
    testing.expect_value(t, set.entries[find_entry(set, entry_id)].custom_name_length, 0)
}

// Retire queued identity after removal without binding its mutation to a new placement.
@(test)
collections_stale_operations_cannot_target_readded_placement :: proc(t: ^testing.T) {
    set := collections_test_set()
    defer collections_test_destroy(set)
    entry_id := collections_test_id(80)
    sibling_id := collections_test_id(81)
    testing.expect_value(t,
        favorites_add(set, entry_id, collections_test_id(82)), Policy_Error.None)
    testing.expect_value(t,
        favorites_add(set, sibling_id, collections_test_id(83)), Policy_Error.None)
    identity, identity_error := placement_identity_for_entry(set, entry_id)
    testing.expect_value(t, identity_error, Policy_Error.None)
    stale_name, name_error := make_placement_name_mutation(identity, "Stale")
    testing.expect_value(t, name_error, Mutation_Error.None)
    stale_move, move_error := make_placement_move(set, identity, .Down)
    testing.expect_value(t, move_error, Policy_Error.None)
    remove: Mutation = {
        kind = .Remove_Favorite,
        placement = identity,
        entry_id = entry_id,
    }
    testing.expect_value(t, apply_mutation(set, remove), Mutation_Error.None)
    testing.expect_value(t, apply_mutation(set, stale_name), Mutation_Error.Policy)
    testing.expect_value(t, apply_mutation(set, stale_move), Mutation_Error.Policy)

    replacement_id := collections_test_id(84)
    testing.expect(t, replacement_id != entry_id)
    testing.expect_value(t, favorites_add(
        set, replacement_id, collections_test_id(82)), Policy_Error.None)
    testing.expect_value(t, apply_mutation(set, stale_name), Mutation_Error.Policy)
    testing.expect_value(t, apply_mutation(set, stale_move), Mutation_Error.Policy)
    replacement := find_entry(set, replacement_id)
    testing.expect_value(t, set.entries[replacement].custom_name_length, 0)
}

// Enforce the 256-byte rather than codepoint limit for valid UTF-8 names.
@(test)
collections_entry_names_enforce_byte_capacity :: proc(t: ^testing.T) {
    set := collections_test_shuffled_set()
    defer collections_test_destroy(set)
    entry_id := collections_test_id(40)
    exact: [ENTRY_NAME_MAX_BYTES]u8
    for index in 0..<254 {
        exact[index] = 'x'
    }
    exact[254] = 0xc3
    exact[255] = 0xa9
    mutation, failure := collections_test_name_mutation(
        set, entry_id, string(exact[:]))
    testing.expect_value(t, failure, Mutation_Error.None)
    testing.expect_value(t, apply_mutation(set, mutation), Mutation_Error.None)
    index := find_entry(set, entry_id)
    testing.expect_value(t, set^.entries[index].custom_name_length, ENTRY_NAME_MAX_BYTES)

    over_limit: [ENTRY_NAME_MAX_BYTES + 1]u8
    for index in 0..<255 {
        over_limit[index] = 'x'
    }
    over_limit[255] = 0xc3
    over_limit[256] = 0xa9
    _, failure = collections_test_name_mutation(
        set, entry_id, string(over_limit[:]))
    testing.expect_value(t, failure, Mutation_Error.Invalid_Name)
}

// Reject malformed UTF-8 and NUL in constructor-provided names.
@(test)
collections_entry_names_reject_invalid_utf8_and_nul :: proc(t: ^testing.T) {
    entry_id := collections_test_id(40)
    invalid_utf8: [2]u8 = {0xc0, 0xaf}
    identity: Placement_Identity = {
        collection_id = FAVORITES_COLLECTION_ID,
        entry_id = entry_id,
    }
    _, failure := make_placement_name_mutation(identity, string(invalid_utf8[:]))
    testing.expect_value(t, failure, Mutation_Error.Invalid_Name)
    _, failure = make_placement_name_mutation(identity, "custom\x00name")
    testing.expect_value(t, failure, Mutation_Error.Invalid_Name)
}

// Reject malformed mutation payloads atomically without changing entry state.
@(test)
collections_entry_names_reject_malformed_mutations_atomically :: proc(t: ^testing.T) {
    set := collections_test_shuffled_set()
    defer collections_test_destroy(set)
    entry_id := collections_test_id(40)
    index := find_entry(set, entry_id)
    before := set^.entries[index]
    malformed: Mutation = {
        kind = .Set_Entry_Name,
        placement = collections_test_identity(set, entry_id),
        entry_id = entry_id,
        custom_name_length = ENTRY_NAME_MAX_BYTES + 1,
    }
    testing.expect_value(t, apply_mutation(set, malformed), Mutation_Error.Invalid_Name)
    malformed.custom_name_length = 2
    malformed.custom_name[0], malformed.custom_name[1] = 0xc0, 0xaf
    testing.expect_value(t, apply_mutation(set, malformed), Mutation_Error.Invalid_Name)
    malformed.custom_name_length = 3
    malformed.custom_name[0], malformed.custom_name[1], malformed.custom_name[2] =
        'a', 0, 'b'
    testing.expect_value(t, apply_mutation(set, malformed), Mutation_Error.Invalid_Name)
    testing.expect_value(t, set^.entries[index].custom_name_length,
        before.custom_name_length)
    testing.expect_value(t, set^.entries[index].sibling_order, before.sibling_order)
}

// Reject naming missing or read-only placements without changing the snapshot.
@(test)
collections_entry_name_mutations_enforce_editable_owner :: proc(t: ^testing.T) {
    set := collections_test_shuffled_set()
    defer collections_test_destroy(set)
    mutation, failure := collections_test_name_mutation(
        set, collections_test_id(99), "Missing")
    testing.expect_value(t, failure, Mutation_Error.None)
    testing.expect_value(t, apply_mutation(set, mutation), Mutation_Error.Policy)
    testing.expect_value(t, set^.entries[0].custom_name_length, 0)

    nested := collections_test_nested_set()
    defer collections_test_destroy(nested)
    mutation, failure = collections_test_name_mutation(
        nested, collections_test_id(23), "Read only")
    testing.expect_value(t, failure, Mutation_Error.None)
    testing.expect_value(t, apply_mutation(nested, mutation), Mutation_Error.Policy)
    testing.expect_value(t, nested^.entries[2].custom_name_length, 0)
}

// Verify ordered enumeration and bounded neighbor queries ignore storage layout.
@(test)
collections_sibling_queries_use_authoritative_order :: proc(t: ^testing.T) {
    set := collections_test_shuffled_set()
    defer collections_test_destroy(set)
    ordered: [ENTRY_INDEX_BUFFER_CAPACITY]int
    count, failure := ordered_siblings(
        set, FAVORITES_COLLECTION_ID, {}, ordered[:])
    testing.expect_value(t, failure, Policy_Error.None)
    testing.expect_value(t, count, 3)
    testing.expect_value(t, set^.entries[ordered[0]].id, collections_test_id(41))
    testing.expect_value(t, set^.entries[ordered[1]].id, collections_test_id(40))
    testing.expect_value(t, set^.entries[ordered[2]].id, collections_test_id(42))
    testing.expect_value(t, set^.entries[ordered[2]].sibling_order, max(i64))

    neighbor: uuid.Identifier
    neighbor, failure = collections_test_neighbor(
        set, collections_test_id(40), .Up)
    testing.expect_value(t, failure, Policy_Error.None)
    testing.expect_value(t, neighbor, collections_test_id(41))
    neighbor, failure = collections_test_neighbor(
        set, collections_test_id(40), .Down)
    testing.expect_value(t, failure, Policy_Error.None)
    testing.expect_value(t, neighbor, collections_test_id(42))
    _, failure = collections_test_neighbor(set, collections_test_id(41), .Up)
    testing.expect_value(t, failure, Policy_Error.No_Neighbor)
    _, failure = collections_test_neighbor(set, collections_test_id(42), .Down)
    testing.expect_value(t, failure, Policy_Error.No_Neighbor)
}

// Verify immutable moves swap only order values and replay deterministically.
@(test)
collections_sibling_moves_preserve_placement_identity :: proc(t: ^testing.T) {
    set := collections_test_shuffled_set()
    defer collections_test_destroy(set)
    mutation: Mutation
    failure: Policy_Error
    mutation, failure = collections_test_move(
        set, collections_test_id(40), .Up)
    testing.expect_value(t, failure, Policy_Error.None)
    replay := new(Set, context.allocator)
    defer collections_test_destroy(replay)
    testing.expect(t, clone(replay, set))
    testing.expect_value(t, apply_mutation(set, mutation), Mutation_Error.None)
    testing.expect_value(t, apply_mutation(replay, mutation), Mutation_Error.None)
    testing.expect_value(t, set^.entries[1].id, collections_test_id(40))
    testing.expect_value(t, set^.entries[1].sibling_order, i64(2))
    testing.expect_value(t, set^.entries[1].animation_id, collections_test_id(50))
    testing.expect_value(t, set^.entries[2].id, collections_test_id(41))
    testing.expect_value(t, set^.entries[2].sibling_order, i64(7))
    testing.expect_value(t, replay^.entries[1].sibling_order, i64(2))
    testing.expect_value(t, replay^.entries[2].sibling_order, i64(7))

    mutation, failure = collections_test_move(
        set, collections_test_id(40), .Down)
    testing.expect_value(t, failure, Policy_Error.None)
    testing.expect_value(t, apply_mutation(set, mutation), Mutation_Error.None)
    testing.expect_value(t, set^.entries[1].sibling_order, i64(7))
    testing.expect_value(t, set^.entries[2].sibling_order, i64(2))
    testing.expect_value(t, validate(set), Validation_Error.None)
}

// Reject a replay that no longer refers to the immediate sibling.
@(test)
collections_sibling_moves_reject_stale_operations :: proc(t: ^testing.T) {
    set := collections_test_shuffled_set()
    defer collections_test_destroy(set)
    stale, failure := collections_test_move(
        set, collections_test_id(40), .Up)
    testing.expect_value(t, failure, Policy_Error.None)
    intervening: Mutation
    intervening, failure = collections_test_move(
        set, collections_test_id(42), .Up)
    testing.expect_value(t, failure, Policy_Error.None)
    testing.expect_value(t, apply_mutation(set, intervening), Mutation_Error.None)
    stale_result := new(Set, context.allocator)
    defer collections_test_destroy(stale_result)
    testing.expect(t, clone(stale_result, set))
    testing.expect_value(t, sibling_move_apply(set, stale), Policy_Error.Not_Adjacent)
    testing.expect_value(t, set^.entries[0].sibling_order,
        stale_result^.entries[0].sibling_order)
    testing.expect_value(t, set^.entries[1].sibling_order,
        stale_result^.entries[1].sibling_order)
    testing.expect_value(t, set^.entries[2].sibling_order,
        stale_result^.entries[2].sibling_order)
}

// Reject read-only and cross-parent moves without changing collection order.
@(test)
collections_sibling_moves_reject_read_only_and_cross_parent :: proc(t: ^testing.T) {
    set := collections_test_nested_set()
    defer collections_test_destroy(set)
    neighbor: uuid.Identifier
    failure: Policy_Error
    neighbor, failure = collections_test_neighbor(
        set, collections_test_id(22), .Down)
    testing.expect_value(t, failure, Policy_Error.Read_Only)
    set^.collections[1].is_read_only = false
    assert(append_entry(set, {
        id = collections_test_id(25),
        collection_id = collections_test_id(20),
        parent_entry_id = collections_test_id(21),
        sibling_order = 8,
        kind = .Group,
    }) == .None)
    neighbor, failure = collections_test_neighbor(
        set, collections_test_id(22), .Down)
    testing.expect_value(t, failure, Policy_Error.None)
    testing.expect_value(t, neighbor, collections_test_id(25))
    cross_scope: Mutation = {
        kind = .Reorder_Siblings,
        placement = collections_test_identity(set, collections_test_id(21)),
        entry_id = collections_test_id(21),
        sibling_entry_id = collections_test_id(22),
        direction = .Down,
    }
    testing.expect_value(t, sibling_move_apply(set, cross_scope),
        Policy_Error.Different_Scope)
    testing.expect_value(t, validate(set), Validation_Error.None)
}

// Reject malformed immutable moves with a precise policy error and no mutation.
@(test)
collections_sibling_moves_reject_malformed_operations :: proc(t: ^testing.T) {
    set := collections_test_shuffled_set()
    defer collections_test_destroy(set)
    malformed: Mutation = {
        kind = .Reorder_Siblings,
        placement = collections_test_identity(set, collections_test_id(40)),
        entry_id = collections_test_id(40),
        sibling_entry_id = collections_test_id(40),
        direction = .Up,
    }
    testing.expect_value(t, sibling_move_apply(set, malformed),
        Policy_Error.Invalid_Identity)
    malformed.sibling_entry_id = collections_test_id(99)
    testing.expect_value(t, sibling_move_apply(set, malformed),
        Policy_Error.Missing_Sibling)
    malformed.sibling_entry_id = collections_test_id(41)
    malformed.direction = Move_Direction(255)
    testing.expect_value(t, sibling_move_apply(set, malformed),
        Policy_Error.Invalid_Direction)
    testing.expect_value(t, set^.entries[1].sibling_order, i64(7))
    testing.expect_value(t, set^.entries[2].sibling_order, i64(2))
}

// Reject insufficient output space, empty scopes, and malformed move requests.
@(test)
collections_sibling_queries_reject_invalid_and_bounded_requests :: proc(t: ^testing.T) {
    set := collections_test_shuffled_set()
    defer collections_test_destroy(set)
    small: [1]int
    count, failure := ordered_siblings(
        set, FAVORITES_COLLECTION_ID, {}, small[:])
    testing.expect_value(t, count, 0)
    testing.expect_value(t, failure, Policy_Error.Capacity)
    _, failure = collections_test_neighbor(
        set, collections_test_id(40), Move_Direction(255))
    testing.expect_value(t, failure, Policy_Error.Invalid_Direction)
    _, failure = collections_test_neighbor(set, collections_test_id(99), .Up)
    testing.expect_value(t, failure, Policy_Error.Missing_Entry)

    empty := collections_test_set()
    defer free(empty, context.allocator)
    empty_count: int
    empty_count, failure = ordered_siblings(
        empty, FAVORITES_COLLECTION_ID, {}, small[:])
    testing.expect_value(t, empty_count, 0)
    testing.expect_value(t, failure, Policy_Error.None)

    single := collections_test_set()
    defer free(single, context.allocator)
    testing.expect_value(t, favorites_add(
        single, collections_test_id(60), collections_test_id(61)),
        Policy_Error.None)
    _, failure = collections_test_neighbor(single, collections_test_id(60), .Up)
    testing.expect_value(t, failure, Policy_Error.No_Neighbor)
    _, failure = collections_test_move(single, collections_test_id(60), .Down)
    testing.expect_value(t, failure, Policy_Error.No_Neighbor)
}

// Build a valid collection fixture containing nested group and animation rows.
collections_test_nested_set :: proc() -> ^Set {
    set := collections_test_set()
    collection_id := collections_test_id(20)
    collections_test_add_nested_collection(set, collection_id)
    collections_test_add_nested_entries(set, collection_id)
    return set
}

// Add a read-only named collection fixture record.
collections_test_add_nested_collection :: proc(
    set: ^Set, collection_id: uuid.Identifier) {
    name: [4]u8 = {'W', 'o', 'r', 'k'}
    assert(append_collection(set, {
        id = collection_id,
        role = .User,
        name = name[:],
        name_length = 4,
        order = 1,
        is_read_only = true,
    }) == .None)
}

// Add one group root, a nested group, and a nested animation placement.
collections_test_add_nested_entries :: proc(set: ^Set, collection_id: uuid.Identifier) {
    root_group_id := collections_test_id(21)
    child_group_id := collections_test_id(22)
    animation_entry_id := collections_test_id(23)
    assert(append_entry(set, {
        id = root_group_id,
        collection_id = collection_id,
        kind = .Group,
    }) == .None)
    assert(append_entry(set, {
        id = child_group_id,
        collection_id = collection_id,
        parent_entry_id = root_group_id,
        sibling_order = 0,
        kind = .Group,
    }) == .None)
    assert(append_entry(set, {
        id = animation_entry_id,
        collection_id = collection_id,
        parent_entry_id = child_group_id,
        sibling_order = 0,
        kind = .Animation,
        animation_id = collections_test_id(24),
    }) == .None)
}

// Admit nested general collection entries and reject parent cycles.
@(test)
collections_validate_general_nested_topology :: proc(t: ^testing.T) {
    set := collections_test_nested_set()
    defer collections_test_destroy(set)
    testing.expect_value(t, set^.collections[1].name_length, 4)
    testing.expect_value(t, len(set^.collections[1].name), 4)
    testing.expect_value(t, set^.collections[1].name[0], u8('W'))
    testing.expect_value(t, set^.collections[1].name[1], u8('o'))
    testing.expect_value(t, set^.collections[1].name[2], u8('r'))
    testing.expect_value(t, set^.collections[1].name[3], u8('k'))
    testing.expect_value(t,
        validate_collection_fields(&set^.collections[1]), Validation_Error.None)
    testing.expect_value(t, validate(set), Validation_Error.None)

    set^.entries[0].parent_entry_id = collections_test_id(22)
    testing.expect_value(t, validate(set), Validation_Error.Cycle)
}

// Reject duplicate Favorites membership and the forbidden read-only role.
@(test)
collections_validate_favorites_role_and_unique_animation :: proc(t: ^testing.T) {
    set := collections_test_set()
    defer collections_test_destroy(set)
    animation_id := collections_test_id(31)
    testing.expect_value(t, favorites_add(
        set, collections_test_id(32), animation_id), Policy_Error.None)
    duplicate := set^.entries[0]
    duplicate.custom_name = nil
    duplicate.custom_name_length = 0
    testing.expect_value(t, append_entry(set, duplicate), Policy_Error.Already_Favorited)
    set^.entries[1] = duplicate
    set^.entry_count = 2
    set^.entries[1].id = collections_test_id(33)
    set^.entries[1].sibling_order = 1
    testing.expect_value(t, validate(set),
        Validation_Error.Duplicate_Favorite_Animation)

    set^.entry_count = 0
    set^.collections[0].is_read_only = true
    testing.expect_value(t, validate(set), Validation_Error.Invalid_Collection)
}

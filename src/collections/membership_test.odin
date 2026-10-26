#+test
package collections

import "core:testing"

// Create two writable custom destinations with deliberately indistinguishable labels.
collections_test_membership_set :: proc(t: ^testing.T) -> ^Set {
    set := collections_test_set()
    for value in 70..<72 {
        mutation, policy := make_collection_create_mutation(
            set, collections_test_id(u8(value)), "Same")
        testing.expect_value(t, policy, Policy_Error.None)
        testing.expect_value(t, apply_mutation(set, mutation), Mutation_Error.None)
    }
    return set
}

// Admit and apply one custom root addition through the immutable public operation.
collections_test_membership_add :: proc(
    t: ^testing.T, set: ^Set, collection, entry, animation: u8) -> Mutation {
    mutation, policy := make_collection_animation_add_mutation(
        set, collections_test_id(collection), collections_test_id(entry),
        collections_test_id(animation))
    testing.expect_value(t, policy, Policy_Error.None)
    testing.expect_value(t, apply_mutation(set, mutation), Mutation_Error.None)
    return mutation
}

// Reject invalid, duplicate, protected, unavailable and overflowing destinations unchanged.
@(test)
collections_membership_admission_rejects_invalid_targets :: proc(t: ^testing.T) {
    set := collections_test_membership_set(t)
    defer collections_test_destroy(set)
    collection := collections_test_id(70)
    entry := collections_test_id(80)
    animation := collections_test_id(90)
    _, missing := make_collection_animation_add_mutation(
        set, collections_test_id(69), entry, animation)
    testing.expect_value(t, missing, Policy_Error.Missing_Collection)
    _, protected := make_collection_animation_add_mutation(
        set, FAVORITES_COLLECTION_ID, entry, animation)
    testing.expect_value(t, protected, Policy_Error.Read_Only)
    _, invalid := make_collection_animation_add_mutation(set, collection, {}, animation)
    testing.expect_value(t, invalid, Policy_Error.Invalid_Identity)
    set.collections[1].is_read_only = true
    _, read_only := make_collection_animation_add_mutation(
        set, collection, entry, animation)
    testing.expect_value(t, read_only, Policy_Error.Read_Only)
    set.collections[1].is_read_only = false
    add := collections_test_membership_add(t, set, 70, 80, 90)
    _, duplicate := make_collection_animation_add_mutation(
        set, collection, collections_test_id(81), animation)
    testing.expect_value(t, duplicate, Policy_Error.Already_In_Collection)
    testing.expect_value(t, apply_mutation(set, add), Mutation_Error.Policy)
    set.entries[0].sibling_order = max(i64)
    _, overflow := make_collection_animation_add_mutation(
        set, collection, collections_test_id(81), collections_test_id(91))
    testing.expect_value(t, overflow, Policy_Error.Order_Overflow)
    testing.expect_value(t, set.entry_count, 1)
}

// Custom memberships share animation identity without sharing aliases, order or Favorites policy.
@(test)
collections_membership_preserves_other_destinations :: proc(t: ^testing.T) {
    set := collections_test_membership_set(t)
    defer collections_test_destroy(set)
    _ = collections_test_membership_add(t, set, 70, 80, 90)
    _ = collections_test_membership_add(t, set, 71, 81, 90)
    testing.expect_value(t,
        favorites_add(set, collections_test_id(82), collections_test_id(90)),
        Policy_Error.None)
    identity, policy := collection_animation_identity(
        set, collections_test_id(70), collections_test_id(90))
    testing.expect_value(t, policy, Policy_Error.None)
    rename, _ := make_placement_name_mutation(identity, "Independent")
    testing.expect_value(t, apply_mutation(set, rename), Mutation_Error.None)
    remove, remove_policy := make_collection_animation_remove_mutation(set, identity)
    testing.expect_value(t, remove_policy, Policy_Error.None)
    testing.expect_value(t, apply_mutation(set, remove), Mutation_Error.None)
    testing.expect_value(t, set.entry_count, 2)
    for entry in set.entries[:set.entry_count] {
        testing.expect_value(t, entry.animation_id, collections_test_id(90))
        testing.expect_value(t, entry.custom_name_length, 0)
        testing.expect_value(t, entry.sibling_order, i64(0))
    }
    testing.expect_value(t, validate(set), Validation_Error.None)
}

// Re-adding allocates a fresh root at the end, with no removed alias or copied label history.
@(test)
collections_membership_readd_resets_alias_and_rejects_stale_remove :: proc(
    t: ^testing.T) {
    set := collections_test_membership_set(t)
    defer collections_test_destroy(set)
    first := collections_test_membership_add(t, set, 70, 80, 90)
    _ = collections_test_membership_add(t, set, 70, 81, 91)
    rename, _ := make_placement_name_mutation(first.placement, "Old alias")
    testing.expect_value(t, apply_mutation(set, rename), Mutation_Error.None)
    testing.expect_value(t,
        placement_canonical_name_set(set, first.placement, "Old catalogue"),
        Policy_Error.None)
    remove, _ := make_collection_animation_remove_mutation(set, first.placement)
    testing.expect_value(t, apply_mutation(set, remove), Mutation_Error.None)
    _ = collections_test_membership_add(t, set, 70, 82, 90)
    testing.expect_value(t, apply_mutation(set, remove), Mutation_Error.Policy)
    current, _ := collection_animation_identity(
        set, collections_test_id(70), collections_test_id(90))
    testing.expect_value(t, current.entry_id, collections_test_id(82))
    placement, _ := placement_resolve(set, current)
    testing.expect_value(t, placement.custom_name_length, 0)
    testing.expect_value(t, placement.canonical_name_length, 0)
    testing.expect_value(t, placement.sibling_order, i64(2))
    remove, _ = make_collection_animation_remove_mutation(set, current)
    remove.placement.collection_id = collections_test_id(71)
    testing.expect_value(t, apply_mutation(set, remove), Mutation_Error.Policy)
    remove.placement = current
    remove.animation_id = collections_test_id(91)
    testing.expect_value(t, apply_mutation(set, remove), Mutation_Error.Policy)
    testing.expect_value(t, set.entry_count, 2)
}

// Preserve nested groups while enforcing membership uniqueness over the whole collection.
@(test)
collections_membership_nested_placement_is_exact_and_unique :: proc(t: ^testing.T) {
    set := collections_test_membership_set(t)
    defer collections_test_destroy(set)
    group: Entry = {
        id = collections_test_id(79),
        collection_id = collections_test_id(70),
        kind = .Group,
    }
    testing.expect_value(t, append_entry(set, group), Policy_Error.None)
    nested: Entry = {
        id = collections_test_id(80),
        collection_id = group.collection_id,
        parent_entry_id = group.id,
        kind = .Animation,
        animation_id = collections_test_id(90),
    }
    testing.expect_value(t, append_entry(set, nested), Policy_Error.None)
    identity, _ := collection_animation_identity(
        set, group.collection_id, nested.animation_id)
    testing.expect_value(t, identity.parent_entry_id, group.id)
    duplicate := nested
    duplicate.id = collections_test_id(81)
    duplicate.parent_entry_id = {}
    duplicate.sibling_order = 1
    testing.expect_value(t,
        append_entry(set, duplicate), Policy_Error.Already_In_Collection)
    _ = collections_test_membership_add(t, set, 70, 82, 91)
    testing.expect_value(t, set.entries[2].sibling_order, i64(1))
    collections_test_nested_membership_remove(t, set, identity, group)
}

// Reject a stale parent and group removal while retiring only the exact nested animation.
collections_test_nested_membership_remove :: proc(
    t: ^testing.T, set: ^Set, identity: Placement_Identity, group: Entry) {
    remove, _ := make_collection_animation_remove_mutation(set, identity)
    remove.placement.parent_entry_id = {}
    testing.expect_value(t, apply_mutation(set, remove), Mutation_Error.Policy)
    remove.placement = identity
    testing.expect_value(t, apply_mutation(set, remove), Mutation_Error.None)
    testing.expect_value(t, find_entry(set, group.id), 0)
    testing.expect_value(t, validate(set), Validation_Error.None)
    _, policy := make_collection_animation_remove_mutation(
        set, {group.collection_id, {}, group.id})
    testing.expect_value(t, policy, Policy_Error.Invalid_Identity)
}

// Validation rejects bypassed duplicate storage even when root and child orders are distinct.
@(test)
collections_membership_validation_rejects_duplicate_loaded_shape :: proc(
    t: ^testing.T) {
    set := collections_test_membership_set(t)
    defer collections_test_destroy(set)
    _ = collections_test_membership_add(t, set, 70, 80, 90)
    _ = collections_test_membership_add(t, set, 70, 81, 91)
    set.entries[1].animation_id = collections_test_id(90)
    testing.expect_value(t,
        validate(set), Validation_Error.Duplicate_Collection_Animation)
    _, failure := make_collection_animation_remove_mutation(
        set, {collections_test_id(70), {}, collections_test_id(80)})
    testing.expect_value(t, failure, Policy_Error.Invalid_Set)
}

// Replay rechecks writability and captured scope instead of trusting admission-time policy.
@(test)
collections_membership_replay_rejects_changed_owner_policy :: proc(t: ^testing.T) {
    set := collections_test_membership_set(t)
    defer collections_test_destroy(set)
    add, _ := make_collection_animation_add_mutation(
        set, collections_test_id(70), collections_test_id(80), collections_test_id(90))
    set.collections[1].is_read_only = true
    testing.expect_value(t, apply_mutation(set, add), Mutation_Error.Policy)
    testing.expect_value(t, set.entry_count, 0)
    set.collections[1].is_read_only = false
    testing.expect_value(t, apply_mutation(set, add), Mutation_Error.None)
    remove, _ := make_collection_animation_remove_mutation(set, add.placement)
    set.collections[1].is_read_only = true
    testing.expect_value(t, apply_mutation(set, remove), Mutation_Error.Policy)
    testing.expect_value(t, set.entry_count, 1)
    set.collections[1].is_read_only = false
    deletion, _ := make_collection_delete_mutation(set, add.placement.collection_id)
    testing.expect_value(t, apply_mutation(set, deletion), Mutation_Error.None)
    testing.expect_value(t, apply_mutation(set, add), Mutation_Error.Policy)
    testing.expect_value(t, apply_mutation(set, remove), Mutation_Error.Policy)
}

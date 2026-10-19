#+test
package collections

import "core:testing"

// Deletion removes all owned groups, aliases and unavailable targets, never canonical identities.
@(test)
collections_delete_retires_only_the_exact_custom_owner :: proc(t: ^testing.T) {
    set := collections_test_heads(t)
    defer collections_test_destroy(set)
    owner := collections_test_id(2)
    group := collections_test_id(20)
    for entry in ([]Entry{
        {id = group, collection_id = owner, kind = .Group, sibling_order = 1},
        {id = collections_test_id(21), collection_id = owner,
            parent_entry_id = group, kind = .Animation,
            animation_id = collections_test_id(90), sibling_order = 1},
        {id = collections_test_id(22), collection_id = collections_test_id(3),
            kind = .Animation, animation_id = collections_test_id(90), sibling_order = 1},
    }) {
        testing.expect_value(t, append_entry(set, entry), Policy_Error.None)
    }
    rename, _ := make_placement_name_mutation(
        collections_test_identity(set, collections_test_id(21)), "Alias")
    testing.expect_value(t, apply_mutation(set, rename), Mutation_Error.None)
    testing.expect_value(t, favorites_add(
        set, collections_test_id(23), collections_test_id(90)), Policy_Error.None)
    mutation, failure := make_collection_delete_mutation(set, owner)
    testing.expect_value(t, failure, Policy_Error.None)
    testing.expect_value(t, apply_mutation(set, mutation), Mutation_Error.None)
    testing.expect_value(t, set.collection_count, 3)
    testing.expect_value(t, set.entry_count, 2)
    testing.expect_value(t, find_collection(set, owner), -1)
    testing.expect_value(t, find_entry(set, group), -1)
    testing.expect_value(t, find_entry(set, collections_test_id(21)), -1)
    testing.expect(t, find_entry(set, collections_test_id(22)) >= 0)
    testing.expect(t, favorites_animation_exists(set, collections_test_id(90), -1))
    testing.expect_value(t, validate(set), Validation_Error.None)
    testing.expect_value(t, apply_mutation(set, mutation), Mutation_Error.Policy)
}

// Protected, read-only and absent owners cannot delete; accepted removal never allocates.
@(test)
collections_delete_policy_and_allocation_free_commit :: proc(t: ^testing.T) {
    set := collections_test_heads(t)
    defer collections_test_destroy(set)
    _, protected := make_collection_delete_mutation(set, FAVORITES_COLLECTION_ID)
    testing.expect_value(t, protected, Policy_Error.Read_Only)
    set.collections[1].is_read_only = true
    _, read_only := make_collection_delete_mutation(set, collections_test_id(1))
    testing.expect_value(t, read_only, Policy_Error.Read_Only)
    _, absent := make_collection_delete_mutation(set, collections_test_id(90))
    testing.expect(t, absent != .None)
    mutation, failure := make_collection_delete_mutation(set, collections_test_id(3))
    testing.expect_value(t, failure, Policy_Error.None)
    backing := set.allocator.backing_allocator
    set.allocator.backing_allocator = {procedure = collections_test_reject_backing}
    testing.expect_value(t, apply_mutation(set, mutation), Mutation_Error.None)
    set.allocator.backing_allocator = backing
    testing.expect_value(t, validate(set), Validation_Error.None)
}

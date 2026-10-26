#+test
package collections

import "core:testing"
import storage "../core/storage"

// Populate three custom heads with duplicate labels through ordinary creation admission.
collections_test_heads :: proc(t: ^testing.T) -> ^Set {
    set := collections_test_set()
    for index in 1..=3 {
        mutation, failure := make_collection_create_mutation(
            set, collections_test_id(u8(index)), "Same")
        testing.expect_value(t, failure, Policy_Error.None)
        testing.expect_value(t, apply_mutation(set, mutation), Mutation_Error.None)
    }
    return set
}

// Mandatory head labels enforce byte limits and retain copied text independently.
@(test)
collections_head_names_validate_copy_and_protect_favorites :: proc(t: ^testing.T) {
    set := collections_test_heads(t)
    defer collections_test_destroy(set)
    bytes: [COLLECTION_NAME_MAX_BYTES]u8
    for &value in bytes {
        value = 'x'
    }
    mutation, failure := make_collection_name_mutation(
        set, collections_test_id(1), string(bytes[:]))
    testing.expect_value(t, failure, Policy_Error.None)
    bytes[0] = 'y'
    testing.expect_value(t, apply_mutation(set, mutation), Mutation_Error.None)
    testing.expect_value(t, set^.collections[1].name[0], u8('x'))
    oversized: [COLLECTION_NAME_MAX_BYTES + 1]u8
    for name in ([]string{"", "\xff", "a\x00b", string(oversized[:])}) {
        _, rejected := make_collection_name_mutation(set, collections_test_id(1), name)
        testing.expect_value(t, rejected, Policy_Error.Invalid_Name)
    }
    _, protected := make_collection_name_mutation(set, FAVORITES_COLLECTION_ID, "No")
    testing.expect_value(t, protected, Policy_Error.Read_Only)
    mutation.collection_name_length = 0
    testing.expect_value(t, apply_mutation(set, mutation), Mutation_Error.Invalid_Name)
    testing.expect_value(t, validate(set), Validation_Error.None)
}

// Adjacent swaps exclude Favorites, preserve identities, and reject stale exact neighbors.
@(test)
collections_head_moves_are_adjacent_and_overflow_free :: proc(t: ^testing.T) {
    set := collections_test_heads(t)
    defer collections_test_destroy(set)
    set^.collections[3].order = max(i64)
    _, endpoint := make_collection_move(set, collections_test_id(1), .Up)
    testing.expect_value(t, endpoint, Policy_Error.No_Neighbor)
    move, failure := make_collection_move(set, collections_test_id(3), .Up)
    testing.expect_value(t, failure, Policy_Error.None)
    testing.expect_value(t, apply_mutation(set, move), Mutation_Error.None)
    testing.expect_value(t, set^.collections[2].order, max(i64))
    testing.expect_value(t, set^.collections[3].order, i64(2))
    testing.expect_value(t, apply_mutation(set, move), Mutation_Error.Policy)
    reverse, reverse_error := make_collection_move(set, collections_test_id(3), .Down)
    testing.expect_value(t, reverse_error, Policy_Error.None)
    testing.expect_value(t, apply_mutation(set, reverse), Mutation_Error.None)
    testing.expect_value(t, set^.collections[3].order, max(i64))
    _, protected := make_collection_move(set, FAVORITES_COLLECTION_ID, .Down)
    testing.expect_value(t, protected, Policy_Error.Read_Only)
    testing.expect_value(t, validate(set), Validation_Error.None)
}

// Exhausting replacement-name storage cannot retire the accepted head label.
@(test)
collections_head_rename_allocation_failure_is_atomic :: proc(t: ^testing.T) {
    set := collections_test_heads(t)
    defer collections_test_destroy(set)
    name: [COLLECTION_NAME_MAX_BYTES]u8
    for &value in name {
        value = 'n'
    }
    mutation, _ := make_collection_name_mutation(
        set, collections_test_id(1), string(name[:]))
    backing := set^.allocator.backing_allocator
    set^.allocator.backing_allocator = {
        procedure = collections_test_reject_backing,
    }
    ballast: [256][]u8
    count := collections_test_exhaust_name_storage(set, ballast[:])
    before := storage.tlsf_owner_diagnostics(&set^.allocator)
    testing.expect_value(t,
        apply_mutation(set, mutation), Mutation_Error.Allocation_Failed)
    after := storage.tlsf_owner_diagnostics(&set^.allocator)
    testing.expect_value(t, before.current_live_bytes, after.current_live_bytes)
    testing.expect_value(t, string(set^.collections[1].name), "Same")
    allocator := storage.tlsf_owner_allocator(&set^.allocator)
    for block in ballast[:count] {
        delete(block, allocator)
    }
    set^.allocator.backing_allocator = backing
    testing.expect_value(t, apply_mutation(set, mutation), Mutation_Error.None)
}

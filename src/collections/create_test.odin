#+test
package collections

import "core:testing"

// Creation retains copied text, distinct identity and replay-time append order.
@(test)
collections_create_empty_duplicates_replay_independently :: proc(t: ^testing.T) {
    set := collections_test_set()
    defer collections_test_destroy(set)
    replay := collections_test_set()
    defer collections_test_destroy(replay)
    source: [4]u8 = {'N', 'a', 'm', 'e'}
    first, failure := make_collection_create_mutation(
        set, collections_test_id(101), string(source[:]))
    testing.expect_value(t, failure, Policy_Error.None)
    source[0] = 'X'
    second, second_error := make_collection_create_mutation(
        set, collections_test_id(102), "Name")
    testing.expect_value(t, second_error, Policy_Error.None)
    for mutation in ([]Mutation{first, second}) {
        testing.expect_value(t, apply_mutation(set, mutation), Mutation_Error.None)
        testing.expect_value(t, apply_mutation(replay, mutation), Mutation_Error.None)
    }
    for index in 1..<3 {
        testing.expect_value(t, string(set^.collections[index].name), "Name")
        testing.expect_value(t, set^.collections[index].order, i64(index))
        testing.expect_value(t,
            replay^.collections[index].id, set^.collections[index].id)
        testing.expect_value(t, set^.collections[index].role, Role.User)
        testing.expect(t, !set^.collections[index].is_read_only)
    }
    testing.expect_value(t, set^.entry_count, 0)
    testing.expect_value(t, validate(set), Validation_Error.None)
    testing.expect_value(t, apply_mutation(set, first), Mutation_Error.Policy)
    testing.expect_value(t, set^.collection_count, 3)
}

// Empty, oversized, malformed UTF-8 and NUL labels never become accepted names.
@(test)
collections_create_rejects_invalid_names_and_reserved_identity :: proc(t: ^testing.T) {
    set := collections_test_set()
    defer collections_test_destroy(set)
    oversized: [COLLECTION_NAME_MAX_BYTES + 1]u8
    for &value in oversized {
        value = 'a'
    }
    for name in ([]string{"", "\xFF", "bad\x00name", string(oversized[:])}) {
        _, failure := make_collection_create_mutation(set, collections_test_id(1), name)
        testing.expect_value(t, failure, Policy_Error.Invalid_Name)
    }
    _, zero := make_collection_create_mutation(set, {}, "Name")
    _, reserved := make_collection_create_mutation(set, FAVORITES_COLLECTION_ID, "Name")
    _, missing := make_collection_create_mutation(nil, collections_test_id(1), "Name")
    testing.expect_value(t, zero, Policy_Error.Invalid_Identity)
    testing.expect_value(t, reserved, Policy_Error.Invalid_Identity)
    testing.expect_value(t, missing, Policy_Error.Invalid_Set)
    testing.expect_value(t, set^.collection_count, 1)
}

// Replay distrusts copied mutation lengths and labels, including malicious payloads.
@(test)
collections_create_revalidates_bounded_payloads :: proc(t: ^testing.T) {
    set := collections_test_set()
    defer collections_test_destroy(set)
    mutation, failure := make_collection_create_mutation(
        set, collections_test_id(1), "é")
    testing.expect_value(t, failure, Policy_Error.None)
    for length in ([]int{-1, 0, COLLECTION_NAME_MAX_BYTES + 1, 1}) {
        invalid := mutation
        invalid.collection_name_length = length
        testing.expect_value(t,
            apply_mutation(set, invalid), Mutation_Error.Invalid_Name)
    }
    invalid := mutation
    invalid.collection_id = FAVORITES_COLLECTION_ID
    testing.expect_value(t, apply_mutation(set, invalid), Mutation_Error.Policy)
    testing.expect_value(t, apply_mutation(set, mutation), Mutation_Error.None)
    _, duplicate := make_collection_create_mutation(set, mutation.collection_id, "Other")
    testing.expect_value(t, duplicate, Policy_Error.Invalid_Identity)
    testing.expect_value(t, set^.collection_count, 2)
}

// Full-byte names are admitted, gaps stay intact and maximum order rejects append.
@(test)
collections_create_append_preserves_gaps_and_rejects_overflow :: proc(t: ^testing.T) {
    set := collections_test_set()
    defer collections_test_destroy(set)
    name: [COLLECTION_NAME_MAX_BYTES]u8
    for &value in name {
        value = 'a'
    }
    first, failure := make_collection_create_mutation(
        set, collections_test_id(1), string(name[:]))
    testing.expect_value(t, failure, Policy_Error.None)
    testing.expect_value(t, apply_mutation(set, first), Mutation_Error.None)
    set^.collections[1].order = 40
    second, second_error := make_collection_create_mutation(
        set, collections_test_id(2), "é")
    testing.expect_value(t, second_error, Policy_Error.None)
    testing.expect_value(t, apply_mutation(set, second), Mutation_Error.None)
    testing.expect_value(t, set^.collections[2].order, i64(41))
    set^.collections[2].order = max(i64)
    _, overflow := make_collection_create_mutation(set, collections_test_id(3), "Name")
    testing.expect_value(t, overflow, Policy_Error.Order_Overflow)
    second.collection_id = collections_test_id(3)
    testing.expect_value(t, apply_mutation(set, second), Mutation_Error.Policy)
    testing.expect_value(t, set^.collection_count, 3)
}

// Loaded/admitted collections use the same name, role and unique-order invariants.
@(test)
collections_validate_custom_name_and_order_contract :: proc(t: ^testing.T) {
    set := collections_test_set()
    defer collections_test_destroy(set)
    first, _ := make_collection_create_mutation(set, collections_test_id(1), "Name")
    testing.expect_value(t, apply_mutation(set, first), Mutation_Error.None)
    set^.collections[1].order = 0
    testing.expect_value(t, validate(set), Validation_Error.Invalid_Collection)
    set^.collections[1].order = 1
    second := first
    second.collection_id = collections_test_id(2)
    testing.expect_value(t, apply_mutation(set, second), Mutation_Error.None)
    set^.collections[2].order = 1
    testing.expect_value(t, validate(set), Validation_Error.Duplicate_Order)
    set^.collections[2].order = 2
    set^.collections[1].name[0] = 0xFF
    testing.expect_value(t, validate(set), Validation_Error.Invalid_Collection)
    set^.collections[1].name[0] = 'N'
    set^.collections[0].order = 3
    testing.expect_value(t, validate(set), Validation_Error.Invalid_Collection)
}

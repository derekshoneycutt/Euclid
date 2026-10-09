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

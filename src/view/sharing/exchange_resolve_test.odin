#+test
package viewsharing

import sharingmodel "../../view/sharing/model"
import sharing "../../sharing"
import "core:encoding/uuid"
import "core:testing"

Exchange_Resolve_Test_Installed :: struct {
    identifiers: [16]uuid.Identifier,
    count: int,
}

// Build a deterministic identifier for resolver fixtures.
exchange_resolve_test_id :: proc(value: u8) -> uuid.Identifier {
    identifier: uuid.Identifier
    identifier[15] = value
    return identifier
}

// Mark one deterministic identifier installed without external catalog access.
exchange_resolve_test_is_installed :: proc(
    animation_id: uuid.Identifier, user_data: rawptr) -> bool {
    installed := cast(^Exchange_Resolve_Test_Installed)user_data
    for candidate in installed.identifiers[:installed.count] {
        if candidate == animation_id {
            return true
        }
    }
    return false
}

// Verify two omitted ancestors promote surviving children to the root in order.
@(test)
exchange_resolve_promotes_through_omitted_ancestors :: proc(t: ^testing.T) {
    source_entries: [5]sharing.Staged_Entry = {
        {
            animation_id = exchange_resolve_test_id(1),
            parent = -1,
        },
        {
            animation_id = exchange_resolve_test_id(2),
            parent = 0,
        },
        {
            animation_id = exchange_resolve_test_id(3),
            parent = 1,
        },
        {
            animation_id = exchange_resolve_test_id(4),
            parent = 1,
        },
        {
            animation_id = exchange_resolve_test_id(5),
            parent = 0,
        },
    }
    source_collection: sharing.Staged_Collection = {
        entries = source_entries[:],
        entry_count = len(source_entries),
        importable = true,
    }
    source_collections: [1]sharing.Staged_Collection = {source_collection}
    document: sharing.Staged_Document = {
        collections = source_collections[:],
        collection_count = 1,
        entry_total = len(source_entries),
        initialized = true,
    }
    installed_identifiers: [16]uuid.Identifier
    installed_identifiers[0] = exchange_resolve_test_id(3)
    installed_identifiers[1] = exchange_resolve_test_id(4)
    installed_identifiers[2] = exchange_resolve_test_id(5)
    installed: Exchange_Resolve_Test_Installed = {
        identifiers = installed_identifiers,
        count = 3,
    }
    resolved_collections: [1]sharingmodel.Exchange_Resolved_Collection
    resolved_entries: [5]sharingmodel.Exchange_Resolved_Entry
    result, ok := exchange_resolve(
        &document, exchange_resolve_test_is_installed, &installed,
        resolved_collections[:], resolved_entries[:])
    testing.expect(t, ok)
    testing.expect_value(t, result.omitted_entry_count, 2)
    testing.expect_value(t, result.entry_count, 3)
    testing.expect_value(t, resolved_entries[0].parent_entry_index, -1)
    testing.expect_value(t, resolved_entries[1].parent_entry_index, -1)
    testing.expect_value(t, resolved_entries[2].parent_entry_index, -1)
    testing.expect_value(t, resolved_entries[0].sibling_order, 0)
    testing.expect_value(t, resolved_entries[1].sibling_order, 1)
    testing.expect_value(t, resolved_entries[2].sibling_order, 2)
}

// Verify all-missing collections are not importable and report each omission.
@(test)
exchange_resolve_rejects_empty_after_all_entries_are_missing :: proc(t: ^testing.T) {
    source_entries: [2]sharing.Staged_Entry = {
        {
            animation_id = exchange_resolve_test_id(1),
            parent = -1,
        },
        {
            animation_id = exchange_resolve_test_id(2),
            parent = 0,
        },
    }
    source_collection: sharing.Staged_Collection = {
        entries = source_entries[:],
        entry_count = len(source_entries),
        importable = true,
    }
    source_collections: [1]sharing.Staged_Collection = {source_collection}
    document: sharing.Staged_Document = {
        collections = source_collections[:],
        collection_count = 1,
        entry_total = len(source_entries),
        initialized = true,
    }
    installed: Exchange_Resolve_Test_Installed
    resolved_collections: [1]sharingmodel.Exchange_Resolved_Collection
    resolved_entries: [2]sharingmodel.Exchange_Resolved_Entry
    result, ok := exchange_resolve(
        &document, exchange_resolve_test_is_installed, &installed,
        resolved_collections[:], resolved_entries[:])
    testing.expect(t, ok)
    testing.expect_value(t, result.omitted_entry_count, 2)
    testing.expect_value(t, resolved_collections[0].resolved_entry_count, 0)
    testing.expect(t, !resolved_collections[0].importable)
}

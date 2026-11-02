#+test
package userdata

import collections "../../collections"
import sqlite "../../sqlite"
import uuid "core:encoding/uuid"
import "core:os"
import "core:testing"

// Persist two plans and verify export rows stream in collection/depth-first order.
@(test)
userdata_collection_exchange_exports_depth_first_notes_and_duplicate_names :: proc(
    t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)
    store: Store
    testing.expect_value(t, store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    defer store_close(&store)
    collection_rows: [2]Import_Plan_Collection
    entry_rows: [4]Import_Plan_Entry
    plan: Collection_Import_Plan
    userdata_exchange_build_export_plan(
        &plan, collection_rows[:], entry_rows[:])
    testing.expect_value(t, store_import_collections(&store, &plan).kind,
        Store_Error_Kind.None)
    userdata_exchange_expect_export_rows(t, &store)
}

// Build collections with a named parent, child, note, and one empty duplicate label.
userdata_exchange_build_export_plan :: proc(
    plan: ^Collection_Import_Plan,
    collection_rows: []Import_Plan_Collection,
    entry_rows: []Import_Plan_Entry) {
    collection_rows[0] = {
        id = userdata_test_id(31),
        name = "Repeated",
    }
    collection_rows[1] = {
        id = userdata_test_id(32),
        name = "Repeated",
    }
    userdata_exchange_set_export_entries(entry_rows)
    plan^ = {
        collections = collection_rows,
        entries = entry_rows,
    }
}

// Fill entries in depth-first order with notes on both selected collections.
userdata_exchange_set_export_entries :: proc(entry_rows: []Import_Plan_Entry) {
    entry_rows[0] = {
        collection = 0,
        parent = -1,
        id = userdata_test_id(41),
        animation_id = userdata_test_id(51),
        sibling_order = 0,
        name = "Parent",
        note = "π note",
        has_note = true,
        notes_on_top = true,
    }
    entry_rows[1] = {
        collection = 0,
        parent = 0,
        id = userdata_test_id(42),
        animation_id = userdata_test_id(52),
        sibling_order = 0,
    }
    entry_rows[2] = {
        collection = 0,
        parent = -1,
        id = userdata_test_id(43),
        animation_id = userdata_test_id(53),
        sibling_order = 1,
    }
    entry_rows[3] = {
        collection = 1,
        parent = -1,
        id = userdata_test_id(44),
        animation_id = userdata_test_id(54),
        sibling_order = 0,
        note = "second",
        has_note = true,
    }
}

// Read the selected collections and assert stable collection and DFS row order.
userdata_exchange_expect_export_rows :: proc(t: ^testing.T, store: ^Store) {
    selected: [2]uuid.Identifier = {
        userdata_test_id(32),
        userdata_test_id(31),
    }
    cursor: Collection_Export_Cursor
    testing.expect_value(t,
        store_export_begin(store, selected[:], &cursor).kind, Store_Error_Kind.None)
    rows: [8]Collection_Export_Row
    row_count := 0
    for {
        has_row, failure := store_export_next(&cursor, &rows[row_count])
        testing.expect_value(t, failure.kind, Store_Error_Kind.None)
        if !has_row || !store_error_is_clear(failure) {
            break
        }
        row_count += 1
    }
    testing.expect_value(t, row_count, 6)
    userdata_exchange_expect_export_content(t, rows[:row_count])
    testing.expect_value(t, store_export_end(&cursor).kind, Store_Error_Kind.None)
}

// Verify the export's entry depths, notes, custom names, and repeated labels.
userdata_exchange_expect_export_content :: proc(
    t: ^testing.T, rows: []Collection_Export_Row) {
    testing.expect_value(t, rows[0].kind, Collection_Export_Row_Kind.Collection)
    testing.expect_value(t, string(rows[0].name[:rows[0].name_length]), "Repeated")
    testing.expect_value(t, rows[0].entry_count, 1)
    testing.expect_value(t, rows[1].kind, Collection_Export_Row_Kind.Entry)
    testing.expect_value(t, rows[1].depth, 0)
    testing.expect_value(t, string(rows[1].note[:rows[1].note_length]), "second")
    testing.expect_value(t, rows[2].kind, Collection_Export_Row_Kind.Collection)
    testing.expect_value(t, rows[2].entry_count, 3)
    testing.expect_value(t, string(rows[3].name[:rows[3].name_length]), "Parent")
    testing.expect_value(t, string(rows[3].note[:rows[3].note_length]), "π note")
    testing.expect(t, rows[3].notes_on_top)
    testing.expect_value(t, rows[4].depth, 1)
    testing.expect_value(t, rows[5].depth, 0)
    testing.expect_value(t, rows[5].animation_id, userdata_test_id(53))
}

// A damaged over-limit note is returned as an explicit capacity error, never truncated.
@(test)
userdata_collection_exchange_export_rejects_overlong_database_note :: proc(
    t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)
    store: Store
    testing.expect_value(t, store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    defer store_close(&store)
    collection_rows: [1]Import_Plan_Collection
    entry_rows: [1]Import_Plan_Entry
    plan: Collection_Import_Plan
    userdata_exchange_build_single_entry_plan(
        &plan, collection_rows[:], entry_rows[:], [3]u8{61, 62, 63})
    testing.expect_value(t, store_import_collections(&store, &plan).kind,
        Store_Error_Kind.None)
    userdata_exchange_insert_overlong_note(t, &store)
    userdata_exchange_expect_overlong_export_failure(t, &store)
}

// Insert a 4097-byte note with checks disabled to exercise exact bounded reads.
userdata_exchange_insert_overlong_note :: proc(t: ^testing.T, store: ^Store) {
    testing.expect(t, store_sqlite_error_is_clear(
        store_exec(store, "PRAGMA ignore_check_constraints=ON")))
    statement: sqlite.Statement
    failure := sqlite.statement_prepare_text(
        &store.connection, &statement,
        "INSERT INTO user_collection_note VALUES (?1, ?2, ?3, 0)")
    testing.expect(t, store_sqlite_error_is_clear(failure))
    if !store_sqlite_error_is_clear(failure) {
        return
    }
    defer sqlite.statement_finalize(&statement)
    note: [COLLECTION_EXPORT_NOTE_CAPACITY + 1]u8
    for index in 0..<len(note) {
        note[index] = 'x'
    }
    collection_id := userdata_test_id(61)
    entry_id := userdata_test_id(62)
    failure = sqlite.statement_bind_blob(&statement, 1, collection_id[:])
    testing.expect(t, store_sqlite_error_is_clear(failure))
    failure = sqlite.statement_bind_blob(&statement, 2, entry_id[:])
    testing.expect(t, store_sqlite_error_is_clear(failure))
    failure = sqlite.statement_bind_text(&statement, 3, string(note[:]))
    testing.expect(t, store_sqlite_error_is_clear(failure))
    _, failure = sqlite.statement_step(&statement)
    testing.expect(t, store_sqlite_error_is_clear(failure))
}

// Assert the export cursor aborts and reports the oversized note precisely.
userdata_exchange_expect_overlong_export_failure :: proc(
    t: ^testing.T, store: ^Store) {
    selected: [1]uuid.Identifier = {userdata_test_id(61)}
    cursor: Collection_Export_Cursor
    testing.expect_value(t,
        store_export_begin(store, selected[:], &cursor).kind, Store_Error_Kind.None)
    row: Collection_Export_Row
    _, failure := store_export_next(&cursor, &row)
    testing.expect_value(t, failure.kind, Store_Error_Kind.None)
    _, failure = store_export_next(&cursor, &row)
    testing.expect_value(t, failure.kind, Store_Error_Kind.Read)
    testing.expect_value(
        t, failure.sqlite_error.validation, sqlite.Validation_Error.Capacity)
}

// Reject Favorites before an export cursor can publish rows.
@(test)
userdata_collection_exchange_export_rejects_favorites :: proc(t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)
    store: Store
    testing.expect_value(t, store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    defer store_close(&store)
    selected: [1]uuid.Identifier = {collections.FAVORITES_COLLECTION_ID}
    cursor: Collection_Export_Cursor
    failure := store_export_begin(&store, selected[:], &cursor)
    testing.expect_value(t, failure.kind, Store_Error_Kind.Invalid_Batch)
    testing.expect(t, !cursor.in_transaction)
    testing.expect(t, cursor.ended)
}

// Reimport the same label with fresh IDs and ensure neither import merges nor renames.
@(test)
userdata_collection_exchange_import_keeps_duplicate_names_and_fresh_ids :: proc(
    t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)
    store: Store
    testing.expect_value(t, store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    defer store_close(&store)
    first_collections: [2]Import_Plan_Collection
    second_collections: [2]Import_Plan_Collection
    first: Collection_Import_Plan
    second: Collection_Import_Plan
    userdata_exchange_build_two_collection_plan(
        &first, first_collections[:], 71, 72)
    userdata_exchange_build_two_collection_plan(
        &second, second_collections[:], 73, 74)
    testing.expect_value(t, store_import_collections(&store, &first).kind,
        Store_Error_Kind.None)
    testing.expect_value(t, store_import_collections(&store, &second).kind,
        Store_Error_Kind.None)
    userdata_exchange_expect_imported_collections(t, &store)
}

// Build two same-named empty collections with new caller-supplied UUIDs.
userdata_exchange_build_two_collection_plan :: proc(
    plan: ^Collection_Import_Plan, values: []Import_Plan_Collection,
    first_id, second_id: u8) {
    values[0] = {
        id = userdata_test_id(first_id),
        name = "Same name",
    }
    values[1] = {
        id = userdata_test_id(second_id),
        name = "Same name",
    }
    plan^ = {
        collections = values,
    }
}

// Reload and verify all duplicate labels remain distinct and unchanged.
userdata_exchange_expect_imported_collections :: proc(
    t: ^testing.T, store: ^Store) {
    snapshot := new(collections.Set, context.allocator)
    defer userdata_test_free_collection_set(snapshot)
    testing.expect(t, collections.initialize(snapshot))
    testing.expect_value(t,
        store_load_collections(store, snapshot).kind, Store_Error_Kind.None)
    testing.expect_value(t, snapshot.collection_count, 5)
    for index in 1..<snapshot.collection_count {
        testing.expect_value(t, string(snapshot.collections[index].name), "Same name")
    }
    testing.expect_value(t, snapshot.collections[1].id, userdata_test_id(71))
    testing.expect_value(t, snapshot.collections[2].id, userdata_test_id(72))
    testing.expect_value(t, snapshot.collections[3].id, userdata_test_id(73))
    testing.expect_value(t, snapshot.collections[4].id, userdata_test_id(74))
}

// A duplicate persisted identity rolls back earlier rows in the same import.
@(test)
userdata_collection_exchange_import_duplicate_id_rolls_back :: proc(t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)
    store: Store
    testing.expect_value(t, store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    defer store_close(&store)
    existing_collections: [2]Import_Plan_Collection
    existing: Collection_Import_Plan
    userdata_exchange_build_two_collection_plan(
        &existing, existing_collections[:], 81, 82)
    testing.expect_value(t, store_import_collections(&store, &existing).kind,
        Store_Error_Kind.None)
    duplicate: [2]Import_Plan_Collection = {
        {
            id = userdata_test_id(83),
            name = "Will roll back",
        },
        {
            id = userdata_test_id(81),
            name = "Duplicate",
        },
    }
    plan: Collection_Import_Plan = {
        collections = duplicate[:],
    }
    failure := store_import_collections(&store, &plan)
    testing.expect_value(t, failure.kind, Store_Error_Kind.Write)
    userdata_exchange_expect_collection_count(t, &store, 3)
}

// A deterministic failure after the first inserted collection leaves no partial rows.
@(test)
userdata_collection_exchange_import_failure_after_first_insert_rolls_back :: proc(
    t: ^testing.T) {
    fixture := userdata_test_path(t)
    testing.expect(t, fixture.valid)
    if !fixture.valid {
        return
    }
    defer os.remove_all(fixture.directory)
    store: Store
    testing.expect_value(t, store_open(&store, fixture.path).kind, Store_Error_Kind.None)
    defer store_close(&store)
    plan_collections: [2]Import_Plan_Collection
    plan: Collection_Import_Plan
    userdata_exchange_build_two_collection_plan(
        &plan, plan_collections[:], 91, 92)
    failure := store_import_collections_internal(&store, &plan, 1)
    testing.expect_value(t, failure.kind, Store_Error_Kind.Write)
    userdata_exchange_expect_collection_count(t, &store, 1)
}

// Reload the collection set to assert an exact durable collection count.
userdata_exchange_expect_collection_count :: proc(
    t: ^testing.T, store: ^Store, expected: int) {
    snapshot := new(collections.Set, context.allocator)
    defer userdata_test_free_collection_set(snapshot)
    testing.expect(t, collections.initialize(snapshot))
    testing.expect_value(t,
        store_load_collections(store, snapshot).kind, Store_Error_Kind.None)
    testing.expect_value(t, snapshot.collection_count, expected)
}

// Build one collection and root animation entry for export error fixtures.
userdata_exchange_build_single_entry_plan :: proc(
    plan: ^Collection_Import_Plan,
    collection_rows: []Import_Plan_Collection,
    entry_rows: []Import_Plan_Entry,
    ids: [3]u8) {
    collection_rows[0] = {
        id = userdata_test_id(ids[0]),
        name = "Oversized note",
    }
    entry_rows[0] = {
        collection = 0,
        parent = -1,
        id = userdata_test_id(ids[1]),
        animation_id = userdata_test_id(ids[2]),
        sibling_order = 0,
    }
    plan^ = {
        collections = collection_rows,
        entries = entry_rows,
    }
}

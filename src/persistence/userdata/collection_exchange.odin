package userdata

import sqlite "../../sqlite"
import collections "../../collections"
import uuid "core:encoding/uuid"
import "core:strings"
import "core:unicode/utf8"

COLLECTION_EXPORT_NAME_CAPACITY :: 256
COLLECTION_EXPORT_NOTE_CAPACITY :: 4096

READ_COLLECTION_EXPORT_SQL :: #load("sql/read_collection_export.sql", string)
READ_COLLECTION_EXPORT_ENTRIES_SQL :: #load(
    "sql/read_collection_export_entries.sql", string)
READ_NEXT_COLLECTION_ORDER_SQL :: #load(
    "sql/read_next_collection_order.sql", string)

Collection_Export_Row_Kind :: enum u8 {
    Collection,
    Entry,
}

// Collection_Export_Row is a fixed-buffer persistence row independent of the codec.
Collection_Export_Row :: struct {
    kind: Collection_Export_Row_Kind,
    animation_id: uuid.Identifier,
    depth: int,
    name: [COLLECTION_EXPORT_NAME_CAPACITY]u8,
    name_length: int,
    note: [COLLECTION_EXPORT_NOTE_CAPACITY]u8,
    note_length: int,
    has_note: bool,
    notes_on_top: bool,
    entry_count: int,
}

// Collection_Export_Cursor borrows selected IDs and owns its SQLite snapshot statements.
Collection_Export_Cursor :: struct {
    store: ^Store,
    collection_ids: []uuid.Identifier,
    metadata_statement: sqlite.Statement,
    entries_statement: sqlite.Statement,
    collection_index: int,
    active_entry_count: int,
    active_entry_rows: int,
    active_collection_id: uuid.Identifier,
    active_entries: bool,
    in_transaction: bool,
    ended: bool,
}

// A Collection_Import_Plan borrows names and notes from the staged arena.
Collection_Import_Plan :: struct {
    collections: []Import_Plan_Collection,
    entries: []Import_Plan_Entry,
}

Import_Plan_Collection :: struct {
    id: uuid.Identifier,
    name: string,
}

// Import_Plan_Entry carries identity and a prior depth-first plan-local parent index.
Import_Plan_Entry :: struct {
    collection: int,
    parent: int,
    id: uuid.Identifier,
    animation_id: uuid.Identifier,
    sibling_order: int,
    name: string,
    note: string,
    has_note: bool,
    notes_on_top: bool,
}

Collection_Export_Metadata :: struct {
    name: [COLLECTION_EXPORT_NAME_CAPACITY]u8,
    name_length: int,
    entry_count: int,
}

// Open one read snapshot and validate every selected user collection without buffering rows.
store_export_begin :: proc(
    store: ^Store, collection_ids: []uuid.Identifier,
    cursor: ^Collection_Export_Cursor) -> Store_Error {
    if !store_export_begin_valid(store, collection_ids, cursor) {
        return {
            kind = .Invalid_Batch,
        }
    }
    begin_error := store_exec(store, "BEGIN")
    if !store_sqlite_error_is_clear(begin_error) {
        return {
            kind = .Read,
            sqlite_error = begin_error,
        }
    }
    cursor^ = {
        store = store,
        collection_ids = collection_ids,
        in_transaction = true,
    }
    failure := store_export_prepare(cursor)
    if store_error_is_clear(failure) {
        failure = store_export_validate_selection(cursor)
    }
    if !store_error_is_clear(failure) {
        return store_export_abort(cursor, failure)
    }
    return {}
}

// Reject invalid ownership, selection, and cursor state before starting a transaction.
store_export_begin_valid :: proc(
    store: ^Store, collection_ids: []uuid.Identifier,
    cursor: ^Collection_Export_Cursor) -> bool {
    return store != nil && cursor != nil && !cursor.in_transaction &&
        cursor.metadata_statement.handle == nil &&
        cursor.entries_statement.handle == nil &&
        (store.status == .Ready || store.status == .Read_Only) &&
        len(collection_ids) > 0
}

// Prepare both reusable row queries owned by the export cursor.
store_export_prepare :: proc(cursor: ^Collection_Export_Cursor) -> Store_Error {
    failure := sqlite.statement_prepare_text(
        &cursor.store.connection, &cursor.metadata_statement,
        READ_COLLECTION_EXPORT_SQL)
    if !store_sqlite_error_is_clear(failure) {
        return {
            kind = .Read,
            sqlite_error = failure,
        }
    }
    failure = sqlite.statement_prepare_text(
        &cursor.store.connection, &cursor.entries_statement,
        READ_COLLECTION_EXPORT_ENTRIES_SQL)
    if !store_sqlite_error_is_clear(failure) {
        return {
            kind = .Read,
            sqlite_error = failure,
        }
    }
    return {}
}

// Validate all selected IDs and reject Favorites before exposing any export row.
store_export_validate_selection :: proc(
    cursor: ^Collection_Export_Cursor) -> Store_Error {
    for collection_id, index in cursor.collection_ids {
        if collection_id == (uuid.Identifier{}) {
            return {
                kind = .Invalid_Batch,
            }
        }
        for previous in 0..<index {
            if cursor.collection_ids[previous] == collection_id {
                return {
                    kind = .Invalid_Batch,
                }
            }
        }
        _, failure := store_export_metadata(cursor, collection_id)
        if !store_error_is_clear(failure) {
            return failure
        }
    }
    return {}
}

// Pull the next collection or depth-first entry row from the stable read snapshot.
store_export_next :: proc(
    cursor: ^Collection_Export_Cursor,
    row: ^Collection_Export_Row) -> (bool, Store_Error) {
    if cursor == nil || row == nil || !cursor.in_transaction || cursor.ended {
        return false, {
            kind = .Invalid_State,
        }
    }
    row^ = {}
    for {
        if cursor.active_entries {
            has_row, failure := store_export_next_entry(cursor, row)
            if !store_error_is_clear(failure) || has_row {
                return has_row, failure
            }
        }
        if cursor.collection_index >= len(cursor.collection_ids) {
            return false, {}
        }
        has_row, failure := store_export_next_collection(cursor, row)
        if !store_error_is_clear(failure) || has_row {
            return has_row, failure
        }
    }
}

// Fetch one collection record, then prime its entry query for subsequent calls.
store_export_next_collection :: proc(
    cursor: ^Collection_Export_Cursor,
    row: ^Collection_Export_Row) -> (bool, Store_Error) {
    collection_id := cursor.collection_ids[cursor.collection_index]
    cursor.collection_index += 1
    metadata, failure := store_export_metadata(cursor, collection_id)
    if !store_error_is_clear(failure) {
        return false, store_export_abort(cursor, failure)
    }
    row.kind = .Collection
    row.name = metadata.name
    row.name_length = metadata.name_length
    row.entry_count = metadata.entry_count
    cursor.active_collection_id = collection_id
    cursor.active_entry_count = metadata.entry_count
    cursor.active_entry_rows = 0
    collection_id_copy := collection_id
    sql_failure := sqlite.statement_reset(&cursor.entries_statement)
    if store_sqlite_error_is_clear(sql_failure) {
        sql_failure = sqlite.statement_bind_blob(
            &cursor.entries_statement, 1, collection_id_copy[:])
    }
    if !store_sqlite_error_is_clear(sql_failure) {
        return false, store_export_abort(cursor, {
            kind = .Read,
            sqlite_error = sql_failure,
        })
    }
    cursor.active_entries = true
    return true, {}
}

// Fetch and exactly decode one entry row, including optional placement notes.
store_export_next_entry :: proc(
    cursor: ^Collection_Export_Cursor,
    row: ^Collection_Export_Row) -> (bool, Store_Error) {
    status, failure := sqlite.statement_step(&cursor.entries_statement)
    if !store_sqlite_error_is_clear(failure) {
        return false, store_export_abort(cursor, {
            kind = .Read,
            sqlite_error = failure,
        })
    }
    if status == .Done {
        return store_export_entries_done(cursor)
    }
    if status != .Row {
        failure = sqlite.sqlite_make_validation_error(.Step, .Invalid_State)
        return false, store_export_abort(cursor, {
            kind = .Read,
            sqlite_error = failure,
        })
    }
    failure = store_export_decode_entry(&cursor.entries_statement, row)
    if !store_sqlite_error_is_clear(failure) {
        return false, store_export_abort(cursor, {
            kind = .Read,
            sqlite_error = failure,
        })
    }
    cursor.active_entry_rows += 1
    return true, {}
}

// Reset a finished tree query and verify its rows match the collection count.
store_export_entries_done :: proc(
    cursor: ^Collection_Export_Cursor) -> (bool, Store_Error) {
    failure := sqlite.statement_reset(&cursor.entries_statement)
    if !store_sqlite_error_is_clear(failure) {
        return false, store_export_abort(cursor, {
            kind = .Read,
            sqlite_error = failure,
        })
    }
    cursor.active_entries = false
    if cursor.active_entry_rows != cursor.active_entry_count {
        failure = sqlite.sqlite_make_validation_error(.Step, .Invalid_State)
        return false, store_export_abort(cursor, {
            kind = .Invalid_Schema,
            sqlite_error = failure,
        })
    }
    return false, {}
}

// Read collection metadata into bounded storage and reject unsupported stored nodes.
store_export_metadata :: proc(
    cursor: ^Collection_Export_Cursor,
    collection_id: uuid.Identifier) -> (Collection_Export_Metadata, Store_Error) {
    statement := &cursor.metadata_statement
    failure := sqlite.statement_reset(statement)
    if store_sqlite_error_is_clear(failure) {
        collection_id_copy := collection_id
        failure = sqlite.statement_bind_blob(statement, 1, collection_id_copy[:])
    }
    if !store_sqlite_error_is_clear(failure) {
        return {}, store_export_statement_failure(statement, failure)
    }
    status, step_failure := sqlite.statement_step(statement)
    if !store_sqlite_error_is_clear(step_failure) {
        return {}, store_export_statement_failure(statement, step_failure)
    }
    if status != .Row {
        failure = sqlite.sqlite_make_validation_error(.Step, .Invalid_Argument)
        return {}, store_export_statement_failure(statement, failure)
    }
    result, row_failure := store_export_metadata_row(statement)
    failure = row_failure
    failure = store_reset_preserving(statement, failure)
    if !store_sqlite_error_is_clear(failure) {
        return {}, store_export_metadata_failure(failure)
    }
    return result, {}
}

// Decode metadata, require exactly one row, and retain the original SQLite failure.
store_export_metadata_row :: proc(
    statement: ^sqlite.Statement) -> (Collection_Export_Metadata, sqlite.Error) {
    result, failure := store_export_decode_metadata(statement)
    if !store_sqlite_error_is_clear(failure) {
        return {}, failure
    }
    status, step_failure := sqlite.statement_step(statement)
    if !store_sqlite_error_is_clear(step_failure) {
        return {}, step_failure
    }
    if status != .Done {
        return {}, sqlite.sqlite_make_validation_error(.Step, .Invalid_State)
    }
    return result, {}
}

// Convert a missing or ineligible export selection into a public batch error.
store_export_metadata_failure :: proc(failure: sqlite.Error) -> Store_Error {
    kind := Store_Error_Kind.Read
    if failure.validation == .Invalid_Argument {
        kind = .Invalid_Batch
    }
    return {
        kind = kind,
        sqlite_error = failure,
    }
}

// Decode a user collection's exact name and nonnegative export counts.
store_export_decode_metadata :: proc(
    statement: ^sqlite.Statement) -> (Collection_Export_Metadata, sqlite.Error) {
    if sqlite.column_type(statement, 0) != .Null {
        return {}, sqlite.sqlite_make_validation_error(.Column, .Invalid_Argument)
    }
    if sqlite.column_type(statement, 1) != .Text {
        return {}, sqlite.sqlite_make_validation_error(.Column, .Type_Mismatch)
    }
    result: Collection_Export_Metadata
    length, failure := sqlite.column_text_copy(
        statement, 1, result.name[:])
    if !store_sqlite_error_is_clear(failure) {
        return {}, failure
    }
    if !store_exchange_text_valid(
        string(result.name[:length]), COLLECTION_EXPORT_NAME_CAPACITY, false) {
        return {}, sqlite.sqlite_make_validation_error(.Column, .Type_Mismatch)
    }
    result.name_length = length
    result.entry_count, failure = store_export_integer(statement, 2)
    if !store_sqlite_error_is_clear(failure) {
        return {}, failure
    }
    unsupported_count, unsupported_failure := store_export_integer(statement, 3)
    failure = unsupported_failure
    if !store_sqlite_error_is_clear(failure) {
        return {}, failure
    }
    if unsupported_count != 0 {
        return {}, sqlite.sqlite_make_validation_error(.Column, .Invalid_Argument)
    }
    return result, {}
}

// Read one nonnegative SQLite integer used in collection export metadata.
store_export_integer :: proc(
    statement: ^sqlite.Statement, column: int) -> (int, sqlite.Error) {
    if sqlite.column_type(statement, column) != .Integer {
        return 0, sqlite.sqlite_make_validation_error(.Column, .Type_Mismatch)
    }
    value, failure := sqlite.column_i64(statement, column)
    if !store_sqlite_error_is_clear(failure) {
        return 0, failure
    }
    if value < 0 || value > i64(max(int)) {
        return 0, sqlite.sqlite_make_validation_error(.Column, .Range)
    }
    return int(value), {}
}

// Decode a streamed entry row without truncating names or note text.
store_export_decode_entry :: proc(
    statement: ^sqlite.Statement,
    row: ^Collection_Export_Row) -> sqlite.Error {
    depth, failure := store_export_integer(statement, 0)
    if !store_sqlite_error_is_clear(failure) {
        return failure
    }
    row.depth = depth
    if sqlite.column_type(statement, 1) != .Blob {
        return sqlite.sqlite_make_validation_error(.Column, .Type_Mismatch)
    }
    copied, copy_failure := sqlite.column_blob_copy(
        statement, 1, row.animation_id[:])
    if !store_sqlite_error_is_clear(copy_failure) {
        return copy_failure
    }
    if copied != len(row.animation_id) ||
        row.animation_id == (uuid.Identifier{}) {
        return sqlite.sqlite_make_validation_error(.Column, .Type_Mismatch)
    }
    row.kind = .Entry
    failure = store_export_decode_optional_name(statement, 2, row)
    if store_sqlite_error_is_clear(failure) {
        failure = store_export_decode_note(statement, row)
    }
    return failure
}

// Copy an optional custom name while preserving NULL as an empty format name.
store_export_decode_optional_name :: proc(
    statement: ^sqlite.Statement, column: int,
    row: ^Collection_Export_Row) -> sqlite.Error {
    switch sqlite.column_type(statement, column) {
    case .Null:
        return {}
    case .Text:
        length, failure := sqlite.column_text_copy(
            statement, column, row.name[:])
        if !store_sqlite_error_is_clear(failure) {
            return failure
        }
        if length == 0 || !store_exchange_text_valid(
            string(row.name[:length]), COLLECTION_EXPORT_NAME_CAPACITY, false) {
            return sqlite.sqlite_make_validation_error(.Column, .Type_Mismatch)
        }
        row.name_length = length
        return {}
    case .Invalid, .Integer, .Float, .Blob:
        return sqlite.sqlite_make_validation_error(.Column, .Type_Mismatch)
    }
    return sqlite.sqlite_make_validation_error(.Column, .Type_Mismatch)
}

// Decode an optional note row and its stored reading order exactly.
store_export_decode_note :: proc(
    statement: ^sqlite.Statement,
    row: ^Collection_Export_Row) -> sqlite.Error {
    has_note, failure := store_export_integer(statement, 5)
    if !store_sqlite_error_is_clear(failure) || (has_note != 0 && has_note != 1) {
        return sqlite.sqlite_make_validation_error(.Column, .Range)
    }
    row.has_note = has_note == 1
    if !row.has_note {
        if sqlite.column_type(statement, 3) != .Null ||
            sqlite.column_type(statement, 4) != .Null {
            return sqlite.sqlite_make_validation_error(.Column, .Type_Mismatch)
        }
        return {}
    }
    return store_export_decode_note_values(statement, row)
}

// Copy note content and reading order from an existing note row.
store_export_decode_note_values :: proc(
    statement: ^sqlite.Statement,
    row: ^Collection_Export_Row) -> sqlite.Error {
    if sqlite.column_type(statement, 3) != .Text {
        return sqlite.sqlite_make_validation_error(.Column, .Type_Mismatch)
    }
    length, note_failure := sqlite.column_text_copy(
        statement, 3, row.note[:])
    if !store_sqlite_error_is_clear(note_failure) {
        return note_failure
    }
    if !store_exchange_text_valid(
        string(row.note[:length]), COLLECTION_EXPORT_NOTE_CAPACITY, true) ||
        sqlite.column_type(statement, 4) != .Integer {
        return sqlite.sqlite_make_validation_error(.Column, .Type_Mismatch)
    }
    top, top_failure := sqlite.column_i64(statement, 4)
    if !store_sqlite_error_is_clear(top_failure) {
        return top_failure
    }
    if top != 0 && top != 1 {
        return sqlite.sqlite_make_validation_error(.Column, .Range)
    }
    row.note_length = length
    row.notes_on_top = top == 1
    return {}
}

// Reset a failed metadata statement while preserving the original SQLite error.
store_export_statement_failure :: proc(
    statement: ^sqlite.Statement, failure: sqlite.Error) -> Store_Error {
    return {
        kind = .Read,
        sqlite_error = store_reset_preserving(statement, failure),
    }
}

// Finalize cursor statements and commit the completed read snapshot.
store_export_end :: proc(cursor: ^Collection_Export_Cursor) -> Store_Error {
    if cursor == nil {
        return {
            kind = .Invalid_State,
        }
    }
    if cursor.ended {
        return {}
    }
    failure := store_export_finalize_statements(cursor)
    if !store_sqlite_error_is_clear(failure) {
        return store_export_abort(cursor, {
            kind = .Finalize,
            sqlite_error = failure,
        })
    }
    commit_error := store_exec(cursor.store, "COMMIT")
    if !store_sqlite_error_is_clear(commit_error) {
        return store_export_abort(cursor, {
            kind = .Read,
            sqlite_error = commit_error,
        })
    }
    cursor.in_transaction = false
    cursor.ended = true
    return {}
}

// Abort the snapshot after any cursor failure while preserving cleanup errors.
store_export_abort :: proc(
    cursor: ^Collection_Export_Cursor, failure: Store_Error) -> Store_Error {
    if cursor == nil || cursor.ended {
        return failure
    }
    result: Store_Error = failure
    finalize_error := store_export_finalize_statements(cursor)
    rollback_error: sqlite.Error = {}
    if cursor.in_transaction {
        rollback_error = store_exec(cursor.store, "ROLLBACK")
        cursor.in_transaction = false
    }
    cursor.ended = true
    if !store_sqlite_error_is_clear(rollback_error) {
        cursor.store.status = .Unusable
        return {
            kind = result.kind,
            sqlite_error = result.sqlite_error,
            cleanup_error = rollback_error,
        }
    }
    if !store_sqlite_error_is_clear(finalize_error) &&
        store_sqlite_error_is_clear(result.cleanup_error) {
        result.cleanup_error = finalize_error
    }
    return result
}

// Finalize both cursor-owned statements while retaining the first cleanup failure.
store_export_finalize_statements :: proc(
    cursor: ^Collection_Export_Cursor) -> sqlite.Error {
    failure: sqlite.Error = {}
    if cursor.entries_statement.handle != nil {
        failure = sqlite.statement_finalize(&cursor.entries_statement)
    }
    if cursor.metadata_statement.handle != nil {
        finalize_error := sqlite.statement_finalize(&cursor.metadata_statement)
        if store_sqlite_error_is_clear(failure) {
            failure = finalize_error
        }
    }
    return failure
}

// Validate and atomically insert an immutable staged collection plan.
store_import_collections :: proc(
    store: ^Store, plan: ^Collection_Import_Plan) -> Store_Error {
    return store_import_collections_internal(store, plan, -1)
}

// Commit a plan with a deterministic failure point available to rollback tests.
store_import_collections_internal :: proc(
    store: ^Store, plan: ^Collection_Import_Plan,
    fail_after_inserts: int) -> Store_Error {
    failure := store_import_preflight(store, plan)
    if !store_error_is_clear(failure) {
        return failure
    }
    begin_error := store_exec(store, "BEGIN IMMEDIATE")
    if !store_sqlite_error_is_clear(begin_error) {
        return {
            kind = .Write,
            sqlite_error = begin_error,
        }
    }
    sql_failure := store_exec(store, "PRAGMA defer_foreign_keys=ON")
    next_order := i64(0)
    if store_sqlite_error_is_clear(sql_failure) {
        next_order, sql_failure = store_import_next_order(store)
    }
    if store_sqlite_error_is_clear(sql_failure) {
        sql_failure = store_import_insert_plan(
            store, plan, next_order, fail_after_inserts)
    }
    if !store_sqlite_error_is_clear(sql_failure) {
        return store_rollback_failure(store, .Write, sql_failure)
    }
    sql_failure = store_exec(store, "COMMIT")
    if !store_sqlite_error_is_clear(sql_failure) {
        return store_rollback_failure(store, .Write, sql_failure)
    }
    return {}
}

// Validate plan ownership and bounded text before acquiring the write lock.
store_import_preflight :: proc(
    store: ^Store, plan: ^Collection_Import_Plan) -> Store_Error {
    if store == nil || store.status == .Closed {
        return {
            kind = .Closed,
        }
    }
    if store.status == .Unusable {
        return {
            kind = .Unusable,
        }
    }
    if store.status == .Read_Only {
        return {
            kind = .Not_Writable,
        }
    }
    if plan == nil || len(plan.collections) == 0 ||
        !store_import_plan_valid(plan) {
        return {
            kind = .Invalid_Batch,
        }
    }
    return {}
}

// Check every plan reference, identity, order, and stored-text bound.
store_import_plan_valid :: proc(plan: ^Collection_Import_Plan) -> bool {
    for collection in plan.collections {
        if collection.id == (uuid.Identifier{}) ||
            collection.id == collections.FAVORITES_COLLECTION_ID ||
            !store_exchange_text_valid(
                collection.name, COLLECTION_EXPORT_NAME_CAPACITY, false) {
            return false
        }
    }
    for entry, index in plan.entries {
        if !store_import_entry_valid(plan, index, entry) {
            return false
        }
    }
    return true
}

// Check one entry's collection, parent, identity, sibling order, and content.
store_import_entry_valid :: proc(
    plan: ^Collection_Import_Plan, index: int,
    entry: Import_Plan_Entry) -> bool {
    if entry.collection < 0 || entry.collection >= len(plan.collections) ||
        entry.id == (uuid.Identifier{}) ||
        entry.animation_id == (uuid.Identifier{}) ||
        entry.sibling_order < 0 ||
        !store_exchange_text_valid(
            entry.name, COLLECTION_EXPORT_NAME_CAPACITY, true) ||
        (entry.has_note && !store_exchange_text_valid(
            entry.note, COLLECTION_EXPORT_NOTE_CAPACITY, true)) {
        return false
    }
    if entry.parent < -1 {
        return false
    }
    if entry.parent >= 0 {
        if entry.parent >= index ||
            plan.entries[entry.parent].collection != entry.collection {
            return false
        }
    }
    return true
}

// Read the next durable user-collection order inside the write transaction.
store_import_next_order :: proc(store: ^Store) -> (i64, sqlite.Error) {
    maximum, failure := store_read_integer_query(
        &store.connection, READ_NEXT_COLLECTION_ORDER_SQL)
    if !store_sqlite_error_is_clear(failure) {
        return 0, failure
    }
    if maximum < 0 || maximum == max(i64) {
        return 0, sqlite.sqlite_make_validation_error(.Column, .Range)
    }
    return maximum + 1, {}
}

// Insert collections, entries, and notes in one transaction without mutation-batch limits.
store_import_insert_plan :: proc(
    store: ^Store, plan: ^Collection_Import_Plan,
    next_order: i64, fail_after_inserts: int) -> sqlite.Error {
    insert_count := 0
    for collection, collection_index in plan.collections {
        if next_order > max(i64) - i64(collection_index) {
            return sqlite.sqlite_make_validation_error(.Bind, .Range)
        }
        failure := store_import_insert_collection(
            store, collection, next_order + i64(collection_index))
        if !store_sqlite_error_is_clear(failure) {
            return failure
        }
        insert_count += 1
        if store_import_injected_failure(insert_count, fail_after_inserts) {
            return sqlite.sqlite_make_validation_error(.Step, .Invalid_State)
        }
    }
    return store_import_insert_entries(store, plan, &insert_count, fail_after_inserts)
}

// Insert one imported user collection with a caller-provided identity and order.
store_import_insert_collection :: proc(
    store: ^Store, value: Import_Plan_Collection, order: i64) -> sqlite.Error {
    name_storage: [collections.COLLECTION_NAME_MAX_BYTES]u8
    copy(name_storage[:], transmute([]u8)value.name)
    collection: collections.Collection = {
        id = value.id,
        role = .User,
        name = name_storage[:len(value.name)],
        name_length = len(value.name),
        order = order,
    }
    return store_insert_collection(&store.insert_collection, &collection)
}

// Insert every plan entry and optional note, including parent links by plan index.
store_import_insert_entries :: proc(
    store: ^Store, plan: ^Collection_Import_Plan,
    insert_count: ^int, fail_after_inserts: int) -> sqlite.Error {
    for value in plan.entries {
        failure := store_import_insert_entry(store, plan, value)
        if !store_sqlite_error_is_clear(failure) {
            return failure
        }
        insert_count^ += 1
        if store_import_injected_failure(insert_count^, fail_after_inserts) {
            return sqlite.sqlite_make_validation_error(.Step, .Invalid_State)
        }
        if value.has_note {
            failure = store_write_collection_note_row(
                store,
                {
                    collection_id = plan.collections[value.collection].id,
                    entry_id = value.id,
                },
                value.note,
                value.notes_on_top)
            if !store_sqlite_error_is_clear(failure) {
                return failure
            }
            insert_count^ += 1
            if store_import_injected_failure(insert_count^, fail_after_inserts) {
                return sqlite.sqlite_make_validation_error(.Step, .Invalid_State)
            }
        }
    }
    return {}
}

// Translate a plan entry to the existing transient-binding SQLite insertion path.
store_import_insert_entry :: proc(
    store: ^Store, plan: ^Collection_Import_Plan,
    value: Import_Plan_Entry) -> sqlite.Error {
    name_storage: [collections.ENTRY_NAME_MAX_BYTES]u8
    copy(name_storage[:], transmute([]u8)value.name)
    parent_id: uuid.Identifier = {}
    if value.parent >= 0 {
        parent_id = plan.entries[value.parent].id
    }
    entry: collections.Entry = {
        id = value.id,
        collection_id = plan.collections[value.collection].id,
        parent_entry_id = parent_id,
        sibling_order = i64(value.sibling_order),
        kind = .Animation,
        animation_id = value.animation_id,
        custom_name = name_storage[:len(value.name)],
        custom_name_length = len(value.name),
    }
    return store_insert_collection_entry(&store.insert_collection_entry, &entry)
}

// Match the injected failure count after a completed insert, never before one.
store_import_injected_failure :: proc(
    insert_count, fail_after_inserts: int) -> bool {
    return fail_after_inserts >= 0 && insert_count == fail_after_inserts
}

// Validate UTF-8 bytes and the exact database text bounds without truncation.
store_exchange_text_valid :: proc(
    value: string, max_bytes: int, allow_empty: bool) -> bool {
    return (allow_empty || len(value) > 0) &&
        len(value) <= max_bytes &&
        utf8.valid_string(value) &&
        !strings.contains(value, "\x00")
}

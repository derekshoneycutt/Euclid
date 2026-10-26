package userdata

import sqlite "../sqlite"
import collections "../collections"
import uuid "core:encoding/uuid"
import "core:unicode/utf8"

// Admit the persisted collection topology before a store becomes available.
store_verify_collection_admission :: proc(store: ^Store) -> Store_Error {
    return store_load_collections(store, &store^.collection_replay_workspace)
}

// Load collection and entry rows from one validated SQLite snapshot.
store_load_collections :: proc(
    store: ^Store, destination: ^collections.Set) -> Store_Error {
    if store == nil || destination == nil ||
        (store^.status != .Ready && store^.status != .Read_Only) {
        return {
            kind = .Closed,
        }
    }
    staged := &store^.collection_replay_workspace
    if !staged^.initialized {
        return {
            kind = .Unusable,
        }
    }
    begin_error := store_exec(store, "BEGIN")
    if !store_sqlite_error_is_clear(begin_error) {
        return {
            kind = .Read,
            sqlite_error = begin_error,
        }
    }
    failure := store_read_collection_snapshot(store, staged)
    if !store_error_is_clear(failure) {
        return store_rollback_failure(store, failure.kind, failure.sqlite_error)
    }
    commit_error := store_exec(store, "COMMIT")
    if !store_sqlite_error_is_clear(commit_error) {
        return store_rollback_failure(store, .Read, commit_error)
    }
    if destination != staged && !collections.clone(destination, staged) {
        return {
            kind = .Allocation,
        }
    }
    return {}
}

// Persist a complete validated collection snapshot atomically.
store_replace_collections :: proc(
    store: ^Store, snapshot: ^collections.Set) -> Store_Error {
    if store == nil || snapshot == nil ||
        (store^.status != .Ready && store^.status != .Read_Only) {
        return {
            kind = .Closed,
        }
    }
    if collections.validate(snapshot) != .None {
        return {
            kind = .Invalid_Batch,
        }
    }
    if store^.status == .Read_Only {
        return {
            kind = .Not_Writable,
        }
    }
    begin_error := store_exec(store, "BEGIN IMMEDIATE")
    if !store_sqlite_error_is_clear(begin_error) {
        return {
            kind = .Write,
            sqlite_error = begin_error,
        }
    }
    failure := store_exec(store, "PRAGMA defer_foreign_keys=ON")
    if store_sqlite_error_is_clear(failure) {
        failure = store_apply_collection_snapshot(store, snapshot)
    }
    if !store_sqlite_error_is_clear(failure) {
        return store_rollback_failure(store, .Write, failure)
    }
    failure = store_exec(store, "COMMIT")
    if !store_sqlite_error_is_clear(failure) {
        return store_rollback_failure(store, .Write, failure)
    }
    return {}
}

// Replay an immutable operation batch and persist its final topology in a caller transaction.
store_apply_collection_mutations :: proc(
    store: ^Store, mutations: []collections.Mutation) -> Store_Error {
    if len(mutations) == 0 {
        return {}
    }
    snapshot := &store^.collection_replay_workspace
    if !snapshot^.initialized {
        return {
            kind = .Unusable,
        }
    }
    read_error := store_read_collection_snapshot(store, snapshot)
    if !store_error_is_clear(read_error) {
        return read_error
    }
    for mutation in mutations {
        failure := collections.apply_mutation(snapshot, mutation)
        if failure == .Allocation_Failed {
            return {
                kind = .Allocation,
            }
        }
        if failure != .None {
            return {
                kind = .Write,
                sqlite_error = sqlite.sqlite_make_validation_error(
                    .Bind, .Invalid_Argument),
            }
        }
    }
    write_error := store_exec(store, "PRAGMA defer_foreign_keys=ON")
    if !store_sqlite_error_is_clear(write_error) {
        return {
            kind = .Write,
            sqlite_error = write_error,
        }
    }
    write_error = store_apply_collection_snapshot(store, snapshot)
    if !store_sqlite_error_is_clear(write_error) {
        return {
            kind = .Write,
            sqlite_error = write_error,
        }
    }
    return {}
}

// Reuse replay storage to decode and validate rows inside the caller's transaction.
store_read_collection_snapshot :: proc(
    store: ^Store, snapshot: ^collections.Set) -> Store_Error {
    collections.clear(snapshot)
    failure := store_read_collection_rows(store, snapshot)
    if store_error_is_clear(failure) {
        failure = store_read_collection_entry_rows(store, snapshot)
    }
    if store_error_is_clear(failure) && collections.validate(snapshot) != .None {
        failure = {
            kind = .Invalid_Schema,
        }
    }
    return failure
}

// Read bounded collection rows without retaining SQLite-owned memory.
store_read_collection_rows :: proc(
    store: ^Store, destination: ^collections.Set) -> Store_Error {
    statement := &store^.read_collections
    failure := sqlite.statement_reset(statement)
    if !store_sqlite_error_is_clear(failure) {
        return {
            kind = .Read,
            sqlite_error = failure,
        }
    }
    for {
        status, step_error := sqlite.statement_step(statement)
        if !store_sqlite_error_is_clear(step_error) {
            return store_collection_read_failure(statement, step_error)
        }
        if status == .Done {
            return store_collection_read_reset(statement)
        }
        if status != .Row {
            invalid := sqlite.sqlite_make_validation_error(.Step, .Capacity)
            return store_collection_read_failure(statement, invalid)
        }
        name_buffer: [collections.COLLECTION_NAME_MAX_BYTES]u8
        decoded := store_decode_collection(statement, name_buffer[:])
        if !store_sqlite_error_is_clear(decoded.failure) {
            return store_collection_read_failure(statement, decoded.failure)
        }
        if !decoded.valid {
            invalid := sqlite.sqlite_make_validation_error(.Column, .Type_Mismatch)
            return store_collection_read_failure(statement, invalid)
        }
        append_error := collections.append_collection(destination, decoded.value)
        if append_error != .None {
            return store_collection_read_append_failure(statement, append_error)
        }
    }
}

// Decode a collection row using exact SQLite types and bounded copied text.
store_decode_collection :: proc(
    statement: ^sqlite.Statement,
    name_buffer: []u8) -> Collection_Decode_Result {
    result: Collection_Decode_Result
    id := store_read_uuid(statement, 0)
    result.value.id = id.value
    if !store_sqlite_error_is_clear(id.failure) || !id.valid {
        result.valid = id.valid
        result.failure = id.failure
        return result
    }
    result.valid, result.failure = store_decode_collection_role(
        statement, &result.value, name_buffer)
    if !store_sqlite_error_is_clear(result.failure) || !result.valid {
        return result
    }
    result.value.order, result.failure = sqlite.column_i64(statement, 3)
    if !store_sqlite_error_is_clear(result.failure) {
        return result
    }
    read_only, failure := sqlite.column_i64(statement, 4)
    if !store_sqlite_error_is_clear(failure) {
        result.failure = failure
        return result
    }
    if read_only != 0 && read_only != 1 {
        return result
    }
    result.value.is_read_only = read_only == 1
    result.valid = true
    return result
}

// Decode Favorites role versus a named user collection without label inference.
store_decode_collection_role :: proc(
    statement: ^sqlite.Statement,
    value: ^collections.Collection,
    name_buffer: []u8) -> (bool, sqlite.Error) {
    role_type := sqlite.column_type(statement, 1)
    display_type := sqlite.column_type(statement, 2)
    switch role_type {
    case .Null:
        value^.role = .User
        if display_type != .Text {
            return false, {}
        }
        count, text_error := sqlite.column_text_copy(
            statement, 2, name_buffer)
        if !store_sqlite_error_is_clear(text_error) {
            return false, text_error
        }
        value^.name = name_buffer[:count]
        value^.name_length = count
    case .Text:
        buffer: [16]u8
        count, text_error := sqlite.column_text_copy(statement, 1, buffer[:])
        if !store_sqlite_error_is_clear(text_error) {
            return false, text_error
        }
        if string(buffer[:count]) != "favorites" ||
            display_type != .Null {
            return false, {}
        }
        value^.role = .Favorites
    case .Invalid, .Integer, .Float, .Blob:
        return false, {}
    }
    return true, {}
}

// Read all entry rows and preserve their UUID parent and animation links.
store_read_collection_entry_rows :: proc(
    store: ^Store, destination: ^collections.Set) -> Store_Error {
    statement := &store^.read_collection_entries
    failure := sqlite.statement_reset(statement)
    if !store_sqlite_error_is_clear(failure) {
        return {
            kind = .Read,
            sqlite_error = failure,
        }
    }
    for {
        status, step_error := sqlite.statement_step(statement)
        if !store_sqlite_error_is_clear(step_error) {
            return store_collection_read_failure(statement, step_error)
        }
        if status == .Done {
            return store_collection_read_reset(statement)
        }
        if status != .Row {
            invalid := sqlite.sqlite_make_validation_error(.Step, .Capacity)
            return store_collection_read_failure(statement, invalid)
        }
        name_buffer: [collections.ENTRY_NAME_MAX_BYTES]u8
        decoded := store_decode_collection_entry(statement, name_buffer[:])
        if !store_sqlite_error_is_clear(decoded.failure) {
            return store_collection_read_failure(statement, decoded.failure)
        }
        if !decoded.valid {
            invalid := sqlite.sqlite_make_validation_error(.Column, .Type_Mismatch)
            return store_collection_read_failure(statement, invalid)
        }
        append_error := collections.append_entry(destination, decoded.value)
        if append_error != .None {
            return store_collection_read_append_failure(statement, append_error)
        }
    }
}

// Decode one placement row and reject malformed nullable UUID columns.
store_decode_collection_entry :: proc(
    statement: ^sqlite.Statement,
    name_buffer: []u8) -> Collection_Entry_Decode_Result {
    result := store_decode_entry_links(statement)
    if !store_sqlite_error_is_clear(result.failure) || !result.valid {
        return result
    }
    result.value.sibling_order, result.failure = sqlite.column_i64(statement, 3)
    if !store_sqlite_error_is_clear(result.failure) {
        return result
    }
    kind := store_read_entry_kind(statement, 4)
    result.value.kind = kind.value
    result.valid = kind.valid
    result.failure = kind.failure
    if !store_sqlite_error_is_clear(result.failure) || !result.valid {
        return result
    }
    animation_id := store_read_nullable_uuid(statement, 5)
    result.value.animation_id = animation_id.value
    result.valid = animation_id.valid
    result.failure = animation_id.failure
    if !store_sqlite_error_is_clear(result.failure) || !result.valid {
        return result
    }
    result.valid, result.failure = store_decode_nullable_entry_name(
        statement, 6, &result.value, name_buffer)
    return result
}

// Decode a nullable optional entry name and reject malformed stored text.
store_decode_nullable_entry_name :: proc(
    statement: ^sqlite.Statement,
    column: int,
    value: ^collections.Entry,
    name_buffer: []u8) -> (bool, sqlite.Error) {
    switch sqlite.column_type(statement, column) {
    case .Null:
        return true, {}
    case .Text:
        count, failure := sqlite.column_text_copy(statement, column, name_buffer)
        if !store_sqlite_error_is_clear(failure) {
            return false, failure
        }
        if count == 0 || !utf8.valid_string(string(name_buffer[:count])) {
            return false, {}
        }
        for character in name_buffer[:count] {
            if character == 0 {
                return false, {}
            }
        }
        value^.custom_name = name_buffer[:count]
        value^.custom_name_length = count
        return true, {}
    case .Invalid, .Integer, .Float, .Blob:
        return false, {}
    }
    return false, {}
}

// Decode placement, collection, and nullable parent UUID fields.
store_decode_entry_links :: proc(
    statement: ^sqlite.Statement) -> Collection_Entry_Decode_Result {
    result: Collection_Entry_Decode_Result
    id := store_read_uuid(statement, 0)
    result.value.id = id.value
    result.valid = id.valid
    result.failure = id.failure
    if !store_sqlite_error_is_clear(result.failure) || !result.valid {
        return result
    }
    collection_id := store_read_uuid(statement, 1)
    result.value.collection_id = collection_id.value
    result.valid = collection_id.valid
    result.failure = collection_id.failure
    if !store_sqlite_error_is_clear(result.failure) || !result.valid {
        return result
    }
    parent_id := store_read_nullable_uuid(statement, 2)
    result.value.parent_entry_id = parent_id.value
    result.valid = parent_id.valid
    result.failure = parent_id.failure
    return result
}

// Decode only the two persisted collection entry kinds.
store_read_entry_kind :: proc(
    statement: ^sqlite.Statement, column: int) -> Collection_Kind_Decode_Result {
    result: Collection_Kind_Decode_Result
    if sqlite.column_type(statement, column) != .Text {
        return result
    }
    buffer: [16]u8
    count, failure := sqlite.column_text_copy(statement, column, buffer[:])
    if !store_sqlite_error_is_clear(failure) {
        result.failure = failure
        return result
    }
    switch string(buffer[:count]) {
    case "animation":
        result.value = .Animation
        result.valid = true
    case "group":
        result.value = .Group
        result.valid = true
    }
    return result
}

// Copy an exact 16-byte UUID BLOB from a result row.
store_read_uuid :: proc(
    statement: ^sqlite.Statement,
    column: int) -> Collection_Uuid_Decode_Result {
    result: Collection_Uuid_Decode_Result
    if sqlite.column_type(statement, column) != .Blob {
        return result
    }
    count, failure := sqlite.column_blob_copy(statement, column, result.value[:])
    if !store_sqlite_error_is_clear(failure) {
        result.failure = failure
        return result
    }
    result.valid = count == len(result.value)
    return result
}

// Copy a nullable 16-byte UUID BLOB, mapping SQL NULL to the zero identity.
store_read_nullable_uuid :: proc(
    statement: ^sqlite.Statement,
    column: int) -> Collection_Uuid_Decode_Result {
    if sqlite.column_type(statement, column) == .Null {
        return {
            valid = true,
        }
    }
    return store_read_uuid(statement, column)
}

// Apply a complete snapshot, deferring parent foreign keys until commit.
store_apply_collection_snapshot :: proc(
    store: ^Store, snapshot: ^collections.Set) -> sqlite.Error {
    failure := store_execute_prepared(&store^.delete_collection_entries)
    if store_sqlite_error_is_clear(failure) {
        failure = store_execute_prepared(&store^.delete_collections)
    }
    for index in 0..<snapshot.collection_count {
        if !store_sqlite_error_is_clear(failure) {
            break
        }
        failure = store_insert_collection(
            &store^.insert_collection, &snapshot.collections[index])
    }
    for index in 0..<snapshot.entry_count {
        if !store_sqlite_error_is_clear(failure) {
            break
        }
        failure = store_insert_collection_entry(
            &store^.insert_collection_entry, &snapshot.entries[index])
    }
    return failure
}

// Bind and insert one collection row using transient SQLite-owned copies.
store_insert_collection :: proc(
    statement: ^sqlite.Statement,
    value: ^collections.Collection) -> sqlite.Error {
    failure := sqlite.statement_reset(statement)
    if store_sqlite_error_is_clear(failure) {
        failure = sqlite.statement_bind_blob(statement, 1, value^.id[:])
    }
    if store_sqlite_error_is_clear(failure) && value^.role == .Favorites {
        failure = sqlite.statement_bind_text(statement, 2, "favorites")
    } else if store_sqlite_error_is_clear(failure) {
        failure = sqlite.statement_bind_null(statement, 2)
    }
    if store_sqlite_error_is_clear(failure) && value^.role == .User {
        failure = sqlite.statement_bind_text(
            statement, 3, string(value^.name[:value^.name_length]))
    } else if store_sqlite_error_is_clear(failure) {
        failure = sqlite.statement_bind_null(statement, 3)
    }
    if store_sqlite_error_is_clear(failure) {
        failure = sqlite.statement_bind_i64(statement, 4, value^.order)
    }
    if store_sqlite_error_is_clear(failure) {
        failure = sqlite.statement_bind_i64(
            statement, 5, i64(value^.is_read_only ? 1 : 0))
    }
    if store_sqlite_error_is_clear(failure) {
        _, failure = sqlite.statement_step(statement)
    }
    return store_reset_preserving(statement, failure)
}

// Bind and insert one hierarchical entry, including nullable identity links.
store_insert_collection_entry :: proc(
    statement: ^sqlite.Statement,
    value: ^collections.Entry) -> sqlite.Error {
    failure := sqlite.statement_reset(statement)
    failure = store_bind_collection_entry_identity(statement, value, failure)
    failure = store_bind_collection_entry_values(statement, value, failure)
    if store_sqlite_error_is_clear(failure) {
        _, failure = sqlite.statement_step(statement)
    }
    return store_reset_preserving(statement, failure)
}

// Bind collection and parent identities plus sibling order for one entry row.
store_bind_collection_entry_identity :: proc(
    statement: ^sqlite.Statement,
    value: ^collections.Entry, failure: sqlite.Error) -> sqlite.Error {
    result := failure
    if store_sqlite_error_is_clear(result) {
        result = sqlite.statement_bind_blob(statement, 1, value^.id[:])
    }
    if store_sqlite_error_is_clear(result) {
        result = sqlite.statement_bind_blob(statement, 2, value^.collection_id[:])
    }
    result = store_bind_nullable_entry_uuid(
        statement, 3, value^.parent_entry_id, result)
    if store_sqlite_error_is_clear(result) {
        result = sqlite.statement_bind_i64(statement, 4, value^.sibling_order)
    }
    return result
}

// Bind entry kind, optional animation identity, and optional custom name.
store_bind_collection_entry_values :: proc(
    statement: ^sqlite.Statement,
    value: ^collections.Entry, failure: sqlite.Error) -> sqlite.Error {
    result := failure
    if store_sqlite_error_is_clear(result) {
        kind := value^.kind == .Animation ? "animation" : "group"
        result = sqlite.statement_bind_text(statement, 5, kind)
    }
    result = store_bind_nullable_entry_uuid(
        statement, 6, value^.animation_id, result)
    result = store_bind_nullable_entry_name(statement, 7, value, result)
    return result
}

// Bind one nullable entry UUID to a prepared statement column.
store_bind_nullable_entry_uuid :: proc(
    statement: ^sqlite.Statement, column: int,
    value: uuid.Identifier, failure: sqlite.Error) -> sqlite.Error {
    if !store_sqlite_error_is_clear(failure) {
        return failure
    }
    if value != (uuid.Identifier{}) {
        identifier := value
        return sqlite.statement_bind_blob(statement, column, identifier[:])
    }
    return sqlite.statement_bind_null(statement, column)
}

// Bind one optional placement name, preserving absence as SQL NULL.
store_bind_nullable_entry_name :: proc(
    statement: ^sqlite.Statement, column: int,
    value: ^collections.Entry, failure: sqlite.Error) -> sqlite.Error {
    if !store_sqlite_error_is_clear(failure) {
        return failure
    }
    if value^.custom_name_length > 0 {
        return sqlite.statement_bind_text(statement, column,
            string(value^.custom_name[:value^.custom_name_length]))
    }
    return sqlite.statement_bind_null(statement, column)
}

// Execute one store-owned parameterless statement and return its first failure.
store_execute_prepared :: proc(
    statement: ^sqlite.Statement) -> sqlite.Error {
    failure := sqlite.statement_reset(statement)
    if store_sqlite_error_is_clear(failure) {
        _, failure = sqlite.statement_step(statement)
    }
    return store_reset_preserving(statement, failure)
}

// Preserve an operation error while resetting the reusable read statement.
store_collection_read_failure :: proc(
    statement: ^sqlite.Statement, failure: sqlite.Error) -> Store_Error {
    reset_error := store_reset_preserving(statement, failure)
    return {
        kind = .Read,
        sqlite_error = reset_error,
    }
}

// Reset the active query while preserving an owned-record allocation failure.
store_collection_read_append_failure :: proc(
    statement: ^sqlite.Statement,
    failure: collections.Policy_Error) -> Store_Error {
    reset_error := sqlite.statement_reset(statement)
    if !store_sqlite_error_is_clear(reset_error) {
        return {
            kind = .Read,
            sqlite_error = reset_error,
        }
    }
    if failure == .Allocation_Failed || failure == .Capacity {
        return {
            kind = .Allocation,
        }
    }
    return {
        kind = .Invalid_Schema,
    }
}

// Reset one completed collection query and surface finalization-state errors.
store_collection_read_reset :: proc(
    statement: ^sqlite.Statement) -> Store_Error {
    failure := sqlite.statement_reset(statement)
    if !store_sqlite_error_is_clear(failure) {
        return {
            kind = .Read,
            sqlite_error = failure,
        }
    }
    return {}
}

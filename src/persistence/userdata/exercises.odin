package userdata

import sqlite "../../sqlite"
import crypto "core:crypto"
import uuid "core:encoding/uuid"
import strings "core:strings"
import utf8 "core:unicode/utf8"

// Create one exercise with an internally generated permanent identity.
store_user_exercise_create :: proc(
    store: ^Store,
    draft: User_Exercise_Draft) -> (User_Exercise_Record, Store_Error) {
    failure := store_user_exercise_write_preflight(store, draft)
    if !store_error_is_clear(failure) {
        return {}, failure
    }
    failure = store_user_exercise_begin(store)
    if !store_error_is_clear(failure) {
        return {}, failure
    }
    failure = store_user_exercise_reference_available(store, draft.reference)
    if !store_error_is_clear(failure) {
        return {}, store_user_exercise_rollback(store, failure)
    }
    record: User_Exercise_Record
    record, failure = store_user_exercise_make_new_record(store, draft)
    if !store_error_is_clear(failure) {
        return {}, store_user_exercise_rollback(store, failure)
    }
    failure = store_user_exercise_insert(store, record)
    if !store_error_is_clear(failure) {
        return {}, store_user_exercise_rollback(store, failure)
    }
    failure = store_user_exercise_commit(store)
    if !store_error_is_clear(failure) {
        return {}, failure
    }
    return record, {}
}

// Read one exercise by stable identity without exposing SQLite-owned column bytes.
store_user_exercise_read_by_identity :: proc(
    store: ^Store,
    identity: uuid.Identifier) -> (User_Exercise_Record, Store_Error) {
    failure := store_user_exercise_read_preflight(store)
    if !store_error_is_clear(failure) {
        return {}, failure
    }
    if identity == (uuid.Identifier{}) {
        return {}, {
            kind = .Invalid_Exercise,
        }
    }
    identity_copy := identity
    read_result := store_user_exercise_read_blob(
        &store^.exercise_by_identity, identity_copy[:])
    return store_user_exercise_read_result(
        read_result.record, read_result.found, read_result.failure)
}

// Read one exercise by alias and explicitly report permanently retired aliases.
store_user_exercise_read_by_reference :: proc(
    store: ^Store,
    reference: string) -> (User_Exercise_Record, Store_Error) {
    failure := store_user_exercise_read_preflight(store)
    if !store_error_is_clear(failure) {
        return {}, failure
    }
    if !store_user_exercise_reference_is_valid(reference) {
        return {}, {
            kind = .Invalid_Reference,
        }
    }
    read_result := store_user_exercise_read_text(
        &store^.exercise_by_alias, reference)
    if !store_sqlite_error_is_clear(read_result.failure) || read_result.found {
        return store_user_exercise_read_result(
            read_result.record, read_result.found, read_result.failure)
    }
    retired, retired_error := store_user_exercise_reference_retired(store, reference)
    if !store_sqlite_error_is_clear(retired_error) {
        return {}, {
            kind = .Read,
            sqlite_error = retired_error,
        }
    }
    if retired {
        return {}, {
            kind = .Reference_Retired,
        }
    }
    return {}, {
        kind = .Not_Found,
    }
}

// Read one deterministic page of exercises attached to an exact animation UUID.
store_user_exercise_list :: proc(
    store: ^Store, animation_id: uuid.Identifier,
    result_offset: u32, page_limit: u16) -> (User_Exercise_Page, Store_Error) {
    failure := store_user_exercise_read_preflight(store)
    if !store_error_is_clear(failure) {
        return {}, failure
    }
    if page_limit == 0 || page_limit > USER_EXERCISE_LIST_PAGE_CAPACITY ||
       result_offset > u32(max(i32)) {
        return {}, {
            kind = .Invalid_Exercise,
        }
    }
    page: User_Exercise_Page = {
        result_offset = result_offset,
    }
    count, count_failure := store_user_exercise_list_count(store, animation_id)
    if !store_error_is_clear(count_failure) {
        return {}, count_failure
    }
    page.total_count = count
    row_failure := store_user_exercise_list_rows(
        store, animation_id, result_offset, page_limit, &page)
    if !store_error_is_clear(row_failure) {
        return {}, row_failure
    }
    page.more_available =
        u64(result_offset) + u64(page.returned_count) < u64(page.total_count)
    return page, {}
}

// Count all stored exercises for one animation before selecting a page.
store_user_exercise_list_count :: proc(
    store: ^Store, animation_id: uuid.Identifier) -> (u32, Store_Error) {
    statement := &store^.exercise_list_count
    identity := animation_id
    failure := sqlite.statement_reset(statement)
    if store_sqlite_error_is_clear(failure) {
        if identity == (uuid.Identifier{}) {
            failure = sqlite.statement_bind_null(statement, 1)
        } else {
            failure = sqlite.statement_bind_blob(statement, 1, identity[:])
        }
    }
    if !store_sqlite_error_is_clear(failure) {
        return 0, {
            kind = .Read,
            sqlite_error = store_reset_preserving(statement, failure),
        }
    }
    return store_user_exercise_list_count_read(statement)
}

// Decode the count row, require statement completion, and restore prepared state.
store_user_exercise_list_count_read :: proc(
    statement: ^sqlite.Statement) -> (u32, Store_Error) {
    status, step_failure := sqlite.statement_step(statement)
    if !store_sqlite_error_is_clear(step_failure) || status != .Row {
        if store_sqlite_error_is_clear(step_failure) {
            step_failure = sqlite.sqlite_make_validation_error(.Step, .Invalid_State)
        }
        return 0, {
            kind = .Read,
            sqlite_error = store_reset_preserving(statement, step_failure),
        }
    }
    count, column_failure := sqlite.column_i64(statement, 0)
    if store_sqlite_error_is_clear(column_failure) &&
       (count < 0 || count > i64(max(u32))) {
        column_failure = sqlite.sqlite_make_validation_error(.Column, .Range)
    }
    if store_sqlite_error_is_clear(column_failure) {
        status, column_failure = sqlite.statement_step(statement)
        if store_sqlite_error_is_clear(column_failure) && status != .Done {
            column_failure = sqlite.sqlite_make_validation_error(.Step, .Invalid_State)
        }
    }
    column_failure = store_reset_preserving(statement, column_failure)
    if !store_sqlite_error_is_clear(column_failure) {
        return 0, {
            kind = .Read,
            sqlite_error = column_failure,
        }
    }
    return u32(count), {}
}

// Copy one bounded, title-ordered window without loading instruction bodies.
store_user_exercise_list_rows :: proc(
    store: ^Store, animation_id: uuid.Identifier,
    result_offset: u32, page_limit: u16,
    page: ^User_Exercise_Page) -> Store_Error {
    statement := &store^.exercise_list_rows
    failure := store_user_exercise_list_rows_bind(
        statement, animation_id, result_offset, page_limit)
    if !store_sqlite_error_is_clear(failure) {
        return {
            kind = .Read,
            sqlite_error = store_reset_preserving(statement, failure),
        }
    }
    return store_user_exercise_list_rows_copy(statement, page, page_limit)
}

// Bind all bounded paging parameters before stepping the prepared page query.
store_user_exercise_list_rows_bind :: proc(
    statement: ^sqlite.Statement, animation_id: uuid.Identifier,
    result_offset: u32, page_limit: u16) -> sqlite.Error {
    identity := animation_id
    failure := sqlite.statement_reset(statement)
    if store_sqlite_error_is_clear(failure) {
        if identity == (uuid.Identifier{}) {
            failure = sqlite.statement_bind_null(statement, 1)
        } else {
            failure = sqlite.statement_bind_blob(statement, 1, identity[:])
        }
    }
    if store_sqlite_error_is_clear(failure) {
        failure = sqlite.statement_bind_i32(statement, 2, i32(page_limit))
    }
    if store_sqlite_error_is_clear(failure) {
        failure = sqlite.statement_bind_i32(statement, 3, i32(result_offset))
    }
    return failure
}

// Decode each selected row and reset the page statement on every exit.
store_user_exercise_list_rows_copy :: proc(
    statement: ^sqlite.Statement, page: ^User_Exercise_Page,
    page_limit: u16) -> Store_Error {
    for page^.returned_count < page_limit {
        status, failure := sqlite.statement_step(statement)
        if !store_sqlite_error_is_clear(failure) {
            return {
                kind = .Read,
                sqlite_error = store_reset_preserving(statement, failure),
            }
        }
        if status == .Done {
            failure = sqlite.statement_reset(statement)
            return {
                kind = .Read if !store_sqlite_error_is_clear(failure) else .None,
                sqlite_error = failure,
            }
        }
        if status != .Row ||
           !store_user_exercise_list_row(statement,
                &page^.exercises[page^.returned_count]) {
            failure = sqlite.sqlite_make_validation_error(.Column, .Type_Mismatch)
            return {
                kind = .Read,
                sqlite_error = store_reset_preserving(statement, failure),
            }
        }
        page^.returned_count += 1
    }
    failure := sqlite.statement_reset(statement)
    return {
        kind = .Read if !store_sqlite_error_is_clear(failure) else .None,
        sqlite_error = failure,
    }
}

// Validate and copy one exercise identity, animation, alias, and title.
store_user_exercise_list_row :: proc(
    statement: ^sqlite.Statement, summary: ^User_Exercise_Summary) -> bool {
    record: User_Exercise_Record
    identity := store_user_exercise_read_uuid(statement, 0)
    animation := store_user_exercise_read_uuid(statement, 1)
    record.id, record.animation_id = identity.identity, animation.identity
    if !store_sqlite_error_is_clear(identity.failure) ||
       !store_sqlite_error_is_clear(animation.failure) ||
       !identity.valid || !animation.valid {
        return false
    }
    reference_valid, reference_failure :=
        store_user_exercise_decode_reference(statement, &record)
    title_valid, title_failure :=
        store_user_exercise_decode_title(statement, &record)
    if !store_sqlite_error_is_clear(reference_failure) ||
       !store_sqlite_error_is_clear(title_failure) ||
       !reference_valid || !title_valid {
        return false
    }
    summary^ = {
        id = record.id,
        animation_id = record.animation_id,
        reference = record.reference,
        reference_length = record.reference_length,
        title = record.title,
        title_length = record.title_length,
    }
    return true
}

// Replace mutable exercise fields while retaining its stable UUID.
store_user_exercise_update :: proc(
    store: ^Store, identity: uuid.Identifier,
    draft: User_Exercise_Draft) -> (User_Exercise_Record, Store_Error) {
    failure := store_user_exercise_write_preflight(store, draft)
    if !store_error_is_clear(failure) {
        return {}, failure
    }
    if identity == (uuid.Identifier{}) {
        return {}, {
            kind = .Invalid_Exercise,
        }
    }
    failure = store_user_exercise_begin(store)
    if !store_error_is_clear(failure) {
        return {}, failure
    }
    identity_copy := identity
    read_result := store_user_exercise_read_blob(
        &store^.exercise_by_identity, identity_copy[:])
    previous := read_result.record
    failure = store_user_exercise_existing_row_failure(
        read_result.found, read_result.failure)
    if !store_error_is_clear(failure) {
        return {}, store_user_exercise_rollback(store, failure)
    }
    failure = store_user_exercise_update_reference_check(store, previous, draft)
    if !store_error_is_clear(failure) {
        return {}, store_user_exercise_rollback(store, failure)
    }
    updated := store_user_exercise_record_make(identity, draft)
    return store_user_exercise_update_commit(store, previous, updated)
}

// Update the row, retire a changed alias, and commit as one transaction.
store_user_exercise_update_commit :: proc(
    store: ^Store, previous, updated: User_Exercise_Record) ->
        (User_Exercise_Record, Store_Error) {
    failure := store_user_exercise_update_row(store, updated)
    if store_error_is_clear(failure) &&
       store_user_exercise_alias_changed(previous, updated) {
        previous_copy := previous
        failure = store_user_exercise_retire_alias(
            store, previous_copy.reference[:previous_copy.reference_length],
            updated.id, false)
    }
    if !store_error_is_clear(failure) {
        return {}, store_user_exercise_rollback(store, failure)
    }
    failure = store_user_exercise_commit(store)
    if !store_error_is_clear(failure) {
        return {}, failure
    }
    return updated, {}
}

// Delete one exercise and permanently retire its UUID and every historical alias.
store_user_exercise_delete :: proc(
    store: ^Store, identity: uuid.Identifier) -> Store_Error {
    failure := store_user_exercise_write_state(store)
    if !store_error_is_clear(failure) {
        return failure
    }
    if identity == (uuid.Identifier{}) {
        return {
            kind = .Invalid_Exercise,
        }
    }
    failure = store_user_exercise_begin(store)
    if !store_error_is_clear(failure) {
        return failure
    }
    identity_copy := identity
    read_result := store_user_exercise_read_blob(
        &store^.exercise_by_identity, identity_copy[:])
    record := read_result.record
    failure = store_user_exercise_existing_row_failure(
        read_result.found, read_result.failure)
    if store_error_is_clear(failure) {
        failure = store_user_exercise_retire_alias(
            store, record.reference[:record.reference_length], identity, true)
    }
    if store_error_is_clear(failure) {
        failure = store_user_exercise_retire_identity(store, identity)
    }
    if store_error_is_clear(failure) {
        failure = store_user_exercise_delete_row(store, identity)
    }
    if !store_error_is_clear(failure) {
        return store_user_exercise_rollback(store, failure)
    }
    return store_user_exercise_commit(store)
}

// Require a usable writable store and valid bounded exercise text.
store_user_exercise_write_preflight :: proc(
    store: ^Store, draft: User_Exercise_Draft) -> Store_Error {
    failure := store_user_exercise_write_state(store)
    if !store_error_is_clear(failure) {
        return failure
    }
    if !store_user_exercise_draft_is_valid(draft) {
        return {
            kind = .Invalid_Exercise,
        }
    }
    return {}
}

// Reject store states before preparing or changing any exercise row.
store_user_exercise_write_state :: proc(store: ^Store) -> Store_Error {
    if store == nil || store^.status == .Closed {
        return {
            kind = .Closed,
        }
    }
    if store^.status == .Unusable {
        return {
            kind = .Unusable,
        }
    }
    if store^.status == .Read_Only {
        return {
            kind = .Not_Writable,
        }
    }
    return {}
}

// Require a readable admitted store for one exercise lookup.
store_user_exercise_read_preflight :: proc(store: ^Store) -> Store_Error {
    if store == nil || store^.status == .Closed {
        return {
            kind = .Closed,
        }
    }
    if store^.status == .Unusable {
        return {
            kind = .Unusable,
        }
    }
    return {}
}

// Validate the required animation identity and each exact UTF-8 byte limit.
store_user_exercise_draft_is_valid :: proc(draft: User_Exercise_Draft) -> bool {
    return draft.animation_id != (uuid.Identifier{}) &&
        store_user_exercise_reference_is_valid(draft.reference) &&
        store_user_exercise_text_is_valid(
            draft.title, USER_EXERCISE_TITLE_MAX_BYTES) &&
        store_user_exercise_text_is_valid(
            draft.instructions, USER_EXERCISE_INSTRUCTIONS_MAX_BYTES)
}

// Accept the stable lowercase ASCII alias grammar.
store_user_exercise_reference_is_valid :: proc(reference: string) -> bool {
    if len(reference) < 1 || len(reference) > USER_EXERCISE_REFERENCE_MAX_BYTES {
        return false
    }
    for value in transmute([]u8)reference {
        if !(value >= 'a' && value <= 'z') &&
           !(value >= '0' && value <= '9') && value != '-' && value != '_' {
            return false
        }
    }
    return true
}

// Require nonblank valid UTF-8 without NUL and within the byte capacity.
store_user_exercise_text_is_valid :: proc(value: string, capacity: int) -> bool {
    if len(value) < 1 || len(value) > capacity || !utf8.valid_string(value) ||
       len(strings.trim_space(value)) == 0 {
        return false
    }
    for byte in transmute([]u8)value {
        if byte == 0 {
            return false
        }
    }
    return true
}

// Start an immediate transaction before checking alias or identity uniqueness.
store_user_exercise_begin :: proc(store: ^Store) -> Store_Error {
    failure := store_exec(store, "BEGIN IMMEDIATE")
    if !store_sqlite_error_is_clear(failure) {
        return {
            kind = .Write,
            sqlite_error = failure,
        }
    }
    return {}
}

// Commit a complete exercise operation and surface commit failures.
store_user_exercise_commit :: proc(store: ^Store) -> Store_Error {
    failure := store_exec(store, "COMMIT")
    if !store_sqlite_error_is_clear(failure) {
        return store_user_exercise_rollback(
            store, {
                kind = .Write,
                sqlite_error = failure,
            })
    }
    return {}
}

// Roll back failed work while retaining both the operation and cleanup errors.
store_user_exercise_rollback :: proc(
    store: ^Store, failure: Store_Error) -> Store_Error {
    rollback := store_exec(store, "ROLLBACK")
    if !store_sqlite_error_is_clear(rollback) {
        store^.status = .Unusable
        result := failure
        result.cleanup_error = rollback
        return result
    }
    return failure
}

// Check active and retired aliases while holding the transaction's write lock.
store_user_exercise_reference_available :: proc(
    store: ^Store, reference: string) -> Store_Error {
    statement := &store^.exercise_alias_state
    failure := sqlite.statement_reset(statement)
    if store_sqlite_error_is_clear(failure) {
        failure = sqlite.statement_bind_text(statement, 1, reference)
    }
    if !store_sqlite_error_is_clear(failure) {
        return {
            kind = .Read,
            sqlite_error = store_reset_preserving(statement, failure),
        }
    }
    status, step_failure := sqlite.statement_step(statement)
    failure = step_failure
    if !store_sqlite_error_is_clear(failure) {
        return {
            kind = .Read,
            sqlite_error = store_reset_preserving(statement, failure),
        }
    }
    if status == .Done {
        failure = sqlite.statement_reset(statement)
        if !store_sqlite_error_is_clear(failure) {
            return {
                kind = .Read,
                sqlite_error = failure,
            }
        }
        return {}
    }
    return store_user_exercise_reference_state(statement, status)
}

// Decode and reset the one active-or-retired alias state row.
store_user_exercise_reference_state :: proc(
    statement: ^sqlite.Statement, status: sqlite.Step_Status) -> Store_Error {
    if status != .Row || sqlite.column_type(statement, 0) != .Integer {
        failure := sqlite.sqlite_make_validation_error(.Step, .Invalid_State)
        return {
            kind = .Invalid_Schema,
            sqlite_error = store_reset_preserving(statement, failure),
        }
    }
    state, failure := sqlite.column_i64(statement, 0)
    failure = store_reset_preserving(statement, failure)
    if !store_sqlite_error_is_clear(failure) {
        return {
            kind = .Read,
            sqlite_error = failure,
        }
    }
    if state == 1 {
        return {
            kind = .Reference_Collision,
        }
    }
    if state == 2 {
        return {
            kind = .Reference_Retired,
        }
    }
    return {
        kind = .Invalid_Schema,
    }
}

// Generate an unused UUID and copy the validated draft into an owned record.
store_user_exercise_make_new_record :: proc(
    store: ^Store,
    draft: User_Exercise_Draft) -> (User_Exercise_Record, Store_Error) {
    for _ in 0..<USER_EXERCISE_ID_GENERATION_ATTEMPTS {
        context.random_generator = crypto.random_generator()
        identity := uuid.generate_v4()
        if identity == (uuid.Identifier{}) {
            continue
        }
        taken, failure := store_user_exercise_identity_is_taken(store, identity)
        if !store_sqlite_error_is_clear(failure) {
            return {}, {
                kind = .Read,
                sqlite_error = failure,
            }
        }
        if !taken {
            return store_user_exercise_record_make(identity, draft), {}
        }
    }
    return {}, {
        kind = .Identity_Collision,
    }
}

// Reserve UUIDs that are active or permanently represented by retirement rows.
store_user_exercise_identity_is_taken :: proc(
    store: ^Store, identity: uuid.Identifier) -> (bool, sqlite.Error) {
    statement := &store^.exercise_identity_taken
    identity_copy := identity
    failure := sqlite.statement_reset(statement)
    if store_sqlite_error_is_clear(failure) {
        failure = sqlite.statement_bind_blob(statement, 1, identity_copy[:])
    }
    if !store_sqlite_error_is_clear(failure) {
        return false, store_reset_preserving(statement, failure)
    }
    status, step_failure := sqlite.statement_step(statement)
    if !store_sqlite_error_is_clear(step_failure) {
        return false, store_reset_preserving(statement, step_failure)
    }
    taken := status == .Row
    if !taken && status != .Done {
        step_failure = sqlite.sqlite_make_validation_error(.Step, .Invalid_State)
    }
    return taken, store_reset_preserving(statement, step_failure)
}

// Build the bounded record value while its input strings are still borrowed.
store_user_exercise_record_make :: proc(
    identity: uuid.Identifier, draft: User_Exercise_Draft) -> User_Exercise_Record {
    record: User_Exercise_Record = {
        id = identity,
        animation_id = draft.animation_id,
        reference_length = u8(len(draft.reference)),
        title_length = u16(len(draft.title)),
        instructions_length = u32(len(draft.instructions)),
    }
    copy(record.reference[:], transmute([]u8)draft.reference)
    copy(record.title[:], transmute([]u8)draft.title)
    copy(record.instructions[:], transmute([]u8)draft.instructions)
    return record
}

// Read and validate a single row selected by a bound BLOB identity.
store_user_exercise_read_blob :: proc(
    statement: ^sqlite.Statement,
    identity: []u8) -> User_Exercise_Read_Result {
    failure := sqlite.statement_reset(statement)
    if store_sqlite_error_is_clear(failure) {
        failure = sqlite.statement_bind_blob(statement, 1, identity)
    }
    return store_user_exercise_read_after_bind(statement, failure)
}

// Read and validate a single row selected by a bound TEXT alias.
store_user_exercise_read_text :: proc(
    statement: ^sqlite.Statement,
    reference: string) -> User_Exercise_Read_Result {
    failure := sqlite.statement_reset(statement)
    if store_sqlite_error_is_clear(failure) {
        failure = sqlite.statement_bind_text(statement, 1, reference)
    }
    return store_user_exercise_read_after_bind(statement, failure)
}

// Decode one unique result row, copy all columns, and reset its statement.
store_user_exercise_read_after_bind :: proc(
    statement: ^sqlite.Statement,
    failure: sqlite.Error) -> User_Exercise_Read_Result {
    result_failure := failure
    if !store_sqlite_error_is_clear(result_failure) {
        return {
            failure = store_reset_preserving(statement, result_failure),
        }
    }
    status, step_error := sqlite.statement_step(statement)
    if !store_sqlite_error_is_clear(step_error) {
        return {
            failure = store_reset_preserving(statement, step_error),
        }
    }
    if status == .Done {
        return {
            failure = sqlite.statement_reset(statement),
        }
    }
    if status != .Row {
        result_failure = sqlite.sqlite_make_validation_error(.Step, .Invalid_State)
        return {
            failure = store_reset_preserving(statement, result_failure),
        }
    }
    decoded := store_user_exercise_decode(statement)
    return store_user_exercise_read_finish(statement, decoded)
}

// Reset a decoded row and reject duplicate rows or invalid stored fields.
store_user_exercise_read_finish :: proc(
    statement: ^sqlite.Statement,
    decoded: User_Exercise_Decode_Result) -> User_Exercise_Read_Result {
    result := decoded
    if store_sqlite_error_is_clear(result.failure) && result.valid {
        status, failure := sqlite.statement_step(statement)
        result.failure = failure
        if store_sqlite_error_is_clear(result.failure) && status != .Done {
            result.failure = sqlite.sqlite_make_validation_error(.Step, .Invalid_State)
        }
    }
    result.failure = store_reset_preserving(statement, result.failure)
    if !store_sqlite_error_is_clear(result.failure) {
        return {
            failure = result.failure,
        }
    }
    if !result.valid {
        return {
            failure = sqlite.sqlite_make_validation_error(.Column, .Type_Mismatch),
        }
    }
    return {
        record = result.record,
        found = true,
    }
}

// Decode an exercise row into caller-owned fixed buffers and revalidate its text.
store_user_exercise_decode :: proc(
    statement: ^sqlite.Statement) -> User_Exercise_Decode_Result {
    record: User_Exercise_Record
    identity_result := store_user_exercise_read_uuid(statement, 0)
    record.id = identity_result.identity
    if !store_sqlite_error_is_clear(identity_result.failure) || !identity_result.valid {
        return {
            record = record,
            valid = identity_result.valid,
            failure = identity_result.failure,
        }
    }
    animation_result := store_user_exercise_read_uuid(statement, 1)
    record.animation_id = animation_result.identity
    if !store_sqlite_error_is_clear(animation_result.failure) ||
       !animation_result.valid {
        return {
            record = record,
            valid = animation_result.valid,
            failure = animation_result.failure,
        }
    }
    valid, failure := store_user_exercise_decode_reference(statement, &record)
    if !store_sqlite_error_is_clear(failure) || !valid {
        return {
            record = record,
            failure = failure,
        }
    }
    valid, failure = store_user_exercise_decode_title(statement, &record)
    if !store_sqlite_error_is_clear(failure) || !valid {
        return {
            record = record,
            failure = failure,
        }
    }
    valid, failure = store_user_exercise_decode_instructions(statement, &record)
    if !store_sqlite_error_is_clear(failure) || !valid {
        return {
            record = record,
            failure = failure,
        }
    }
    return {
        record = record,
        valid = true,
    }
}

// Copy and validate the bounded stable exercise alias.
store_user_exercise_decode_reference :: proc(
    statement: ^sqlite.Statement, record: ^User_Exercise_Record) -> (bool, sqlite.Error) {
    length, failure := store_user_exercise_read_text_column(
        statement, 2, record^.reference[:])
    record^.reference_length = u8(length)
    valid := store_user_exercise_reference_is_valid(
        string(record^.reference[:record^.reference_length]))
    return valid, failure
}

// Copy and validate the bounded exercise title.
store_user_exercise_decode_title :: proc(
    statement: ^sqlite.Statement, record: ^User_Exercise_Record) -> (bool, sqlite.Error) {
    length, failure := store_user_exercise_read_text_column(
        statement, 3, record^.title[:])
    record^.title_length = length
    valid := store_user_exercise_text_is_valid(
        string(record^.title[:record^.title_length]), len(record^.title))
    return valid, failure
}

// Copy and validate the bounded exercise instructions.
store_user_exercise_decode_instructions :: proc(
    statement: ^sqlite.Statement, record: ^User_Exercise_Record) -> (bool, sqlite.Error) {
    length, failure := store_user_exercise_read_instruction_column(
        statement, record^.instructions[:])
    record^.instructions_length = length
    valid := store_user_exercise_text_is_valid(
        string(record^.instructions[:record^.instructions_length]),
        len(record^.instructions))
    return valid, failure
}

// Copy one nonzero UUID BLOB from the active SQLite row.
store_user_exercise_read_uuid :: proc(
    statement: ^sqlite.Statement,
    column: int) -> User_Exercise_Uuid_Result {
    identity: uuid.Identifier
    count, failure := sqlite.column_blob_copy(statement, column, identity[:])
    valid := count == len(identity) && identity != (uuid.Identifier{})
    return {
        identity = identity,
        valid = valid,
        failure = failure,
    }
}

// Copy one bounded text column and require its byte length to fit its destination.
store_user_exercise_read_text_column :: proc(
    statement: ^sqlite.Statement, column: int,
    destination: []u8) -> (u16, sqlite.Error) {
    count, failure := sqlite.column_text_copy(statement, column, destination)
    if !store_sqlite_error_is_clear(failure) {
        return 0, failure
    }
    return u16(count), {}
}

// Copy a 32 KiB instruction field into the owned record buffer.
store_user_exercise_read_instruction_column :: proc(
    statement: ^sqlite.Statement, destination: []u8) -> (u32, sqlite.Error) {
    count, failure := sqlite.column_text_copy(statement, 4, destination)
    if !store_sqlite_error_is_clear(failure) {
        return 0, failure
    }
    return u32(count), {}
}

// Map a successful unique-row lookup or its explicit absence.
store_user_exercise_read_result :: proc(
    record: User_Exercise_Record, found: bool,
    failure: sqlite.Error) -> (User_Exercise_Record, Store_Error) {
    if !store_sqlite_error_is_clear(failure) {
        return {}, {
            kind = .Read,
            sqlite_error = failure,
        }
    }
    if !found {
        return {}, {
            kind = .Not_Found,
        }
    }
    return record, {}
}

// Distinguish SQL failures from absent identities for atomic mutations.
store_user_exercise_existing_row_failure :: proc(
    found: bool, failure: sqlite.Error) -> Store_Error {
    if !store_sqlite_error_is_clear(failure) {
        return {
            kind = .Read,
            sqlite_error = failure,
        }
    }
    if !found {
        return {
            kind = .Not_Found,
        }
    }
    return {}
}

// Determine whether an alias has already been retired.
store_user_exercise_reference_retired :: proc(
    store: ^Store, reference: string) -> (bool, sqlite.Error) {
    statement := &store^.retired_exercise_alias
    failure := sqlite.statement_reset(statement)
    if store_sqlite_error_is_clear(failure) {
        failure = sqlite.statement_bind_text(statement, 1, reference)
    }
    if !store_sqlite_error_is_clear(failure) {
        return false, store_reset_preserving(statement, failure)
    }
    status, step_failure := sqlite.statement_step(statement)
    if !store_sqlite_error_is_clear(step_failure) {
        return false, store_reset_preserving(statement, step_failure)
    }
    return store_user_exercise_retired_read_finish(statement, status)
}

// Validate and reset one retired-alias lookup.
store_user_exercise_retired_read_finish :: proc(
    statement: ^sqlite.Statement, status: sqlite.Step_Status) -> (bool, sqlite.Error) {
    step_status := status
    if step_status == .Done {
        return false, sqlite.statement_reset(statement)
    }
    if step_status != .Row || sqlite.column_type(statement, 0) != .Blob ||
       sqlite.column_type(statement, 1) != .Integer {
        failure := sqlite.sqlite_make_validation_error(.Column, .Type_Mismatch)
        return false, store_reset_preserving(statement, failure)
    }
    identity_result := store_user_exercise_read_uuid(statement, 0)
    retired, retired_error := sqlite.column_i64(statement, 1)
    failure := identity_result.failure
    if store_sqlite_error_is_clear(failure) {
        failure = retired_error
    }
    if store_sqlite_error_is_clear(failure) &&
       (!identity_result.valid || (retired != 0 && retired != 1)) {
        failure = sqlite.sqlite_make_validation_error(.Column, .Range)
    }
    if store_sqlite_error_is_clear(failure) {
        step_status, failure = sqlite.statement_step(statement)
        if store_sqlite_error_is_clear(failure) && step_status != .Done {
            failure = sqlite.sqlite_make_validation_error(.Step, .Invalid_State)
        }
    }
    failure = store_reset_preserving(statement, failure)
    return store_sqlite_error_is_clear(failure), failure
}

// Persist one complete generated-identity record using bound values.
store_user_exercise_insert :: proc(
    store: ^Store, record: User_Exercise_Record) -> Store_Error {
    statement := &store^.exercise_insert
    failure := sqlite.statement_reset(statement)
    failure = store_user_exercise_bind_record(statement, record, failure, true)
    return store_user_exercise_execute(statement, failure)
}

// Bind all five insert values, or four update fields plus the stable identity.
store_user_exercise_bind_record :: proc(
    statement: ^sqlite.Statement, record: User_Exercise_Record,
    prior_failure: sqlite.Error, inserting: bool) -> sqlite.Error {
    record_copy := record
    failure := prior_failure
    if inserting {
        failure = store_user_exercise_bind_blob(statement, 1, record_copy.id[:], failure)
    }
    offset := 1 if inserting else 0
    failure = store_user_exercise_bind_blob(
        statement, 1 + offset, record_copy.animation_id[:], failure)
    failure = store_user_exercise_bind_text(
        statement, 2 + offset,
        string(record_copy.reference[:record_copy.reference_length]), failure)
    failure = store_user_exercise_bind_text(
        statement, 3 + offset,
        string(record_copy.title[:record_copy.title_length]), failure)
    failure = store_user_exercise_bind_text(
        statement, 4 + offset,
        string(record_copy.instructions[:record_copy.instructions_length]), failure)
    if !inserting {
        failure = store_user_exercise_bind_blob(
            statement, 5, record_copy.id[:], failure)
    }
    return failure
}

// Bind a BLOB only while preserving the first failed bind.
store_user_exercise_bind_blob :: proc(
    statement: ^sqlite.Statement, index: int, value: []u8,
    prior_failure: sqlite.Error) -> sqlite.Error {
    if !store_sqlite_error_is_clear(prior_failure) {
        return prior_failure
    }
    return sqlite.statement_bind_blob(statement, index, value)
}

// Bind TEXT only while preserving the first failed bind.
store_user_exercise_bind_text :: proc(
    statement: ^sqlite.Statement, index: int, value: string,
    prior_failure: sqlite.Error) -> sqlite.Error {
    if !store_sqlite_error_is_clear(prior_failure) {
        return prior_failure
    }
    return sqlite.statement_bind_text(statement, index, value)
}

// Update a stable exercise record without changing its UUID.
store_user_exercise_update_row :: proc(
    store: ^Store, record: User_Exercise_Record) -> Store_Error {
    statement := &store^.exercise_update
    failure := sqlite.statement_reset(statement)
    failure = store_user_exercise_bind_record(statement, record, failure, false)
    return store_user_exercise_execute(statement, failure)
}

// Insert a permanent alias tombstone with an explicit identity-retirement bit.
store_user_exercise_retire_alias :: proc(
    store: ^Store, reference: []u8, identity: uuid.Identifier,
    identity_retired: bool) -> Store_Error {
    statement := &store^.exercise_retire_alias
    identity_copy := identity
    failure := sqlite.statement_reset(statement)
    if store_sqlite_error_is_clear(failure) {
        failure = sqlite.statement_bind_text(statement, 1, string(reference))
    }
    if store_sqlite_error_is_clear(failure) {
        failure = sqlite.statement_bind_blob(statement, 2, identity_copy[:])
    }
    if store_sqlite_error_is_clear(failure) {
        failure = sqlite.statement_bind_i32(statement, 3, 1 if identity_retired else 0)
    }
    return store_user_exercise_execute(statement, failure)
}

// Permanently retire all old aliases when an exercise identity is deleted.
store_user_exercise_retire_identity :: proc(
    store: ^Store, identity: uuid.Identifier) -> Store_Error {
    statement := &store^.exercise_retire_identity
    identity_copy := identity
    failure := sqlite.statement_reset(statement)
    if store_sqlite_error_is_clear(failure) {
        failure = sqlite.statement_bind_blob(statement, 1, identity_copy[:])
    }
    return store_user_exercise_execute(statement, failure)
}

// Delete the active row after its current alias has been reserved.
store_user_exercise_delete_row :: proc(
    store: ^Store, identity: uuid.Identifier) -> Store_Error {
    statement := &store^.exercise_delete
    identity_copy := identity
    failure := sqlite.statement_reset(statement)
    if store_sqlite_error_is_clear(failure) {
        failure = sqlite.statement_bind_blob(statement, 1, identity_copy[:])
    }
    return store_user_exercise_execute(statement, failure)
}

// Require one successful DML statement and reset it for symmetric reuse.
store_user_exercise_execute :: proc(
    statement: ^sqlite.Statement, failure: sqlite.Error) -> Store_Error {
    result_failure := failure
    if store_sqlite_error_is_clear(result_failure) {
        status, step_error := sqlite.statement_step(statement)
        result_failure = step_error
        if store_sqlite_error_is_clear(result_failure) && status != .Done {
            result_failure = sqlite.sqlite_make_validation_error(.Step, .Invalid_State)
        }
    }
    result_failure = store_reset_preserving(statement, result_failure)
    if !store_sqlite_error_is_clear(result_failure) {
        return {
            kind = .Write,
            sqlite_error = result_failure,
        }
    }
    return {}
}

// Read all persisted exercise rows and reject malformed stored values at admission.
store_verify_user_exercise_admission :: proc(store: ^Store) -> Store_Error {
    failure := store_user_exercise_admit_active_rows(store)
    if !store_error_is_clear(failure) {
        return failure
    }
    return store_user_exercise_admit_retired_rows(store)
}

// Validate active rows without retaining SQLite memory or allocating a catalogue.
store_user_exercise_admit_active_rows :: proc(store: ^Store) -> Store_Error {
    statement := &store^.exercise_rows_for_admission
    failure := sqlite.statement_reset(statement)
    if !store_sqlite_error_is_clear(failure) {
        return {
            kind = .Invalid_Schema,
            sqlite_error = failure,
        }
    }
    for {
        status, step_error := sqlite.statement_step(statement)
        if !store_sqlite_error_is_clear(step_error) {
            return store_user_exercise_admission_failure(statement, step_error)
        }
        if status == .Done {
            return store_user_exercise_admission_reset(statement)
        }
        decoded := store_user_exercise_decode(statement)
        if !store_sqlite_error_is_clear(decoded.failure) || !decoded.valid {
            return store_user_exercise_admission_failure(statement, decoded.failure)
        }
    }
}

// Validate each retired alias and prove its identity/alias cannot be live.
store_user_exercise_admit_retired_rows :: proc(store: ^Store) -> Store_Error {
    statement := &store^.retired_exercise_rows_for_admission
    failure := sqlite.statement_reset(statement)
    if !store_sqlite_error_is_clear(failure) {
        return {
            kind = .Invalid_Schema,
            sqlite_error = failure,
        }
    }
    for {
        status, step_error := sqlite.statement_step(statement)
        if !store_sqlite_error_is_clear(step_error) {
            return store_user_exercise_admission_failure(statement, step_error)
        }
        if status == .Done {
            return store_user_exercise_admission_reset(statement)
        }
        if !store_user_exercise_retired_row_valid(statement) {
            failure = sqlite.sqlite_make_validation_error(.Column, .Type_Mismatch)
            return store_user_exercise_admission_failure(statement, failure)
        }
    }
}

// Check all tombstone column types, identity state, and permanent alias exclusion.
store_user_exercise_retired_row_valid :: proc(statement: ^sqlite.Statement) -> bool {
    if sqlite.column_type(statement, 0) != .Blob ||
       sqlite.column_type(statement, 1) != .Text ||
       sqlite.column_type(statement, 2) != .Integer ||
       sqlite.column_type(statement, 3) != .Integer ||
       sqlite.column_type(statement, 4) != .Integer {
        return false
    }
    identity_result := store_user_exercise_read_uuid(statement, 0)
    reference: [USER_EXERCISE_REFERENCE_MAX_BYTES]u8
    count, text_failure := sqlite.column_text_copy(statement, 1, reference[:])
    retired, retired_failure := sqlite.column_i64(statement, 2)
    identity_live, identity_failure := sqlite.column_i64(statement, 3)
    reference_live, reference_failure := sqlite.column_i64(statement, 4)
    return identity_result.valid &&
        store_sqlite_error_is_clear(identity_result.failure) &&
        store_sqlite_error_is_clear(text_failure) &&
        store_user_exercise_reference_is_valid(string(reference[:count])) &&
        store_sqlite_error_is_clear(retired_failure) &&
        store_sqlite_error_is_clear(identity_failure) &&
        store_sqlite_error_is_clear(reference_failure) &&
        (retired == 0 || retired == 1) && identity_live == 1 - retired &&
        reference_live == 0
}

// Reset an admission scan and report any schema-level decoding failure.
store_user_exercise_admission_failure :: proc(
    statement: ^sqlite.Statement, failure: sqlite.Error) -> Store_Error {
    result_failure := store_reset_preserving(statement, failure)
    return {
        kind = .Invalid_Schema,
        sqlite_error = result_failure,
    }
}

// Reset a successful admission scan before publishing it.
store_user_exercise_admission_reset :: proc(
    statement: ^sqlite.Statement) -> Store_Error {
    failure := sqlite.statement_reset(statement)
    if !store_sqlite_error_is_clear(failure) {
        return {
            kind = .Invalid_Schema,
            sqlite_error = failure,
        }
    }
    return {}
}

// Check whether the candidate alias differs from the active value before lookup.
store_user_exercise_update_reference_check :: proc(
    store: ^Store, previous: User_Exercise_Record,
    draft: User_Exercise_Draft) -> Store_Error {
    previous_copy := previous
    old_reference := string(previous_copy.reference[:previous_copy.reference_length])
    if old_reference == draft.reference {
        return {}
    }
    return store_user_exercise_reference_available(store, draft.reference)
}

// Compare exact alias bytes before retiring a reference on update.
store_user_exercise_alias_changed :: proc(
    previous, updated: User_Exercise_Record) -> bool {
    previous_copy := previous
    updated_copy := updated
    return previous_copy.reference_length != updated_copy.reference_length ||
        string(previous_copy.reference[:previous_copy.reference_length]) !=
            string(updated_copy.reference[:updated_copy.reference_length])
}

// Verify the fixed request buffers before they cross to the worker.
store_user_exercise_task_is_valid :: proc(task: User_Exercise_Task) -> bool {
    task_copy := task
    switch task_copy.operation {
    case .List:
        return task_copy.page_limit > 0 &&
            task_copy.page_limit <= USER_EXERCISE_LIST_PAGE_CAPACITY &&
            task_copy.result_offset <= u32(max(i32))
    case .Create, .Update:
        if task_copy.draft_reference_length > len(task_copy.draft_reference) ||
           task_copy.draft_title_length > len(task_copy.draft_title) ||
           task_copy.draft_instructions_length > len(task_copy.draft_instructions) {
            return false
        }
        if task_copy.operation == .Update &&
           task_copy.identity == (uuid.Identifier{}) {
            return false
        }
        return store_user_exercise_draft_is_valid(
            store_user_exercise_task_draft(&task_copy))
    case .Read_Identity, .Delete:
        return task_copy.identity != (uuid.Identifier{})
    case .Read_Reference:
        if task_copy.reference_length > len(task_copy.reference) {
            return false
        }
        return store_user_exercise_reference_is_valid(
            string(task_copy.reference[:task_copy.reference_length]))
    case .None:
        return false
    }
    return false
}

// Identify read-only operations so an unavailable preference writer cannot block browsing.
store_user_exercise_task_is_read_only :: proc(task: User_Exercise_Task) -> bool {
    switch task.operation {
    case .List, .Read_Identity, .Read_Reference:
        return true
    case .None, .Create, .Update, .Delete:
        return false
    }
    return false
}

// Execute one copied request on the settings-save worker's admitted connection.
store_user_exercise_task_execute :: proc(
    store: ^Store, task: ^User_Exercise_Task) -> Store_Error {
    if task == nil || !store_user_exercise_task_is_valid(task^) {
        return {
            kind = .Invalid_Exercise,
        }
    }
    switch task^.operation {
    case .Create:
        return store_user_exercise_task_create(store, task)
    case .List:
        return store_user_exercise_task_list(store, task)
    case .Read_Identity:
        return store_user_exercise_task_read_identity(store, task)
    case .Read_Reference:
        return store_user_exercise_task_read_reference(store, task)
    case .Update:
        return store_user_exercise_task_update(store, task)
    case .Delete:
        task^.failure = store_user_exercise_delete(store, task^.identity)
        return task^.failure
    case .None:
        return {
            kind = .Invalid_Exercise,
        }
    }
    return {
        kind = .Invalid_Exercise,
    }
}

// Execute one list page and retain its bounded result for joined copy-out.
store_user_exercise_task_list :: proc(
    store: ^Store, task: ^User_Exercise_Task) -> Store_Error {
    task^.page, task^.failure = store_user_exercise_list(
        store, task^.identity, task^.result_offset, task^.page_limit)
    return task^.failure
}

// Copy task-owned draft bytes into a short-lived typed persistence input.
store_user_exercise_task_draft :: proc(
    task: ^User_Exercise_Task) -> User_Exercise_Draft {
    return {
        animation_id = task^.draft_animation_id,
        reference = string(task^.draft_reference[:task^.draft_reference_length]),
        title = string(task^.draft_title[:task^.draft_title_length]),
        instructions = string(
            task^.draft_instructions[:task^.draft_instructions_length]),
    }
}

// Create from the immutable request and retain the generated record for join.
store_user_exercise_task_create :: proc(
    store: ^Store, task: ^User_Exercise_Task) -> Store_Error {
    record, failure := store_user_exercise_create(
        store, store_user_exercise_task_draft(task))
    task^.result = record
    task^.failure = failure
    return failure
}

// Read by stable identity and retain the copied result for join.
store_user_exercise_task_read_identity :: proc(
    store: ^Store, task: ^User_Exercise_Task) -> Store_Error {
    record, failure := store_user_exercise_read_by_identity(store, task^.identity)
    task^.result = record
    task^.failure = failure
    return failure
}

// Read by alias and retain the copied result for join.
store_user_exercise_task_read_reference :: proc(
    store: ^Store, task: ^User_Exercise_Task) -> Store_Error {
    reference := string(task^.reference[:task^.reference_length])
    record, failure := store_user_exercise_read_by_reference(store, reference)
    task^.result = record
    task^.failure = failure
    return failure
}

// Update mutable fields while keeping the request's stable identity.
store_user_exercise_task_update :: proc(
    store: ^Store, task: ^User_Exercise_Task) -> Store_Error {
    record, failure := store_user_exercise_update(
        store, task^.identity, store_user_exercise_task_draft(task))
    task^.result = record
    task^.failure = failure
    return failure
}

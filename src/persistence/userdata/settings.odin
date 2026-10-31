package userdata

import sqlite "../../sqlite"
import settings "../../settings"

// Load the bounded known settings from one consistent SQLite read snapshot.
store_load_settings :: proc(
    store: ^Store, preferences: ^settings.Preferences) -> Load_Result {
    if store == nil || preferences == nil ||
        (store^.status != .Ready && store^.status != .Read_Only) {
        failure_kind := Store_Error_Kind.Closed
        if store != nil && store^.status == .Unusable {
            failure_kind = .Unusable
        }
        return {
            failure = {
                kind = failure_kind,
            },
        }
    }
    begin_error := store_exec(store, "BEGIN")
    if !store_sqlite_error_is_clear(begin_error) {
        return {
            failure = {
                kind = .Read,
                sqlite_error = begin_error,
            },
        }
    }
    staged := preferences^
    result := store_collect_known_settings(store, &staged)
    if !store_error_is_clear(result.failure) {
        result.failure = store_rollback_failure(
            store, .Read, result.failure.sqlite_error)
        return result
    }
    commit_error := store_exec(store, "COMMIT")
    if !store_sqlite_error_is_clear(commit_error) {
        result.failure = store_rollback_failure(store, .Read, commit_error)
        return result
    }
    preferences^ = staged
    return result
}

// Read every catalog key into a staged preference snapshot.
store_collect_known_settings :: proc(
    store: ^Store, staged: ^settings.Preferences) -> Load_Result {
    result: Load_Result
    for id in settings.ALL_SETTING_IDS {
        read := store_read_known_setting(store, id)
        if !store_sqlite_error_is_clear(read.failure) {
            result.failure = {
                kind = .Read,
                sqlite_error = read.failure,
            }
            return result
        }
        if !read.found {
            continue
        }
        if read.reason != .None ||
            !settings.valid_setting_value(id, read.value) {
            if read.reason == .None {
                read.reason = .Value_Range
            }
            result.invalid_values[result.invalid_count] = {id, read.reason}
            result.invalid_count += 1
            continue
        }
        if !settings.apply_setting_value(staged, id, read.value, .Saved) {
            result.invalid_values[result.invalid_count] = {id, .Value_Range}
            result.invalid_count += 1
        }
    }
    return result
}

// Find one known row and decode its value without retaining SQLite column memory.
store_read_known_setting :: proc(
    store: ^Store,
    id: settings.Setting_Id) -> Setting_Read_Result {
    definition, valid := settings.setting_definition(id)
    if !valid {
        return {
            reason = .Storage_Type,
            failure = sqlite.sqlite_make_validation_error(.Bind, .Invalid_Argument),
        }
    }
    statement := &store^.read_setting
    failure := sqlite.statement_reset(statement)
    if store_sqlite_error_is_clear(failure) {
        failure = sqlite.statement_bind_text(statement, 1, definition.namespace)
    }
    if store_sqlite_error_is_clear(failure) {
        failure = sqlite.statement_bind_text(statement, 2, definition.key)
    }
    if !store_sqlite_error_is_clear(failure) {
        return {
            reason = .Storage_Type,
            failure = store_reset_preserving(statement, failure),
        }
    }
    result := store_fetch_known_row(statement, id)
    result.failure = store_reset_preserving(statement, result.failure)
    return result
}

// Decode one result row and verify the query returns no duplicate match.
store_fetch_known_row :: proc(
    statement: ^sqlite.Statement,
    id: settings.Setting_Id) -> Setting_Read_Result {
    status, failure := sqlite.statement_step(statement)
    if !store_sqlite_error_is_clear(failure) {
        return {
            reason = .Storage_Type,
            failure = failure,
        }
    }
    if status == .Done {
        return {
            reason = .Storage_Type,
        }
    }
    if status != .Row {
        failure = sqlite.sqlite_make_validation_error(.Step, .Invalid_State)
        return {
            reason = .Storage_Type,
            failure = failure,
        }
    }
    decoded := store_decode_setting_row(statement, id)
    if !store_sqlite_error_is_clear(decoded.failure) {
        return {
            reason = decoded.reason,
            failure = decoded.failure,
        }
    }
    status, failure = sqlite.statement_step(statement)
    if !store_sqlite_error_is_clear(failure) || status != .Done {
        if store_sqlite_error_is_clear(failure) {
            failure = sqlite.sqlite_make_validation_error(.Step, .Invalid_State)
        }
        return {
            reason = decoded.reason,
            failure = failure,
        }
    }
    return {
        value = decoded.value,
        found = true,
        reason = decoded.reason,
    }
}

// Decode generic columns into a known setting type, copying text before reset.
store_decode_setting_row :: proc(
    statement: ^sqlite.Statement,
    id: settings.Setting_Id) -> Setting_Value_Read_Result {
    definition, valid := settings.setting_definition(id)
    if !valid {
        return {
            reason = .Storage_Type,
            failure = sqlite.sqlite_make_validation_error(.Column, .Invalid_Argument),
        }
    }
    stored_type := store_read_type_name(statement)
    if !store_sqlite_error_is_clear(stored_type.failure) {
        return {
            reason = stored_type.reason,
            failure = stored_type.failure,
        }
    }
    if stored_type.reason != .None {
        return {
            reason = stored_type.reason,
        }
    }
    if stored_type.kind != definition.storage_kind {
        return {
            reason = .Storage_Type,
        }
    }
    result := store_read_stored_value(
        statement, id, definition.storage_kind)
    return result
}

// Read the bounded discriminator string from its statement-owned column.
store_read_type_name :: proc(
    statement: ^sqlite.Statement) -> Setting_Storage_Type_Result {
    column_kind := sqlite.column_type(statement, 0)
    if column_kind == .Invalid {
        return {
            kind = .Boolean,
            reason = .Column_Type,
            failure = sqlite.sqlite_make_validation_error(.Column, .Invalid_State),
        }
    }
    if column_kind != .Text {
        return {
            kind = .Boolean,
            reason = .Column_Type,
        }
    }
    buffer: [8]u8
    count, failure := sqlite.column_text_copy(statement, 0, buffer[:])
    if !store_sqlite_error_is_clear(failure) {
        if failure.validation == .Capacity {
            return {
                kind = .Boolean,
                reason = .Text_Capacity,
            }
        }
        return {
            kind = .Boolean,
            reason = .Column_Type,
            failure = failure,
        }
    }
    switch string(buffer[:count]) {
    case "boolean":
        return {
            kind = .Boolean,
        }
    case "integer":
        return {
            kind = .Integer,
        }
    case "text":
        return {
            kind = .Text,
        }
    }
    return {
        kind = .Boolean,
        reason = .Storage_Type,
    }
}

// Map one storage discriminator to its canonical database spelling.
store_value_type_name :: proc(kind: settings.Setting_Storage_Kind) -> string {
    switch kind {
    case .Boolean:
        return "boolean"
    case .Integer:
        return "integer"
    case .Text:
        return "text"
    }
    return ""
}

// Read the exact scalar columns required by a setting's storage definition.
store_read_stored_value :: proc(
    statement: ^sqlite.Statement,
    id: settings.Setting_Id,
    kind: settings.Setting_Storage_Kind) -> Setting_Value_Read_Result {
    switch kind {
    case .Boolean:
        return store_read_boolean(statement)
    case .Integer:
        return store_read_integer(statement)
    case .Text:
        return store_read_enum_text(statement, id)
    }
    return {
        reason = .Storage_Type,
        failure = sqlite.sqlite_make_validation_error(.Column, .Invalid_Argument),
    }
}

// Require an exact boolean integer and a NULL text column.
store_read_boolean :: proc(
    statement: ^sqlite.Statement) -> Setting_Value_Read_Result {
    text_column := sqlite.column_type(statement, 2)
    if text_column == .Invalid {
        return {
            reason = .Column_Type,
            failure = sqlite.sqlite_make_validation_error(.Column, .Invalid_State),
        }
    }
    if text_column != .Null {
        return {
            reason = .Null_Column,
        }
    }
    value, failure := sqlite.column_i64(statement, 1)
    if !store_sqlite_error_is_clear(failure) {
        return store_column_read_failure(failure)
    }
    if value != 0 && value != 1 {
        return {
            reason = .Value_Range,
        }
    }
    return {
        value = settings.boolean_value(value == 1),
    }
}

// Require an exact integer value and a NULL text column.
store_read_integer :: proc(
    statement: ^sqlite.Statement) -> Setting_Value_Read_Result {
    text_column := sqlite.column_type(statement, 2)
    if text_column == .Invalid {
        return {
            reason = .Column_Type,
            failure = sqlite.sqlite_make_validation_error(.Column, .Invalid_State),
        }
    }
    if text_column != .Null {
        return {
            reason = .Null_Column,
        }
    }
    value, failure := sqlite.column_i64(statement, 1)
    if !store_sqlite_error_is_clear(failure) {
        return store_column_read_failure(failure)
    }
    converted := int(value)
    if i64(converted) != value {
        return {
            reason = .Value_Range,
        }
    }
    return {
        value = settings.integer_value(converted),
    }
}

// Treat stored-class mismatches as corrupt values and propagate SQLite failures.
store_column_read_failure :: proc(failure: sqlite.Error) -> Setting_Value_Read_Result {
    result: Setting_Value_Read_Result = {
        reason = .Column_Type,
    }
    if failure.validation != .Type_Mismatch {
        result.failure = failure
    }
    return result
}

// Require a bounded text enum and a NULL integer column.
store_read_enum_text :: proc(
    statement: ^sqlite.Statement,
    id: settings.Setting_Id) -> Setting_Value_Read_Result {
    integer_column := sqlite.column_type(statement, 1)
    text_column := sqlite.column_type(statement, 2)
    if integer_column == .Invalid || text_column == .Invalid {
        return {
            reason = .Column_Type,
            failure = sqlite.sqlite_make_validation_error(.Column, .Invalid_State),
        }
    }
    if integer_column != .Null || text_column != .Text {
        return {
            reason = .Null_Column,
        }
    }
    buffer: [DATABASE_TEXT_MAX_BYTES]u8
    count, failure := sqlite.column_text_copy(statement, 2, buffer[:])
    if !store_sqlite_error_is_clear(failure) {
        if failure.validation == .Capacity {
            return {
                reason = .Text_Capacity,
            }
        }
        return {
            reason = .Column_Type,
            failure = failure,
        }
    }
    return store_decode_enum_text(id, string(buffer[:count]))
}

// Decode one persisted spelling for the application's closed text enums.
store_decode_enum_text :: proc(
    id: settings.Setting_Id, value: string) -> Setting_Value_Read_Result {
    #partial switch id {
    case .Window_Mode:
        switch value {
        case "fixed":
            return {
                value = settings.window_mode_value(.Fixed),
            }
        case "resizable":
            return {
                value = settings.window_mode_value(.Resizable),
            }
        }
    case .Window_Layout:
        switch value {
        case "auto":
            return {
                value = settings.layout_preference_value(.Auto),
            }
        case "landscape":
            return {
                value = settings.layout_preference_value(.Landscape),
            }
        case "portrait":
            return {
                value = settings.layout_preference_value(.Portrait),
            }
        }
    }
    return {
        reason = .Unknown_Enum,
    }
}

// Apply each bounded change and preserve the first failing setting identity.
store_apply_batch_changes :: proc(
    store: ^Store,
    changes: settings.Change_Set,
    fail_after_changes: int) -> Batch_Apply_Result {
    for index in 0..<changes.count {
        change := changes.changes[index]
        failure := store_apply_change(store, change)
        if store_sqlite_error_is_clear(failure) &&
            fail_after_changes == index + 1 {
            failure = store_exec(
                store,
                "INSERT INTO user_setting VALUES ('', '', 'boolean', 0, NULL)")
        }
        if !store_sqlite_error_is_clear(failure) {
            return {
                failure = failure,
                failed_id = change.id,
                has_failed_id = true,
            }
        }
    }
    return {}
}

// Apply one prepared Set or Reset operation inside the active transaction.
store_apply_change :: proc(store: ^Store, change: settings.Change) -> sqlite.Error {
    definition, valid := settings.setting_definition(change.id)
    if !valid {
        return sqlite.sqlite_make_validation_error(.Bind, .Invalid_Argument)
    }
    if change.kind == .Reset {
        return store_delete_setting(store, definition)
    }
    if !settings.valid_setting_value(change.id, change.value) {
        return sqlite.sqlite_make_validation_error(.Bind, .Invalid_Argument)
    }
    return store_upsert_setting(store, definition, change.value)
}

// Delete one known preference so its current application default applies.
store_delete_setting :: proc(
    store: ^Store,
    definition: settings.Setting_Definition) -> sqlite.Error {
    statement := &store^.delete_setting
    failure := sqlite.statement_reset(statement)
    if store_sqlite_error_is_clear(failure) {
        failure = sqlite.statement_bind_text(statement, 1, definition.namespace)
    }
    if store_sqlite_error_is_clear(failure) {
        failure = sqlite.statement_bind_text(statement, 2, definition.key)
    }
    if store_sqlite_error_is_clear(failure) {
        status, step_error := sqlite.statement_step(statement)
        failure = step_error
        if store_sqlite_error_is_clear(failure) && status != .Done {
            failure = sqlite.sqlite_make_validation_error(.Step, .Invalid_State)
        }
    }
    return store_reset_preserving(statement, failure)
}

// Upsert one validated typed setting with exact scalar storage columns.
store_upsert_setting :: proc(
    store: ^Store,
    definition: settings.Setting_Definition,
    value: settings.Setting_Value) -> sqlite.Error {
    statement := &store^.upsert_setting
    failure := sqlite.statement_reset(statement)
    if store_sqlite_error_is_clear(failure) {
        failure = sqlite.statement_bind_text(statement, 1, definition.namespace)
    }
    if store_sqlite_error_is_clear(failure) {
        failure = sqlite.statement_bind_text(statement, 2, definition.key)
    }
    if store_sqlite_error_is_clear(failure) {
        failure = sqlite.statement_bind_text(
            statement, 3, store_value_type_name(definition.storage_kind))
    }
    if store_sqlite_error_is_clear(failure) {
        failure = store_bind_setting_value(statement, definition.storage_kind, value)
    }
    if store_sqlite_error_is_clear(failure) {
        status, step_error := sqlite.statement_step(statement)
        failure = step_error
        if store_sqlite_error_is_clear(failure) && status != .Done {
            failure = sqlite.sqlite_make_validation_error(.Step, .Invalid_State)
        }
    }
    return store_reset_preserving(statement, failure)
}

// Bind both value columns according to the catalog's scalar storage kind.
store_bind_setting_value :: proc(
    statement: ^sqlite.Statement,
    kind: settings.Setting_Storage_Kind,
    value: settings.Setting_Value) -> sqlite.Error {
    switch kind {
    case .Boolean:
        integer := i64(0)
        if value.boolean {
            integer = 1
        }
        failure := sqlite.statement_bind_i64(statement, 4, integer)
        if !store_sqlite_error_is_clear(failure) {
            return failure
        }
        return sqlite.statement_bind_null(statement, 5)
    case .Integer:
        failure := sqlite.statement_bind_i64(statement, 4, i64(value.integer))
        if !store_sqlite_error_is_clear(failure) {
            return failure
        }
        return sqlite.statement_bind_null(statement, 5)
    case .Text:
        text := store_enum_text(value)
        failure := sqlite.statement_bind_null(statement, 4)
        if !store_sqlite_error_is_clear(failure) {
            return failure
        }
        return sqlite.statement_bind_text(statement, 5, text)
    }
    return sqlite.sqlite_make_validation_error(.Bind, .Invalid_Argument)
}

// Serialize one closed application enum to its stable durable spelling.
store_enum_text :: proc(value: settings.Setting_Value) -> string {
    switch value.kind {
    case .Boolean, .Integer:
        return ""
    case .Window_Mode:
        if value.window_mode == .Fixed {
            return "fixed"
        }
        if value.window_mode == .Resizable {
            return "resizable"
        }
    case .Layout_Preference:
        switch value.layout {
        case .Auto:
            return "auto"
        case .Landscape:
            return "landscape"
        case .Portrait:
            return "portrait"
        }
    }
    return ""
}


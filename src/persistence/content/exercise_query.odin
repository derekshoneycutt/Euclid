package contentstore

import contentdata "../../core/content"
import sqlite "../../sqlite"

import "core:encoding/uuid"
import "core:unicode/utf8"

// Execute one bounded built-in exercise operation on the content owner thread.
content_database_execute_exercise :: proc(
    database: ^Content_Database,
    request: contentdata.Exercise_Query_Request) -> contentdata.Exercise_Query_Result {
    result: contentdata.Exercise_Query_Result = {
        generation = request.generation,
        index_generation = database.index_generation,
        kind = request.kind,
        status = .Invalid_Request,
        result_offset = request.result_offset,
    }
    if !content_exercise_request_is_valid(request) {
        return result
    }
    switch request.kind {
    case .List:
        return content_database_list_exercises(database, request, result)
    case .Resolve_Alias, .Resolve_Uuid:
        return content_database_resolve_exercise(database, request, result)
    case .Read_Uuid:
        return content_database_read_exercise(database, request, result)
    case .Children:
        return result
    }
    return result
}

// Validate the exact fields permitted by one operation kind.
content_exercise_request_is_valid :: proc(
    request: contentdata.Exercise_Query_Request) -> bool {
    value := request
    if value.kind == .List {
        return value.animation_id_length == contentdata.EXERCISE_UUID_BYTE_COUNT &&
            value.reference_length == 0 &&
            value.page_limit > 0 &&
            value.page_limit <= contentdata.EXERCISE_LIST_PAGE_CAPACITY &&
            value.result_offset <= u32(max(i32)) &&
            contentdata.exercise_uuid_is_valid(
                string(value.animation_id[:value.animation_id_length]))
    }
    if value.animation_id_length != 0 || value.result_offset != 0 ||
       value.page_limit != 0 || value.reference_length == 0 ||
       value.reference_length > len(value.reference) {
        return false
    }
    reference := string(value.reference[:value.reference_length])
    if value.kind == .Resolve_Alias {
        return contentdata.exercise_reference_is_valid(reference)
    }
    if value.kind == .Resolve_Uuid || value.kind == .Read_Uuid {
        return contentdata.exercise_uuid_is_valid(reference)
    }
    return false
}

// Initialize one request-correlated result with the active content generation.
content_exercise_result_make :: proc(
    database: ^Content_Database, request: contentdata.Exercise_Query_Request,
    result: contentdata.Exercise_Query_Result) -> contentdata.Exercise_Query_Result {
    output := result
    output.generation = request.generation
    output.index_generation = database.index_generation
    output.kind = request.kind
    output.result_offset = request.result_offset
    return output
}

// Count all exercises for one animation before fetching its bounded page.
content_database_list_exercises :: proc(
    database: ^Content_Database, request: contentdata.Exercise_Query_Request,
    result: contentdata.Exercise_Query_Result) -> contentdata.Exercise_Query_Result {
    output := content_exercise_result_make(database, request, result)
    request_value := request
    animation_id := string(
        request_value.animation_id[:request_value.animation_id_length])
    count, counted := content_database_exercise_count(database, animation_id)
    if !counted {
        output.status = .Database_Failed
        return output
    }
    output.total_count = count
    if !content_database_exercise_page(database, request_value, &output) {
        output.status = .Database_Failed
        return output
    }
    output.more_available =
        u64(request_value.result_offset) + u64(output.returned_count) < u64(count)
    output.status = .Ready
    return output
}

// Execute and reset the fixed per-animation exercise count statement.
content_database_exercise_count :: proc(
    database: ^Content_Database, animation_id: string) -> (u32, bool) {
    statement := &database.statements.exercise_list_count
    if !search_statement_reset(statement) ||
       !search_bind_text(statement, 1, animation_id) ||
       search_step(statement) != .Row {
        _ = search_statement_reset(statement)
        return 0, false
    }
    count, count_ok := search_column_i64(statement, 0)
    done := search_step(statement) == .Done
    reset := search_statement_reset(statement)
    valid := count_ok && count >= 0 && count <= i64(max(u32))
    return u32(count), done && reset && valid
}

// Read one deterministic bounded page and reject malformed stored columns.
content_database_exercise_page :: proc(
    database: ^Content_Database, request: contentdata.Exercise_Query_Request,
    result: ^contentdata.Exercise_Query_Result) -> bool {
    statement := &database.statements.exercise_list_rows
    request_value := request
    animation_id := string(
        request_value.animation_id[:request_value.animation_id_length])
    if !search_statement_reset(statement) ||
       !search_bind_text(statement, 1, animation_id) ||
       !search_bind_i32(statement, 2, i32(request.page_limit)) ||
       !search_bind_i32(statement, 3, i32(request.result_offset)) {
        _ = search_statement_reset(statement)
        return false
    }
    for result.returned_count < request.page_limit {
        status := search_step(statement)
        if status == .Done {
            return search_statement_reset(statement)
        }
        if status != .Row ||
           !content_database_exercise_summary(statement,
                &result.exercises[result.returned_count]) {
            _ = search_statement_reset(statement)
            return false
        }
        result.returned_count += 1
    }
    return search_statement_reset(statement)
}

// Copy and validate the five fixed metadata columns into pointer-free storage.
content_database_exercise_summary :: proc(
    statement: ^sqlite.Statement,
    summary: ^contentdata.Exercise_Summary) -> bool {
    exercise_id, exercise_ok := content_admission_read_uuid(statement, 0)
    animation_id, animation_ok := content_admission_read_uuid(statement, 1)
    reference_ok := content_admission_exercise_reference(statement, 2)
    title_storage: [contentdata.EXERCISE_TITLE_BYTE_CAPACITY]u8
    title_count, title_ok := content_admission_copy_text(
        statement, 3, title_storage[:], len(title_storage), false)
    order, order_ok := search_column_i64(statement, 4)
    if !exercise_ok || !animation_ok || exercise_id == (uuid.Identifier{}) ||
       animation_id == (uuid.Identifier{}) || !reference_ok ||
       !title_ok || !order_ok || order < 0 || order > i64(max(i32)) {
        return false
    }
    return content_database_exercise_copy_identity(
        statement, summary, title_storage[:title_count], i32(order))
}

// Copy verified exercise identities and title into the fixed result record.
content_database_exercise_copy_identity :: proc(
    statement: ^sqlite.Statement, summary: ^contentdata.Exercise_Summary,
    title: []u8, order: i32) -> bool {
    exercise_id_count, exercise_ok := search_copy_column(
        statement, 0, summary.exercise_id[:])
    animation_id_count, animation_ok := search_copy_column(
        statement, 1, summary.animation_id[:])
    reference_count, reference_ok := search_copy_column(
        statement, 2, summary.reference[:])
    copy(summary.title[:], title)
    if !exercise_ok || !animation_ok || !reference_ok ||
       exercise_id_count != len(summary.exercise_id) ||
       animation_id_count != len(summary.animation_id) {
        return false
    }
    summary.exercise_id_length = u16(exercise_id_count)
    summary.animation_id_length = u16(animation_id_count)
    summary.reference_length = u16(reference_count)
    summary.title_length = u16(len(title))
    summary.display_order = order
    return true
}

// Resolve one friendly reference or stable UUID without interpreting titles.
content_database_resolve_exercise :: proc(
    database: ^Content_Database, request: contentdata.Exercise_Query_Request,
    result: contentdata.Exercise_Query_Result) -> contentdata.Exercise_Query_Result {
    output := content_exercise_result_make(database, request, result)
    request_value := request
    statement := &database.statements.exercise_resolve
    mode := i32(1)
    if request_value.kind == .Resolve_Uuid {
        mode = 2
    }
    reference := string(request_value.reference[:request_value.reference_length])
    if !search_statement_reset(statement) ||
       !search_bind_i32(statement, 1, mode) ||
       !search_bind_text(statement, 2, reference) {
        output.status = .Database_Failed
        _ = search_statement_reset(statement)
        return output
    }
    status := search_step(statement)
    if status == .Row {
        return content_database_resolve_row(statement, output)
    }
    reset := search_statement_reset(statement)
    if status != .Done || !reset {
        output.status = .Database_Failed
        return output
    }
    retired, checked := content_database_exercise_is_retired(database, mode, reference)
    if !checked {
        output.status = .Database_Failed
    } else if retired {
        output.status = .Retired
    } else {
        output.status = .Not_Found
    }
    return output
}

// Decode one successful lookup and verify the query returns a unique row.
content_database_resolve_row :: proc(
    statement: ^sqlite.Statement,
    result: contentdata.Exercise_Query_Result) -> contentdata.Exercise_Query_Result {
    output := result
    if !content_database_exercise_summary(statement, &output.exercise) {
        output.status = .Database_Failed
        _ = search_statement_reset(statement)
        return output
    }
    done := search_step(statement) == .Done
    reset := search_statement_reset(statement)
    output.status = done && reset ? .Ready : .Database_Failed
    output.returned_count = done && reset ? u16(1) : u16(0)
    return output
}

// Read one exercise instruction snapshot by stable UUID.
content_database_read_exercise :: proc(
    database: ^Content_Database, request: contentdata.Exercise_Query_Request,
    result: contentdata.Exercise_Query_Result) -> contentdata.Exercise_Query_Result {
    output := content_exercise_result_make(database, request, result)
    request_value := request
    statement := &database.statements.exercise_read
    exercise_id := string(
        request_value.reference[:request_value.reference_length])
    if !search_statement_reset(statement) ||
       !search_bind_text(statement, 1, exercise_id) {
        output.status = .Database_Failed
        _ = search_statement_reset(statement)
        return output
    }
    status := search_step(statement)
    if status == .Row {
        return content_database_read_exercise_row(statement, output)
    }
    reset := search_statement_reset(statement)
    if status != .Done || !reset {
        output.status = .Database_Failed
        return output
    }
    retired, checked := content_database_exercise_is_retired(database, 2, exercise_id)
    if !checked {
        output.status = .Database_Failed
    } else if retired {
        output.status = .Retired
    } else {
        output.status = .Not_Found
    }
    return output
}

// Copy one complete exercise read and its UTF-8 instruction bytes.
content_database_read_exercise_row :: proc(
    statement: ^sqlite.Statement,
    result: contentdata.Exercise_Query_Result) -> contentdata.Exercise_Query_Result {
    output := result
    if !content_database_exercise_summary(statement, &output.exercise) {
        output.status = .Database_Failed
        _ = search_statement_reset(statement)
        return output
    }
    count, text_ok := search_copy_column(statement, 5, output.instructions[:])
    valid := text_ok && count > 0 && count <= len(output.instructions) &&
        utf8.valid_string(string(output.instructions[:count]))
    done := search_step(statement) == .Done
    reset := search_statement_reset(statement)
    if !valid || !done || !reset {
        output.status = .Database_Failed
        return output
    }
    output.instructions_length = u16(count)
    output.returned_count = 1
    output.status = .Ready
    return output
}

// Check the fixed retired-alias or deleted-identity lookup.
content_database_exercise_is_retired :: proc(
    database: ^Content_Database, mode: i32, reference: string) -> (bool, bool) {
    statement := &database.statements.exercise_retired
    if !search_statement_reset(statement) ||
       !search_bind_i32(statement, 1, mode) ||
       !search_bind_text(statement, 2, reference) ||
       search_step(statement) != .Row {
        _ = search_statement_reset(statement)
        return false, false
    }
    retired, valid := search_column_i64(statement, 0)
    done := search_step(statement) == .Done
    reset := search_statement_reset(statement)
    valid_result := valid && (retired == 0 || retired == 1) && done && reset
    return retired == 1, valid_result
}

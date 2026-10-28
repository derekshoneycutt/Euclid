package termhiststore

import protocol "../../../core/protocol"
import coretext "../../../core/text"
import sqlite "../../../sqlite"

TERMINAL_HISTORY_SEARCH_OLDER_SQL :: #load("sql/search_older.sql", string)
TERMINAL_HISTORY_SEARCH_NEWER_SQL :: #load("sql/search_newer.sql", string)
TERMINAL_HISTORY_SEARCH_COMBINED_OLDER_SQL :: #load(
    "sql/search_combined_older.sql", string)
TERMINAL_HISTORY_SEARCH_COMBINED_NEWER_SQL :: #load(
    "sql/search_combined_newer.sql", string)

// Four lookahead bytes distinguish a cluster boundary at the summary byte limit.
HISTORY_SEARCH_PREFIX_BYTES :: HISTORY_SEARCH_SUMMARY_MAX_BYTES + 4

// Prepare session search without referencing the optional durable schema.
history_store_prepare_search_session :: proc(
    store: ^History_Store) -> History_Store_Error {
    failure := history_store_prepare(
        store, &store^.search_older, TERMINAL_HISTORY_SEARCH_OLDER_SQL)
    if failure.kind != .None {
        return failure
    }
    return history_store_prepare(
        store, &store^.search_newer, TERMINAL_HISTORY_SEARCH_NEWER_SQL)
}

// Prepare combined search only after durable-table admission.
history_store_prepare_search_combined :: proc(
    store: ^History_Store) -> History_Store_Error {
    failure := history_store_prepare(
        store, &store^.search_combined_older, TERMINAL_HISTORY_SEARCH_COMBINED_OLDER_SQL)
    if failure.kind != .None {
        return failure
    }
    return history_store_prepare(
        store, &store^.search_combined_newer, TERMINAL_HISTORY_SEARCH_COMBINED_NEWER_SQL)
}

// Scan one bounded logical window on the exclusively borrowed SQLite connection.
// SQLite may allocate; native output is written only into caller-owned slices.
// Reset releases the statement before return. Failed output must not be published.
history_store_search :: proc(
    store: ^History_Store, request: History_Search_Request,
    rows: []History_Candidate_Summary,
    summaries: []u8) -> History_Search_Result {
    failure := history_store_validate_search(store, request, len(rows))
    if failure.kind != .None {
        return {
            failure = failure,
        }
    }
    statement := history_store_search_statement(store, request)
    failure = history_store_begin_statement(statement)
    if failure.kind == .None {
        failure = history_store_bind_search(statement, request)
    }
    result: History_Search_Result
    if failure.kind == .None {
        result = history_store_search_window(statement, request, rows, summaries)
        failure = result.failure
    }
    failure = history_store_reset_after(statement, failure)
    if failure.kind != .None {
        return {
            failure = failure,
        }
    }
    return result
}

// Validate admission, cursor narrowing, and explicit per-operation work bounds.
history_store_validate_search :: proc(
    store: ^History_Store, request: History_Search_Request,
    row_capacity: int) -> History_Store_Error {
    if !history_store_ready(store) ||
       (request.include_persistent && !store^.durable_available) {
        return {
            kind = .Invalid_State,
        }
    }
    if len(request.query) > HISTORY_SEARCH_QUERY_MAX_BYTES || row_capacity == 0 {
        return {
            kind = .Capacity,
        }
    }
    if request.candidate_budget <= 0 ||
       request.candidate_budget > HISTORY_SEARCH_CANDIDATE_MAX ||
       (request.direction != .Older && request.direction != .Newer) {
        return {
            kind = .Invalid_Argument,
        }
    }
    if request.cursor_valid {
        return history_store_validate_search_cursor(request)
    }
    return {}
}

// Reject invalid or cross-policy cursor positions rather than restarting silently.
history_store_validate_search_cursor :: proc(
    request: History_Search_Request) -> History_Store_Error {
    failure := history_store_validate_identity(request.cursor.source_id)
    if failure.kind != .None {
        return failure
    }
    if request.cursor.submitted_at_unix_ms < 0 ||
       history_store_scope_to_i64(request.cursor.scope) < 0 ||
       (!request.include_persistent && request.cursor.scope != .Session) {
        return {
            kind = .Invalid_Argument,
        }
    }
    return {}
}

// Select fixed SQL by direction and visibility; no query text becomes SQL.
history_store_search_statement :: proc(
    store: ^History_Store, request: History_Search_Request) -> ^sqlite.Statement {
    if request.include_persistent {
        return &store^.search_combined_older if request.direction == .Older else
            &store^.search_combined_newer
    }
    return &store^.search_older if request.direction == .Older else &store^.search_newer
}

// Bind sparse session slots and the complete combined cursor using the same ABI.
history_store_bind_search :: proc(
    statement: ^sqlite.Statement,
    request: History_Search_Request) -> History_Store_Error {
    values: [5]i64 = {
        i64(request.cursor_valid),
        request.cursor.submitted_at_unix_ms,
        history_store_scope_to_i64(request.cursor.scope),
        i64(request.cursor.source_id),
        i64(request.candidate_budget),
    }
    for index in 0..<len(values) {
        if !request.include_persistent && (index == 1 || index == 2) {
            continue
        }
        failure := sqlite_bind_i64(statement, index + 1, values[index])
        if failure.kind != .None {
            return failure
        }
    }
    failure := sqlite_bind_text(statement, 6, request.query)
    if failure.kind != .None {
        return failure
    }
    return sqlite_bind_i64(statement, 7, HISTORY_SEARCH_PREFIX_BYTES)
}

// Advance past nonmatches too; never consume a match that could not be copied.
history_store_search_window :: proc(
    statement: ^sqlite.Statement, request: History_Search_Request,
    rows: []History_Candidate_Summary,
    summaries: []u8) -> History_Search_Result {
    result: History_Search_Result = {
        outcome = .Scanned,
        cursor = request.cursor,
        cursor_valid = request.cursor_valid,
    }
    for result.examined_count < request.candidate_budget {
        if result.row_count == len(rows) {
            result.output_full = true
            break
        }
        status, failure := history_store_step(statement)
        if failure.kind != .None {
            result.failure = failure
            break
        }
        if status == .Done {
            result.exhausted = true
            break
        }
        result.examined_count += 1
        if !history_store_search_consume(statement, rows, summaries, &result) {
            break
        }
    }
    return result
}

// Validate row metadata even for a nonmatch, then publish its consumed position.
history_store_search_consume :: proc(
    statement: ^sqlite.Statement, rows: []History_Candidate_Summary,
    summaries: []u8, result: ^History_Search_Result) -> bool {
    row := history_store_decode_row_metadata(statement)
    result^.failure = row.failure
    if result^.failure.kind != .None {
        return false
    }
    if row.source_length > protocol.TERMINAL_RETAINED_TEXT_MAX_BYTES {
        result^.failure.kind = .Capacity
        return false
    }
    matches, column_failure := sqlite.column_i64(statement, 10)
    result^.failure = history_store_column_error(column_failure)
    if result^.failure.kind != .None {
        return false
    }
    if matches != 0 && matches != 1 {
        result^.failure.kind = .Invalid_Data
        return false
    }
    if matches == 1 &&
       !history_store_search_copy_summary(statement, row, rows, summaries, result) {
        return false
    }
    result^.cursor = {
        submitted_at_unix_ms = row.record.submitted_at_unix_ms,
        scope = row.record.scope,
        source_id = row.record.source_id,
    }
    result^.cursor_valid = true
    return true
}

// Copy only a bounded prefix, clipping complete graphemes without modifying source.
history_store_search_copy_summary :: proc(
    statement: ^sqlite.Statement, row: History_Read_Result,
    rows: []History_Candidate_Summary, summaries: []u8,
    result: ^History_Search_Result) -> bool {
    prefix: [HISTORY_SEARCH_PREFIX_BYTES]u8
    length, copy_failure := sqlite.column_blob_copy(statement, 1, prefix[:])
    result^.failure = history_store_column_error(copy_failure)
    if result^.failure.kind != .None {
        return false
    }
    if length != min(row.source_length, len(prefix)) {
        result^.failure.kind = .Invalid_Data
        return false
    }
    summary_length := coretext.text_grapheme_clamp_boundary(
        string(prefix[:length]), min(length, HISTORY_SEARCH_SUMMARY_MAX_BYTES))
    if summary_length > len(summaries) - result^.summary_bytes {
        result^.output_full = true
        if result^.row_count == 0 {
            result^.failure.kind = .Capacity
        }
        return false
    }
    offset := result^.summary_bytes
    copy(summaries[offset:offset + summary_length], prefix[:summary_length])
    rows[result^.row_count] = {
        record = row.record,
        source_length = row.source_length,
        summary_offset = offset,
        summary_length = summary_length,
        summary_clipped = summary_length < row.source_length,
    }
    result^.row_count += 1
    result^.summary_bytes += summary_length
    return true
}

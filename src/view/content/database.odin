package content

import sqlite "../../sqlite"

import "core:strings"

SEARCH_SPELLFIX_CANDIDATE_CAPACITY :: 8

// One bounded correction candidate copied out of SQLite-owned column storage.
Search_Correction_Candidate :: struct {
    item_index: u8,
    byte_count: u16,
    bytes: [SEARCH_QUERY_ITEM_BYTE_CAPACITY]u8,
    distance: i32,
    rank: i32,
}

// Internal execution outcome paired with a fully initialized result message.
Search_Execution :: struct {
    result: Search_Query_Result,
    ok: bool,
}

// Fixed statement set and connection exclusively owned by the catalogue worker.
Content_Database :: struct {
    connection: sqlite.Connection,
    statements: Content_Statements,
    index_generation: u64,
    expected_table_counts: [12]u16,
    expected_record_count: u32,
}

// Prepare one persistent repository-owned statement for worker-lifetime reuse.
search_prepare :: proc(
    connection: ^sqlite.Connection, statement: ^sqlite.Statement,
    sql: cstring) -> bool {
    failure := sqlite.statement_prepare(connection, statement, sql)
    return failure.validation == .None && failure.result == .Ok
}

// Reset one reusable statement and clear every prior binding.
search_statement_reset :: proc(statement: ^sqlite.Statement) -> bool {
    failure := sqlite.statement_reset(statement)
    return failure.validation == .None && failure.result == .Ok
}

// Bind copied text so request-local bytes may be reused immediately.
search_bind_text :: proc(
    statement: ^sqlite.Statement, index: int, value: string) -> bool {
    failure := sqlite.statement_bind_text(statement, index, value)
    return failure.validation == .None && failure.result == .Ok
}

// Bind one checked integer value to a fixed catalogue query parameter.
search_bind_i32 :: proc(statement: ^sqlite.Statement, index: int, value: i32) -> bool {
    failure := sqlite.statement_bind_i32(statement, index, value)
    return failure.validation == .None && failure.result == .Ok
}

// Copy one exact SQLite text column into caller-owned bounded bytes.
search_copy_column :: proc(
    statement: ^sqlite.Statement, column: int,
    destination: []u8) -> (int, bool) {
    count, failure := sqlite.column_text_copy(statement, column, destination)
    return count, failure.validation == .None && failure.result == .Ok
}

// Step one statement and preserve row, done, and failure as distinct outcomes.
search_step :: proc(statement: ^sqlite.Statement) -> sqlite.Step_Status {
    status, _ := sqlite.statement_step(statement)
    return status
}

// Read the exact SQLite storage class for one catalogue column.
search_column_type :: proc(
    statement: ^sqlite.Statement, column: int) -> sqlite.Column_Type {
    return sqlite.column_type(statement, column)
}

// Read an exact integer column as a checked signed 64-bit value.
search_column_i64 :: proc(statement: ^sqlite.Statement, column: int) -> (i64, bool) {
    value, failure := sqlite.column_i64(statement, column)
    return value, failure.validation == .None && failure.result == .Ok
}

// Read an exact integer column as a checked signed 32-bit value.
search_column_i32 :: proc(statement: ^sqlite.Statement, column: int) -> (i32, bool) {
    value, failure := sqlite.column_i32(statement, column)
    return value, failure.validation == .None && failure.result == .Ok
}

// Parse the first 64 bits of one canonical lowercase SHA-256 identity.
search_generation_from_fingerprint :: proc(value: string) -> (u64, bool) {
    if len(value) != SEARCH_FINGERPRINT_BYTE_COUNT {
        return 0, false
    }
    generation: u64
    for byte in transmute([]u8)value[:16] {
        digit: u64
        if byte >= '0' && byte <= '9' {
            digit = u64(byte - '0')
        } else if byte >= 'a' && byte <= 'f' {
            digit = u64(byte - 'a' + 10)
        } else {
            return 0, false
        }
        generation = generation << 4 | digit
    }
    return generation, true
}

// Read one required metadata value through the fixed bound lookup statement.
search_metadata_equals :: proc(
    database: ^Content_Database, key, expected: string) -> bool {
    statement := &database.statements.search_metadata
    if !search_bind_text(statement, 1, key) || search_step(statement) != .Row {
        _ = search_statement_reset(statement)
        return false
    }
    value_storage: [SEARCH_FINGERPRINT_BYTE_COUNT]u8
    count, copied := search_copy_column(statement, 0, value_storage[:])
    matches := copied && count == len(expected) &&
        string(value_storage[:count]) == expected
    exhausted := search_step(statement) == .Done
    return search_statement_reset(statement) && matches && exhausted
}

// Finalize one optional statement while retaining aggregate cleanup success.
search_finalize :: proc(statement: ^sqlite.Statement, ok: ^bool) {
    if statement.handle == nil {
        return
    }
    failure := sqlite.statement_finalize(statement)
    if failure.validation != .None || failure.result != .Ok {
        ok^ = false
    }
}

// Close every worker-owned SQLite resource in reverse preparation order.
content_database_close :: proc(database: ^Content_Database) -> bool {
    ok := true
    search_finalize(&database.statements.projection_rows, &ok)
    search_finalize(&database.statements.availability_rows, &ok)
    search_finalize(&database.statements.edition_rows, &ok)
    search_finalize(&database.statements.name_rows, &ok)
    search_finalize(&database.statements.catalog_rows, &ok)
    search_finalize(&database.statements.subject_rows, &ok)
    search_finalize(&database.statements.translation_rows, &ok)
    search_finalize(&database.statements.argument_rows, &ok)
    search_finalize(&database.statements.message_rows, &ok)
    search_finalize(&database.statements.locale_rows, &ok)
    search_finalize(&database.statements.raw_metadata_rows, &ok)
    search_finalize(&database.statements.spellfix, &ok)
    search_finalize(&database.statements.search_metadata, &ok)
    search_finalize(&database.statements.search_rows, &ok)
    search_finalize(&database.statements.count, &ok)
    if database.connection.handle != nil {
        failure := sqlite.connection_close(&database.connection)
        if failure.validation != .None || failure.result != .Ok {
            ok = false
        }
    }
    if ok {
        database^ = {}
    }
    return ok
}

// Prepare the complete fixed runtime statement set transactionally.
content_database_prepare_statements :: proc(database: ^Content_Database) -> bool {
    return content_database_prepare_search_statements(database) &&
        content_database_prepare_declaration_statements(database) &&
        content_database_prepare_catalogue_statements(database)
}

// Prepare one named statement against the owned connection.
content_database_prepare :: proc(
    database: ^Content_Database, statement: ^sqlite.Statement, sql: cstring) -> bool {
    return search_prepare(&database.connection, statement, sql)
}

// Prepare the preserved schema-2 search and raw metadata statements.
content_database_prepare_search_statements :: proc(
    database: ^Content_Database) -> bool {
    statements := &database.statements
    return content_database_prepare(
        database, &statements.count, cstring(SEARCH_COUNT_SQL)) &&
        content_database_prepare(
            database, &statements.search_rows, cstring(SEARCH_ROWS_SQL)) &&
        content_database_prepare(
            database, &statements.search_metadata, cstring(SEARCH_METADATA_SQL)) &&
        content_database_prepare(
            database, &statements.spellfix, cstring(SEARCH_SPELLFIX_SQL)) &&
        content_database_prepare(
            database, &statements.raw_metadata_rows, cstring(RAW_METADATA_ROWS_SQL))
}

// Prepare locale and localized UI message declaration statements.
content_database_prepare_declaration_statements :: proc(
    database: ^Content_Database) -> bool {
    statements := &database.statements
    return content_database_prepare(
        database, &statements.locale_rows, cstring(LOCALE_ROWS_SQL)) &&
        content_database_prepare(
            database, &statements.message_rows, cstring(MESSAGE_ROWS_SQL)) &&
        content_database_prepare(
            database, &statements.argument_rows, cstring(ARGUMENT_ROWS_SQL)) &&
        content_database_prepare(
            database, &statements.translation_rows, cstring(TRANSLATION_ROWS_SQL))
}

// Prepare subject, catalogue, edition, availability, and projection statements.
content_database_prepare_catalogue_statements :: proc(
    database: ^Content_Database) -> bool {
    statements := &database.statements
    return content_database_prepare(
        database, &statements.subject_rows, cstring(SUBJECT_ROWS_SQL)) &&
        content_database_prepare(
            database, &statements.catalog_rows, cstring(CATALOG_ROWS_SQL)) &&
        content_database_prepare(
            database, &statements.name_rows, cstring(NAME_ROWS_SQL)) &&
        content_database_prepare(
            database, &statements.edition_rows, cstring(EDITION_ROWS_SQL)) &&
        content_database_prepare(
            database, &statements.availability_rows, cstring(AVAILABILITY_ROWS_SQL)) &&
        content_database_prepare(
            database, &statements.projection_rows, cstring(PROJECTION_ROWS_SQL))
}

// Validate the immutable database contract before worker readiness publication.
content_database_validate_metadata :: proc(
    database: ^Content_Database, expected_fingerprint: string) -> bool {
    if !search_metadata_equals(database, "schema_version", "2") ||
       !search_metadata_equals(database, "sqlite_version", "3.53.4") ||
       !search_metadata_equals(database, "tokenizer_version", "porter-unicode61-v1") ||
       !search_metadata_equals(database, "query_contract_version", "1") ||
       !search_metadata_equals(database, "document_count", "138") ||
       !search_metadata_equals(database, "catalog_fingerprint", expected_fingerprint) ||
       !search_metadata_equals(database, "index_generation", expected_fingerprint) ||
       !content_admission_validate_metadata(database, expected_fingerprint) {
        return false
    }
    generation, valid := search_generation_from_fingerprint(expected_fingerprint)
    database.index_generation = generation
    return valid
}

// Open, configure, and admit one immutable packaged database.
content_database_open :: proc(
    database: ^Content_Database, path, expected_fingerprint: string,
    generation: ^Content_Generation) -> bool {
    open_failure := sqlite.connection_open(
        &database.connection, path, .Immutable_Readonly, context.temp_allocator)
    if open_failure.validation != .None || open_failure.result != .Ok {
        if generation != nil {
            content_generation_reset_failed_read(database, generation)
        }
        _ = content_database_close(database)
        return false
    }
    spellfix_failure := sqlite.connection_register_spellfix(&database.connection)
    if spellfix_failure.validation != .None || spellfix_failure.result != .Ok ||
       !content_database_prepare_statements(database) ||
       !content_database_validate_metadata(database, expected_fingerprint) ||
       !content_generation_read_database(database, generation) {
        if generation != nil {
            content_generation_reset_failed_read(database, generation)
        }
        _ = content_database_close(database)
        return false
    }
    return true
}

// Execute the fixed count statement for one compiler-generated MATCH value.
content_database_count :: proc(
    database: ^Content_Database, match: string) -> (u32, bool) {
    statement := &database.statements.count
    if !search_bind_text(statement, 1, match) || search_step(statement) != .Row {
        _ = search_statement_reset(statement)
        return 0, false
    }
    count, count_ok := search_column_i64(statement, 0)
    ok := count_ok && count >= 0 && count <= i64(max(u32))
    reset_ok := search_statement_reset(statement)
    return u32(count), ok && reset_ok
}

// Decode one built-in source-aware document key from the current result row.
search_read_document_key :: proc(
    statement: ^sqlite.Statement, key: ^Search_Document_Key) -> bool {
    namespace: [7]u8
    namespace_count, namespace_ok := search_copy_column(statement, 0, namespace[:])
    if !namespace_ok || string(namespace[:namespace_count]) != "builtin" {
        return false
    }
    id_count, id_ok := search_copy_column(
        statement, 1, key.document_id.bytes[:])
    if !id_ok || id_count != SEARCH_DOCUMENT_ID_BYTE_COUNT {
        return false
    }
    key.source_namespace = .Builtin
    return true
}

// Fill one bounded deterministic result window through the fixed ranked query.
content_database_rows :: proc(
    database: ^Content_Database, match: string,
    result: ^Search_Query_Result) -> bool {
    statement := &database.statements.search_rows
    if !search_bind_text(statement, 1, match) ||
       !search_bind_i32(statement, 2, i32(SEARCH_RESULT_WINDOW_CAPACITY)) ||
       result.result_offset > u32(max(i32)) ||
       !search_bind_i32(statement, 3, i32(result.result_offset)) {
        _ = search_statement_reset(statement)
        return false
    }
    for result.returned_count < SEARCH_RESULT_WINDOW_CAPACITY {
        status := search_step(statement)
        if status == .Done {
            return search_statement_reset(statement)
        }
        if status != .Row || !search_read_document_key(
            statement, &result.document_keys[result.returned_count]) {
            _ = search_statement_reset(statement)
            return false
        }
        result.returned_count += 1
    }
    return search_statement_reset(statement)
}

// Append one normalized suggestion item while preserving exclusion and phrase shape.
search_append_suggestion_item :: proc(
    result: ^Search_Query_Result, count: ^int, item: ^Search_Query_Item,
    text: []u8, separated: bool) -> bool {
    negative := item.kind == .Negative_Term || item.kind == .Negative_Phrase
    phrase := item.kind == .Positive_Phrase || item.kind == .Negative_Phrase
    required := len(text) + int(separated) + int(negative) + 2 * int(phrase)
    if required > len(result.suggestion_bytes) - count^ {
        return false
    }
    if separated {
        result.suggestion_bytes[count^] = ' '; count^ += 1
    }
    if negative {
        result.suggestion_bytes[count^] = '-'; count^ += 1
    }
    if phrase {
        result.suggestion_bytes[count^] = '"'; count^ += 1
    }
    copy(result.suggestion_bytes[count^:], text)
    count^ += len(text)
    if phrase {
        result.suggestion_bytes[count^] = '"'; count^ += 1
    }
    return true
}

// Reconstruct normalized friendly syntax after replacing one positive term.
search_build_suggestion :: proc(
    parsed: ^Search_Parsed_Query, replacement: ^Search_Correction_Candidate,
    result: ^Search_Query_Result) -> bool {
    count := 0
    for &item, index in parsed.items[:parsed.item_count] {
        text := item.text[:int(item.text_length)]
        if index == int(replacement.item_index) {
            text = replacement.bytes[:replacement.byte_count]
        }
        if !search_append_suggestion_item(
            result, &count, &item, text, index > 0) {
            return false
        }
    }
    result.suggestion_length = u16(count)
    return true
}

// Query bounded spellfix candidates for one positive bare item.
search_spellfix_candidates :: proc(
    database: ^Content_Database, parsed: ^Search_Parsed_Query, item_index: int,
    candidates: ^[SEARCH_SPELLFIX_CANDIDATE_CAPACITY]Search_Correction_Candidate,
    candidate_count: ^int) -> bool {
    item := &parsed.items[item_index]
    if item.kind != .Positive_Term {
        return true
    }
    statement := &database.statements.spellfix
    word := string(item.text[:item.text_length])
    if !search_bind_text(statement, 1, word) ||
       !search_bind_i32(statement, 2, i32(SEARCH_SPELLFIX_CANDIDATE_CAPACITY)) ||
       !search_bind_i32(statement, 3, i32(SEARCH_SPELLFIX_CANDIDATE_CAPACITY)) {
        _ = search_statement_reset(statement)
        return false
    }
    for candidate_count^ < len(candidates) {
        status := search_step(statement)
        if status == .Done {
            return search_statement_reset(statement)
        }
        candidate := &candidates[candidate_count^]
        copied, ok := search_copy_column(statement, 0, candidate.bytes[:])
        if status != .Row || !ok {
            _ = search_statement_reset(statement)
            return false
        }
        candidate.item_index = u8(item_index)
        candidate.byte_count = u16(copied)
        candidate.distance, _ = search_column_i32(statement, 1)
        candidate.rank, _ = search_column_i32(statement, 2)
        candidate_count^ += 1
    }
    return search_statement_reset(statement)
}

// Return whether a candidate improves deterministic distance/frequency ordering.
search_candidate_is_better :: proc(
    candidate, best: ^Search_Correction_Candidate, has_best: bool) -> bool {
    if !has_best || candidate.distance != best.distance {
        return !has_best || candidate.distance < best.distance
    }
    if candidate.rank != best.rank {
        return candidate.rank < best.rank
    }
    candidate_text := string(candidate.bytes[:candidate.byte_count])
    best_text := string(best.bytes[:best.byte_count])
    return strings.compare(candidate_text, best_text) < 0
}

// Find the best spellfix replacement that executes to at least one real result.
content_database_suggestion :: proc(
    database: ^Content_Database, compiled: ^Search_Compiled_Query,
    result: ^Search_Query_Result) -> bool {
    candidates: [SEARCH_SPELLFIX_CANDIDATE_CAPACITY]Search_Correction_Candidate
    candidate_count := 0
    for index in 0..<int(compiled.parsed.item_count) {
        if !search_spellfix_candidates(
            database, &compiled.parsed, index, &candidates, &candidate_count) {
            return false
        }
    }
    best: Search_Correction_Candidate
    has_best := false
    for &candidate in candidates[:candidate_count] {
        candidate_query := compiled.parsed
        item := &candidate_query.items[candidate.item_index]
        item.text_length = candidate.byte_count
        copy(item.text[:], candidate.bytes[:candidate.byte_count])
        candidate_match := search_parsed_query_compile(candidate_query)
        count, ok := content_database_count(
            database, search_compiled_text(&candidate_match))
        if ok && count > 0 && search_candidate_is_better(&candidate, &best, has_best) {
            best = candidate
            has_best = true
        }
    }
    return !has_best || search_build_suggestion(&compiled.parsed, &best, result)
}

// Execute one admitted query and optionally verify a zero-result correction.
content_database_execute :: proc(
    database: ^Content_Database, request: Search_Query_Request) -> Search_Execution {
    result := Search_Query_Result{generation = request.generation,
        index_generation = database.index_generation,
        result_offset = request.result_offset}
    if int(request.query_length) > len(request.query_bytes) ||
       request.result_offset > u32(max(i32)) {
        result.status = .Invalid_Query
        return {result = result, ok = true}
    }
    query_bytes := request.query_bytes
    source := string(query_bytes[:int(request.query_length)])
    compiled := search_query_compile(source)
    if compiled.status != .Success {
        result.status = .Invalid_Query
        return {result = result, ok = true}
    }
    match := search_compiled_text(&compiled)
    total, count_ok := content_database_count(database, match)
    result.total_match_count = total
    if !count_ok || !content_database_rows(database, match, &result) {
        result.status = .Query_Failed
        return {result = result}
    }
    returned_end := u64(result.result_offset) + u64(result.returned_count)
    result.more_available = returned_end < u64(total)
    result.status = .Ready
    suggestion_ok := total > 0 || content_database_suggestion(
        database, &compiled, &result)
    return {result = result, ok = suggestion_ok}
}
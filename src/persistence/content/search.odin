package contentstore

import sqlite "../../sqlite"
import "core:strings"
import contentdata "../../core/content"

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
    statement: ^sqlite.Statement, key: ^contentdata.Search_Document_Key) -> bool {
    namespace: [7]u8
    namespace_count, namespace_ok := search_copy_column(statement, 0, namespace[:])
    if !namespace_ok || string(namespace[:namespace_count]) != "builtin" {
        return false
    }
    id_count, id_ok := search_copy_column(
        statement, 1, key.document_id.bytes[:])
    if !id_ok || id_count != contentdata.SEARCH_DOCUMENT_ID_BYTE_COUNT {
        return false
    }
    key.source_namespace = .Builtin
    return true
}

// Fill one bounded deterministic result window through the fixed ranked query.
content_database_rows :: proc(
    database: ^Content_Database, match: string,
    result: ^contentdata.Search_Query_Result) -> bool {
    statement := &database.statements.search_rows
    if !search_bind_text(statement, 1, match) ||
       !search_bind_i32(statement, 2, i32(contentdata.SEARCH_RESULT_WINDOW_CAPACITY)) ||
       result.result_offset > u32(max(i32)) ||
       !search_bind_i32(statement, 3, i32(result.result_offset)) {
        _ = search_statement_reset(statement)
        return false
    }
    for result.returned_count < contentdata.SEARCH_RESULT_WINDOW_CAPACITY {
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
    result: ^contentdata.Search_Query_Result, count: ^int, item: ^Search_Query_Item,
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
    result: ^contentdata.Search_Query_Result) -> bool {
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
    result: ^contentdata.Search_Query_Result) -> bool {
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
    database: ^Content_Database,
    request: contentdata.Search_Query_Request) -> Search_Execution {
    result: contentdata.Search_Query_Result = {
        generation = request.generation,
        index_generation = database.index_generation,
        result_offset = request.result_offset,
    }
    if int(request.query_length) > len(request.query_bytes) ||
       request.result_offset > u32(max(i32)) {
        result.status = .Invalid_Query
        return {
            result = result,
            ok = true,
        }
    }
    query_bytes := request.query_bytes
    source := string(query_bytes[:int(request.query_length)])
    compiled := search_query_compile(source)
    if compiled.status != .Success {
        result.status = .Invalid_Query
        return {
            result = result,
            ok = true,
        }
    }
    match := search_compiled_text(&compiled)
    total, count_ok := content_database_count(database, match)
    result.total_match_count = total
    if !count_ok || !content_database_rows(database, match, &result) {
        result.status = .Query_Failed
        return {
            result = result,
        }
    }
    returned_end := u64(result.result_offset) + u64(result.returned_count)
    result.more_available = returned_end < u64(total)
    result.status = .Ready
    suggestion_ok := total > 0 || content_database_suggestion(
        database, &compiled, &result)
    return {
        result = result,
        ok = suggestion_ok,
    }
}

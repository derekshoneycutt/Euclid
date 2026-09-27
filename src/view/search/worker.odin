package search

import sqlite3 "../../../libs/sqlite3"

import "core:c"
import "core:mem"
import tlsf "core:mem/tlsf"
import vmem "core:mem/virtual"
import "core:strings"
import "core:sync/chan"
import "core:thread"

SEARCH_WORKER_CHANNEL_CAPACITY :: 8
SEARCH_WORKER_ALLOCATOR_CAPACITY :: 256 * 1024
SEARCH_DATABASE_PATH_CAPACITY :: 4096
SEARCH_FINGERPRINT_BYTE_COUNT :: 64
SEARCH_SPELLFIX_CANDIDATE_CAPACITY :: 8

SEARCH_COUNT_SQL :: `SELECT count(*) FROM animation_search
WHERE animation_search MATCH ?1`
SEARCH_ROWS_SQL :: `SELECT documents.source_namespace, documents.document_id
FROM animation_search
JOIN search_documents AS documents ON documents.rowid = animation_search.rowid
WHERE animation_search MATCH ?1
ORDER BY bm25(animation_search, 10.0, 6.0, 8.0, 2.0) ASC,
documents.source_namespace ASC, documents.document_id ASC
LIMIT ?2 OFFSET ?3`
SEARCH_METADATA_SQL :: `SELECT value FROM search_metadata WHERE key = ?1`
SEARCH_SPELLFIX_SQL :: `SELECT word, distance, rank FROM search_terms
WHERE word MATCH ?1 AND top = ?2
ORDER BY distance ASC, rank ASC, word ASC LIMIT ?3`

// Fixed statement set and connection exclusively owned by the worker thread.
Search_Database :: struct {
    handle: ^sqlite3.Database,
    count_statement: ^sqlite3.Statement,
    rows_statement: ^sqlite3.Statement,
    metadata_statement: ^sqlite3.Statement,
    spellfix_statement: ^sqlite3.Statement,
    index_generation: u64,
}

// One bounded correction candidate copied out of SQLite-owned column storage.
Search_Correction_Candidate :: struct {
    item_index: u8,
    byte_count: u16,
    bytes: [SEARCH_QUERY_ITEM_BYTE_CAPACITY]u8,
    distance: i32,
    rank: i32,
}

// Dedicated worker service with fixed allocator and value-message channels.
Search_Service :: struct {
    requests: chan.Chan(Search_Worker_Request),
    results: chan.Chan(Search_Query_Result),
    worker: ^thread.Thread,
    backing: []byte,
    allocator_state: tlsf.Allocator,
    synchronized_allocator: mem.Mutex_Allocator,
    database_path_length: u16,
    database_path: [SEARCH_DATABASE_PATH_CAPACITY]u8,
    expected_fingerprint: [SEARCH_FINGERPRINT_BYTE_COUNT]u8,
    index_generation: u64,
    running: bool,
}

// Internal execution outcome paired with a fully initialized result message.
Search_Execution :: struct {
    result: Search_Query_Result,
    ok: bool,
}

// Return whether one SQLite operation produced its required exact status.
search_sqlite_status_is :: proc(actual, expected: sqlite3.Result) -> bool {
    return actual == expected
}

// Prepare one persistent repository-owned statement for worker-lifetime reuse.
search_prepare :: proc(
    database: ^sqlite3.Database, sql: cstring) -> (^sqlite3.Statement, bool) {
    statement: ^sqlite3.Statement
    status := sqlite3.sqlite3_prepare_v3(database, sql, -1,
        c.uint(sqlite3.Prepare_Flag.Persistent), &statement, nil)
    return statement, search_sqlite_status_is(status, .Ok)
}

// Reset one reusable statement and clear every prior binding.
search_statement_reset :: proc(statement: ^sqlite3.Statement) -> bool {
    if sqlite3.sqlite3_reset(statement) != .Ok {return false}
    return sqlite3.sqlite3_clear_bindings(statement) == .Ok
}

// Bind copied text so request-local bytes may be reused immediately.
search_bind_text :: proc(
    statement: ^sqlite3.Statement, index: c.int, value: string) -> bool {
    encoded := strings.clone_to_cstring(value, context.temp_allocator)
    return sqlite3.sqlite3_bind_text(statement, index, encoded,
        c.int(len(value)), sqlite3.transient_destructor()) == .Ok
}

// Copy one exact SQLite text column into caller-owned bounded bytes.
search_copy_column :: proc(
    statement: ^sqlite3.Statement, column: c.int,
    destination: []u8) -> (int, bool) {
    count := int(sqlite3.sqlite3_column_bytes(statement, column))
    source := sqlite3.sqlite3_column_text(statement, column)
    if source == nil || count < 0 || count > len(destination) {return 0, false}
    copy(destination[:count], string(source)[:count])
    return count, true
}

// Parse the first 64 bits of one canonical lowercase SHA-256 identity.
search_generation_from_fingerprint :: proc(value: string) -> (u64, bool) {
    if len(value) != SEARCH_FINGERPRINT_BYTE_COUNT {return 0, false}
    generation: u64
    for byte in transmute([]u8)value[:16] {
        digit: u64
        if byte >= '0' && byte <= '9' {digit = u64(byte - '0')
        } else if byte >= 'a' && byte <= 'f' {digit = u64(byte - 'a' + 10)
        } else {return 0, false}
        generation = generation << 4 | digit
    }
    return generation, true
}

// Read one required metadata value through the fixed bound lookup statement.
search_metadata_equals :: proc(
    database: ^Search_Database, key, expected: string) -> bool {
    statement := database.metadata_statement
    if !search_bind_text(statement, 1, key) || sqlite3.sqlite3_step(statement) != .Row {
        _ = search_statement_reset(statement)
        return false
    }
    count := int(sqlite3.sqlite3_column_bytes(statement, 0))
    value := sqlite3.sqlite3_column_text(statement, 0)
    matches := value != nil && count == len(expected) && string(value) == expected
    return search_statement_reset(statement) && matches
}

// Finalize one optional statement while retaining aggregate cleanup success.
search_finalize :: proc(statement: ^^sqlite3.Statement, ok: ^bool) {
    if statement^ == nil {return}
    if sqlite3.sqlite3_finalize(statement^) != .Ok {ok^ = false}
    statement^ = nil
}

// Close every worker-owned SQLite resource in reverse preparation order.
search_database_close :: proc(database: ^Search_Database) -> bool {
    ok := true
    search_finalize(&database.spellfix_statement, &ok)
    search_finalize(&database.metadata_statement, &ok)
    search_finalize(&database.rows_statement, &ok)
    search_finalize(&database.count_statement, &ok)
    if database.handle != nil && sqlite3.sqlite3_close(database.handle) != .Ok {
        ok = false
    }
    database^ = {}
    return ok
}

// Prepare the complete fixed runtime statement set.
search_database_prepare_statements :: proc(database: ^Search_Database) -> bool {
    database.count_statement, _ = search_prepare(database.handle, SEARCH_COUNT_SQL)
    if database.count_statement == nil {return false}
    database.rows_statement, _ = search_prepare(database.handle, SEARCH_ROWS_SQL)
    if database.rows_statement == nil {return false}
    database.metadata_statement, _ = search_prepare(database.handle, SEARCH_METADATA_SQL)
    if database.metadata_statement == nil {return false}
    database.spellfix_statement, _ = search_prepare(database.handle, SEARCH_SPELLFIX_SQL)
    return database.spellfix_statement != nil
}

// Validate the immutable database contract before worker readiness publication.
search_database_validate_metadata :: proc(
    database: ^Search_Database, expected_fingerprint: string) -> bool {
    if !search_metadata_equals(database, "schema_version", "1") ||
       !search_metadata_equals(database, "sqlite_version", "3.53.4") ||
       !search_metadata_equals(database, "tokenizer_version", "porter-unicode61-v1") ||
         !search_metadata_equals(database, "query_contract_version", "1") ||
         !search_metadata_equals(database, "document_count", "138") ||
       !search_metadata_equals(database, "catalog_fingerprint", expected_fingerprint) ||
       !search_metadata_equals(database, "index_generation", expected_fingerprint) {
        return false
    }
    generation, valid := search_generation_from_fingerprint(expected_fingerprint)
    database.index_generation = generation
    return valid
}

// Open one validated packaged index read-only with immutable URI semantics.
search_database_open :: proc(
    database: ^Search_Database, path, expected_fingerprint: string) -> bool {
    uri := strings.concatenate({"file:", path, "?immutable=1"},
        context.temp_allocator)
    encoded := strings.clone_to_cstring(uri, context.temp_allocator)
    flags := c.int(sqlite3.Open_Flag.Readonly) | c.int(sqlite3.Open_Flag.Uri) |
        c.int(sqlite3.Open_Flag.No_Mutex)
    if sqlite3.sqlite3_open_v2(encoded, &database.handle, flags, nil) != .Ok {
        _ = search_database_close(database)
        return false
    }
    if sqlite3.euclid_sqlite_register_spellfix(database.handle) != .Ok ||
       !search_database_prepare_statements(database) ||
       !search_database_validate_metadata(database, expected_fingerprint) {
        _ = search_database_close(database)
        return false
    }
    return true
}

// Execute the fixed count statement for one compiler-generated MATCH value.
search_database_count :: proc(
    database: ^Search_Database, match: string) -> (u32, bool) {
    statement := database.count_statement
    if !search_bind_text(statement, 1, match) || sqlite3.sqlite3_step(statement) != .Row {
        _ = search_statement_reset(statement)
        return 0, false
    }
    count := sqlite3.sqlite3_column_int64(statement, 0)
    ok := count >= 0 && count <= c.longlong(max(u32))
    reset_ok := search_statement_reset(statement)
    return u32(count), ok && reset_ok
}

// Decode one built-in source-aware document key from the current result row.
search_read_document_key :: proc(
    statement: ^sqlite3.Statement, key: ^Search_Document_Key) -> bool {
    namespace: [7]u8
    namespace_count, namespace_ok := search_copy_column(statement, 0, namespace[:])
    if !namespace_ok || string(namespace[:namespace_count]) != "builtin" {return false}
    id_count, id_ok := search_copy_column(
        statement, 1, key.document_id.bytes[:])
    if !id_ok || id_count != SEARCH_DOCUMENT_ID_BYTE_COUNT {return false}
    key.source_namespace = .Builtin
    return true
}

// Fill one bounded deterministic result window through the fixed ranked query.
search_database_rows :: proc(
    database: ^Search_Database, match: string,
    result: ^Search_Query_Result) -> bool {
    statement := database.rows_statement
    if !search_bind_text(statement, 1, match) ||
       sqlite3.sqlite3_bind_int(statement, 2, SEARCH_RESULT_WINDOW_CAPACITY) != .Ok ||
       sqlite3.sqlite3_bind_int(statement, 3, c.int(result.result_offset)) != .Ok {
        _ = search_statement_reset(statement)
        return false
    }
    for result.returned_count < SEARCH_RESULT_WINDOW_CAPACITY {
        status := sqlite3.sqlite3_step(statement)
        if status == .Done {return search_statement_reset(statement)}
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
    if required > len(result.suggestion_bytes) - count^ {return false}
    if separated {result.suggestion_bytes[count^] = ' '; count^ += 1}
    if negative {result.suggestion_bytes[count^] = '-'; count^ += 1}
    if phrase {result.suggestion_bytes[count^] = '"'; count^ += 1}
    copy(result.suggestion_bytes[count^:], text)
    count^ += len(text)
    if phrase {result.suggestion_bytes[count^] = '"'; count^ += 1}
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
            result, &count, &item, text, index > 0) {return false}
    }
    result.suggestion_length = u16(count)
    return true
}

// Query bounded spellfix candidates for one positive bare item.
search_spellfix_candidates :: proc(
    database: ^Search_Database, parsed: ^Search_Parsed_Query, item_index: int,
    candidates: ^[SEARCH_SPELLFIX_CANDIDATE_CAPACITY]Search_Correction_Candidate,
    candidate_count: ^int) -> bool {
    item := &parsed.items[item_index]
    if item.kind != .Positive_Term {return true}
    statement := database.spellfix_statement
    word := string(item.text[:item.text_length])
    if !search_bind_text(statement, 1, word) ||
       sqlite3.sqlite3_bind_int(
           statement, 2, SEARCH_SPELLFIX_CANDIDATE_CAPACITY) != .Ok ||
       sqlite3.sqlite3_bind_int(
           statement, 3, SEARCH_SPELLFIX_CANDIDATE_CAPACITY) != .Ok {
        _ = search_statement_reset(statement)
        return false
    }
    for candidate_count^ < len(candidates) {
        status := sqlite3.sqlite3_step(statement)
        if status == .Done {return search_statement_reset(statement)}
        candidate := &candidates[candidate_count^]
        copied, ok := search_copy_column(statement, 0, candidate.bytes[:])
        if status != .Row || !ok {
            _ = search_statement_reset(statement)
            return false
        }
        candidate.item_index = u8(item_index)
        candidate.byte_count = u16(copied)
        candidate.distance = sqlite3.sqlite3_column_int(statement, 1)
        candidate.rank = sqlite3.sqlite3_column_int(statement, 2)
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
    if candidate.rank != best.rank {return candidate.rank < best.rank}
    candidate_text := string(candidate.bytes[:candidate.byte_count])
    best_text := string(best.bytes[:best.byte_count])
    return strings.compare(candidate_text, best_text) < 0
}

// Find the best spellfix replacement that executes to at least one real result.
search_database_suggestion :: proc(
    database: ^Search_Database, compiled: ^Search_Compiled_Query,
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
        count, ok := search_database_count(
            database, search_compiled_text(&candidate_match))
        if ok && count > 0 && search_candidate_is_better(&candidate, &best, has_best) {
            best = candidate
            has_best = true
        }
    }
    return !has_best || search_build_suggestion(&compiled.parsed, &best, result)
}

// Execute one admitted query and optionally verify a zero-result correction.
search_database_execute :: proc(
    database: ^Search_Database, request: Search_Query_Request) -> Search_Execution {
    result := Search_Query_Result{generation = request.generation,
        index_generation = database.index_generation,
        result_offset = request.result_offset}
    if int(request.query_length) > len(request.query_bytes) {
        result.status = .Invalid_Query
        return {result = result, ok = true}
    }
    if request.result_offset > u32(max(i32)) {
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
    total, count_ok := search_database_count(database, match)
    result.total_match_count = total
    if !count_ok || !search_database_rows(database, match, &result) {
        result.status = .Query_Failed
        return {result = result}
    }
    returned_end := u64(result.result_offset) + u64(result.returned_count)
    result.more_available = returned_end < u64(total)
    result.status = .Ready
    suggestion_ok := total > 0 || search_database_suggestion(database, &compiled, &result)
    return {result = result, ok = suggestion_ok}
}

// Drain queued requests and retain shutdown or the newest query generation.
search_worker_coalesce :: proc(
    service: ^Search_Service, first: Search_Worker_Request) -> Search_Worker_Request {
    newest := first
    for {
        candidate, available := chan.try_recv(service.requests)
        if !available {return newest}
        if candidate.kind == .Shutdown ||
           candidate.query.generation >= newest.query.generation {
            newest = candidate
        }
    }
}

// Run the SQLite owner loop, coalescing queued queries to the newest generation.
search_worker_run :: proc(service: ^Search_Service, database: ^Search_Database) {
    for {
        request, received := chan.recv(service.requests)
        if !received {return}
        newest := search_worker_coalesce(service, request)
        if newest.kind == .Shutdown {
            _ = chan.send(service.results, Search_Query_Result{status = .Stopped})
            return
        }
        execution := search_database_execute(database, newest.query)
        if !execution.ok {execution.result.status = .Query_Failed}
        _ = chan.try_send(service.results, execution.result)
        free_all(context.temp_allocator)
    }
}

// Own SQLite from open through finalization on the dedicated worker thread.
search_worker_entry :: proc(data: rawptr) {
    service := cast(^Search_Service)data
    path := string(service.database_path[:service.database_path_length])
    fingerprint := string(service.expected_fingerprint[:])
    database: Search_Database
    ready := search_database_open(&database, path, fingerprint)
    status := ready ? Search_Query_Status.Ready : .Unavailable
    _ = chan.send(service.results, Search_Query_Result{
        status = status, index_generation = database.index_generation})
    if ready {search_worker_run(service, &database)}
    _ = search_database_close(&database)
}

// Release the dedicated channel allocator after all users have stopped.
search_service_release_allocator :: proc(service: ^Search_Service) {
    tlsf.destroy(&service.allocator_state)
    if service.backing != nil {
        vmem.release(raw_data(service.backing), uint(len(service.backing)))
    }
    service.backing = nil
}

// Initialize fixed service storage and both bounded channels.
search_service_init_storage :: proc(service: ^Search_Service) -> bool {
    backing, backing_error := vmem.reserve_and_commit(SEARCH_WORKER_ALLOCATOR_CAPACITY)
    if backing_error != nil {return false}
    service.backing = backing
    if tlsf.init_from_buffer(&service.allocator_state, backing) != .None {
        search_service_release_allocator(service)
        return false
    }
    mem.mutex_allocator_init(
        &service.synchronized_allocator, tlsf.allocator(&service.allocator_state))
    allocator := mem.mutex_allocator(&service.synchronized_allocator)
    requests, request_error := chan.create(
        chan.Chan(Search_Worker_Request), SEARCH_WORKER_CHANNEL_CAPACITY, allocator)
    if request_error != .None {search_service_release_allocator(service); return false}
    service.requests = requests
    results, result_error := chan.create(
        chan.Chan(Search_Query_Result), SEARCH_WORKER_CHANNEL_CAPACITY, allocator)
    if result_error == .None {service.results = results; return true}
    _ = chan.destroy(service.requests)
    search_service_release_allocator(service)
    return false
}

// Start the owner thread with the service allocator inherited in its context.
search_service_start_worker :: proc(service: ^Search_Service) -> bool {
    saved_context := context
    context.allocator = mem.mutex_allocator(&service.synchronized_allocator)
    service.worker = thread.create_and_start_with_data(
        rawptr(service), search_worker_entry)
    context = saved_context
    return service.worker != nil
}

// Join a failed startup and release all service-owned storage.
search_service_rollback_start :: proc(service: ^Search_Service) {
    if service.worker != nil {thread.destroy(service.worker)}
    _ = chan.destroy(service.results)
    _ = chan.destroy(service.requests)
    search_service_release_allocator(service)
    service^ = {}
}

// Start one dedicated worker and synchronously require validated database readiness.
search_service_init :: proc(
    service: ^Search_Service, database_path,
    expected_fingerprint: string) -> bool {
    if service == nil || service.running || len(database_path) == 0 ||
       len(database_path) > len(service.database_path) ||
       len(expected_fingerprint) != SEARCH_FINGERPRINT_BYTE_COUNT {
        return false
    }
    service^ = {}
    copy(service.database_path[:], transmute([]u8)database_path)
    service.database_path_length = u16(len(database_path))
    copy(service.expected_fingerprint[:], transmute([]u8)expected_fingerprint)
    if !search_service_init_storage(service) {service^ = {}; return false}
    if !search_service_start_worker(service) {
        search_service_rollback_start(service)
        return false
    }
    readiness, received := chan.recv(service.results)
    if !received || readiness.status != .Ready {
        search_service_rollback_start(service)
        return false
    }
    service.index_generation = readiness.index_generation
    service.running = true
    return true
}

// Allocate and start one service at an address stable for its worker lifetime.
search_service_create :: proc(
    database_path, expected_fingerprint: string) -> ^Search_Service {
    storage, storage_error := vmem.reserve_and_commit(size_of(Search_Service))
    if storage_error != nil {return nil}
    service := cast(^Search_Service)raw_data(storage)
    service^ = {}
    if search_service_init(service, database_path, expected_fingerprint) {
        return service
    }
    vmem.release(rawptr(service), size_of(Search_Service))
    return nil
}

// Try to submit one query without blocking the display owner.
search_service_try_submit :: proc(
    service: ^Search_Service, request: Search_Query_Request) -> bool {
    return service != nil && service.running && chan.try_send(
        service.requests, Search_Worker_Request{kind = .Query, query = request})
}

// Try to receive one worker result without blocking the display owner.
search_service_try_receive :: proc(
    service: ^Search_Service) -> (Search_Query_Result, bool) {
    if service == nil || !service.running {return {}, false}
    return chan.try_recv(service.results)
}

// Return the immutable index generation validated during worker startup.
search_service_index_generation :: proc(service: ^Search_Service) -> u64 {
    if service == nil || !service.running {return 0}
    return service.index_generation
}

// Stop, join, and release one worker before its owning allocator is destroyed.
search_service_destroy :: proc(service: ^Search_Service) {
    if service == nil {return}
    if service.running {
        _ = chan.send(service.requests, Search_Worker_Request{kind = .Shutdown})
        for {
            result, received := chan.recv(service.results)
            if !received || result.status == .Stopped {break}
        }
        service.running = false
    }
    if service.worker != nil {thread.destroy(service.worker)}
    if service.backing != nil {
        _ = chan.destroy(service.results)
        _ = chan.destroy(service.requests)
        search_service_release_allocator(service)
    }
    service^ = {}
}

// Stop and release one service created with search_service_create.
search_service_destroy_owned :: proc(service: ^Search_Service) {
    if service == nil {return}
    search_service_destroy(service)
    vmem.release(rawptr(service), size_of(Search_Service))
}

// Copy one bounded query into a pointer-free request value.
search_query_request_make :: proc(
    generation: u64, offset: u32, source: string) -> (Search_Query_Request, bool) {
    if len(source) > SEARCH_QUERY_BYTE_CAPACITY {return {}, false}
    request := Search_Query_Request{generation = generation, result_offset = offset,
        query_length = u16(len(source))}
    copy(request.query_bytes[:], transmute([]u8)source)
    return request, true
}
package catalog

import sqlite3 "../../../libs/sqlite3"

import "core:c"
import "core:mem"
import tlsf "core:mem/tlsf"
import vmem "core:mem/virtual"
import "core:strings"
import "core:sync/chan"
import "core:thread"
import "core:unicode/utf8"
import "core:encoding/uuid"

SEARCH_WORKER_CHANNEL_CAPACITY :: 8
SEARCH_SPELLFIX_CANDIDATE_CAPACITY :: 8
CATALOG_EXPECTED_RECORD_COUNT :: CATALOG_RECORD_CAPACITY
CATALOG_SNAPSHOT_EXTRA_ALLOCATOR_CAPACITY :: 64 * 1024

SEARCH_COUNT_SQL :: `SELECT count(*) FROM animation_search
WHERE animation_search MATCH ?1`
SEARCH_ROWS_SQL :: `SELECT documents.source_namespace, documents.animation_id
FROM animation_search
JOIN animation_catalog AS documents ON documents.rowid = animation_search.rowid
WHERE animation_search MATCH ?1
ORDER BY bm25(animation_search, 10.0, 6.0, 8.0, 2.0) ASC,
documents.source_namespace ASC, documents.animation_id ASC
LIMIT ?2 OFFSET ?3`
SEARCH_METADATA_SQL :: `SELECT value FROM search_metadata WHERE key = ?1`
SEARCH_SPELLFIX_SQL :: `SELECT word, distance, rank FROM search_terms
WHERE word MATCH ?1 AND top = ?2
ORDER BY distance ASC, rank ASC, word ASC LIMIT ?3`
CATALOG_ROWS_SQL :: `SELECT source_namespace, animation_id,
parent_animation_id, node_kind, display_name, sibling_order,
catalog_order, implementation_path
FROM animation_catalog ORDER BY catalog_order ASC`

// Fixed statement set and connection exclusively owned by the worker thread.
Catalog_Database :: struct {
    handle: ^sqlite3.Database,
    count_statement: ^sqlite3.Statement,
    rows_statement: ^sqlite3.Statement,
    catalog_statement: ^sqlite3.Statement,
    metadata_statement: ^sqlite3.Statement,
    spellfix_statement: ^sqlite3.Statement,
    index_generation: u64,
}

SEARCH_WORKER_ALLOCATOR_CAPACITY :: size_of(Catalog_Snapshot) +
    size_of(Catalog_Snapshot) +
    SEARCH_WORKER_CHANNEL_CAPACITY *
        (size_of(Search_Worker_Request) + size_of(Search_Query_Result) +
            size_of(Catalog_Control_Result)) +
    CATALOG_SNAPSHOT_EXTRA_ALLOCATOR_CAPACITY

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

// Coalesced query plus an optional first control request that followed it.
Search_Coalesced_Request :: struct {
    query: Search_Worker_Request,
    pending: Search_Worker_Request,
    has_pending: bool,
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
    if sqlite3.sqlite3_reset(statement) != .Ok {
        return false
    }
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
    if source == nil || count < 0 || count > len(destination) {
        return 0, false
    }
    copy(destination[:count], string(source)[:count])
    return count, true
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
    database: ^Catalog_Database, key, expected: string) -> bool {
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
    if statement^ == nil {
        return
    }
    if sqlite3.sqlite3_finalize(statement^) != .Ok {
        ok^ = false
    }
    statement^ = nil
}

// Close every worker-owned SQLite resource in reverse preparation order.
catalog_database_close :: proc(database: ^Catalog_Database) -> bool {
    ok := true
    search_finalize(&database.spellfix_statement, &ok)
    search_finalize(&database.metadata_statement, &ok)
    search_finalize(&database.catalog_statement, &ok)
    search_finalize(&database.rows_statement, &ok)
    search_finalize(&database.count_statement, &ok)
    if database.handle != nil && sqlite3.sqlite3_close(database.handle) != .Ok {
        ok = false
    }
    database^ = {}
    return ok
}

// Prepare the complete fixed runtime statement set.
catalog_database_prepare_statements :: proc(database: ^Catalog_Database) -> bool {
    database.count_statement, _ = search_prepare(database.handle, SEARCH_COUNT_SQL)
    if database.count_statement == nil {
        return false
    }
    database.rows_statement, _ = search_prepare(database.handle, SEARCH_ROWS_SQL)
    if database.rows_statement == nil {
        return false
    }
    database.catalog_statement, _ = search_prepare(database.handle, CATALOG_ROWS_SQL)
    if database.catalog_statement == nil {
        return false
    }
    database.metadata_statement, _ = search_prepare(database.handle, SEARCH_METADATA_SQL)
    if database.metadata_statement == nil {
        return false
    }
    database.spellfix_statement, _ = search_prepare(database.handle, SEARCH_SPELLFIX_SQL)
    return database.spellfix_statement != nil
}

// Copy one required UTF-8 column, rejecting embedded NUL and invalid byte sequences.
catalog_copy_utf8_column :: proc(
    statement: ^sqlite3.Statement, column: c.int, destination: []u8) -> (int, bool) {
    if sqlite3.sqlite3_column_type(statement, column) != .Text {
        return 0, false
    }
    count, ok := search_copy_column(statement, column, destination)
    if !ok || count == 0 {
        return 0, false
    }
    value := string(destination[:count])
    return count, utf8.valid_string(value) && !strings.contains(value, "\x00")
}

// Parse one required canonical UUID while SQLite column memory is current.
catalog_read_uuid_column :: proc(
    statement: ^sqlite3.Statement, column: c.int) -> (uuid.Identifier, bool) {
    encoded: [SEARCH_DOCUMENT_ID_BYTE_COUNT]u8
    count, ok := catalog_copy_utf8_column(statement, column, encoded[:])
    if !ok || count != SEARCH_DOCUMENT_ID_BYTE_COUNT {
        return {}, false
    }
    identifier, read_error := uuid.read(string(encoded[:count]))
    return identifier, read_error == .None && identifier != uuid.Identifier{}
}

// Admit only package-local slash-separated relative implementation paths.
catalog_implementation_path_is_safe :: proc(path: string) -> bool {
    if len(path) == 0 || path[0] == '/' || strings.contains(path, "\\") ||
       strings.contains(path, ":") || !utf8.valid_string(path) {
        return false
    }
    component_start := 0
    for index in 0..=len(path) {
        if index < len(path) && path[index] != '/' {
            continue
        }
        component := path[component_start:index]
        if len(component) == 0 || component == "." || component == ".." {
            return false
        }
        component_start = index + 1
    }
    return true
}

// Find one stable identity in the fixed snapshot without allocating lookup storage.
catalog_snapshot_find :: proc(
    snapshot: ^Catalog_Snapshot, stable_id: uuid.Identifier) -> int {
    for index in 0..<int(snapshot.record_count) {
        if snapshot.records[index].stable_id == stable_id {
            return index
        }
    }
    return -1
}

// Validate one record's parent chain and uniqueness against prior catalogue rows.
catalog_snapshot_record_is_valid :: proc(
    snapshot: ^Catalog_Snapshot, index: int) -> bool {
    record := &snapshot.records[index]
    if record.has_parent &&
       catalog_snapshot_find(snapshot, record.parent_stable_id) < 0 {
        return false
    }
    for prior_index in 0..<index {
        prior := &snapshot.records[prior_index]
        same_parent := record.has_parent == prior.has_parent &&
            (!record.has_parent || record.parent_stable_id == prior.parent_stable_id)
        if record.stable_id == prior.stable_id ||
           (same_parent && record.sibling_order == prior.sibling_order) {
            return false
        }
    }
    current := record
    hops := 0
    for current.has_parent {
        parent_index := catalog_snapshot_find(snapshot, current.parent_stable_id)
        if parent_index < 0 || parent_index == index {
            return false
        }
        current = &snapshot.records[parent_index]
        hops += 1
        if hops > int(snapshot.record_count) {
            return false
        }
    }
    return record.node_kind != .Terminal || !record.has_parent
}

// Validate parent existence, sibling order, terminal uniqueness, and acyclic topology.
catalog_snapshot_topology_is_valid :: proc(snapshot: ^Catalog_Snapshot) -> bool {
    terminal_count := 0
    for index in 0..<int(snapshot.record_count) {
        record := &snapshot.records[index]
        if record.node_kind == .Terminal {
            terminal_count += 1
        }
        if !catalog_snapshot_record_is_valid(snapshot, index) {
            return false
        }
    }
    return terminal_count == 1
}

// Validate and copy one row's source identity and optional parent identity.
catalog_record_identity_read :: proc(
    statement: ^sqlite3.Statement, record: ^Catalog_Record) -> bool {
    namespace: [7]u8
    namespace_count, namespace_ok := catalog_copy_utf8_column(statement, 0, namespace[:])
    if !namespace_ok || namespace_count != len(namespace) ||
       string(namespace[:]) != "builtin" {
        return false
    }
    stable_id, id_ok := catalog_read_uuid_column(statement, 1)
    if !id_ok {
        return false
    }
    record.stable_id = stable_id
    if sqlite3.sqlite3_column_type(statement, 2) != .Null {
        parent_stable_id, parent_ok := catalog_read_uuid_column(statement, 2)
        if !parent_ok {
            return false
        }
        record.parent_stable_id = parent_stable_id
        record.has_parent = true
    }
    return true
}

// Validate and copy one row's node kind, display name, and stable ordering values.
catalog_record_metadata_read :: proc(
    statement: ^sqlite3.Statement, expected_order: int,
    record: ^Catalog_Record) -> bool {
    if sqlite3.sqlite3_column_type(statement, 3) != .Integer ||
       sqlite3.sqlite3_column_type(statement, 5) != .Integer ||
       sqlite3.sqlite3_column_type(statement, 6) != .Integer {
        return false
    }
    kind := sqlite3.sqlite3_column_int(statement, 3)
    if kind < 1 || kind > 3 {
        return false
    }
    record.node_kind = Catalog_Node_Kind(kind)
    name_count, name_ok := catalog_copy_utf8_column(
        statement, 4, record.display_name[:])
    sibling_order := sqlite3.sqlite3_column_int64(statement, 5)
    catalog_order := sqlite3.sqlite3_column_int64(statement, 6)
    if !name_ok || sibling_order < 0 || sibling_order > i64(max(i32)) ||
       catalog_order != i64(expected_order) {
        return false
    }
    record.display_name_length = u16(name_count)
    record.sibling_order = i32(sibling_order)
    record.catalog_order = i32(catalog_order)
    return true
}

// Validate and copy one row's nullable path according to its node kind.
catalog_record_path_read :: proc(
    statement: ^sqlite3.Statement, record: ^Catalog_Record) -> bool {
    path_type := sqlite3.sqlite3_column_type(statement, 7)
    if record.node_kind == .Terminal {
        return path_type == .Null
    }
    path_count, path_ok := catalog_copy_utf8_column(
        statement, 7, record.implementation_path[:])
    if !path_ok || !catalog_implementation_path_is_safe(
        string(record.implementation_path[:path_count])) {
        return false
    }
    record.implementation_path_length = u16(path_count)
    return true
}

// Decode one catalogue row into caller-owned fixed storage.
catalog_database_read_record :: proc(
    statement: ^sqlite3.Statement, expected_order: int,
    record: ^Catalog_Record) -> bool {
    return catalog_record_identity_read(statement, record) &&
        catalog_record_metadata_read(statement, expected_order, record) &&
        catalog_record_path_read(statement, record)
}

// Decode and validate every catalogue row before publishing worker readiness.
catalog_database_read_snapshot :: proc(
    database: ^Catalog_Database, snapshot: ^Catalog_Snapshot) -> bool {
    if snapshot == nil {
        return false
    }
    statement := database.catalog_statement
    snapshot^ = Catalog_Snapshot{
        generation = database.index_generation,
    }
    for index in 0..<CATALOG_RECORD_CAPACITY {
        status := sqlite3.sqlite3_step(statement)
        if status == .Done {
            break
        }
        if status != .Row || !catalog_database_read_record(
            statement, index, &snapshot.records[index]) {
            _ = search_statement_reset(statement)
            return false
        }
        snapshot.record_count += 1
    }
    exhausted := sqlite3.sqlite3_step(statement) == .Done
    reset_ok := search_statement_reset(statement)
    return exhausted && reset_ok &&
        snapshot.record_count == CATALOG_EXPECTED_RECORD_COUNT &&
        snapshot.generation != 0 && catalog_snapshot_topology_is_valid(snapshot)
}

// Validate the immutable database contract before worker readiness publication.
catalog_database_validate_metadata :: proc(
    database: ^Catalog_Database, expected_fingerprint: string) -> bool {
    if !search_metadata_equals(database, "schema_version", "2") ||
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
catalog_database_open :: proc(
    database: ^Catalog_Database, path, expected_fingerprint: string,
    snapshot: ^Catalog_Snapshot) -> bool {
    uri := strings.concatenate({"file:", path, "?immutable=1"},
        context.temp_allocator)
    encoded := strings.clone_to_cstring(uri, context.temp_allocator)
    flags := c.int(sqlite3.Open_Flag.Readonly) | c.int(sqlite3.Open_Flag.Uri) |
        c.int(sqlite3.Open_Flag.No_Mutex)
    if sqlite3.sqlite3_open_v2(encoded, &database.handle, flags, nil) != .Ok {
        _ = catalog_database_close(database)
        return false
    }
    if sqlite3.euclid_sqlite_register_spellfix(database.handle) != .Ok ||
       !catalog_database_prepare_statements(database) ||
         !catalog_database_validate_metadata(database, expected_fingerprint) ||
         !catalog_database_read_snapshot(database, snapshot) {
        _ = catalog_database_close(database)
        return false
    }
    return true
}

// Execute the fixed count statement for one compiler-generated MATCH value.
catalog_database_count :: proc(
    database: ^Catalog_Database, match: string) -> (u32, bool) {
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
catalog_database_rows :: proc(
    database: ^Catalog_Database, match: string,
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
    database: ^Catalog_Database, parsed: ^Search_Parsed_Query, item_index: int,
    candidates: ^[SEARCH_SPELLFIX_CANDIDATE_CAPACITY]Search_Correction_Candidate,
    candidate_count: ^int) -> bool {
    item := &parsed.items[item_index]
    if item.kind != .Positive_Term {
        return true
    }
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
    if candidate.rank != best.rank {
        return candidate.rank < best.rank
    }
    candidate_text := string(candidate.bytes[:candidate.byte_count])
    best_text := string(best.bytes[:best.byte_count])
    return strings.compare(candidate_text, best_text) < 0
}

// Find the best spellfix replacement that executes to at least one real result.
catalog_database_suggestion :: proc(
    database: ^Catalog_Database, compiled: ^Search_Compiled_Query,
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
        count, ok := catalog_database_count(
            database, search_compiled_text(&candidate_match))
        if ok && count > 0 && search_candidate_is_better(&candidate, &best, has_best) {
            best = candidate
            has_best = true
        }
    }
    return !has_best || search_build_suggestion(&compiled.parsed, &best, result)
}

// Execute one admitted query and optionally verify a zero-result correction.
catalog_database_execute :: proc(
    database: ^Catalog_Database, request: Search_Query_Request) -> Search_Execution {
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
    total, count_ok := catalog_database_count(database, match)
    result.total_match_count = total
    if !count_ok || !catalog_database_rows(database, match, &result) {
        result.status = .Query_Failed
        return {result = result}
    }
    returned_end := u64(result.result_offset) + u64(result.returned_count)
    result.more_available = returned_end < u64(total)
    result.status = .Ready
    suggestion_ok := total > 0 || catalog_database_suggestion(
        database, &compiled, &result)
    return {result = result, ok = suggestion_ok}
}

// Drain queued requests and retain shutdown or the newest query generation.
search_worker_coalesce :: proc(
    service: ^Catalog_Service,
    first: Search_Worker_Request) -> Search_Coalesced_Request {
    result := Search_Coalesced_Request{query = first}
    for {
        candidate, available := chan.try_recv(service.requests)
        if !available {
            return result
        }
        if candidate.kind != .Query {
            result.pending = candidate
            result.has_pending = true
            return result
        }
        if candidate.query.generation >= result.query.query.generation {
            result.query = candidate
        }
    }
}

// Publish one worker control result after a staged-catalogue operation.
catalog_worker_control_result :: proc(
    service: ^Catalog_Service, status: Search_Query_Status,
    generation: u64) {
    _ = chan.send(service.control_results, Catalog_Control_Result{
        status = status,
        index_generation = generation,
    })
}

// Stage one immutable candidate while preserving the active query connection.
catalog_worker_stage :: proc(
    service: ^Catalog_Service, staged: ^Catalog_Database,
    request: ^Search_Worker_Request) {
    _ = catalog_database_close(staged)
    service.staged_snapshot^ = {}
    path := string(request.database_path[:request.database_path_length])
    fingerprint := string(request.expected_fingerprint[:])
    if catalog_database_open(staged, path, fingerprint, service.staged_snapshot) {
        catalog_worker_control_result(
            service, .Candidate_Ready, staged.index_generation)
        return
    }
    catalog_worker_control_result(service, .Unavailable, 0)
}

// Promote one admitted candidate and retire the previous active connection.
catalog_worker_commit :: proc(
    service: ^Catalog_Service, active, staged: ^Catalog_Database) {
    if staged.handle == nil {
        catalog_worker_control_result(service, .Unavailable, 0)
        return
    }
    previous := active^
    active^ = staged^
    staged^ = previous
    generation := active.index_generation
    catalog_worker_control_result(service, .Candidate_Committed, generation)
}

// Retire or roll back one candidate and preserve the prior active connection.
catalog_worker_discard :: proc(
    service: ^Catalog_Service, active, staged: ^Catalog_Database,
    committed: bool) {
    if committed {
        active^, staged^ = staged^, active^
    }
    _ = catalog_database_close(staged)
    catalog_worker_control_result(service, .Candidate_Discarded, 0)
}

// Retire the previous active connection after the outer transaction publishes.
catalog_worker_finalize :: proc(
    service: ^Catalog_Service, staged: ^Catalog_Database) {
    _ = catalog_database_close(staged)
    catalog_worker_control_result(service, .Candidate_Finalized, 0)
}

// Dispatch one non-query command and report whether the owner loop should stop.
catalog_worker_dispatch_control :: proc(
    service: ^Catalog_Service, active, staged: ^Catalog_Database,
    request: ^Search_Worker_Request,
    candidate_committed: ^bool) -> (bool, bool) {
    if request.kind == .Query {
        return false, false
    }
    if request.kind == .Shutdown {
        _ = chan.send(service.results, Search_Query_Result{status = .Stopped})
        return true, true
    }
    if request.kind == .Stage {
        catalog_worker_stage(service, staged, request)
    } else if request.kind == .Commit {
        catalog_worker_commit(service, active, staged)
        candidate_committed^ = staged.handle != nil
    } else if request.kind == .Discard {
        catalog_worker_discard(
            service, active, staged, candidate_committed^)
        candidate_committed^ = false
    } else if request.kind == .Finalize {
        catalog_worker_finalize(service, staged)
        candidate_committed^ = false
    }
    return true, false
}

// Run the SQLite owner loop, coalescing adjacent queries without crossing controls.
search_worker_run :: proc(service: ^Catalog_Service, database: ^Catalog_Database) {
    staged: Catalog_Database
    pending: Search_Worker_Request
    has_pending := false
    candidate_committed := false
    defer _ = catalog_database_close(&staged)
    for {
        request: Search_Worker_Request
        if has_pending {
            request = pending
            has_pending = false
        } else {
            received: bool
            request, received = chan.recv(service.requests)
            if !received {
                return
            }
        }
        handled, stop := catalog_worker_dispatch_control(
            service, database, &staged, &request, &candidate_committed)
        if stop {
            return
        }
        if handled {
            continue
        }
        coalesced := search_worker_coalesce(service, request)
        pending = coalesced.pending
        has_pending = coalesced.has_pending
        execution := catalog_database_execute(database, coalesced.query.query)
        if !execution.ok {
            execution.result.status = .Query_Failed
        }
        _ = chan.try_send(service.results, execution.result)
        free_all(context.temp_allocator)
    }
}

// Own SQLite from open through finalization on the dedicated worker thread.
search_worker_entry :: proc(data: rawptr) {
    service := cast(^Catalog_Service)data
    path := string(service.database_path[:service.database_path_length])
    fingerprint := string(service.expected_fingerprint[:])
    database: Catalog_Database
    ready := catalog_database_open(&database, path, fingerprint, service.snapshot)
    status := ready ? Search_Query_Status.Ready : .Unavailable
    _ = chan.send(service.results, Search_Query_Result{
        status = status, index_generation = database.index_generation})
    if ready {
        search_worker_run(service, &database)
    }
    _ = catalog_database_close(&database)
}

// Release the dedicated channel allocator after all users have stopped.
catalog_service_release_allocator :: proc(service: ^Catalog_Service) {
    if service.snapshot != nil {
        free(service.snapshot, mem.mutex_allocator(&service.synchronized_allocator))
        service.snapshot = nil
    }
    if service.staged_snapshot != nil {
        free(service.staged_snapshot,
            mem.mutex_allocator(&service.synchronized_allocator))
        service.staged_snapshot = nil
    }
    tlsf.destroy(&service.allocator_state)
    if service.backing != nil {
        vmem.release(raw_data(service.backing), uint(len(service.backing)))
    }
    service.backing = nil
}

// Allocate both generation-scoped snapshots from the service allocator.
catalog_service_init_snapshots :: proc(
    service: ^Catalog_Service, allocator: mem.Allocator) -> bool {
    service.snapshot = new(Catalog_Snapshot, allocator)
    if service.snapshot == nil {
        return false
    }
    service.staged_snapshot = new(Catalog_Snapshot, allocator)
    return service.staged_snapshot != nil
}

// Allocate bounded request, query-result, and control-result channels.
catalog_service_init_channels :: proc(
    service: ^Catalog_Service, allocator: mem.Allocator) -> bool {
    requests, request_error := chan.create(
        chan.Chan(Search_Worker_Request), SEARCH_WORKER_CHANNEL_CAPACITY, allocator)
    if request_error != .None {
        return false
    }
    service.requests = requests
    results, result_error := chan.create(
        chan.Chan(Search_Query_Result), SEARCH_WORKER_CHANNEL_CAPACITY, allocator)
    if result_error != .None {
        _ = chan.destroy(service.requests)
        return false
    }
    service.results = results
    controls, control_error := chan.create(
        chan.Chan(Catalog_Control_Result), SEARCH_WORKER_CHANNEL_CAPACITY, allocator)
    if control_error == .None {
        service.control_results = controls
        return true
    }
    _ = chan.destroy(service.results)
    _ = chan.destroy(service.requests)
    return false
}

// Initialize fixed service storage and both bounded channels.
catalog_service_init_storage :: proc(service: ^Catalog_Service) -> bool {
    backing, backing_error := vmem.reserve_and_commit(SEARCH_WORKER_ALLOCATOR_CAPACITY)
    if backing_error != nil {
        return false
    }
    service.backing = backing
    if tlsf.init_from_buffer(&service.allocator_state, backing) != .None {
        catalog_service_release_allocator(service)
        return false
    }
    mem.mutex_allocator_init(
        &service.synchronized_allocator, tlsf.allocator(&service.allocator_state))
    allocator := mem.mutex_allocator(&service.synchronized_allocator)
    if !catalog_service_init_snapshots(service, allocator) {
        catalog_service_release_allocator(service)
        return false
    }
    if !catalog_service_init_channels(service, allocator) {
        catalog_service_release_allocator(service)
        return false
    }
    return true
}

// Start the owner thread with the service allocator inherited in its context.
catalog_service_start_worker :: proc(service: ^Catalog_Service) -> bool {
    saved_context := context
    context.allocator = mem.mutex_allocator(&service.synchronized_allocator)
    service.worker = thread.create_and_start_with_data(
        rawptr(service), search_worker_entry)
    context = saved_context
    return service.worker != nil
}

// Join a failed startup and release all service-owned storage.
catalog_service_rollback_start :: proc(service: ^Catalog_Service) {
    if service.worker != nil {
        thread.destroy(service.worker)
    }
    _ = chan.destroy(service.control_results)
    _ = chan.destroy(service.results)
    _ = chan.destroy(service.requests)
    catalog_service_release_allocator(service)
    service^ = {}
}

// Start one dedicated worker and synchronously require validated database readiness.
catalog_service_init :: proc(
    service: ^Catalog_Service, database_path,
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
    if !catalog_service_init_storage(service) {
        service^ = {}
        return false
    }
    if !catalog_service_start_worker(service) {
        catalog_service_rollback_start(service)
        return false
    }
    readiness, received := chan.recv(service.results)
    if !received || readiness.status != .Ready {
        catalog_service_rollback_start(service)
        return false
    }
    service.index_generation = readiness.index_generation
    service.running = true
    return true
}

// Allocate and start one service at an address stable for its worker lifetime.
catalog_service_create :: proc(
    database_path, expected_fingerprint: string) -> ^Catalog_Service {
    storage, storage_error := vmem.reserve_and_commit(size_of(Catalog_Service))
    if storage_error != nil {
        return nil
    }
    service := cast(^Catalog_Service)raw_data(storage)
    service^ = {}
    if catalog_service_init(service, database_path, expected_fingerprint) {
        return service
    }
    vmem.release(rawptr(service), size_of(Catalog_Service))
    return nil
}

// Try to submit one query without blocking the display owner.
catalog_service_try_submit :: proc(
    service: ^Catalog_Service, request: Search_Query_Request) -> bool {
    return service != nil && service.running && chan.try_send(
        service.requests, Search_Worker_Request{kind = .Query, query = request})
}

// Try to receive one worker result without blocking the display owner.
catalog_service_try_receive :: proc(
    service: ^Catalog_Service) -> (Search_Query_Result, bool) {
    if service == nil || !service.running {
        return {}, false
    }
    return chan.try_recv(service.results)
}

// Build one bounded worker request for a candidate immutable database.
catalog_stage_request_make :: proc(
    database_path, expected_fingerprint: string) -> (Search_Worker_Request, bool) {
    if len(database_path) == 0 || len(database_path) > CATALOG_DATABASE_PATH_CAPACITY ||
       len(expected_fingerprint) != SEARCH_FINGERPRINT_BYTE_COUNT {
        return {}, false
    }
    request := Search_Worker_Request{
        kind = .Stage,
        database_path_length = u16(len(database_path)),
    }
    copy(request.database_path[:], transmute([]u8)database_path)
    copy(request.expected_fingerprint[:], transmute([]u8)expected_fingerprint)
    return request, true
}

// Stage and validate one candidate without replacing the active catalogue.
catalog_service_stage :: proc(
    service: ^Catalog_Service, database_path,
    expected_fingerprint: string) -> bool {
    if service == nil || !service.running || service.candidate_state != .None {
        return false
    }
    request, valid := catalog_stage_request_make(database_path, expected_fingerprint)
    if !valid || !chan.send(service.requests, request) {
        return false
    }
    result, received := chan.recv(service.control_results)
    if !received || result.status != .Candidate_Ready {
        return false
    }
    service.candidate_state = .Staged
    return true
}

// Return the immutable candidate snapshot only after staged admission succeeds.
catalog_service_staged_snapshot :: proc(
    service: ^Catalog_Service) -> ^Catalog_Snapshot {
    if service == nil || !service.running || service.staged_snapshot == nil ||
       service.staged_snapshot^.generation == 0 {
        return nil
    }
    return service.staged_snapshot
}

// Promote one admitted candidate and advance the display-visible index generation.
catalog_service_commit :: proc(service: ^Catalog_Service) -> bool {
    if service == nil || !service.running ||
    service.candidate_state != .Staged ||
    service.staged_snapshot^.generation == 0 ||
       !chan.send(service.requests, Search_Worker_Request{kind = .Commit}) {
        return false
    }
    result, received := chan.recv(service.control_results)
    if !received || result.status != .Candidate_Committed {
        return false
    }
    service.snapshot, service.staged_snapshot =
        service.staged_snapshot, service.snapshot
    service.index_generation = result.index_generation
    service.candidate_state = .Committed
    return true
}

// Discard or reverse one candidate while preserving the prior catalogue generation.
catalog_service_discard :: proc(service: ^Catalog_Service) -> bool {
    if service == nil || !service.running ||
       !chan.send(service.requests, Search_Worker_Request{kind = .Discard}) {
        return false
    }
    result, received := chan.recv(service.control_results)
    if !received || result.status != .Candidate_Discarded {
        return false
    }
    if service.candidate_state == .Committed {
        service.snapshot, service.staged_snapshot =
            service.staged_snapshot, service.snapshot
        service.index_generation = service.snapshot^.generation
    }
    service.staged_snapshot^ = {}
    service.candidate_state = .None
    return true
}

// Retire the previous connection after all outer reload publications succeed.
catalog_service_finalize :: proc(service: ^Catalog_Service) -> bool {
    if service == nil || !service.running ||
       service.candidate_state != .Committed ||
       !chan.send(service.requests, Search_Worker_Request{kind = .Finalize}) {
        return false
    }
    result, received := chan.recv(service.control_results)
    if !received || result.status != .Candidate_Finalized {
        return false
    }
    service.staged_snapshot^ = {}
    service.candidate_state = .None
    return true
}

// Return the immutable index generation validated during worker startup.
catalog_service_index_generation :: proc(service: ^Catalog_Service) -> u64 {
    if service == nil || !service.running {
        return 0
    }
    return service.index_generation
}

// Return the immutable snapshot only after complete catalogue admission succeeds.
catalog_service_snapshot :: proc(service: ^Catalog_Service) -> ^Catalog_Snapshot {
    if service == nil || !service.running {
        return nil
    }
    return service.snapshot
}

// Stop, join, and release one worker before its owning allocator is destroyed.
catalog_service_destroy :: proc(service: ^Catalog_Service) {
    if service == nil {
        return
    }
    if service.running {
        _ = chan.send(service.requests, Search_Worker_Request{kind = .Shutdown})
        for {
            result, received := chan.recv(service.results)
            if !received || result.status == .Stopped {
                break
            }
        }
        service.running = false
    }
    if service.worker != nil {
        thread.destroy(service.worker)
    }
    if service.backing != nil {
        _ = chan.destroy(service.control_results)
        _ = chan.destroy(service.results)
        _ = chan.destroy(service.requests)
        catalog_service_release_allocator(service)
    }
    service^ = {}
}

// Stop and release one service created with catalog_service_create.
catalog_service_destroy_owned :: proc(service: ^Catalog_Service) {
    if service == nil {
        return
    }
    catalog_service_destroy(service)
    vmem.release(rawptr(service), size_of(Catalog_Service))
}

// Copy one bounded query into a pointer-free request value.
search_query_request_make :: proc(
    generation: u64, offset: u32, source: string) -> (Search_Query_Request, bool) {
    if len(source) > SEARCH_QUERY_BYTE_CAPACITY {
        return {}, false
    }
    request := Search_Query_Request{generation = generation, result_offset = offset,
        query_length = u16(len(source))}
    copy(request.query_bytes[:], transmute([]u8)source)
    return request, true
}
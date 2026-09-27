package search

import sqlite3 "../../../libs/sqlite3"

import "core:c"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync/chan"
import "core:testing"

SEARCH_TEST_FINGERPRINT ::
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

SEARCH_TEST_SCHEMA :: `
CREATE TABLE search_metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;
CREATE TABLE search_documents(
    rowid INTEGER PRIMARY KEY,
    source_namespace TEXT NOT NULL,
    document_id TEXT NOT NULL,
    node_kind INTEGER NOT NULL,
    display_name TEXT NOT NULL,
    hierarchy_path TEXT NOT NULL,
    aliases TEXT NOT NULL,
    semantic_text TEXT NOT NULL,
    UNIQUE(source_namespace, document_id));
CREATE VIRTUAL TABLE animation_search USING fts5(
    display_name, hierarchy_path, aliases, semantic_text,
    content='search_documents', content_rowid='rowid',
    tokenize='porter unicode61 remove_diacritics 2', detail=full);
CREATE VIRTUAL TABLE search_terms USING spellfix1;
INSERT INTO search_documents VALUES
    (1, 'builtin', '00000000-0000-0000-0000-000000000001', 1,
     'Perpendicular', 'Elements Book I Perpendicular', 'normal line right angle',
     'A line forming equal adjacent right angles is perpendicular.'),
    (2, 'builtin', '00000000-0000-0000-0000-000000000002', 1,
     'Circle', 'Elements Circle', 'round circumference',
     'A circle has points equally distant from its center.'),
    (3, 'builtin', '00000000-0000-0000-0000-000000000003', 1,
     'Line Construction', 'Elements Book I Line Construction', 'straight line',
     'Construct a straight line through two points.');
WITH RECURSIVE sequence(value) AS (
    VALUES(4) UNION ALL SELECT value + 1 FROM sequence WHERE value < 138)
INSERT INTO search_documents
SELECT value, 'builtin', printf('00000000-0000-0000-0000-%012d', value), 1,
       printf('Synthetic %03d', value), 'Synthetic Scale', 'generated fixture',
       'Synthetic searchable geometry document'
FROM sequence;
INSERT INTO animation_search(animation_search) VALUES('rebuild');
INSERT INTO search_terms(word, rank) VALUES
    ('perpendicular', 1), ('circle', 2), ('construction', 3), ('line', 4);
INSERT INTO search_metadata VALUES
    ('schema_version', '1'),
    ('sqlite_version', '3.53.4'),
    ('catalog_fingerprint', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
    ('document_count', '138'),
    ('tokenizer_version', 'porter-unicode61-v1'),
    ('query_contract_version', '1'),
    ('index_generation', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
`

// Owned paths and creation outcome for one temporary search database.
Search_Test_Database :: struct {
    directory: string,
    path: string,
    ok: bool,
}

// Execute one fixed fixture SQL program and release any SQLite diagnostic.
search_test_execute_sql :: proc(database: ^sqlite3.Database, sql: cstring) -> bool {
    message: cstring
    status := sqlite3.sqlite3_exec(database, sql, nil, nil, &message)
    if message != nil {sqlite3.sqlite3_free(rawptr(message))}
    return status == .Ok
}

// Create one isolated immutable-search database fixture under the OS temp directory.
search_test_database_create :: proc(
    suffix: string) -> Search_Test_Database {
    result: Search_Test_Database
    temp, temp_error := os.temp_directory(context.temp_allocator)
    if temp_error != nil {return result}
    directory_name := fmt.tprintf("euclid-search-worker-%s", suffix)
    result.directory, _ = filepath.join(
        []string{temp, directory_name}, context.allocator)
    if len(result.directory) == 0 {return result}
    _ = os.remove_all(result.directory)
    if os.make_directory_all(result.directory) != nil {return result}
    result.path, _ = filepath.join(
        []string{result.directory, "search.sqlite3"}, context.allocator)
    if len(result.path) == 0 {return result}
    database: ^sqlite3.Database
    flags := c.int(sqlite3.Open_Flag.Readwrite) | c.int(sqlite3.Open_Flag.Create)
    encoded_path := strings.clone_to_cstring(result.path, context.temp_allocator)
    if sqlite3.sqlite3_open_v2(encoded_path, &database, flags, nil) != .Ok {
        return result
    }
    registered := sqlite3.euclid_sqlite_register_spellfix(database) == .Ok
    populated := registered && search_test_execute_sql(database, SEARCH_TEST_SCHEMA)
    closed := sqlite3.sqlite3_close(database) == .Ok
    result.ok = populated && closed
    return result
}

// Wait for one result in tests after a successful nonblocking submission.
search_test_receive :: proc(service: ^Search_Service) -> Search_Query_Result {
    result, _ := chan.recv(service.results)
    return result
}

// Submit one query and synchronously receive its worker-owned result in tests.
search_test_query :: proc(
    t: ^testing.T, service: ^Search_Service,
    generation: u64, source: string) -> Search_Query_Result {
    request, valid := search_query_request_make(generation, 0, source)
    testing.expect(t, valid)
    testing.expect(t, search_service_try_submit(service, request))
    return search_test_receive(service)
}

// Submit one query window with an explicit offset and receive its result.
search_test_query_window :: proc(
    t: ^testing.T, service: ^Search_Service,
    generation: u64, offset: u32, source: string) -> Search_Query_Result {
    request, valid := search_query_request_make(generation, offset, source)
    testing.expect(t, valid)
    testing.expect(t, search_service_try_submit(service, request))
    return search_test_receive(service)
}

// Verify immutable startup, friendly query behavior, ranking, and joined shutdown.
@(test)
search_worker_executes_bounded_ranked_queries :: proc(t: ^testing.T) {
    fixture := search_test_database_create("queries")
    defer delete(fixture.directory)
    defer delete(fixture.path)
    defer _ = os.remove_all(fixture.directory)
    testing.expect(t, fixture.ok)
    service: Search_Service
    testing.expect(t, search_service_init(
        &service, fixture.path, SEARCH_TEST_FINGERPRINT))
    defer search_service_destroy(&service)

    prefix := search_test_query(t, &service, 7, "perpend")
    testing.expect_value(t, prefix.status, Search_Query_Status.Ready)
    testing.expect_value(t, prefix.generation, u64(7))
    testing.expect_value(t, prefix.total_match_count, u32(1))
    testing.expect_value(t, prefix.returned_count, u16(1))
    testing.expect_value(t, prefix.document_keys[0].source_namespace,
        Search_Source_Namespace.Builtin)

    excluded := search_test_query(t, &service, 8, `line -circle`)
    testing.expect_value(t, excluded.status, Search_Query_Status.Ready)
    testing.expect_value(t, excluded.total_match_count, u32(2))
    testing.expect(t, !excluded.more_available)
}

// Verify spellfix suggestions are published only after a corrected query has results.
@(test)
search_worker_verifies_corrections_against_real_results :: proc(t: ^testing.T) {
    fixture := search_test_database_create("correction")
    defer delete(fixture.directory)
    defer delete(fixture.path)
    defer _ = os.remove_all(fixture.directory)
    testing.expect(t, fixture.ok)
    service: Search_Service
    testing.expect(t, search_service_init(
        &service, fixture.path, SEARCH_TEST_FINGERPRINT))
    defer search_service_destroy(&service)

    misspelled := search_test_query(t, &service, 1, "perpendiculr")
    testing.expect_value(t, misspelled.total_match_count, u32(0))
    testing.expect_value(t,
        string(misspelled.suggestion_bytes[:misspelled.suggestion_length]),
        "perpendicular")

    unknown := search_test_query(t, &service, 2,
        "zzzzzzzz -line -circle -perpendicular -construction")
    testing.expect_value(t, unknown.total_match_count, u32(0))
    testing.expect_value(t, unknown.suggestion_length, u16(0))
}

// Verify incompatible metadata prevents worker readiness before any query executes.
@(test)
search_worker_rejects_stale_index_metadata :: proc(t: ^testing.T) {
    fixture := search_test_database_create("metadata")
    defer delete(fixture.directory)
    defer delete(fixture.path)
    defer _ = os.remove_all(fixture.directory)
    testing.expect(t, fixture.ok)
    service: Search_Service
    other := "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    testing.expect(t, !search_service_init(&service, fixture.path, other))
    testing.expect(t, !service.running)
}

// Verify transport shape remains independent of corpus size and rejects oversized text.
@(test)
search_protocol_is_fixed_and_bounded :: proc(t: ^testing.T) {
    testing.expect_value(t, len(Search_Query_Result{}.document_keys),
        SEARCH_RESULT_WINDOW_CAPACITY)
    _, received := search_service_try_receive(nil)
    testing.expect(t, !received)
    oversized: [SEARCH_QUERY_BYTE_CAPACITY + 1]u8
    _, accepted := search_query_request_make(1, 0, string(oversized[:]))
    testing.expect(t, !accepted)
    testing.expect(t, size_of(Search_Query_Result) < 16 * 1024)
}

// Verify large result sets use stable nonoverlapping windows and exact totals.
@(test)
search_worker_pages_large_corpora_without_message_growth :: proc(t: ^testing.T) {
    fixture := search_test_database_create("windows")
    defer delete(fixture.directory)
    defer delete(fixture.path)
    defer _ = os.remove_all(fixture.directory)
    testing.expect(t, fixture.ok)
    service: Search_Service
    testing.expect(t, search_service_init(
        &service, fixture.path, SEARCH_TEST_FINGERPRINT))
    defer search_service_destroy(&service)

    first := search_test_query_window(t, &service, 1, 0, "synthetic")
    second := search_test_query_window(t, &service, 2, 64, "synthetic")
    testing.expect_value(t, first.total_match_count, u32(135))
    testing.expect_value(t, first.returned_count, u16(64))
    testing.expect(t, first.more_available)
    testing.expect_value(t, second.returned_count, u16(64))
    testing.expect(t, second.more_available)
    testing.expect(t,
        first.document_keys[63].document_id != second.document_keys[0].document_id)
}

// Verify queued edits coalesce to the newest generation without blocking admission.
@(test)
search_worker_queue_is_bounded_and_coalesces_newest :: proc(t: ^testing.T) {
    service: Search_Service
    testing.expect(t, search_service_init_storage(&service))
    defer search_service_destroy(&service)
    service.running = true
    for generation in 1..=SEARCH_WORKER_CHANNEL_CAPACITY {
        request, _ := search_query_request_make(u64(generation), 0, "line")
        testing.expect(t, search_service_try_submit(&service, request))
    }
    rejected, _ := search_query_request_make(99, 0, "circle")
    testing.expect(t, !search_service_try_submit(&service, rejected))
    first, received := chan.recv(service.requests)
    testing.expect(t, received)
    newest := search_worker_coalesce(&service, first)
    testing.expect_value(t, newest.query.generation,
        u64(SEARCH_WORKER_CHANNEL_CAPACITY))
    service.running = false
}

// Verify display-side acceptance rejects stale query and index generations.
@(test)
search_result_acceptance_requires_both_current_generations :: proc(t: ^testing.T) {
    result := Search_Query_Result{
        generation = 7, index_generation = 11, status = .Ready}
    testing.expect_value(t, search_result_acceptance(&result, 7, 11),
        Search_Result_Acceptance.Accepted)
    testing.expect_value(t, search_result_acceptance(&result, 8, 11),
        Search_Result_Acceptance.Stale_Query_Generation)
    testing.expect_value(t, search_result_acceptance(&result, 7, 12),
        Search_Result_Acceptance.Stale_Index_Generation)
}
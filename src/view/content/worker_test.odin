#+test
package content

import sqlite3 "../../../libs/sqlite3"
import contentdata "../../core/content"

import "core:c"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync/chan"
import "core:testing"

SEARCH_TEST_FINGERPRINT ::
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
SEARCH_TEST_CANDIDATE_FINGERPRINT ::
    "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

SEARCH_TEST_SCHEMA :: `
CREATE TABLE search_metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;
PRAGMA foreign_keys=ON;
CREATE TABLE animation_catalog(
    rowid INTEGER PRIMARY KEY,
    source_namespace TEXT NOT NULL,
    animation_id TEXT NOT NULL,
    parent_animation_id TEXT,
    node_kind INTEGER NOT NULL,
    display_name TEXT NOT NULL,
    sibling_order INTEGER NOT NULL,
    catalog_order INTEGER NOT NULL,
    implementation_path TEXT,
    hierarchy_path TEXT NOT NULL,
    aliases TEXT NOT NULL,
    semantic_text TEXT NOT NULL,
    UNIQUE(source_namespace, animation_id),
    UNIQUE(source_namespace, catalog_order),
    FOREIGN KEY(source_namespace, parent_animation_id)
        REFERENCES animation_catalog(source_namespace, animation_id)
        DEFERRABLE INITIALLY DEFERRED);
CREATE UNIQUE INDEX animation_catalog_root_order
ON animation_catalog(source_namespace, sibling_order)
WHERE parent_animation_id IS NULL;
CREATE UNIQUE INDEX animation_catalog_child_order
ON animation_catalog(source_namespace, parent_animation_id, sibling_order)
WHERE parent_animation_id IS NOT NULL;
CREATE VIRTUAL TABLE animation_search USING fts5(
    display_name, hierarchy_path, aliases, semantic_text,
    content='animation_catalog', content_rowid='rowid',
    tokenize='porter unicode61 remove_diacritics 2', detail=full);
CREATE VIRTUAL TABLE search_terms USING spellfix1;
INSERT INTO animation_catalog VALUES
    (1, 'builtin', '00000000-0000-0000-0000-000000000001', NULL, 1,
     'Perpendicular', 0, 0, 'synthetic/1.jl',
        'Elements Book I Perpendicular', 'normal line right angle',
     'A line forming equal adjacent right angles is perpendicular.'),
    (2, 'builtin', '00000000-0000-0000-0000-000000000002', NULL, 1,
     'Circle', 1, 1, 'synthetic/2.jl',
        'Elements Circle', 'round circumference',
     'A circle has points equally distant from its center.'),
    (3, 'builtin', '00000000-0000-0000-0000-000000000003', NULL, 1,
     'Line Construction', 2, 2, 'synthetic/3.jl',
        'Elements Book I Line Construction', 'straight line',
     'Construct a straight line through two points.');
WITH RECURSIVE sequence(value) AS (
    VALUES(4) UNION ALL SELECT value + 1 FROM sequence WHERE value < 138)
INSERT INTO animation_catalog
SELECT value, 'builtin', printf('00000000-0000-0000-0000-%012d', value), NULL, 1,
       printf('Synthetic %03d', value), value - 1, value - 1,
       printf('synthetic/%d.jl', value),
    'Synthetic Scale', 'generated fixture',
       'Synthetic searchable geometry document'
FROM sequence;
UPDATE animation_catalog SET node_kind=3, display_name='Terminal',
    implementation_path=NULL WHERE rowid=138;
INSERT INTO animation_search(animation_search) VALUES('rebuild');
INSERT INTO search_terms(word, rank) VALUES
    ('perpendicular', 1), ('circle', 2), ('construction', 3), ('line', 4);
INSERT INTO search_metadata VALUES
    ('schema_version', '2'),
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
    if message != nil {
       sqlite3.sqlite3_free(rawptr(message))
    }
    return status == .Ok
}

// Create one isolated immutable-search database fixture under the OS temp directory.
search_test_database_create :: proc(
    suffix: string) -> Search_Test_Database {
    result: Search_Test_Database
    temp, temp_error := os.temp_directory(context.temp_allocator)
    if temp_error != nil {
       return result
    }
    directory_name := fmt.tprintf("euclid-search-worker-%s", suffix)
    result.directory, _ = filepath.join(
        []string{temp, directory_name}, context.allocator)
    if len(result.directory) == 0 {
       return result
    }
    _ = os.remove_all(result.directory)
    if os.make_directory_all(result.directory) != nil {
       return result
    }
    result.path, _ = filepath.join(
        []string{result.directory, "search.sqlite3"}, context.allocator)
    if len(result.path) == 0 {
       return result
    }
    database: ^sqlite3.Database
    flags := c.int(sqlite3.Open_Flag.Readwrite) | c.int(sqlite3.Open_Flag.Create)
    encoded_path := strings.clone_to_cstring(result.path, context.temp_allocator)
    if sqlite3.sqlite3_open_v2(encoded_path, &database, flags, nil) != .Ok {
        return result
    }
    registered := sqlite3.euclid_sqlite_register_spellfix(database) == .Ok
    populated := registered && search_test_execute_sql(database, SEARCH_TEST_SCHEMA) &&
        search_test_populate_content(database)
    closed := sqlite3.sqlite3_close(database) == .Ok
    result.ok = populated && closed
    return result
}

// Give one fixture a distinct admitted generation and visible catalogue value.
search_test_make_candidate :: proc(
    t: ^testing.T, fixture: ^Search_Test_Database) {
    database: ^sqlite3.Database
    encoded_path := strings.clone_to_cstring(fixture.path, context.temp_allocator)
    opened := sqlite3.sqlite3_open_v2(encoded_path, &database,
        c.int(sqlite3.Open_Flag.Readwrite), nil)
    testing.expect_value(t, opened, sqlite3.Result.Ok)
    if opened != .Ok {
        return
    }
    mutation := "UPDATE search_metadata SET value='" +
        SEARCH_TEST_CANDIDATE_FINGERPRINT + "' WHERE key IN " +
        "('catalog_fingerprint', 'index_generation');" +
        "UPDATE content_metadata SET value='" +
        SEARCH_TEST_CANDIDATE_FINGERPRINT + "' WHERE key IN " +
        "('content_fingerprint', 'generation_identity');" +
        "UPDATE ui_translation SET template='Candidate message' "+
        "WHERE message_key NOT IN (SELECT message_key FROM ui_argument);"+
        "UPDATE edition SET unique_name='Candidate Original' WHERE edition_id='original';"+
        "UPDATE animation_catalog SET display_name='Candidate Perpendicular' " +
        "WHERE rowid=1;"
    encoded := strings.clone_to_cstring(mutation, context.temp_allocator)
    testing.expect(t, search_test_execute_sql(database, encoded))
    testing.expect_value(t, sqlite3.sqlite3_close(database), sqlite3.Result.Ok)
}

// Wait for one result in tests after a successful nonblocking submission.
search_test_receive :: proc(service: ^Content_Service) -> Search_Query_Result {
    result, _ := chan.recv(service.results)
    return result
}

// Mutate one valid fixture and require catalogue startup to reject its snapshot.
search_test_rejects_catalog_mutation :: proc(
    t: ^testing.T, suffix, mutation: string) {
    fixture := search_test_database_create(suffix)
    defer delete(fixture.directory)
    defer delete(fixture.path)
    defer _ = os.remove_all(fixture.directory)
    testing.expect(t, fixture.ok)
    database: ^sqlite3.Database
    encoded_path := strings.clone_to_cstring(fixture.path, context.temp_allocator)
    opened := sqlite3.sqlite3_open_v2(encoded_path, &database,
        c.int(sqlite3.Open_Flag.Readwrite), nil)
    testing.expect_value(t, opened, sqlite3.Result.Ok)
    if opened != .Ok {
       return
    }
    encoded_mutation := strings.clone_to_cstring(mutation, context.temp_allocator)
    testing.expect(t, search_test_execute_sql(database, encoded_mutation))
    testing.expect_value(t, sqlite3.sqlite3_close(database), sqlite3.Result.Ok)
    service: Content_Service
    testing.expect(t, !content_service_init(
        &service, fixture.path, SEARCH_TEST_FINGERPRINT))
    testing.expect(t, !service.running)
}

// Submit one query and synchronously receive its worker-owned result in tests.
search_test_query :: proc(
    t: ^testing.T, service: ^Content_Service,
    generation: u64, source: string) -> Search_Query_Result {
    request, valid := search_query_request_make(generation, 0, source)
    testing.expect(t, valid)
    testing.expect(t, content_service_try_submit(service, request))
    return search_test_receive(service)
}

// Submit one query window with an explicit offset and receive its result.
search_test_query_window :: proc(
    t: ^testing.T, service: ^Content_Service,
    generation: u64, offset: u32, source: string) -> Search_Query_Result {
    request, valid := search_query_request_make(generation, offset, source)
    testing.expect(t, valid)
    testing.expect(t, content_service_try_submit(service, request))
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
    service: Content_Service
    testing.expect(t, content_service_init(
        &service, fixture.path, SEARCH_TEST_FINGERPRINT))
    defer content_service_destroy(&service)
    generation := content_service_generation(&service)
    testing.expect(t, generation != nil)
    testing.expect_value(t, generation^.generation, service.index_generation)
    testing.expect_value(t, generation^.record_count, u16(CATALOG_EXPECTED_RECORD_COUNT))
    testing.expect_value(t,
        generation^.records[137].node_kind, Catalog_Node_Kind.Terminal)
    name, name_status := contentdata.content_generation_text(
        generation, generation^.records[0].display_name)
    testing.expect_value(t, name_status, contentdata.Content_Generation_Status.Ok)
    testing.expect_value(t, name, "Perpendicular")

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

// Verify snapshot admission rejects malformed rows, topology, order, and overflow.
@(test)
catalog_snapshot_rejects_invalid_rows_and_capacity_overflow :: proc(t: ^testing.T) {
    search_test_rejects_catalog_mutation(t, "bad-uuid",
        "UPDATE animation_catalog SET animation_id='not-a-uuid' WHERE rowid=1")
    search_test_rejects_catalog_mutation(t, "bad-utf8",
        "UPDATE animation_catalog SET display_name=CAST(x'80' AS TEXT) WHERE rowid=1")
    search_test_rejects_catalog_mutation(t, "unsafe-path",
        "UPDATE animation_catalog SET implementation_path='../escape.jl' WHERE rowid=2")
    search_test_rejects_catalog_mutation(t, "bad-order",
        "UPDATE animation_catalog SET catalog_order=138 WHERE rowid=1")
    search_test_rejects_catalog_mutation(t, "text-sibling-order",
        "UPDATE animation_catalog SET sibling_order='zero' WHERE rowid=1")
    search_test_rejects_catalog_mutation(t, "missing-parent",
        "UPDATE animation_catalog SET parent_animation_id=" +
        "'00000000-0000-0000-0000-999999999999' WHERE rowid=1")
    search_test_rejects_catalog_mutation(t, "parent-cycle",
        "UPDATE animation_catalog SET parent_animation_id=CASE rowid " +
        "WHEN 1 THEN '00000000-0000-0000-0000-000000000002' " +
        "WHEN 2 THEN '00000000-0000-0000-0000-000000000001' END " +
        "WHERE rowid IN (1, 2)")
    search_test_rejects_catalog_mutation(t, "overflow",
        "INSERT INTO animation_catalog SELECT 139, 'builtin', " +
        "'00000000-0000-0000-0000-000000000139', NULL, 1, 'Overflow', " +
        "138, 138, 'synthetic/139.jl', 'Overflow', '', ''")
}

// Verify spellfix suggestions are published only after a corrected query has results.
@(test)
search_worker_verifies_corrections_against_real_results :: proc(t: ^testing.T) {
    fixture := search_test_database_create("correction")
    defer delete(fixture.directory)
    defer delete(fixture.path)
    defer _ = os.remove_all(fixture.directory)
    testing.expect(t, fixture.ok)
    service: Content_Service
    testing.expect(t, content_service_init(
        &service, fixture.path, SEARCH_TEST_FINGERPRINT))
    defer content_service_destroy(&service)

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
    service: Content_Service
    other := "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    testing.expect(t, !content_service_init(&service, fixture.path, other))
    testing.expect(t, !service.running)
}

// Exercise discard, provisional rollback, and finalized candidate publication.
search_test_catalog_candidate_lifecycle :: proc(
    t: ^testing.T, service: ^Content_Service,
    candidate: ^Search_Test_Database, active_generation: u64) {
    queued, valid := search_query_request_make(1, 0, "perpendicular")
    testing.expect(t, valid && content_service_try_submit(service, queued))
    testing.expect(t, content_service_stage(
        service, candidate.path, SEARCH_TEST_CANDIDATE_FINGERPRINT))
    staged := content_service_staged_generation(service)
    testing.expect(t, staged != nil && staged^.generation != active_generation)
    before_commit := search_test_receive(service)
    testing.expect_value(t, before_commit.index_generation, active_generation)
    testing.expect(t, content_service_discard(service))

    testing.expect(t, content_service_stage(
        service, candidate.path, SEARCH_TEST_CANDIDATE_FINGERPRINT))
    staged = content_service_staged_generation(service)
    staged_generation := staged^.generation
    staged^.generation += 1
    testing.expect(t, !content_service_commit(service))
    staged^.generation = staged_generation
    testing.expect(t, content_service_discard(service))
    testing.expect_value(t, content_service_index_generation(service), active_generation)

    testing.expect(t, content_service_stage(
        service, candidate.path, SEARCH_TEST_CANDIDATE_FINGERPRINT))
    candidate_generation := content_service_staged_generation(service)^.generation
    testing.expect(t, content_service_commit(service))
    testing.expect(t, content_service_discard(service))
    after_rollback := search_test_query(t, service, 2, "perpendicular")
    testing.expect_value(t, after_rollback.index_generation, active_generation)

    testing.expect(t, content_service_stage(
        service, candidate.path, SEARCH_TEST_CANDIDATE_FINGERPRINT))
    testing.expect(t, content_service_commit(service))
    testing.expect(t, content_service_finalize(service))
    after_commit := search_test_query(t, service, 3, "perpendicular")
    testing.expect_value(t, after_commit.index_generation, candidate_generation)
}

// Verify staging is isolated and commit advances snapshot and query generations together.
@(test)
content_worker_stages_discards_and_commits_one_candidate :: proc(t: ^testing.T) {
    active := search_test_database_create("transaction-active")
    candidate := search_test_database_create("transaction-candidate")
    defer delete(active.directory)
    defer delete(active.path)
    defer delete(candidate.directory)
    defer delete(candidate.path)
    defer _ = os.remove_all(active.directory)
    defer _ = os.remove_all(candidate.directory)
    testing.expect(t, active.ok && candidate.ok)
    search_test_make_candidate(t, &candidate)

    service: Content_Service
    testing.expect(t, content_service_init(
        &service, active.path, SEARCH_TEST_FINGERPRINT))
    defer content_service_destroy(&service)
    active_generation := content_service_index_generation(&service)
    search_test_catalog_candidate_lifecycle(
        t, &service, &candidate, active_generation)
}

// Verify transport shape remains independent of corpus size and rejects oversized text.
@(test)
search_protocol_is_fixed_and_bounded :: proc(t: ^testing.T) {
    testing.expect_value(t, len(Search_Query_Result{}.document_keys),
        SEARCH_RESULT_WINDOW_CAPACITY)
    _, received := content_service_try_receive(nil)
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
    service: Content_Service
    testing.expect(t, content_service_init(
        &service, fixture.path, SEARCH_TEST_FINGERPRINT))
    defer content_service_destroy(&service)

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
    service: Content_Service
    testing.expect(t, content_service_init_storage(&service))
    defer content_service_destroy(&service)
    service.running = true
    for generation in 1..=CONTENT_WORKER_CHANNEL_CAPACITY {
        request, _ := search_query_request_make(u64(generation), 0, "line")
        testing.expect(t, content_service_try_submit(&service, request))
    }
    rejected, _ := search_query_request_make(99, 0, "circle")
    testing.expect(t, !content_service_try_submit(&service, rejected))
    first, received := chan.recv(service.requests)
    testing.expect(t, received)
    coalesced := search_worker_coalesce(&service, first)
    testing.expect(t, !coalesced.has_pending)
    testing.expect_value(t, coalesced.query.query.generation,
        u64(CONTENT_WORKER_CHANNEL_CAPACITY))
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
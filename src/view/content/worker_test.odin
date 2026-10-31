#+test
package content

import reader "../../persistence/content"

import contentfixture "../../persistence/content/testsupport"

import sqlite3 "../../../libs/sqlite3"
import contentdata "../../core/content"

import "core:c"
import "core:os"
import "core:strings"
import "core:sync/chan"
import "core:testing"

// Wait for one result in tests after a successful nonblocking submission.
search_test_receive :: proc(service: ^Content_Service) -> Search_Query_Result {
    result, _ := chan.recv(service.results)
    return result
}

// Mutate one valid fixture and require catalogue startup to reject its snapshot.
search_test_rejects_catalog_mutation :: proc(
    t: ^testing.T, suffix, mutation: string) {
    fixture := contentfixture.search_test_database_create(suffix)
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
    testing.expect(t, contentfixture.search_test_execute_sql(database, encoded_mutation))
    testing.expect_value(t, sqlite3.sqlite3_close(database), sqlite3.Result.Ok)
    service: Content_Service
    testing.expect(t, !content_service_init(
        &service, fixture.path, contentfixture.SEARCH_TEST_FINGERPRINT))
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
    fixture := contentfixture.search_test_database_create("queries")
    defer delete(fixture.directory)
    defer delete(fixture.path)
    defer _ = os.remove_all(fixture.directory)
    testing.expect(t, fixture.ok)
    service: Content_Service
    testing.expect(t, content_service_init(
        &service, fixture.path, contentfixture.SEARCH_TEST_FINGERPRINT))
    defer content_service_destroy(&service)
    generation := content_service_generation(&service)
    testing.expect(t, generation != nil)
    testing.expect_value(t, generation^.generation, service.index_generation)
    testing.expect_value(t,
        generation^.record_count, u16(reader.CATALOG_EXPECTED_RECORD_COUNT))
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
    fixture := contentfixture.search_test_database_create("correction")
    defer delete(fixture.directory)
    defer delete(fixture.path)
    defer _ = os.remove_all(fixture.directory)
    testing.expect(t, fixture.ok)
    service: Content_Service
    testing.expect(t, content_service_init(
        &service, fixture.path, contentfixture.SEARCH_TEST_FINGERPRINT))
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
    fixture := contentfixture.search_test_database_create("metadata")
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
    candidate: ^contentfixture.Search_Test_Database, active_generation: u64) {
    queued, valid := search_query_request_make(1, 0, "perpendicular")
    testing.expect(t, valid && content_service_try_submit(service, queued))
    testing.expect(t, content_service_stage(
        service, candidate.path, contentfixture.SEARCH_TEST_CANDIDATE_FINGERPRINT))
    staged := content_service_staged_generation(service)
    testing.expect(t, staged != nil && staged^.generation != active_generation)
    before_commit := search_test_receive(service)
    testing.expect_value(t, before_commit.index_generation, active_generation)
    testing.expect(t, content_service_discard(service))

    testing.expect(t, content_service_stage(
        service, candidate.path, contentfixture.SEARCH_TEST_CANDIDATE_FINGERPRINT))
    staged = content_service_staged_generation(service)
    staged_generation := staged^.generation
    staged^.generation += 1
    testing.expect(t, !content_service_commit(service))
    staged^.generation = staged_generation
    testing.expect(t, content_service_discard(service))
    testing.expect_value(t, content_service_index_generation(service), active_generation)

    testing.expect(t, content_service_stage(
        service, candidate.path, contentfixture.SEARCH_TEST_CANDIDATE_FINGERPRINT))
    candidate_generation := content_service_staged_generation(service)^.generation
    testing.expect(t, content_service_commit(service))
    testing.expect(t, content_service_discard(service))
    after_rollback := search_test_query(t, service, 2, "perpendicular")
    testing.expect_value(t, after_rollback.index_generation, active_generation)

    testing.expect(t, content_service_stage(
        service, candidate.path, contentfixture.SEARCH_TEST_CANDIDATE_FINGERPRINT))
    testing.expect(t, content_service_commit(service))
    testing.expect(t, content_service_finalize(service))
    after_commit := search_test_query(t, service, 3, "perpendicular")
    testing.expect_value(t, after_commit.index_generation, candidate_generation)
}

// Verify staging is isolated and commit advances snapshot and query generations together.
@(test)
content_worker_stages_discards_and_commits_one_candidate :: proc(t: ^testing.T) {
    active := contentfixture.search_test_database_create("transaction-active")
    candidate := contentfixture.search_test_database_create("transaction-candidate")
    defer delete(active.directory)
    defer delete(active.path)
    defer delete(candidate.directory)
    defer delete(candidate.path)
    defer _ = os.remove_all(active.directory)
    defer _ = os.remove_all(candidate.directory)
    testing.expect(t, active.ok && candidate.ok)
    contentfixture.search_test_make_candidate(t, &candidate)

    service: Content_Service
    testing.expect(t, content_service_init(
        &service, active.path, contentfixture.SEARCH_TEST_FINGERPRINT))
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
    fixture := contentfixture.search_test_database_create("windows")
    defer delete(fixture.directory)
    defer delete(fixture.path)
    defer _ = os.remove_all(fixture.directory)
    testing.expect(t, fixture.ok)
    service: Content_Service
    testing.expect(t, content_service_init(
        &service, fixture.path, contentfixture.SEARCH_TEST_FINGERPRINT))
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
    result: Search_Query_Result = {
        generation = 7,
        index_generation = 11,
        status = .Ready,
    }
    testing.expect_value(t, search_result_acceptance(&result, 7, 11),
        Search_Result_Acceptance.Accepted)
    testing.expect_value(t, search_result_acceptance(&result, 8, 11),
        Search_Result_Acceptance.Stale_Query_Generation)
    testing.expect_value(t, search_result_acceptance(&result, 7, 12),
        Search_Result_Acceptance.Stale_Index_Generation)
}

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

// Submit one built-in exercise request and wait for its owner-thread result.
exercise_test_query :: proc(
    t: ^testing.T, service: ^Content_Service,
    request: contentdata.Exercise_Query_Request) -> Exercise_Query_Result {
    testing.expect(t, content_service_try_submit_exercise(service, request))
    result, received := chan.recv(service.exercise_results)
    testing.expect(t, received)
    return result
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
        generation^.records[139].node_kind, Catalog_Node_Kind.Terminal)
    testing.expect_value(t,
        generation^.records[140].node_kind, Catalog_Node_Kind.Builder)
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

// Exercise list, alias/UUID resolution, instruction reads, and empty/missing states.
@(test)
content_worker_reads_bounded_builtin_exercises :: proc(t: ^testing.T) {
    fixture := contentfixture.search_test_database_create("exercise-reads")
    defer delete(fixture.directory)
    defer delete(fixture.path)
    defer _ = os.remove_all(fixture.directory)
    retired := "INSERT INTO retired_exercise_reference VALUES " +
        "('10000000-0000-0000-0000-000000000001','old-exercise',0);"
    testing.expect(t, fixture.ok &&
        contentfixture.content_test_mutate(&fixture, retired))
    service: Content_Service
    testing.expect(t, content_service_init(
        &service, fixture.path, contentfixture.SEARCH_TEST_FINGERPRINT))
    defer content_service_destroy(&service)

    exercise_test_list_page(t, &service)
    exercise_test_resolve_and_read(t, &service)
    exercise_test_catalogue_pages(t, &service)
}

// Verify the worker returns the requested bounded list and generation.
exercise_test_list_page :: proc(t: ^testing.T, service: ^Content_Service) {
    animation_id := "00000000-0000-0000-0000-000000000001"
    list_request, list_valid := contentdata.exercise_query_request_make(
        7, .List, animation_id, "", {0, 4})
    testing.expect(t, list_valid)
    listed := exercise_test_query(t, service, list_request)
    testing.expect_value(t, listed.status, Exercise_Query_Status.Ready)
    testing.expect_value(t, listed.generation, u64(7))
    testing.expect_value(t, listed.total_count, u32(1))
    testing.expect_value(t, listed.returned_count, u16(1))
    testing.expect_value(t,
        string(listed.exercises[0].reference[:listed.exercises[0].reference_length]),
        "test-exercise")
}

// Resolve aliases and UUIDs to the same instruction snapshot, preserving missing states.
exercise_test_resolve_and_read :: proc(t: ^testing.T, service: ^Content_Service) {
    exercise_id := "10000000-0000-0000-0000-000000000001"
    alias_request, alias_valid := contentdata.exercise_query_request_make(
        8, .Resolve_Alias, "", "test-exercise", {})
    testing.expect(t, alias_valid)
    alias := exercise_test_query(t, service, alias_request)
    testing.expect_value(t, alias.status, Exercise_Query_Status.Ready)
    testing.expect_value(t,
        string(alias.exercise.exercise_id[:alias.exercise.exercise_id_length]),
        exercise_id)
    uuid_request, uuid_valid := contentdata.exercise_query_request_make(
        9, .Resolve_Uuid, "", exercise_id, {})
    testing.expect(t, uuid_valid)
    resolved := exercise_test_query(t, service, uuid_request)
    testing.expect_value(t, resolved.status, Exercise_Query_Status.Ready)
    testing.expect_value(t, resolved.exercise, alias.exercise)

    read_request, read_valid := contentdata.exercise_query_request_make(
        10, .Read_Uuid, "", exercise_id, {})
    testing.expect(t, read_valid)
    read := exercise_test_query(t, service, read_request)
    testing.expect_value(t, read.status, Exercise_Query_Status.Ready)
    testing.expect_value(t,
        string(read.instructions[:read.instructions_length]),
        "Synthetic exercise instructions")
    retired_request, retired_valid := contentdata.exercise_query_request_make(
        11, .Resolve_Alias, "", "old-exercise", {})
    testing.expect(t, retired_valid)
    retired_result := exercise_test_query(t, service, retired_request)
    testing.expect_value(t, retired_result.status, Exercise_Query_Status.Retired)
    missing_request, missing_valid := contentdata.exercise_query_request_make(
        12, .Resolve_Alias, "", "missing", {})
    testing.expect(t, missing_valid)
    missing := exercise_test_query(t, service, missing_request)
    testing.expect_value(t, missing.status, Exercise_Query_Status.Not_Found)
}

// Assert hierarchy paging, successful empty windows, and unavailable associations differ.
exercise_test_catalogue_pages :: proc(t: ^testing.T, service: ^Content_Service) {
    root, root_valid := contentdata.exercise_query_request_make(
        13, .Children, "", "", {0, 1})
    testing.expect(t, root_valid)
    roots := exercise_test_query(t, service, root)
    testing.expect_value(t, roots.status, Exercise_Query_Status.Ready)
    testing.expect_value(t, roots.returned_count, u16(1))
    root.result_offset = roots.total_count
    empty_roots := exercise_test_query(t, service, root)
    testing.expect_value(t, empty_roots.status, Exercise_Query_Status.Ready)
    testing.expect_value(t, empty_roots.returned_count, u16(0))
    testing.expect(t, !empty_roots.more_available)
    list, valid := contentdata.exercise_query_request_make(
        14, .List, "00000000-0000-0000-0000-000000000001", "", {1, 1})
    testing.expect(t, valid)
    empty := exercise_test_query(t, service, list)
    testing.expect_value(t, empty.status, Exercise_Query_Status.Ready)
    testing.expect_value(t, empty.total_count, u32(1))
    testing.expect_value(t, empty.returned_count, u16(0))
    missing, missing_valid := contentdata.exercise_query_request_make(
        15, .List, "00000000-0000-0000-0000-999999999999", "", {0, 1})
    testing.expect(t, missing_valid)
    unavailable := exercise_test_query(t, service, missing)
    testing.expect_value(t, unavailable.status, Exercise_Query_Status.Missing_Animation)
}

// A deleted exercise UUID remains reserved and produces a retired result.
@(test)
content_worker_reports_deleted_exercise_identity_as_retired :: proc(t: ^testing.T) {
    fixture := contentfixture.search_test_database_create("exercise-retired-identity")
    defer delete(fixture.directory)
    defer delete(fixture.path)
    defer _ = os.remove_all(fixture.directory)
    mutation := "DELETE FROM builtin_exercise;" +
        "INSERT INTO retired_exercise_reference VALUES " +
        "('10000000-0000-0000-0000-000000000001','deleted-exercise',1);"
    testing.expect(t, fixture.ok &&
        contentfixture.content_test_mutate(&fixture, mutation))
    service: Content_Service
    testing.expect(t, content_service_init(
        &service, fixture.path, contentfixture.SEARCH_TEST_FINGERPRINT))
    defer content_service_destroy(&service)

    request, valid := contentdata.exercise_query_request_make(
        1, .Read_Uuid, "", "10000000-0000-0000-0000-000000000001", {})
    testing.expect(t, valid)
    result := exercise_test_query(t, &service, request)
    testing.expect_value(t, result.status, Exercise_Query_Status.Retired)
}

// An unavailable prepared statement is a database failure, never an empty lookup.
@(test)
content_query_distinguishes_exercise_database_failure :: proc(t: ^testing.T) {
    database: reader.Content_Database
    request, valid := contentdata.exercise_query_request_make(
        1, .Resolve_Alias, "", "test-exercise", {})
    testing.expect(t, valid)
    result := reader.content_database_execute_exercise(&database, request)
    testing.expect_value(t, result.status, Exercise_Query_Status.Database_Failed)
}

// Verify full and trailing windows preserve order with no skipped or duplicated rows.
@(test)
content_worker_pages_exercises_at_the_exact_bound :: proc(t: ^testing.T) {
    fixture := contentfixture.search_test_database_create("exercise-paging")
    defer delete(fixture.directory)
    defer delete(fixture.path)
    defer _ = os.remove_all(fixture.directory)
    mutation := `WITH RECURSIVE n(i) AS (
        SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i<17)
        INSERT INTO builtin_exercise
        SELECT printf('20000000-0000-0000-0000-%012d',i), 'builtin',
        '00000000-0000-0000-0000-000000000001', printf('exercise-%d',i),
        'Paging exercise', i, 'Paging instructions' FROM n;`
    testing.expect(t,
        fixture.ok && contentfixture.content_test_mutate(&fixture, mutation))
    service: Content_Service
    testing.expect(t, content_service_init(
        &service, fixture.path, contentfixture.SEARCH_TEST_FINGERPRINT))
    defer content_service_destroy(&service)
    request, valid := contentdata.exercise_query_request_make(
        1, .List, "00000000-0000-0000-0000-000000000001", "", {0, 16})
    testing.expect(t, valid)
    first := exercise_test_query(t, &service, request)
    testing.expect_value(t, first.status, Exercise_Query_Status.Ready)
    testing.expect_value(t, first.returned_count, u16(16))
    testing.expect_value(t, first.total_count, u32(18))
    testing.expect(t, first.more_available)
    request.result_offset = 16
    last := exercise_test_query(t, &service, request)
    testing.expect_value(t, last.returned_count, u16(2))
    testing.expect_value(t, last.exercises[0].display_order, i32(16))
    testing.expect_value(t, last.exercises[1].display_order, i32(17))
    testing.expect(t, !last.more_available)
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
        "UPDATE animation_catalog SET catalog_order=141 WHERE rowid=1")
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
        "INSERT INTO animation_catalog SELECT 142, 'builtin', " +
        "'00000000-0000-0000-0000-000000000142', NULL, 1, 'Overflow', " +
        "141, 141, 'synthetic/142.jl', 'Overflow', '', ''")
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
    testing.expect(t, size_of(Exercise_Query_Result) < 40 * 1024)
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
    testing.expect_value(t, first.total_match_count, u32(138))
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

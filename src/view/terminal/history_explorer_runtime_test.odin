#+test
package terminalview

import historyruntime "../../terminal/history/runtime"
import termhiststore "../../terminal/history/store"
import protocol "../../core/protocol"
import sqlite "../../sqlite"
import taskpool "../../taskpool"
import viewuserdata "../userdata"
import "core:testing"

History_Explorer_Test_Fixture :: struct {
    history: historyruntime.History_Runtime,
    connection: sqlite.Connection,
    admission: protocol.User_Data_Connection_Admission,
    pool: taskpool.Task_Pool,
}

// Allocate one stable test owner and initialize its joined worker/SQLite fixture.
history_explorer_test_start :: proc(
    t: ^testing.T, durable: bool = false) -> ^History_Explorer_Test_Fixture {
    fixture := new(History_Explorer_Test_Fixture, context.allocator)
    if !history_runtime_test_start(t, {
        history = &fixture.history,
        connection = &fixture.connection,
        admission = &fixture.admission,
        pool = &fixture.pool,
        create_persistent_table = durable,
    }) {
        history_explorer_test_destroy(t, fixture)
        return nil
    }
    history_runtime_attach_generation(&fixture.history, 1)
    return fixture
}

// Drain every borrower before releasing the fixture's test-owned allocation.
history_explorer_test_destroy :: proc(
    t: ^testing.T, fixture: ^History_Explorer_Test_Fixture) {
    if fixture.pool.state == .Running {
        testing.expect(t, history_runtime_test_shutdown(
            t, &fixture.history, &fixture.admission, &fixture.pool))
    }
    taskpool.task_pool_destroy(&fixture.pool)
    if fixture.connection.handle != nil {
        failure := sqlite.connection_close(&fixture.connection)
        testing.expect_value(t, failure.validation, sqlite.Validation_Error.None)
        testing.expect(t, failure.result == .Ok)
    }
    free(fixture, context.allocator)
}

// Store a synthetic source through the ordinary asynchronous mutation lane.
history_explorer_test_insert :: proc(
    t: ^testing.T, fixture: ^History_Explorer_Test_Fixture, id: u64, source: string) {
    testing.expect_value(t, history_runtime_enqueue_insert(
        &fixture.history, history_runtime_test_record(id, 1), source),
        historyruntime.History_Runtime_Enqueue_Result.Queued)
    history_runtime_service(
        &fixture.history, &fixture.admission, &fixture.pool, false)
    history_explorer_test_join(t, fixture)
    testing.expect_value(t, fixture.history.last_write_result.outcome,
        termhiststore.History_Write_Outcome.Stored)
}

// Join admitted history work without executing SQLite on the test owner thread.
history_explorer_test_join :: proc(
    t: ^testing.T, fixture: ^History_Explorer_Test_Fixture) {
    testing.expect(t, history_runtime_test_wait_task(
        &fixture.history, &fixture.admission, &fixture.pool))
    testing.expect(t, viewuserdata.connection_admission_is_idle(&fixture.admission))
}

// Start an explicit query and return the lifecycle token its requests must retain.
history_explorer_test_query :: proc(
    t: ^testing.T, fixture: ^History_Explorer_Test_Fixture,
    opening, query: u64) -> historyruntime.History_Explorer_Identity {
    identity, ready := history_runtime_begin_query(&fixture.history, opening, query)
    testing.expect(t, ready)
    return identity
}

// Supply the documented work bound while leaving all storage policy to admission.
history_explorer_test_search :: proc(
    t: ^testing.T, fixture: ^History_Explorer_Test_Fixture,
    identity: historyruntime.History_Explorer_Identity, request_id: u64,
    scan: termhiststore.History_Search_Request) {
    testing.expect_value(t, history_runtime_request_search(&fixture.history, {
        identity = identity,
        request_id = request_id,
        scan = scan,
    }), historyruntime.History_Runtime_Enqueue_Result.Queued)
}

// Fast typing replaces queued work and retires an already-running old query.
@(test)
history_explorer_coalesces_queries_and_copies_input :: proc(t: ^testing.T) {
    fixture := history_explorer_test_start(t)
    if fixture == nil {
        return
    }
    defer history_explorer_test_destroy(t, fixture)
    history_explorer_test_insert(t, fixture, 1, "needle")
    history_explorer_test_insert(t, fixture, 2, "miss")
    identity := history_explorer_test_query(t, fixture, 1, 1)
    query := [?]u8{'n', 'e', 'e', 'd', 'l', 'e'}
    history_explorer_test_search(t, fixture, identity, 1, {
        query = string(query[:]),
        candidate_budget = 2,
    })
    query[0] = 'x'
    history_runtime_service(
        &fixture.history, &fixture.admission, &fixture.pool, false)
    testing.expect_value(t,
        string(fixture.history.active_query[:6]), "needle")
    identity = history_explorer_test_query(t, fixture, 1, 2)
    history_explorer_test_search(t, fixture, identity, 1, {
        query = "discarded",
        candidate_budget = 2,
    })
    history_explorer_test_search(t, fixture, identity, 2, {
        query = "needle",
        candidate_budget = 2,
    })
    history_explorer_test_join(t, fixture)
    history_explorer_test_expect_search(t, fixture, identity, 2, 1)
}

// Check the joined request identity and copy a small successful candidate batch.
history_explorer_test_expect_search :: proc(
    t: ^testing.T, fixture: ^History_Explorer_Test_Fixture,
    identity: historyruntime.History_Explorer_Identity, request_id: u64, count: int) {
    rows: [8]termhiststore.History_Candidate_Summary
    summaries: [8 * termhiststore.HISTORY_SEARCH_SUMMARY_MAX_BYTES]u8
    completion, consumed := history_runtime_consume_search_result(
        &fixture.history, rows[:], summaries[:])
    testing.expect(t, consumed && completion.ready)
    testing.expect_value(t, completion.request.identity, identity)
    testing.expect_value(t, completion.request.request_id, request_id)
    testing.expect_value(t, completion.request.scan.query, "")
    testing.expect_value(t, completion.result.outcome,
        termhiststore.History_Search_Outcome.Scanned)
    testing.expect_value(t, completion.result.row_count, count)
}

// Each empty window releases admission and allows Settings its next fair turn.
@(test)
history_explorer_zero_matches_continue_between_settings_turns :: proc(t: ^testing.T) {
    fixture := history_explorer_test_start(t)
    if fixture == nil {
        return
    }
    defer history_explorer_test_destroy(t, fixture)
    for id in u64(1)..=5 {
        history_explorer_test_insert(t, fixture, id, "needle" if id == 1 else "miss")
    }
    identity := history_explorer_test_query(t, fixture, 1, 1)
    scan: termhiststore.History_Search_Request = {
        query = "needle",
        candidate_budget = 2,
    }
    rows: [2]termhiststore.History_Candidate_Summary
    summaries: [16]u8
    for window in 0..<3 {
        history_explorer_test_search(t, fixture, identity, u64(window + 1), scan)
        history_runtime_service(
            &fixture.history, &fixture.admission, &fixture.pool, false)
        history_explorer_test_join(t, fixture)
        completion, consumed := history_runtime_consume_search_result(
            &fixture.history, rows[:], summaries[:])
        testing.expect(t, consumed)
        testing.expect_value(t, completion.result.examined_count,
            1 if window == 2 else 2)
        testing.expect_value(t, completion.result.row_count, 1 if window == 2 else 0)
        testing.expect_value(t, completion.result.exhausted, window == 2)
        scan.cursor, scan.cursor_valid =
            completion.result.cursor, completion.result.cursor_valid
        history_explorer_test_settings_turn(t, fixture)
    }
}

// Exercise real worker admission and join for the other connection borrower.
history_explorer_test_settings_turn :: proc(
    t: ^testing.T, fixture: ^History_Explorer_Test_Fixture) {
    testing.expect_value(t, fixture.admission.next_turn,
        protocol.User_Data_Connection_Client.Settings_Save)
    testing.expect(t, !history_runtime_claim(
        &fixture.history, &fixture.admission, true, false))
    testing.expect(t, viewuserdata.connection_admission_claim(
        &fixture.admission, .Settings_Save, true, false))
    handle, submitted := taskpool.task_pool_submit(
        &fixture.pool, history_runtime_test_save_worker, nil, .Worker_Only)
    testing.expect_value(t, submitted, taskpool.Task_Submit_Outcome.Queued)
    testing.expect(t, viewuserdata.connection_admission_mark_submitted(
        &fixture.admission, .Settings_Save))
    _, joined := taskpool.task_pool_wait(&fixture.pool, handle)
    testing.expect_value(t, joined, taskpool.Task_Join_Outcome.Joined)
    testing.expect(t, viewuserdata.connection_admission_release_joined(
        &fixture.admission, .Settings_Save))
}

// Persistent-only source has no session anchor and must copy exactly, never partially.
@(test)
history_explorer_preview_is_scope_qualified_and_capacity_safe :: proc(t: ^testing.T) {
    fixture := history_explorer_test_start(t, true)
    if fixture == nil {
        return
    }
    defer history_explorer_test_destroy(t, fixture)
    testing.expect(t, history_runtime_set_persistence(&fixture.history, true))
    failure := sqlite.connection_exec(&fixture.connection,
        "INSERT INTO main.user_terminal_history "+
        "(entry_id, source, mode, submitted_at_unix_ms, terminal_generation, source_revision) "+
        "VALUES (7, 'saved\n    \u03bb', 3, 100, 8, 5);")
    testing.expect_value(t, failure.validation, sqlite.Validation_Error.None)
    identity := history_explorer_test_query(t, fixture, 1, 1)
    testing.expect_value(t, history_runtime_request_preview(&fixture.history, {
        identity = identity,
        request_id = 1,
        scope = .Persistent,
        source_id = 7,
        source_revision = 5,
    }), historyruntime.History_Runtime_Enqueue_Result.Queued)
    history_runtime_service(
        &fixture.history, &fixture.admission, &fixture.pool, false)
    history_explorer_test_join(t, fixture)
    history_explorer_test_preview_capacity(t, fixture)
}

// A small destination leaves the joined preview available for a full-source retry.
history_explorer_test_preview_capacity :: proc(
    t: ^testing.T, fixture: ^History_Explorer_Test_Fixture) {
    destination: [32]u8
    destination[0] = 'x'
    failed, copied := history_runtime_consume_preview_result(
        &fixture.history, destination[:1])
    testing.expect(t, !copied && failed.ready)
    testing.expect_value(t, failed.result.failure.kind,
        termhiststore.History_Store_Error_Kind.Capacity)
    testing.expect_value(t, destination[0], u8('x'))
    testing.expect(t, fixture.history.preview_completion.ready)
    complete: historyruntime.History_Preview_Completion
    complete, copied = history_runtime_consume_preview_result(
        &fixture.history, destination[:])
    testing.expect(t, copied && complete.ready)
    testing.expect_value(t, complete.result.outcome,
        termhiststore.History_Read_Outcome.Found)
    testing.expect_value(t, complete.result.record.scope,
        termhiststore.History_Record_Scope.Persistent)
    testing.expect_value(t, complete.result.record.submission_id, u64(0))
    testing.expect_value(t, complete.result.record.mode, protocol.Evaluation_Mode.Shell)
    testing.expect_value(t,
        string(destination[:complete.result.source_length]), "saved\n    \u03bb")
}

// A newly selected candidate retires the old in-flight preview, even within one query.
@(test)
history_explorer_preview_rejects_stale_candidate_and_revision :: proc(t: ^testing.T) {
    fixture := history_explorer_test_start(t)
    if fixture == nil {
        return
    }
    defer history_explorer_test_destroy(t, fixture)
    history_explorer_test_insert(t, fixture, 1, "first")
    history_explorer_test_insert(t, fixture, 2, "second")
    identity := history_explorer_test_query(t, fixture, 1, 1)
    request: historyruntime.History_Preview_Request = {
        identity = identity,
        request_id = 1,
        source_id = 1,
        source_revision = 1,
    }
    testing.expect_value(t, history_runtime_request_preview(&fixture.history, request),
        historyruntime.History_Runtime_Enqueue_Result.Queued)
    history_runtime_service(
        &fixture.history, &fixture.admission, &fixture.pool, false)
    request.request_id, request.source_id = 2, 2
    testing.expect_value(t, history_runtime_request_preview(&fixture.history, request),
        historyruntime.History_Runtime_Enqueue_Result.Queued)
    history_explorer_test_join(t, fixture)
    destination: [16]u8
    completion, copied := history_runtime_consume_preview_result(
        &fixture.history, destination[:])
    testing.expect(t, copied)
    testing.expect_value(t, completion.request.source_id, u64(2))
    testing.expect_value(t,
        string(destination[:completion.result.source_length]), "second")
    history_explorer_test_revision_conflict(t, fixture, request)
}

// The worker explicitly reports a changed revision rather than returning newer text.
history_explorer_test_revision_conflict :: proc(
    t: ^testing.T, fixture: ^History_Explorer_Test_Fixture,
    request: historyruntime.History_Preview_Request) {
    stale := request
    stale.request_id = 3
    stale.source_revision = 2
    testing.expect_value(t, history_runtime_request_preview(&fixture.history, stale),
        historyruntime.History_Runtime_Enqueue_Result.Queued)
    history_runtime_service(
        &fixture.history, &fixture.admission, &fixture.pool, false)
    history_explorer_test_join(t, fixture)
    destination: [16]u8
    destination[0] = 'x'
    completion, copied := history_runtime_consume_preview_result(
        &fixture.history, destination[:])
    testing.expect(t, copied && completion.ready)
    testing.expect_value(t, completion.result.outcome,
        termhiststore.History_Read_Outcome.Failed)
    testing.expect_value(t, completion.result.failure.kind,
        termhiststore.History_Store_Error_Kind.Conflict)
    testing.expect_value(t, destination[0], u8('x'))
}

// Pool saturation keeps only the newest queued query and releases rejected claims.
@(test)
history_explorer_pool_pressure_preserves_pending_work :: proc(t: ^testing.T) {
    fixture := history_explorer_test_start(t)
    if fixture == nil {
        return
    }
    defer history_explorer_test_destroy(t, fixture)
    history_explorer_test_insert(t, fixture, 1, "match")
    identity := history_explorer_test_query(t, fixture, 1, 1)
    for id in u64(1)..=10 {
        history_explorer_test_search(t, fixture, identity, id, {
            candidate_budget = 2,
        })
    }
    handles: [3]taskpool.Task_Handle
    for &handle in handles {
        outcome: taskpool.Task_Submit_Outcome
        handle, outcome = taskpool.task_pool_submit(
            &fixture.pool, history_runtime_test_save_worker, nil, .Worker_Only)
        testing.expect_value(t, outcome, taskpool.Task_Submit_Outcome.Queued)
    }
    history_runtime_service(
        &fixture.history, &fixture.admission, &fixture.pool, false)
    testing.expect(t, !fixture.history.task_active)
    testing.expect(t, fixture.history.search_pending)
    testing.expect(t, viewuserdata.connection_admission_is_idle(&fixture.admission))
    for handle in handles {
        _, joined := taskpool.task_pool_wait(&fixture.pool, handle)
        testing.expect_value(t, joined, taskpool.Task_Join_Outcome.Joined)
    }
    history_runtime_service(
        &fixture.history, &fixture.admission, &fixture.pool, false)
    history_explorer_test_join(t, fixture)
    history_explorer_test_search_capacity(t, fixture, identity)
}

// Search copy-out is atomic and retryable when either output budget is insufficient.
history_explorer_test_search_capacity :: proc(
    t: ^testing.T, fixture: ^History_Explorer_Test_Fixture,
    identity: historyruntime.History_Explorer_Identity) {
    rows: [1]termhiststore.History_Candidate_Summary
    summaries: [8]u8
    summaries[0] = 'x'
    failure, copied := history_runtime_consume_search_result(
        &fixture.history, rows[:], summaries[:1])
    testing.expect(t, !copied && failure.ready)
    testing.expect_value(t, failure.result.failure.kind,
        termhiststore.History_Store_Error_Kind.Capacity)
    testing.expect_value(t, summaries[0], u8('x'))
    failure, copied = history_runtime_consume_search_result(
        &fixture.history, nil, summaries[:])
    testing.expect(t, !copied && failure.ready)
    testing.expect_value(t, failure.result.failure.kind,
        termhiststore.History_Store_Error_Kind.Capacity)
    history_explorer_test_expect_search(t, fixture, identity, 10, 1)
}

// Writes win over queued searches; a committed continuation invalidates all candidates.
@(test)
history_explorer_mutations_retire_search_and_preview :: proc(t: ^testing.T) {
    fixture := history_explorer_test_start(t)
    if fixture == nil {
        return
    }
    defer history_explorer_test_destroy(t, fixture)
    history_explorer_test_insert(t, fixture, 1, "before")
    identity := history_explorer_test_query(t, fixture, 1, 1)
    history_explorer_test_search(t, fixture, identity, 1, {
        candidate_budget = 2,
    })
    testing.expect_value(t, history_runtime_request_preview(&fixture.history, {
        identity = identity,
        request_id = 1,
        source_id = 1,
        source_revision = 1,
    }), historyruntime.History_Runtime_Enqueue_Result.Queued)
    testing.expect_value(t, history_runtime_enqueue_update(&fixture.history, {
        submission_id = 1,
        expected_revision = 1,
        new_revision = 2,
        mode = .Help,
        source = "after",
    }), historyruntime.History_Runtime_Enqueue_Result.Queued)
    history_runtime_service(
        &fixture.history, &fixture.admission, &fixture.pool, false)
    testing.expect_value(t, fixture.history.task_kind,
        historyruntime.History_Runtime_Task_Kind.Mutation)
    history_explorer_test_join(t, fixture)
    testing.expect_value(t, fixture.history.last_write_result.outcome,
        termhiststore.History_Write_Outcome.Updated)
    history_explorer_test_expect_retired(t, fixture, identity)
}

// All old tokens fail after invalidation, including reused request IDs.
history_explorer_test_expect_retired :: proc(
    t: ^testing.T, fixture: ^History_Explorer_Test_Fixture,
    identity: historyruntime.History_Explorer_Identity) {
    testing.expect(t, !fixture.history.search_completion.ready)
    testing.expect(t, !fixture.history.preview_completion.ready)
    testing.expect(t, !history_runtime_has_explorer_work(&fixture.history))
    testing.expect(t, !history_runtime_explorer_current(&fixture.history, identity))
    testing.expect_value(t, history_runtime_request_search(&fixture.history, {
        identity = identity,
        request_id = 99,
        scan = {
            candidate_budget = 2,
        },
    }), historyruntime.History_Runtime_Enqueue_Result.Invalid_Request)
}

// Clear failure preserves results; only a committed all-scope clear retires them.
@(test)
history_explorer_clear_invalidation_requires_commit :: proc(t: ^testing.T) {
    fixture := history_explorer_test_start(t, true)
    if fixture == nil {
        return
    }
    defer history_explorer_test_destroy(t, fixture)
    history_explorer_test_insert(t, fixture, 1, "kept")
    identity := history_explorer_test_query(t, fixture, 1, 1)
    history_explorer_test_search(t, fixture, identity, 1, {
        candidate_budget = 2,
    })
    testing.expect_value(t, history_runtime_request_preview(&fixture.history, {
        identity = identity,
        request_id = 1,
        source_id = 1,
        source_revision = 1,
    }), historyruntime.History_Runtime_Enqueue_Result.Queued)
    history_runtime_service(
        &fixture.history, &fixture.admission, &fixture.pool, false)
    history_explorer_test_join(t, fixture)
    failure := sqlite.connection_exec(&fixture.connection,
        "CREATE TEMP TRIGGER reject_explorer_clear BEFORE DELETE ON terminal_history "+
        "BEGIN SELECT RAISE(ABORT, 'injected clear failure'); END;")
    testing.expect_value(t, failure.validation, sqlite.Validation_Error.None)
    testing.expect_value(t, history_runtime_enqueue_clear(&fixture.history),
        historyruntime.History_Runtime_Enqueue_Result.Queued)
    history_runtime_service(
        &fixture.history, &fixture.admission, &fixture.pool, false)
    history_explorer_test_join(t, fixture)
    testing.expect_value(t, fixture.history.last_clear_result.outcome,
        termhiststore.History_Clear_Outcome.Failed)
    testing.expect(t, fixture.history.search_completion.ready)
    testing.expect(t, fixture.history.preview_completion.ready)
    testing.expect(t, history_runtime_explorer_current(&fixture.history, identity))
    history_explorer_test_committed_clear(t, fixture, identity)
}

// Retire both active-query authority and published data after successful deletion.
history_explorer_test_committed_clear :: proc(
    t: ^testing.T, fixture: ^History_Explorer_Test_Fixture,
    identity: historyruntime.History_Explorer_Identity) {
    failure := sqlite.connection_exec(
        &fixture.connection, "DROP TRIGGER temp.reject_explorer_clear;")
    testing.expect_value(t, failure.validation, sqlite.Validation_Error.None)
    testing.expect_value(t, history_runtime_enqueue_clear(&fixture.history),
        historyruntime.History_Runtime_Enqueue_Result.Queued)
    history_runtime_service(
        &fixture.history, &fixture.admission, &fixture.pool, false)
    history_explorer_test_join(t, fixture)
    testing.expect_value(t, fixture.history.last_clear_result.outcome,
        termhiststore.History_Clear_Outcome.Cleared)
    history_explorer_test_expect_retired(t, fixture, identity)
}

// Preference changes retire active work; a new query captures the new scope policy.
@(test)
history_explorer_visibility_and_generation_retire_active_work :: proc(t: ^testing.T) {
    fixture := history_explorer_test_start(t, true)
    if fixture == nil {
        return
    }
    defer history_explorer_test_destroy(t, fixture)
    history_explorer_test_insert(t, fixture, 1, "session")
    identity := history_explorer_test_query(t, fixture, 1, 1)
    history_explorer_test_search(t, fixture, identity, 1, {
        candidate_budget = 2,
    })
    history_runtime_service(
        &fixture.history, &fixture.admission, &fixture.pool, false)
    testing.expect(t, history_runtime_set_persistence(&fixture.history, true))
    history_explorer_test_join(t, fixture)
    history_explorer_test_expect_retired(t, fixture, identity)
    identity = history_explorer_test_query(t, fixture, 1, 1)
    history_explorer_test_search(t, fixture, identity, 1, {
        candidate_budget = 2,
    })
    testing.expect(t, fixture.history.queued_search.scan.include_persistent)
    history_runtime_service(
        &fixture.history, &fixture.admission, &fixture.pool, false)
    history_runtime_attach_generation(&fixture.history, 2)
    history_explorer_test_join(t, fixture)
    history_explorer_test_expect_retired(t, fixture, identity)
}

// Shutdown joins an in-flight preview but cannot publish it or admit another query.
@(test)
history_explorer_shutdown_joins_and_retires_preview :: proc(t: ^testing.T) {
    fixture := history_explorer_test_start(t)
    if fixture == nil {
        return
    }
    defer history_explorer_test_destroy(t, fixture)
    history_explorer_test_insert(t, fixture, 1, "retained")
    identity := history_explorer_test_query(t, fixture, 1, 1)
    testing.expect_value(t, history_runtime_request_preview(&fixture.history, {
        identity = identity,
        request_id = 1,
        source_id = 1,
        source_revision = 1,
    }), historyruntime.History_Runtime_Enqueue_Result.Queued)
    history_runtime_service(
        &fixture.history, &fixture.admission, &fixture.pool, false)
    history_runtime_begin_shutdown(&fixture.history)
    testing.expect_value(t, history_runtime_request_preview(&fixture.history, {
        identity = identity,
        request_id = 2,
        source_id = 1,
        source_revision = 1,
    }), historyruntime.History_Runtime_Enqueue_Result.Shutting_Down)
    history_explorer_test_join(t, fixture)
    testing.expect(t, !fixture.history.preview_completion.ready)
    testing.expect(t, history_runtime_test_shutdown(
        t, &fixture.history, &fixture.admission, &fixture.pool))
    testing.expect(t, !fixture.history.store.initialized)
}

// Store errors become explicit joined failures, not empty candidate success.
@(test)
history_explorer_reports_worker_failures :: proc(t: ^testing.T) {
    fixture := history_explorer_test_start(t)
    if fixture == nil {
        return
    }
    defer history_explorer_test_destroy(t, fixture)
    identity := history_explorer_test_query(t, fixture, 1, 1)
    failure := sqlite.connection_exec(
        &fixture.connection, "DROP TABLE temp.terminal_history;")
    testing.expect_value(t, failure.validation, sqlite.Validation_Error.None)
    history_explorer_test_search(t, fixture, identity, 1, {
        candidate_budget = 2,
    })
    history_runtime_service(
        &fixture.history, &fixture.admission, &fixture.pool, false)
    history_explorer_test_join(t, fixture)
    completion, copied := history_runtime_consume_search_result(
        &fixture.history, nil, nil)
    testing.expect(t, copied && completion.ready)
    testing.expect_value(t, completion.result.outcome,
        termhiststore.History_Search_Outcome.Failed)
    testing.expect_value(t, completion.result.failure.kind,
        termhiststore.History_Store_Error_Kind.Sqlite)
    testing.expect_value(t, fixture.history.status,
        historyruntime.History_Runtime_Status.Ready)
}

// Navigation, preview, and search results can coexist without blocking or aliasing.
@(test)
history_explorer_uses_independent_completion_mailboxes :: proc(t: ^testing.T) {
    fixture := history_explorer_test_start(t)
    if fixture == nil {
        return
    }
    defer history_explorer_test_destroy(t, fixture)
    history_explorer_test_insert(t, fixture, 1, "original")
    identity := history_explorer_test_query(t, fixture, 1, 1)
    testing.expect(t, history_runtime_request_read(&fixture.history, {
        kind = .By_Id,
        request_id = 1,
        submission_id = 1,
        terminal_generation = 1,
    }))
    history_explorer_test_search(t, fixture, identity, 1, {
        candidate_budget = 2,
    })
    testing.expect_value(t, history_runtime_request_preview(&fixture.history, {
        identity = identity,
        request_id = 1,
        source_id = 1,
        source_revision = 1,
    }), historyruntime.History_Runtime_Enqueue_Result.Queued)
    history_runtime_service(
        &fixture.history, &fixture.admission, &fixture.pool, false)
    testing.expect_value(t, fixture.history.task_kind,
        historyruntime.History_Runtime_Task_Kind.Read)
    history_explorer_test_join(t, fixture)
    testing.expect(t, fixture.history.read_result_ready)
    testing.expect(t, fixture.history.search_completion.ready)
    testing.expect(t, fixture.history.preview_completion.ready)
    history_explorer_test_consume_mailboxes(t, fixture, identity)
}

// Each output retains its own original bytes despite the other two operations.
history_explorer_test_consume_mailboxes :: proc(
    t: ^testing.T, fixture: ^History_Explorer_Test_Fixture,
    identity: historyruntime.History_Explorer_Identity) {
    destination: [16]u8
    preview, copied := history_runtime_consume_preview_result(
        &fixture.history, destination[:])
    testing.expect(t, copied)
    testing.expect_value(t,
        string(destination[:preview.result.source_length]), "original")
    history_explorer_test_expect_search(t, fixture, identity, 1, 1)
    navigation: historyruntime.History_Read_Completion
    navigation, copied = history_runtime_consume_read_result(
        &fixture.history, destination[:])
    testing.expect(t, copied)
    testing.expect_value(t, navigation.request.target,
        historyruntime.History_Read_Target.Navigation)
    testing.expect_value(t,
        string(destination[:navigation.result.source_length]), "original")
}

// Explorer admission is independent of a saturated speculative highlighting queue.
@(test)
history_explorer_does_not_queue_behind_highlighting :: proc(t: ^testing.T) {
    fixture := history_explorer_test_start(t)
    if fixture == nil {
        return
    }
    defer history_explorer_test_destroy(t, fixture)
    history_explorer_test_insert(t, fixture, 1, "source")
    for id in u64(1)..=u64(historyruntime.HISTORY_RUNTIME_READ_CAPACITY) {
        testing.expect(t, history_runtime_request_read(&fixture.history, {
            kind = .By_Id,
            priority = .Speculative,
            target = .Highlighting,
            request_id = id,
            submission_id = 1,
            terminal_generation = 1,
        }))
    }
    identity := history_explorer_test_query(t, fixture, 1, 1)
    history_explorer_test_search(t, fixture, identity, 1, {
        candidate_budget = 2,
    })
    history_runtime_service(
        &fixture.history, &fixture.admission, &fixture.pool, false)
    testing.expect_value(t, fixture.history.task_kind,
        historyruntime.History_Runtime_Task_Kind.Search)
    history_explorer_test_join(t, fixture)
    history_explorer_test_expect_search(t, fixture, identity, 1, 1)
    testing.expect(t, fixture.history.read_result_ready)
    testing.expect_value(t, fixture.history.read_result_request.target,
        historyruntime.History_Read_Target.Highlighting)
}

// Closing and reopening with repeated caller IDs cannot resurrect an active reply.
@(test)
history_explorer_close_reopen_does_not_alias_old_work :: proc(t: ^testing.T) {
    fixture := history_explorer_test_start(t)
    if fixture == nil {
        return
    }
    defer history_explorer_test_destroy(t, fixture)
    history_explorer_test_insert(t, fixture, 1, "source")
    old := history_explorer_test_query(t, fixture, 1, 1)
    history_explorer_test_search(t, fixture, old, 1, {
        candidate_budget = 2,
    })
    history_runtime_service(
        &fixture.history, &fixture.admission, &fixture.pool, false)
    history_runtime_retire_explorer(&fixture.history)
    current := history_explorer_test_query(t, fixture, 1, 1)
    testing.expect(t, current.runtime_epoch != old.runtime_epoch)
    history_explorer_test_join(t, fixture)
    testing.expect(t, !fixture.history.search_completion.ready)
    history_explorer_test_search(t, fixture, current, 1, {
        candidate_budget = 2,
    })
    history_runtime_service(
        &fixture.history, &fixture.admission, &fixture.pool, false)
    history_explorer_test_join(t, fixture)
    history_explorer_test_expect_search(t, fixture, current, 1, 1)
}

// Query byte bounds and unavailable/stale scopes fail explicitly before admission.
@(test)
history_explorer_validates_request_admission :: proc(t: ^testing.T) {
    fixture := history_explorer_test_start(t)
    if fixture == nil {
        return
    }
    defer history_explorer_test_destroy(t, fixture)
    identity := history_explorer_test_query(t, fixture, 1, 1)
    query: [termhiststore.HISTORY_SEARCH_QUERY_MAX_BYTES + 1]u8
    testing.expect_value(t, history_runtime_request_search(&fixture.history, {
        identity = identity,
        request_id = 1,
        scan = {
            query = string(query[:]),
            candidate_budget = 2,
        },
    }), historyruntime.History_Runtime_Enqueue_Result.Source_Too_Large)
    testing.expect_value(t, history_runtime_request_preview(&fixture.history, {
        identity = identity,
        request_id = 1,
        scope = .Persistent,
        source_id = 1,
        source_revision = 1,
    }), historyruntime.History_Runtime_Enqueue_Result.Not_Ready)
    testing.expect_value(t, history_runtime_request_preview(&fixture.history, {
        identity = identity,
        request_id = 1,
        source_revision = 1,
    }), historyruntime.History_Runtime_Enqueue_Result.Invalid_Request)
    history_runtime_retire_reads(&fixture.history)
    testing.expect_value(t, history_runtime_request_search(&fixture.history, {
        identity = identity,
        request_id = 1,
    }), historyruntime.History_Runtime_Enqueue_Result.Shutting_Down)
}

// Exact transport capacities bound output, not how far callers can search.
@(test)
history_explorer_bounds_output_without_capping_search_scope :: proc(t: ^testing.T) {
    fixture := history_explorer_test_start(t)
    if fixture == nil {
        return
    }
    defer history_explorer_test_destroy(t, fixture)
    source: [termhiststore.HISTORY_SEARCH_SUMMARY_MAX_BYTES + 8]u8
    for &byte in source {
        byte = 'x'
    }
    copy(source[len(source) - 4:], "tail")
    for id in u64(1)..=u64(historyruntime.HISTORY_RUNTIME_SEARCH_ROW_CAPACITY + 1) {
        history_explorer_test_insert(t, fixture, id, string(source[:]))
    }
    identity := history_explorer_test_query(t, fixture, 1, 1)
    cursor := history_explorer_test_full_batch(t, fixture, identity)
    history_explorer_test_search(t, fixture, identity, 2, {
        query = "tail",
        cursor = cursor,
        cursor_valid = true,
        candidate_budget = termhiststore.HISTORY_SEARCH_CANDIDATE_MAX,
    })
    history_runtime_service(
        &fixture.history, &fixture.admission, &fixture.pool, false)
    history_explorer_test_join(t, fixture)
    history_explorer_test_expect_search(t, fixture, identity, 2, 1)
    history_explorer_test_full_preview(t, fixture, identity, source[:])
}

// A batch fills both the row and packed-byte limits without consuming the next match.
history_explorer_test_full_batch :: proc(
    t: ^testing.T, fixture: ^History_Explorer_Test_Fixture,
    identity: historyruntime.History_Explorer_Identity) ->
        termhiststore.History_Browse_Cursor {
    history_explorer_test_search(t, fixture, identity, 1, {
        query = "tail",
        candidate_budget = termhiststore.HISTORY_SEARCH_CANDIDATE_MAX,
    })
    history_runtime_service(
        &fixture.history, &fixture.admission, &fixture.pool, false)
    history_explorer_test_join(t, fixture)
    ROW_CAP :: historyruntime.HISTORY_RUNTIME_SEARCH_ROW_CAPACITY
    rows: [ROW_CAP]termhiststore.History_Candidate_Summary
    summaries: [historyruntime.HISTORY_RUNTIME_SEARCH_SUMMARY_BYTES]u8
    completion, copied := history_runtime_consume_search_result(
        &fixture.history, rows[:], summaries[:])
    testing.expect(t, copied)
    testing.expect_value(t, completion.result.row_count, len(rows))
    testing.expect_value(t, completion.result.examined_count, len(rows))
    testing.expect_value(t, completion.result.summary_bytes, len(summaries))
    testing.expect(t, completion.result.output_full && !completion.result.exhausted)
    testing.expect(t, rows[0].summary_clipped)
    testing.expect_value(t, completion.result.cursor.source_id, u64(2))
    return completion.result.cursor
}

// Full preview must include source beyond the summary and match the original exactly.
history_explorer_test_full_preview :: proc(
    t: ^testing.T, fixture: ^History_Explorer_Test_Fixture,
    identity: historyruntime.History_Explorer_Identity, source: []u8) {
    testing.expect_value(t, history_runtime_request_preview(&fixture.history, {
        identity = identity,
        request_id = 1,
        source_id = 1,
        source_revision = 1,
    }), historyruntime.History_Runtime_Enqueue_Result.Queued)
    history_runtime_service(
        &fixture.history, &fixture.admission, &fixture.pool, false)
    history_explorer_test_join(t, fixture)
    destination: [termhiststore.HISTORY_SEARCH_SUMMARY_MAX_BYTES + 8]u8
    completion, copied := history_runtime_consume_preview_result(
        &fixture.history, destination[:])
    testing.expect(t, copied)
    testing.expect_value(t, completion.result.source_length, len(source))
    testing.expect_value(t, string(destination[:]), string(source))
}

#+test
package termhiststore

import sqlite "../../../sqlite"
import termhistsearch "../search"
import protocol "../../../core/protocol"
import pcre2 "../../../pcre2"
import "core:c"
import "core:testing"

// SQL uses the complete native grammar and admits invalid-only queries as browsing.
@(test)
history_search_sql_native_conditions :: proc(t: ^testing.T) {
    connection: sqlite.Connection
    store: History_Store
    if !history_store_test_open_memory(t, &connection, &store) {
        return
    }
    defer _ = sqlite.connection_close(&connection)
    defer _ = history_store_destroy(&store)
    sources := [?]string{"foo_bar λaa", "FOO BAR", "fooBar", "keep this"}
    for source, index in sources {
        mode := protocol.Evaluation_Mode.Shell if index == 0 else .Normal
        testing.expect_value(t, history_store_insert(&store,
            history_store_test_record(u64(index + 1), mode, 100, 1, 1), source).outcome,
            History_Write_Outcome.Stored)
    }
    cases := [?]struct {query: string, ids: []u64}{
        {"foo bar", []u64{3, 2, 1}}, {"foo BAR", nil},
        {"foo; BAR", []u64{2}}, {"=foo;!λ", []u64{3}},
        {"/(?<=\\p{Greek})(a)\\1", []u64{1}},
        {"`fb", []u64{3, 2, 1}}, {"~fb", []u64{3, 1}},
        {"shell>;help>", []u64{1}}, {"unknown>", nil},
        {"/[", []u64{4, 3, 2, 1}}, {"foo;/[", []u64{3, 2, 1}},
    }
    for item in cases {
        history_search_test_query(t, &store, item.query, item.ids, false)
        history_search_test_query(t, &store, item.query, item.ids, true)
    }
}

// Admitted resources survive pages, repeated callbacks, and positive-range extraction.
@(test)
history_search_sql_retains_compilation :: proc(t: ^testing.T) {
    connection: sqlite.Connection
    store: History_Store
    if !history_store_test_open_memory(t, &connection, &store) {
        return
    }
    defer _ = sqlite.connection_close(&connection)
    defer _ = history_store_destroy(&store)
    for id in u64(1)..=3 {
        testing.expect_value(t, history_store_insert(&store,
            history_store_test_record(id, .Normal, 100, 1, 1), "alpha").outcome,
            History_Write_Outcome.Stored)
    }
    history_search_test_retained_pages(t, &store)
}

// Page boundaries and ranges borrow the same immutable code and reusable workspace.
history_search_test_retained_pages :: proc(t: ^testing.T, store: ^History_Store) {
    request: History_Search_Request = {
        query = "/a",
        search_identity = 9,
        result_limit = 1,
    }
    rows: [1]History_Candidate_Summary
    bytes: [16]u8
    for id := u64(3); id > 0; id -= 1 {
        result := history_store_search(store, request, rows[:], bytes[:])
        testing.expect_value(t, result.outcome, History_Search_Outcome.Complete)
        testing.expect_value(t, rows[0].record.source_id, id)
        testing.expect_value(t, result.exhausted, id == 1)
        testing.expect_value(t, store.search.compile_count, u64(1))
        request.cursor, request.cursor_valid = result.cursor, result.cursor_valid
        ranges: [2]termhistsearch.Search_Range
        matched := termhistsearch.history_search_match_ranges(
            &store.search.plan, &store.search.workspace, "alpha", ranges[:])
        testing.expect_value(t, matched.count, 2)
    }
    request.query = "/b"
    rejected := history_store_search(store, request, rows[:], bytes[:])
    testing.expect_value(t,
        rejected.failure.kind, History_Store_Error_Kind.Invalid_Argument)
    request.search_identity = 10
    accepted := history_store_search(store, request, rows[:], bytes[:])
    testing.expect_value(t, accepted.outcome, History_Search_Outcome.Complete)
    testing.expect_value(t, store.search.compile_count, u64(2))
}

// SQLite and PCRE2 share a cancellation token; reset restores ordinary execution.
@(test)
history_search_sql_cancellation_and_reset :: proc(t: ^testing.T) {
    connection: sqlite.Connection
    store: History_Store
    if !history_store_test_open_memory(t, &connection, &store) {
        return
    }
    defer _ = sqlite.connection_close(&connection)
    defer _ = history_store_destroy(&store)
    request: History_Search_Request = {
        query = "/a",
        result_limit = 1,
    }
    rows: [1]History_Candidate_Summary
    history_store_cancel_search(&store)
    result := history_store_search(&store, request, rows[:], nil)
    testing.expect_value(t, result.failure.kind, History_Store_Error_Kind.Cancelled)
    testing.expect(t, store.search_adapter.active == nil)
    history_store_reset_search_cancel(&store)
    result = history_store_search(&store, request, rows[:], nil)
    testing.expect_value(t, result.outcome, History_Search_Outcome.Complete)
    testing.expect(t, result.exhausted)
}

// A callback cannot execute without a checked active identity and strict value types.
@(test)
history_search_sql_rejects_invalid_callbacks :: proc(t: ^testing.T) {
    connection: sqlite.Connection
    store: History_Store
    if !history_store_test_open_memory(t, &connection, &store) {
        return
    }
    defer _ = sqlite.connection_close(&connection)
    defer _ = history_store_destroy(&store)
    history_search_test_callback_rejected(t, &connection,
        "SELECT history_matches('source', 0, 1);")
    request: History_Search_Request = {
        query = "source",
        search_identity = 7,
    }
    testing.expect_value(t, history_store_admit_search(&store, request).kind,
        History_Store_Error_Kind.None)
    testing.expect_value(t, history_store_begin_search_execution(&store).kind,
        History_Store_Error_Kind.None)
    defer _ = history_store_end_search_execution(&store)
    cases := [?]string{
        "SELECT history_matches('source', 0, 8);",
        "SELECT history_matches('source', 99, 7);",
        "SELECT history_matches('source', '0', 7);",
        "SELECT history_matches(X'00', 0, 7);",
        "SELECT history_matches(NULL, 0, 7);",
        "SELECT history_matches('source', 0, NULL);",
        "SELECT history_matches('source', 0);",
    }
    for sql in cases {
        history_search_test_callback_rejected(t, &connection, sql)
    }
}

// Every rejected callback surfaces an SQLite error rather than a false predicate.
history_search_test_callback_rejected :: proc(
    t: ^testing.T, connection: ^sqlite.Connection, sql: string) {
    statement: sqlite.Statement
    failure := sqlite.statement_prepare_text(connection, &statement, sql)
    if !history_store_sqlite_error_is_clear(failure) {
        return
    }
    defer _ = sqlite.statement_finalize(&statement)
    status, step_error := sqlite.statement_step(&statement)
    testing.expect_value(t, status, sqlite.Step_Status.Failed)
    testing.expect(t, !history_store_sqlite_error_is_clear(step_error))
}

// Failure after an earlier matching row publishes no partial page and permits reset/reuse.
@(test)
history_search_sql_discards_partial_page :: proc(t: ^testing.T) {
    connection: sqlite.Connection
    store: History_Store
    if !history_store_test_open_memory(t, &connection, &store) {
        return
    }
    defer _ = sqlite.connection_close(&connection)
    defer _ = history_store_destroy(&store)
    for id in u64(1)..=2 {
        testing.expect_value(t, history_store_insert(&store,
            history_store_test_record(id, .Normal, 100, 1, 1), "source").outcome,
            History_Write_Outcome.Stored)
    }
    testing.expect(t, history_store_test_exec(&connection,
        "UPDATE temp.terminal_history SET mode=99 WHERE submission_id=1;"))
    request: History_Search_Request = {
        query = "/source",
        result_limit = 2,
    }
    rows: [2]History_Candidate_Summary
    bytes: [32]u8
    result := history_store_search(&store, request, rows[:], bytes[:])
    testing.expect_value(t, result.outcome, History_Search_Outcome.Failed)
    testing.expect_value(t, result.row_count, 0)
    testing.expect_value(t, result.summary_bytes, 0)
    testing.expect(t, store.search_adapter.active == nil)
    testing.expect(t, connection.progress.callback == nil)
    testing.expect(t, history_store_test_exec(&connection,
        "UPDATE temp.terminal_history SET mode=0 WHERE submission_id=1;"))
    result = history_store_search(&store, request, rows[:], bytes[:])
    testing.expect_value(t, result.row_count, 2)
    testing.expect_value(t, store.search.compile_count, u64(1))
}

// A prior progress owner remains active during search and is restored on failure.
@(test)
history_search_sql_preserves_progress_owner :: proc(t: ^testing.T) {
    connection: sqlite.Connection
    store: History_Store
    if !history_store_test_open_memory(t, &connection, &store) {
        return
    }
    defer _ = sqlite.connection_close(&connection)
    defer _ = history_store_destroy(&store)
    calls: int
    previous: sqlite.Progress_Handler = {
        instructions = 1,
        callback = history_search_test_progress,
        user_data = &calls,
    }
    testing.expect(t, history_store_sqlite_error_is_clear(
        sqlite.connection_set_progress(&connection, previous)))
    rows: [1]History_Candidate_Summary
    result := history_store_search(&store, {
        query = "/a",
        result_limit = 1,
    }, rows[:], nil)
    testing.expect_value(t, result.outcome, History_Search_Outcome.Failed)
    testing.expect(t, calls > 0)
    testing.expect_value(t, connection.progress, previous)
    testing.expect(t, history_store_sqlite_error_is_clear(
        sqlite.connection_set_progress(&connection, {})))
}

// Interrupt a statement from the fixture's previously installed progress handler.
history_search_test_progress :: proc "c" (user_data: rawptr) -> c.int {
    calls := cast(^int)user_data
    calls^ += 1
    return 1
}

// Cancellation requested by the prior owner is observed by the SQL progress scope.
@(test)
history_search_sql_progress_observes_cancellation :: proc(t: ^testing.T) {
    connection: sqlite.Connection
    store: History_Store
    if !history_store_test_open_memory(t, &connection, &store) {
        return
    }
    defer _ = sqlite.connection_close(&connection)
    defer _ = history_store_destroy(&store)
    previous: sqlite.Progress_Handler = {
        instructions = 1,
        callback = history_search_test_cancel_progress,
        user_data = &store,
    }
    testing.expect(t, history_store_sqlite_error_is_clear(
        sqlite.connection_set_progress(&connection, previous)))
    rows: [1]History_Candidate_Summary
    result := history_store_search(&store, {
        result_limit = 1,
    }, rows[:], nil)
    testing.expect_value(t, result.failure.kind, History_Store_Error_Kind.Cancelled)
    testing.expect_value(t, result.row_count, 0)
    testing.expect_value(t, result.summary_bytes, 0)
    testing.expect_value(t, connection.progress, previous)
    testing.expect(t, store.search_adapter.active == nil)
    testing.expect(t, history_store_sqlite_error_is_clear(
        sqlite.connection_set_progress(&connection, {})))
}

// Request token cancellation without interrupting directly or entering the regex engine.
history_search_test_cancel_progress :: proc "c" (user_data: rawptr) -> c.int {
    store := cast(^History_Store)user_data
    context = store.search_adapter.saved_context
    history_store_cancel_search(store)
    return 0
}

// A malformed generated/admission input is retained as failure, not retried per page.
@(test)
history_search_sql_retains_failed_admission :: proc(t: ^testing.T) {
    connection: sqlite.Connection
    store: History_Store
    if !history_store_test_open_memory(t, &connection, &store) {
        return
    }
    defer _ = sqlite.connection_close(&connection)
    defer _ = history_store_destroy(&store)
    invalid := [?]u8{0xFF}
    request: History_Search_Request = {
        query = string(invalid[:]),
        search_identity = 13,
        result_limit = 1,
    }
    rows: [1]History_Candidate_Summary
    for _ in 0..<3 {
        result := history_store_search(&store, request, rows[:], nil)
        testing.expect_value(t, result.failure.kind, History_Store_Error_Kind.Search)
        testing.expect_value(t, result.failure.search_error,
            termhistsearch.Search_Error.Invalid_Query)
        testing.expect_value(t, store.search.compile_count, u64(1))
    }
    testing.expect(t, store.search_adapter.active == nil)
    testing.expect(t, connection.progress.callback == nil)
}

// PCRE2 execution limits remain typed search failures through SQLite and reset.
@(test)
history_search_sql_retains_match_limit_cause :: proc(t: ^testing.T) {
    connection: sqlite.Connection
    store: History_Store
    if !history_store_test_open_memory(t, &connection, &store) {
        return
    }
    defer _ = sqlite.connection_close(&connection)
    defer _ = history_store_destroy(&store)
    testing.expect_value(t, history_store_insert(&store,
        history_store_test_record(1, .Normal, 100, 1, 1),
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa!").outcome, History_Write_Outcome.Stored)
    request: History_Search_Request = {
        query = "/(a+)+$",
        search_identity = 1,
        result_limit = 1,
    }
    rows: [1]History_Candidate_Summary
    result := history_store_search(&store, request, rows[:], nil)
    testing.expect_value(t, result.failure.kind, History_Store_Error_Kind.Search)
    testing.expect_value(t, result.failure.search_error,
        termhistsearch.Search_Error.Match_Engine)
    testing.expect(t, result.failure.engine_error != 0)
    testing.expect_value(t, result.row_count, 0)
    request.query = "=!"
    request.search_identity = 2
    bytes: [64]u8
    result = history_store_search(&store, request, rows[:], bytes[:])
    testing.expect_value(t, result.outcome, History_Search_Outcome.Complete)
    testing.expect_value(t, result.row_count, 1)
}

// A cancelled PCRE2 callback reports interruption even without a SQL progress callback.
@(test)
history_search_sql_callback_observes_native_cancel :: proc(t: ^testing.T) {
    connection: sqlite.Connection
    store: History_Store
    if !history_store_test_open_memory(t, &connection, &store) {
        return
    }
    defer _ = sqlite.connection_close(&connection)
    defer _ = history_store_destroy(&store)
    testing.expect_value(t, history_store_admit_search(&store, {
        query = "/source",
        search_identity = 7,
    }).kind, History_Store_Error_Kind.None)
    testing.expect_value(t, history_store_begin_search_execution(&store).kind,
        History_Store_Error_Kind.None)
    defer _ = history_store_end_search_execution(&store)
    testing.expect(t, history_store_sqlite_error_is_clear(
        sqlite.connection_set_progress(&connection, {})))
    pcre2.cancel_token_request(&store.search_cancel)
    history_search_test_callback_rejected(t, &connection,
        "SELECT history_matches('source', 0, 7);")
    testing.expect_value(t, store.search_adapter.failure.kind,
        History_Store_Error_Kind.Cancelled)
    testing.expect_value(t, store.search_adapter.failure.search_error,
        termhistsearch.Search_Error.Cancelled)
}

// Linked saved rows stay suppressed even when their session representation does not match.
@(test)
history_search_sql_suppresses_overlap_before_matching :: proc(t: ^testing.T) {
    connection: sqlite.Connection
    store: History_Store
    if !history_store_test_open_memory(t, &connection, &store) {
        return
    }
    defer _ = sqlite.connection_close(&connection)
    defer _ = history_store_destroy(&store)
    testing.expect_value(t, history_store_insert_persistent(&store,
        history_store_test_record(1, .Normal, 100, 1, 1), "needle").outcome,
        History_Write_Outcome.Stored)
    testing.expect(t, history_store_test_exec(&connection,
        "UPDATE temp.terminal_history SET source='miss' WHERE submission_id=1;"))
    history_search_test_query(t, &store, "needle", nil, true)
}

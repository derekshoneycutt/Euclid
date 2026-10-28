#+test
package termhiststore

import protocol "../../../core/protocol"
import sqlite "../../../sqlite"

import "core:testing"

// Literal predicates must not interpret punctuation, SQL, whitespace, or case.
@(test)
history_search_matches_literal_source :: proc(t: ^testing.T) {
    connection: sqlite.Connection
    store: History_Store
    if !history_store_test_open_memory(t, &connection, &store) {
        return
    }
    defer _ = sqlite.connection_close(&connection)
    defer _ = history_store_destroy(&store)
    sources := [?]string{
        "plot %_ ? ~foo /foo mode> ' OR 1=1 --",
        "Plot",
        "alpha beta\n    \u03bb = \u03b1 + 1",
        "plot %_ ? ~foo /foo mode> ' OR 1=1 --",
        "alpha  beta",
        "",
    }
    for source, index in sources {
        record := history_store_test_record(u64(index + 1), .Normal, 100, 1, 1)
        testing.expect_value(t, history_store_insert(&store, record, source).outcome,
            History_Write_Outcome.Stored)
    }
    history_search_test_literals(t, &store)
}

// Exercise the exact query language and retain distinct repeated submissions.
history_search_test_literals :: proc(t: ^testing.T, store: ^History_Store) {
    cases := [?]struct {query: string, ids: []u64}{
        {"", []u64{6, 5, 4, 3, 2, 1}},
        {"plot", []u64{4, 1}}, {"Plot", []u64{2}}, {"PLOT", nil},
        {"%", []u64{4, 1}}, {"_", []u64{4, 1}}, {"?", []u64{4, 1}},
        {"~foo", []u64{4, 1}}, {"/foo", []u64{4, 1}},
        {"mode>", []u64{4, 1}}, {"' OR 1=1 --", []u64{4, 1}},
        {"alpha beta", []u64{3}}, {"alpha  beta", []u64{5}},
        {"beta\n    \u03bb", []u64{3}}, {"\u03bb", []u64{3}},
        {"\u039b", nil}, {"\\n", nil},
    }
    for item in cases {
        visibility := [?]bool{false, true}
        for combined in visibility {
            history_search_test_literal(t, store, item.query, item.ids, combined)
        }
    }
}

// Inspect literal output in both visibility modes without using failed result bytes.
history_search_test_literal :: proc(
    t: ^testing.T, store: ^History_Store,
    query: string, ids: []u64, combined: bool) {
    request: History_Search_Request = {
        query = query,
        include_persistent = combined,
        candidate_budget = HISTORY_SEARCH_CANDIDATE_MAX,
    }
    rows: [8]History_Candidate_Summary
    summaries: [512]u8
    result := history_store_search(store, request, rows[:], summaries[:])
    testing.expect_value(t, result.failure.kind, History_Store_Error_Kind.None)
    testing.expect_value(t, result.outcome, History_Search_Outcome.Scanned)
    if result.outcome != .Scanned {
        return
    }
    testing.expect(t, result.exhausted)
    testing.expect_value(t, result.examined_count, 6)
    testing.expect_value(t, result.row_count, len(ids))
    for id, index in ids {
        testing.expect_value(t, rows[index].record.submission_id, id)
        history_search_test_exact_summary(t, store, rows[index], summaries[:])
    }
}

// The copied summary and scope-qualified exact read must agree for short source.
history_search_test_exact_summary :: proc(
    t: ^testing.T, store: ^History_Store,
    row: History_Candidate_Summary, summaries: []u8) {
    source: [512]u8
    read: History_Read_Result
    if row.record.scope == .Session {
        read = history_store_get_by_id(store, row.record.source_id, source[:])
    } else {
        read = history_store_get_persistent_by_id(store, row.record.source_id, source[:])
    }
    testing.expect_value(t, read.outcome, History_Read_Outcome.Found)
    testing.expect_value(t, row.record, read.record)
    testing.expect_value(t, row.source_length, read.source_length)
    testing.expect(t, !row.summary_clipped)
    testing.expect_value(t,
        string(summaries[row.summary_offset:row.summary_offset + row.summary_length]),
        string(source[:read.source_length]))
}

// Zero-match windows must advance through all examined candidates to a rare match.
@(test)
history_search_continues_after_empty_windows :: proc(t: ^testing.T) {
    connection: sqlite.Connection
    store: History_Store
    if !history_store_test_open_memory(t, &connection, &store) {
        return
    }
    defer _ = sqlite.connection_close(&connection)
    defer _ = history_store_destroy(&store)
    for id in u64(1)..=7 {
        source := "needle" if id == 1 else "miss"
        testing.expect_value(t, history_store_insert(
            &store, history_store_test_record(id, .Normal, 100, 1, 1), source).outcome,
            History_Write_Outcome.Stored)
    }
    visibility := [?]bool{false, true}
    for combined in visibility {
        history_search_test_sparse_direction(t, &store, combined, .Older, "needle")
        history_search_test_sparse_direction(t, &store, combined, .Newer, "absent")
    }
}

// Continue with returned scan positions rather than using the last matching row.
history_search_test_sparse_direction :: proc(
    t: ^testing.T, store: ^History_Store, combined: bool,
    direction: History_Search_Direction, query: string) {
    request: History_Search_Request = {
        query = query,
        direction = direction,
        include_persistent = combined,
        candidate_budget = 2,
    }
    rows: [2]History_Candidate_Summary
    summaries: [32]u8
    for window in 0..<4 {
        result := history_store_search(store, request, rows[:], summaries[:])
        testing.expect_value(t, result.outcome, History_Search_Outcome.Scanned)
        testing.expect_value(t, result.examined_count, 1 if window == 3 else 2)
        testing.expect_value(t, result.exhausted, window == 3)
        expected_id := u64(max(1, 6 - window * 2)) if direction == .Older else
            u64(min(7, 2 + window * 2))
        testing.expect(t, result.cursor_valid)
        testing.expect_value(t, result.cursor.source_id, expected_id)
        testing.expect_value(t, result.row_count,
            1 if direction == .Older && window == 3 else 0)
        request.cursor = result.cursor
        request.cursor_valid = result.cursor_valid
    }
}

// Both directions preserve tie order, linked overlap, and session-only visibility.
@(test)
history_search_preserves_logical_chronology :: proc(t: ^testing.T) {
    connection: sqlite.Connection
    store: History_Store
    if !history_store_test_open_memory(t, &connection, &store) {
        return
    }
    defer _ = sqlite.connection_close(&connection)
    defer _ = history_store_destroy(&store)
    testing.expect_value(t, history_store_insert_persistent(
        &store, history_store_test_record(10, .Shell, 100, 4, 2), "repeat").outcome,
        History_Write_Outcome.Stored)
    testing.expect(t, history_store_test_exec(&connection,
        "INSERT INTO main.user_terminal_history "+
        "(source, mode, submitted_at_unix_ms, terminal_generation, source_revision) "+
        "VALUES ('repeat', 1, 100, 2, 3), ('repeat', 2, 100, 3, 4);"))
    testing.expect_value(t, history_store_insert(
        &store, history_store_test_record(20, .Help, 100, 5, 6), "repeat").outcome,
        History_Write_Outcome.Stored)
    testing.expect_value(t, history_store_insert(
        &store, history_store_test_record(30, .Normal, 80, 7, 8), "repeat").outcome,
        History_Write_Outcome.Stored)
    visibility := [?]bool{false, true}
    for combined in visibility {
        history_search_test_order(t, &store, combined, .Older)
        history_search_test_order(t, &store, combined, .Newer)
    }
}

// One-row destinations exercise cursor resumption across every scope tie-breaker.
history_search_test_order :: proc(
    t: ^testing.T, store: ^History_Store,
    combined: bool, direction: History_Search_Direction) {
    combined_ids := [?]u64{20, 10, 3, 2, 30}
    combined_scopes := [?]History_Record_Scope{
        .Session, .Session, .Persistent, .Persistent, .Session,
    }
    session_ids := [?]u64{30, 20, 10}
    ids := combined_ids[:] if combined else session_ids[:]
    request: History_Search_Request = {
        direction = direction,
        include_persistent = combined,
        candidate_budget = 2,
    }
    rows: [1]History_Candidate_Summary
    summaries: [6]u8
    for step in 0..<len(ids) {
        index := step if direction == .Older else len(ids) - step - 1
        result := history_store_search(store, request, rows[:], summaries[:])
        testing.expect_value(t, result.outcome, History_Search_Outcome.Scanned)
        testing.expect_value(t, result.row_count, 1)
        testing.expect_value(t, rows[0].record.source_id, ids[index])
        testing.expect_value(t, rows[0].record.scope,
            combined_scopes[index] if combined else History_Record_Scope.Session)
        history_search_test_exact_summary(t, store, rows[0], summaries[:])
        request.cursor, request.cursor_valid = result.cursor, result.cursor_valid
    }
    boundary := history_store_search(store, request, rows[:], summaries[:])
    testing.expect_value(t, boundary.outcome, History_Search_Outcome.Scanned)
    testing.expect_value(t, boundary.row_count, 0)
    testing.expect(t, boundary.exhausted)
}

// Byte pressure must not skip the unconsumed match or silently truncate its summary.
@(test)
history_search_bounds_output_independently :: proc(t: ^testing.T) {
    connection: sqlite.Connection
    store: History_Store
    if !history_store_test_open_memory(t, &connection, &store) {
        return
    }
    defer _ = sqlite.connection_close(&connection)
    defer _ = history_store_destroy(&store)
    sources := [?]string{"older", "defg", "abc"}
    for source, index in sources {
        testing.expect_value(t, history_store_insert(&store,
            history_store_test_record(u64(index + 1), .Normal, 100, 1, 1),
            source).outcome, History_Write_Outcome.Stored)
    }
    visibility := [?]bool{false, true}
    for combined in visibility {
        history_search_test_byte_pressure(t, &store, combined)
    }
}

// A rejected row is re-examined after the last successfully consumed position.
history_search_test_byte_pressure :: proc(
    t: ^testing.T, store: ^History_Store, combined: bool) {
    request: History_Search_Request = {
        include_persistent = combined,
        candidate_budget = 3,
    }
    rows: [3]History_Candidate_Summary
    summaries: [6]u8
    for id := u64(3); id > 0; id -= 1 {
        result := history_store_search(store, request, rows[:], summaries[:])
        testing.expect_value(t, result.outcome, History_Search_Outcome.Scanned)
        testing.expect_value(t, result.row_count, 1)
        testing.expect_value(t, result.examined_count, 1 if id == 1 else 2)
        testing.expect_value(t, result.cursor.source_id, id)
        testing.expect_value(t, result.output_full, id != 1)
        testing.expect_value(t, result.exhausted, id == 1)
        history_search_test_exact_summary(t, store, rows[0], summaries[:])
        request.cursor, request.cursor_valid = result.cursor, result.cursor_valid
    }
    request.cursor_valid = false
    too_small := history_store_search(store, request, rows[:], summaries[:2])
    testing.expect_value(t, too_small.outcome, History_Search_Outcome.Failed)
    testing.expect_value(t, too_small.failure.kind, History_Store_Error_Kind.Capacity)
    exact := history_store_search(store, request, rows[:], summaries[:3])
    testing.expect_value(t, exact.outcome, History_Search_Outcome.Scanned)
    testing.expect_value(t, exact.summary_bytes, 3)
    testing.expect_value(t, exact.cursor.source_id, u64(3))
}

// Bounded prefixes preserve graphemes, while matching and recall use complete source.
@(test)
history_search_clips_summaries_not_search_or_recall :: proc(t: ^testing.T) {
    connection: sqlite.Connection
    store: History_Store
    if !history_store_test_open_memory(t, &connection, &store) {
        return
    }
    defer _ = sqlite.connection_close(&connection)
    defer _ = history_store_destroy(&store)
    cases := [?]struct {offset: int, cluster: string}{
        {255, "\u03b1"}, {254, "a\u0301"},
        {252, "\U0001f469\u200d\U0001f4bb"},
    }
    for item, index in cases {
        source: [300]u8
        for &byte in source {
            byte = u8('x')
        }
        copy(source[item.offset:], item.cluster)
        copy(source[294:], "needle")
        record := history_store_test_record(u64(index + 1), .Shell, 100, 4, 5)
        testing.expect_value(t,
            history_store_insert(&store, record, string(source[:])).outcome,
            History_Write_Outcome.Stored)
        history_search_test_prefix(t, &store, source[:], item.offset)
    }
}

// Verify owned summary bytes and full exact source survive statement resets.
history_search_test_prefix :: proc(
    t: ^testing.T, store: ^History_Store, source: []u8, expected_prefix: int) {
    request: History_Search_Request = {
        query = "needle",
        candidate_budget = 1,
    }
    rows: [1]History_Candidate_Summary
    summaries: [HISTORY_SEARCH_SUMMARY_MAX_BYTES]u8
    result := history_store_search(store, request, rows[:], summaries[:])
    testing.expect_value(t, result.outcome, History_Search_Outcome.Scanned)
    testing.expect_value(t, result.row_count, 1)
    testing.expect(t, !result.exhausted)
    testing.expect(t, rows[0].summary_clipped)
    testing.expect_value(t, rows[0].summary_length, expected_prefix)
    testing.expect_value(t, rows[0].source_length, len(source))
    testing.expect_value(t, rows[0].record.mode, protocol.Evaluation_Mode.Shell)
    testing.expect_value(t, rows[0].record.source_revision, u64(5))
    exact_source: [300]u8
    exact := history_store_get_by_id(
        store, rows[0].record.source_id, exact_source[:])
    testing.expect_value(t, exact.outcome, History_Read_Outcome.Found)
    testing.expect_value(t, string(exact_source[:]), string(source))
    testing.expect_value(t,
        string(summaries[:expected_prefix]), string(source[:expected_prefix]))
}

// Session search must work even when no main history table exists.
@(test)
history_search_without_durable_schema :: proc(t: ^testing.T) {
    connection: sqlite.Connection
    failure := sqlite.connection_open(
        &connection, ":memory:", .Readwrite_Create, context.temp_allocator)
    testing.expect(t, history_store_sqlite_error_is_clear(failure))
    if !history_store_sqlite_error_is_clear(failure) {
        return
    }
    defer _ = sqlite.connection_close(&connection)
    store: History_Store
    testing.expect_value(t, history_store_init(&store, &connection).kind,
        History_Store_Error_Kind.None)
    defer _ = history_store_destroy(&store)
    testing.expect(t, !store.durable_available)
    testing.expect_value(t, history_store_insert(&store,
        history_store_test_record(1, .Normal, 100, 1, 1), "session").outcome,
        History_Write_Outcome.Stored)
    history_search_test_unavailable_scope(t, &store)
}

// Unavailable combined search is explicit, never a private connection or fallback.
history_search_test_unavailable_scope :: proc(
    t: ^testing.T, store: ^History_Store) {
    request: History_Search_Request = {
        candidate_budget = 2,
    }
    rows: [2]History_Candidate_Summary
    summaries: [16]u8
    directions := [?]History_Search_Direction{.Older, .Newer}
    for direction in directions {
        request.direction = direction
        result := history_store_search(store, request, rows[:], summaries[:])
        testing.expect_value(t, result.outcome, History_Search_Outcome.Scanned)
        testing.expect_value(t, result.row_count, 1)
        testing.expect(t, result.exhausted)
    }
    request.include_persistent = true
    unavailable := history_store_search(store, request, rows[:], summaries[:])
    testing.expect_value(t, unavailable.outcome, History_Search_Outcome.Failed)
    testing.expect_value(t, unavailable.failure.kind,
        History_Store_Error_Kind.Invalid_State)
}

// Reject invalid budgets/cursors/capacities and preserve explicit SQLite failures.
@(test)
history_search_reports_failures :: proc(t: ^testing.T) {
    connection: sqlite.Connection
    store: History_Store
    if !history_store_test_open_memory(t, &connection, &store) {
        return
    }
    defer _ = sqlite.connection_close(&connection)
    defer _ = history_store_destroy(&store)
    history_search_test_invalid_requests(t, &store)
    testing.expect(t, history_store_test_exec(
        &connection, "DROP TABLE temp.terminal_history;"))
    request: History_Search_Request = {
        candidate_budget = 1,
    }
    rows: [1]History_Candidate_Summary
    result := history_store_search(&store, request, rows[:], nil)
    testing.expect_value(t, result.outcome, History_Search_Outcome.Failed)
    testing.expect_value(t, result.failure.kind, History_Store_Error_Kind.Sqlite)
    testing.expect_value(t, result.row_count, 0)
}

// Invalid input is distinguished from a successful empty search.
history_search_test_invalid_requests :: proc(t: ^testing.T, store: ^History_Store) {
    cases := [?]History_Search_Request{
        {},
        {
            candidate_budget = -1,
        },
        {
            candidate_budget = HISTORY_SEARCH_CANDIDATE_MAX + 1,
        },
        {
            candidate_budget = 1,
            direction = History_Search_Direction(99),
        },
        {
            candidate_budget = 1,
            cursor_valid = true,
        },
        {
            candidate_budget = 1,
            cursor_valid = true,
            cursor = {
                source_id = u64(max(i64)) + 1,
            },
        },
        {
            candidate_budget = 1,
            cursor_valid = true,
            cursor = {
                scope = .Persistent,
                source_id = 1,
            },
        },
        {
            candidate_budget = 1,
            cursor_valid = true,
            cursor = {
                submitted_at_unix_ms = -1,
                source_id = 1,
            },
        },
    }
    rows: [1]History_Candidate_Summary
    for request in cases {
        result := history_store_search(store, request, rows[:], nil)
        testing.expect_value(t, result.outcome, History_Search_Outcome.Failed)
        testing.expect(t, result.failure.kind != .None)
    }
    request: History_Search_Request = {
        candidate_budget = 1,
    }
    testing.expect_value(t, history_store_search(store, request, nil, nil).failure.kind,
        History_Store_Error_Kind.Capacity)
    query: [HISTORY_SEARCH_QUERY_MAX_BYTES + 1]u8
    request.query = string(query[:])
    testing.expect_value(t,
        history_store_search(store, request, rows[:], nil).failure.kind,
        History_Store_Error_Kind.Capacity)
}

// Exact maximum query and work budgets must not stop at an implicit history cap.
@(test)
history_search_reaches_beyond_maximum_window :: proc(t: ^testing.T) {
    connection: sqlite.Connection
    store: History_Store
    if !history_store_test_open_memory(t, &connection, &store) {
        return
    }
    defer _ = sqlite.connection_close(&connection)
    defer _ = history_store_destroy(&store)
    source: [HISTORY_SEARCH_QUERY_MAX_BYTES]u8
    for &byte in source {
        byte = u8('q')
    }
    for id in u64(1)..=u64(HISTORY_SEARCH_CANDIDATE_MAX + 1) {
        testing.expect_value(t, history_store_insert(&store,
            history_store_test_record(id, .Normal, 100, 1, 1),
            string(source[:])).outcome, History_Write_Outcome.Stored)
    }
    request: History_Search_Request = {
        query = string(source[:]),
        candidate_budget = HISTORY_SEARCH_CANDIDATE_MAX,
    }
    rows: [HISTORY_SEARCH_CANDIDATE_MAX]History_Candidate_Summary
    summaries: [HISTORY_SEARCH_CANDIDATE_MAX * HISTORY_SEARCH_SUMMARY_MAX_BYTES]u8
    first := history_store_search(&store, request, rows[:], summaries[:])
    testing.expect_value(t, first.outcome, History_Search_Outcome.Scanned)
    testing.expect_value(t, first.examined_count, HISTORY_SEARCH_CANDIDATE_MAX)
    testing.expect_value(t, first.row_count, HISTORY_SEARCH_CANDIDATE_MAX)
    testing.expect_value(t, first.summary_bytes, len(summaries))
    testing.expect(t, !first.exhausted)
    request.cursor, request.cursor_valid = first.cursor, first.cursor_valid
    last := history_store_search(&store, request, rows[:], summaries[:])
    testing.expect_value(t, last.outcome, History_Search_Outcome.Scanned)
    testing.expect_value(t, last.row_count, 1)
    testing.expect_value(t, rows[0].record.source_id, u64(1))
    testing.expect(t, last.exhausted)
}

// No match needs no summary storage, and malformed rows never publish partial success.
@(test)
history_search_distinguishes_empty_from_bad_data :: proc(t: ^testing.T) {
    connection: sqlite.Connection
    store: History_Store
    if !history_store_test_open_memory(t, &connection, &store) {
        return
    }
    defer _ = sqlite.connection_close(&connection)
    defer _ = history_store_destroy(&store)
    request: History_Search_Request = {
        candidate_budget = 3,
    }
    rows: [2]History_Candidate_Summary
    empty := history_store_search(&store, request, rows[:], nil)
    testing.expect_value(t, empty.outcome, History_Search_Outcome.Scanned)
    testing.expect(t, empty.exhausted)
    testing.expect(t, !empty.cursor_valid)
    for id in u64(1)..=2 {
        testing.expect_value(t, history_store_insert(&store,
            history_store_test_record(id, .Normal, 100, 1, 1), "source").outcome,
            History_Write_Outcome.Stored)
    }
    request.query = "absent"
    absent := history_store_search(&store, request, rows[:], nil)
    testing.expect_value(t, absent.outcome, History_Search_Outcome.Scanned)
    testing.expect_value(t, absent.row_count, 0)
    testing.expect_value(t, absent.examined_count, 2)
    testing.expect(t, absent.exhausted)
    history_search_test_bad_data(t, &store, &connection)
}

// A row failure discards published counts; resetting permits a later repaired read.
history_search_test_bad_data :: proc(
    t: ^testing.T, store: ^History_Store, connection: ^sqlite.Connection) {
    request: History_Search_Request = {
        candidate_budget = 3,
    }
    rows: [3]History_Candidate_Summary
    summaries: [16]u8
    testing.expect(t, history_store_test_exec(
        connection, "UPDATE temp.terminal_history SET mode=99 WHERE submission_id=1;"))
    failed := history_store_search(store, request, rows[:], summaries[:])
    testing.expect_value(t, failed.outcome, History_Search_Outcome.Failed)
    testing.expect_value(t, failed.failure.kind, History_Store_Error_Kind.Invalid_Data)
    testing.expect_value(t, failed.row_count, 0)
    testing.expect_value(t, failed.summary_bytes, 0)
    testing.expect(t, history_store_test_exec(
        connection, "UPDATE temp.terminal_history SET mode=0 WHERE submission_id=1;"))
    repaired := history_store_search(store, request, rows[:], summaries[:])
    testing.expect_value(t, repaired.outcome, History_Search_Outcome.Scanned)
    testing.expect_value(t, repaired.row_count, 2)
    testing.expect(t, repaired.exhausted)
    testing.expect_value(t, history_store_destroy(store).kind,
        History_Store_Error_Kind.None)
    testing.expect(t, !history_store_has_statements(store))
    testing.expect(t, connection.handle != nil)
}

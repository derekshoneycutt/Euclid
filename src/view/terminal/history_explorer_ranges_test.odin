#+test
package terminalview

import historyruntime "../../terminal/history/runtime"
import termhiststore "../../persistence/userdata/history"
import "core:testing"

// Range capacity failures are visible presentation failures, never failed filtering or recall.
@(test)
history_explorer_ranges_overflow_keeps_exact_source :: proc(t: ^testing.T) {
    fixture := history_explorer_test_start(t)
    if fixture == nil {
        return
    }
    defer history_explorer_test_destroy(t, fixture)
    source: [257]u8
    for &byte in source {
        byte = 'a'
    }
    history_explorer_test_insert(t, fixture, 1, string(source[:]))
    identity := history_explorer_test_query(t, fixture, 1, 1)
    history_explorer_test_search(t, fixture, identity, 1, {
        query = "=a",
        result_limit = 1,
    })
    history_runtime_service(&fixture.history, &fixture.admission, &fixture.pool, false)
    history_explorer_test_join(t, fixture)
    rows: [1]termhiststore.History_Candidate_Summary
    summaries: [256]u8
    completion, copied := history_runtime_consume_search_result(
        &fixture.history, rows[:], summaries[:])
    testing.expect(t, copied && completion.result.outcome == .Complete)
    testing.expect_value(t, rows[0].matches.count, 0)
    testing.expect(t, rows[0].matches.failure.kind == .Search &&
        rows[0].matches.failure.search_error == .Capacity)
    testing.expect_value(t, fixture.history.store.search.compile_count, u64(1))
    history_explorer_test_overflow_preview(t, fixture, identity, source[:])
}

// Preview remains complete and recallable when its separate bounded emphasis cannot fit.
history_explorer_test_overflow_preview :: proc(
    t: ^testing.T, fixture: ^History_Explorer_Test_Fixture,
    identity: historyruntime.History_Explorer_Identity, source: []u8) {
    testing.expect(t, history_runtime_request_preview(&fixture.history, {
        identity = identity,
        request_id = 1,
        source_id = 1,
        source_revision = 1,
    }) == .Queued)
    history_runtime_service(&fixture.history, &fixture.admission, &fixture.pool, false)
    history_explorer_test_join(t, fixture)
    destination: [257]u8
    completion, copied := history_runtime_consume_preview_result(
        &fixture.history, destination[:])
    testing.expect(t, copied && completion.result.outcome == .Found)
    testing.expect_value(t, string(destination[:]), string(source))
    testing.expect_value(t, completion.matches.count, 0)
    testing.expect(t, completion.matches.failure.search_error == .Capacity)
    testing.expect_value(t, fixture.history.store.search.compile_count, u64(1))
}

// The shared page budget never changes acceptance when individually valid rows exhaust it.
@(test)
history_explorer_ranges_pack_one_bounded_page :: proc(t: ^testing.T) {
    fixture := history_explorer_test_start(t)
    if fixture == nil {
        return
    }
    defer history_explorer_test_destroy(t, fixture)
    source: [200]u8
    for &byte in source {
        byte = 'a'
    }
    history_explorer_test_insert(t, fixture, 1, string(source[:]))
    history_explorer_test_insert(t, fixture, 2, string(source[:]))
    identity := history_explorer_test_query(t, fixture, 1, 1)
    history_explorer_test_search(t, fixture, identity, 1, {
        query = "=a",
        result_limit = 2,
    })
    history_runtime_service(&fixture.history, &fixture.admission, &fixture.pool, false)
    history_explorer_test_join(t, fixture)
    rows: [2]termhiststore.History_Candidate_Summary
    summaries: [512]u8
    completion, copied := history_runtime_consume_search_result(
        &fixture.history, rows[:], summaries[:])
    testing.expect(t, copied && completion.result.outcome == .Complete)
    testing.expect_value(t, completion.result.row_count, 2)
    testing.expect_value(t, completion.ranges[199].end_byte, 200)
    testing.expect_value(t, rows[0].matches.count, 200)
    testing.expect_value(t,
        rows[0].matches.failure.kind, termhiststore.History_Store_Error_Kind.None)
    testing.expect_value(t, rows[1].matches.count, 0)
    testing.expect_value(t,
        rows[1].matches.failure.kind, termhiststore.History_Store_Error_Kind.Capacity)
    testing.expect_value(t, fixture.history.store.search.compile_count, u64(1))
}

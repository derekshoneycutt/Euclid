package terminalview

import historyruntime "../../terminal/history/runtime"
import termhiststore "../../terminal/history/store"

// Refetch accepted full sources under the same lease; mutation scratch is idle during search.
history_runtime_collect_row_matches :: proc(history: ^historyruntime.History_Runtime) {
    history.search_range_count = 0
    for &row in history.search_rows[:history.active_search_result.row_count] {
        read: termhiststore.History_Read_Result
        if row.record.scope == .Persistent {
            read = termhiststore.history_store_get_persistent_by_id(
                &history.store, row.record.source_id, history.active_source[:])
        } else {
            read = termhiststore.history_store_get_by_id(
                &history.store, row.record.source_id, history.active_source[:])
        }
        if read.outcome != .Found || read.record != row.record {
            if read.outcome == .Found {
                history_runtime_clear_bytes(history.active_source[:read.source_length])
            }
            row.matches.failure = read.failure
            if row.matches.failure.kind == .None {
                row.matches.failure.kind = .Conflict
            }
            history_runtime_report_explorer_failure("row_ranges", row.matches.failure)
            continue
        }
        matches := history_runtime_source_matches(
            history, history.active_search.identity,
            string(history.active_source[:read.source_length]))
        history_runtime_pack_row_matches(history, &row, &matches)
        history_runtime_clear_bytes(history.active_source[:read.source_length])
    }
}

// Pack a complete row's emphasis or report capacity without publishing partial ranges.
history_runtime_pack_row_matches :: proc(
    history: ^historyruntime.History_Runtime,
    row: ^termhiststore.History_Candidate_Summary,
    matches: ^termhiststore.History_Match_Ranges) {
    row.matches = {
        offset = history.search_range_count,
        failure = matches.failure,
    }
    if matches.count > len(history.search_ranges) - history.search_range_count {
        row.matches.failure.kind = .Capacity
        history_runtime_report_explorer_failure("page_ranges", row.matches.failure)
        return
    }
    row.matches.count = matches.count
    copy(history.search_ranges[history.search_range_count:],
        matches.ranges[:matches.count])
    history.search_range_count += matches.count
}

// Preserve readable source on presentation failure, with an explicit nonblocking diagnostic.
history_runtime_source_matches :: proc(
    history: ^historyruntime.History_Runtime,
    identity: historyruntime.History_Explorer_Identity,
    source: string) -> termhiststore.History_Match_Ranges {
    result := termhiststore.history_store_match_ranges(
        &history.store, identity.runtime_epoch, source)
    if result.failure.kind != .None && result.failure.kind != .Cancelled {
        history_runtime_report_explorer_failure("ranges", result.failure)
    }
    return result
}

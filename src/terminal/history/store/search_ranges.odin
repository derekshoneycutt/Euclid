package termhiststore

import termhistsearch "../search"

// Evaluate presentation ranges only against the retained query, never recompile or filter.
history_store_match_ranges :: proc(
    store: ^History_Store, identity: u64, source: string) -> History_Match_Ranges {
    output: History_Match_Ranges
    if !history_store_ready(store) || !store.search.admitted ||
       store.search.identity != identity || store.search.failure.kind != .None {
        output.failure.kind = .Invalid_State
        return output
    }
    result := termhistsearch.history_search_match_ranges(
        &store.search.plan, &store.search.workspace, source,
        output.ranges[:], &store.search_cancel)
    if result.error != .None {
        output.failure = history_search_native_error({
            error = result.error,
            engine_error = result.engine_error,
        })
        return output
    }
    output.count = result.count
    return output
}

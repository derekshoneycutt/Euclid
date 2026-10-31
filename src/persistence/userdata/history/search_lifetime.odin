package termhiststore

import sqlite "../../../sqlite"
import pcre2 "../../../pcre2"
import termhistsearch "../../../terminal/history/search"
import sync "core:sync"

// Compile only at admission; a retained identity cannot silently change its query.
// Zero identity supports synchronous store clients, keyed by their exact query bytes.
history_store_admit_search :: proc(
    store: ^History_Store, request: History_Search_Request) -> History_Store_Error {
    if !history_store_ready(store) || store.search_adapter.active != nil {
        return {
            kind = .Invalid_State,
        }
    }
    if len(request.query) > HISTORY_SEARCH_QUERY_MAX_BYTES ||
       request.search_identity > u64(max(i64)) {
        return {
            kind = .Capacity,
        }
    }
    search := &store.search
    same_query := request.query == string(search.query[:search.query_length])
    if search.admitted &&
       (request.search_identity == 0 || search.identity == request.search_identity) {
        if same_query {
            return search.failure
        }
        if request.search_identity != 0 {
            return {
                kind = .Invalid_Argument,
            }
        }
    }
    return history_store_compile_search(store, request)
}

// Replace a retired search and retain either its compiled resources or admission failure.
history_store_compile_search :: proc(
    store: ^History_Store, request: History_Search_Request) -> History_Store_Error {
    search := &store.search
    next_identity := request.search_identity
    if next_identity == 0 {
        next_identity = search.identity % u64(max(i64)) + 1
    }
    history_store_retire_search(store)
    if sync.atomic_load_explicit(&store.search_cancel.requested, .Acquire) != 0 {
        return {
            kind = .Cancelled,
            search_error = .Cancelled,
        }
    }
    failure := termhistsearch.history_search_compile(
        &search.plan, &search.workspace, request.query)
    search.compile_count += 1
    search.identity = next_identity
    search.admitted = true
    search.query_length = len(request.query)
    copy(search.query[:], request.query)
    if failure != .None {
        search.failure = {
            kind = .Search,
            search_error = failure,
        }
    }
    return search.failure
}

// Retire native handles only after the statement and any worker borrows have joined.
history_store_retire_search :: proc(store: ^History_Store) {
    termhistsearch.history_search_destroy(&store.search.plan, &store.search.workspace)
    store.search.query = {}
    store.search.query_length = 0
    store.search.admitted = false
    store.search.failure = {}
}

// Bind one exclusive execution and chain the tracked connection progress owner.
history_store_begin_search_execution :: proc(
    store: ^History_Store) -> History_Store_Error {
    adapter := &store.search_adapter
    if !adapter.registered || adapter.active != nil ||
       !store.search.plan.initialized {
        return {
            kind = .Invalid_State,
        }
    }
    if sync.atomic_load_explicit(&store.search_cancel.requested, .Acquire) != 0 {
        return {
            kind = .Cancelled,
            search_error = .Cancelled,
        }
    }
    adapter.saved_context = context
    adapter.active = &store.search
    adapter.cancel = &store.search_cancel
    adapter.failure = {}
    adapter.previous_progress = store.connection.progress
    previous_interval := adapter.previous_progress.instructions
    adapter.progress_interval = min(1000, previous_interval) if previous_interval > 0 else
        1000
    adapter.progress_ticks = 0
    handler: sqlite.Progress_Handler = {
        instructions = adapter.progress_interval,
        callback = history_search_sql_progress,
        user_data = adapter,
    }
    failure := history_store_error_from_sqlite(
        sqlite.connection_set_progress(store.connection, handler))
    if failure.kind != .None {
        adapter.active, adapter.cancel = nil, nil
        adapter.previous_progress = {}
    }
    return failure
}

// Detach after statement reset, before releasing exclusive connection admission.
history_store_end_search_execution :: proc(
    store: ^History_Store) -> History_Store_Error {
    adapter := &store.search_adapter
    failure := sqlite.connection_set_progress(
        store.connection, adapter.previous_progress)
    adapter.active = nil
    adapter.cancel = nil
    adapter.previous_progress = {}
    return history_store_error_from_sqlite(failure)
}

// Cancellation is the only store field a display owner may touch during execution.
history_store_cancel_search :: proc(store: ^History_Store) {
    pcre2.cancel_token_request(&store.search_cancel)
}

// Reset cancellation only at the joined boundary before submitting a new execution.
history_store_reset_search_cancel :: proc(store: ^History_Store) {
    pcre2.cancel_token_reset(&store.search_cancel)
}

// Unregister before the stable store child can die; never manually invoke its destructor.
history_store_unregister_search :: proc(store: ^History_Store) -> sqlite.Error {
    history_store_retire_search(store)
    if !store.search_adapter.registered {
        return {}
    }
    return sqlite.connection_unregister_scalar(store.connection, "history_matches", 3)
}

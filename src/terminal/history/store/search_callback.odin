package termhiststore

import sqlite "../../../sqlite"
import termhistsearch "../search"
import protocol "../../../core/protocol"
import "core:c"
import sync "core:sync"

// Register the stable store child; SQLite owns the destructor notification, not its memory.
history_store_register_search :: proc(store: ^History_Store) -> History_Store_Error {
    if store.search_adapter.registered {
        return {
            kind = .Invalid_State,
        }
    }
    store.search_adapter.saved_context = context
    store.search_adapter.registered = true
    function: sqlite.Scalar_Function = {
        name = "history_matches",
        argument_count = 3,
        user_data = &store.search_adapter,
        callback = history_search_sql_callback,
        destroy = history_search_sql_destroy,
    }
    failure := sqlite.connection_register_scalar(store.connection, function)
    if failure.validation != .None {
        store.search_adapter.registered = false
    }
    return history_store_error_from_sqlite(failure)
}

// SQLite calls this exactly once on native failure, replacement, unregister, or close.
history_search_sql_destroy :: proc "c" (user_data: rawptr) {
    adapter := cast(^History_Search_Adapter)user_data
    adapter.registered = false
}

// Validate the execution identity before borrowing SQLite source for native matching.
history_search_sql_callback :: proc "c" (
    call: ^sqlite.Function_Context, count: c.int, values: [^]^sqlite.Value) {
    adapter := cast(^History_Search_Adapter)sqlite.function_user_data(call)
    context = adapter.saved_context
    if count != 3 || adapter.active == nil {
        history_search_sql_fail(adapter, call, {
            kind = .Invalid_State,
        })
        return
    }
    identity, identity_error := sqlite.value_i64(values[2])
    mode_value, mode_error := sqlite.value_i64(values[1])
    mode, mode_valid := history_store_mode_from_i64(mode_value)
    if identity_error.validation != .None || mode_error.validation != .None ||
       !mode_valid || identity <= 0 || u64(identity) != adapter.active.identity {
        history_search_sql_fail(adapter, call, {
            kind = .Invalid_Argument,
        })
        return
    }
    source, source_error := sqlite.value_text(call, values[0])
    failure := history_store_column_error(source_error)
    if len(source) > protocol.TERMINAL_RETAINED_TEXT_MAX_BYTES {
        failure.kind = .Capacity
    }
    if failure.kind != .None {
        history_search_sql_fail(adapter, call, failure)
        return
    }
    result := termhistsearch.history_search_matches(
        &adapter.active.plan, &adapter.active.workspace, source, mode, adapter.cancel)
    if result.error != .None {
        history_search_sql_fail(adapter, call, history_search_native_error(result))
        return
    }
    sqlite.function_result_bool(call, result.matched)
}

// Keep native causes outside SQLite's generic callback error and abort the statement.
history_search_sql_fail :: proc(
    adapter: ^History_Search_Adapter, call: ^sqlite.Function_Context,
    failure: History_Store_Error) {
    if adapter.failure.kind == .None {
        adapter.failure = failure
    }
    code := sqlite.Result_Code.Error
    if failure.search_error == .Out_Of_Memory ||
       failure.sqlite_error.result == .No_Memory {
        code = .No_Memory
    } else if failure.kind == .Cancelled {
        code = .Interrupt
    }
    sqlite.function_result_error(call, code, "history search execution failed")
}

// Translate match failures without treating cancellation or resource exhaustion as no-match.
history_search_native_error :: proc(
    result: termhistsearch.Search_Result) -> History_Store_Error {
    return {
        kind = .Cancelled if result.error == .Cancelled else .Search,
        search_error = result.error,
        engine_error = result.engine_error,
    }
}

// Observe the same atomic token as PCRE2 and preserve the prior progress owner's cadence.
history_search_sql_progress :: proc "c" (user_data: rawptr) -> c.int {
    adapter := cast(^History_Search_Adapter)user_data
    context = adapter.saved_context
    if sync.atomic_load_explicit(&adapter.cancel.requested, .Acquire) != 0 {
        adapter.failure.kind = .Cancelled
        adapter.failure.search_error = .Cancelled
        return 1
    }
    previous := adapter.previous_progress
    if previous.instructions > 0 {
        adapter.progress_ticks += adapter.progress_interval
        if adapter.progress_ticks >= previous.instructions {
            adapter.progress_ticks -= previous.instructions
            return previous.callback(previous.user_data)
        }
    }
    return 0
}

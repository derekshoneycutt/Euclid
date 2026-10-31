#+test
package termhiststore

import sqlite "../../../sqlite"
import "core:testing"

// Presentation borrows the admitted identity, with no fake ranges from modes, exclusions, or skips.
@(test)
history_search_ranges_require_retained_identity :: proc(t: ^testing.T) {
    connection: sqlite.Connection
    store: History_Store
    if !history_store_test_open_memory(t, &connection, &store) {
        return
    }
    defer _ = sqlite.connection_close(&connection)
    defer _ = history_store_destroy(&store)
    testing.expect_value(t, history_store_admit_search(&store, {
        query = "!missing;julia>;/[",
        search_identity = 9,
    }).kind, History_Store_Error_Kind.None)
    result := history_store_match_ranges(&store, 9, "source")
    testing.expect_value(t, result.count, 0)
    testing.expect_value(t, result.failure.kind, History_Store_Error_Kind.None)
    result = history_store_match_ranges(&store, 10, "source")
    testing.expect_value(t, result.count, 0)
    testing.expect_value(t, result.failure.kind, History_Store_Error_Kind.Invalid_State)
    testing.expect_value(t, store.search.compile_count, u64(1))
}

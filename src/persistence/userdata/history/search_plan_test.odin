#+test
package termhiststore

import sqlite "../../../sqlite"
import "core:strings"
import "core:testing"

// Session chronology avoids a sort; combined overlap uses the existing link index.
@(test)
history_search_sql_query_plans_preserve_access_paths :: proc(t: ^testing.T) {
    connection: sqlite.Connection
    store: History_Store
    if !history_store_test_open_memory(t, &connection, &store) {
        return
    }
    defer _ = sqlite.connection_close(&connection)
    defer _ = history_store_destroy(&store)
    queries := [?]struct {sql: string, combined: bool}{
        {TERMINAL_HISTORY_SEARCH_OLDER_SQL, false},
        {TERMINAL_HISTORY_SEARCH_NEWER_SQL, false},
        {TERMINAL_HISTORY_SEARCH_COMBINED_OLDER_SQL, true},
        {TERMINAL_HISTORY_SEARCH_COMBINED_NEWER_SQL, true},
    }
    for query in queries {
        history_search_test_query_plan(t, &connection, query.sql, query.combined)
    }
}

// Inspect the actual SQLite plan without executing callbacks or mutating history.
history_search_test_query_plan :: proc(
    t: ^testing.T, connection: ^sqlite.Connection, sql: string, combined: bool) {
    bytes: [8192]u8
    prefix := "EXPLAIN QUERY PLAN "
    copy(bytes[:], prefix)
    copy(bytes[len(prefix):], sql)
    statement: sqlite.Statement
    failure := sqlite.statement_prepare_text(
        connection, &statement, string(bytes[:len(prefix) + len(sql)]))
    testing.expect(t, history_store_sqlite_error_is_clear(failure))
    if !history_store_sqlite_error_is_clear(failure) {
        return
    }
    defer _ = sqlite.statement_finalize(&statement)
    link_index := false
    for {
        status, step_error := sqlite.statement_step(&statement)
        testing.expect(t, history_store_sqlite_error_is_clear(step_error))
        if status != .Row {
            break
        }
        length, read_error := sqlite.column_text_copy(&statement, 3, bytes[:])
        testing.expect(t, history_store_sqlite_error_is_clear(read_error))
        detail := string(bytes[:length])
        testing.expect(t, !strings.contains(detail, "MATERIALIZE"))
        if !combined {
            testing.expect(t, !strings.contains(detail, "USE TEMP B-TREE"))
        }
        link_index = link_index || strings.contains(detail,
            "COVERING INDEX terminal_history_persistent_entry")
    }
    testing.expect_value(t, link_index, combined)
}

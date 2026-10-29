#+test
package main

import termhistsearch "terminal/history/search"

import "core:testing"

// Include the history-owned compiler in the full Odin test dependency graph.
@(test)
terminal_history_search_substrate_is_wired :: proc(t: ^testing.T) {
    plan: termhistsearch.Search_Plan
    workspace: termhistsearch.Search_Workspace
    query := "word"
    result := termhistsearch.history_search_compile(
        &plan, &workspace, query)
    testing.expect_value(t, result, termhistsearch.Search_Error.None)
    if result == .None {
        termhistsearch.history_search_destroy(&plan, &workspace)
    }
}

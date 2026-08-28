#+test
package evidence_text

import "core:testing"

// Verify overwritten handles become stale and required eviction remains sticky.
@(test)
text_test_generational_eviction :: proc(t: ^testing.T) {
    store: Store
    first, complete := store_put(&store, "first", true)
    testing.expect(t, complete)
    value, found := store_get(&store, first)
    testing.expect(t, found)
    testing.expect_value(t, value, "first")

    for index in 0..<TEXT_STORE_CAPACITY {
        _, _ = store_put(&store, "replacement", false)
    }
    _, stale := store_get(&store, first)
    testing.expect(t, !stale)
    testing.expect(t, store.required_evidence_lost)
}

// Verify oversized text is retained as an explicitly truncated bounded prefix.
@(test)
text_test_truncation_is_reported :: proc(t: ^testing.T) {
    store: Store
    source: [TEXT_ENTRY_CAPACITY + 1]u8
    handle, complete := store_put(&store, string(source[:]), false)
    testing.expect(t, !complete)
    value, found := store_get(&store, handle)
    testing.expect(t, found)
    testing.expect_value(t, len(value), TEXT_ENTRY_CAPACITY)
}

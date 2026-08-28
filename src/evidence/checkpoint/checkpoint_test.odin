#+test
package evidence_checkpoint

import "core:testing"

// Verify snapshots retain values and reject stale overwritten handles.
@(test)
checkpoint_test_generational_storage :: proc(t: ^testing.T) {
    store: Store
    snapshot := Snapshot{fixed_step = 7, point_count = 1}
    snapshot.points[0] = {index = 3, x = 1, y = 2, z = 3, has_position = true}
    first := store_put(&store, snapshot, true)
    stored, found := store_get(&store, first)
    testing.expect(t, found)
    testing.expect_value(t, stored^.fixed_step, u64(7))
    testing.expect_value(t, stored^.points[0].index, i32(3))

    for index in 0..<CHECKPOINT_STORE_CAPACITY {
        _ = store_put(&store, {fixed_step = u64(index + 8)}, false)
    }
    _, stale := store_get(&store, first)
    testing.expect(t, !stale)
    testing.expect(t, store.required_evidence_lost)
}

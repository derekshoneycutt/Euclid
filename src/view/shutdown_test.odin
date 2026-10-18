#+test
package view

import core "../core"
import "core:mem"
import "core:testing"
import "base:runtime"

// The display's root allocation must not be released through Julia's callback context.
@(test)
root_state_teardown_uses_display_context :: proc(t: ^testing.T) {
    tracker: mem.Tracking_Allocator
    mem.tracking_allocator_init(&tracker, context.allocator, context.allocator)
    defer mem.tracking_allocator_destroy(&tracker)
    context.allocator = mem.tracking_allocator(&tracker)
    state := new(core.Euclid_General_State, context.allocator)
    state^.saved_context = context
    state^.saved_context.allocator = {procedure = runtime.heap_allocator_proc}
    free_animations_state(state)
    testing.expect_value(t, len(tracker.allocation_map), 0)
    testing.expect_value(t, tracker.current_memory_allocated, i64(0))
}

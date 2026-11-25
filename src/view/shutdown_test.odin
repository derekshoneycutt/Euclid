#+test
package view

import core "../core"
import audio "../audio"
import operations "../operations"
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
    state^.saved_context.allocator = {
        procedure = runtime.heap_allocator_proc,
    }
    free_animations_state(state)
    testing.expect_value(t, len(tracker.allocation_map), 0)
    testing.expect_value(t, tracker.current_memory_allocated, i64(0))
}


// Shutdown invalidates outstanding handles and clears native drawing activity.
@(test)
shutdown_active_operations_releases_activity_and_storage :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    testing.expect(t, operations.active_operation_storage_init(
        &state^.active_operations))
    reservation, reserve_status := operations.active_operation_reserve(
        &state^.active_operations, 1, 2, 3)
    testing.expect_value(t, reserve_status, operations.Active_Operation_Status.Ok)
    testing.expect_value(t, operations.active_operation_admit(
        &state^.active_operations, reservation.execution),
        operations.Active_Operation_Status.Ok)
    testing.expect(t, audio.set_native_drawing_activity(
        &state^.chalk_audio, 1, true))
    shutdown_active_operations(state)
    testing.expect(t, !state^.chalk_audio.drawing_active)
    testing.expect(t, !operations.active_operation_storage_diagnostics(
        &state^.active_operations).initialized)
    _, live := operations.active_operation_observe(
        &state^.active_operations, reservation.execution)
    testing.expect(t, !live)
    free(state, context.allocator)
}

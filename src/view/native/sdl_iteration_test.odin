package native

import testing "core:testing"

// Verify nested entry cannot run another frame and deadlines retain skipped work.
@(test)
sdl_iteration_guard_and_nonblocking_pacing :: proc(t: ^testing.T) {
    gate: Sdl_Iteration_Gate
    testing.expect(t, sdl_iteration_enter(&gate))
    testing.expect(t, !sdl_iteration_enter(&gate))
    testing.expect(t, gate.active && gate.pending)
    testing.expect(t, sdl_iteration_due(&gate, 100, true, false))
    next := gate.next_tick
    testing.expect(t, !sdl_iteration_due(&gate, 101, true, false))
    testing.expect_value(t, gate.next_tick, next)
    testing.expect(t, sdl_iteration_due(&gate, 102, true, true))
    testing.expect(t, sdl_iteration_due(&gate, 103, false, false))
    sdl_iteration_leave(&gate)
    testing.expect(t, !gate.active)
    testing.expect(t, sdl_iteration_enter(&gate))
    sdl_iteration_leave(&gate)
    testing.expect(t, sdl_iteration_due(&gate, gate.next_tick, true, false))
}

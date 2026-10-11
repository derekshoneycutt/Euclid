#+test
package capture

import trace "../trace"
import "core:testing"

// Record the checkpoint passed to an injected display capture mechanism.
capture_test_sink :: proc(user_data: rawptr, checkpoint: Checkpoint) -> bool {
    destination := (^Checkpoint)(user_data)
    destination^ = checkpoint
    return true
}

// Verify capture binds the first post-request presented frame and semantic state.
@(test)
capture_test_first_presented_frame :: proc(t: ^testing.T) {
    coordinator: Coordinator
    trigger := trace.Identity{kind = .Checkpoint, id = 42, generation = 3}
    testing.expect(t, checkpoint_request(&coordinator, 7, trigger))
    testing.expect(t, !checkpoint_request(&coordinator, 8, {}))
    captured: Checkpoint

    status := checkpoint_after_present(&coordinator, 100, 12, {
        user_data = &captured,
        capture = capture_test_sink,
    })

    testing.expect_value(t, status, Checkpoint_Status.Completed)
    testing.expect_value(t, captured.scenario_step, u32(7))
    testing.expect_value(t, captured.trigger, trigger)
    testing.expect_value(t, captured.presented_frame, u64(100))
    testing.expect_value(t, captured.fixed_step, u64(12))
}

// Verify screenshot targets cannot escape the configured working root.
@(test)
capture_test_rejects_unsafe_path :: proc(t: ^testing.T) {
    coordinator: Coordinator
    testing.expect(t, !checkpoint_request(&coordinator, 1, {}, "../../outside.png"))
    testing.expect(t, !checkpoint_request(&coordinator, 1, {}, "/tmp/outside.png"))
    testing.expect(t, checkpoint_request(
        &coordinator, 1, {}, ".build/run/screen.png"))
}

// Verify a missing display sink produces a durable, attributable failure.
@(test)
capture_test_missing_sink_is_explicit_failure :: proc(t: ^testing.T) {
    coordinator: Coordinator
    testing.expect(t, checkpoint_request(&coordinator, 2, {
        kind = .Scenario_Action, id = 9, generation = 1,
    }))
    testing.expect_value(t,
        checkpoint_after_present(&coordinator, 4, 3, {}),
        Checkpoint_Status.Failed)
    testing.expect_value(t, coordinator.checkpoint.failure_reason,
        Failure_Reason.No_Sink)
}

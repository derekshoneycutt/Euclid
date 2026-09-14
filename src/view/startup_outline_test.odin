package view

import "core:testing"

// Verify the startup silhouette covers every intended stable UI boundary.
@(test)
startup_outline_contains_bounded_nonempty_segments :: proc(t: ^testing.T) {
    outline := startup_outline_create()

    testing.expect_value(t, outline.segment_count, STARTUP_OUTLINE_SEGMENT_CAP)
    testing.expect(t, outline.total_length > 0)
    for index in 0..<outline.segment_count {
        testing.expect(t, outline.segments[index].length > 0)
    }
}

// Verify reveal motion respects clamped loading milestones without overshoot.
@(test)
startup_outline_reveal_tracks_bounded_target :: proc(t: ^testing.T) {
    outline := startup_outline_create()
    startup_outline_set_target(&outline, 0.35)
    startup_outline_advance(&outline, STARTUP_OUTLINE_SECONDS)

    testing.expect_value(t, outline.reveal_distance, outline.total_length * 0.35)
    startup_outline_set_target(&outline, 2)
    startup_outline_advance(&outline, STARTUP_OUTLINE_SECONDS)
    testing.expect_value(t, outline.reveal_distance, outline.total_length)
    testing.expect_value(t, outline.target_distance, outline.total_length)
}
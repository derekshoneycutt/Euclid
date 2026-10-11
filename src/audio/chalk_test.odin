package audio

import "core:testing"

// Verify the gain envelope reaches each target without overshoot.
@(test)
chalk_gain_envelope_is_bounded :: proc(t: ^testing.T) {
    testing.expect_value(t, advance_chalk_gain(0, 1, CHALK_ATTACK_SECONDS), f32(1))
    testing.expect_value(t, advance_chalk_gain(1, 0, CHALK_RELEASE_SECONDS), f32(0))
    testing.expect_value(t, advance_chalk_gain(0.25, 1, 0), f32(0.25))
}

// Verify queue slices wrap only at the authored end-to-start boundary.
@(test)
chalk_loop_segments_wrap_at_source_boundary :: proc(t: ^testing.T) {
    segment := chalk_loop_segment(8, 10, 6)
    testing.expect_value(t, segment.offset, u32(8))
    testing.expect_value(t, segment.count, u32(2))
    testing.expect_value(t, segment.next, u32(0))

    segment = chalk_loop_segment(segment.next, 10, 4)
    testing.expect_value(t, segment.offset, u32(0))
    testing.expect_value(t, segment.count, u32(4))
    testing.expect_value(t, segment.next, u32(4))
}

// Verify semantic drawing activity is idempotent and explicitly replaceable.
@(test)
chalk_drawing_activity_is_binary :: proc(t: ^testing.T) {
    runtime: Chalk_Audio_Runtime
    set_drawing_activity(&runtime, true)
    set_drawing_activity(&runtime, true)
    testing.expect(t, runtime.drawing_active)
    set_drawing_activity(&runtime, false)
    testing.expect(t, !runtime.drawing_active)
}
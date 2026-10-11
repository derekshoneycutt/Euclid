package audio

import audiomodel "model"

Chalk_Audio_Runtime :: audiomodel.Chalk_Audio_Runtime

CHALK_ATTACK_SECONDS :: f32(0.035)
CHALK_RELEASE_SECONDS :: f32(0.080)

Chalk_Loop_Segment :: struct {
    offset: u32,
    count: u32,
    next: u32,
}

// Advance a bounded linear gain envelope without overshooting its target.
advance_chalk_gain :: proc(current, target, dt: f32) -> f32 {
    if dt <= 0 || current == target {
        return current
    }
    duration := target > current ? CHALK_ATTACK_SECONDS : CHALK_RELEASE_SECONDS
    step := dt / duration
    if target > current {
        return min(target, current + step)
    }
    return max(target, current - step)
}

// Select the next contiguous source span, wrapping only at the authored boundary.
chalk_loop_segment :: proc(cursor, total, requested: u32) -> Chalk_Loop_Segment {
    if total == 0 || requested == 0 {
        return {offset = cursor, next = cursor}
    }
    offset := min(cursor, total - 1)
    count := min(requested, total - offset)
    return {offset, count, (offset + count) % total}
}

// Replace activity with the semantic state of the latest accepted animation tick.
set_drawing_activity :: proc "contextless" (
    runtime: ^Chalk_Audio_Runtime, active: bool) {
    if runtime != nil {
        runtime^.drawing_active = active
    }
}

// Advance the display-independent envelope for the current audible policy.
update_chalk_policy :: proc(
    runtime: ^Chalk_Audio_Runtime, enabled, paused: bool, dt: f32) -> f32 {
    if runtime == nil {
        return 0
    }
    target: f32 = enabled && !paused && runtime^.drawing_active ? 1 : 0
    runtime^.gain = advance_chalk_gain(runtime^.gain, target, dt)
    return runtime^.gain
}
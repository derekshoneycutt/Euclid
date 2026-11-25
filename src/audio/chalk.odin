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
        return {
            offset = cursor,
            next = cursor,
        }
    }
    offset := min(cursor, total - 1)
    count := min(requested, total - offset)
    return {offset, count, (offset + count) % total}
}

// Replace activity with the semantic state of the latest accepted animation tick.
set_drawing_activity :: proc "contextless" (
    runtime: ^Chalk_Audio_Runtime, active: bool) {
    if runtime != nil {
        runtime^.julia_drawing_active = active
        update_drawing_activity(runtime)
    }
}

// Replace one native producer's activity without silencing other active sources.
set_native_drawing_activity :: proc "contextless" (
    runtime: ^Chalk_Audio_Runtime, identity: u64, active: bool) -> bool {
    if !native_drawing_activity_can_set(runtime, identity, active) {
        return false
    }
    for &source in runtime^.native_drawing_sources {
        if source.identity == identity {
            source.active = active
            update_drawing_activity(runtime)
            return true
        }
    }
    if !active {
        return true
    }
    free_index := -1
    for &source, index in runtime^.native_drawing_sources {
        if free_index < 0 && !source.active {
            free_index = index
        }
    }
    if free_index < 0 {
        return false
    }
    runtime^.native_drawing_sources[free_index] = {identity, true}
    update_drawing_activity(runtime)
    return true
}

// Report whether a native source identity can be admitted without mutation.
native_drawing_activity_can_set :: proc "contextless" (
    runtime: ^Chalk_Audio_Runtime, identity: u64, active: bool) -> bool {
    if runtime == nil || identity == 0 {
        return false
    }
    if !active {
        return true
    }
    for source in runtime^.native_drawing_sources {
        if source.identity == identity || !source.active {
            return true
        }
    }
    return false
}

// Retire all native contributors during an owning lifecycle transition.
clear_native_drawing_activity :: proc "contextless" (
    runtime: ^Chalk_Audio_Runtime) {
    if runtime == nil {
        return
    }
    for &source in runtime^.native_drawing_sources {
        source.active = false
    }
    update_drawing_activity(runtime)
}

// Derive the audible aggregate from the independent producer states.
update_drawing_activity :: proc "contextless" (
    runtime: ^Chalk_Audio_Runtime) {
    native_active := false
    for source in runtime^.native_drawing_sources {
        native_active = native_active || source.active
    }
    runtime^.drawing_active = runtime^.julia_drawing_active || native_active
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
package main

import "../core"
import "core:log"

// Expose exact bytes of stable owner storage only to the synchronous headless test.
content_notice_observation_bytes :: proc(pointer: ^$T) -> []u8 {
    bytes := cast([^]u8)pointer
    return bytes[:size_of(T)]
}

// Append one observed byte range, or count it during the sizing query.
content_notice_observation_append :: proc(
    destination: []u8, count: ^int, source: []u8) {
    if len(destination) > 0 {
        copy(destination[count^:], source)
    }
    count^ += len(source)
}

// Copy simulation, RNG, geometry, particles, pause, policy payloads, and presentation.
content_notice_observation_copy :: proc(
    state: ^core.Euclid_General_State, destination: []u8) -> int {
    service := state^.julia_runtime_service
    count := 0
    parts := [?][]u8{
        content_notice_observation_bytes(state^.shape_world),
        content_notice_observation_bytes(state^.particle_system),
        content_notice_observation_bytes(&state^.ui_runtime),
        content_notice_observation_bytes(&state^.fixed_step),
        content_notice_observation_bytes(&state^.simulation_time),
        content_notice_observation_bytes(&state^.current_delta_time),
        content_notice_observation_bytes(&state^.accumulator),
        content_notice_observation_bytes(&state^.animation_values),
        content_notice_observation_bytes(&state^.cycle_boundary_generation),
        content_notice_observation_bytes(&service^.presentation_generation),
    }
    for part in parts {
        content_notice_observation_append(destination, &count, part)
    }
    for entry in state^.animation_values.entries {
        if entry.occupied {
            content_notice_observation_append(destination, &count, entry.payload)
        }
    }
    for &slot in service^.view_snapshots {
        content_notice_observation_append(destination, &count,
            content_notice_observation_bytes(&slot))
        content_notice_observation_append(
            destination, &count, slot.presentation_bytes)
    }
    return count
}

// Test-only synchronous copy-out; nil/zero sizes first, invalid input reports failure.
@(export)
copy_animation_notice_observation :: proc "c" (
    state: ^core.Euclid_General_State, destination: ^u8, capacity: i64) -> i64 {
    if state == nil {
        return -1
    }
    context = state^.saved_context
    if state^.shape_world == nil || state^.particle_system == nil ||
        state^.julia_runtime_service == nil || capacity < 0 {
        log.error("animation_notice_observation_invalid_state")
        return -1
    }
    required := content_notice_observation_copy(state, nil)
    if destination == nil && capacity == 0 {
        return i64(required)
    }
    if destination == nil || capacity < i64(required) {
        log.error("animation_notice_observation_capacity")
        return -1
    }
    bytes := cast([^]u8)destination
    return i64(content_notice_observation_copy(state, bytes[:int(capacity)]))
}

package bridge

import rl "vendor:raylib"

import "../core"
import "../particles"

import "core:math"

// Report whether one tool endpoint participates in floor dust contact.
tool_dust_contact_on_floor :: #force_inline proc(position: rl.Vector3) -> bool {
    return f32(math.abs(f64(position.z))) <= FLOOR_CONTACT_Z_EPSILON
}

// Convert a boolean value to its C ABI u8 representation.
to_u8 :: #force_inline proc(value: bool) -> u8 {
    if value {return 1}
    return 0
}

// Queue one tool endpoint at the floor boundary.
queue_tool_dust_contact :: proc(
    state: ^core.Euclid_General_State,
    endpoint: rl.Vector3) {
    if !tool_dust_contact_on_floor(endpoint) {
        return
    }
    accepted := particles.queue_dust_tool_contact(
        state^.particle_system, {endpoint = endpoint, source = .Point})
    assert(accepted)
}

// Queue one compound filled-compass sweep when both legs lie on the floor.
queue_compass_filled_dust_contact :: proc(
    state: ^core.Euclid_General_State,
    previous_first, previous_second, current_first, current_second: rl.Vector3) {
    if !tool_dust_contact_on_floor(previous_first) ||
        !tool_dust_contact_on_floor(previous_second) ||
        !tool_dust_contact_on_floor(current_first) ||
        !tool_dust_contact_on_floor(current_second) {
        queue_tool_dust_contact(state, current_second)
        return
    }
    accepted := particles.queue_dust_tool_contact(state^.particle_system, {
        endpoint = current_second,
        previous_segment_first = previous_first,
        previous_segment_second = previous_second,
        segment_first = current_first,
        segment_second = current_second,
        has_sweep = true,
        source = .Compass_Filled_Sweep,
    })
    assert(accepted)
}

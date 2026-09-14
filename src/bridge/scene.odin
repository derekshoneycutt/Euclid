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

// Queue one tool endpoint and optional compass sweep at the floor boundary.
queue_tool_dust_contact :: proc(
    state: ^core.Euclid_General_State,
    endpoint, first, second: rl.Vector3,
    sweep: bool) {
    if !tool_dust_contact_on_floor(endpoint) {
        return
    }
    floor_sweep := sweep &&
        tool_dust_contact_on_floor(first) && tool_dust_contact_on_floor(second)
    accepted := particles.queue_dust_tool_contact(
        state^.particle_system, {
            endpoint = endpoint, segment_first = first, segment_second = second,
            sample_count = COMPASS_LINE_DUST_SAMPLES, has_sweep = floor_sweep})
    assert(accepted)
}

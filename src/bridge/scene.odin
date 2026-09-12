package bridge

import "../core"
import "../particles"

import "core:math"

// Convert a boolean value to its C ABI u8 representation.
to_u8 :: #force_inline proc(value: bool) -> u8 {
    if value {return 1}
    return 0
}

// Emit floor-contact dust when a transform is close to the drawing plane.
push_dust_if_floor_contact :: proc(
    state: ^core.Euclid_General_State,
    position: core.Vector3) {
    if f32(math.abs(f64(position.z))) <= FLOOR_CONTACT_Z_EPSILON {
        particles.push_dust_away_from_xy(
            state^.particle_system, position.x, position.y)
    }
}

// Emit sampled dust pushes along one floor-level segment.
push_dust_along_floor_segment :: proc(
    state: ^core.Euclid_General_State,
    first, second: core.Vector3) {
    samples := COMPASS_LINE_DUST_SAMPLES
    inv_samples := f32(1.0) / f32(samples)
    for index in 0..<samples {
        interpolation := f32(index) * inv_samples
        x := math.lerp(first.x, second.x, interpolation)
        y := math.lerp(first.y, second.y, interpolation)
        particles.push_dust_away_from_xy(state^.particle_system, x, y)
    }
}

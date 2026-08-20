package view_core

// The isometric projection code is here. We perform precomputations and the projection here.

import "core:simd"
import "core:math"

SCREENSHAKE_TRAUMA_MAX :: 1.0
SCREENSHAKE_DUST_KICK_IMPULSE :: 0.82
SCREENSHAKE_DUST_KICK_BATCH_BASE_IMPULSE :: 0.55
SCREENSHAKE_DUST_KICK_BATCH_GAIN_IMPULSE :: 0.22
SCREENSHAKE_DECAY_RATE :: 8.8
SCREENSHAKE_PHASE_SPEED :: 78.0
SCREENSHAKE_MAX_PIXELS :: 10.0
SCREENSHAKE_TRAUMA_EPSILON :: 0.01
SCREENSHAKE_MAX_TIME :: 0.24

USE_SIMD_BATCH_PROJECTION :: true

Iso_Batch_Projection :: struct {
    xs, ys, zs: []f32,
    out: []Vector2,
    scale: Iso_Scale,
}

//   Report whether the configured build can execute hardware SIMD projection.
simd_batch_projection_available :: proc() -> bool {
    return USE_SIMD_BATCH_PROJECTION && simd.HAS_HARDWARE_SIMD
}

//   Wrap one angle to [0, 2π).
screenshake_normalize_theta :: #force_inline proc(theta: f32) -> f32 {
    tau := f32(2.0 * math.PI)
    if tau <= 0 {
        return theta
    }

    t := math.mod(theta, tau)
    if t < 0 {
        t += tau
    }
    return t
}

//   Reset shake state to a fully at-rest condition.
screenshake_clear :: proc(scale: ^Iso_Scale) {
    scale^.screenshake_trauma = 0
    scale^.screenshake_elapsed = 0
    scale^.screenshake_offset_x = 0
    scale^.screenshake_offset_y = 0
    scale^.screenshake_phase = 0
}

//   Add one single dust-kick trauma impulse.
screenshake_on_dust_kick :: proc(scale: ^Iso_Scale) {
    screenshake_add_trauma(scale, SCREENSHAKE_DUST_KICK_IMPULSE)
}

//   Add one aggregated trauma impulse for batched dust-kick events.
screenshake_on_dust_kick_batch :: proc(scale: ^Iso_Scale, count: int) {
    if count <= 0 {
        return
    }

    count_scale := f32(math.sqrt(f64(count)))
    impulse := SCREENSHAKE_DUST_KICK_BATCH_BASE_IMPULSE +
        SCREENSHAKE_DUST_KICK_BATCH_GAIN_IMPULSE * count_scale
    screenshake_add_trauma(scale, impulse)
}

//   Add trauma, clamp, and restart deterministic shake window.
screenshake_add_trauma :: proc(scale: ^Iso_Scale, impulse: f32) {
    if impulse <= 0 {
        return
    }

    scale^.screenshake_trauma = math.clamp(
        scale^.screenshake_trauma + impulse,
        f32(0.0),
        SCREENSHAKE_TRAUMA_MAX)
    scale^.screenshake_elapsed = 0

    if scale^.screenshake_phase == 0 {
        scale^.screenshake_phase = 0.6180339
    }

    screenshake_set_offsets_from_trauma(scale)
}

//   Rebuild current shake offsets from trauma and phase without advancing time.
screenshake_set_offsets_from_trauma :: proc(scale: ^Iso_Scale) {
    amplitude := SCREENSHAKE_MAX_PIXELS *
        scale^.screenshake_trauma * scale^.screenshake_trauma
    phase_y := screenshake_normalize_theta(
        scale^.screenshake_phase * 1.6180339 + 1.0471976)
    scale^.screenshake_offset_x = amplitude * f32(math.sin(scale^.screenshake_phase))
    scale^.screenshake_offset_y = amplitude * f32(math.sin(phase_y))
}

//   Advance trauma envelope and synthesize per-frame x/y shake offsets.
screenshake_update :: proc(scale: ^Iso_Scale, dt: f32) {
    if scale^.screenshake_trauma <= 0 {
        screenshake_clear(scale)
        return
    }

    scale^.screenshake_elapsed += dt

    decay := f32(math.exp(f64(-SCREENSHAKE_DECAY_RATE * dt)))
    scale^.screenshake_trauma *= decay

    if scale^.screenshake_elapsed >= SCREENSHAKE_MAX_TIME ||
        scale^.screenshake_trauma <= SCREENSHAKE_TRAUMA_EPSILON {
        screenshake_clear(scale)
        return
    }

    scale^.screenshake_phase = screenshake_normalize_theta(
        scale^.screenshake_phase + SCREENSHAKE_PHASE_SPEED * dt)

    screenshake_set_offsets_from_trauma(scale)
}

//   Recompute cached scalar coefficients used by isometric projection.
//
// Parameters:
//   - scale: Projection scale struct to update in place.
//
// Returns:
//   - none.
recompute_iso_scale_precompute :: proc(scale: ^Iso_Scale) {
    scale^.half_scale = scale^.scale * 0.5
    scale^.quarter_scale = scale^.scale * 0.25
}

//   Fast force-inlined projection helper using precomputed coefficients.
//
// Parameters:
//   - coord: World-space isometric coordinate.
//   - scale: Projection scale and precomputed coefficients.
//
// Returns:
//   - screen: 2D screen coordinate.
iso_to_cartesian_components_inline :: #force_inline proc(
    x, y, z: f32,
    scale: Iso_Scale) -> Vector2 {
    return {
        (x - y) * scale.half_scale + scale.x_offset,
        -(x + y) * scale.quarter_scale + scale.y_offset - (z * scale.half_scale),
    }
}

//   Batch-project decomposed x/y/z arrays into screen-space points.
//
// Parameters:
//   - xs: World-space x positions.
//   - ys: World-space y positions.
//   - zs: World-space z positions.
//   - out: Destination array for projected screen coordinates.
//   - scale: Projection scale and precomputed coefficients.
//
// Returns:
//   - count: Number of projected elements written to out.
iso_to_cartesian_components_batch :: proc(
    xs, ys, zs: []f32,
    out: []Vector2,
    scale: Iso_Scale) -> int {
    count := len(xs)
    if len(ys) < count {
        count = len(ys)
    }
    if len(zs) < count {
        count = len(zs)
    }
    if len(out) < count {
        count = len(out)
    }

    for i in 0..<count {
        out[i] = iso_to_cartesian_components_inline(xs[i], ys[i], zs[i], scale)
    }
    return count
}

//   Batch-project decomposed arrays using core:simd f32x4 operations.
store_simd_projection :: #force_inline proc(
    out: []Vector2,
    index: int,
    screen_x, screen_y: simd.f32x4) {

    xs := simd.to_array(screen_x)
    ys := simd.to_array(screen_y)
    for lane in 0..<4 {
        out[index + lane].x = xs[lane]
        out[index + lane].y = ys[lane]
    }
}

//   Batch-project decomposed arrays using core:simd f32x4 operations.
//
// Notes:
//   - Processes 4 elements per iteration with explicit SIMD vectors.
//   - Falls back to scalar semantics for any remainder.
//   - This is basically equal and probably worth having off a lot, but was a first go into simd use
iso_to_cartesian_components_batch_simd :: proc(
    xs, ys, zs: []f32,
    out: []Vector2,
    scale: Iso_Scale) -> int {
    count := len(xs)
    if len(ys) < count {
        count = len(ys)
    }
    if len(zs) < count {
        count = len(zs)
    }
    if len(out) < count {
        count = len(out)
    }

    half_scale := simd.f32x4{
        scale.half_scale, scale.half_scale, scale.half_scale, scale.half_scale}
    quarter_scale := simd.f32x4{
        scale.quarter_scale, scale.quarter_scale,
        scale.quarter_scale, scale.quarter_scale}
    x_offset := simd.f32x4{scale.x_offset, scale.x_offset, scale.x_offset, scale.x_offset}
    y_offset := simd.f32x4{scale.y_offset, scale.y_offset, scale.y_offset, scale.y_offset}

    i := 0
    for i + 3 < count {
        xv := simd.f32x4{xs[i], xs[i + 1], xs[i + 2], xs[i + 3]}
        yv := simd.f32x4{ys[i], ys[i + 1], ys[i + 2], ys[i + 3]}
        zv := simd.f32x4{zs[i], zs[i + 1], zs[i + 2], zs[i + 3]}

        screen_x := (xv - yv) * half_scale + x_offset
        screen_y := -((xv + yv) * quarter_scale) + y_offset - (zv * half_scale)

        store_simd_projection(out, i, screen_x, screen_y)

        i += 4
    }

    for i < count {
        out[i] = iso_to_cartesian_components_inline(xs[i], ys[i], zs[i], scale)
        i += 1
    }
    return count
}

//   Select the configured scalar or SIMD batch projection strategy.
iso_to_cartesian_components_batch_selected :: proc(
    batch: Iso_Batch_Projection,
    use_simd_projection: bool) -> int {
    if use_simd_projection && simd_batch_projection_available() {
        return iso_to_cartesian_components_batch_simd(
            batch.xs, batch.ys, batch.zs, batch.out, batch.scale)
    }
    return iso_to_cartesian_components_batch(
        batch.xs, batch.ys, batch.zs, batch.out, batch.scale)
}

//   Fast force-inlined projection helper using precomputed coefficients.
//
// Parameters:
//   - coord: World-space isometric coordinate.
//   - scale: Projection scale and precomputed coefficients.
//
// Returns:
//   - screen: 2D screen coordinate.
iso_to_cartesian_inline :: #force_inline proc(
    coord: Vector3,
    scale: Iso_Scale) -> Vector2 {
    return iso_to_cartesian_components_inline(coord.x, coord.y, coord.z, scale)
}

//   Project an isometric 3D coordinate into 2D screen space.
//
// Parameters:
//   - coord: World-space isometric coordinate.
//   - scale: Projection scale and screen-offset configuration.
//
// Returns:
//   - screen: 2D screen coordinate.
iso_to_cartesian :: proc(coord : Vector3, scale : Iso_Scale) -> Vector2 {
    return iso_to_cartesian_inline(coord, scale)
}

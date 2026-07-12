package view

// The isometric projection code is here. We perform precomputations and the projection here.

import "core:simd"

USE_SIMD_BATCH_PROJECTION :: true

simd_batch_projection_available :: proc() -> bool {
    return USE_SIMD_BATCH_PROJECTION && simd.HAS_HARDWARE_SIMD
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

    half_scale := simd.f32x4{scale.half_scale, scale.half_scale, scale.half_scale, scale.half_scale}
    quarter_scale := simd.f32x4{scale.quarter_scale, scale.quarter_scale, scale.quarter_scale, scale.quarter_scale}
    x_offset := simd.f32x4{scale.x_offset, scale.x_offset, scale.x_offset, scale.x_offset}
    y_offset := simd.f32x4{scale.y_offset, scale.y_offset, scale.y_offset, scale.y_offset}

    i := 0
    for i + 3 < count {
        xv := simd.f32x4{xs[i], xs[i + 1], xs[i + 2], xs[i + 3]}
        yv := simd.f32x4{ys[i], ys[i + 1], ys[i + 2], ys[i + 3]}
        zv := simd.f32x4{zs[i], zs[i + 1], zs[i + 2], zs[i + 3]}

        screen_x := (xv - yv) * half_scale + x_offset
        screen_y := -((xv + yv) * quarter_scale) + y_offset - (zv * half_scale)

        screen_x_array := simd.to_array(screen_x)
        screen_y_array := simd.to_array(screen_y)

        out[i + 0].x = screen_x_array[0]
        out[i + 0].y = screen_y_array[0]
        out[i + 1].x = screen_x_array[1]
        out[i + 1].y = screen_y_array[1]
        out[i + 2].x = screen_x_array[2]
        out[i + 2].y = screen_y_array[2]
        out[i + 3].x = screen_x_array[3]
        out[i + 3].y = screen_y_array[3]

        i += 4
    }

    for i < count {
        out[i] = iso_to_cartesian_components_inline(xs[i], ys[i], zs[i], scale)
        i += 1
    }
    return count
}

//   Select the active batch projection strategy.
iso_to_cartesian_components_batch_selected :: proc(
    xs, ys, zs: []f32,
    out: []Vector2,
    scale: Iso_Scale,
    use_simd_projection: bool) -> int {
    if use_simd_projection && simd_batch_projection_available() {
        return iso_to_cartesian_components_batch_simd(xs, ys, zs, out, scale)
    }
    return iso_to_cartesian_components_batch(xs, ys, zs, out, scale)
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

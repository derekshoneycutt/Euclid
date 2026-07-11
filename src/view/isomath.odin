package view

// The isometric projection code is here. We perform precomputations and the projection here.

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
iso_to_cartesian_inline :: #force_inline proc(
    coord: Vector3,
    scale: Iso_Scale) -> Vector2 {
    return {
        (coord.x - coord.y) * scale.half_scale + scale.x_offset,
        -(coord.x + coord.y) * scale.quarter_scale + scale.y_offset - (coord.z * scale.half_scale),
    }
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

package view

// Yeah, yeah, it's just one method. But it's used by elements and particles so fuck it all

// Summary:
//   Project an isometric 3D coordinate into 2D screen space.
//
// Parameters:
//   - coord: World-space isometric coordinate.
//   - scale: Projection scale and screen-offset configuration.
//
// Returns:
//   - screen: 2D screen coordinate.
iso_to_cartesian :: proc(coord : Vector3, scale : Iso_Scale) -> Vector2 {
    return { (coord.x - coord.y) * (scale.scale / 2) + scale.x_offset,
        -(coord.x + coord.y) * (scale.scale / 4) + scale.y_offset - (coord.z * scale.scale / 2) }
}

package view

// Yeah, yeah, it's just one method. But it's used by elements and particles so fuck it all

iso_to_cartesian :: proc(coord : Vector3, scale : IsoScale) -> Vector2 {
    return { (coord.x - coord.y) * (scale.Scale / 2) + scale.XOffset,
        -(coord.x + coord.y) * (scale.Scale / 4) + scale.YOffset - (coord.z * scale.Scale / 2) };
}

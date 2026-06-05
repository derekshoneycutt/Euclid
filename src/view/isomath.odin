package view

import ec "../core"
import "core:math"
import "core:math/linalg"

IsoScale :: struct {
    Scale : f32,
    XOffset : f32,
    YOffset : f32
}

iso_to_cartesian :: proc(coord : ec.Vector3, scale : IsoScale) -> ec.Vector2 {
    return { (coord.x - coord.y) * (scale.Scale / 2) + scale.XOffset,
        (coord.x + coord.y) * (scale.Scale / 4) + scale.YOffset - (coord.z * scale.Scale / 2) };
}

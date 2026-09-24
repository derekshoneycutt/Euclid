package view

import particlemodel "../particles/model"

import "core:math"

MAX_PARTICLES :: particlemodel.MAX_PARTICLES
MAX_LOW_PARTICLES :: particlemodel.MAX_LOW_PARTICLES
DUST_TEXTURE_SIZE :: 64
DUST_ATLAS_COLUMNS :: 3
DUST_ATLAS_ROWS :: 3
DUST_ATLAS_VARIANT_COUNT :: particlemodel.DUST_ATLAS_VARIANT_COUNT
DUST_ATLAS_SIZE :: DUST_TEXTURE_SIZE * DUST_ATLAS_COLUMNS
DUST_TEXTURE_SOFT_EDGE_START :: 0.58
DUST_HYPOCYCLOID_SAMPLE_COUNT :: 128

// point_in_polygon tests one point against a closed polygon by ray casting.
point_in_polygon :: proc(point: Vector2, polygon: []Vector2) -> bool {
    inside := false
    previous := len(polygon) - 1
    for index in 0..<len(polygon) {
        current_point := polygon[index]
        previous_point := polygon[previous]
        if (current_point.y > point.y) != (previous_point.y > point.y) &&
            point.x < (previous_point.x - current_point.x) *
                (point.y - current_point.y) /
                (previous_point.y - current_point.y) + current_point.x {
            inside = !inside
        }
        previous = index
    }
    return inside
}

// sample_dust_hypocycloid_points writes one normalized closed atlas contour.
sample_dust_hypocycloid_points :: proc(points: []Vector2, k: int) -> int {
    if k < 3 || len(points) < DUST_HYPOCYCLOID_SAMPLE_COUNT {return 0}
    outer_radius := f32(k - 1)
    frequency := f64(k - 1)
    max_radius: f32
    for index in 0..<DUST_HYPOCYCLOID_SAMPLE_COUNT {
        theta := 2 * math.PI * f64(index) / DUST_HYPOCYCLOID_SAMPLE_COUNT
        x := outer_radius * f32(math.cos(theta)) + f32(math.cos(frequency * theta))
        y := outer_radius * f32(math.sin(theta)) - f32(math.sin(frequency * theta))
        max_radius = max(max_radius, math.sqrt_f32(x * x + y * y))
        points[index] = {x, y}
    }
    if max_radius <= 0 {return 0}
    scale := 0.82 / max_radius
    for &point in points[:DUST_HYPOCYCLOID_SAMPLE_COUNT] {point *= scale}
    return DUST_HYPOCYCLOID_SAMPLE_COUNT
}

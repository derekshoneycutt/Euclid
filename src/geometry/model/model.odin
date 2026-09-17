package geometry_model

// Vector2 stores two f32 coordinates whose space is named by the owning field.
Vector2 :: [2]f32

// Vector3 stores three f32 coordinates whose space is named by the owning field.
Vector3 :: [3]f32

// Rectangle stores an origin and nonnegative extent in its owner's coordinate space.
Rectangle :: struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
}

// rectangle_contains reports half-open containment on both rectangle axes.
rectangle_contains :: #force_inline proc(rect: Rectangle, point: Vector2) -> bool {
    return point.x >= rect.x && point.x < rect.x + rect.width &&
        point.y >= rect.y && point.y < rect.y + rect.height
}
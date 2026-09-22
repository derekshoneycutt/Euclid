package geometry

// Vector2 stores one Euclid-owned two-component floating-point value.
Vector2 :: [2]f32

// Vector3 stores one Euclid-owned three-component floating-point value.
Vector3 :: [3]f32

// Rectangle stores a top-left origin and non-normalized floating-point extents.
Rectangle :: struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
}

#assert(size_of(Vector2) == 2 * size_of(f32))
#assert(size_of(Vector3) == 3 * size_of(f32))
#assert(size_of(Rectangle) == 4 * size_of(f32))

// rectangle_contains reports Raylib-compatible inclusive edge containment.
rectangle_contains :: #force_inline proc(rectangle: Rectangle, point: Vector2) -> bool {
    return point.x >= rectangle.x &&
        point.x <= rectangle.x + rectangle.width &&
        point.y >= rectangle.y &&
        point.y <= rectangle.y + rectangle.height
}

// rectangles_intersect reports visible overlap between positive rectangles.
rectangles_intersect :: #force_inline proc(first, second: Rectangle) -> bool {
    if first.width <= 0 || first.height <= 0 ||
        second.width <= 0 || second.height <= 0 {
        return false
    }
    return first.x < second.x + second.width &&
        first.x + first.width > second.x &&
        first.y < second.y + second.height &&
        first.y + first.height > second.y
}
"""
Shared geometric intersection helpers used by Euclid animation scripts.

`EuclidGeometry` provides stable utility functions for common XY/3D
intersection calculations so content modules can reuse one canonical
implementation instead of duplicating geometry math.
"""
module EuclidGeometry

using LinearAlgebra

export circle_circle_intersections_xy, circle_line_intersections_xy,
    line_intersection_3d

@inline function xy_components(v::Vector{Float32})
    if length(v) < 2
        throw(ArgumentError("Expected a vector with at least x and y components."))
    end
    return v[1], v[2]
end

@inline vec3_xy(x::Float32, y::Float32) = Float32[x, y, 0f0]

"""
    circle_line_intersections_xy(line_a, line_b, center, radius; atol=1f-5)

Find intersection points between an infinite line and a circle in XY.

- `line_a`, `line_b`: two points defining the line (only x/y are used)
- `center`: circle center (only x/y are used)
- `radius`: circle radius

Returns a `Vector{Vector{Float32}}` containing 0-2 points.
Each point is returned as `[x, y, 0f0]`.
"""
function circle_line_intersections_xy(
    line_a::Vector{Float32},
    line_b::Vector{Float32},
    center::Vector{Float32},
    radius::Float32;
    atol::Float32=1f-5)

    if radius < 0f0
        throw(ArgumentError("Circle radius must be non-negative."))
    end

    ax, ay = xy_components(line_a)
    bx, by = xy_components(line_b)
    cx, cy = xy_components(center)

    dx = bx - ax
    dy = by - ay

    a = dx * dx + dy * dy
    if a <= atol
        throw(ArgumentError("Line points must be distinct in XY."))
    end

    fx = ax - cx
    fy = ay - cy
    b = 2f0 * (fx * dx + fy * dy)
    c = fx * fx + fy * fy - radius * radius

    disc = b * b - 4f0 * a * c
    if disc < -atol
        return Vector{Vector{Float32}}()
    end

    if abs(disc) <= atol
        t = -b / (2f0 * a)
        return Vector{Vector{Float32}}([vec3_xy(ax + t * dx, ay + t * dy)])
    end

    sqrt_disc = sqrt(max(0f0, disc))
    t1 = (-b + sqrt_disc) / (2f0 * a)
    t2 = (-b - sqrt_disc) / (2f0 * a)

    p1 = vec3_xy(ax + t1 * dx, ay + t1 * dy)
    p2 = vec3_xy(ax + t2 * dx, ay + t2 * dy)

    return Vector{Vector{Float32}}([p1, p2])
end

"""
    circle_circle_intersections_xy(center1, radius1, center2, radius2; atol=1f-5)

Find intersection points between two circles in XY.

- `center1`, `center2`: circle centers (only x/y are used)
- `radius1`, `radius2`: circle radii

Returns a `Vector{Vector{Float32}}` containing 0-2 points.
Each point is returned as `[x, y, 0f0]`.
"""
function circle_circle_intersections_xy(
    center1::Vector{Float32},
    radius1::Float32,
    center2::Vector{Float32},
    radius2::Float32;
    atol::Float32=1f-5)

    if radius1 < 0f0 || radius2 < 0f0
        throw(ArgumentError("Circle radii must be non-negative."))
    end

    x1, y1 = xy_components(center1)
    x2, y2 = xy_components(center2)

    dx = x2 - x1
    dy = y2 - y1
    d2 = dx * dx + dy * dy
    d = sqrt(d2)

    if d <= atol
        return Vector{Vector{Float32}}()
    end

    sum_r = radius1 + radius2
    diff_r = abs(radius1 - radius2)

    if d > sum_r + atol
        return Vector{Vector{Float32}}()
    end
    if d < diff_r - atol
        return Vector{Vector{Float32}}()
    end

    a = (radius1 * radius1 - radius2 * radius2 + d2) / (2f0 * d)
    h2 = radius1 * radius1 - a * a

    if h2 < -atol
        return Vector{Vector{Float32}}()
    end

    xm = x1 + a * dx / d
    ym = y1 + a * dy / d

    if abs(h2) <= atol
        return Vector{Vector{Float32}}([vec3_xy(xm, ym)])
    end

    h = sqrt(max(0f0, h2))
    rx = -dy * (h / d)
    ry = dx * (h / d)

    p1 = vec3_xy(xm + rx, ym + ry)
    p2 = vec3_xy(xm - rx, ym - ry)

    return Vector{Vector{Float32}}([p1, p2])
end

"""
    line_intersection_3d(a1, a2, b1, b2; atol=1f-4)

Find the intersection point of two infinite 3D lines, where each line is defined
by two points:

- Line A: `a1` to `a2`
- Line B: `b1` to `b2`

All inputs must be `Vector{Float32}` of length 3.

Returns:
- `Vector{Float32}` intersection point when the lines intersect (within `atol`)
- `nothing` when the lines are parallel, skew, or do not intersect
"""
function line_intersection_3d(
    a1::Vector{Float32},
    a2::Vector{Float32},
    b1::Vector{Float32},
    b2::Vector{Float32};
    atol::Float32=1f-4)

    if length(a1) != 3 || length(a2) != 3 || length(b1) != 3 || length(b2) != 3
        throw(ArgumentError("All points must be 3D vectors (length 3)."))
    end

    v1 = a2 - a1
    v2 = b2 - b1
    w0 = a1 - b1

    a = dot(v1, v1)
    b = dot(v1, v2)
    c = dot(v2, v2)
    d = dot(v1, w0)
    e = dot(v2, w0)

    if a <= atol || c <= atol
        throw(ArgumentError("Each line must be defined by two distinct points."))
    end

    denom = a * c - b * b

    if abs(denom) <= atol
        return nothing
    end

    t = (b * e - c * d) / denom
    u = (a * e - b * d) / denom

    p_on_a = a1 .+ t .* v1
    p_on_b = b1 .+ u .* v2

    if norm(p_on_a - p_on_b) <= atol
        return 0.5f0 .* (p_on_a + p_on_b)
    end

    return nothing
end


end

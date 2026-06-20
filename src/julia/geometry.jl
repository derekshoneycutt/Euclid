module EuclidGeometry

using LinearAlgebra

export line_intersection_3d

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

const TransformEps = 1f-6

"""Retain the three authored positions defining one reflected angle marker."""
struct ReflectedAngleMarkerPose
    center::AbstractVector{<:Real}
    start_point::AbstractVector{<:Real}
    end_point::AbstractVector{<:Real}
end

"""
Convert an input vector-like value to a concrete 3D `Float32` vector.

Returns `nothing` when fewer than 3 components are provided.
"""
@inline function as_vec3(value::AbstractVector{<:Real})
    if length(value) < 3
        return nothing
    end
    return Float32[Float32(value[1]), Float32(value[2]), Float32(value[3])]
end


"""
Build a displacement vector from direction and total displacement length.

Returns a zero vector when the direction is degenerate.
"""
@inline function displacement_from_vector_and_length(
    direction::AbstractVector{<:Real}, displacement_length::Real)

    directionvec = Float32[Float32(d) for d in direction]
    direction_length = norm(directionvec)
    if direction_length <= TransformEps
        return Float32[0f0, 0f0, 0f0]
    end
    return (directionvec / direction_length) * Float32(displacement_length)
end


"""
Rotate one point around a 3D axis line using Rodrigues' rotation formula.

Returns `nothing` when the axis line is degenerate.
"""
@inline function rotate_point_about_axis_line(
    point::AbstractVector{<:Real}, axis_a::AbstractVector{<:Real},
    axis_b::AbstractVector{<:Real}, angle::Real)

    pointvec = Float32[Float32(p) for p in point]
    axis_avec = Float32[Float32(a) for a in axis_a]
    axis_bvec = Float32[Float32(b) for b in axis_b]
    axis_direction = axis_bvec - axis_avec
    axis_length = norm(axis_direction)
    if axis_length <= TransformEps
        return nothing
    end

    unit_axis = axis_direction / axis_length
    relative = pointvec - axis_avec
    c = Float32(cos(Float32(angle)))
    s = Float32(sin(Float32(angle)))

    rotatedrelative =
        relative * c +
        cross(unit_axis, relative) * s +
        unit_axis * dot(unit_axis, relative) * (1f0 - c)

    return axis_avec + rotatedrelative
end


"""
Reflect one 3D point across a 2D line on the XY plane.

Only XY components participate in reflection geometry; `z` is preserved.
Returns `nothing` when the line is degenerate.
"""
@inline function reflect_point_xy_across_line(
    point::AbstractVector{<:Real}, line_a::AbstractVector{<:Real},
    line_b::AbstractVector{<:Real})

    pointvec = Float32[Float32(p) for p in point]
    line_avec = Float32[Float32(a) for a in line_a]
    line_bvec = Float32[Float32(b) for b in line_b]
    line_dx = line_bvec[1] - line_avec[1]
    line_dy = line_bvec[2] - line_avec[2]
    line_length = Float32(hypot(line_dx, line_dy))
    if line_length <= TransformEps
        return nothing
    end

    ux = line_dx / line_length
    uy = line_dy / line_length
    rel_x = pointvec[1] - line_avec[1]
    rel_y = pointvec[2] - line_avec[2]
    proj = rel_x * ux + rel_y * uy
    proj_x = proj * ux
    proj_y = proj * uy
    perp_x = rel_x - proj_x
    perp_y = rel_y - proj_y

    return Float32[
        line_avec[1] + (proj_x - perp_x),
        line_avec[2] + (proj_y - perp_y),
        pointvec[3],
    ]
end


"""
Choose the reflection half-turn branch with greater positive z lift.

Returns `nothing` when axis rotation cannot be resolved.
"""
@inline function reflection_arc_point_above_surface(
    start_on_plane::AbstractVector{<:Real},
    line_a::AbstractVector{<:Real},
    line_b::AbstractVector{<:Real},
    angle::Real)

    rotated_pos = rotate_point_about_axis_line(start_on_plane, line_a, line_b, angle)
    rotated_neg = rotate_point_about_axis_line(start_on_plane, line_a, line_b, -angle)
    if rotated_pos === nothing || rotated_neg === nothing
        return nothing
    end

    return rotated_pos[3] >= rotated_neg[3] ? rotated_pos : rotated_neg
end


"""
Choose the reflection half-turn branch with greater negative z lift.

Returns `nothing` when axis rotation cannot be resolved.
"""
@inline function reflection_arc_point_below_surface(
    start_on_plane::AbstractVector{<:Real},
    line_a::AbstractVector{<:Real},
    line_b::AbstractVector{<:Real},
    angle::Real)

    rotated_pos = rotate_point_about_axis_line(start_on_plane, line_a, line_b, angle)
    rotated_neg = rotate_point_about_axis_line(start_on_plane, line_a, line_b, -angle)
    if rotated_pos === nothing || rotated_neg === nothing
        return nothing
    end

    return rotated_pos[3] <= rotated_neg[3] ? rotated_pos : rotated_neg
end


"""
Translate one point by a direct displacement vector over normalized time.

--------

Parameters:

- `state_ptr` : Pointer to Euclid host state.
- `point_id` : Target point id to update.
- `start_position` : Initial `[x, y, z]` position for this animation step.
- `displacement` : Final displacement vector applied at `t = 1`.
- `current_time` : Elapsed time value for this step.
- `total_duration` : Total step duration in the same unit as `current_time`.

Returns:

- Bridge status code (`BRIDGE_STATUS_OK` on success).
"""
function transform_translate_point(
    state_ptr::Ptr{Cvoid},
    point_id::Integer,
    start_position::AbstractVector{<:Real},
    displacement::AbstractVector{<:Real},
    current_time::Real,
    total_duration::Real)

    start_vec = as_vec3(start_position)
    displacement_vec = as_vec3(displacement)
    if start_vec === nothing || displacement_vec === nothing
        return OdinJuliaBridge.BRIDGE_STATUS_INVALID_ARGUMENT
    end

    t = normalized_progress(current_time, total_duration)
    point = start_vec + displacement_vec * t
    return OdinJuliaBridge.set_point_position_status(state_ptr, point_id, point)
end


"""
Translate one point by direction and scalar displacement length over time.

The direction is normalized internally; `displacement_length` controls total
distance traveled at `t = 1`.

--------

Parameters:

- `state_ptr` : Pointer to Euclid host state.
- `point_id` : Target point id to update.
- `start_position` : Initial `[x, y, z]` position for this animation step.
- `direction` : Direction vector for translation.
- `displacement_length` : Total displacement magnitude at `t = 1`.
- `current_time` : Elapsed time value for this step.
- `total_duration` : Total step duration in the same unit as `current_time`.

Returns:

- Bridge status code (`BRIDGE_STATUS_OK` on success).
"""
function transform_translate_point(
    state_ptr::Ptr{Cvoid},
    point_id::Integer,
    start_position::AbstractVector{<:Real},
    direction::AbstractVector{<:Real},
    displacement_length::Real,
    current_time::Real,
    total_duration::Real)

    directionvec = as_vec3(direction)
    if directionvec === nothing
        return OdinJuliaBridge.BRIDGE_STATUS_INVALID_ARGUMENT
    end

    displacement_vec = displacement_from_vector_and_length(
        directionvec, displacement_length)
    return transform_translate_point(
        state_ptr,
        point_id,
        start_position,
        displacement_vec,
        current_time,
        total_duration)
end


"""
Rotate one point around a 3D axis line defined by two points.

--------

Parameters:

- `state_ptr` : Pointer to Euclid host state.
- `point_id` : Target point id to update.
- `start_position` : Initial `[x, y, z]` position for this animation step.
- `axis_point_a` : First point on the rotation axis line.
- `axis_point_b` : Second point on the rotation axis line.
- `theta` : Total rotation angle in radians at `t = 1`.
- `current_time` : Elapsed time value for this step.
- `total_duration` : Total step duration in the same unit as `current_time`.

Returns:

- Bridge status code (`BRIDGE_STATUS_OK` on success).
"""
function transform_rotate_point(
    state_ptr::Ptr{Cvoid},
    point_id::Integer,
    start_position::AbstractVector{<:Real},
    axis_point_a::AbstractVector{<:Real},
    axis_point_b::AbstractVector{<:Real},
    theta::Real,
    current_time::Real,
    total_duration::Real)

    start_vec = as_vec3(start_position)
    axis_a = as_vec3(axis_point_a)
    axis_b = as_vec3(axis_point_b)
    if start_vec === nothing || axis_a === nothing || axis_b === nothing
        return OdinJuliaBridge.BRIDGE_STATUS_INVALID_ARGUMENT
    end

    t = normalized_progress(current_time, total_duration)
    frame_angle = Float32(theta) * t
    rotated = rotate_point_about_axis_line(start_vec, axis_a, axis_b, frame_angle)
    if rotated === nothing
        return OdinJuliaBridge.BRIDGE_STATUS_INVALID_ARGUMENT
    end

    return OdinJuliaBridge.set_point_position_status(state_ptr, point_id, rotated)
end


"""
Rotate one point around the world X axis through the origin.

Convenience overload for `transform_rotate_point`.
"""
function transform_rotate_point_x(
    state_ptr::Ptr{Cvoid},
    point_id::Integer,
    start_position::AbstractVector{<:Real},
    theta::Real,
    current_time::Real,
    total_duration::Real)

    return transform_rotate_point(
        state_ptr,
        point_id,
        start_position,
        Float32[0f0, 0f0, 0f0],
        Float32[1f0, 0f0, 0f0],
        theta,
        current_time,
        total_duration)
end


"""
Rotate one point around the world Y axis through the origin.

Convenience overload for `transform_rotate_point`.
"""
function transform_rotate_point_y(
    state_ptr::Ptr{Cvoid},
    point_id::Integer,
    start_position::AbstractVector{<:Real},
    theta::Real,
    current_time::Real,
    total_duration::Real)

    return transform_rotate_point(
        state_ptr,
        point_id,
        start_position,
        Float32[0f0, 0f0, 0f0],
        Float32[0f0, 1f0, 0f0],
        theta,
        current_time,
        total_duration)
end


"""
Rotate one point around the world Z axis through the origin.

Convenience overload for `transform_rotate_point`.
"""
function transform_rotate_point_z(
    state_ptr::Ptr{Cvoid},
    point_id::Integer,
    start_position::AbstractVector{<:Real},
    theta::Real,
    current_time::Real,
    total_duration::Real)

    return transform_rotate_point(
        state_ptr,
        point_id,
        start_position,
        Float32[0f0, 0f0, 0f0],
        Float32[0f0, 0f0, 1f0],
        theta,
        current_time,
        total_duration)
end


"""
Reflect one point across a 2D line on XY, preserving the original `z`.

For this first implementation, both line points must lie on `z = 0`.
The animation path uses a half-turn around the reflection line so points lift
off the surface during the transition and land on the reflected endpoint.

--------

Parameters:

- `state_ptr` : Pointer to Euclid host state.
- `point_id` : Target point id to update.
- `start_position` : Initial `[x, y, z]` position for this animation step.
- `line_point_a` : First point on the XY reflection axis (`z = 0`).
- `line_point_b` : Second point on the XY reflection axis (`z = 0`).
- `current_time` : Elapsed time value for this step.
- `total_duration` : Total step duration in the same unit as `current_time`.

Returns:

- Bridge status code (`BRIDGE_STATUS_OK` on success).
"""
function transform_reflect2d_point(
    state_ptr::Ptr{Cvoid},
    point_id::Integer,
    start_position::AbstractVector{<:Real},
    line_point_a::AbstractVector{<:Real},
    line_point_b::AbstractVector{<:Real},
    current_time::Real,
    total_duration::Real)

    start_vec = as_vec3(start_position)
    line_a = as_vec3(line_point_a)
    line_b = as_vec3(line_point_b)
    if start_vec === nothing || line_a === nothing || line_b === nothing
        return OdinJuliaBridge.BRIDGE_STATUS_INVALID_ARGUMENT
    end

    if abs(line_a[3]) > TransformEps || abs(line_b[3]) > TransformEps
        return OdinJuliaBridge.BRIDGE_STATUS_INVALID_ARGUMENT
    end

    t = normalized_progress(current_time, total_duration)
    start_on_plane = Float32[start_vec[1], start_vec[2], 0f0]
    angle = Float32(pi) * t
    rotated = reflection_arc_point_above_surface(start_on_plane, line_a, line_b, angle)
    if rotated === nothing
        return OdinJuliaBridge.BRIDGE_STATUS_INVALID_ARGUMENT
    end

    point = Float32[rotated[1], rotated[2], start_vec[3] + rotated[3]]
    return OdinJuliaBridge.set_point_position_status(state_ptr, point_id, point)
end


"""
Reflect one point across a 2D line on XY, preserving the original `z`.

This variant follows the negative-Z half-turn branch during the transition.
"""
function transform_reflect2d_point_negative(
    state_ptr::Ptr{Cvoid},
    point_id::Integer,
    start_position::AbstractVector{<:Real},
    line_point_a::AbstractVector{<:Real},
    line_point_b::AbstractVector{<:Real},
    current_time::Real,
    total_duration::Real)

    start_vec = as_vec3(start_position)
    line_a = as_vec3(line_point_a)
    line_b = as_vec3(line_point_b)
    if start_vec === nothing || line_a === nothing || line_b === nothing
        return OdinJuliaBridge.BRIDGE_STATUS_INVALID_ARGUMENT
    end

    if abs(line_a[3]) > TransformEps || abs(line_b[3]) > TransformEps
        return OdinJuliaBridge.BRIDGE_STATUS_INVALID_ARGUMENT
    end

    t = normalized_progress(current_time, total_duration)
    start_on_plane = Float32[start_vec[1], start_vec[2], 0f0]
    angle = Float32(pi) * t
    rotated = reflection_arc_point_below_surface(start_on_plane, line_a, line_b, angle)
    if rotated === nothing
        return OdinJuliaBridge.BRIDGE_STATUS_INVALID_ARGUMENT
    end

    point = Float32[rotated[1], rotated[2], start_vec[3] + rotated[3]]
    return OdinJuliaBridge.set_point_position_status(state_ptr, point_id, point)
end


"""
Reflect one point across the X axis (`y = 0`) on XY.

Convenience overload for `transform_reflect2d_point`.
"""
function transform_reflect2d_point_x_axis(
    state_ptr::Ptr{Cvoid},
    point_id::Integer,
    start_position::AbstractVector{<:Real},
    current_time::Real,
    total_duration::Real)

    return transform_reflect2d_point(
        state_ptr,
        point_id,
        start_position,
        Float32[0f0, 0f0, 0f0],
        Float32[1f0, 0f0, 0f0],
        current_time,
        total_duration)
end


"""
Reflect one point across the Y axis (`x = 0`) on XY.

Convenience overload for `transform_reflect2d_point`.
"""
function transform_reflect2d_point_y_axis(
    state_ptr::Ptr{Cvoid},
    point_id::Integer,
    start_position::AbstractVector{<:Real},
    current_time::Real,
    total_duration::Real)

    return transform_reflect2d_point(
        state_ptr,
        point_id,
        start_position,
        Float32[0f0, 0f0, 0f0],
        Float32[0f0, 1f0, 0f0],
        current_time,
        total_duration)
end


"""
Reflect one point across the diagonal line `y = x` on XY.

Convenience overload for `transform_reflect2d_point`.
"""
function transform_reflect2d_point_diag_pos(
    state_ptr::Ptr{Cvoid},
    point_id::Integer,
    start_position::AbstractVector{<:Real},
    current_time::Real,
    total_duration::Real)

    return transform_reflect2d_point(
        state_ptr,
        point_id,
        start_position,
        Float32[0f0, 0f0, 0f0],
        Float32[1f0, 1f0, 0f0],
        current_time,
        total_duration)
end


"""
Reflect one point across the diagonal line `y = -x` on XY.

Convenience overload for `transform_reflect2d_point`.
"""
function transform_reflect2d_point_diag_neg(
    state_ptr::Ptr{Cvoid},
    point_id::Integer,
    start_position::AbstractVector{<:Real},
    current_time::Real,
    total_duration::Real)

    return transform_reflect2d_point(
        state_ptr,
        point_id,
        start_position,
        Float32[0f0, 0f0, 0f0],
        Float32[1f0, -1f0, 0f0],
        current_time,
        total_duration)
end


"""
Compute reflected target pose for a filled angle marker on XY.

When `swap_boundary_points` is true, reflected start/end are swapped so filled
sectors stay on the interior side after reflection.
"""
function reflected_angle_marker_pose_xy(
    center::AbstractVector{<:Real},
    start_point::AbstractVector{<:Real},
    end_point::AbstractVector{<:Real},
    line_point_a::AbstractVector{<:Real},
    line_point_b::AbstractVector{<:Real};
    swap_boundary_points::Bool=true)

    reflected_center = reflect_point_xy_across_line(center, line_point_a, line_point_b)
    reflected_start =
        reflect_point_xy_across_line(start_point, line_point_a, line_point_b)
    reflected_end = reflect_point_xy_across_line(end_point, line_point_a, line_point_b)

    if reflected_center === nothing || reflected_start === nothing ||
        reflected_end === nothing
        return nothing
    end

    if swap_boundary_points
        return ReflectedAngleMarkerPose(
            reflected_center, reflected_end, reflected_start)
    end

    return ReflectedAngleMarkerPose(
        reflected_center, reflected_start, reflected_end)
end


"""Return one point's animated 3D reflection-arc position for current progress."""
@inline function reflected_arc_point_xy_progress(
    start_position::AbstractVector{<:Real},
    line_point_a::AbstractVector{<:Real},
    line_point_b::AbstractVector{<:Real},
    current_time::Real,
    total_duration::Real)

    start_vec = as_vec3(start_position)
    line_a = as_vec3(line_point_a)
    line_b = as_vec3(line_point_b)
    if start_vec === nothing || line_a === nothing || line_b === nothing
        return nothing
    end

    if abs(line_a[3]) > TransformEps || abs(line_b[3]) > TransformEps
        return nothing
    end

    t = normalized_progress(current_time, total_duration)
    start_on_plane = Float32[start_vec[1], start_vec[2], 0f0]
    angle = Float32(pi) * t
    rotated = reflection_arc_point_above_surface(start_on_plane, line_a, line_b, angle)
    if rotated === nothing
        return nothing
    end

    return Float32[rotated[1], rotated[2], start_vec[3] + rotated[3]]
end


"""Return CCW sweep angle in `[0, 2pi)` from `start_point` to `end_point` around `center`."""
@inline function ccw_sweep_xy(
    center::AbstractVector{<:Real},
    start_point::AbstractVector{<:Real},
    end_point::AbstractVector{<:Real})

    cx = Float32(center[1])
    cy = Float32(center[2])
    sx = Float32(start_point[1]) - cx
    sy = Float32(start_point[2]) - cy
    ex = Float32(end_point[1]) - cx
    ey = Float32(end_point[2]) - cy

    start_norm = Float32(hypot(sx, sy))
    end_norm = Float32(hypot(ex, ey))
    if start_norm <= TransformEps || end_norm <= TransformEps
        return 0f0
    end

    cross_z = sx * ey - sy * ex
    dot_xy = sx * ex + sy * ey
    sweep = Float32(atan(cross_z, dot_xy))
    if sweep < 0f0
        sweep += Float32(2f0 * pi)
    end
    return sweep
end


"""
Animate a filled angle marker through 3D reflection arc motion.

This animates one arc host with the same half-turn lift used by
`transform_reflect2d_point` while preserving interior sector orientation.
"""
function animate_reflect2d_filled_angle_marker(
    state_ptr::Ptr{Cvoid},
    marker_host_id::Integer;
    start_center::AbstractVector{<:Real}=[0f0,0f0,0f0],
    start_point::AbstractVector{<:Real}=[0f0,0f0,0f0],
    end_point::AbstractVector{<:Real}=[0f0,0f0,0f0],
    line_point_a::AbstractVector{<:Real}=[0f0,0f0,0f0],
    line_point_b::AbstractVector{<:Real}=[0f0,0f0,0f0],
    current_time::Real=0f0,
    total_duration::Real=0f0,
    preserve_interior::Bool=true)

    # TODO : This looks like ass lmfao we should fix this.

    reflected_center = reflected_arc_point_xy_progress(
        start_center, line_point_a, line_point_b, current_time, total_duration)
    reflected_start = reflected_arc_point_xy_progress(
        start_point, line_point_a, line_point_b, current_time, total_duration)
    reflected_end = reflected_arc_point_xy_progress(
        end_point, line_point_a, line_point_b, current_time, total_duration)

    if reflected_center === nothing || reflected_start === nothing ||
        reflected_end === nothing
        return OdinJuliaBridge.BRIDGE_STATUS_INVALID_ARGUMENT
    end

    start_out, end_out = reflected_marker_endpoints(
        reflected_center, reflected_start, reflected_end, preserve_interior)

    host_status = OdinJuliaBridge.set_point_position_status(
        state_ptr, marker_host_id, reflected_center)
    if host_status != OdinJuliaBridge.BRIDGE_STATUS_OK
        return host_status
    end
    radius = Float32(hypot(
        start_out[1] - reflected_center[1], start_out[2] - reflected_center[2]))
    start_theta = Float32(atan(
        start_out[2] - reflected_center[2], start_out[1] - reflected_center[1]))
    sweep_theta = ccw_sweep_xy(reflected_center, start_out, end_out)
    return OdinJuliaBridge.set_arc_geometry(
        state_ptr, marker_host_id, radius, start_theta, sweep_theta)
end


"""Order reflected marker endpoints to preserve the interior sweep direction."""
function reflected_marker_endpoints(
    reflected_center::AbstractVector{<:Real}, reflected_start::AbstractVector{<:Real},
    reflected_end::AbstractVector{<:Real}, preserve_interior::Bool)

    if preserve_interior
        sweep = ccw_sweep_xy(reflected_center, reflected_start, reflected_end)
        if sweep > Float32(pi)
            return reflected_end, reflected_start
        end
    end
    return reflected_start, reflected_end
end

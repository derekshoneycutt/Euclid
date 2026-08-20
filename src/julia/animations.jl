"""
Reusable animation-motion helpers for EuclidApp scripts.

`EuclidAnimations` provides shared pen/compass motion primitives and higher-level
draw helpers that orchestrate bridge calls through `OdinJuliaBridge`. Animation
modules should consume this API to keep motion pacing and tool behavior consistent
across Euclid content and scratchpad workflows.
"""
module EuclidAnimations

using ..OdinJuliaBridge

using LinearAlgebra

export animate_pen_descend, animate_pen_rise, animate_compass_descend,
    animate_compass_rise, animate_pen_tilt, animate_pen_cone, animate_pen_drag,
    animate_pen_arcmove, animate_compass_arcmove, animate_highlight_point,
    animate_extend_line, animate_pen_tilt_and_drag, animate_draw_point,
    animate_draw_line,
    animate_draw_filledcircle,
    animate_draw_two_line_segments,
    animate_draw_circle, animate_compass_fill_arc_highlight,
    animate_compass_arc_highlight,
    animate_repl_draw_point, animate_repl_draw_line,
    animate_repl_draw_circle, animate_repl_draw_filledcircle,
    transform_translate_point,
    transform_rotate_point, transform_rotate_point_x,
    transform_rotate_point_y, transform_rotate_point_z,
    transform_reflect2d_point, transform_reflect2d_point_negative,
    transform_reflect2d_point_x_axis,
    transform_reflect2d_point_y_axis, transform_reflect2d_point_diag_pos,
    transform_reflect2d_point_diag_neg,
    reflected_angle_marker_pose_xy,
    animate_reflect2d_filled_angle_marker

const PenLength = 0.14f0

const PenStraightFloorAngle = π / 2f0

const PenDrawLineAngle = π / 3f0

const PenConeRadius = 0.02f0
const PenConeSpinSpeed = 6f0
const PenConeTipHeight =
    Float32(sqrt(PenLength * PenLength - PenConeRadius * PenConeRadius))
const PenConeFloorAngle = Float32(atan(PenConeTipHeight, PenConeRadius))
const PenConeSimulatedDrawSpeed = 3f0

const TiltToConeDuration = 0.15f0
const GroundTrailDuration = 0.7f0
const GroundTrailEndTime = TiltToConeDuration + GroundTrailDuration

const TiltToLineDuration = 0.15f0
const GroundLineDuration = 0.7f0
const GroundLineEndTime = TiltToLineDuration + GroundLineDuration

const MarkerRadialTrailSamples = 8f0

const ReplToolTravelTopZ = 1.4f0
const ReplDescendShare = 0.2f0
const ReplDrawShare = 0.6f0
const TransformEps = 1f-6

struct ReflectedAngleMarkerPose
    center::AbstractVector{<:Real}
    start_point::AbstractVector{<:Real}
    end_point::AbstractVector{<:Real}
end


"""
Normalize elapsed time into `[0, 1]` progress.

Treats non-positive duration as an immediate completion (`1f0`).
"""
@inline function normalized_progress(current_time::Real, total_duration::Real)
    if total_duration <= 0
        return 1f0
    end
    return clamp(Float32(current_time / total_duration), 0f0, 1f0)
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

This animates the center/start/end point IDs with the same half-turn lift used
by `transform_reflect2d_point`, and optionally swaps start/end IDs each frame
to preserve interior sector orientation after reflection.
"""
function animate_reflect2d_filled_angle_marker(
    state_ptr::Ptr{Cvoid},
    marker_host_id::Integer,
    marker_start_id::Integer,
    marker_end_id::Integer;
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

    return write_marker_point_positions(
        state_ptr, marker_host_id, marker_start_id, marker_end_id,
        reflected_center, start_out, end_out)
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


"""Write the three reflected marker point positions, returning the first failure."""
function write_marker_point_positions(
    state_ptr::Ptr{Cvoid},
    marker_host_id::Integer, marker_start_id::Integer, marker_end_id::Integer,
    reflected_center::AbstractVector{<:Real}, start_out::AbstractVector{<:Real},
    end_out::AbstractVector{<:Real})

    host_status = OdinJuliaBridge.set_point_position_status(
        state_ptr, marker_host_id, reflected_center)
    if host_status != OdinJuliaBridge.BRIDGE_STATUS_OK
        return host_status
    end

    start_status = OdinJuliaBridge.set_point_position_status(
        state_ptr, marker_start_id, start_out)
    if start_status != OdinJuliaBridge.BRIDGE_STATUS_OK
        return start_status
    end

    return OdinJuliaBridge.set_point_position_status(state_ptr, marker_end_id, end_out)
end


"""
Place a pen at the given floor and swing angles, updating its pose each frame.
"""
function place_pen_at_angles(
    state_ptr::Ptr{Cvoid}, pen_x::Real, pen_y::Real, base_z::Real,
    floor_angle::Real, azimuth::Real)

    horizontal_length = PenLength * Float32(cos(floor_angle))
    vertical_length = PenLength * Float32(sin(floor_angle))

    tip_x = pen_x + horizontal_length * Float32(cos(azimuth))
    tip_y = pen_y + horizontal_length * Float32(sin(azimuth))
    tip_z = base_z + vertical_length

    OdinJuliaBridge.lock_pen_joint1(state_ptr, pen_x, pen_y, base_z)
    OdinJuliaBridge.move_pen_joint2(state_ptr, tip_x, tip_y, tip_z)
end


function place_pen_at_angles(
    state_ptr::Ptr{Cvoid}, penpos::AbstractVector{<:Real},
    floor_angle::Real, azimuth::Real)

    place_pen_at_angles(state_ptr, penpos[1], penpos[2], penpos[3], floor_angle, azimuth)
end


"""
Emit a trailing filled-circle radius particle burst for the current frame.
"""
function emit_filledcircle_radius_trail(
    state_ptr::Ptr{Cvoid}, joint_point::AbstractVector{<:Real},
    end_point::AbstractVector{<:Real}, color)

    for i in 0:MarkerRadialTrailSamples
        t = (Float32(i) / Float32(MarkerRadialTrailSamples)) +
            Float32(rand() - 0.5f0) / MarkerRadialTrailSamples
        markerpoint = joint_point + (end_point - joint_point) * t
        OdinJuliaBridge.emit_trailing_particle(state_ptr, markerpoint, color)
    end
end



"""
Animate pen descent from a raised Z offset to the drawing plane.

--------

Parameters:

- state_ptr : Pointer to the Euclid application state.
- timer : Elapsed animation time.
- duration : Total duration for the descend phase.
- topz : Starting Z height above the drawing plane.
- penx : Pen base X position.
- peny : Pen base Y position.

Returns:

- nothing
"""
function animate_pen_descend(
    state_ptr::Ptr{Cvoid},
    timer::Real, duration::Real,
    topz::Real, penx::Real, peny::Real)

    t = clamp(timer / duration, 0f0, 1f0)
    penz = topz - (topz * t)
    OdinJuliaBridge.lock_pen_joint1(state_ptr, penx, peny, penz)
    OdinJuliaBridge.move_pen_joint2(state_ptr, penx, peny, penz + PenLength)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, :white)
    OdinJuliaBridge.show_pen(state_ptr)
end

"""
Animate compass descent from a raised Z offset to the drawing plane.

--------

Parameters:

- state_ptr : Pointer to the Euclid application state.
- timer : Elapsed animation time.
- duration : Total duration for the descend phase.
- topz : Starting Z height above the drawing plane.
- joint1x : Compass joint 1 X position.
- joint1y : Compass joint 1 Y position.
- joint2x : Compass joint 2 X position.
- joint2y : Compass joint 2 Y position.

Returns:

- nothing
"""
function animate_compass_descend(
    state_ptr::Ptr{Cvoid},
    timer::Real, duration::Real,
    topz::Real, joint1x::Real, joint1y::Real,
    joint2x::Real, joint2y::Real)

    t = clamp(timer / duration, 0f0, 1f0)
    tip_z = topz + (0f0 - topz) * t
    OdinJuliaBridge.set_compass_active(state_ptr, 0, :white)
    OdinJuliaBridge.lock_compass_joint1(
        state_ptr, joint1x, joint1y, tip_z, sweep = false)
    OdinJuliaBridge.lock_compass_joint2(
        state_ptr, joint2x, joint2y, tip_z, sweep = false)
    OdinJuliaBridge.show_compass(state_ptr)
end

"""
Animate pen rise from the drawing plane to a raised Z offset.

--------

Parameters:

- state_ptr : Pointer to the Euclid application state.
- timer : Elapsed animation time.
- duration : Total duration for the rise phase.
- startz : Start Z height above the drawing plane where the pen begins.
- topz : Target Z height above the drawing plane.
- penx : Pen base X position.
- peny : Pen base Y position.

Returns:

- nothing
"""
function animate_pen_rise(
    state_ptr::Ptr{Cvoid},
    timer::Real, duration::Real,
    topz::Real, penx::Real, peny::Real)

    t = clamp(timer / duration, 0f0, 1f0)
    penz = topz * t
    OdinJuliaBridge.lock_pen_joint1(state_ptr, penx, peny, penz)
    OdinJuliaBridge.move_pen_joint2(state_ptr, penx, peny, penz + PenLength)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, :white)
    OdinJuliaBridge.show_pen(state_ptr)
end
function animate_pen_rise(
    state_ptr::Ptr{Cvoid},
    timer::Real, duration::Real,
    startz::Real, topz::Real, penx::Real, peny::Real)

    t = clamp(timer / duration, 0f0, 1f0)
    diffz = topz - startz
    penzoffset = diffz * t
    penz = startz + penzoffset
    OdinJuliaBridge.lock_pen_joint1(state_ptr, penx, peny, penz)
    OdinJuliaBridge.move_pen_joint2(state_ptr, penx, peny, penz + PenLength)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, :white)
    OdinJuliaBridge.show_pen(state_ptr)
end

"""
Animate compass rise from the drawing plane to a raised Z offset.

--------

Parameters:

- state_ptr : Pointer to the Euclid application state.
- timer : Elapsed animation time.
- duration : Total duration for the rise phase.
- topz : Target Z height above the drawing plane.
- joint1x : Compass joint 1 X position.
- joint1y : Compass joint 1 Y position.
- joint2x : Compass joint 2 X position.
- joint2y : Compass joint 2 Y position.

Returns:

- nothing
"""
function animate_compass_rise(
    state_ptr::Ptr{Cvoid},
    timer::Real, duration::Real,
    topz::Real, joint1x::Real, joint1y::Real,
    joint2x::Real, joint2y::Real)

    t = clamp(timer / duration, 0f0, 1f0)
    tip_z = 0f0 + (topz - 0f0) * t

    OdinJuliaBridge.lock_compass_joint1(
        state_ptr, joint1x, joint1y, tip_z, sweep = false)
    OdinJuliaBridge.lock_compass_joint2(
        state_ptr, joint2x, joint2y, tip_z, sweep = false)
    OdinJuliaBridge.set_compass_active(state_ptr, 0, :white)
    OdinJuliaBridge.show_compass(state_ptr)
end

"""
Animate pen floor-angle interpolation at a fixed pen base position.

--------

Parameters:

- state_ptr : Pointer to the Euclid application state.
- timer : Elapsed animation time.
- duration : Total duration for the tilt phase.
- penx : Pen base X position.
- peny : Pen base Y position.
- penz : Pen base Z position.
- startθ : Starting floor angle in radians.
- endθ : Ending floor angle in radians.
- azimuth : Pen azimuth angle in radians.

Returns:

- nothing
"""
function animate_pen_tilt(
    state_ptr::Ptr{Cvoid},
    timer::Real, duration::Real,
    penpos::AbstractVector{<:Real},
    startθ::Real, endθ::Real, azimuth::Real)

    t = clamp(timer / duration, 0f0, 1f0)
    floor_angle = startθ + (endθ - startθ) * t

    place_pen_at_angles(state_ptr, penpos, floor_angle, azimuth)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, :white)
    OdinJuliaBridge.show_pen(state_ptr)
end

"""
Animate continuous conical pen motion around a fixed pen base position.

--------

Parameters:

- state_ptr : Pointer to the Euclid application state.
- timer : Elapsed animation time.
- penx : Pen base X position.
- peny : Pen base Y position.
- penz : Pen base Z position.
- pen_floor_angle : Pen floor angle in radians.
- spin_speed : Angular spin speed in radians per second.

Returns:

- nothing
"""
function animate_pen_cone(
    state_ptr::Ptr{Cvoid},
    timer::Real,
    penx::Real, peny::Real, penz::Real, pen_floor_angle::Real,
    spin_speed::Real)

    animate_pen_cone(state_ptr, timer, [penx, peny, penz], pen_floor_angle, spin_speed)
end

function animate_pen_cone(
    state_ptr::Ptr{Cvoid},
    timer::Real,
    penpos::AbstractVector{<:Real}, pen_floor_angle::Real,
    spin_speed::Real)

    θ = timer * spin_speed

    place_pen_at_angles(state_ptr, penpos, pen_floor_angle, θ)
    OdinJuliaBridge.show_pen(state_ptr)
end

"""
Animate pen drag from start to end while emitting trailing particles.

--------

Parameters:

- state_ptr : Pointer to the Euclid application state.
- timer : Elapsed animation time.
- duration : Total duration for the drag phase.
- startpos : Starting tip position vector [x, y, z].
- endpos : Ending tip position vector [x, y, z].
- dragθ : Pen floor angle used during drag.
- drag_azimuth : Pen azimuth used during drag.
- color : Trail and active pen color.

Returns:

- tippos : Interpolated pen tip position at time timer.
"""
function animate_pen_drag(
    state_ptr::Ptr{Cvoid},
    timer::Real, duration::Real,
    startpos::AbstractVector{<:Real},
    endpos::AbstractVector{<:Real},
    dragθ::Real, drag_azimuth::Real, color)

    t = clamp(timer / duration, 0f0, 1f0)

    tippos = startpos + (endpos - startpos) * t

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 1, color)
    place_pen_at_angles(state_ptr, tippos, dragθ, drag_azimuth)

    OdinJuliaBridge.emit_trailing_particle(state_ptr, tippos, color)

    return tippos
end

"""
Animate pen transfer along an elevated arc between two positions.

--------

Parameters:

- state_ptr : Pointer to the Euclid application state.
- timer : Elapsed animation time.
- duration : Total duration for the arc move.
- startpos : Starting position vector [x, y, z].
- endpos : Ending position vector [x, y, z].
- height : Arc peak height scale.
- periods : Number of sinusoidal periods over the move.
- strikecolor : Particle strike color near the floor, or :none.

Returns:

- nothing
"""
function animate_pen_arcmove(
    state_ptr::Ptr{Cvoid},
    timer::Real, duration::Real,
    startpos::AbstractVector{<:Real},
    endpos::AbstractVector{<:Real},
    height::Real, periods::Integer, strikecolor)

    t = clamp(timer / duration, 0f0, 1f0)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, :white)

    vec = endpos - startpos
    tvec = t * vec
    offsetz = abs(clamp(sin(t * periods * π) * height, -1f0, 1f0))
    tvec[3] = tvec[3] + offsetz
    use_point = startpos + tvec
    place_pen_at_angles(state_ptr, use_point, π / 2f0, 0f0)
    if use_point[3] < 0.05 && strikecolor != :none
        particle_point = [use_point[1], use_point[2], 0f0]
        OdinJuliaBridge.emit_trailing_particle(state_ptr, particle_point, strikecolor)
    end
end

"""Compute the 2D cross-product z-component of two vectors."""
@inline xy_cross(ax::Real, ay::Real, bx::Real, by::Real) = ax * by - ay * bx

"""
Return whether a point lies on a segment within a tolerance in the xy plane.
"""
@inline function point_on_segment_xy(
    a::AbstractVector{<:Real}, b::AbstractVector{<:Real}, p::AbstractVector{<:Real},
    eps::Real)

    return (p[1] >= min(a[1], b[1]) - eps && p[1] <= max(a[1], b[1]) + eps &&
        p[2] >= min(a[2], b[2]) - eps && p[2] <= max(a[2], b[2]) + eps)
end

"""
Return whether the two cross-product signs straddle zero, meaning the tested
points lie on opposite sides of the reference line.
"""
@inline xy_orientations_straddle(p::Real, q::Real, eps::Real) =
    (p > eps && q < -eps) || (p < -eps && q > eps)

"""
Return whether a cross product is collinear within `eps` and its point lies on
the segment between `seg_a` and `seg_b`.
"""
@inline xy_collinear_on_segment(
    orientation::Real,
    seg_a::AbstractVector{<:Real}, seg_b::AbstractVector{<:Real},
    point::AbstractVector{<:Real}, eps::Real) =

    abs(orientation) <= eps && point_on_segment_xy(seg_a, seg_b, point, eps)

"""
Return whether two segments intersect in the xy plane, including collinear overlap.
"""
@inline function segments_intersect_xy(
    a1::AbstractVector{<:Real}, a2::AbstractVector{<:Real},
    b1::AbstractVector{<:Real}, b2::AbstractVector{<:Real})

    eps = 1f-5

    o1 = xy_cross(a2[1] - a1[1], a2[2] - a1[2], b1[1] - a1[1], b1[2] - a1[2])
    o2 = xy_cross(a2[1] - a1[1], a2[2] - a1[2], b2[1] - a1[1], b2[2] - a1[2])
    o3 = xy_cross(b2[1] - b1[1], b2[2] - b1[2], a1[1] - b1[1], a1[2] - b1[2])
    o4 = xy_cross(b2[1] - b1[1], b2[2] - b1[2], a2[1] - b1[1], a2[2] - b1[2])

    xy_orientations_straddle(o1, o2, eps) &&
        xy_orientations_straddle(o3, o4, eps) && return true

    return (xy_collinear_on_segment(o1, a1, a2, b1, eps) ||
        xy_collinear_on_segment(o2, a1, a2, b2, eps) ||
        xy_collinear_on_segment(o3, b1, b2, a1, eps) ||
        xy_collinear_on_segment(o4, b1, b2, a2, eps))
end

"""
Return the average of the two endpoint distances from an xy center.
"""
@inline function avg_radius_to_xy_center(
    start_joint::AbstractVector{<:Real}, end_joint::AbstractVector{<:Real},
    center_x::Real, center_y::Real)

    start_radius = hypot(start_joint[1] - center_x, start_joint[2] - center_y)
    end_radius = hypot(end_joint[1] - center_x, end_joint[2] - center_y)
    return (start_radius + end_radius) * 0.5f0
end

"""
Apply a detour arc that routes a point around an inside segment.

Mutates `outside_point` in place as the arc progresses over normalized time `t`.
"""
@inline function apply_xy_detour_arc!(
    outside_point::AbstractVector{<:Real},
    outside_start::AbstractVector{<:Real}, outside_end::AbstractVector{<:Real},
    inside_start::AbstractVector{<:Real}, inside_end::AbstractVector{<:Real},
    t::Real)

    dir_x = outside_end[1] - outside_start[1]
    dir_y = outside_end[2] - outside_start[2]
    dir_len = hypot(dir_x, dir_y)
    if dir_len <= 1f-6
        return
    end

    normal_x = -dir_y / dir_len
    normal_y = dir_x / dir_len

    rel_x = outside_start[1] - inside_start[1]
    rel_y = outside_start[2] - inside_start[2]
    side = sign(xy_cross(dir_x, dir_y, rel_x, rel_y))
    if side == 0f0
        side = 1f0
    end

    span_start = hypot(outside_start[1] - inside_start[1],
        outside_start[2] - inside_start[2])
    span_end = hypot(outside_end[1] - inside_end[1], outside_end[2] - inside_end[2])
    avg_span = (span_start + span_end) * 0.5f0
    arc_amplitude = clamp(avg_span * 0.15f0, 0.01f0, 0.05f0)

    offset = sin(t * π) * arc_amplitude * side
    outside_point[1] += normal_x * offset
    outside_point[2] += normal_y * offset
end

"""
Apply the detour arc to the compass joint with the larger radius.

When two compass joint paths cross, the joint farther from the shared center is
routed around the nearer joint's segment so the compass does not clip itself.
"""
function apply_compass_joint_detour!(
    use_point1::AbstractVector{<:Real}, use_point2::AbstractVector{<:Real},
    start_joint1::AbstractVector{<:Real}, end_joint1::AbstractVector{<:Real},
    start_joint2::AbstractVector{<:Real}, end_joint2::AbstractVector{<:Real},
    t::Real)

    center_x = (start_joint1[1] + start_joint2[1] + end_joint1[1] + end_joint2[1])
    center_x = center_x * 0.25f0
    center_y = (start_joint1[2] + start_joint2[2] + end_joint1[2] + end_joint2[2])
    center_y = center_y * 0.25f0

    joint1_radius = avg_radius_to_xy_center(
        start_joint1, end_joint1, center_x, center_y)
    joint2_radius = avg_radius_to_xy_center(
        start_joint2, end_joint2, center_x, center_y)

    if joint1_radius >= joint2_radius
        apply_xy_detour_arc!(
            use_point1, start_joint1, end_joint1, start_joint2, end_joint2, t)
    else
        apply_xy_detour_arc!(
            use_point2, start_joint2, end_joint2, start_joint1, end_joint1, t)
    end
end


"""
Animate compass transfer along an elevated arc between two joint pairs.

--------

Parameters:

- state_ptr : Pointer to the Euclid application state.
- timer : Elapsed animation time.
- duration : Total duration for the arc move.
- start_joint1 : Starting position of compass joint 1 [x, y, z].
- end_joint1 : Ending position of compass joint 1 [x, y, z].
- start_joint2 : Starting position of compass joint 2 [x, y, z].
- end_joint2 : Ending position of compass joint 2 [x, y, z].
- height : Arc peak height scale.
- periods : Number of sinusoidal periods over the move.
- strikecolor : Particle strike color near the floor, or :none.

Returns:

- nothing
"""
function animate_compass_arcmove(
    state_ptr::Ptr{Cvoid},
    timer::Real, duration::Real,
    start_joint1::AbstractVector{<:Real},
    end_joint1::AbstractVector{<:Real},
    start_joint2::AbstractVector{<:Real},
    end_joint2::AbstractVector{<:Real};
    height::Real=0.22f0,
    periods::Integer=1,
    strikecolor=:none)

    t = clamp(timer / duration, 0f0, 1f0)
    OdinJuliaBridge.set_compass_active(state_ptr, 0, :white)

    vec1 = end_joint1 - start_joint1
    vec2 = end_joint2 - start_joint2

    tvec1 = t * vec1
    tvec2 = t * vec2

    z_arc = sin(t * periods * π) * height
    tvec1[3] = z_arc
    tvec2[3] = z_arc

    use_point1 = start_joint1 + tvec1
    use_point2 = start_joint2 + tvec2

    if segments_intersect_xy(start_joint1, end_joint1, start_joint2, end_joint2)
        apply_compass_joint_detour!(
            use_point1, use_point2,
            start_joint1, end_joint1, start_joint2, end_joint2, t)
    end

    use_point1[3] = abs(clamp(use_point1[3], -1f0, 1f0))
    use_point2[3] = abs(clamp(use_point2[3], -1f0, 1f0))

    OdinJuliaBridge.lock_compass_joint1(state_ptr, use_point1; sweep = false)
    OdinJuliaBridge.lock_compass_joint2(state_ptr, use_point2; sweep = false)
    OdinJuliaBridge.show_compass(state_ptr)

    if use_point1[3] < 0.05 && strikecolor != :none
        OdinJuliaBridge.emit_trailing_particle(state_ptr, use_point1, strikecolor)
        OdinJuliaBridge.emit_trailing_particle(state_ptr, use_point2, strikecolor)
    end
end

"""
Animate a full line stroke with tilt-in, drag, and tilt-out phases.

--------

Parameters:

- state_ptr : Pointer to the Euclid application state.
- timer : Elapsed animation time.
- duration : Total duration for the stroke sequence.
- startpos : Starting position vector [x, y, z].
- endpos : Ending position vector [x, y, z].
- color : Stroke and particle color.

Returns:

- nothing
"""
function animate_pen_tilt_and_drag(
    state_ptr::Ptr{Cvoid},
    timer::Real, duration::Real,
    startpos::AbstractVector{<:Real}, endpos::AbstractVector{<:Real}, color)

    t = clamp(timer / duration, 0f0, 1f0)

    azimuth = Float32(atan(endpos[2] - startpos[2], endpos[1] - startpos[1]))
    if t < TiltToLineDuration
        animate_pen_tilt(
            state_ptr, timer, duration * TiltToLineDuration, startpos,
            PenStraightFloorAngle, PenDrawLineAngle, azimuth)
    elseif t < GroundLineEndTime
        tippos = animate_pen_drag(state_ptr, timer - duration * TiltToLineDuration,
            duration * GroundLineDuration, startpos, endpos, PenDrawLineAngle,
            azimuth, color)

        OdinJuliaBridge.emit_trailing_particle(state_ptr, tippos, color)

        OdinJuliaBridge.set_pen_active(state_ptr, 0, color)
    else
        animate_pen_tilt(
            state_ptr, timer - duration * GroundTrailEndTime,
            duration * (1f0 - GroundTrailEndTime), endpos,
            PenDrawLineAngle, PenStraightFloorAngle, azimuth)
    end
end

"""
Animate highlighting a point with tilt-in, cone contact, and tilt-out phases.

--------

Parameters:

- state_ptr : Pointer to the Euclid application state.
- timer : Elapsed animation time.
- duration : Total duration for the point draw sequence.
- penpos : Pen base position vector [x, y, z].
- pencolor : Point and trail color.

Returns:

- nothing
"""
function animate_highlight_point(
    state_ptr::Ptr{Cvoid},
    timer::Real, duration::Real,
    penpos::AbstractVector{<:Real}, pencolor)

    t = clamp(timer / duration, 0f0, 1f0)

    if t < TiltToConeDuration
        animate_pen_tilt(
            state_ptr, timer, duration * TiltToConeDuration, penpos,
            PenStraightFloorAngle, PenConeFloorAngle, 0f0)
    elseif t < GroundTrailEndTime
        animate_pen_cone(
            state_ptr, timer - duration * TiltToConeDuration,
            penpos, PenConeFloorAngle, PenConeSpinSpeed)

        OdinJuliaBridge.emit_trailing_particle(state_ptr, penpos, pencolor)

        OdinJuliaBridge.set_pen_active(state_ptr, 1, pencolor)
    else
        end_azimuth = (GroundTrailDuration * duration) * PenConeSpinSpeed
        animate_pen_tilt(
            state_ptr, timer - duration * GroundTrailEndTime,
            duration * (1f0 - GroundTrailEndTime), penpos,
            PenConeFloorAngle, PenStraightFloorAngle, end_azimuth)
    end
end

"""
Animate drawing a point with tilt-in, cone contact, and tilt-out phases.

--------

Parameters:

- state_ptr : Pointer to the Euclid application state.
- timer : Elapsed animation time.
- duration : Total duration for the point draw sequence.
- penpos : Pen base position vector [x, y, z].
- penbrush : Brush size for the point primitive.
- pencolor : Point and trail color.
- pointid : Host point id to update and show.

Returns:

- nothing
"""
function animate_draw_point(
    state_ptr::Ptr{Cvoid},
    timer::Real, duration::Real,
    penpos::AbstractVector{<:Real}, penbrush::Real, pencolor,
    pointid::Integer)

    t = clamp(timer / duration, 0f0, 1f0)

    if t < TiltToConeDuration
        animate_pen_tilt(
            state_ptr, timer, duration * TiltToConeDuration, penpos,
            PenStraightFloorAngle, PenConeFloorAngle, 0f0)
    elseif t < GroundTrailEndTime
        animate_pen_cone(
            state_ptr, timer - duration * TiltToConeDuration,
            penpos, PenConeFloorAngle, PenConeSpinSpeed)

        OdinJuliaBridge.simulate_drawing_sound(state_ptr, PenConeSimulatedDrawSpeed)

        OdinJuliaBridge.set_point_color(state_ptr, pointid, pencolor)
        OdinJuliaBridge.set_point_position(state_ptr, pointid, penpos)
        OdinJuliaBridge.set_point_brush(state_ptr, pointid, penbrush)
        OdinJuliaBridge.show_point(state_ptr, pointid)

        OdinJuliaBridge.emit_trailing_particle(state_ptr, penpos, pencolor)

        OdinJuliaBridge.set_pen_active(state_ptr, 1, pencolor)
    else
        end_azimuth = (GroundTrailDuration * duration) * PenConeSpinSpeed
        animate_pen_tilt(
            state_ptr, timer - duration * GroundTrailEndTime,
            duration * (1f0 - GroundTrailEndTime), penpos,
            PenConeFloorAngle, PenStraightFloorAngle, end_azimuth)
    end
end

"""
Animate drawing a line primitive with pen motion and endpoint updates.

--------

Parameters:

- state_ptr : Pointer to the Euclid application state.
- timer : Elapsed animation time.
- duration : Total duration for the line draw sequence.
- startpos : Starting line endpoint vector [x, y, z].
- endpos : Ending line endpoint vector [x, y, z].
- penbrush : Brush size for the line host primitive.
- pencolor : Line and trail color.
- line_host_id : Host point id representing the line primitive.
- line_joint1_id : Start endpoint control id.
- line_joint2_id : End endpoint control id.

Returns:

- nothing
"""
function animate_draw_line(
    state_ptr::Ptr{Cvoid},
    timer::Real, duration::Real,
    startpos::AbstractVector{<:Real}, endpos::AbstractVector{<:Real};
    penbrush::Real,
    pencolor,
    line_host_id::Integer,
    line_joint1_id::Integer,
    line_joint2_id::Integer)

    t = clamp(timer / duration, 0f0, 1f0)

    azimuth = Float32(atan(endpos[2] - startpos[2], endpos[1] - startpos[1]))
    if t < TiltToLineDuration
        animate_pen_tilt(state_ptr, timer, duration * TiltToLineDuration, startpos,
            PenStraightFloorAngle, PenDrawLineAngle, azimuth)
    elseif t < GroundLineEndTime
        tippos = animate_pen_drag(state_ptr, timer - duration * TiltToLineDuration,
            duration * GroundLineDuration, startpos, endpos, PenDrawLineAngle,
            azimuth, pencolor)

        OdinJuliaBridge.set_point_color(state_ptr, line_host_id, pencolor)
        OdinJuliaBridge.set_point_brush(state_ptr, line_host_id, penbrush)
        OdinJuliaBridge.set_point_position(state_ptr, line_joint1_id, startpos)
        OdinJuliaBridge.set_point_position(state_ptr, line_joint2_id, tippos)
        OdinJuliaBridge.show_point(state_ptr, line_host_id)

        OdinJuliaBridge.emit_trailing_particle(state_ptr, tippos, pencolor)

        OdinJuliaBridge.set_pen_active(state_ptr, 1, pencolor)
    else
        animate_pen_tilt(
            state_ptr, timer - duration * GroundTrailEndTime,
            duration * (1f0 - GroundTrailEndTime), endpos,
            PenDrawLineAngle, PenStraightFloorAngle, azimuth)
    end
end

"""Run the pen tilt-in or tilt-out phase bounding a two-segment line draw."""
function animate_two_segment_tilt(
    state_ptr::Ptr{Cvoid}, timer::Real, duration::Real,
    position::AbstractVector{<:Real}, azimuth::Real, tilt_in::Bool)

    if tilt_in
        animate_pen_tilt(
            state_ptr, timer, duration * TiltToLineDuration, position,
            PenStraightFloorAngle, PenDrawLineAngle, azimuth)
    else
        animate_pen_tilt(
            state_ptr, timer - duration * GroundTrailEndTime,
            duration * (1f0 - GroundTrailEndTime), position,
            PenDrawLineAngle, PenStraightFloorAngle, azimuth)
    end
end


"""
Animate two connected line segments as one continuous pen stroke.

This keeps pen contact across the shared midpoint so the result reads as one
drawn line while still updating two independent host line primitives.
"""
function animate_draw_two_line_segments(
    state_ptr::Ptr{Cvoid},
    timer::Real, duration::Real,
    startpos::AbstractVector{<:Real}, midpos::AbstractVector{<:Real},
    endpos::AbstractVector{<:Real},
    penbrush::Real, pencolor;
    line1_host_id::Integer, line1_joint1_id::Integer, line1_joint2_id::Integer,
    line2_host_id::Integer, line2_joint1_id::Integer, line2_joint2_id::Integer)

    t = clamp(timer / duration, 0f0, 1f0)

    seg1 = max(norm(midpos - startpos), TransformEps)
    seg2 = max(norm(endpos - midpos), TransformEps)
    seg_total = seg1 + seg2

    azimuth1 = Float32(atan(midpos[2] - startpos[2], midpos[1] - startpos[1]))
    azimuth2 = Float32(atan(endpos[2] - midpos[2], endpos[1] - midpos[1]))
    draw_duration = duration * GroundLineDuration
    seg1_duration = draw_duration * (seg1 / seg_total)
    seg2_duration = draw_duration - seg1_duration

    if t < TiltToLineDuration
        animate_two_segment_tilt(
            state_ptr, timer, duration, startpos, azimuth1, true)
    elseif t < GroundLineEndTime
        draw_two_segment_stroke(
            state_ptr, timer - duration * TiltToLineDuration,
            (seg1_duration, seg2_duration), (startpos, midpos, endpos),
            (penbrush, pencolor), (azimuth1, azimuth2),
            (line1_host_id, line1_joint1_id, line1_joint2_id),
            (line2_host_id, line2_joint1_id, line2_joint2_id))
    else
        set_line_segment_points(state_ptr, penbrush, pencolor, line1_host_id,
            (line1_joint1_id, line1_joint2_id), startpos, midpos, true)
        set_line_segment_points(state_ptr, penbrush, pencolor, line2_host_id,
            (line2_joint1_id, line2_joint2_id), midpos, endpos, true)

        animate_two_segment_tilt(
            state_ptr, timer, duration, endpos, azimuth2, false)
    end
end


"""Draw the active stroke across two connected line segments for the current drag."""
function draw_two_segment_stroke(
    state_ptr::Ptr{Cvoid}, drag_time::Real,
    seg_durations::Tuple{<:Real,<:Real},
    positions::Tuple{<:AbstractVector{<:Real},
        <:AbstractVector{<:Real},<:AbstractVector{<:Real}},
    style::Tuple{<:Real,Any}, azimuths::Tuple{<:Real,<:Real},
    line1_ids::Tuple{<:Integer,<:Integer,<:Integer},
    line2_ids::Tuple{<:Integer,<:Integer,<:Integer})

    seg1_duration, seg2_duration = seg_durations
    startpos, midpos, endpos = positions
    penbrush, pencolor = style
    azimuth1, azimuth2 = azimuths
    if drag_time <= seg1_duration
        tippos = animate_pen_drag(
            state_ptr, drag_time, seg1_duration,
            startpos, midpos, PenDrawLineAngle, azimuth1, pencolor)
        set_line_segment_points(state_ptr, penbrush, pencolor, line1_ids[1],
            (line1_ids[2], line1_ids[3]), startpos, tippos, true)
        set_line_segment_points(state_ptr, penbrush, pencolor, line2_ids[1],
            (line2_ids[2], line2_ids[3]), midpos, midpos, false)
    else
        tippos = animate_pen_drag(
            state_ptr, drag_time - seg1_duration, seg2_duration,
            midpos, endpos, PenDrawLineAngle, azimuth2, pencolor)
        set_line_segment_points(state_ptr, penbrush, pencolor, line1_ids[1],
            (line1_ids[2], line1_ids[3]), startpos, midpos, true)
        set_line_segment_points(state_ptr, penbrush, pencolor, line2_ids[1],
            (line2_ids[2], line2_ids[3]), midpos, tippos, true)
    end

    OdinJuliaBridge.set_pen_active(state_ptr, 1, pencolor)
end


"""Set one line segment host/joint point state, showing or hiding the host."""
function set_line_segment_points(
    state_ptr::Ptr{Cvoid}, penbrush::Real, pencolor,
    host_id::Integer, joint_ids::Tuple{<:Integer,<:Integer},
    joint1_pos::AbstractVector{<:Real}, joint2_pos::AbstractVector{<:Real},
    show_host::Bool)

    OdinJuliaBridge.set_point_color(state_ptr, host_id, pencolor)
    OdinJuliaBridge.set_point_brush(state_ptr, host_id, penbrush)
    OdinJuliaBridge.set_point_position(state_ptr, joint_ids[1], joint1_pos)
    OdinJuliaBridge.set_point_position(state_ptr, joint_ids[2], joint2_pos)
    if show_host
        OdinJuliaBridge.show_point(state_ptr, host_id)
    else
        OdinJuliaBridge.hide_point(state_ptr, host_id)
    end
end

"""
Animate extending drawing a line primitive with pen motion and endpoint updates.

--------

Parameters:

- state_ptr : Pointer to the Euclid application state.
- timer : Elapsed animation time.
- duration : Total duration for the line draw sequence.
- startpos : Starting line endpoint vector [x, y, z].
- midpos : Starting line endpoint vector for the extension (the previous endpos) [x, y, z].
- endpos : Ending line endpoint vector [x, y, z].
- penbrush : Brush size for the line host primitive.
- pencolor : Line and trail color.
- line_host_id : Host point id representing the line primitive.
- line_joint1_id : Start endpoint control id.
- line_joint2_id : End endpoint control id.

Returns:

- nothing
"""
function animate_extend_line(
    state_ptr::Ptr{Cvoid},
    timer::Real, duration::Real,
    startpos::AbstractVector{<:Real}, midpos::AbstractVector{<:Real},
    endpos::AbstractVector{<:Real},
    penbrush::Real, pencolor;
    line_host_id::Integer=0,
    line_joint1_id::Integer=0,
    line_joint2_id::Integer=0)

    t = clamp(timer / duration, 0f0, 1f0)

    azimuth = Float32(atan(endpos[2] - startpos[2], endpos[1] - startpos[1]))
    if t < TiltToLineDuration
        animate_pen_tilt(state_ptr, timer, duration * TiltToLineDuration, midpos,
            PenStraightFloorAngle, PenDrawLineAngle, azimuth)
    elseif t < GroundLineEndTime
        tippos = animate_pen_drag(state_ptr, timer - duration * TiltToLineDuration,
            duration * GroundLineDuration, midpos, endpos, PenDrawLineAngle,
            azimuth, pencolor)

        OdinJuliaBridge.set_point_color(state_ptr, line_host_id, pencolor)
        OdinJuliaBridge.set_point_brush(state_ptr, line_host_id, penbrush)
        OdinJuliaBridge.set_point_position(state_ptr, line_joint1_id, startpos)
        OdinJuliaBridge.set_point_position(state_ptr, line_joint2_id, tippos)
        OdinJuliaBridge.show_point(state_ptr, line_host_id)

        OdinJuliaBridge.emit_trailing_particle(state_ptr, tippos, pencolor)

        OdinJuliaBridge.set_pen_active(state_ptr, 1, pencolor)
    else
        animate_pen_tilt(
            state_ptr, timer - duration * GroundTrailEndTime,
            duration * (1f0 - GroundTrailEndTime), endpos,
            PenDrawLineAngle, PenStraightFloorAngle, azimuth)
    end
end

"""
Animate drawing a circle sector using compass motion.

--------

Parameters:

- state_ptr : Pointer to the Euclid application state.
- timer : Elapsed animation time.
- duration : Total duration for the circle draw sequence.
- joint_point : Compass pivot position vector [x, y, z].
- start_point : Marker start point vector [x, y, z].
- angle_theta : Sweep angle in radians.
- radius : Marker radius.
- brush : Brush size for the marker host primitive.
- color : Marker and trail color.
- marker_host_id : Host id for the filled marker primitive.
- marker_start_id : Start control point id for marker geometry.
- marker_end_id : End control point id for marker geometry.

Returns:

- nothing
"""
function animate_draw_circle(
    state_ptr::Ptr{Cvoid},
    timer::Real, duration::Real,
    joint_point::AbstractVector{<:Real}, start_point::AbstractVector{<:Real},
    angle_theta::Real, radius::Real;
    brush::Real=0f0,
    color=:black,
    marker_host_id::Integer=0,
    marker_start_id::Integer=0,
    marker_end_id::Integer=0)

    t = clamp(timer / duration, 0f0, 1f0)
    start_theta = Float32(atan(start_point[2] - joint_point[2],
        start_point[1] - joint_point[1]))
    theta = start_theta + angle_theta * t

    end_point = [
        joint_point[1] + radius * Float32(cos(theta)),
        joint_point[2] + radius * Float32(sin(theta)),
        0f0]

    OdinJuliaBridge.lock_compass_joint1(state_ptr, joint_point, sweep = false)
    OdinJuliaBridge.set_compass_active(state_ptr, 3, color)
    OdinJuliaBridge.lock_compass_joint2(state_ptr, end_point, sweep = false)
    OdinJuliaBridge.show_compass(state_ptr)

    OdinJuliaBridge.set_point_color(state_ptr, marker_host_id, color)
    OdinJuliaBridge.set_point_brush(state_ptr, marker_host_id, brush)
    OdinJuliaBridge.set_point_position(state_ptr, marker_start_id, start_point)
    OdinJuliaBridge.set_point_position(state_ptr, marker_end_id, end_point)
    OdinJuliaBridge.show_point(state_ptr, marker_host_id)

    OdinJuliaBridge.emit_trailing_particle(state_ptr, end_point, color)
end

"""
Animate drawing a filled circular sector marker using compass motion.

--------

Parameters:

- state_ptr : Pointer to the Euclid application state.
- timer : Elapsed animation time.
- duration : Total duration for the marker draw sequence.
- joint_point : Compass pivot position vector [x, y, z].
- start_point : Marker start point vector [x, y, z].
- angle_theta : Sweep angle in radians.
- radius : Marker radius.
- brush : Brush size for the marker host primitive.
- color : Marker and trail color.
- marker_host_id : Host id for the filled marker primitive.
- marker_start_id : Start control point id for marker geometry.
- marker_end_id : End control point id for marker geometry.

Returns:

- nothing
"""
function animate_draw_filledcircle(
    state_ptr::Ptr{Cvoid},
    timer::Real, duration::Real,
    joint_point::AbstractVector{<:Real}, start_point::AbstractVector{<:Real},
    angle_theta::Real, radius::Real;
    brush::Real=0f0,
    color=:black,
    marker_host_id::Integer=0,
    marker_start_id::Integer=0,
    marker_end_id::Integer=0)

    t = clamp(timer / duration, 0f0, 1f0)
    start_theta = Float32(atan(start_point[2] - joint_point[2],
        start_point[1] - joint_point[1]))
    theta = start_theta + angle_theta * t

    end_point = [
        joint_point[1] + radius * Float32(cos(theta)),
        joint_point[2] + radius * Float32(sin(theta)),
        0f0]

    OdinJuliaBridge.lock_compass_joint1(state_ptr, joint_point)
    OdinJuliaBridge.set_compass_active(state_ptr, 3, color)
    OdinJuliaBridge.lock_compass_joint2(state_ptr, end_point)
    OdinJuliaBridge.show_compass(state_ptr)

    OdinJuliaBridge.set_point_color(state_ptr, marker_host_id, color)
    OdinJuliaBridge.set_point_brush(state_ptr, marker_host_id, brush)
    OdinJuliaBridge.set_point_position(state_ptr, marker_start_id, start_point)
    OdinJuliaBridge.set_point_position(state_ptr, marker_end_id, end_point)
    OdinJuliaBridge.show_point(state_ptr, marker_host_id)

    emit_filledcircle_radius_trail(state_ptr, joint_point, end_point, color)
end

"""
Animate a compass-only filled arc highlight sweep without mutating marker geometry.

--------

Parameters:

- state_ptr : Pointer to the Euclid application state.
- timer : Elapsed animation time.
- duration : Total duration for the highlight sweep.
- joint_point : Compass pivot position vector [x, y, z].
- start_point : Sweep start point vector [x, y, z].
- angle_theta : Sweep angle in radians.
- radius : Sweep radius.
- color : Trail and compass-active color.

Returns:

- nothing
"""
function animate_compass_fill_arc_highlight(
    state_ptr::Ptr{Cvoid},
    timer::Real, duration::Real,
    joint_point::AbstractVector{<:Real}, start_point::AbstractVector{<:Real},
    angle_theta::Real, radius::Real, color)

    t = clamp(timer / duration, 0f0, 1f0)
    start_theta = Float32(atan(start_point[2] - joint_point[2],
        start_point[1] - joint_point[1]))
    theta = start_theta + angle_theta * t

    end_point = [
        joint_point[1] + radius * Float32(cos(theta)),
        joint_point[2] + radius * Float32(sin(theta)),
        0f0]

    OdinJuliaBridge.lock_compass_joint1(state_ptr, joint_point; sweep = false)
    OdinJuliaBridge.lock_compass_joint2(state_ptr, end_point; sweep = false)
    OdinJuliaBridge.set_compass_active(state_ptr, 3, color)
    OdinJuliaBridge.show_compass(state_ptr)

    emit_filledcircle_radius_trail(state_ptr, joint_point, end_point, color)
end

"""
Animate a compass-only unfilled arc highlight sweep without mutating marker geometry.

--------

Parameters:

- state_ptr : Pointer to the Euclid application state.
- timer : Elapsed animation time.
- duration : Total duration for the highlight sweep.
- joint_point : Compass pivot position vector [x, y, z].
- start_point : Sweep start point vector [x, y, z].
- angle_theta : Sweep angle in radians.
- radius : Sweep radius.
- color : Trail and compass-active color.

Returns:

- nothing
"""
function animate_compass_arc_highlight(
    state_ptr::Ptr{Cvoid},
    timer::Real, duration::Real,
    joint_point::AbstractVector{<:Real}, start_point::AbstractVector{<:Real},
    angle_theta::Real, radius::Real, color)

    t = clamp(timer / duration, 0f0, 1f0)
    start_theta = Float32(atan(start_point[2] - joint_point[2],
        start_point[1] - joint_point[1]))
    theta = start_theta + angle_theta * t

    end_point = [
        joint_point[1] + radius * Float32(cos(theta)),
        joint_point[2] + radius * Float32(sin(theta)),
        0f0]

    OdinJuliaBridge.lock_compass_joint1(state_ptr, joint_point; sweep = false)
    OdinJuliaBridge.lock_compass_joint2(state_ptr, end_point; sweep = false)
    OdinJuliaBridge.set_compass_active(state_ptr, 3, color)
    OdinJuliaBridge.show_compass(state_ptr)

    OdinJuliaBridge.emit_trailing_particle(state_ptr, end_point, color)
end

"""Animate a REPL point draw with explicit pen descend, draw, and rise phases."""
function animate_repl_draw_point(
    state_ptr::Ptr{Cvoid},
    timer::Real, duration::Real,
    penpos::AbstractVector{<:Real}, penbrush::Real, pencolor,
    pointid::Integer)

    t = clamp(timer / duration, 0f0, 1f0)

    descend_duration = duration * ReplDescendShare
    draw_duration = duration * ReplDrawShare
    draw_start = descend_duration
    draw_end = draw_start + draw_duration

    if t < ReplDescendShare
        animate_pen_descend(
            state_ptr,
            timer,
            descend_duration,
            ReplToolTravelTopZ,
            penpos[1],
            penpos[2])
        return
    end

    if t < (ReplDescendShare + ReplDrawShare)
        animate_draw_point(
            state_ptr,
            timer - draw_start,
            draw_duration,
            penpos,
            penbrush,
            pencolor,
            pointid)
        return
    end

    animate_pen_rise(
        state_ptr,
        timer - draw_end,
        duration - draw_end,
        ReplToolTravelTopZ,
        penpos[1],
        penpos[2])
end

"""Animate a REPL line draw with explicit pen descend, draw, and rise phases."""
function animate_repl_draw_line(
    state_ptr::Ptr{Cvoid},
    timer::Real, duration::Real,
    startpos::AbstractVector{<:Real}, endpos::AbstractVector{<:Real};
    penbrush::Real=0f0,
    pencolor=:black,
    line_host_id::Integer=0,
    line_joint1_id::Integer=0,
    line_joint2_id::Integer=0)

    t = clamp(timer / duration, 0f0, 1f0)

    draw_start = duration * ReplDescendShare
    draw_end = draw_start + duration * ReplDrawShare

    if t < ReplDescendShare
        animate_pen_descend(
            state_ptr, timer, draw_start, ReplToolTravelTopZ,
            startpos[1], startpos[2])
        return
    end

    if t < (ReplDescendShare + ReplDrawShare)
        animate_draw_line(
            state_ptr, timer - draw_start, duration * ReplDrawShare,
            startpos, endpos; penbrush=penbrush, pencolor=pencolor,
            line_host_id=line_host_id,
            line_joint1_id=line_joint1_id,
            line_joint2_id=line_joint2_id)
        return
    end

    animate_pen_rise(
        state_ptr, timer - draw_end, duration - draw_end,
        ReplToolTravelTopZ, endpos[1], endpos[2])
end

"""Run the compass descend/rise phases around a REPL circle draw."""
function animate_repl_circle_phases(
    state_ptr::Ptr{Cvoid},
    timer::Real, duration::Real,
    joint_point::AbstractVector{<:Real}, start_point::AbstractVector{<:Real},
    sweep::Tuple{<:Real,<:Real},
    marker_host_id::Integer, full_sweep::Bool)

    angle_theta, radius = sweep
    if full_sweep
        OdinJuliaBridge.set_point_offset(state_ptr, marker_host_id, angle_theta)
    else
        OdinJuliaBridge.set_point_offset(state_ptr, marker_host_id, 0f0)
    end

    draw_end = duration * (ReplDescendShare + ReplDrawShare)
    final_theta = Float32(atan(start_point[2] - joint_point[2],
        start_point[1] - joint_point[1])) + angle_theta
    end_point = Float32[
        joint_point[1] + radius * Float32(cos(final_theta)),
        joint_point[2] + radius * Float32(sin(final_theta)),
        joint_point[3],
    ]

    animate_compass_rise(
        state_ptr, timer - draw_end, duration - draw_end, ReplToolTravelTopZ,
        joint_point[1], joint_point[2], end_point[1], end_point[2])
end


"""Animate a REPL circle draw with explicit compass descend, draw, and rise phases."""
function animate_repl_draw_circle(
    state_ptr::Ptr{Cvoid},
    timer::Real, duration::Real,
    joint_point::AbstractVector{<:Real}, start_point::AbstractVector{<:Real},
    angle_theta::Real,
    radius::Real;
    brush::Real=0f0,
    color=:black,
    marker_host_id::Integer=0,
    marker_start_id::Integer=0,
    marker_end_id::Integer=0,
    full_sweep::Bool=false)

    t = clamp(timer / duration, 0f0, 1f0)

    descend_duration = duration * ReplDescendShare
    draw_duration = duration * ReplDrawShare
    draw_start = descend_duration
    draw_end = draw_start + draw_duration

    if t < ReplDescendShare
        animate_compass_descend(
            state_ptr,
            timer,
            descend_duration,
            ReplToolTravelTopZ,
            joint_point[1],
            joint_point[2],
            start_point[1],
            start_point[2])
        return
    end

    if t < (ReplDescendShare + ReplDrawShare)
        animate_draw_circle(
            state_ptr, timer - draw_start, draw_duration,
            joint_point, start_point, angle_theta, radius;
            brush=brush, color=color, marker_host_id=marker_host_id,
            marker_start_id=marker_start_id, marker_end_id=marker_end_id)
        return
    end

    animate_repl_circle_phases(
        state_ptr, timer, duration, joint_point, start_point,
        (angle_theta, radius), marker_host_id, full_sweep)
end

"""Animate a REPL filled-circle draw with explicit compass descend, draw, and rise phases."""
function animate_repl_draw_filledcircle(
    state_ptr::Ptr{Cvoid},
    timer::Real, duration::Real,
    joint_point::AbstractVector{<:Real}, start_point::AbstractVector{<:Real},
    angle_theta::Real, radius::Real;
    brush::Real=0f0,
    color=:black,
    marker_host_id::Integer=0,
    marker_start_id::Integer=0,
    marker_end_id::Integer=0,
    full_sweep::Bool=false)

    t = clamp(timer / duration, 0f0, 1f0)

    descend_duration = duration * ReplDescendShare
    draw_duration = duration * ReplDrawShare
    draw_start = descend_duration
    draw_end = draw_start + draw_duration

    if t < ReplDescendShare
        animate_compass_descend(
            state_ptr,
            timer,
            descend_duration,
            ReplToolTravelTopZ,
            joint_point[1],
            joint_point[2],
            start_point[1],
            start_point[2])
        return
    end

    if t < (ReplDescendShare + ReplDrawShare)
        animate_draw_filledcircle(
            state_ptr, timer - draw_start, draw_duration,
            joint_point, start_point, angle_theta, radius;
            brush=brush, color=color, marker_host_id=marker_host_id,
            marker_start_id=marker_start_id, marker_end_id=marker_end_id)
        return
    end

    animate_repl_circle_phases(
        state_ptr, timer, duration, joint_point, start_point,
        (angle_theta, radius), marker_host_id, full_sweep)
end

end

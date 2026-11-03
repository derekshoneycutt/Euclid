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

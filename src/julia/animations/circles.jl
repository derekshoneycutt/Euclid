const MarkerRadialTrailSamples = 8f0

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
    marker_host_id::Integer=0)

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
    OdinJuliaBridge.set_arc_geometry(
        state_ptr, marker_host_id, radius, start_theta, angle_theta * t)
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
- formation : Form the sector behind the leg from a sweep reveal started at
  `timer <= 0` while trailing the compass tip; when false, emit the sampled
  radius trail instead.

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
    formation::Bool=true)

    t = clamp(timer / duration, 0f0, 1f0)
    start_theta = Float32(atan(start_point[2] - joint_point[2],
        start_point[1] - joint_point[1]))
    theta = start_theta + angle_theta * t

    end_point = [
        joint_point[1] + radius * Float32(cos(theta)),
        joint_point[2] + radius * Float32(sin(theta)),
        0f0]

    OdinJuliaBridge.lock_compass_joint1(state_ptr, joint_point; sweep = false)
    OdinJuliaBridge.set_compass_active(state_ptr, 3, color)
    OdinJuliaBridge.lock_compass_joint2(state_ptr, end_point)
    OdinJuliaBridge.show_compass(state_ptr)

    OdinJuliaBridge.set_point_color(state_ptr, marker_host_id, color)
    OdinJuliaBridge.set_point_brush(state_ptr, marker_host_id, brush)
    OdinJuliaBridge.set_arc_geometry(
        state_ptr, marker_host_id, radius, start_theta, angle_theta * t)
    OdinJuliaBridge.show_point(state_ptr, marker_host_id)

    if !formation
        emit_filledcircle_radius_trail(state_ptr, joint_point, end_point, color)
    else
        OdinJuliaBridge.emit_trailing_particle(state_ptr, end_point, color)
        if timer <= 0
            OdinJuliaBridge.reveal_sweep!(state_ptr, marker_host_id, duration)
        end
    end
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

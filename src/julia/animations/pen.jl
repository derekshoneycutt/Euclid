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

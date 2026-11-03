const ReplToolTravelTopZ = 1.4f0
const ReplDescendShare = 0.2f0
const ReplDrawShare = 0.6f0

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
    marker_host_id::Integer)

    angle_theta, radius = sweep
    draw_end = duration * (ReplDescendShare + ReplDrawShare)
    start_theta = Float32(atan(start_point[2] - joint_point[2],
        start_point[1] - joint_point[1]))
    OdinJuliaBridge.set_arc_geometry(
        state_ptr, marker_host_id, radius, start_theta, angle_theta)
    final_theta = start_theta + angle_theta
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
    marker_host_id::Integer=0)

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
            brush=brush, color=color, marker_host_id=marker_host_id)
        return
    end

    animate_repl_circle_phases(
        state_ptr, timer, duration, joint_point, start_point,
        (angle_theta, radius), marker_host_id)
end

"""Animate a REPL filled-circle draw with explicit compass descend, draw, and rise phases."""
function animate_repl_draw_filledcircle(
    state_ptr::Ptr{Cvoid},
    timer::Real, duration::Real,
    joint_point::AbstractVector{<:Real}, start_point::AbstractVector{<:Real},
    angle_theta::Real, radius::Real;
    brush::Real=0f0,
    color=:black,
    marker_host_id::Integer=0)

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
            formation=false)
        return
    end

    animate_repl_circle_phases(
        state_ptr, timer, duration, joint_point, start_point,
        (angle_theta, radius), marker_host_id)
end

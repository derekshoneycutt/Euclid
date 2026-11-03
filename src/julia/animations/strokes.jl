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

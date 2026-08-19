module NullAnimation

using ..OdinJuliaBridge
using ..EuclidAnimations

using LinearAlgebra

export get_view_text, initialize, clean, loop

const StartRotation = π / 4f0
const CircleRadius = 0.25f0
const Anchor = [0.5f0, 0.5f0, 0f0]
const StartRotationPos = Anchor +
    [ CircleRadius * cos(StartRotation), CircleRadius * sin(StartRotation), 0]
const PenRotation = π / 4f0
const Color1 = :steelblue
const Color2 = :khaki3
const Color3 = :palevioletred1
const CompassDrawColor = Color1
const PenDrawColor1 = Color2
const PenDrawColor2 = Color3

"""Return the placeholder root view text for the null animation."""
function get_view_text(state_ptr::Ptr{Cvoid})
    "Welcome to Euclid"
end

"""Initialize the null animation's pen, compass, and animation metadata."""
function initialize(state_ptr::Ptr{Cvoid})
    OdinJuliaBridge.set_drawing_sound_enabled(state_ptr, false)

    use_rotation = π - PenRotation

    OdinJuliaBridge.set_animation_meta(state_ptr, 1, StartRotation)
    OdinJuliaBridge.set_animation_meta(state_ptr, 2, -1f0)
    OdinJuliaBridge.set_animation_meta(state_ptr, 3, use_rotation)
    
    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 1, PenDrawColor1)
    OdinJuliaBridge.lock_pen_joint1(state_ptr, 0.9f0, 0.9f0, 0f0)
    OdinJuliaBridge.move_pen_joint2(
        state_ptr, 0.9f0, 0.9f0 + cos(use_rotation), sin(use_rotation))

    OdinJuliaBridge.show_compass(state_ptr)
    OdinJuliaBridge.set_compass_active(state_ptr, 3, CompassDrawColor)
    OdinJuliaBridge.lock_compass_joint1(state_ptr, 0.5f0, 0.5f0, 0f0, sweep = false)
    OdinJuliaBridge.lock_compass_joint2(state_ptr, StartRotationPos, sweep = false)

    line1 = OdinJuliaBridge.create_new_line(state_ptr,
        0f0, 0f0, 0f0,
        0f0, 0f0, 0f0,
        PenDrawColor1, 5f0)
    line2 = OdinJuliaBridge.create_new_line(state_ptr,
        0f0, 0f0, 0f0,
        0f0, 0f0, 0f0,
        PenDrawColor2, 5f0)
    OdinJuliaBridge.set_animation_meta(state_ptr, 4, Float32(line1.host_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, 5, Float32(line1.joint1_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, 6, Float32(line1.joint2_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, 7, Float32(line2.host_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, 8, Float32(line2.joint1_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, 9, Float32(line2.joint2_id))

    circle = OdinJuliaBridge.create_new_circle(state_ptr,
        0.5f0, 0.5f0, 0f0,
        CircleRadius, StartRotation, StartRotation, CompassDrawColor, 5f0)
    OdinJuliaBridge.set_animation_meta(state_ptr, 10, Float32(circle.host_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, 11, Float32(circle.start_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, 12, Float32(circle.end_id))

    OdinJuliaBridge.set_animation_meta(state_ptr, 100, 0f0)
    OdinJuliaBridge.set_animation_meta(state_ptr, 101, 0f0)
end

"""Clean up the null animation; Odin clears its data automatically."""
function clean(state_ptr::Ptr{Cvoid})
    # nothing special on the julia side; our data is auto-cleared in Odin side
end

"""Animate the null animation's oscillating pen line for one frame step."""
function draw_line(state_ptr::Ptr{Cvoid}, dt::Float32)
    draw_line_flag = OdinJuliaBridge.get_animation_meta(state_ptr, 100)
    line1_host = OdinJuliaBridge.get_animation_meta(state_ptr, 4)
    line1_point1 = OdinJuliaBridge.get_animation_meta(state_ptr, 5)
    line1_point2 = OdinJuliaBridge.get_animation_meta(state_ptr, 6)
    line2_host = OdinJuliaBridge.get_animation_meta(state_ptr, 7)
    line2_point1 = OdinJuliaBridge.get_animation_meta(state_ptr, 8)
    line2_point2 = OdinJuliaBridge.get_animation_meta(state_ptr, 9)

    line1_host_desc = OdinJuliaBridge.get_point(state_ptr, Integer(line1_host))
    line2_host_desc = OdinJuliaBridge.get_point(state_ptr, Integer(line2_host))

    pen_direction = OdinJuliaBridge.get_animation_meta(state_ptr, 2)
    pen_rotation_curr = OdinJuliaBridge.get_animation_meta(state_ptr, 3)
    (penx1, peny1, penz1) = OdinJuliaBridge.get_pen_joint1_position(state_ptr)
    (penx2, peny2, penz2) = OdinJuliaBridge.get_pen_joint2_position(state_ptr)
    vec = [penx2, peny2, penz2] - [penx1, peny1, penz1]
    len = norm(vec)
    if pen_direction < 1
        pen_draw_color = PenDrawColor1
        peny1 = peny1 - (dt * 0.4f0)
        peny2 = peny2 - (dt * 0.4f0)

        OdinJuliaBridge.hide_point(state_ptr, Integer(line2_host))
        OdinJuliaBridge.set_point_position(
            state_ptr, Integer(line2_point1), 0.9f0, 0.1f0, 0f0)
        OdinJuliaBridge.set_point_position(
            state_ptr, Integer(line2_point2), 0.9f0, 0.1f0, 0f0)
        if draw_line_flag > 0
            OdinJuliaBridge.set_point_position(
                state_ptr, Integer(line1_point1), 0.9f0, 0.9f0, 0f0)
            OdinJuliaBridge.set_point_position(
                state_ptr, Integer(line1_point2), penx1, peny1, 0f0)
            OdinJuliaBridge.set_point_brush(state_ptr, Integer(line1_host), 5f0)
            OdinJuliaBridge.show_point(state_ptr, Integer(line1_host))
        end

        if peny1 <= 0.1
            peny1 = 0.1f0
            pen_rotation_curr = pen_rotation_curr - (dt * 3f0π/4f0)
            if pen_rotation_curr <= PenRotation
                pen_rotation_curr = PenRotation
                OdinJuliaBridge.set_animation_meta(state_ptr, 2, 1f0)
                draw_line_flag = Float32((Integer(draw_line_flag) + 1) % 2)
                OdinJuliaBridge.set_animation_meta(state_ptr, 100, draw_line_flag)
            end
            peny2 = 0.1f0 + cos(pen_rotation_curr) * len
            penz2 = sin(pen_rotation_curr) * len
            OdinJuliaBridge.set_animation_meta(state_ptr, 3, pen_rotation_curr)
        end
    else
        pen_draw_color = PenDrawColor2
        peny1 = peny1 + (dt * 0.4f0)
        peny2 = peny2 + (dt * 0.4f0)

        OdinJuliaBridge.hide_point(state_ptr, Integer(line1_host))
        OdinJuliaBridge.set_point_position(
            state_ptr, Integer(line1_point1), 0.9f0, 0.1f0, 0f0)
        OdinJuliaBridge.set_point_position(
            state_ptr, Integer(line1_point2), 0.9f0, 0.1f0, 0f0)
        if draw_line_flag > 0
            OdinJuliaBridge.set_point_position(
                state_ptr, Integer(line2_point1), 0.9f0, 0.1f0, 0f0)
            OdinJuliaBridge.set_point_position(
                state_ptr, Integer(line2_point2), penx1, peny1, 0f0)
            OdinJuliaBridge.set_point_brush(state_ptr, Integer(line2_host), 5f0)
            OdinJuliaBridge.show_point(state_ptr, Integer(line2_host))
        end

        if peny1 >= 0.9
            peny1 = 0.9f0
            pen_rotation_curr = pen_rotation_curr + (dt * 3f0π/4f0)
            if  pen_rotation_curr >= π - PenRotation
                pen_rotation_curr = 1f0π - PenRotation
                OdinJuliaBridge.set_animation_meta(state_ptr, 2, -1f0)
            end
            peny2 = 0.9f0 + cos(pen_rotation_curr) * len
            penz2 = sin(pen_rotation_curr) * len
            OdinJuliaBridge.set_animation_meta(state_ptr, 3, pen_rotation_curr)
        end
    end
    OdinJuliaBridge.lock_pen_joint1(state_ptr, penx1, peny1, penz1)
    OdinJuliaBridge.move_pen_joint2(state_ptr, penx2, peny2, penz2)
    OdinJuliaBridge.set_pen_active(state_ptr, 1, pen_draw_color)
    OdinJuliaBridge.emit_trailing_particle(state_ptr, penx1, peny1, penz1, pen_draw_color)
end

"""Animate the null animation's rotating compass circle for one frame step."""
function draw_circle(state_ptr::Ptr{Cvoid}, dt::Float32)
    curr_rotation = OdinJuliaBridge.get_animation_meta(state_ptr, 1)
    curr_rotation = curr_rotation - (dt * π/2)
    if curr_rotation < 0
        curr_rotation = Float32(curr_rotation + 2π)
    end
    
    out_pos = Anchor +
        [ CircleRadius * cos(curr_rotation), CircleRadius * sin(curr_rotation), 0]

    draw_circle_flag = OdinJuliaBridge.get_animation_meta(state_ptr, 101)
    circle_host = OdinJuliaBridge.get_animation_meta(state_ptr, 10)
    circle_start = OdinJuliaBridge.get_animation_meta(state_ptr, 11)
    circle_end = OdinJuliaBridge.get_animation_meta(state_ptr, 12)

    circle_host_desc = OdinJuliaBridge.get_point(state_ptr, Integer(circle_host))

    if abs(curr_rotation - StartRotation) < dt * π/2 && curr_rotation <= StartRotation
        draw_circle_flag = Float32((Integer(draw_circle_flag) + 1) % 2)
        OdinJuliaBridge.set_animation_meta(state_ptr, 101, draw_circle_flag)
    end

    if draw_circle_flag > 0
        OdinJuliaBridge.set_point_position(state_ptr, Integer(circle_end),
            StartRotationPos[1], StartRotationPos[2], StartRotationPos[3])
        OdinJuliaBridge.set_point_position(state_ptr, Integer(circle_start),
            out_pos[1], out_pos[2], out_pos[3])
        OdinJuliaBridge.set_point_brush(state_ptr, Integer(circle_host), 5f0)
        OdinJuliaBridge.show_point(state_ptr, Integer(circle_host))
    else
        OdinJuliaBridge.hide_point(state_ptr, Integer(circle_host))
        OdinJuliaBridge.set_point_position(state_ptr, Integer(circle_start),
            StartRotationPos[1], StartRotationPos[2], StartRotationPos[3])
    end

    OdinJuliaBridge.set_animation_meta(state_ptr, 1, curr_rotation)
    OdinJuliaBridge.lock_compass_joint2(state_ptr, out_pos, sweep = false)
    OdinJuliaBridge.emit_trailing_particle(state_ptr, out_pos, CompassDrawColor)
end

"""Advance the null animation by one frame, updating pen and compass."""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    draw_line(state_ptr, dt)
    draw_circle(state_ptr, dt)
end

end


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

"""Complete immutable state for one null animation generation."""
struct AnimationState
    line1_host::Int64
    line1_point1::Int64
    line1_point2::Int64
    line2_host::Int64
    line2_point1::Int64
    line2_point2::Int64
    circle_host::Int64
    circle_start::Int64
    circle_end::Int64
    curr_rotation::Float32
    pen_direction::Float32
    pen_rotation::Float32
    draw_line_flag::Float32
    draw_circle_flag::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

"""Return state with updated pen motion and unchanged compass state."""
function with_line_motion(
    state::AnimationState, pen_direction::Float32,
    pen_rotation::Float32, draw_line_flag::Float32)

    return AnimationState(
        state.line1_host, state.line1_point1, state.line1_point2,
        state.line2_host, state.line2_point1, state.line2_point2,
        state.circle_host, state.circle_start, state.circle_end,
        state.curr_rotation, pen_direction, pen_rotation,
        draw_line_flag, state.draw_circle_flag)
end

"""Return state with updated compass motion and unchanged pen state."""
function with_circle_motion(
    state::AnimationState, curr_rotation::Float32,
    draw_circle_flag::Float32)

    return AnimationState(
        state.line1_host, state.line1_point1, state.line1_point2,
        state.line2_host, state.line2_point1, state.line2_point2,
        state.circle_host, state.circle_start, state.circle_end,
        curr_rotation, state.pen_direction, state.pen_rotation,
        state.draw_line_flag, draw_circle_flag)
end

"""Return the placeholder root view text for the null animation."""
function get_view_text(state_ptr::Ptr{Cvoid})
    "Welcome to Euclid"
end

"""Initialize the null animation's pen, compass, and canonical state."""
function initialize(state_ptr::Ptr{Cvoid})
    OdinJuliaBridge.set_drawing_sound_enabled(state_ptr, false)

    use_rotation = π - PenRotation

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
        [0f0, 0f0, 0f0], [0f0, 0f0, 0f0], PenDrawColor1, 5f0)
    line2 = OdinJuliaBridge.create_new_line(state_ptr,
        [0f0, 0f0, 0f0], [0f0, 0f0, 0f0], PenDrawColor2, 5f0)
    circle = OdinJuliaBridge.create_new_circle(state_ptr,
        [0.5f0, 0.5f0, 0f0], CircleRadius, StartRotation, StartRotation,
        CompassDrawColor, 5f0)

    state = AnimationState(
        line1.host_id, line1.joint1_id, line1.joint2_id,
        line2.host_id, line2.joint1_id, line2.joint2_id,
        circle.host_id, circle.start_id, circle.end_id,
        StartRotation, -1f0, Float32(use_rotation), 0f0, 0f0)
    OdinJuliaBridge.set_animation_value!(state_ptr, StateKey, state)
end

"""Clean up the null animation; Odin clears its data automatically."""
function clean(state_ptr::Ptr{Cvoid})
    # nothing special on the julia side; our data is auto-cleared in Odin side
end

"""Animate the null animation's oscillating pen line for one frame step."""
function draw_line(state_ptr::Ptr{Cvoid}, dt::Float32)
    state, status = OdinJuliaBridge.get_animation_value(state_ptr, StateKey)
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return
    draw_line_flag = state.draw_line_flag
    line1_host = state.line1_host
    line1_point1 = state.line1_point1
    line1_point2 = state.line1_point2
    line2_host = state.line2_host
    line2_point1 = state.line2_point1
    line2_point2 = state.line2_point2

    line1_host_desc = OdinJuliaBridge.get_point(state_ptr, line1_host)
    line2_host_desc = OdinJuliaBridge.get_point(state_ptr, line2_host)

    pen_direction = state.pen_direction
    pen_rotation_curr = state.pen_rotation
    (penx1, peny1, penz1) = OdinJuliaBridge.get_pen_joint1_position(state_ptr)
    (penx2, peny2, penz2) = OdinJuliaBridge.get_pen_joint2_position(state_ptr)
    vec = [penx2, peny2, penz2] - [penx1, peny1, penz1]
    len = norm(vec)
    if pen_direction < 1
        pen_draw_color = PenDrawColor1
        peny1 = peny1 - (dt * 0.4f0)
        peny2 = peny2 - (dt * 0.4f0)

        OdinJuliaBridge.hide_point(state_ptr, line2_host)
        OdinJuliaBridge.set_point_position(
            state_ptr, line2_point1, 0.9f0, 0.1f0, 0f0)
        OdinJuliaBridge.set_point_position(
            state_ptr, line2_point2, 0.9f0, 0.1f0, 0f0)
        if draw_line_flag > 0
            OdinJuliaBridge.set_point_position(
                state_ptr, line1_point1, 0.9f0, 0.9f0, 0f0)
            OdinJuliaBridge.set_point_position(
                state_ptr, line1_point2, penx1, peny1, 0f0)
            OdinJuliaBridge.set_point_brush(state_ptr, line1_host, 5f0)
            OdinJuliaBridge.show_point(state_ptr, line1_host)
        end

        if peny1 <= 0.1
            peny1 = 0.1f0
            pen_rotation_curr = pen_rotation_curr - (dt * 3f0π/4f0)
            if pen_rotation_curr <= PenRotation
                pen_rotation_curr = PenRotation
                pen_direction = 1f0
                draw_line_flag = Float32((Integer(draw_line_flag) + 1) % 2)
            end
            peny2 = 0.1f0 + cos(pen_rotation_curr) * len
            penz2 = sin(pen_rotation_curr) * len
        end
    else
        pen_draw_color = PenDrawColor2
        peny1 = peny1 + (dt * 0.4f0)
        peny2 = peny2 + (dt * 0.4f0)

        OdinJuliaBridge.hide_point(state_ptr, line1_host)
        OdinJuliaBridge.set_point_position(
            state_ptr, line1_point1, 0.9f0, 0.1f0, 0f0)
        OdinJuliaBridge.set_point_position(
            state_ptr, line1_point2, 0.9f0, 0.1f0, 0f0)
        if draw_line_flag > 0
            OdinJuliaBridge.set_point_position(
                state_ptr, line2_point1, 0.9f0, 0.9f0, 0f0)
            OdinJuliaBridge.set_point_position(
                state_ptr, line2_point2, penx1, peny1, 0f0)
            OdinJuliaBridge.set_point_brush(state_ptr, line2_host, 5f0)
            OdinJuliaBridge.show_point(state_ptr, line2_host)
        end

        if peny1 >= 0.9
            peny1 = 0.9f0
            pen_rotation_curr = pen_rotation_curr + (dt * 3f0π/4f0)
            if  pen_rotation_curr >= π - PenRotation
                pen_rotation_curr = 1f0π - PenRotation
                pen_direction = -1f0
            end
            peny2 = 0.9f0 + cos(pen_rotation_curr) * len
            penz2 = sin(pen_rotation_curr) * len
        end
    end
    OdinJuliaBridge.lock_pen_joint1(state_ptr, penx1, peny1, penz1)
    OdinJuliaBridge.move_pen_joint2(state_ptr, penx2, peny2, penz2)
    OdinJuliaBridge.set_pen_active(state_ptr, 1, pen_draw_color)
    OdinJuliaBridge.emit_trailing_particle(state_ptr, penx1, peny1, penz1, pen_draw_color)
    OdinJuliaBridge.set_animation_value!(state_ptr, StateKey,
        with_line_motion(state, pen_direction, pen_rotation_curr, draw_line_flag))
end

"""Animate the null animation's rotating compass circle for one frame step."""
function draw_circle(state_ptr::Ptr{Cvoid}, dt::Float32)
    state, status = OdinJuliaBridge.get_animation_value(state_ptr, StateKey)
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return
    curr_rotation = state.curr_rotation
    curr_rotation = curr_rotation - (dt * π/2)
    if curr_rotation < 0
        curr_rotation = Float32(curr_rotation + 2π)
    end
    
    out_pos = Anchor +
        [ CircleRadius * cos(curr_rotation), CircleRadius * sin(curr_rotation), 0]

    draw_circle_flag = state.draw_circle_flag
    circle_host = state.circle_host
    circle_start = state.circle_start
    circle_end = state.circle_end

    circle_host_desc = OdinJuliaBridge.get_point(state_ptr, circle_host)

    if abs(curr_rotation - StartRotation) < dt * π/2 && curr_rotation <= StartRotation
        draw_circle_flag = Float32((Integer(draw_circle_flag) + 1) % 2)
    end

    if draw_circle_flag > 0
        OdinJuliaBridge.set_point_position(state_ptr, circle_end,
            StartRotationPos[1], StartRotationPos[2], StartRotationPos[3])
        OdinJuliaBridge.set_point_position(state_ptr, circle_start,
            out_pos[1], out_pos[2], out_pos[3])
        OdinJuliaBridge.set_point_brush(state_ptr, circle_host, 5f0)
        OdinJuliaBridge.show_point(state_ptr, circle_host)
    else
        OdinJuliaBridge.hide_point(state_ptr, circle_host)
        OdinJuliaBridge.set_point_position(state_ptr, circle_start,
            StartRotationPos[1], StartRotationPos[2], StartRotationPos[3])
    end

    OdinJuliaBridge.lock_compass_joint2(state_ptr, out_pos, sweep = false)
    OdinJuliaBridge.emit_trailing_particle(state_ptr, out_pos, CompassDrawColor)
    OdinJuliaBridge.set_animation_value!(state_ptr, StateKey,
        with_circle_motion(state, curr_rotation, draw_circle_flag))
end

"""Advance the null animation by one frame, updating pen and compass."""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    draw_line(state_ptr, dt)
    draw_circle(state_ptr, dt)
end

end


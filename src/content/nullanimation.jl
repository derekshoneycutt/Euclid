module NullAnimation

using ..OdinJuliaBridge
using ..EuclidAnimations

using LinearAlgebra

export get_view_content, initialize, clean, loop, animation_entry

const PointA = Float32[0.40f0, 0.60f0, 0f0]
const PointB = Float32[0.60f0, 0.40f0, 0f0]
const Radius = norm(PointB - PointA)
const PointC = PointA + Radius * Float32[cos(π / 12f0), sin(π / 12f0), 0f0]
const MidpointAB = (PointA + PointB) / 2f0
const CircleSweep = 2f0 * π

const SideStarts = (PointA, PointB, PointC)
const SideEnds = (PointB, PointC, PointA)
const SideColors = (:grey60, :palevioletred1, :khaki3)
const CircleColors = (:steelblue, :palevioletred1)
const ReflectionStart = (PointA, PointB, PointB, PointC, PointC, PointA)
const ReflectionMirrored = (PointB, PointA, PointA, PointC, PointC, PointB)

const PenTopZ = 1.4f0
const CompassTopZ = 1.4f0
const Brush = 5f0
const ToolDuration = 1.8f0
const CircleDrawDuration = 4.4f0
const CompassMoveDuration = 1.6f0
const LineDrawDuration = 2.2f0
const ReflectionDuration = 2.4f0
const HoldDuration = 1.2f0

const PhaseCompassDescend = 0f0
const PhaseDrawCircleA = 1f0
const PhaseMoveCompass = 2f0
const PhaseDrawCircleB = 3f0
const PhaseCompassRise = 4f0
const PhasePenDescend = 5f0
const PhaseDrawAB = 6f0
const PhaseDrawBC = 7f0
const PhaseDrawCA = 8f0
const PhasePenRise = 9f0
const PhaseReflectFirst = 10f0
const PhaseReflectSecond = 11f0
const PhaseHold = 12f0

"""Stable native handles for one line owned by the null animation."""
struct LineIds
    host::Int64
    joint1::Int64
    joint2::Int64
end

"""Complete immutable state for one null-animation cycle."""
struct AnimationState
    lines::NTuple{3,LineIds}
    circles::NTuple{2,Int64}
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(state.lines, state.circles, phase, timer)
end

"""Return the placeholder root view content for the null animation."""
function get_view_content(_state_ptr::Ptr{Cvoid})
    return "Welcome to Euclid"
end

"""Set all triangle endpoints to one exact reflection pose."""
function set_triangle_pose!(state_ptr::Ptr{Cvoid}, state::AnimationState,
    pose::NTuple{6,Vector{Float32}})

    for i in 1:3
        OdinJuliaBridge.set_point_position(
            state_ptr, state.lines[i].joint1, pose[2i - 1])
        OdinJuliaBridge.set_point_position(
            state_ptr, state.lines[i].joint2, pose[2i])
    end
end

"""Rotate every triangle endpoint halfway around its reflection axis."""
function animate_reflection!(state_ptr::Ptr{Cvoid}, state::AnimationState,
    starts::NTuple{6,Vector{Float32}}, timer::Float32)

    for i in 1:3
        EuclidAnimations.transform_rotate_point(
            state_ptr, state.lines[i].joint1, starts[2i - 1],
            PointC, MidpointAB, π, timer, ReflectionDuration)
        EuclidAnimations.transform_rotate_point(
            state_ptr, state.lines[i].joint2, starts[2i],
            PointC, MidpointAB, π, timer, ReflectionDuration)
    end
end

"""Reset hidden geometry and elevated instruments for a fresh cycle."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhaseCompassDescend, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [state.lines[1].host, state.lines[2].host, state.lines[3].host,
         state.circles[1], state.circles[2]])
    set_triangle_pose!(state_ptr, state, ReflectionStart)
    OdinJuliaBridge.set_arc_geometry(
        state_ptr, state.circles[1], Radius, 7f0 * π / 4f0, 0f0)
    OdinJuliaBridge.set_arc_geometry(
        state_ptr, state.circles[2], Radius, 3f0 * π / 4f0, 0f0)
    reset_tools(state_ptr)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Hide and elevate both drawing instruments for reset."""
function reset_tools(state_ptr::Ptr{Cvoid})
    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.lock_pen_joint1(state_ptr, PointA[1], PointA[2], PenTopZ)
    OdinJuliaBridge.move_pen_joint2(
        state_ptr, PointA[1], PointA[2], PenTopZ + 0.14f0)
    OdinJuliaBridge.hide_compass(state_ptr)
    OdinJuliaBridge.lock_compass_joint1(
        state_ptr, PointA[1], PointA[2], CompassTopZ, sweep=false)
    OdinJuliaBridge.lock_compass_joint2(
        state_ptr, PointB[1], PointB[2], CompassTopZ, sweep=false)
end

"""Initialize the null animation's construction geometry and cycle state."""
function initialize(state_ptr::Ptr{Cvoid})
    OdinJuliaBridge.set_drawing_sound_enabled(state_ptr, false)
    lines = ntuple(3) do i
        line = OdinJuliaBridge.create_new_line(
            state_ptr, SideStarts[i], SideStarts[i], SideColors[i], 0f0)
        LineIds(line.host_id, line.joint1_id, line.joint2_id)
    end
    circle_a = OdinJuliaBridge.create_new_circle(
        state_ptr, PointA, Radius, 7f0 * π / 4f0, 0f0, CircleColors[1], 0f0)
    circle_b = OdinJuliaBridge.create_new_circle(
        state_ptr, PointB, Radius, 3f0 * π / 4f0, 0f0, CircleColors[2], 0f0)
    state = AnimationState(
        lines, (circle_a.host_id, circle_b.host_id), PhaseCompassDescend, 0f0)
    reset_cycle_state(state_ptr, state)
end

"""Clean up the null animation; Odin clears its data automatically."""
function clean(_state_ptr::Ptr{Cvoid})
end

"""Return the duration of one compass construction phase."""
function compass_phase_duration(phase::Float32)
    if phase == PhaseCompassDescend || phase == PhaseCompassRise
        return ToolDuration
    elseif phase == PhaseMoveCompass
        return CompassMoveDuration
    end
    return CircleDrawDuration
end

"""Apply the visible work for one compass construction phase."""
function animate_compass_phase(state_ptr::Ptr{Cvoid}, state::AnimationState,
    phase::Float32, timer::Float32)

    if phase == PhaseCompassDescend
        EuclidAnimations.animate_compass_descend(state_ptr, timer, ToolDuration,
            CompassTopZ, PointA[1], PointA[2], PointB[1], PointB[2])
    elseif phase == PhaseDrawCircleA
        EuclidAnimations.animate_draw_circle(state_ptr, timer, CircleDrawDuration,
            PointA, PointB, CircleSweep, Radius;
            brush=Brush, color=CircleColors[1], marker_host_id=state.circles[1])
    elseif phase == PhaseMoveCompass
        EuclidAnimations.animate_compass_arcmove(state_ptr, timer,
            CompassMoveDuration, PointA, PointB, PointB, PointA)
    elseif phase == PhaseDrawCircleB
        EuclidAnimations.animate_draw_circle(state_ptr, timer, CircleDrawDuration,
            PointB, PointA, CircleSweep, Radius;
            brush=Brush, color=CircleColors[2], marker_host_id=state.circles[2])
    else
        EuclidAnimations.animate_compass_rise(state_ptr, timer, ToolDuration,
            CompassTopZ, PointB[1], PointB[2], PointA[1], PointA[2])
    end
end

"""Advance the circle-construction phases by one fixed frame step."""
function advance_compass_phase(state_ptr::Ptr{Cvoid}, state::AnimationState,
    phase::Float32, timer::Float32, dt::Float32)

    animate_compass_phase(state_ptr, state, phase, timer)
    timer += dt
    if timer >= compass_phase_duration(phase)
        return phase + 1f0, 0f0
    end
    return phase, timer
end

"""Apply one pen drawing phase and return its duration."""
function animate_pen_phase(state_ptr::Ptr{Cvoid}, state::AnimationState,
    phase::Float32, timer::Float32)

    if phase == PhasePenDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, ToolDuration, PenTopZ, PointA[1], PointA[2])
        return ToolDuration
    elseif phase == PhasePenRise
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, ToolDuration, PenTopZ, PointA[1], PointA[2])
        return ToolDuration
    end

    side_index = Int(phase - PhaseDrawAB) + 1
    EuclidAnimations.animate_draw_line(state_ptr, timer, LineDrawDuration,
        SideStarts[side_index], SideEnds[side_index];
        penbrush=Brush, pencolor=SideColors[side_index],
        line_host_id=state.lines[side_index].host,
        line_joint1_id=state.lines[side_index].joint1,
        line_joint2_id=state.lines[side_index].joint2)
    return LineDrawDuration
end

"""Advance the pen construction phases by one fixed frame step."""
function advance_pen_phase(state_ptr::Ptr{Cvoid}, state::AnimationState,
    phase::Float32, timer::Float32, dt::Float32)

    duration = animate_pen_phase(state_ptr, state, phase, timer)
    timer += dt
    if timer >= duration
        return phase + 1f0, 0f0
    end
    return phase, timer
end

"""Advance one of the two exact half-turn reflection phases."""
function advance_reflection_phase(state_ptr::Ptr{Cvoid}, state::AnimationState,
    phase::Float32, timer::Float32, dt::Float32)

    starts = phase == PhaseReflectFirst ? ReflectionStart : ReflectionMirrored
    animate_reflection!(state_ptr, state, starts, timer)
    timer += dt
    if timer < ReflectionDuration
        return phase, timer
    end

    final_pose = phase == PhaseReflectFirst ? ReflectionMirrored : ReflectionStart
    set_triangle_pose!(state_ptr, state, final_pose)
    return phase + 1f0, 0f0
end

"""Advance the null animation by one fixed frame step."""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    state, status = OdinJuliaBridge.get_animation_value(state_ptr, StateKey)
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return
    phase = state.phase
    timer = state.timer

    if phase <= PhaseCompassRise
        phase, timer = advance_compass_phase(state_ptr, state, phase, timer, dt)
        phase == PhasePenDescend && OdinJuliaBridge.hide_compass(state_ptr)
    elseif phase <= PhasePenRise
        phase, timer = advance_pen_phase(state_ptr, state, phase, timer, dt)
        phase == PhaseReflectFirst && OdinJuliaBridge.hide_pen(state_ptr)
    elseif phase == PhaseReflectFirst || phase == PhaseReflectSecond
        phase, timer = advance_reflection_phase(state_ptr, state, phase, timer, dt)
    else
        timer += dt
        if timer >= HoldDuration
            reset_cycle_state(state_ptr, state)
            return
        end
    end

    OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, phase, timer))
end

"""Dispatch one bridge-stable lifecycle operation for the null animation."""
function animation_entry(
    state_ptr::Ptr{Cvoid}, operation::Int32, dt::Float32)::Bool

    if operation == OdinJuliaBridge.ANIMATION_OPERATION_ENTER
        initialize(state_ptr)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_TICK
        loop(state_ptr, dt)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_EXIT
        clean(state_ptr)
    else
        return false
    end
    return true
end

end

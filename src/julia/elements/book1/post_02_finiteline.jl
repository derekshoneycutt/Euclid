module ElementsOnePostulatesFiniteLine

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

using LinearAlgebra

export get_view_text, initialize, clean, loop

const StartPoint = [0.25f0, 0.75f0, 0f0]
const MidPoint = [0.3f0, 0.7f0, 0f0]
const EndPoint = [0.75f0, 0.25f0, 0f0]
const PenTopZ = 1.4f0

const LineColor = :steelblue
const Point1Color = :palevioletred1
const Point2Color = :khaki3
const LineMaxBrush = 5f0
const PointMaxBrush = 5f0

const DescendDuration = 1.8f0
const MoveToJoint1Duration = 1f0
const MoveToJoint2Duration = 1f0
const ExtremityTrailDuration = 2f0
const DrawInitLineDuration = 1.5f0
const DrawLineDuration = 4.2f0
const EndLiftDuration = 1.8f0

"""Stable native handles for one line owned by the animation."""
struct LineIds
    host::Int64
    joint1::Int64
    joint2::Int64
end

"""Complete immutable state for one finite-line animation generation."""
struct AnimationState
    initial_line::LineIds
    line::LineIds
    points::NTuple{2,Int64}
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhaseDescend = 0f0
const PhasePutJoint1 = 1f0
const PhaseMoveToJoint2 = 2f0
const PhasePutJoint2 = 3f0
const PhaseMoveToJoint1 = 4f0
const PhaseDrawInitLine = 5f0
const PhaseMoveToJoint1Again = 6f0
const PhaseDrawLine = 7f0
const PhaseEndLift = 8f0

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(state.initial_line, state.line, state.points, phase, timer)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """Euclid Elements - Book I - Postulates: Produce a Finite Line

Let the following be postulated:

To produce a finite straight line continuously in a straight line."""
    latex = raw"""\textbf{Euclid Elements - Book I - Postulates}: \textit{Produce a Finite Line}

\textit{Let the following be postulated:}

To produce a finite straight line \euclidline[color=steelblue,length=3,thickness=4] continuously in a straight line."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset the animation cycle while preserving its native handles."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    point1id, point2id = state.points
    init_line_host_id = state.initial_line.host
    init_line_joint1_id = state.initial_line.joint1
    init_line_joint2_id = state.initial_line.joint2
    line_host_id = state.line.host
    line_joint1_id = state.line.joint1
    line_joint2_id = state.line.joint2

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhaseDescend, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.hide_point(state_ptr, init_line_host_id)
    OdinJuliaBridge.set_point_position(
        state_ptr, init_line_joint1_id, StartPoint[1], StartPoint[2], StartPoint[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, init_line_joint2_id, StartPoint[1], StartPoint[2], StartPoint[3])

    OdinJuliaBridge.hide_point(state_ptr, line_host_id)
    OdinJuliaBridge.set_point_position(
        state_ptr, line_joint1_id, StartPoint[1], StartPoint[2], StartPoint[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, line_joint2_id, StartPoint[1], StartPoint[2], StartPoint[3])

    OdinJuliaBridge.hide_point_batch(state_ptr, [point1id, point2id])

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, LineColor)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    point1 = OdinJuliaBridge.create_new_point(
        state_ptr,
        StartPoint[1], StartPoint[2], StartPoint[3],
        Point1Color,
        0f0)
    point2 = OdinJuliaBridge.create_new_point(
        state_ptr,
        EndPoint[1], EndPoint[2], EndPoint[3],
        Point2Color,
        0f0)

    init_line = OdinJuliaBridge.create_new_line(
        state_ptr, StartPoint, StartPoint,
        LineColor, 5f0)
    OdinJuliaBridge.show_point(state_ptr, init_line.host_id)

    line = OdinJuliaBridge.create_new_line(
        state_ptr, StartPoint, StartPoint,
        LineColor, 0f0)

    state = AnimationState(
        LineIds(init_line.host_id, init_line.joint1_id, init_line.joint2_id),
        LineIds(line.host_id, line.joint1_id, line.joint2_id),
        (point1.index, point2.index), PhaseDescend, 0f0)
    reset_cycle_state(state_ptr, state)
    OdinJuliaBridge.publish_view_update(state_ptr, get_view_text)
end

"""Clean any extra animation data at the end of performance"""
function clean(state_ptr::Ptr{Cvoid})
end

"""Perform an iteration of the animation loop for this animation"""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    state, status = OdinJuliaBridge.get_animation_value(state_ptr, StateKey)
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return
    point1id, point2id = state.points
    init_line_host_id = state.initial_line.host
    init_line_joint1_id = state.initial_line.joint1
    init_line_joint2_id = state.initial_line.joint2
    line_host_id = state.line.host
    line_joint1_id = state.line.joint1
    line_joint2_id = state.line.joint2

    if line_host_id < 0
        return
    end

    phase = state.phase
    timer = state.timer

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, StartPoint[1], StartPoint[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhasePutJoint1
            timer = 0f0
        end
    elseif phase == PhasePutJoint1
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, ExtremityTrailDuration, StartPoint,
            PointMaxBrush, Point1Color, point1id)

        timer += dt
        if timer >= ExtremityTrailDuration
            phase = PhaseMoveToJoint2
            timer = 0f0
        end
    elseif phase == PhaseMoveToJoint2
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, MoveToJoint2Duration,
            StartPoint, MidPoint, 0.15f0, 1, :none)

        timer += dt
        if timer >= MoveToJoint2Duration
            phase = PhasePutJoint2
            timer = 0f0
        end
    elseif phase == PhasePutJoint2
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, ExtremityTrailDuration, MidPoint,
            PointMaxBrush, Point2Color, point2id)

        timer += dt
        if timer >= ExtremityTrailDuration
            phase = PhaseMoveToJoint1
            timer = 0f0
        end
    elseif phase == PhaseMoveToJoint1
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, MoveToJoint1Duration,
            MidPoint, StartPoint, 0.15f0, 1, :none)

        timer += dt
        if timer >= MoveToJoint1Duration
            phase = PhaseDrawInitLine
            timer = 0f0
        end
    elseif phase == PhaseDrawInitLine
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawInitLineDuration,
            StartPoint, MidPoint;
            penbrush=LineMaxBrush,
            pencolor=LineColor,
            line_host_id=init_line_host_id,
            line_joint1_id=init_line_joint1_id,
            line_joint2_id=init_line_joint2_id)

        timer += dt
        if timer >= DrawInitLineDuration
            phase = PhaseMoveToJoint1Again
            timer = 0f0
        end
    elseif phase == PhaseMoveToJoint1Again
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, MoveToJoint1Duration,
            MidPoint, StartPoint, 0.25f0, 1, :none)

        timer += dt
        if timer >= MoveToJoint1Duration
            phase = PhaseDrawLine
            timer = 0f0
        end
    elseif phase == PhaseDrawLine
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawLineDuration,
            StartPoint, EndPoint;
            penbrush=LineMaxBrush,
            pencolor=LineColor,
            line_host_id=line_host_id,
            line_joint1_id=line_joint1_id,
            line_joint2_id=line_joint2_id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ, EndPoint[1], EndPoint[2])

        timer += dt
        if timer >= EndLiftDuration
            reset_cycle_state(state_ptr, state)
            return
        end
    end

    OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, phase, timer))
end

end

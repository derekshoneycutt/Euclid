module HilbertChapterOneTheorem3

using UUIDs
using ..AnimationCatalog

const AnimationId = UUID("d119466f-cf6b-569a-8228-f5e21b753b74")

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

export get_view_text, initialize, clean, loop, animation_entry

const LineStart = [0.16f0, 0.52f0, 0f0]
const LineEnd = [0.84f0, 0.52f0, 0f0]
const PointA = [0.34f0, 0.52f0, 0f0]
const PointB = [0.68f0, 0.52f0, 0f0]
const PenTopZ = 1.4f0

const LineColor = :grey60
const PointAColor = :steelblue
const PointBColor = :palevioletred1
const PointTapColor = :khaki3
const LineMaxBrush = 5f0
const PointMaxBrush = 5f0

const DescendDuration = 1.8f0
const DrawLineDuration = 4.2f0
const ArcMoveDuration = 2f0
const PointTrailDuration = 2f0
const TapSweepDuration = 5f0
const EndLiftDuration = 1.8f0

"""Stable native handles for one line owned by the animation."""
struct LineIds
    host::Int64
    joint1::Int64
    joint2::Int64
end

"""Complete immutable state for one Theorem 3 animation generation."""
struct AnimationState
    line::LineIds
    point_a::Int64
    point_b::Int64
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhaseDescend = 0f0
const PhaseDrawLine = 1f0
const PhaseMoveToPointA = 2f0
const PhasePutPointA = 3f0
const PhaseMoveToPointB = 4f0
const PhasePutPointB = 5f0
const PhaseTapToPointA = 6f0
const PhaseTapToPointB = 7f0
const PhaseEndLift = 8f0

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(state.line, state.point_a, state.point_b, phase, timer)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - Theorem 3

Between any two points of a straight line, there always exists an unlimited number of points."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - Theorem 3}

Between any two points \euclidpoint[color=steelblue,size=1] \euclidpoint[color=palevioletred1,size=1] of a straight line \euclidline[color=grey60,length=3,thickness=4], there always exists an unlimited number of points \euclidpoint[color=khaki3,size=1]."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset the animation cycle while preserving its native handles."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    line_host_id = state.line.host
    line_joint1_id = state.line.joint1
    line_joint2_id = state.line.joint2
    point_a_id = state.point_a
    point_b_id = state.point_b

    OdinJuliaBridge.hide_point_batch(state_ptr, [line_host_id, point_a_id, point_b_id])

    OdinJuliaBridge.set_point_position(state_ptr, line_joint1_id, LineStart)
    OdinJuliaBridge.set_point_position(state_ptr, line_joint2_id, LineStart)

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, LineColor)

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhaseDescend, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    line = OdinJuliaBridge.create_new_line(
        state_ptr, LineStart, LineStart, LineColor, 0f0)
    point_a = OdinJuliaBridge.create_new_point(
        state_ptr, PointA, PointAColor, 0f0)
    point_b = OdinJuliaBridge.create_new_point(
        state_ptr, PointB, PointBColor, 0f0)

    state = AnimationState(
        LineIds(line.host_id, line.joint1_id, line.joint2_id),
        point_a.index, point_b.index, PhaseDescend, 0f0)
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
    line_host_id = state.line.host
    line_joint1_id = state.line.joint1
    line_joint2_id = state.line.joint2
    point_a_id = state.point_a
    point_b_id = state.point_b

    if line_host_id < 0
        return
    end

    phase = state.phase
    timer = state.timer

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, LineStart[1], LineStart[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawLine
            timer = 0f0
        end
    elseif phase == PhaseDrawLine
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawLineDuration,
            LineStart, LineEnd;
            penbrush=LineMaxBrush,
            pencolor=LineColor,
            line_host_id=line_host_id,
            line_joint1_id=line_joint1_id,
            line_joint2_id=line_joint2_id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseMoveToPointA
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            LineEnd, PointA, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePutPointA
            timer = 0f0
        end
    elseif phase == PhasePutPointA
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointTrailDuration, PointA,
            PointMaxBrush, PointAColor, point_a_id)

        timer += dt
        if timer >= PointTrailDuration
            phase = PhaseMoveToPointB
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointA, PointB, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePutPointB
            timer = 0f0
        end
    elseif phase == PhasePutPointB
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointTrailDuration, PointB,
            PointMaxBrush, PointBColor, point_b_id)

        timer += dt
        if timer >= PointTrailDuration
            phase = PhaseTapToPointA
            timer = 0f0
        end
    elseif phase == PhaseTapToPointA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, TapSweepDuration,
            PointB, PointA, 0.15f0, 10, PointTapColor)

        timer += dt
        if timer >= TapSweepDuration
            phase = PhaseTapToPointB
            timer = 0f0
        end
    elseif phase == PhaseTapToPointB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, TapSweepDuration,
            PointA, PointB, 0.15f0, 10, PointTapColor)

        timer += dt
        if timer >= TapSweepDuration
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ, PointB[1], PointB[2])

        timer += dt
        if timer >= EndLiftDuration
            reset_cycle_state(state_ptr, state)
            return
        end
    end

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, phase, timer))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return
end


"""Dispatch one bridge-stable lifecycle operation for this animation."""
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

AnimationCatalog.animation(
    HilbertChapterOneTheorem3.AnimationId, HilbertChapterOneTheorem3.animation_entry)

module HilbertChapterOneAxiomI7

using UUIDs
using ..AnimationCatalog

const AnimationId = UUID("8c128636-9d9f-508f-9243-4ddbeb93eead")

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

using LinearAlgebra

export get_view_text, initialize, clean, loop, animation_entry

const LineStart = [0.18f0, 0.58f0, 0f0]
const LineEnd = [0.82f0, 0.58f0, 0f0]
const PointOnLineA = [0.34f0, 0.58f0, 0f0]
const PointOnLineB = [0.66f0, 0.58f0, 0f0]
const PointOffLine = [0.56f0, 0.74f0, 0f0]
const PointSuspended = [0.72f0, 0.32f0, 0.35f0]
const PenTopZ = 1.4f0

const LineColor = :steelblue
const PointOnLineAColor = :palevioletred1
const PointOnLineBColor = :khaki3
const PointOffLineColor = :steelblue
const PointSuspendedColor = :grey60
const LineMaxBrush = 5f0
const PointMaxBrush = 5f0

const DescendDuration = 1.8f0
const DrawLineDuration = 4.2f0
const MoveToPointADuration = 1.8f0
const MoveToPointBDuration = 1.8f0
const MoveToPointCDuration = 1.8f0
const MoveToPointDDuration = 1.8f0
const PointTrailDuration = 2f0
const EndLiftDuration = 1.8f0
const FinalHoldDuration = 1.2f0

"""Complete immutable state for one Axiom I,7 animation generation."""
struct AnimationState
    line_host::Int64
    line_point_a::Int64
    line_point_b::Int64
    point_a::Int64
    point_b::Int64
    point_c::Int64
    point_d::Int64
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
const PhaseMoveToPointC = 6f0
const PhasePutPointC = 7f0
const PhaseMoveToPointD = 8f0
const PhasePutPointD = 9f0
const PhaseEndLift = 10f0
const PhaseFinalHold = 11f0

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(
        state.line_host, state.line_point_a, state.line_point_b,
        state.point_a, state.point_b, state.point_c, state.point_d,
        phase, timer)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - Axiom I,7

I, 7. Upon every straight line there exists at least two points, in every plane at least three points not lying in the same straight line, and in space there exist at least four points not lying in a plane."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - Axiom I,7}

\textbf{I, 7.} Upon every straight line \euclidline[color=steelblue,length=3,thickness=4] there exists at least two points \euclidpoint[color=palevioletred1,size=1] \euclidpoint[color=khaki3,size=1], in every plane at least three points \euclidpoint[color=steelblue,size=1] not lying in the same straight line, and in space there exist at least four points \euclidpoint[color=grey60,size=1] not lying in a plane."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset cycle timing transactionally before restoring visible animation state."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    line_host_id = state.line_host
    line_point_a_id = state.line_point_a
    line_point_b_id = state.line_point_b
    point_a_id = state.point_a
    point_b_id = state.point_b
    point_c_id = state.point_c
    point_d_id = state.point_d

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhaseDescend, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [line_host_id, point_a_id, point_b_id, point_c_id, point_d_id])

    OdinJuliaBridge.set_point_position(
        state_ptr, line_point_a_id, LineStart[1], LineStart[2], LineStart[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, line_point_b_id, LineStart[1], LineStart[2], LineStart[3])

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, LineColor)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    line = OdinJuliaBridge.create_new_line(
        state_ptr, LineStart, LineStart, LineColor, 0f0)
    point_a = OdinJuliaBridge.create_new_point(
        state_ptr, PointOnLineA, PointOnLineAColor, 0f0)
    point_b = OdinJuliaBridge.create_new_point(
        state_ptr, PointOnLineB, PointOnLineBColor, 0f0)
    point_c = OdinJuliaBridge.create_new_point(
        state_ptr, PointOffLine, PointOffLineColor, 0f0)
    point_d = OdinJuliaBridge.create_new_point(
        state_ptr, PointSuspended, PointSuspendedColor, 0f0)

    state = AnimationState(
        line.host_id, line.joint1_id, line.joint2_id,
        point_a.index, point_b.index, point_c.index, point_d.index,
        PhaseDescend, 0f0)
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
    line_host_id = state.line_host
    line_point_a_id = state.line_point_a
    line_point_b_id = state.line_point_b
    point_a_id = state.point_a
    point_b_id = state.point_b
    point_c_id = state.point_c
    point_d_id = state.point_d

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
            line_joint1_id=line_point_a_id,
            line_joint2_id=line_point_b_id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseMoveToPointA
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, MoveToPointADuration,
            LineEnd, PointOnLineA, 0.25f0, 1, :none)

        timer += dt
        if timer >= MoveToPointADuration
            phase = PhasePutPointA
            timer = 0f0
        end
    elseif phase == PhasePutPointA
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointTrailDuration, PointOnLineA,
            PointMaxBrush, PointOnLineAColor, point_a_id)

        timer += dt
        if timer >= PointTrailDuration
            phase = PhaseMoveToPointB
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, MoveToPointBDuration,
            PointOnLineA, PointOnLineB, 0.25f0, 1, :none)

        timer += dt
        if timer >= MoveToPointBDuration
            phase = PhasePutPointB
            timer = 0f0
        end
    elseif phase == PhasePutPointB
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointTrailDuration, PointOnLineB,
            PointMaxBrush, PointOnLineBColor, point_b_id)

        timer += dt
        if timer >= PointTrailDuration
            phase = PhaseMoveToPointC
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointC
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, MoveToPointCDuration,
            PointOnLineB, PointOffLine, 0.25f0, 1, :none)

        timer += dt
        if timer >= MoveToPointCDuration
            phase = PhasePutPointC
            timer = 0f0
        end
    elseif phase == PhasePutPointC
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointTrailDuration, PointOffLine,
            PointMaxBrush, PointOffLineColor, point_c_id)

        timer += dt
        if timer >= PointTrailDuration
            phase = PhaseMoveToPointD
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointD
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, MoveToPointDDuration,
            PointOffLine, PointSuspended, 0.25f0, 1, :none)

        timer += dt
        if timer >= MoveToPointDDuration
            phase = PhasePutPointD
            timer = 0f0
        end
    elseif phase == PhasePutPointD
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointTrailDuration, PointSuspended,
            PointMaxBrush, PointSuspendedColor, point_d_id)

        timer += dt
        if timer >= PointTrailDuration
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PointSuspended[3], PenTopZ,
            PointSuspended[1], PointSuspended[2])

        timer += dt
        if timer >= EndLiftDuration
            phase = PhaseFinalHold
            timer = 0f0
        end
    elseif phase == PhaseFinalHold
        OdinJuliaBridge.show_pen(state_ptr)
        OdinJuliaBridge.set_pen_active(state_ptr, 0, LineColor)

        timer += dt
        if timer >= FinalHoldDuration
            reset_cycle_state(state_ptr, state)
            return
        end
    end

    OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, phase, timer))
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
    HilbertChapterOneAxiomI7.AnimationId, HilbertChapterOneAxiomI7.animation_entry)

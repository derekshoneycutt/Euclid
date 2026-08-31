module HilbertChapterOneTheorem2

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidGeometry
using ..EuclidLatex

using LinearAlgebra

export get_view_text, initialize, clean, loop

const LineAStart = [0.20f0, 0.64f0, 0f0]
const LineAEnd = [0.84f0, 0.40f0, 0f0]
const PointOffLine = [0.34f0, 0.27f0, 0f0]
const LineBStart = [0.18f0, 0.38f0, 0f0]
const LineBEnd = [0.78f0, 0.76f0, 0f0]
const IntersectionPoint = line_intersection_3d(LineAStart, LineAEnd, LineBStart, LineBEnd)
const PenTopZ = 1.4f0

const SurfaceSweepAStart = [0f0, 0.715f0, 0f0]
const SurfaceSweepAEnd = [1f0, 0.34f0, 0f0]
const SurfaceSweepBStart = [0f0, 0.266f0, 0f0]
const SurfaceSweepBEnd = [1f0, 0.89933336f0, 0f0]
const SurfaceSweepCStart = [0.237f0, 0f0, 0f0]
const SurfaceSweepCEnd = [0.617f0, 1f0, 0f0]

const LineAColor = :steelblue
const PointOffLineColor = :palevioletred1
const LineBColor = :khaki3
const IntersectionColor = :grey60
const SurfaceSweepAColor = :steelblue
const SurfaceSweepBColor = :khaki3
const SurfaceSweepCColor = :palevioletred1
const LineMaxBrush = 5f0
const PointMaxBrush = 5f0

const DescendDuration = 1.8f0
const LineDrawDuration = 4.2f0
const ArcMoveDuration = 2.0f0
const PointTrailDuration = 2.0f0
const SurfaceDragDuration = 3.8f0
const EndLiftDuration = 1.8f0
const FinalHoldDuration = 0.35f0

"""Stable native handles for one line owned by the animation."""
struct LineIds
    host::Int64
    joint1::Int64
    joint2::Int64
end

"""Complete immutable state for one Theorem 2 animation generation."""
struct AnimationState
    line_a::LineIds
    line_b::LineIds
    point_off_line::Int64
    intersection_point::Int64
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhaseDescend = 0f0
const PhaseDrawLineA = 1f0
const PhaseMoveToPointOffLine = 2f0
const PhaseDrawPointOffLine = 3f0
const PhaseMoveToLineBStart = 4f0
const PhaseDrawLineB = 5f0
const PhaseMoveToIntersection = 6f0
const PhaseDrawIntersection = 7f0
const PhaseArcToSurfaceSweepA = 8f0
const PhaseDragSurfaceSweepA = 9f0
const PhaseArcToSurfaceSweepB = 10f0
const PhaseDragSurfaceSweepB = 11f0
const PhaseArcToSurfaceSweepC = 12f0
const PhaseDragSurfaceSweepC = 13f0
const PhaseEndLift = 14f0
const PhaseFinalHold = 15f0

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(
        state.line_a, state.line_b, state.point_off_line,
        state.intersection_point, phase, timer)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - Theorem 2

Through a straight line and a point not lying in it, or through two distinct straight lines having a common point, one and only one plane may be made to pass."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - Theorem 2}

Through a straight line \euclidline[color=steelblue,length=3,thickness=4] and a point \euclidpoint[color=palevioletred1,size=1] not lying in it, or through two distinct straight lines \euclidline[color=steelblue,length=3,thickness=4] \euclidline[color=palevioletred1,length=3,thickness=4] having a common point \euclidpoint[color=grey60,size=1], one and only one plane may be made to pass."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset the animation cycle while preserving its native handles."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    line_a_host_id = state.line_a.host
    line_a_joint1_id = state.line_a.joint1
    line_a_joint2_id = state.line_a.joint2
    line_b_host_id = state.line_b.host
    line_b_joint1_id = state.line_b.joint1
    line_b_joint2_id = state.line_b.joint2
    point_off_line_id = state.point_off_line
    intersection_point_id = state.intersection_point

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [line_a_host_id, line_b_host_id, point_off_line_id, intersection_point_id])

    OdinJuliaBridge.set_point_position(
        state_ptr, line_a_joint1_id, LineAStart[1], LineAStart[2], LineAStart[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, line_a_joint2_id, LineAStart[1], LineAStart[2], LineAStart[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, line_b_joint1_id, LineBStart[1], LineBStart[2], LineBStart[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, line_b_joint2_id, LineBStart[1], LineBStart[2], LineBStart[3])

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, LineAColor)

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhaseDescend, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    line_a = OdinJuliaBridge.create_new_line(
        state_ptr, LineAStart, LineAStart, LineAColor, 0f0)
    point_off_line = OdinJuliaBridge.create_new_point(
        state_ptr, PointOffLine, PointOffLineColor, 0f0)
    line_b = OdinJuliaBridge.create_new_line(
        state_ptr, LineBStart, LineBStart, LineBColor, 0f0)
    intersection_point = OdinJuliaBridge.create_new_point(
        state_ptr, IntersectionPoint, IntersectionColor, 0f0)

    state = AnimationState(
        LineIds(line_a.host_id, line_a.joint1_id, line_a.joint2_id),
        LineIds(line_b.host_id, line_b.joint1_id, line_b.joint2_id),
        point_off_line.index, intersection_point.index, PhaseDescend, 0f0)
    reset_cycle_state(state_ptr, state)
end

"""Clean any extra animation data at the end of performance"""
function clean(state_ptr::Ptr{Cvoid})
end

"""Perform an iteration of the animation loop for this animation"""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    state, status = OdinJuliaBridge.get_animation_value(state_ptr, StateKey)
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return
    line_a_host_id = state.line_a.host
    line_a_joint1_id = state.line_a.joint1
    line_a_joint2_id = state.line_a.joint2
    line_b_host_id = state.line_b.host
    line_b_joint1_id = state.line_b.joint1
    line_b_joint2_id = state.line_b.joint2
    point_off_line_id = state.point_off_line
    intersection_point_id = state.intersection_point

    if line_a_host_id < 0
        return
    end

    phase = state.phase
    timer = state.timer

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, LineAStart[1], LineAStart[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawLineA
            timer = 0f0
        end
    elseif phase == PhaseDrawLineA
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, LineDrawDuration,
            LineAStart, LineAEnd;
            penbrush=LineMaxBrush,
            pencolor=LineAColor,
            line_host_id=line_a_host_id,
            line_joint1_id=line_a_joint1_id,
            line_joint2_id=line_a_joint2_id)

        timer += dt
        if timer >= LineDrawDuration
            phase = PhaseMoveToPointOffLine
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointOffLine
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            LineAEnd, PointOffLine, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawPointOffLine
            timer = 0f0
        end
    elseif phase == PhaseDrawPointOffLine
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointTrailDuration, PointOffLine,
            PointMaxBrush, PointOffLineColor, point_off_line_id)

        timer += dt
        if timer >= PointTrailDuration
            phase = PhaseMoveToLineBStart
            timer = 0f0
        end
    elseif phase == PhaseMoveToLineBStart
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointOffLine, LineBStart, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawLineB
            timer = 0f0
        end
    elseif phase == PhaseDrawLineB
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, LineDrawDuration,
            LineBStart, LineBEnd;
            penbrush=LineMaxBrush,
            pencolor=LineBColor,
            line_host_id=line_b_host_id,
            line_joint1_id=line_b_joint1_id,
            line_joint2_id=line_b_joint2_id)

        timer += dt
        if timer >= LineDrawDuration
            phase = PhaseMoveToIntersection
            timer = 0f0
        end
    elseif phase == PhaseMoveToIntersection
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            LineBEnd, IntersectionPoint, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawIntersection
            timer = 0f0
        end
    elseif phase == PhaseDrawIntersection
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointTrailDuration, IntersectionPoint,
            PointMaxBrush, IntersectionColor, intersection_point_id)

        timer += dt
        if timer >= PointTrailDuration
            phase = PhaseArcToSurfaceSweepA
            timer = 0f0
        end
    elseif phase == PhaseArcToSurfaceSweepA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            IntersectionPoint, SurfaceSweepAStart, 0.28f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragSurfaceSweepA
            timer = 0f0
        end
    elseif phase == PhaseDragSurfaceSweepA
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, SurfaceDragDuration,
            SurfaceSweepAStart, SurfaceSweepAEnd, SurfaceSweepAColor)

        timer += dt
        if timer >= SurfaceDragDuration
            phase = PhaseArcToSurfaceSweepB
            timer = 0f0
        end
    elseif phase == PhaseArcToSurfaceSweepB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            SurfaceSweepAEnd, SurfaceSweepBStart, 0.28f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragSurfaceSweepB
            timer = 0f0
        end
    elseif phase == PhaseDragSurfaceSweepB
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, SurfaceDragDuration,
            SurfaceSweepBStart, SurfaceSweepBEnd, SurfaceSweepBColor)

        timer += dt
        if timer >= SurfaceDragDuration
            phase = PhaseArcToSurfaceSweepC
            timer = 0f0
        end
    elseif phase == PhaseArcToSurfaceSweepC
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            SurfaceSweepBEnd, SurfaceSweepCStart, 0.28f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragSurfaceSweepC
            timer = 0f0
        end
    elseif phase == PhaseDragSurfaceSweepC
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, SurfaceDragDuration,
            SurfaceSweepCStart, SurfaceSweepCEnd, SurfaceSweepCColor)

        timer += dt
        if timer >= SurfaceDragDuration
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ,
            SurfaceSweepCEnd[1], SurfaceSweepCEnd[2])

        timer += dt
        if timer >= EndLiftDuration
            phase = PhaseFinalHold
            timer = 0f0
        end
    elseif phase == PhaseFinalHold
        OdinJuliaBridge.show_pen(state_ptr)
        OdinJuliaBridge.set_pen_active(state_ptr, 0, LineAColor)

        timer += dt
        if timer >= FinalHoldDuration
            reset_cycle_state(state_ptr, state)
            return
        end
    end

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, phase, timer))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return
end

end

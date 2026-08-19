module HilbertChapterOneAxiomI7

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

using LinearAlgebra

export get_view_text, initialize, clean, loop

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

const MetaLineHostId = 1
const MetaLinePointAId = 2
const MetaLinePointBId = 3
const MetaPointAId = 11
const MetaPointBId = 12
const MetaPointCId = 13
const MetaPointDId = 14
const MetaPhase = 101
const MetaTimer = 102

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


function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - Axiom I,7

I, 7. Upon every straight line there exists at least two points, in every plane at least three points not lying in the same straight line, and in space there exist at least four points not lying in a plane."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - Axiom I,7}

\textbf{I, 7.} Upon every straight line \euclidline[color=steelblue,length=3,thickness=4] there exists at least two points \euclidpoint[color=palevioletred1,size=1] \euclidpoint[color=khaki3,size=1], in every plane at least three points \euclidpoint[color=steelblue,size=1] not lying in the same straight line, and in space there exist at least four points \euclidpoint[color=grey60,size=1] not lying in a plane."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    line_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineHostId))
    line_point_a_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLinePointAId))
    line_point_b_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLinePointBId))
    point_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    point_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    point_c_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointCId))
    point_d_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointDId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [line_host_id, point_a_id, point_b_id, point_c_id, point_d_id])

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.set_point_position(
        state_ptr, line_point_a_id, LineStart[1], LineStart[2], LineStart[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, line_point_b_id, LineStart[1], LineStart[2], LineStart[3])

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, LineColor)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

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

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineHostId, line.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLinePointAId, line.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLinePointBId, line.joint2_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointAId, point_a.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointBId, point_b.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointCId, point_c.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointDId, point_d.index)

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    line_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineHostId))
    line_point_a_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLinePointAId))
    line_point_b_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLinePointBId))
    point_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    point_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    point_c_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointCId))
    point_d_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointDId))

    if line_host_id < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, LineStart[1], LineStart[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawLine
            timer = 0f0
        end
    elseif phase == PhaseDrawLine
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, LineStart, LineEnd,
            LineMaxBrush, LineColor, line_host_id, line_point_a_id, line_point_b_id)

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
            reset_cycle_state(state_ptr)
            return
        end
    end

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, phase)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, timer)
end

end
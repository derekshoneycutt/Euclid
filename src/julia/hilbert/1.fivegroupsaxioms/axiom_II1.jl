module HilbertChapterOneAxiomII1

using ..OdinJuliaBridge
using ..EuclidAnimations

export get_view_text, initialize, clean, loop

const LineStart = [0.14f0, 0.56f0, 0f0]
const LineEnd = [0.86f0, 0.56f0, 0f0]
const APoint = [0.28f0, 0.56f0, 0f0]
const BPoint = [0.48f0, 0.56f0, 0f0]
const CPoint = [0.74f0, 0.56f0, 0f0]
const PenTopZ = 1.4f0

const ALabelPoint = APoint + [-0.01f0, 0.04f0, 0f0]
const BLabelPoint = BPoint + [-0.005f0, 0.04f0, 0f0]
const CLabelPoint = CPoint + [-0.005f0, 0.04f0, 0f0]
const LabelColor = :plum1

const LineColor = :grey60
const PointAColor = :palevioletred1
const PointBColor = :steelblue
const PointCColor = :khaki3
const LineMaxBrush = 5f0
const PointMaxBrush = 5f0

const DescendDuration = 1.8f0
const DrawLineDuration = 4.2f0
const MoveToPointADuration = 1.8f0
const MoveToPointBDuration = 1.8f0
const MoveToPointCDuration = 1.8f0
const ReturnToPointADuration = 2f0
const PointTrailDuration = 2f0
const DragSegmentDuration = 2.2f0
const EndLiftDuration = 1.8f0

const MetaLineHostId = 1
const MetaLinePointAId = 2
const MetaLinePointBId = 3
const MetaPointAId = 11
const MetaPointBId = 12
const MetaPointCId = 13
const MetaLabelAId = 21
const MetaLabelBId = 22
const MetaLabelCId = 23
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
const PhaseReturnToPointA = 8f0
const PhaseDragAB = 9f0
const PhaseDragBC = 10f0
const PhaseDragCB = 11f0
const PhaseDragBA = 12f0
const PhaseEndLift = 13f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """David Hilbert - Foundations of Geometry - Axiom II,1

II, 1. If A, B, C are points of a straight line and B lies between A and C, then B lies also between C and A."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    lineHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineHostId))
    linePointAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLinePointAId))
    linePointBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLinePointBId))
    pointAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    pointBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    pointCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointCId))
    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labelCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [lineHostId, pointAId, pointBId, pointCId,
         labelAId, labelBId, labelCId])

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.set_point_position(state_ptr, linePointAId, LineStart)
    OdinJuliaBridge.set_point_position(state_ptr, linePointBId, LineStart)

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, LineColor)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    line = OdinJuliaBridge.create_new_line(
        state_ptr, LineStart, LineStart, LineColor, 0f0)
    pointA = OdinJuliaBridge.create_new_point(
        state_ptr, APoint, PointAColor, 0f0)
    pointB = OdinJuliaBridge.create_new_point(
        state_ptr, BPoint, PointBColor, 0f0)
    pointC = OdinJuliaBridge.create_new_point(
        state_ptr, CPoint, PointCColor, 0f0)
    labelA = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', ALabelPoint, LabelColor, 16f0)
    labelB = OdinJuliaBridge.create_new_label(
        state_ptr, 'B', BLabelPoint, LabelColor, 16f0)
    labelC = OdinJuliaBridge.create_new_label(
        state_ptr, 'C', CLabelPoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineHostId, Float32(line.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLinePointAId, Float32(line.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLinePointBId, Float32(line.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointAId, Float32(pointA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointBId, Float32(pointB.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointCId, Float32(pointC.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAId, Float32(labelA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBId, Float32(labelB.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelCId, Float32(labelC.index))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    lineHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineHostId))
    linePointAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLinePointAId))
    linePointBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLinePointBId))
    pointAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    pointBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    pointCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointCId))
    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labelCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))

    if lineHostId < 0
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
            LineMaxBrush, LineColor, lineHostId, linePointAId, linePointBId)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseMoveToPointA
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, MoveToPointADuration,
            LineEnd, APoint, 0.25f0, 1, :none)

        timer += dt
        if timer >= MoveToPointADuration
            phase = PhasePutPointA
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelAId)
        end
    elseif phase == PhasePutPointA
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointTrailDuration, APoint,
            PointMaxBrush, PointAColor, pointAId)

        timer += dt
        if timer >= PointTrailDuration
            phase = PhaseMoveToPointB
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, MoveToPointBDuration,
            APoint, BPoint, 0.25f0, 1, :none)

        timer += dt
        if timer >= MoveToPointBDuration
            phase = PhasePutPointB
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelBId)
        end
    elseif phase == PhasePutPointB
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointTrailDuration, BPoint,
            PointMaxBrush, PointBColor, pointBId)

        timer += dt
        if timer >= PointTrailDuration
            phase = PhaseMoveToPointC
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointC
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, MoveToPointCDuration,
            BPoint, CPoint, 0.25f0, 1, :none)

        timer += dt
        if timer >= MoveToPointCDuration
            phase = PhasePutPointC
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelCId)
        end
    elseif phase == PhasePutPointC
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointTrailDuration, CPoint,
            PointMaxBrush, PointCColor, pointCId)

        timer += dt
        if timer >= PointTrailDuration
            phase = PhaseReturnToPointA
            timer = 0f0
        end
    elseif phase == PhaseReturnToPointA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ReturnToPointADuration,
            CPoint, APoint, 0.3f0, 1, :none)

        timer += dt
        if timer >= ReturnToPointADuration
            phase = PhaseDragAB
            timer = 0f0
        end
    elseif phase == PhaseDragAB
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragSegmentDuration, APoint, BPoint, PointBColor)

        timer += dt
        if timer >= DragSegmentDuration
            phase = PhaseDragBC
            timer = 0f0
        end
    elseif phase == PhaseDragBC
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragSegmentDuration, BPoint, CPoint, PointBColor)

        timer += dt
        if timer >= DragSegmentDuration
            phase = PhaseDragCB
            timer = 0f0
        end
    elseif phase == PhaseDragCB
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragSegmentDuration, CPoint, BPoint, PointBColor)

        timer += dt
        if timer >= DragSegmentDuration
            phase = PhaseDragBA
            timer = 0f0
        end
    elseif phase == PhaseDragBA
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragSegmentDuration, BPoint, APoint, PointBColor)

        timer += dt
        if timer >= DragSegmentDuration
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ, APoint[1], APoint[2])

        timer += dt
        if timer >= EndLiftDuration
            reset_cycle_state(state_ptr)
            return
        end
    end

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, phase)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, timer)
end

end
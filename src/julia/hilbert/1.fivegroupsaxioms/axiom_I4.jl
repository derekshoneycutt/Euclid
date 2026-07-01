module HilbertChapterOneAxiomI4

using ..OdinJuliaBridge
using ..EuclidAnimations

using LinearAlgebra

export get_view_text, initialize, clean, loop

const APoint = [0.25f0, 0.75f0, 0f0]
const BPoint = [0.75f0, 0.25f0, 0f0]
const CPoint = [0.75f0, 0.75f0, 0f0]
const PenTopZ = 1.4f0

const ALabelPoint = APoint + [-0.03f0, 0.01f0, 0f0]
const BLabelPoint = BPoint + [0.01f0, -0.02f0, 0f0]
const CLabelPoint = CPoint + [0.01f0, -0.02f0, 0f0]
const LabelColor = :plum1

const LineColor = :steelblue
const PointAColor = :palevioletred1
const PointBColor = :khaki3
const PointCColor = :steelblue
const SurfaceLineColorAB = :khaki3
const SurfaceLineColorBC = :palevioletred1
const SurfaceLineColorCA = :steelblue
const LineMaxBrush = 5f0
const PointMaxBrush = 5f0

const DescendDuration = 1.8f0
const DrawLineDuration = 4.2f0
const SurfaceDragDuration = 4.2f0
const SurfaceArcMoveDuration = 2.1f0
const SurfaceArcWaveHeight = 0.35f0
const EndMoveToPointADuration = 2f0
const ExtremityTrailDuration = 2f0
const EndMoveToPointBDuration = 2f0
const EndMoveToPointCDuration = 2f0
const EndLiftDuration = 1.8f0

const SurfaceSweepABStart = [0f0, 1f0, 0f0]
const SurfaceSweepABEnd = [1f0, 0f0, 0f0]
const SurfaceSweepBCStart = [0.75f0, 0f0, 0f0]
const SurfaceSweepBCEnd = [0.75f0, 1f0, 0f0]
const SurfaceSweepCAStart = [0f0, 0.75f0, 0f0]
const SurfaceSweepCAEnd = [1f0, 0.75f0, 0f0]

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
const PhasePutPointA = 1f0
const PhaseMoveToPointB = 2f0
const PhasePutPointB = 3f0
const PhaseMoveToPointC = 4f0
const PhasePutPointC = 5f0
const PhaseMoveToPointA = 6f0
const PhaseDrawLine = 7f0
const PhaseArcToSurfaceAB = 8f0
const PhaseDragSurfaceAB = 9f0
const PhaseArcToSurfaceBC = 10f0
const PhaseDragSurfaceBC = 11f0
const PhaseArcToSurfaceCA = 12f0
const PhaseDragSurfaceCA = 13f0
const PhaseEndLift = 14f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """David Hilbert - Foundations of Geometry - Axiom I,4

I, 4. Any three points A, B, C of a plane α, which do not lie in the same straight line, completely determine that plane."""
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
        [labelAId, labelBId, labelCId,
         lineHostId, pointAId, pointBId, pointCId,
        ])

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.set_point_position(
        state_ptr, linePointAId, APoint[1], APoint[2], APoint[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, linePointBId, APoint[1], APoint[2], APoint[3])

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, LineColor)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    pointA = OdinJuliaBridge.create_new_point(
        state_ptr, APoint, PointAColor, 0f0)
    pointB = OdinJuliaBridge.create_new_point(
        state_ptr, BPoint, PointBColor, 0f0)
    pointC = OdinJuliaBridge.create_new_point(
        state_ptr, CPoint, PointCColor, 0f0)
    line = OdinJuliaBridge.create_new_line(
        state_ptr, APoint, APoint, LineColor, 0f0)
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
            state_ptr, timer, DescendDuration, PenTopZ, APoint[1], APoint[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhasePutPointA
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelAId)
        end
    elseif phase == PhasePutPointA
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, ExtremityTrailDuration, APoint,
            PointMaxBrush, PointAColor, pointAId)

        timer += dt
        if timer >= ExtremityTrailDuration
            phase = PhaseMoveToPointB
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, EndMoveToPointBDuration,
            APoint, BPoint, 0.25f0, 1, :none)

        timer += dt
        if timer >= EndMoveToPointBDuration
            phase = PhasePutPointB
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelBId)
        end
    elseif phase == PhasePutPointB
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, ExtremityTrailDuration, BPoint,
            PointMaxBrush, PointBColor, pointBId)

        timer += dt
        if timer >= ExtremityTrailDuration
            phase = PhaseMoveToPointC
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointC
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, EndMoveToPointCDuration,
            BPoint, CPoint, 0.25f0, 1, :none)

        timer += dt
        if timer >= EndMoveToPointCDuration
            phase = PhasePutPointC
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelCId)
        end
    elseif phase == PhasePutPointC
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, ExtremityTrailDuration, CPoint,
            PointMaxBrush, PointCColor, pointCId)

        timer += dt
        if timer >= ExtremityTrailDuration
            phase = PhaseMoveToPointA
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, EndMoveToPointADuration,
            CPoint, APoint, 0.25f0, 1, :none)

        timer += dt
        if timer >= EndMoveToPointADuration
            phase = PhaseDrawLine
            timer = 0f0
        end
    elseif phase == PhaseDrawLine
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, APoint, BPoint,
            LineMaxBrush, LineColor, lineHostId, linePointAId, linePointBId)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseArcToSurfaceAB
            timer = 0f0
        end
    elseif phase == PhaseArcToSurfaceAB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, SurfaceArcMoveDuration,
            BPoint, SurfaceSweepABStart, SurfaceArcWaveHeight, 1, :none)

        timer += dt
        if timer >= SurfaceArcMoveDuration
            phase = PhaseDragSurfaceAB
            timer = 0f0
        end
    elseif phase == PhaseDragSurfaceAB
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, SurfaceDragDuration,
            SurfaceSweepABStart, SurfaceSweepABEnd, SurfaceLineColorAB)

        timer += dt
        if timer >= SurfaceDragDuration
            phase = PhaseArcToSurfaceBC
            timer = 0f0
        end
    elseif phase == PhaseArcToSurfaceBC
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, SurfaceArcMoveDuration,
            SurfaceSweepABEnd, SurfaceSweepBCStart, SurfaceArcWaveHeight, 1, :none)

        timer += dt
        if timer >= SurfaceArcMoveDuration
            phase = PhaseDragSurfaceBC
            timer = 0f0
        end
    elseif phase == PhaseDragSurfaceBC
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, SurfaceDragDuration,
            SurfaceSweepBCStart, SurfaceSweepBCEnd, SurfaceLineColorBC)

        timer += dt
        if timer >= SurfaceDragDuration
            phase = PhaseArcToSurfaceCA
            timer = 0f0
        end
    elseif phase == PhaseArcToSurfaceCA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, SurfaceArcMoveDuration,
            SurfaceSweepBCEnd, SurfaceSweepCAStart, SurfaceArcWaveHeight, 1, :none)

        timer += dt
        if timer >= SurfaceArcMoveDuration
            phase = PhaseDragSurfaceCA
            timer = 0f0
        end
    elseif phase == PhaseDragSurfaceCA
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, SurfaceDragDuration,
            SurfaceSweepCAStart, SurfaceSweepCAEnd, SurfaceLineColorCA)

        timer += dt
        if timer >= SurfaceDragDuration
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ,
            SurfaceSweepCAEnd[1], SurfaceSweepCAEnd[2])

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

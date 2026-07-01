module HilbertChapterOneAxiomI5

using ..OdinJuliaBridge
using ..EuclidAnimations

using LinearAlgebra

export get_view_text, initialize, clean, loop

const APoint = [0.25f0, 0.75f0, 0f0]
const BPoint = [0.75f0, 0.25f0, 0f0]
const PenTopZ = 1.4f0

const ALabelPoint = APoint + [-0.03f0, 0.01f0, 0f0]
const BLabelPoint = BPoint + [0.01f0, -0.02f0, 0f0]
const lineaLabelPoint = [0.55f0, 0.55f0, 0f0]
const LabelColor = :plum1

const LineColor = :steelblue
const PointAColor = :palevioletred1
const PointBColor = :khaki3
const SurfaceLineColorAB = :steelblue
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

const MetaLineHostId = 1
const MetaLinePointAId = 2
const MetaLinePointBId = 3
const MetaPointAId = 11
const MetaPointBId = 12
const MetaLabelAId = 21
const MetaLabelBId = 22
const MetaLabellineaId = 53
const MetaPhase = 101
const MetaTimer = 102

const PhaseDescend = 0f0
const PhasePutPointA = 1f0
const PhaseMoveToPointB = 2f0
const PhasePutPointB = 3f0
const PhaseMoveToPointA = 6f0
const PhaseDrawLine = 7f0
const PhaseArcToSurfaceAB = 8f0
const PhaseDragSurfaceAB = 9f0
const PhaseEndLift = 14f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """David Hilbert - Foundations of Geometry - Axiom I,5

I, 5. If two points A, B of a straight line a lie in a plane α, then every point of a lies in α.

In this case we say: "The straight line a lies in the plane α," etc."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    lineHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineHostId))
    linePointAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLinePointAId))
    linePointBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLinePointBId))
    pointAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    pointBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))

    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labellineaId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabellineaId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [labelAId, labelBId, labellineaId,
         lineHostId, pointAId, pointBId,
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
    line = OdinJuliaBridge.create_new_line(
        state_ptr, APoint, APoint, LineColor, 0f0)
    labelA = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', ALabelPoint, LabelColor, 16f0)
    labelB = OdinJuliaBridge.create_new_label(
        state_ptr, 'B', BLabelPoint, LabelColor, 16f0)
    labellinea = OdinJuliaBridge.create_new_label(
        state_ptr, 'a', lineaLabelPoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineHostId, Float32(line.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLinePointAId, Float32(line.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLinePointBId, Float32(line.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointAId, Float32(pointA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointBId, Float32(pointB.index))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAId, Float32(labelA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBId, Float32(labelB.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabellineaId, Float32(labellinea.index))

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

    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labellineaId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabellineaId))

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
            phase = PhaseMoveToPointA
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, EndMoveToPointADuration,
            BPoint, APoint, 0.25f0, 1, :none)

        timer += dt
        if timer >= EndMoveToPointADuration
            phase = PhaseDrawLine
            timer = 0f0
        end
    elseif phase == PhaseDrawLine
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, APoint, BPoint,
            LineMaxBrush, LineColor, lineHostId, linePointAId, linePointBId)

        if timer / DrawLineDuration >= 0.5
            OdinJuliaBridge.show_point(state_ptr, labellineaId)
        end

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
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ,
            SurfaceSweepABEnd[1], SurfaceSweepABEnd[2])

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

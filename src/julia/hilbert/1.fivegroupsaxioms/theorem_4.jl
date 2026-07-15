module HilbertChapterOneTheorem4

using ..OdinJuliaBridge
using ..EuclidAnimations

export get_view_text, initialize, clean, loop

const LineStart = [0.14f0, 0.52f0, 0f0]
const LineEnd = [0.86f0, 0.52f0, 0f0]
const PointA = [0.30f0, 0.52f0, 0f0]
const PointB = [0.45f0, 0.52f0, 0f0]
const PointC = [0.50f0, 0.52f0, 0f0]
const PointD = [0.54f0, 0.52f0, 0f0]
const PointE = [0.60f0, 0.52f0, 0f0]
const PointK = [0.79f0, 0.52f0, 0f0]
const PenTopZ = 1.4f0

const ALabelPoint = PointA + [-0.005f0, 0.04f0, 0f0]
const BLabelPoint = PointB + [-0.005f0, 0.04f0, 0f0]
const CLabelPoint = PointC + [-0.005f0, 0.04f0, 0f0]
const DLabelPoint = PointD + [-0.005f0, 0.04f0, 0f0]
const ELabelPoint = PointE + [-0.005f0, 0.04f0, 0f0]
const KLabelPoint = PointK + [-0.005f0, 0.04f0, 0f0]
const LabelColor = :plum1

const LineColor = :grey60
const PointAColor = :steelblue
const PointBColor = :palevioletred1
const PointCColor = :khaki3
const PointDColor = :steelblue
const PointEColor = :khaki3
const PointKColor = :steelblue
const LineMaxBrush = 5f0
const PointMaxBrush = 5f0

const DescendDuration = 1.8f0
const DrawLineDuration = 4.2f0
const ArcMoveDuration = 1.8f0
const PointTrailDuration = 2f0
const DragSegmentDuration = 2.1f0
const EndLiftDuration = 1.8f0

const MetaLineHostId = 1
const MetaLineJoint1Id = 2
const MetaLineJoint2Id = 3
const MetaPointAId = 11
const MetaPointBId = 12
const MetaPointCId = 13
const MetaPointDId = 14
const MetaPointEId = 15
const MetaPointKId = 16
const MetaLabelAId = 31
const MetaLabelBId = 32
const MetaLabelCId = 33
const MetaLabelDId = 34
const MetaLabelEId = 35
const MetaLabelKId = 36
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
const PhaseMoveToPointE = 10f0
const PhasePutPointE = 11f0
const PhaseMoveToPointK = 12f0
const PhasePutPointK = 13f0
const PhaseMoveToPointAForDrag = 14f0
const PhaseDragAB = 15f0
const PhaseDragBK = 16f0
const PhaseMoveToPointCForDrag = 17f0
const PhaseDragCD = 18f0
const PhaseDragDE = 19f0
const PhaseMoveToPointBForDrag = 20f0
const PhaseDragBC = 21f0
const PhaseDragCK = 22f0
const PhaseMoveToPointDForDrag = 23f0
const PhaseDragDESecond = 24f0
const PhaseDragEK = 25f0
const PhaseEndLift = 26f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """David Hilbert - Foundations of Geometry - Theorem 4

If we have given any finite number of points situated upon a straight line, we can always arrange them in a sequence A, B, C, D, E, . . . , K so that B shall lie between A and C, D, E, . . . , K; C between A, B and D, E, . . . , K; D between A, B, C and E, . . . , K, etc. Aside from this order of sequence, there exists but one other possessing this property, namely, the reverse order K, . . . , E, D, C, B, A."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    lineHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineHostId))
    lineJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineJoint1Id))
    lineJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineJoint2Id))
    pointAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    pointBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    pointCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointCId))
    pointDId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointDId))
    pointEId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointEId))
    pointKId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointKId))
    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labelCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    labelDId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDId))
    labelEId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelEId))
    labelKId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelKId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [lineHostId,
         pointAId, pointBId, pointCId, pointDId, pointEId, pointKId,
         labelAId, labelBId, labelCId, labelDId, labelEId, labelKId])

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.set_point_position(state_ptr, lineJoint1Id, LineStart)
    OdinJuliaBridge.set_point_position(state_ptr, lineJoint2Id, LineStart)

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, LineColor)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    line = OdinJuliaBridge.create_new_line(
        state_ptr, LineStart, LineStart, LineColor, 0f0)
    pointA = OdinJuliaBridge.create_new_point(
        state_ptr, PointA, PointAColor, 0f0)
    pointB = OdinJuliaBridge.create_new_point(
        state_ptr, PointB, PointBColor, 0f0)
    pointC = OdinJuliaBridge.create_new_point(
        state_ptr, PointC, PointCColor, 0f0)
    pointD = OdinJuliaBridge.create_new_point(
        state_ptr, PointD, PointDColor, 0f0)
    pointE = OdinJuliaBridge.create_new_point(
        state_ptr, PointE, PointEColor, 0f0)
    pointK = OdinJuliaBridge.create_new_point(
        state_ptr, PointK, PointKColor, 0f0)
    labelA = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', ALabelPoint, LabelColor, 16f0)
    labelB = OdinJuliaBridge.create_new_label(
        state_ptr, 'B', BLabelPoint, LabelColor, 16f0)
    labelC = OdinJuliaBridge.create_new_label(
        state_ptr, 'C', CLabelPoint, LabelColor, 16f0)
    labelD = OdinJuliaBridge.create_new_label(
        state_ptr, 'D', DLabelPoint, LabelColor, 16f0)
    labelE = OdinJuliaBridge.create_new_label(
        state_ptr, 'E', ELabelPoint, LabelColor, 16f0)
    labelK = OdinJuliaBridge.create_new_label(
        state_ptr, 'K', KLabelPoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineHostId, Float32(line.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineJoint1Id, Float32(line.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineJoint2Id, Float32(line.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointAId, Float32(pointA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointBId, Float32(pointB.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointCId, Float32(pointC.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointDId, Float32(pointD.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointEId, Float32(pointE.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointKId, Float32(pointK.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAId, Float32(labelA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBId, Float32(labelB.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelCId, Float32(labelC.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelDId, Float32(labelD.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelEId, Float32(labelE.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelKId, Float32(labelK.index))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    lineHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineHostId))
    lineJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineJoint1Id))
    lineJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineJoint2Id))
    pointAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    pointBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    pointCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointCId))
    pointDId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointDId))
    pointEId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointEId))
    pointKId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointKId))
    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labelCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    labelDId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDId))
    labelEId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelEId))
    labelKId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelKId))

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
            LineMaxBrush, LineColor, lineHostId, lineJoint1Id, lineJoint2Id)

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
            OdinJuliaBridge.show_point(state_ptr, labelAId)
        end
    elseif phase == PhasePutPointA
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointTrailDuration, PointA,
            PointMaxBrush, PointAColor, pointAId)

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
            OdinJuliaBridge.show_point(state_ptr, labelBId)
        end
    elseif phase == PhasePutPointB
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointTrailDuration, PointB,
            PointMaxBrush, PointBColor, pointBId)

        timer += dt
        if timer >= PointTrailDuration
            phase = PhaseMoveToPointC
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointC
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointB, PointC, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePutPointC
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelCId)
        end
    elseif phase == PhasePutPointC
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointTrailDuration, PointC,
            PointMaxBrush, PointCColor, pointCId)

        timer += dt
        if timer >= PointTrailDuration
            phase = PhaseMoveToPointD
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointD
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointC, PointD, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePutPointD
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelDId)
        end
    elseif phase == PhasePutPointD
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointTrailDuration, PointD,
            PointMaxBrush, PointDColor, pointDId)

        timer += dt
        if timer >= PointTrailDuration
            phase = PhaseMoveToPointE
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointE
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointD, PointE, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePutPointE
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelEId)
        end
    elseif phase == PhasePutPointE
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointTrailDuration, PointE,
            PointMaxBrush, PointEColor, pointEId)

        timer += dt
        if timer >= PointTrailDuration
            phase = PhaseMoveToPointK
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointK
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointE, PointK, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePutPointK
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelKId)
        end
    elseif phase == PhasePutPointK
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointTrailDuration, PointK,
            PointMaxBrush, PointKColor, pointKId)

        timer += dt
        if timer >= PointTrailDuration
            phase = PhaseMoveToPointAForDrag
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointAForDrag
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointK, PointA, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragAB
            timer = 0f0
        end
    elseif phase == PhaseDragAB
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragSegmentDuration,
            PointA, PointB, PointBColor)

        timer += dt
        if timer >= DragSegmentDuration
            phase = PhaseDragBK
            timer = 0f0
        end
    elseif phase == PhaseDragBK
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragSegmentDuration,
            PointB, PointK, PointBColor)

        timer += dt
        if timer >= DragSegmentDuration
            phase = PhaseMoveToPointCForDrag
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointCForDrag
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointK, PointC, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragCD
            timer = 0f0
        end
    elseif phase == PhaseDragCD
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragSegmentDuration,
            PointC, PointD, PointDColor)

        timer += dt
        if timer >= DragSegmentDuration
            phase = PhaseDragDE
            timer = 0f0
        end
    elseif phase == PhaseDragDE
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragSegmentDuration,
            PointD, PointE, PointDColor)

        timer += dt
        if timer >= DragSegmentDuration
            phase = PhaseMoveToPointBForDrag
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointBForDrag
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointE, PointB, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragBC
            timer = 0f0
        end
    elseif phase == PhaseDragBC
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragSegmentDuration,
            PointB, PointC, PointCColor)

        timer += dt
        if timer >= DragSegmentDuration
            phase = PhaseDragCK
            timer = 0f0
        end
    elseif phase == PhaseDragCK
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragSegmentDuration,
            PointC, PointK, PointCColor)

        timer += dt
        if timer >= DragSegmentDuration
            phase = PhaseMoveToPointDForDrag
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointDForDrag
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointK, PointD, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragDESecond
            timer = 0f0
        end
    elseif phase == PhaseDragDESecond
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragSegmentDuration,
            PointD, PointE, PointEColor)

        timer += dt
        if timer >= DragSegmentDuration
            phase = PhaseDragEK
            timer = 0f0
        end
    elseif phase == PhaseDragEK
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragSegmentDuration,
            PointE, PointK, PointEColor)

        timer += dt
        if timer >= DragSegmentDuration
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ, PointK[1], PointK[2])

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
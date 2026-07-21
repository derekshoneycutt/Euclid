module HilbertChapterOneAxiomIV3

using ..OdinJuliaBridge
using ..EuclidAnimations

export get_view_text, initialize, clean, loop

const LineAStart = [0.14f0, 0.66f0, 0f0]
const LineAEnd = [0.86f0, 0.66f0, 0f0]
const LineAPrimeStart = [0.14f0, 0.34f0, 0f0]
const LineAPrimeEnd = [0.86f0, 0.34f0, 0f0]

const PointA = [0.30f0, 0.66f0, 0f0]
const PointB = [0.46f0, 0.66f0, 0f0]
const PointC = [0.62f0, 0.66f0, 0f0]
const PointAPrime = [0.30f0, 0.34f0, 0f0]
const PointBPrime = [0.46f0, 0.34f0, 0f0]
const PointCPrime = [0.62f0, 0.34f0, 0f0]

const PenTopZ = 1.4f0

const LabelColor = :plum1
const DragColor = :lightgreen
const LineAColor = :steelblue
const LineAPrimeColor = :khaki3
const PointAColor = :palevioletred1
const PointBColor = :khaki3
const PointCColor = :grey60
const PointAPrimeColor = :palevioletred1
const PointBPrimeColor = :steelblue
const PointCPrimeColor = :grey60
const LineMaxBrush = 5f0
const PointMaxBrush = 5f0

const LabelAPoint = PointA + [0f0, 0.07f0, 0f0]
const LabelBPoint = PointB + [0f0, 0.07f0, 0f0]
const LabelCPoint = PointC + [0f0, 0.07f0, 0f0]
const LabelaPoint = LineAStart + [0.03f0, 0.06f0, 0f0]
const LabelAPrimePoint = PointAPrime + [0f0, 0.07f0, 0f0]
const LabelBPrimePoint = PointBPrime + [0f0, 0.07f0, 0f0]
const LabelCPrimePoint = PointCPrime + [0f0, 0.07f0, 0f0]
const LabelAPrimeLinePoint = LineAPrimeStart + [0.03f0, 0.06f0, 0f0]

const DescendDuration = 1.8f0
const DrawLineDuration = 2.6f0
const ArcMoveDuration = 1.4f0
const PointDrawDuration = 1.6f0
const DragDuration = 1.5f0
const EndLiftDuration = 1.8f0
const FinalHoldDuration = 0.9f0

const MetaLineAHostId = 1
const MetaLineAJoint1Id = 2
const MetaLineAJoint2Id = 3
const MetaLineAPrimeHostId = 11
const MetaLineAPrimeJoint1Id = 12
const MetaLineAPrimeJoint2Id = 13

const MetaPointAId = 21
const MetaPointBId = 22
const MetaPointCId = 23
const MetaPointAPrimeId = 24
const MetaPointBPrimeId = 25
const MetaPointCPrimeId = 26

const MetaLabelAId = 31
const MetaLabelBId = 32
const MetaLabelCId = 33
const MetaLabelAPrimeId = 34
const MetaLabelBPrimeId = 35
const MetaLabelCPrimeId = 36
const MetaLabelaId = 37
const MetaLabelAPrimeLineId = 38

const MetaPhase = 101
const MetaTimer = 102

const PhaseDescend = 0f0
const PhaseDrawLineA = 1f0
const PhaseMoveToA = 2f0
const PhaseDrawA = 3f0
const PhaseMoveToB = 4f0
const PhaseDrawB = 5f0
const PhaseMoveToC = 6f0
const PhaseDrawC = 7f0
const PhaseMoveToLineAPrimeStart = 8f0
const PhaseDrawLineAPrime = 9f0
const PhaseMoveToAPrime = 10f0
const PhaseDrawAPrime = 11f0
const PhaseMoveToBPrime = 12f0
const PhaseDrawBPrime = 13f0
const PhaseMoveToCPrime = 14f0
const PhaseDrawCPrime = 15f0
const PhaseArcToA = 16f0
const PhaseDragAToB = 17f0
const PhaseDragBToA = 18f0
const PhaseArcToAPrime = 19f0
const PhaseDragAPrimeToBPrime = 20f0
const PhaseDragBPrimeToAPrime = 21f0
const PhaseArcToB = 22f0
const PhaseDragBToC = 23f0
const PhaseDragCToB = 24f0
const PhaseArcToBPrime = 25f0
const PhaseDragBPrimeToCPrime = 26f0
const PhaseDragCPrimeToBPrime = 27f0
const PhaseArcToASecond = 28f0
const PhaseDragAToC = 29f0
const PhaseDragCToA = 30f0
const PhaseArcToAPrimeSecond = 31f0
const PhaseDragAPrimeToCPrime = 32f0
const PhaseDragCPrimeToAPrime = 33f0
const PhaseEndLift = 34f0
const PhaseFinalHold = 35f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """David Hilbert - Foundations of Geometry - Axiom IV,3

IV, 3. Let AB and BC be two segments of a straight line a which have no points in common aside from the point B, and, furthermore, let A'B' and B'C' be two segments of the same or of another straight line a' having, likewise, no point other than B' in common. Then, if AB ≡ A'B' and BC ≡ B'C', we have AC ≡ A'C'."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    lineAHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAHostId))
    lineAJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAJoint1Id))
    lineAJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAJoint2Id))
    lineAPrimeHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAPrimeHostId))
    lineAPrimeJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAPrimeJoint1Id))
    lineAPrimeJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAPrimeJoint2Id))

    pointAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    pointBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    pointCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointCId))
    pointAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAPrimeId))
    pointBPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBPrimeId))
    pointCPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointCPrimeId))

    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labelCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    labelAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAPrimeId))
    labelBPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBPrimeId))
    labelCPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCPrimeId))
    labelaId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelaId))
    labelAPrimeLineId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAPrimeLineId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [lineAHostId, lineAPrimeHostId,
         pointAId, pointBId, pointCId,
         pointAPrimeId, pointBPrimeId, pointCPrimeId,
         labelAId, labelBId, labelCId,
         labelAPrimeId, labelBPrimeId, labelCPrimeId,
         labelaId, labelAPrimeLineId])

    OdinJuliaBridge.set_point_position(state_ptr, lineAJoint1Id, LineAStart)
    OdinJuliaBridge.set_point_position(state_ptr, lineAJoint2Id, LineAStart)
    OdinJuliaBridge.set_point_position(state_ptr, lineAPrimeJoint1Id, LineAPrimeStart)
    OdinJuliaBridge.set_point_position(state_ptr, lineAPrimeJoint2Id, LineAPrimeStart)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, LineAColor)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    lineA = OdinJuliaBridge.create_new_line(state_ptr, LineAStart, LineAStart, LineAColor, 0f0)
    lineAPrime = OdinJuliaBridge.create_new_line(
        state_ptr, LineAPrimeStart, LineAPrimeStart, LineAPrimeColor, 0f0)

    pointA = OdinJuliaBridge.create_new_point(state_ptr, PointA, PointAColor, 0f0)
    pointB = OdinJuliaBridge.create_new_point(state_ptr, PointB, PointBColor, 0f0)
    pointC = OdinJuliaBridge.create_new_point(state_ptr, PointC, PointCColor, 0f0)
    pointAPrime = OdinJuliaBridge.create_new_point(state_ptr, PointAPrime, PointAPrimeColor, 0f0)
    pointBPrime = OdinJuliaBridge.create_new_point(state_ptr, PointBPrime, PointBPrimeColor, 0f0)
    pointCPrime = OdinJuliaBridge.create_new_point(state_ptr, PointCPrime, PointCPrimeColor, 0f0)

    labelA = OdinJuliaBridge.create_new_label(state_ptr, 'A', LabelAPoint, LabelColor, 16f0)
    labelB = OdinJuliaBridge.create_new_label(state_ptr, 'B', LabelBPoint, LabelColor, 16f0)
    labelC = OdinJuliaBridge.create_new_label(state_ptr, 'C', LabelCPoint, LabelColor, 16f0)
    labela = OdinJuliaBridge.create_new_label(state_ptr, 'a', LabelaPoint, LabelColor, 16f0)
    labelAPrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'A', OdinJuliaBridge.LABEL_DECORATION_PRIME, LabelAPrimePoint, LabelColor, 16f0)
    labelBPrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'B', OdinJuliaBridge.LABEL_DECORATION_PRIME, LabelBPrimePoint, LabelColor, 16f0)
    labelCPrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'C', OdinJuliaBridge.LABEL_DECORATION_PRIME, LabelCPrimePoint, LabelColor, 16f0)
    labelAPrimeLine = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'a', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelAPrimeLinePoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineAHostId, Float32(lineA.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineAJoint1Id, Float32(lineA.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineAJoint2Id, Float32(lineA.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineAPrimeHostId, Float32(lineAPrime.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineAPrimeJoint1Id, Float32(lineAPrime.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineAPrimeJoint2Id, Float32(lineAPrime.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointAId, Float32(pointA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointBId, Float32(pointB.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointCId, Float32(pointC.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointAPrimeId, Float32(pointAPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointBPrimeId, Float32(pointBPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointCPrimeId, Float32(pointCPrime.index))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAId, Float32(labelA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBId, Float32(labelB.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelCId, Float32(labelC.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAPrimeId, Float32(labelAPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBPrimeId, Float32(labelBPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelCPrimeId, Float32(labelCPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelaId, Float32(labela.index))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaLabelAPrimeLineId, Float32(labelAPrimeLine.index))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    lineAHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAHostId))
    lineAJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAJoint1Id))
    lineAJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAJoint2Id))
    lineAPrimeHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAPrimeHostId))
    lineAPrimeJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAPrimeJoint1Id))
    lineAPrimeJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAPrimeJoint2Id))

    pointAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    pointBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    pointCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointCId))
    pointAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAPrimeId))
    pointBPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBPrimeId))
    pointCPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointCPrimeId))

    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labelCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    labelAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAPrimeId))
    labelBPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBPrimeId))
    labelCPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCPrimeId))
    labelaId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelaId))
    labelAPrimeLineId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAPrimeLineId))

    if lineAHostId < 0 || lineAPrimeHostId < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, LineAStart[1], LineAStart[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawLineA
            timer = 0f0
        end
    elseif phase == PhaseDrawLineA
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, LineAStart, LineAEnd,
            LineMaxBrush, LineAColor, lineAHostId, lineAJoint1Id, lineAJoint2Id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseMoveToA
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelaId)
        end
    elseif phase == PhaseMoveToA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, LineAEnd, PointA, 0.24f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawA
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelAId)
        end
    elseif phase == PhaseDrawA
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, PointA,
            PointMaxBrush, PointAColor, pointAId)

        timer += dt
        if timer >= PointDrawDuration
            phase = PhaseMoveToB
            timer = 0f0
        end
    elseif phase == PhaseMoveToB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointA, PointB, 0.18f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawB
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelBId)
        end
    elseif phase == PhaseDrawB
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, PointB,
            PointMaxBrush, PointBColor, pointBId)

        timer += dt
        if timer >= PointDrawDuration
            phase = PhaseMoveToC
            timer = 0f0
        end
    elseif phase == PhaseMoveToC
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointB, PointC, 0.18f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawC
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelCId)
        end
    elseif phase == PhaseDrawC
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, PointC,
            PointMaxBrush, PointCColor, pointCId)

        timer += dt
        if timer >= PointDrawDuration
            phase = PhaseMoveToLineAPrimeStart
            timer = 0f0
        end
    elseif phase == PhaseMoveToLineAPrimeStart
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointC, LineAPrimeStart, 0.26f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawLineAPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawLineAPrime
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, LineAPrimeStart, LineAPrimeEnd,
            LineMaxBrush, LineAPrimeColor,
            lineAPrimeHostId, lineAPrimeJoint1Id, lineAPrimeJoint2Id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseMoveToAPrime
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelAPrimeLineId)
        end
    elseif phase == PhaseMoveToAPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, LineAPrimeEnd, PointAPrime, 0.24f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawAPrime
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelAPrimeId)
        end
    elseif phase == PhaseDrawAPrime
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, PointAPrime,
            PointMaxBrush, PointAPrimeColor, pointAPrimeId)

        timer += dt
        if timer >= PointDrawDuration
            phase = PhaseMoveToBPrime
            timer = 0f0
        end
    elseif phase == PhaseMoveToBPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointAPrime, PointBPrime, 0.18f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawBPrime
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelBPrimeId)
        end
    elseif phase == PhaseDrawBPrime
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, PointBPrime,
            PointMaxBrush, PointBPrimeColor, pointBPrimeId)

        timer += dt
        if timer >= PointDrawDuration
            phase = PhaseMoveToCPrime
            timer = 0f0
        end
    elseif phase == PhaseMoveToCPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointBPrime, PointCPrime, 0.18f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawCPrime
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelCPrimeId)
        end
    elseif phase == PhaseDrawCPrime
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, PointCPrime,
            PointMaxBrush, PointCPrimeColor, pointCPrimeId)

        timer += dt
        if timer >= PointDrawDuration
            phase = PhaseArcToA
            timer = 0f0
        end
    elseif phase == PhaseArcToA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointCPrime, PointA, 0.24f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragAToB
            timer = 0f0
        end
    elseif phase == PhaseDragAToB
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointA, PointB, DragColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseDragBToA
            timer = 0f0
        end
    elseif phase == PhaseDragBToA
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointB, PointA, DragColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseArcToAPrime
            timer = 0f0
        end
    elseif phase == PhaseArcToAPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointA, PointAPrime, 0.24f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragAPrimeToBPrime
            timer = 0f0
        end
    elseif phase == PhaseDragAPrimeToBPrime
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointAPrime, PointBPrime, DragColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseDragBPrimeToAPrime
            timer = 0f0
        end
    elseif phase == PhaseDragBPrimeToAPrime
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointBPrime, PointAPrime, DragColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseArcToB
            timer = 0f0
        end
    elseif phase == PhaseArcToB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointAPrime, PointB, 0.24f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragBToC
            timer = 0f0
        end
    elseif phase == PhaseDragBToC
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointB, PointC, DragColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseDragCToB
            timer = 0f0
        end
    elseif phase == PhaseDragCToB
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointC, PointB, DragColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseArcToBPrime
            timer = 0f0
        end
    elseif phase == PhaseArcToBPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointB, PointBPrime, 0.24f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragBPrimeToCPrime
            timer = 0f0
        end
    elseif phase == PhaseDragBPrimeToCPrime
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointBPrime, PointCPrime, DragColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseDragCPrimeToBPrime
            timer = 0f0
        end
    elseif phase == PhaseDragCPrimeToBPrime
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointCPrime, PointBPrime, DragColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseArcToASecond
            timer = 0f0
        end
    elseif phase == PhaseArcToASecond
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointBPrime, PointA, 0.24f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragAToC
            timer = 0f0
        end
    elseif phase == PhaseDragAToC
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointA, PointC, DragColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseDragCToA
            timer = 0f0
        end
    elseif phase == PhaseDragCToA
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointC, PointA, DragColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseArcToAPrimeSecond
            timer = 0f0
        end
    elseif phase == PhaseArcToAPrimeSecond
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointA, PointAPrime, 0.24f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragAPrimeToCPrime
            timer = 0f0
        end
    elseif phase == PhaseDragAPrimeToCPrime
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointAPrime, PointCPrime, DragColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseDragCPrimeToAPrime
            timer = 0f0
        end
    elseif phase == PhaseDragCPrimeToAPrime
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointCPrime, PointAPrime, DragColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ, PointAPrime[1], PointAPrime[2])

        timer += dt
        if timer >= EndLiftDuration
            phase = PhaseFinalHold
            timer = 0f0
        end
    elseif phase == PhaseFinalHold
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

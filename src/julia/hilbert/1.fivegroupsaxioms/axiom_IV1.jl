module HilbertChapterOneAxiomIV1

using ..OdinJuliaBridge
using ..EuclidAnimations

export get_view_text, initialize, clean, loop

const LineAStart = [0.14f0, 0.62f0, 0f0]
const LineAEnd = [0.86f0, 0.62f0, 0f0]
const LineAPrimeStart = [0.16f0, 0.36f0, 0f0]
const LineAPrimeEnd = [0.88f0, 0.36f0, 0f0]

const PointA = [0.30f0, 0.62f0, 0f0]
const PointB = [0.54f0, 0.62f0, 0f0]
const PointAPrime = [0.32f0, 0.36f0, 0f0]
const PointBPrime = [0.56f0, 0.36f0, 0f0]

const PenTopZ = 1.4f0

const LabelColor = :plum1
const LineAColor = :steelblue
const LineAPrimeColor = :khaki3
const PointAColor = :palevioletred1
const PointBColor = :khaki3
const PointAPrimeColor = :palevioletred1
const PointBPrimeColor = :steelblue
const DragColor = :lightgreen
const LineMaxBrush = 5f0
const PointMaxBrush = 5f0

const LabelaPoint = LineAStart + [0.03f0, 0.06f0, 0f0]
const LabelAPrimeLinePoint = LineAPrimeStart + [0.03f0, 0.06f0, 0f0]
const LabelAPoint = PointA + [0.00f0, 0.07f0, 0f0]
const LabelBPoint = PointB + [0.00f0, 0.07f0, 0f0]
const LabelAPrimePoint = PointAPrime + [0.00f0, 0.07f0, 0f0]
const LabelBPrimePoint = PointBPrime + [0.00f0, 0.07f0, 0f0]

const DescendDuration = 1.8f0
const DrawLineDuration = 3.2f0
const ArcMoveDuration = 1.6f0
const PointDrawDuration = 1.8f0
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
const MetaPointAPrimeId = 23
const MetaPointBPrimeId = 24

const MetaLabelaId = 31
const MetaLabelAPrimeLineId = 32
const MetaLabelAId = 33
const MetaLabelBId = 34
const MetaLabelAPrimeId = 35
const MetaLabelBPrimeId = 36

const MetaPhase = 101
const MetaTimer = 102

const PhaseDescend = 0f0
const PhaseDrawLineA = 1f0
const PhaseMoveToA = 2f0
const PhaseDrawA = 3f0
const PhaseMoveToB = 4f0
const PhaseDrawB = 5f0
const PhaseMoveToAPrimeLineStart = 6f0
const PhaseDrawAPrimeLine = 7f0
const PhaseMoveToAPrime = 8f0
const PhaseDrawAPrime = 9f0
const PhaseMoveToBPrime = 10f0
const PhaseDrawBPrime = 11f0
const PhaseDragBPrimeToAPrime = 12f0
const PhaseDragAPrimeToBPrime = 13f0
const PhaseArcToA = 14f0
const PhaseDragAToB = 15f0
const PhaseDragBToA = 16f0
const PhaseEndLift = 17f0
const PhaseFinalHold = 18f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """David Hilbert - Foundations of Geometry - Axiom IV,1

IV, I. If A, B are two points on a straight line a, and if A' is a point upon the same or another straight line a', then, upon a given side of A' on the straight line a', we can always find one and only one point B' so that the segment AB (or BA) is congruent to the segment A'B'. We indicate this relation by writing

    AB ≡ A'B'.

Every segment is congruent to itself; that is, we always have

    AB ≡ AB.

We can state the above axiom briefly by saying that every segment can be laid off upon a given side of a given point of a given straight line in one and only one way."""
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
    pointAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAPrimeId))
    pointBPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBPrimeId))

    labelaId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelaId))
    labelAPrimeLineId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAPrimeLineId))
    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labelAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAPrimeId))
    labelBPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBPrimeId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [lineAHostId, lineAPrimeHostId,
         pointAId, pointBId, pointAPrimeId, pointBPrimeId,
         labelaId, labelAPrimeLineId, labelAId, labelBId, labelAPrimeId, labelBPrimeId])

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
    pointAPrime = OdinJuliaBridge.create_new_point(state_ptr, PointAPrime, PointAPrimeColor, 0f0)
    pointBPrime = OdinJuliaBridge.create_new_point(state_ptr, PointBPrime, PointBPrimeColor, 0f0)

    labela = OdinJuliaBridge.create_new_label(state_ptr, 'a', LabelaPoint, LabelColor, 16f0)
    labelAPrimeLine = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'a', OdinJuliaBridge.LABEL_DECORATION_PRIME, LabelAPrimeLinePoint, LabelColor,
        16f0)
    labelA = OdinJuliaBridge.create_new_label(state_ptr, 'A', LabelAPoint, LabelColor, 16f0)
    labelB = OdinJuliaBridge.create_new_label(state_ptr, 'B', LabelBPoint, LabelColor, 16f0)
    labelAPrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'A', OdinJuliaBridge.LABEL_DECORATION_PRIME, LabelAPrimePoint, LabelColor, 16f0)
    labelBPrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'B', OdinJuliaBridge.LABEL_DECORATION_PRIME, LabelBPrimePoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineAHostId, Float32(lineA.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineAJoint1Id, Float32(lineA.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineAJoint2Id, Float32(lineA.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineAPrimeHostId, Float32(lineAPrime.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineAPrimeJoint1Id, Float32(lineAPrime.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineAPrimeJoint2Id, Float32(lineAPrime.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointAId, Float32(pointA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointBId, Float32(pointB.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointAPrimeId, Float32(pointAPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointBPrimeId, Float32(pointBPrime.index))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelaId, Float32(labela.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAPrimeLineId, Float32(labelAPrimeLine.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAId, Float32(labelA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBId, Float32(labelB.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAPrimeId, Float32(labelAPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBPrimeId, Float32(labelBPrime.index))

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
    pointAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAPrimeId))
    pointBPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBPrimeId))

    labelaId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelaId))
    labelAPrimeLineId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAPrimeLineId))
    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labelAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAPrimeId))
    labelBPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBPrimeId))

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
            OdinJuliaBridge.show_point(state_ptr, labelaId)
        end
    elseif phase == PhaseDrawLineA
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, LineAStart, LineAEnd,
            LineMaxBrush, LineAColor, lineAHostId, lineAJoint1Id, lineAJoint2Id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseMoveToA
            timer = 0f0
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
            phase = PhaseMoveToAPrimeLineStart
            timer = 0f0
        end
    elseif phase == PhaseMoveToAPrimeLineStart
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointB, LineAPrimeStart, 0.26f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawAPrimeLine
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelAPrimeLineId)
        end
    elseif phase == PhaseDrawAPrimeLine
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, LineAPrimeStart, LineAPrimeEnd,
            LineMaxBrush, LineAPrimeColor, lineAPrimeHostId, lineAPrimeJoint1Id, lineAPrimeJoint2Id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseMoveToAPrime
            timer = 0f0
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
            phase = PhaseDragBPrimeToAPrime
            timer = 0f0
        end
    elseif phase == PhaseDragBPrimeToAPrime
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointBPrime, PointAPrime, DragColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseDragAPrimeToBPrime
            timer = 0f0
        end
    elseif phase == PhaseDragAPrimeToBPrime
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointAPrime, PointBPrime, DragColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseArcToA
            timer = 0f0
        end
    elseif phase == PhaseArcToA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointBPrime, PointA, 0.28f0, 1, :none)

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
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ, PointA[1], PointA[2])

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

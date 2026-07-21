module HilbertChapterOneAxiomIV2

using ..OdinJuliaBridge
using ..EuclidAnimations

export get_view_text, initialize, clean, loop

const LineABStart = [0.14f0, 0.72f0, 0f0]
const LineABEnd = [0.86f0, 0.72f0, 0f0]
const LineAPrimeStart = [0.14f0, 0.50f0, 0f0]
const LineAPrimeEnd = [0.86f0, 0.50f0, 0f0]
const LineADoublePrimeStart = [0.14f0, 0.28f0, 0f0]
const LineADoublePrimeEnd = [0.86f0, 0.28f0, 0f0]

const PointA = [0.30f0, 0.72f0, 0f0]
const PointB = [0.54f0, 0.72f0, 0f0]
const PointAPrime = [0.30f0, 0.50f0, 0f0]
const PointBPrime = [0.54f0, 0.50f0, 0f0]
const PointADoublePrime = [0.30f0, 0.28f0, 0f0]
const PointBDoublePrime = [0.54f0, 0.28f0, 0f0]

const PenTopZ = 1.4f0

const LabelColor = :plum1
const DragColor = :lightgreen
const LineABColor = :steelblue
const LineAPrimeColor = :palevioletred1
const LineADoublePrimeColor = :khaki3

const PointAColor = :palevioletred1
const PointBColor = :khaki3
const PointAPrimeColor = :khaki3
const PointBPrimeColor = :steelblue
const PointADoublePrimeColor = :steelblue
const PointBDoublePrimeColor = :palevioletred1

const LineMaxBrush = 5f0
const PointMaxBrush = 5f0

const LabelAPoint = PointA + [0f0, 0.07f0, 0f0]
const LabelBPoint = PointB + [0f0, 0.07f0, 0f0]
const LabelAPrimePoint = PointAPrime + [0f0, 0.07f0, 0f0]
const LabelBPrimePoint = PointBPrime + [0f0, 0.07f0, 0f0]
const LabelADoublePrimePoint = PointADoublePrime + [0f0, 0.07f0, 0f0]
const LabelBDoublePrimePoint = PointBDoublePrime + [0f0, 0.07f0, 0f0]

const DescendDuration = 1.8f0
const DrawLineDuration = 2.5f0
const ArcMoveDuration = 1.4f0
const PointDrawDuration = 1.6f0
const DragDuration = 1.5f0
const EndLiftDuration = 1.8f0
const FinalHoldDuration = 0.9f0

const MetaLineABHostId = 1
const MetaLineABJoint1Id = 2
const MetaLineABJoint2Id = 3
const MetaLineAPrimeHostId = 11
const MetaLineAPrimeJoint1Id = 12
const MetaLineAPrimeJoint2Id = 13
const MetaLineADoublePrimeHostId = 21
const MetaLineADoublePrimeJoint1Id = 22
const MetaLineADoublePrimeJoint2Id = 23

const MetaPointAId = 31
const MetaPointBId = 32
const MetaPointAPrimeId = 33
const MetaPointBPrimeId = 34
const MetaPointADoublePrimeId = 35
const MetaPointBDoublePrimeId = 36

const MetaLabelAId = 41
const MetaLabelBId = 42
const MetaLabelAPrimeId = 43
const MetaLabelBPrimeId = 44
const MetaLabelADoublePrimeId = 45
const MetaLabelBDoublePrimeId = 46

const MetaPhase = 101
const MetaTimer = 102

const PhaseDescend = 0f0
const PhaseDrawLineAB = 1f0
const PhaseMoveToA = 2f0
const PhaseDrawA = 3f0
const PhaseMoveToB = 4f0
const PhaseDrawB = 5f0
const PhaseMoveToLineAPrimeStart = 6f0
const PhaseDrawLineAPrime = 7f0
const PhaseMoveToAPrime = 8f0
const PhaseDrawAPrime = 9f0
const PhaseMoveToBPrime = 10f0
const PhaseDrawBPrime = 11f0
const PhaseMoveToLineADoublePrimeStart = 12f0
const PhaseDrawLineADoublePrime = 13f0
const PhaseMoveToADoublePrime = 14f0
const PhaseDrawADoublePrime = 15f0
const PhaseMoveToBDoublePrime = 16f0
const PhaseDrawBDoublePrime = 17f0
const PhaseArcFromBDoublePrimeToA = 17.5f0
const PhaseDragAToB = 18f0
const PhaseDragBToA = 19f0
const PhaseArcToAPrime = 20f0
const PhaseDragAPrimeToBPrime = 21f0
const PhaseDragBPrimeToAPrime = 22f0
const PhaseArcToADoublePrime = 23f0
const PhaseDragADoublePrimeToBDoublePrime = 24f0
const PhaseDragBDoublePrimeToADoublePrime = 25f0
const PhaseArcToA = 26f0
const PhaseDragAToBAgain = 27f0
const PhaseDragBToAAgain = 28f0
const PhaseEndLift = 29f0
const PhaseFinalHold = 30f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """David Hilbert - Foundations of Geometry - Axiom IV,2

IV, 2. If a segment AB is congruent to the segment A'B' and also to the segment A''B'', then the segment A'B' is congruent to the segment A''B''; that is, if AB ≡ A'B' and AB ≡ A''B'', then A'B' ≡ A''B''."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    lineABHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineABHostId))
    lineABJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineABJoint1Id))
    lineABJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineABJoint2Id))
    lineAPrimeHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAPrimeHostId))
    lineAPrimeJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAPrimeJoint1Id))
    lineAPrimeJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAPrimeJoint2Id))
    lineADoublePrimeHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineADoublePrimeHostId))
    lineADoublePrimeJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineADoublePrimeJoint1Id))
    lineADoublePrimeJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineADoublePrimeJoint2Id))

    pointAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    pointBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    pointAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAPrimeId))
    pointBPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBPrimeId))
    pointADoublePrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointADoublePrimeId))
    pointBDoublePrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBDoublePrimeId))

    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labelAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAPrimeId))
    labelBPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBPrimeId))
    labelADoublePrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelADoublePrimeId))
    labelBDoublePrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBDoublePrimeId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [lineABHostId, lineAPrimeHostId, lineADoublePrimeHostId,
         pointAId, pointBId, pointAPrimeId, pointBPrimeId, pointADoublePrimeId, pointBDoublePrimeId,
         labelAId, labelBId, labelAPrimeId, labelBPrimeId, labelADoublePrimeId, labelBDoublePrimeId])

    OdinJuliaBridge.set_point_position(state_ptr, lineABJoint1Id, LineABStart)
    OdinJuliaBridge.set_point_position(state_ptr, lineABJoint2Id, LineABStart)
    OdinJuliaBridge.set_point_position(state_ptr, lineAPrimeJoint1Id, LineAPrimeStart)
    OdinJuliaBridge.set_point_position(state_ptr, lineAPrimeJoint2Id, LineAPrimeStart)
    OdinJuliaBridge.set_point_position(state_ptr, lineADoublePrimeJoint1Id, LineADoublePrimeStart)
    OdinJuliaBridge.set_point_position(state_ptr, lineADoublePrimeJoint2Id, LineADoublePrimeStart)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, LineABColor)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    lineAB = OdinJuliaBridge.create_new_line(state_ptr, LineABStart, LineABStart, LineABColor, 0f0)
    lineAPrime = OdinJuliaBridge.create_new_line(
        state_ptr, LineAPrimeStart, LineAPrimeStart, LineAPrimeColor, 0f0)
    lineADoublePrime = OdinJuliaBridge.create_new_line(
        state_ptr, LineADoublePrimeStart, LineADoublePrimeStart, LineADoublePrimeColor, 0f0)

    pointA = OdinJuliaBridge.create_new_point(state_ptr, PointA, PointAColor, 0f0)
    pointB = OdinJuliaBridge.create_new_point(state_ptr, PointB, PointBColor, 0f0)
    pointAPrime = OdinJuliaBridge.create_new_point(state_ptr, PointAPrime, PointAPrimeColor, 0f0)
    pointBPrime = OdinJuliaBridge.create_new_point(state_ptr, PointBPrime, PointBPrimeColor, 0f0)
    pointADoublePrime = OdinJuliaBridge.create_new_point(
        state_ptr, PointADoublePrime, PointADoublePrimeColor, 0f0)
    pointBDoublePrime = OdinJuliaBridge.create_new_point(
        state_ptr, PointBDoublePrime, PointBDoublePrimeColor, 0f0)

    labelA = OdinJuliaBridge.create_new_label(state_ptr, 'A', LabelAPoint, LabelColor, 16f0)
    labelB = OdinJuliaBridge.create_new_label(state_ptr, 'B', LabelBPoint, LabelColor, 16f0)
    labelAPrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'A', OdinJuliaBridge.LABEL_DECORATION_PRIME, LabelAPrimePoint, LabelColor, 16f0)
    labelBPrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'B', OdinJuliaBridge.LABEL_DECORATION_PRIME, LabelBPrimePoint, LabelColor, 16f0)
    labelADoublePrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'A', OdinJuliaBridge.LABEL_DECORATION_DOUBLEPRIME,
        LabelADoublePrimePoint, LabelColor, 16f0)
    labelBDoublePrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'B', OdinJuliaBridge.LABEL_DECORATION_DOUBLEPRIME,
        LabelBDoublePrimePoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineABHostId, Float32(lineAB.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineABJoint1Id, Float32(lineAB.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineABJoint2Id, Float32(lineAB.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineAPrimeHostId, Float32(lineAPrime.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineAPrimeJoint1Id, Float32(lineAPrime.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineAPrimeJoint2Id, Float32(lineAPrime.joint2Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaLineADoublePrimeHostId, Float32(lineADoublePrime.hostId))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaLineADoublePrimeJoint1Id, Float32(lineADoublePrime.joint1Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaLineADoublePrimeJoint2Id, Float32(lineADoublePrime.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointAId, Float32(pointA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointBId, Float32(pointB.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointAPrimeId, Float32(pointAPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointBPrimeId, Float32(pointBPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointADoublePrimeId, Float32(pointADoublePrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointBDoublePrimeId, Float32(pointBDoublePrime.index))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAId, Float32(labelA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBId, Float32(labelB.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAPrimeId, Float32(labelAPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBPrimeId, Float32(labelBPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelADoublePrimeId, Float32(labelADoublePrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBDoublePrimeId, Float32(labelBDoublePrime.index))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    lineABHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineABHostId))
    lineABJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineABJoint1Id))
    lineABJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineABJoint2Id))
    lineAPrimeHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAPrimeHostId))
    lineAPrimeJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAPrimeJoint1Id))
    lineAPrimeJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAPrimeJoint2Id))
    lineADoublePrimeHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineADoublePrimeHostId))
    lineADoublePrimeJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineADoublePrimeJoint1Id))
    lineADoublePrimeJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineADoublePrimeJoint2Id))

    pointAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    pointBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    pointAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAPrimeId))
    pointBPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBPrimeId))
    pointADoublePrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointADoublePrimeId))
    pointBDoublePrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBDoublePrimeId))

    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labelAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAPrimeId))
    labelBPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBPrimeId))
    labelADoublePrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelADoublePrimeId))
    labelBDoublePrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBDoublePrimeId))

    if lineABHostId < 0 || lineAPrimeHostId < 0 || lineADoublePrimeHostId < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, LineABStart[1], LineABStart[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawLineAB
            timer = 0f0
        end
    elseif phase == PhaseDrawLineAB
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, LineABStart, LineABEnd,
            LineMaxBrush, LineABColor, lineABHostId, lineABJoint1Id, lineABJoint2Id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseMoveToA
            timer = 0f0
        end
    elseif phase == PhaseMoveToA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, LineABEnd, PointA, 0.24f0, 1, :none)

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
            phase = PhaseMoveToLineAPrimeStart
            timer = 0f0
        end
    elseif phase == PhaseMoveToLineAPrimeStart
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointB, LineAPrimeStart, 0.26f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawLineAPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawLineAPrime
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
            phase = PhaseMoveToLineADoublePrimeStart
            timer = 0f0
        end
    elseif phase == PhaseMoveToLineADoublePrimeStart
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointBPrime, LineADoublePrimeStart, 0.26f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawLineADoublePrime
            timer = 0f0
        end
    elseif phase == PhaseDrawLineADoublePrime
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, LineADoublePrimeStart, LineADoublePrimeEnd,
            LineMaxBrush, LineADoublePrimeColor,
            lineADoublePrimeHostId, lineADoublePrimeJoint1Id, lineADoublePrimeJoint2Id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseMoveToADoublePrime
            timer = 0f0
        end
    elseif phase == PhaseMoveToADoublePrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, LineADoublePrimeEnd, PointADoublePrime, 0.24f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawADoublePrime
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelADoublePrimeId)
        end
    elseif phase == PhaseDrawADoublePrime
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, PointADoublePrime,
            PointMaxBrush, PointADoublePrimeColor, pointADoublePrimeId)

        timer += dt
        if timer >= PointDrawDuration
            phase = PhaseMoveToBDoublePrime
            timer = 0f0
        end
    elseif phase == PhaseMoveToBDoublePrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointADoublePrime, PointBDoublePrime, 0.18f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawBDoublePrime
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelBDoublePrimeId)
        end
    elseif phase == PhaseDrawBDoublePrime
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, PointBDoublePrime,
            PointMaxBrush, PointBDoublePrimeColor, pointBDoublePrimeId)

        timer += dt
        if timer >= PointDrawDuration
            phase = PhaseArcFromBDoublePrimeToA
            timer = 0f0
        end
    elseif phase == PhaseArcFromBDoublePrimeToA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointBDoublePrime, PointA, 0.24f0, 1, :none)

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
            phase = PhaseArcToADoublePrime
            timer = 0f0
        end
    elseif phase == PhaseArcToADoublePrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointAPrime, PointADoublePrime, 0.24f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragADoublePrimeToBDoublePrime
            timer = 0f0
        end
    elseif phase == PhaseDragADoublePrimeToBDoublePrime
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointADoublePrime, PointBDoublePrime, DragColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseDragBDoublePrimeToADoublePrime
            timer = 0f0
        end
    elseif phase == PhaseDragBDoublePrimeToADoublePrime
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointBDoublePrime, PointADoublePrime, DragColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseArcToA
            timer = 0f0
        end
    elseif phase == PhaseArcToA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointADoublePrime, PointA, 0.24f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragAToBAgain
            timer = 0f0
        end
    elseif phase == PhaseDragAToBAgain
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointA, PointB, DragColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseDragBToAAgain
            timer = 0f0
        end
    elseif phase == PhaseDragBToAAgain
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

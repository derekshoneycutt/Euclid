module HilbertChapterOneTheorem5

using ..OdinJuliaBridge
using ..EuclidAnimations

export get_view_text, initialize, clean, loop

const LineStart = [0.14f0, 0.50f0, 0f0]
const LineEnd = [0.86f0, 0.50f0, 0f0]

const PointA = [0.34f0, 0.57f0, 0f0]
const PointB = [0.58f0, 0.28f0, 0f0]
const PointAPrime = [0.55f0, 0.74f0, 0f0]
const PenTopZ = 1.4f0

const AlphaLabelPoint = [0.12f0, 0.87f0, 0f0]
const LineLabelPoint = [0.80f0, 0.58f0, 0f0]
const ALabelPoint = PointA + [-0.02f0, 0.015f0, 0f0]
const BLabelPoint = PointB + [0.01f0, -0.02f0, 0f0]
const APrimeLabelPoint = PointAPrime + [0.034f0, 0.058f0, 0f0]

const LabelColor = :plum1
const LineColor = :grey60
const PointAColor = :steelblue
const PointBColor = :palevioletred1
const PointAPrimeColor = :khaki3
const SegmentABColor = :steelblue
const SegmentAAPrimeColor = PointAPrimeColor

const LineMaxBrush = 5f0
const PointMaxBrush = 5f0

const DescendDuration = 1.8f0
const ArcMoveDuration = 1.9f0
const DrawLineDuration = 4.0f0
const DrawPointDuration = 1.9f0
const DrawSegmentDuration = 2.4f0
const EndLiftDuration = 1.8f0

const MetaBoundaryLineHostId = 1
const MetaBoundaryLineJoint1Id = 2
const MetaBoundaryLineJoint2Id = 3
const MetaPointAId = 11
const MetaPointBId = 12
const MetaPointAPrimeId = 13
const MetaSegmentABHostId = 21
const MetaSegmentABJoint1Id = 22
const MetaSegmentABJoint2Id = 23
const MetaSegmentAAPrimeHostId = 24
const MetaSegmentAAPrimeJoint1Id = 25
const MetaSegmentAAPrimeJoint2Id = 26
const MetaAlphaLabelId = 41
const MetaLineLabelId = 42
const MetaALabelId = 43
const MetaBLabelId = 44
const MetaAPrimeLabelId = 45
const MetaPhase = 101
const MetaTimer = 102

const PhaseDescendToLine = 0f0
const PhaseDrawBoundaryLine = 1f0
const PhaseMoveToPointA = 2f0
const PhasePutPointA = 3f0
const PhaseMoveToPointB = 4f0
const PhasePutPointB = 5f0
const PhaseMoveToPointAForAB = 6f0
const PhaseDrawSegmentAB = 7f0
const PhaseMoveToPointAPrime = 8f0
const PhasePutPointAPrime = 9f0
const PhaseMoveToPointAForAAPrime = 10f0
const PhaseDrawSegmentAAPrime = 11f0
const PhaseEndLift = 12f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """David Hilbert - Foundations of Geometry - Theorem 5

Every straight line a, which lies in a plane α, divides the remaining points of this plane into two regions having the following properties: Every point A of the one region determines with each point B of the other region a segment AB containing a point of the straight line a. On the other hand, any two points A, A' of the same region determine a segment AA' containing no point of a."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    boundaryLineHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaBoundaryLineHostId))
    boundaryLineJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaBoundaryLineJoint1Id))
    boundaryLineJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaBoundaryLineJoint2Id))
    pointAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    pointBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    pointAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAPrimeId))
    segmentABHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaSegmentABHostId))
    segmentABJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaSegmentABJoint1Id))
    segmentABJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaSegmentABJoint2Id))
    segmentAAPrimeHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaSegmentAAPrimeHostId))
    segmentAAPrimeJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaSegmentAAPrimeJoint1Id))
    segmentAAPrimeJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaSegmentAAPrimeJoint2Id))
    alphaLabelId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAlphaLabelId))
    lineLabelId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineLabelId))
    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaALabelId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaBLabelId))
    labelAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAPrimeLabelId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [boundaryLineHostId,
         pointAId, pointBId, pointAPrimeId,
         segmentABHostId, segmentAAPrimeHostId,
         alphaLabelId, lineLabelId, labelAId, labelBId, labelAPrimeId])

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescendToLine)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.set_point_position(state_ptr, boundaryLineJoint1Id, LineStart)
    OdinJuliaBridge.set_point_position(state_ptr, boundaryLineJoint2Id, LineStart)

    OdinJuliaBridge.set_point_position(state_ptr, segmentABJoint1Id, PointA)
    OdinJuliaBridge.set_point_position(state_ptr, segmentABJoint2Id, PointA)
    OdinJuliaBridge.set_point_position(state_ptr, segmentAAPrimeJoint1Id, PointA)
    OdinJuliaBridge.set_point_position(state_ptr, segmentAAPrimeJoint2Id, PointA)

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, LineColor)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    boundaryLine = OdinJuliaBridge.create_new_line(
        state_ptr, LineStart, LineStart, LineColor, 0f0)
    pointA = OdinJuliaBridge.create_new_point(
        state_ptr, PointA, PointAColor, 0f0)
    pointB = OdinJuliaBridge.create_new_point(
        state_ptr, PointB, PointBColor, 0f0)
    pointAPrime = OdinJuliaBridge.create_new_point(
        state_ptr, PointAPrime, PointAPrimeColor, 0f0)

    segmentAB = OdinJuliaBridge.create_new_line(
        state_ptr, PointA, PointA, SegmentABColor, 0f0)
    segmentAAPrime = OdinJuliaBridge.create_new_line(
        state_ptr, PointA, PointA, SegmentAAPrimeColor, 0f0)

    alphaLabel = OdinJuliaBridge.create_new_label(
        state_ptr, 'α', AlphaLabelPoint, LabelColor, 16f0)
    lineLabel = OdinJuliaBridge.create_new_label(
        state_ptr, 'a', LineLabelPoint, LabelColor, 16f0)
    labelA = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', ALabelPoint, LabelColor, 16f0)
    labelB = OdinJuliaBridge.create_new_label(
        state_ptr, 'B', BLabelPoint, LabelColor, 16f0)
    labelAPrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'A', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        APrimeLabelPoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaBoundaryLineHostId, Float32(boundaryLine.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaBoundaryLineJoint1Id, Float32(boundaryLine.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaBoundaryLineJoint2Id, Float32(boundaryLine.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointAId, Float32(pointA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointBId, Float32(pointB.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointAPrimeId, Float32(pointAPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaSegmentABHostId, Float32(segmentAB.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaSegmentABJoint1Id, Float32(segmentAB.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaSegmentABJoint2Id, Float32(segmentAB.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaSegmentAAPrimeHostId, Float32(segmentAAPrime.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaSegmentAAPrimeJoint1Id, Float32(segmentAAPrime.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaSegmentAAPrimeJoint2Id, Float32(segmentAAPrime.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaAlphaLabelId, Float32(alphaLabel.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineLabelId, Float32(lineLabel.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaALabelId, Float32(labelA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaBLabelId, Float32(labelB.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaAPrimeLabelId, Float32(labelAPrime.index))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    boundaryLineHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaBoundaryLineHostId))
    boundaryLineJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaBoundaryLineJoint1Id))
    boundaryLineJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaBoundaryLineJoint2Id))
    pointAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    pointBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    pointAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAPrimeId))
    segmentABHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaSegmentABHostId))
    segmentABJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaSegmentABJoint1Id))
    segmentABJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaSegmentABJoint2Id))
    segmentAAPrimeHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaSegmentAAPrimeHostId))
    segmentAAPrimeJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaSegmentAAPrimeJoint1Id))
    segmentAAPrimeJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaSegmentAAPrimeJoint2Id))
    alphaLabelId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAlphaLabelId))
    lineLabelId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineLabelId))
    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaALabelId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaBLabelId))
    labelAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAPrimeLabelId))

    if boundaryLineHostId < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescendToLine
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ,
            LineStart[1], LineStart[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawBoundaryLine
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, alphaLabelId)
        end
    elseif phase == PhaseDrawBoundaryLine
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, LineStart, LineEnd,
            LineMaxBrush, LineColor,
            boundaryLineHostId, boundaryLineJoint1Id, boundaryLineJoint2Id)

        if timer / DrawLineDuration >= 0.5f0
            OdinJuliaBridge.show_point(state_ptr, lineLabelId)
        end

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
            state_ptr, timer, DrawPointDuration, PointA,
            PointMaxBrush, PointAColor, pointAId)

        timer += dt
        if timer >= DrawPointDuration
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
            state_ptr, timer, DrawPointDuration, PointB,
            PointMaxBrush, PointBColor, pointBId)

        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseMoveToPointAForAB
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointAForAB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointB, PointA, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawSegmentAB
            timer = 0f0
            OdinJuliaBridge.set_pen_active(state_ptr, 0, SegmentABColor)
        end
    elseif phase == PhaseDrawSegmentAB
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawSegmentDuration, PointA, PointB,
            LineMaxBrush, SegmentABColor,
            segmentABHostId, segmentABJoint1Id, segmentABJoint2Id)

        timer += dt
        if timer >= DrawSegmentDuration
            phase = PhaseMoveToPointAPrime
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointAPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointB, PointAPrime, 0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePutPointAPrime
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelAPrimeId)
        end
    elseif phase == PhasePutPointAPrime
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointAPrime,
            PointMaxBrush, PointAPrimeColor, pointAPrimeId)

        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseMoveToPointAForAAPrime
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointAForAAPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointAPrime, PointA, 0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawSegmentAAPrime
            timer = 0f0
            OdinJuliaBridge.set_pen_active(state_ptr, 0, SegmentAAPrimeColor)
        end
    elseif phase == PhaseDrawSegmentAAPrime
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawSegmentDuration, PointA, PointAPrime,
            LineMaxBrush, SegmentAAPrimeColor,
            segmentAAPrimeHostId, segmentAAPrimeJoint1Id, segmentAAPrimeJoint2Id)

        timer += dt
        if timer >= DrawSegmentDuration
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ,
            PointAPrime[1], PointAPrime[2])

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

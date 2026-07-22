module HilbertChapterOneTheorem9

using ..OdinJuliaBridge
using ..EuclidAnimations

export get_view_text, initialize, clean, loop

const LineYUnprimed = 0.68f0
const LineYPrimed = 0.32f0
const LineXStart = 0.10f0
const LineXEnd = 0.90f0

const LineAStart = [LineXStart, LineYUnprimed, 0f0]
const LineAEnd = [LineXEnd, LineYUnprimed, 0f0]
const LinePrimeStart = [LineXStart, LineYPrimed, 0f0]
const LinePrimeEnd = [LineXEnd, LineYPrimed, 0f0]

const PointA = [0.18f0, LineYUnprimed, 0f0]
const PointB = [0.28f0, LineYUnprimed, 0f0]
const PointC = [0.38f0, LineYUnprimed, 0f0]
const PointD = [0.48f0, LineYUnprimed, 0f0]
const PointK = [0.72f0, LineYUnprimed, 0f0]
const PointL = [0.82f0, LineYUnprimed, 0f0]

const PointAPrime = [0.18f0, LineYPrimed, 0f0]
const PointBPrime = [0.28f0, LineYPrimed, 0f0]
const PointCPrime = [0.38f0, LineYPrimed, 0f0]
const PointDPrime = [0.48f0, LineYPrimed, 0f0]
const PointKPrime = [0.72f0, LineYPrimed, 0f0]
const PointLPrime = [0.82f0, LineYPrimed, 0f0]

const UnprimedLabelOffset = [0f0, 0.07f0, 0f0]
const PrimedLabelOffset = [0f0, -0.07f0, 0f0]

const LabelAPoint = PointA + UnprimedLabelOffset
const LabelBPoint = PointB + UnprimedLabelOffset
const LabelCPoint = PointC + UnprimedLabelOffset
const LabelDPoint = PointD + UnprimedLabelOffset
const LabelKPoint = PointK + UnprimedLabelOffset
const LabelLPoint = PointL + UnprimedLabelOffset

const LabelAPrimePoint = PointAPrime + PrimedLabelOffset
const LabelBPrimePoint = PointBPrime + PrimedLabelOffset
const LabelCPrimePoint = PointCPrime + PrimedLabelOffset
const LabelDPrimePoint = PointDPrime + PrimedLabelOffset
const LabelKPrimePoint = PointKPrime + PrimedLabelOffset
const LabelLPrimePoint = PointLPrime + PrimedLabelOffset

const LabelaLinePoint = LineAStart + [0.03f0, 0.06f0, 0f0]
const LabelAPrimeLinePoint = LinePrimeStart + [0.03f0, -0.08f0, 0f0]

const LabelColor = :plum1
const LineColor = :steelblue
const PointOddColor = :palevioletred1
const PointEvenColor = :khaki3
const LineMaxBrush = 5f0
const PointMaxBrush = 5f0
const PenTopZ = 1.4f0

const DescendDuration = 1.6f0
const DrawLineDuration = 3.2f0
const ArcMoveDuration = 1.0f0
const PointDrawDuration = 1.2f0
const DragLegDuration = 1.1f0
const EndLiftDuration = 1.8f0
const FinalHoldDuration = 0.9f0

const MetaLineAHostId = 1
const MetaLineAJoint1Id = 2
const MetaLineAJoint2Id = 3
const MetaLinePrimeHostId = 4
const MetaLinePrimeJoint1Id = 5
const MetaLinePrimeJoint2Id = 6

const MetaPointBase = 10
const MetaPrimePointBase = 20
const MetaLabelBase = 30
const MetaLabelPrimeBase = 40
const MetaLabelaLine = 51
const MetaLabelAPrimeLine = 52

const MetaPhase = 101
const MetaTimer = 102
const MetaPointIndex = 103
const MetaPassIndex = 104

const PhaseDescend = 0f0
const PhaseDrawLineA = 1f0
const PhaseArcToUnprimedPoint = 2f0
const PhaseDrawUnprimedPoint = 3f0
const PhaseArcToLinePrime = 4f0
const PhaseDrawLinePrime = 5f0
const PhaseArcToPrimedPoint = 6f0
const PhaseDrawPrimedPoint = 7f0
const PhaseArcToPass = 8f0
const PhaseTraceLeg1 = 9f0
const PhaseTraceLeg2 = 10f0
const PhaseEndLift = 11f0
const PhaseFinalHold = 12f0

const UnprimedPointPositions = (PointA, PointB, PointC, PointD, PointK, PointL)
const PrimedPointPositions = (
    PointAPrime, PointBPrime, PointCPrime, PointDPrime, PointKPrime, PointLPrime)
const PointColors = (
    PointOddColor, PointEvenColor, PointOddColor,
    PointEvenColor, PointOddColor, PointEvenColor)
const UnprimedLabelChars = ('A', 'B', 'C', 'D', 'K', 'L')
const UnprimedLabelPoints = (
    LabelAPoint, LabelBPoint, LabelCPoint, LabelDPoint, LabelKPoint, LabelLPoint)
const PrimedLabelPoints = (
    LabelAPrimePoint, LabelBPrimePoint, LabelCPrimePoint,
    LabelDPrimePoint, LabelKPrimePoint, LabelLPrimePoint)

# Each leg is (start, mid, end, dragColor). Drag color follows the mid point.
const TraceLegs = (
    (PointA, PointB, PointC, PointEvenColor),
    (PointA, PointB, PointD, PointEvenColor),
    (PointA, PointB, PointK, PointEvenColor),
    (PointA, PointB, PointL, PointEvenColor),
    (PointA, PointC, PointD, PointOddColor),
    (PointA, PointC, PointK, PointOddColor),
    (PointA, PointC, PointL, PointOddColor),
    (PointAPrime, PointBPrime, PointCPrime, PointEvenColor),
    (PointAPrime, PointBPrime, PointDPrime, PointEvenColor),
    (PointAPrime, PointBPrime, PointKPrime, PointEvenColor),
    (PointAPrime, PointBPrime, PointLPrime, PointEvenColor),
    (PointAPrime, PointCPrime, PointDPrime, PointOddColor),
    (PointAPrime, PointCPrime, PointKPrime, PointOddColor),
    (PointAPrime, PointCPrime, PointLPrime, PointOddColor),
)
const TotalPassCount = length(TraceLegs)


function get_view_text(state_ptr::Ptr{Cvoid})
    """David Hilbert - Foundations of Geometry - Theorem 9

If the first of two congruent series of points A, B, C, D, ..., K, L and A', B', C', D', ..., K', L' is so arranged that B lies between A and C, D, ..., K, L, and C between A, B and D, ..., K, L, etc., then the points A', B', C', D', ..., K', L' of the second series are arranged in a similar way; that is to say, B' lies between A' and C', D', ..., K', L', and C' lies between A', B' and D', ..., K', L', etc."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    lineAHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAHostId))
    lineAJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAJoint1Id))
    lineAJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAJoint2Id))
    linePrimeHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLinePrimeHostId))
    linePrimeJoint1Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaLinePrimeJoint1Id))
    linePrimeJoint2Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaLinePrimeJoint2Id))

    hideIds = Integer[lineAHostId, linePrimeHostId]
    for i in 1:6
        push!(hideIds,
            Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBase + i)))
        push!(hideIds,
            Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPrimePointBase + i)))
        push!(hideIds,
            Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBase + i)))
        push!(hideIds,
            Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelPrimeBase + i)))
    end
    push!(hideIds, Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelaLine)))
    push!(hideIds,
        Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAPrimeLine)))

    OdinJuliaBridge.hide_point_batch(state_ptr, hideIds)

    OdinJuliaBridge.set_point_position(state_ptr, lineAJoint1Id, LineAStart)
    OdinJuliaBridge.set_point_position(state_ptr, lineAJoint2Id, LineAStart)
    OdinJuliaBridge.set_point_position(state_ptr, linePrimeJoint1Id, LinePrimeStart)
    OdinJuliaBridge.set_point_position(state_ptr, linePrimeJoint2Id, LinePrimeStart)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointIndex, 0f0)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPassIndex, 0f0)

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, LineColor)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    lineA = OdinJuliaBridge.create_new_line(
        state_ptr, LineAStart, LineAStart, LineColor, 0f0)
    linePrime = OdinJuliaBridge.create_new_line(
        state_ptr, LinePrimeStart, LinePrimeStart, LineColor, 0f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineAHostId, Float32(lineA.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineAJoint1Id, Float32(lineA.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineAJoint2Id, Float32(lineA.joint2Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaLinePrimeHostId, Float32(linePrime.hostId))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaLinePrimeJoint1Id, Float32(linePrime.joint1Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaLinePrimeJoint2Id, Float32(linePrime.joint2Id))

    for i in 1:6
        pointUnprimed = OdinJuliaBridge.create_new_point(
            state_ptr, UnprimedPointPositions[i], PointColors[i], 0f0)
        OdinJuliaBridge.set_animation_meta(
            state_ptr, MetaPointBase + i, Float32(pointUnprimed.index))
        pointPrimed = OdinJuliaBridge.create_new_point(
            state_ptr, PrimedPointPositions[i], PointColors[i], 0f0)
        OdinJuliaBridge.set_animation_meta(
            state_ptr, MetaPrimePointBase + i, Float32(pointPrimed.index))
    end

    for i in 1:6
        labelUnprimed = OdinJuliaBridge.create_new_label(
            state_ptr, UnprimedLabelChars[i], UnprimedLabelPoints[i], LabelColor, 16f0)
        OdinJuliaBridge.set_animation_meta(
            state_ptr, MetaLabelBase + i, Float32(labelUnprimed.index))
        labelPrimed = OdinJuliaBridge.create_new_label_decorated(
            state_ptr, UnprimedLabelChars[i], OdinJuliaBridge.LABEL_DECORATION_PRIME,
            PrimedLabelPoints[i], LabelColor, 16f0)
        OdinJuliaBridge.set_animation_meta(
            state_ptr, MetaLabelPrimeBase + i, Float32(labelPrimed.index))
    end

    labelaLine = OdinJuliaBridge.create_new_label(
        state_ptr, 'a', LabelaLinePoint, LabelColor, 16f0)
    labelAPrimeLine = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'a', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelAPrimeLinePoint, LabelColor, 16f0)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaLabelaLine, Float32(labelaLine.index))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaLabelAPrimeLine, Float32(labelAPrimeLine.index))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    lineAHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAHostId))
    lineAJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAJoint1Id))
    lineAJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAJoint2Id))
    linePrimeHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLinePrimeHostId))
    linePrimeJoint1Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaLinePrimeJoint1Id))
    linePrimeJoint2Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaLinePrimeJoint2Id))

    if lineAHostId < 0 || linePrimeHostId < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)
    pointIndex = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointIndex))
    passIndex = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPassIndex))

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, LineAStart[1], LineAStart[2])
        timer += dt
        if timer >= DescendDuration
            OdinJuliaBridge.show_point(state_ptr,
                Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelaLine)))
            phase = PhaseDrawLineA
            timer = 0f0
        end
    elseif phase == PhaseDrawLineA
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, LineAStart, LineAEnd,
            LineMaxBrush, LineColor, lineAHostId, lineAJoint1Id, lineAJoint2Id)
        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseArcToUnprimedPoint
            pointIndex = 0
            timer = 0f0
        end
    elseif phase == PhaseArcToUnprimedPoint
        source = pointIndex == 0 ? LineAEnd : UnprimedPointPositions[pointIndex]
        target = UnprimedPointPositions[pointIndex + 1]
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, source, target, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            labelId = Integer(OdinJuliaBridge.get_animation_meta(
                state_ptr, MetaLabelBase + pointIndex + 1))
            OdinJuliaBridge.show_point(state_ptr, labelId)
            phase = PhaseDrawUnprimedPoint
            timer = 0f0
        end
    elseif phase == PhaseDrawUnprimedPoint
        pointId = Integer(OdinJuliaBridge.get_animation_meta(
            state_ptr, MetaPointBase + pointIndex + 1))
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, UnprimedPointPositions[pointIndex + 1],
            PointMaxBrush, PointColors[pointIndex + 1], pointId)
        timer += dt
        if timer >= PointDrawDuration
            pointIndex += 1
            timer = 0f0
            if pointIndex >= 6
                phase = PhaseArcToLinePrime
                pointIndex = 0
            else
                phase = PhaseArcToUnprimedPoint
            end
        end
    elseif phase == PhaseArcToLinePrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointL, LinePrimeStart, 0.28f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawLinePrime
            timer = 0f0
        end
    elseif phase == PhaseDrawLinePrime
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, LinePrimeStart, LinePrimeEnd,
            LineMaxBrush, LineColor, linePrimeHostId, linePrimeJoint1Id, linePrimeJoint2Id)
        timer += dt
        if timer >= DrawLineDuration
            OdinJuliaBridge.show_point(state_ptr,
                Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAPrimeLine)))
            phase = PhaseArcToPrimedPoint
            pointIndex = 0
            timer = 0f0
        end
    elseif phase == PhaseArcToPrimedPoint
        source = pointIndex == 0 ? LinePrimeEnd : PrimedPointPositions[pointIndex]
        target = PrimedPointPositions[pointIndex + 1]
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, source, target, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            labelId = Integer(OdinJuliaBridge.get_animation_meta(
                state_ptr, MetaLabelPrimeBase + pointIndex + 1))
            OdinJuliaBridge.show_point(state_ptr, labelId)
            phase = PhaseDrawPrimedPoint
            timer = 0f0
        end
    elseif phase == PhaseDrawPrimedPoint
        pointId = Integer(OdinJuliaBridge.get_animation_meta(
            state_ptr, MetaPrimePointBase + pointIndex + 1))
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, PrimedPointPositions[pointIndex + 1],
            PointMaxBrush, PointColors[pointIndex + 1], pointId)
        timer += dt
        if timer >= PointDrawDuration
            pointIndex += 1
            timer = 0f0
            if pointIndex >= 6
                phase = PhaseArcToPass
                passIndex = 0
            else
                phase = PhaseArcToPrimedPoint
            end
        end
    elseif phase == PhaseArcToPass
        startPt, _, _, _ = TraceLegs[passIndex + 1]
        source = passIndex == 0 ? PointLPrime : TraceLegs[passIndex][3]
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, source, startPt, 0.24f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseTraceLeg1
            timer = 0f0
        end
    elseif phase == PhaseTraceLeg1
        startPt, midPt, _, color = TraceLegs[passIndex + 1]
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragLegDuration, startPt, midPt, color)
        timer += dt
        if timer >= DragLegDuration
            phase = PhaseTraceLeg2
            timer = 0f0
        end
    elseif phase == PhaseTraceLeg2
        _, midPt, endPt, color = TraceLegs[passIndex + 1]
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragLegDuration, midPt, endPt, color)
        timer += dt
        if timer >= DragLegDuration
            passIndex += 1
            timer = 0f0
            if passIndex >= TotalPassCount
                phase = PhaseEndLift
            else
                phase = PhaseArcToPass
            end
        end
    elseif phase == PhaseEndLift
        endPt = TraceLegs[TotalPassCount][3]
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ, endPt[1], endPt[2])
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
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointIndex, Float32(pointIndex))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPassIndex, Float32(passIndex))
end

end

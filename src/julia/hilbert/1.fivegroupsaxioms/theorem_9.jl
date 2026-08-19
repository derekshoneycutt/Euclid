module HilbertChapterOneTheorem9

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

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

# Each leg is (start, mid, end, drag_color). Drag color follows the mid point.
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
    (PointAPrime, PointCPrime, PointLPrime, PointOddColor))
const TotalPassCount = length(TraceLegs)


function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - Theorem 9

If the first of two congruent series of points A, B, C, D, ..., K, L and A', B', C', D', ..., K', L' is so arranged that B lies between A and C, D, ..., K, L, and C between A, B and D, ..., K, L, etc., then the points A', B', C', D', ..., K', L' of the second series are arranged in a similar way; that is to say, B' lies between A' and C', D', ..., K', L', and C' lies between A', B' and D', ..., K', L', etc."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - Theorem 9}

If the first of two congruent series of points $A, B, C, D, ..., K, L$ \euclidline[color=steelblue,length=3,thickness=4]
and $A', B', C', D', ..., K', L'$ \euclidline[color=steelblue,length=3,thickness=4] is so arranged that
$B$ \euclidpoint[color=khaki3,size=1] lies between $A$ \euclidpoint[color=palevioletred1,size=1] and $C, D, ..., K, L$, and $C$ \euclidpoint[color=palevioletred1,size=1] between
$A, B$ and $D, ..., K, L$, etc., then the points $A', B', C', D', ..., K', L'$ of the second series are arranged
in a similar way; that is to say, $B'$ \euclidpoint[color=khaki3,size=1]
lies between $A'$ \euclidpoint[color=palevioletred1,size=1] and $C', D', ..., K', L'$,
and $C'$ \euclidpoint[color=palevioletred1,size=1] lies between $A', B'$ and $D', ..., K', L'$, etc."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    line_a_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineAHostId))
    line_a_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineAJoint1Id))
    line_a_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineAJoint2Id))
    line_prime_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLinePrimeHostId))
    line_prime_joint1_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaLinePrimeJoint1Id))
    line_prime_joint2_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaLinePrimeJoint2Id))

    hide_ids = Integer[line_a_host_id, line_prime_host_id]
    for i in 1:6
        push!(hide_ids,
            Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBase + i)))
        push!(hide_ids,
            Integer(OdinJuliaBridge.get_animation_meta(
                state_ptr, MetaPrimePointBase + i)))
        push!(hide_ids,
            Integer(OdinJuliaBridge.get_animation_meta(
                state_ptr, MetaLabelBase + i)))
        push!(hide_ids,
            Integer(OdinJuliaBridge.get_animation_meta(
                state_ptr, MetaLabelPrimeBase + i)))
    end
    push!(hide_ids, Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLabelaLine)))
    push!(hide_ids,
        Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAPrimeLine)))

    OdinJuliaBridge.hide_point_batch(state_ptr, hide_ids)

    OdinJuliaBridge.set_point_position(state_ptr, line_a_joint1_id, LineAStart)
    OdinJuliaBridge.set_point_position(state_ptr, line_a_joint2_id, LineAStart)
    OdinJuliaBridge.set_point_position(state_ptr, line_prime_joint1_id, LinePrimeStart)
    OdinJuliaBridge.set_point_position(state_ptr, line_prime_joint2_id, LinePrimeStart)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointIndex, 0f0)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPassIndex, 0f0)

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, LineColor)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    line_a = OdinJuliaBridge.create_new_line(
        state_ptr, LineAStart, LineAStart, LineColor, 0f0)
    line_prime = OdinJuliaBridge.create_new_line(
        state_ptr, LinePrimeStart, LinePrimeStart, LineColor, 0f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineAHostId, line_a.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineAJoint1Id, line_a.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineAJoint2Id, line_a.joint2_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaLinePrimeHostId, line_prime.host_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaLinePrimeJoint1Id, line_prime.joint1_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaLinePrimeJoint2Id, line_prime.joint2_id)

    for i in 1:6
        point_unprimed = OdinJuliaBridge.create_new_point(
            state_ptr, UnprimedPointPositions[i], PointColors[i], 0f0)
        OdinJuliaBridge.set_animation_meta(
            state_ptr, MetaPointBase + i, point_unprimed.index)
        point_primed = OdinJuliaBridge.create_new_point(
            state_ptr, PrimedPointPositions[i], PointColors[i], 0f0)
        OdinJuliaBridge.set_animation_meta(
            state_ptr, MetaPrimePointBase + i, point_primed.index)
    end

    for i in 1:6
        label_unprimed = OdinJuliaBridge.create_new_label(
            state_ptr, UnprimedLabelChars[i], UnprimedLabelPoints[i], LabelColor, 16f0)
        OdinJuliaBridge.set_animation_meta(
            state_ptr, MetaLabelBase + i, label_unprimed.index)
        label_primed = OdinJuliaBridge.create_new_label_decorated(
            state_ptr, UnprimedLabelChars[i], OdinJuliaBridge.LABEL_DECORATION_PRIME,
            PrimedLabelPoints[i], LabelColor, 16f0)
        OdinJuliaBridge.set_animation_meta(
            state_ptr, MetaLabelPrimeBase + i, label_primed.index)
    end

    labela_line = OdinJuliaBridge.create_new_label(
        state_ptr, 'a', LabelaLinePoint, LabelColor, 16f0)
    label_a_prime_line = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'a', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelAPrimeLinePoint, LabelColor, 16f0)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaLabelaLine, labela_line.index)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaLabelAPrimeLine, label_a_prime_line.index)

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    line_a_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineAHostId))
    line_a_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineAJoint1Id))
    line_a_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineAJoint2Id))
    line_prime_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLinePrimeHostId))
    line_prime_joint1_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaLinePrimeJoint1Id))
    line_prime_joint2_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaLinePrimeJoint2Id))

    if line_a_host_id < 0 || line_prime_host_id < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)
    point_index = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointIndex))
    pass_index = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPassIndex))

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
            LineMaxBrush, LineColor, line_a_host_id, line_a_joint1_id, line_a_joint2_id)
        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseArcToUnprimedPoint
            point_index = 0
            timer = 0f0
        end
    elseif phase == PhaseArcToUnprimedPoint
        source = point_index == 0 ? LineAEnd : UnprimedPointPositions[point_index]
        target = UnprimedPointPositions[point_index + 1]
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, source, target, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            label_id = Integer(OdinJuliaBridge.get_animation_meta(
                state_ptr, MetaLabelBase + point_index + 1))
            OdinJuliaBridge.show_point(state_ptr, label_id)
            phase = PhaseDrawUnprimedPoint
            timer = 0f0
        end
    elseif phase == PhaseDrawUnprimedPoint
        pointid = Integer(OdinJuliaBridge.get_animation_meta(
            state_ptr, MetaPointBase + point_index + 1))
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, UnprimedPointPositions[point_index + 1],
            PointMaxBrush, PointColors[point_index + 1], pointid)
        timer += dt
        if timer >= PointDrawDuration
            point_index += 1
            timer = 0f0
            if point_index >= 6
                phase = PhaseArcToLinePrime
                point_index = 0
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
            LineMaxBrush, LineColor, line_prime_host_id,
            line_prime_joint1_id, line_prime_joint2_id)
        timer += dt
        if timer >= DrawLineDuration
            OdinJuliaBridge.show_point(state_ptr,
                Integer(OdinJuliaBridge.get_animation_meta(
                    state_ptr, MetaLabelAPrimeLine)))
            phase = PhaseArcToPrimedPoint
            point_index = 0
            timer = 0f0
        end
    elseif phase == PhaseArcToPrimedPoint
        source = point_index == 0 ? LinePrimeEnd : PrimedPointPositions[point_index]
        target = PrimedPointPositions[point_index + 1]
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, source, target, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            label_id = Integer(OdinJuliaBridge.get_animation_meta(
                state_ptr, MetaLabelPrimeBase + point_index + 1))
            OdinJuliaBridge.show_point(state_ptr, label_id)
            phase = PhaseDrawPrimedPoint
            timer = 0f0
        end
    elseif phase == PhaseDrawPrimedPoint
        pointid = Integer(OdinJuliaBridge.get_animation_meta(
            state_ptr, MetaPrimePointBase + point_index + 1))
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, PrimedPointPositions[point_index + 1],
            PointMaxBrush, PointColors[point_index + 1], pointid)
        timer += dt
        if timer >= PointDrawDuration
            point_index += 1
            timer = 0f0
            if point_index >= 6
                phase = PhaseArcToPass
                pass_index = 0
            else
                phase = PhaseArcToPrimedPoint
            end
        end
    elseif phase == PhaseArcToPass
        start_pt, _, _, _ = TraceLegs[pass_index + 1]
        source = pass_index == 0 ? PointLPrime : TraceLegs[pass_index][3]
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, source, start_pt, 0.24f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseTraceLeg1
            timer = 0f0
        end
    elseif phase == PhaseTraceLeg1
        start_pt, mid_pt, _, color = TraceLegs[pass_index + 1]
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragLegDuration, start_pt, mid_pt, color)
        timer += dt
        if timer >= DragLegDuration
            phase = PhaseTraceLeg2
            timer = 0f0
        end
    elseif phase == PhaseTraceLeg2
        _, mid_pt, end_pt, color = TraceLegs[pass_index + 1]
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragLegDuration, mid_pt, end_pt, color)
        timer += dt
        if timer >= DragLegDuration
            pass_index += 1
            timer = 0f0
            if pass_index >= TotalPassCount
                phase = PhaseEndLift
            else
                phase = PhaseArcToPass
            end
        end
    elseif phase == PhaseEndLift
        end_pt = TraceLegs[TotalPassCount][3]
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ, end_pt[1], end_pt[2])
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
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointIndex, point_index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPassIndex, pass_index)
end

end

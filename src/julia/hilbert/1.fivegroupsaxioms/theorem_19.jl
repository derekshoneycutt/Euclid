module HilbertChapterOneTheorem19

using ..OdinJuliaBridge
using ..EuclidAnimations

export get_view_text, initialize, clean, loop

const LowerLineStart = [0.18f0, 0.35f0, 0f0]
const LowerLineEnd = [0.88f0, 0.35f0, 0f0]
const UpperLineStart = [0.18f0, 0.70f0, 0f0]
const UpperLineEnd = [0.88f0, 0.70f0, 0f0]

const TransversalStart = [0.32f0, 0.88f0, 0f0]
const TransversalEnd = [0.68f0, 0.18f0, 0f0]

const TopIntersection = [0.41257143f0, 0.70f0, 0f0]
const BottomIntersection = [0.59257144f0, 0.35f0, 0f0]

const MarkerRadius = 0.08f0

const ThetaTopUpperRight = Float32(atan(UpperLineEnd[2] - TopIntersection[2], UpperLineEnd[1] - TopIntersection[1]))
const ThetaTopUpperLeft = Float32(atan(UpperLineStart[2] - TopIntersection[2], UpperLineStart[1] - TopIntersection[1]))
const ThetaTopDown = Float32(atan(BottomIntersection[2] - TopIntersection[2], BottomIntersection[1] - TopIntersection[1]))

const ThetaBottomLowerRight = Float32(atan(LowerLineEnd[2] - BottomIntersection[2], LowerLineEnd[1] - BottomIntersection[1]))
const ThetaBottomLowerLeft = Float32(atan(LowerLineStart[2] - BottomIntersection[2], LowerLineStart[1] - BottomIntersection[1]))
const ThetaBottomUp = Float32(atan(TopIntersection[2] - BottomIntersection[2], TopIntersection[1] - BottomIntersection[1]))

const MarkerAlt1Start = [
    TopIntersection[1] + MarkerRadius * Float32(cos(ThetaTopUpperRight)),
    TopIntersection[2] + MarkerRadius * Float32(sin(ThetaTopUpperRight)),
    0f0,
]
const MarkerAlt1End = [
    TopIntersection[1] + MarkerRadius * Float32(cos(ThetaTopDown)),
    TopIntersection[2] + MarkerRadius * Float32(sin(ThetaTopDown)),
    0f0,
]

const MarkerAlt2Start = [
    BottomIntersection[1] + MarkerRadius * Float32(cos(ThetaBottomUp)),
    BottomIntersection[2] + MarkerRadius * Float32(sin(ThetaBottomUp)),
    0f0,
]
const MarkerAlt2End = [
    BottomIntersection[1] + MarkerRadius * Float32(cos(ThetaBottomLowerLeft)),
    BottomIntersection[2] + MarkerRadius * Float32(sin(ThetaBottomLowerLeft)),
    0f0,
]

const MarkerExtInt1Start = [
    TopIntersection[1] + MarkerRadius * Float32(cos(ThetaTopUpperLeft)),
    TopIntersection[2] + MarkerRadius * Float32(sin(ThetaTopUpperLeft)),
    0f0,
]
const MarkerExtInt1End = [
    TopIntersection[1] + MarkerRadius * Float32(cos(ThetaTopDown)),
    TopIntersection[2] + MarkerRadius * Float32(sin(ThetaTopDown)),
    0f0,
]

const MarkerExtInt2Start = [
    BottomIntersection[1] + MarkerRadius * Float32(cos(ThetaBottomLowerRight)),
    BottomIntersection[2] + MarkerRadius * Float32(sin(ThetaBottomLowerRight)),
    0f0,
]
const MarkerExtInt2End = [
    BottomIntersection[1] + MarkerRadius * Float32(cos(ThetaBottomUp)),
    BottomIntersection[2] + MarkerRadius * Float32(sin(ThetaBottomUp)),
    0f0,
]

const AngleAlt1Theta = ThetaTopDown - ThetaTopUpperRight
const AngleAlt2Theta = ThetaBottomLowerLeft - ThetaBottomUp
const AngleExtInt1Theta = ThetaTopDown - ThetaTopUpperLeft + 2f0 * π
const AngleExtInt2Theta = ThetaBottomUp - ThetaBottomLowerRight

const LowerLineColor = :steelblue
const UpperLineColor = :khaki3
const TransversalColor = :palevioletred1
const HighlightColor = :lightgreen

const EdgeBrush = 5f0
const PenTopZ = 1.4f0
const CompassTopZ = 1.4f0
const ToolResetOffscreenJoint1 = [0.50f0, 1.25f0, 1.55f0]
const ToolResetOffscreenJoint2 = [0.57f0, 1.25f0, 1.55f0]

const DescendDuration = 1.8f0
const DrawDuration = 2.2f0
const ArcMoveDuration = 1.35f0
const SweepDuration = 0.95f0
const PenLiftDuration = 1.6f0
const CompassLiftDuration = 1.8f0
const FinalHoldDuration = 0.35f0

const MetaLowerHostId = 1
const MetaLowerJoint1Id = 2
const MetaLowerJoint2Id = 3
const MetaUpperHostId = 11
const MetaUpperJoint1Id = 12
const MetaUpperJoint2Id = 13
const MetaTransversalHostId = 21
const MetaTransversalJoint1Id = 22
const MetaTransversalJoint2Id = 23

const MetaPhase = 101
const MetaTimer = 102

const PhasePenDescendLowerStart = 0f0
const PhaseDrawLower = 1f0
const PhaseArcToUpper = 2f0
const PhaseDrawUpper = 3f0
const PhaseArcToTransversal = 4f0
const PhaseDrawTransversal = 5f0
const PhasePenRise = 6f0

const PhaseCompassDescendAlt1 = 7f0
const PhaseAlt1Forward = 8f0
const PhaseAlt1Back = 9f0
const PhaseArcToAlt2 = 10f0
const PhaseAlt2Forward = 11f0
const PhaseAlt2Back = 12f0
const PhaseArcToExtInt1 = 13f0
const PhaseExtInt1Forward = 14f0
const PhaseExtInt1Back = 15f0
const PhaseArcToExtInt2 = 16f0
const PhaseExtInt2Forward = 17f0
const PhaseExtInt2Back = 18f0
const PhaseCompassRise = 19f0
const PhaseFinalHold = 20f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """David Hilbert - Foundations of Geometry - Theorem 19

If two parallel lines are cut by a third straight line, the alternate-interior angles and also the exterior-interior angles are congruent. Conversely, if the alternate-interior or the exterior-interior angles are congruent, the given lines are parallel."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    lowerHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLowerHostId))
    lowerJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLowerJoint2Id))
    upperHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaUpperHostId))
    upperJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaUpperJoint2Id))
    transversalHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaTransversalHostId))
    transversalJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaTransversalJoint2Id))

    OdinJuliaBridge.hide_point_batch(state_ptr, [lowerHostId, upperHostId, transversalHostId])

    OdinJuliaBridge.set_point_position(state_ptr, lowerJoint2Id, LowerLineStart)
    OdinJuliaBridge.set_point_position(state_ptr, upperJoint2Id, UpperLineStart)
    OdinJuliaBridge.set_point_position(state_ptr, transversalJoint2Id, TransversalStart)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhasePenDescendLowerStart)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.hide_compass(state_ptr)
    OdinJuliaBridge.lock_pen_joint1(
        state_ptr, ToolResetOffscreenJoint1[1], ToolResetOffscreenJoint1[2],
        ToolResetOffscreenJoint1[3])
    OdinJuliaBridge.move_pen_joint2(
        state_ptr, ToolResetOffscreenJoint2[1], ToolResetOffscreenJoint2[2],
        ToolResetOffscreenJoint2[3])
    OdinJuliaBridge.lock_compass_joint1(
        state_ptr, ToolResetOffscreenJoint1[1], ToolResetOffscreenJoint1[2],
        ToolResetOffscreenJoint1[3], sweep = false)
    OdinJuliaBridge.lock_compass_joint2(
        state_ptr, ToolResetOffscreenJoint2[1], ToolResetOffscreenJoint2[2],
        ToolResetOffscreenJoint2[3], sweep = false)

    OdinJuliaBridge.set_pen_active(state_ptr, 0, LowerLineColor)
    OdinJuliaBridge.set_compass_active(state_ptr, 0, HighlightColor)
    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    lowerLine = OdinJuliaBridge.create_new_line(
        state_ptr, LowerLineStart, LowerLineStart, LowerLineColor, 0f0)
    upperLine = OdinJuliaBridge.create_new_line(
        state_ptr, UpperLineStart, UpperLineStart, UpperLineColor, 0f0)
    transversal = OdinJuliaBridge.create_new_line(
        state_ptr, TransversalStart, TransversalStart, TransversalColor, 0f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLowerHostId, Float32(lowerLine.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLowerJoint1Id, Float32(lowerLine.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLowerJoint2Id, Float32(lowerLine.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaUpperHostId, Float32(upperLine.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaUpperJoint1Id, Float32(upperLine.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaUpperJoint2Id, Float32(upperLine.joint2Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaTransversalHostId, Float32(transversal.hostId))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaTransversalJoint1Id, Float32(transversal.joint1Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaTransversalJoint2Id, Float32(transversal.joint2Id))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    lowerHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLowerHostId))
    lowerJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLowerJoint1Id))
    lowerJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLowerJoint2Id))
    upperHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaUpperHostId))
    upperJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaUpperJoint1Id))
    upperJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaUpperJoint2Id))
    transversalHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaTransversalHostId))
    transversalJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaTransversalJoint1Id))
    transversalJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaTransversalJoint2Id))

    if lowerHostId < 0 || upperHostId < 0 || transversalHostId < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhasePenDescendLowerStart
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, LowerLineStart[1], LowerLineStart[2])
        timer += dt
        if timer >= DescendDuration
            OdinJuliaBridge.set_pen_active(state_ptr, 0, LowerLineColor)
            phase = PhaseDrawLower
            timer = 0f0
        end
    elseif phase == PhaseDrawLower
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawDuration, LowerLineStart, LowerLineEnd,
            EdgeBrush, LowerLineColor, lowerHostId, lowerJoint1Id, lowerJoint2Id)
        timer += dt
        if timer >= DrawDuration
            phase = PhaseArcToUpper
            timer = 0f0
        end
    elseif phase == PhaseArcToUpper
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, LowerLineEnd, UpperLineStart, 0.24f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.set_pen_active(state_ptr, 0, UpperLineColor)
            phase = PhaseDrawUpper
            timer = 0f0
        end
    elseif phase == PhaseDrawUpper
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawDuration, UpperLineStart, UpperLineEnd,
            EdgeBrush, UpperLineColor, upperHostId, upperJoint1Id, upperJoint2Id)
        timer += dt
        if timer >= DrawDuration
            phase = PhaseArcToTransversal
            timer = 0f0
        end
    elseif phase == PhaseArcToTransversal
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, UpperLineEnd, TransversalStart, 0.24f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.set_pen_active(state_ptr, 0, TransversalColor)
            phase = PhaseDrawTransversal
            timer = 0f0
        end
    elseif phase == PhaseDrawTransversal
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawDuration, TransversalStart, TransversalEnd,
            EdgeBrush, TransversalColor,
            transversalHostId, transversalJoint1Id, transversalJoint2Id)
        timer += dt
        if timer >= DrawDuration
            phase = PhasePenRise
            timer = 0f0
        end
    elseif phase == PhasePenRise
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ, TransversalEnd[1], TransversalEnd[2])
        timer += dt
        if timer >= PenLiftDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseCompassDescendAlt1
            timer = 0f0
        end

    elseif phase == PhaseCompassDescendAlt1
        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, DescendDuration, CompassTopZ,
            TopIntersection[1], TopIntersection[2], MarkerAlt1Start[1], MarkerAlt1Start[2])
        timer += dt
        if timer >= DescendDuration
            phase = PhaseAlt1Forward
            timer = 0f0
        end
    elseif phase == PhaseAlt1Forward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, SweepDuration,
            TopIntersection, MarkerAlt1Start, AngleAlt1Theta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= SweepDuration
            phase = PhaseAlt1Back
            timer = 0f0
        end
    elseif phase == PhaseAlt1Back
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, SweepDuration,
            TopIntersection, MarkerAlt1End, -AngleAlt1Theta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= SweepDuration
            phase = PhaseArcToAlt2
            timer = 0f0
        end
    elseif phase == PhaseArcToAlt2
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            TopIntersection, BottomIntersection,
            MarkerAlt1Start, MarkerAlt2Start, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseAlt2Forward
            timer = 0f0
        end
    elseif phase == PhaseAlt2Forward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, SweepDuration,
            BottomIntersection, MarkerAlt2Start, AngleAlt2Theta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= SweepDuration
            phase = PhaseAlt2Back
            timer = 0f0
        end
    elseif phase == PhaseAlt2Back
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, SweepDuration,
            BottomIntersection, MarkerAlt2End, -AngleAlt2Theta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= SweepDuration
            phase = PhaseArcToExtInt1
            timer = 0f0
        end
    elseif phase == PhaseArcToExtInt1
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            BottomIntersection, TopIntersection,
            MarkerAlt2Start, MarkerExtInt1Start, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseExtInt1Forward
            timer = 0f0
        end
    elseif phase == PhaseExtInt1Forward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, SweepDuration,
            TopIntersection, MarkerExtInt1Start, AngleExtInt1Theta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= SweepDuration
            phase = PhaseExtInt1Back
            timer = 0f0
        end
    elseif phase == PhaseExtInt1Back
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, SweepDuration,
            TopIntersection, MarkerExtInt1End, -AngleExtInt1Theta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= SweepDuration
            phase = PhaseArcToExtInt2
            timer = 0f0
        end
    elseif phase == PhaseArcToExtInt2
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            TopIntersection, BottomIntersection,
            MarkerExtInt1Start, MarkerExtInt2Start, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseExtInt2Forward
            timer = 0f0
        end
    elseif phase == PhaseExtInt2Forward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, SweepDuration,
            BottomIntersection, MarkerExtInt2Start, AngleExtInt2Theta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= SweepDuration
            phase = PhaseExtInt2Back
            timer = 0f0
        end
    elseif phase == PhaseExtInt2Back
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, SweepDuration,
            BottomIntersection, MarkerExtInt2End, -AngleExtInt2Theta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= SweepDuration
            phase = PhaseCompassRise
            timer = 0f0
        end
    elseif phase == PhaseCompassRise
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassLiftDuration, CompassTopZ,
            BottomIntersection[1], BottomIntersection[2],
            MarkerExtInt2Start[1], MarkerExtInt2Start[2])
        timer += dt
        if timer >= CompassLiftDuration
            OdinJuliaBridge.hide_compass(state_ptr)
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

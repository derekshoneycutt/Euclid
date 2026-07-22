module HilbertChapterOneTheorem15

using ..OdinJuliaBridge
using ..EuclidAnimations

export get_view_text, initialize, clean, loop

const PointB = [0.08f0, 0.68f0, 0f0]
const PointA = [0.28f0, 0.68f0, 0f0]
const PointC = [0.50f0, 0.68f0, 0f0]
const PointD = [0.28f0, 0.92f0, 0f0]
const PointDDouble = [0.17f0, 0.82f0, 0f0]
const PointDTriple = [0.39f0, 0.82f0, 0f0]

const PointBPrime = [0.55f0, 0.22f0, 0f0]
const PointAPrime = [0.75f0, 0.22f0, 0f0]
const PointCPrime = [0.97f0, 0.22f0, 0f0]
const PointDPrime = [0.75f0, 0.46f0, 0f0]

const BaseLineStart = PointB
const BaseLineEnd = PointC
const RightRayStart = PointA
const RightRayEnd = PointD
const RightRayDoubleEnd = PointDDouble
const RightRayTripleEnd = PointDTriple

const BaseLinePrimeStart = PointBPrime
const BaseLinePrimeEnd = PointCPrime
const RightRayPrimeStart = PointAPrime
const RightRayPrimeEnd = PointDPrime

const BaseLineAMidShare = Float32((PointA[1] - PointB[1]) / (PointC[1] - PointB[1]))
const BaseLinePrimeAMidShare = Float32(
    (PointAPrime[1] - PointBPrime[1]) / (PointCPrime[1] - PointBPrime[1]))

const MarkerRadius = 0.08f0

const ThetaAB = Float32(atan(PointB[2] - PointA[2], PointB[1] - PointA[1]))
const ThetaAC = Float32(atan(PointC[2] - PointA[2], PointC[1] - PointA[1]))
const ThetaAD = Float32(atan(PointD[2] - PointA[2], PointD[1] - PointA[1]))
const ThetaADDouble = Float32(atan(
    PointDDouble[2] - PointA[2], PointDDouble[1] - PointA[1]))
const ThetaADTriple = Float32(atan(
    PointDTriple[2] - PointA[2], PointDTriple[1] - PointA[1]))

const ThetaAPrimeB = Float32(atan(
    PointBPrime[2] - PointAPrime[2], PointBPrime[1] - PointAPrime[1]))
const ThetaAPrimeC = Float32(atan(
    PointCPrime[2] - PointAPrime[2], PointCPrime[1] - PointAPrime[1]))
const ThetaAPrimeD = Float32(atan(
    PointDPrime[2] - PointAPrime[2], PointDPrime[1] - PointAPrime[1]))

const MarkerBADStart = [
    PointA[1] + MarkerRadius * Float32(cos(ThetaAB)),
    PointA[2] + MarkerRadius * Float32(sin(ThetaAB)),
    0f0,
]
const MarkerBADEnd = [
    PointA[1] + MarkerRadius * Float32(cos(ThetaAD)),
    PointA[2] + MarkerRadius * Float32(sin(ThetaAD)),
    0f0,
]
const MarkerCADStart = [
    PointA[1] + MarkerRadius * Float32(cos(ThetaAC)),
    PointA[2] + MarkerRadius * Float32(sin(ThetaAC)),
    0f0,
]
const MarkerCADEnd = MarkerBADEnd

const MarkerBPrimeADPrimeStart = [
    PointAPrime[1] + MarkerRadius * Float32(cos(ThetaAPrimeB)),
    PointAPrime[2] + MarkerRadius * Float32(sin(ThetaAPrimeB)),
    0f0,
]
const MarkerBPrimeADPrimeEnd = [
    PointAPrime[1] + MarkerRadius * Float32(cos(ThetaAPrimeD)),
    PointAPrime[2] + MarkerRadius * Float32(sin(ThetaAPrimeD)),
    0f0,
]
const MarkerCPrimeADPrimeStart = [
    PointAPrime[1] + MarkerRadius * Float32(cos(ThetaAPrimeC)),
    PointAPrime[2] + MarkerRadius * Float32(sin(ThetaAPrimeC)),
    0f0,
]
const MarkerCPrimeADPrimeEnd = MarkerBPrimeADPrimeEnd

const MarkerBADDoubleStart = MarkerBADStart
const MarkerBADDoubleEnd = [
    PointA[1] + MarkerRadius * Float32(cos(ThetaADDouble)),
    PointA[2] + MarkerRadius * Float32(sin(ThetaADDouble)),
    0f0,
]
const MarkerCADDoubleStart = MarkerCADStart
const MarkerCADDoubleEnd = MarkerBADDoubleEnd

const MarkerBADTripleStart = MarkerBADStart
const MarkerBADTripleEnd = [
    PointA[1] + MarkerRadius * Float32(cos(ThetaADTriple)),
    PointA[2] + MarkerRadius * Float32(sin(ThetaADTriple)),
    0f0,
]
const MarkerCADTripleStart = MarkerCADStart
const MarkerCADTripleEnd = MarkerBADTripleEnd

const AngleBADTheta = ThetaAD - ThetaAB
const AngleCADTheta = ThetaAD - ThetaAC
const AngleBPrimeADPrimeTheta = ThetaAPrimeD - ThetaAPrimeB
const AngleCPrimeADPrimeTheta = ThetaAPrimeD - ThetaAPrimeC
const AngleBADDoubleTheta = ThetaADDouble - ThetaAB
const AngleCADDoubleTheta = ThetaADDouble - ThetaAC
const AngleBADTripleTheta = ThetaADTriple - ThetaAB
const AngleCADTripleTheta = ThetaADTriple - ThetaAC

const LabelColor = :plum1
const HighlightColor = :lightgreen
const ContradictionColor = :firebrick
const BaseLineColor = :steelblue
const RightRayColor = :khaki3

const EdgeBrush = 5f0
const PenTopZ = 1.4f0
const CompassTopZ = 1.4f0
const ToolResetOffscreenJoint1 = [0.50f0, 1.25f0, 1.55f0]
const ToolResetOffscreenJoint2 = [0.57f0, 1.25f0, 1.55f0]

const LabelBPoint = PointB + [-0.03f0, -0.04f0, 0f0]
const LabelAPoint = PointA + [-0.01f0, -0.05f0, 0f0]
const LabelCPoint = PointC + [0.01f0, -0.04f0, 0f0]
const LabelDPoint = PointD + [0.01f0, 0.04f0, 0f0]
const LabelDDoublePoint = PointDDouble + [-0.06f0, 0.03f0, 0f0]
const LabelDTriplePoint = PointDTriple + [0.01f0, 0.03f0, 0f0]

const LabelBPrimePoint = PointBPrime + [-0.03f0, -0.04f0, 0f0]
const LabelAPrimePoint = PointAPrime + [-0.01f0, -0.05f0, 0f0]
const LabelCPrimePoint = PointCPrime + [0.01f0, -0.04f0, 0f0]
const LabelDPrimePoint = PointDPrime + [0.01f0, 0.04f0, 0f0]

const DescendDuration = 1.8f0
const DrawEdgeDuration = 2.2f0
const ArcMoveDuration = 1.35f0
const DragDuration = 1.25f0
const PenLiftDuration = 1.6f0
const CompassLiftDuration = 1.8f0
const CompassSweepDuration = 0.95f0
const FinalHoldDuration = 0.35f0

const MetaBaseLineHostId = 1
const MetaBaseLineJoint1Id = 2
const MetaBaseLineJoint2Id = 3
const MetaRightRayHostId = 11
const MetaRightRayJoint1Id = 12
const MetaRightRayJoint2Id = 13
const MetaBaseLinePrimeHostId = 21
const MetaBaseLinePrimeJoint1Id = 22
const MetaBaseLinePrimeJoint2Id = 23
const MetaRightRayPrimeHostId = 31
const MetaRightRayPrimeJoint1Id = 32
const MetaRightRayPrimeJoint2Id = 33
const MetaRightRayDoubleHostId = 41
const MetaRightRayDoubleJoint1Id = 42
const MetaRightRayDoubleJoint2Id = 43
const MetaRightRayTripleHostId = 51
const MetaRightRayTripleJoint1Id = 52
const MetaRightRayTripleJoint2Id = 53

const MetaLabelBId = 61
const MetaLabelAId = 62
const MetaLabelCId = 63
const MetaLabelDId = 64
const MetaLabelBPrimeId = 65
const MetaLabelAPrimeId = 66
const MetaLabelCPrimeId = 67
const MetaLabelDPrimeId = 68
const MetaLabelDDoubleId = 69
const MetaLabelDTripleId = 70

const MetaPhase = 101
const MetaTimer = 102

const PhaseDescendToB = 0f0
const PhaseDrawBaseLine = 1f0
const PhaseArcCToA = 2f0
const PhaseDrawRightRay = 3f0
const PhaseArcDToBPrime = 4f0
const PhaseDrawBaseLinePrime = 5f0
const PhaseArcCPrimeToAPrime = 6f0
const PhaseDrawRightRayPrime = 7f0
const PhasePenRiseBeforeGreenAngles = 8f0

const PhaseCompassDescendBAD = 9f0
const PhaseHighlightBADForward = 10f0
const PhaseHighlightBADBack = 11f0
const PhaseCompassArcBADToCAD = 12f0
const PhaseHighlightCADForward = 13f0
const PhaseHighlightCADBack = 14f0
const PhaseCompassArcCADToPrimeBAD = 15f0
const PhaseHighlightPrimeBADForward = 16f0
const PhaseHighlightPrimeBADBack = 17f0
const PhaseCompassArcPrimeBADToPrimeCAD = 18f0
const PhaseHighlightPrimeCADForward = 19f0
const PhaseHighlightPrimeCADBack = 20f0
const PhaseCompassRiseAfterGreenAngles = 21f0

const PhasePenDescendAForDouble = 22f0
const PhaseDrawRightRayDouble = 23f0
const PhasePenRiseBeforeDoubleAngles = 24f0
const PhaseCompassDescendBADDouble = 25f0
const PhaseHighlightBADDoubleForward = 26f0
const PhaseHighlightBADDoubleBack = 27f0
const PhaseCompassArcBADDoubleToPrimeBAD = 28f0
const PhaseHighlightPrimeBADFireForward = 29f0
const PhaseHighlightPrimeBADFireBack = 30f0
const PhaseCompassArcPrimeBADToCADDouble = 31f0
const PhaseHighlightCADDoubleForward = 32f0
const PhaseHighlightCADDoubleBack = 33f0
const PhaseCompassArcCADDoubleToPrimeCAD = 34f0
const PhaseHighlightPrimeCADFireForward = 35f0
const PhaseHighlightPrimeCADFireBack = 36f0
const PhaseCompassRiseAfterDoubleAngles = 37f0

const PhasePenDescendAForTriple = 38f0
const PhaseDrawRightRayTriple = 39f0
const PhasePenRiseBeforeTripleAngles = 40f0
const PhaseCompassDescendBADTriple = 41f0
const PhaseHighlightBADTripleForward = 42f0
const PhaseHighlightBADTripleBack = 43f0
const PhaseCompassArcBADTripleToPrimeBAD = 44f0
const PhaseHighlightPrimeBADFireAgainForward = 45f0
const PhaseHighlightPrimeBADFireAgainBack = 46f0
const PhaseCompassArcPrimeBADAgainToCADTriple = 47f0
const PhaseHighlightCADTripleForward = 48f0
const PhaseHighlightCADTripleBack = 49f0
const PhaseCompassArcCADTripleToPrimeCAD = 50f0
const PhaseHighlightPrimeCADFireAgainForward = 51f0
const PhaseHighlightPrimeCADFireAgainBack = 52f0
const PhaseCompassArcPrimeCADToBAD = 53f0
const PhaseHighlightBADLightForward = 54f0
const PhaseHighlightBADLightBack = 55f0
const PhaseCompassArcBADToCADAgain = 56f0
const PhaseHighlightCADLightForward = 57f0
const PhaseHighlightCADLightBack = 58f0
const PhaseCompassArcCADToPrimeBADLight = 59f0
const PhaseHighlightPrimeBADLightForward = 60f0
const PhaseHighlightPrimeBADLightBack = 61f0
const PhaseCompassArcPrimeBADLightToPrimeCADLight = 62f0
const PhaseHighlightPrimeCADLightForward = 63f0
const PhaseHighlightPrimeCADLightBack = 64f0
const PhaseCompassRiseEnd = 65f0
const PhaseFinalHold = 66f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """David Hilbert - Foundations of Geometry - Theorem 15

All right angles are congruent to one another.

Proof: Let the angle BAD be congruent to its supplementary angle CAD, and, likewise, let the angle B'A'D' be congruent to its supplementary angle C'A'D'. Hence the angles BAD, CAD, B'A'D', and C'A'D' are all right angles. We will assume that the contrary of our proposition is true, namely, that the right angle B'A'D' is not congruent to the right angle BAD, and will show that this assumption leads to a contradiction. We lay off the angle B'A'D' upon the half-ray AB in such a manner that the side AD'' arising from this operation falls either within the angle BAD or within the angle CAD. Suppose, for example, the first of these possibilities to be true. Because of the congruence of the angles B'A'D' and BAD'', it follows from theorem 12 that angle C'A'D' is congruent to angle CAD'', and, as the angles B'A'D' and C'A'D' are congruent to each other, then, by IV, 5, the angle BAD'' must be congruent to CAD''.

Furthermore, since the angle BAD is congruent to the angle CAD, it is possible, by theorem 13, to find within the angle CAD a half-ray AD''' emanating from A, so that the angle BAD'' will be congruent to the angle CAD''', and also the angle DAD'' will be congruent to the angle DAD'''. The angle BAD'' was shown to be congruent to the angle CAD'', and, hence, by axiom IV, 5, the angle CAD''' is congruent to the angle CAD''. This, however, is not possible; for, according to axiom IV, 4, an angle can be laid off in a plane upon a given side of a given half-ray in only one way. With this our proposition is demonstrated. We can now introduce, in accordance with common usage, the terms "acute angle" and "obtuse angle."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    baseLineHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaBaseLineHostId))
    baseLineJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaBaseLineJoint2Id))
    rightRayHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRightRayHostId))
    rightRayJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRightRayJoint2Id))
    baseLinePrimeHostId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaBaseLinePrimeHostId))
    baseLinePrimeJoint2Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaBaseLinePrimeJoint2Id))
    rightRayPrimeHostId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaRightRayPrimeHostId))
    rightRayPrimeJoint2Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaRightRayPrimeJoint2Id))
    rightRayDoubleHostId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaRightRayDoubleHostId))
    rightRayDoubleJoint2Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaRightRayDoubleJoint2Id))
    rightRayTripleHostId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaRightRayTripleHostId))
    rightRayTripleJoint2Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaRightRayTripleJoint2Id))

    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    labelDId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDId))
    labelBPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBPrimeId))
    labelAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAPrimeId))
    labelCPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCPrimeId))
    labelDPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDPrimeId))
    labelDDoubleId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDDoubleId))
    labelDTripleId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDTripleId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [baseLineHostId, rightRayHostId,
         baseLinePrimeHostId, rightRayPrimeHostId,
         rightRayDoubleHostId, rightRayTripleHostId,
         labelBId, labelAId, labelCId, labelDId,
         labelBPrimeId, labelAPrimeId, labelCPrimeId, labelDPrimeId,
         labelDDoubleId, labelDTripleId])

    OdinJuliaBridge.set_point_position(state_ptr, baseLineJoint2Id, BaseLineStart)
    OdinJuliaBridge.set_point_position(state_ptr, rightRayJoint2Id, RightRayStart)
    OdinJuliaBridge.set_point_position(state_ptr, baseLinePrimeJoint2Id, BaseLinePrimeStart)
    OdinJuliaBridge.set_point_position(state_ptr, rightRayPrimeJoint2Id, RightRayPrimeStart)
    OdinJuliaBridge.set_point_position(state_ptr, rightRayDoubleJoint2Id, RightRayStart)
    OdinJuliaBridge.set_point_position(state_ptr, rightRayTripleJoint2Id, RightRayStart)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescendToB)
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

    OdinJuliaBridge.set_pen_active(state_ptr, 0, BaseLineColor)
    OdinJuliaBridge.set_compass_active(state_ptr, 0, HighlightColor)
    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    baseLine = OdinJuliaBridge.create_new_line(
        state_ptr, BaseLineStart, BaseLineStart, BaseLineColor, 0f0)
    rightRay = OdinJuliaBridge.create_new_line(
        state_ptr, RightRayStart, RightRayStart, RightRayColor, 0f0)
    baseLinePrime = OdinJuliaBridge.create_new_line(
        state_ptr, BaseLinePrimeStart, BaseLinePrimeStart, BaseLineColor, 0f0)
    rightRayPrime = OdinJuliaBridge.create_new_line(
        state_ptr, RightRayPrimeStart, RightRayPrimeStart, RightRayColor, 0f0)
    rightRayDouble = OdinJuliaBridge.create_new_line(
        state_ptr, RightRayStart, RightRayStart, ContradictionColor, 0f0)
    rightRayTriple = OdinJuliaBridge.create_new_line(
        state_ptr, RightRayStart, RightRayStart, ContradictionColor, 0f0)

    labelB = OdinJuliaBridge.create_new_label(state_ptr, 'B', LabelBPoint, LabelColor, 16f0)
    labelA = OdinJuliaBridge.create_new_label(state_ptr, 'A', LabelAPoint, LabelColor, 16f0)
    labelC = OdinJuliaBridge.create_new_label(state_ptr, 'C', LabelCPoint, LabelColor, 16f0)
    labelD = OdinJuliaBridge.create_new_label(state_ptr, 'D', LabelDPoint, LabelColor, 16f0)
    labelBPrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'B', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelBPrimePoint, LabelColor, 16f0)
    labelAPrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'A', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelAPrimePoint, LabelColor, 16f0)
    labelCPrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'C', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelCPrimePoint, LabelColor, 16f0)
    labelDPrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'D', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelDPrimePoint, LabelColor, 16f0)
    labelDDouble = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'D', OdinJuliaBridge.LABEL_DECORATION_DOUBLEPRIME,
        LabelDDoublePoint, LabelColor, 16f0)
    labelDTriple = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'D', OdinJuliaBridge.LABEL_DECORATION_TRIPLEPRIME,
        LabelDTriplePoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaBaseLineHostId, Float32(baseLine.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaBaseLineJoint1Id, Float32(baseLine.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaBaseLineJoint2Id, Float32(baseLine.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRightRayHostId, Float32(rightRay.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRightRayJoint1Id, Float32(rightRay.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRightRayJoint2Id, Float32(rightRay.joint2Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaBaseLinePrimeHostId, Float32(baseLinePrime.hostId))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaBaseLinePrimeJoint1Id, Float32(baseLinePrime.joint1Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaBaseLinePrimeJoint2Id, Float32(baseLinePrime.joint2Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaRightRayPrimeHostId, Float32(rightRayPrime.hostId))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaRightRayPrimeJoint1Id, Float32(rightRayPrime.joint1Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaRightRayPrimeJoint2Id, Float32(rightRayPrime.joint2Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaRightRayDoubleHostId, Float32(rightRayDouble.hostId))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaRightRayDoubleJoint1Id, Float32(rightRayDouble.joint1Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaRightRayDoubleJoint2Id, Float32(rightRayDouble.joint2Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaRightRayTripleHostId, Float32(rightRayTriple.hostId))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaRightRayTripleJoint1Id, Float32(rightRayTriple.joint1Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaRightRayTripleJoint2Id, Float32(rightRayTriple.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBId, Float32(labelB.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAId, Float32(labelA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelCId, Float32(labelC.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelDId, Float32(labelD.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBPrimeId, Float32(labelBPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAPrimeId, Float32(labelAPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelCPrimeId, Float32(labelCPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelDPrimeId, Float32(labelDPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelDDoubleId, Float32(labelDDouble.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelDTripleId, Float32(labelDTriple.index))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    baseLineHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaBaseLineHostId))
    baseLineJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaBaseLineJoint1Id))
    baseLineJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaBaseLineJoint2Id))
    rightRayHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRightRayHostId))
    rightRayJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRightRayJoint1Id))
    rightRayJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRightRayJoint2Id))
    baseLinePrimeHostId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaBaseLinePrimeHostId))
    baseLinePrimeJoint1Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaBaseLinePrimeJoint1Id))
    baseLinePrimeJoint2Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaBaseLinePrimeJoint2Id))
    rightRayPrimeHostId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaRightRayPrimeHostId))
    rightRayPrimeJoint1Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaRightRayPrimeJoint1Id))
    rightRayPrimeJoint2Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaRightRayPrimeJoint2Id))
    rightRayDoubleHostId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaRightRayDoubleHostId))
    rightRayDoubleJoint1Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaRightRayDoubleJoint1Id))
    rightRayDoubleJoint2Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaRightRayDoubleJoint2Id))
    rightRayTripleHostId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaRightRayTripleHostId))
    rightRayTripleJoint1Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaRightRayTripleJoint1Id))
    rightRayTripleJoint2Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaRightRayTripleJoint2Id))

    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    labelDId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDId))
    labelBPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBPrimeId))
    labelAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAPrimeId))
    labelCPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCPrimeId))
    labelDPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDPrimeId))
    labelDDoubleId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDDoubleId))
    labelDTripleId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDTripleId))

    if baseLineHostId < 0 || rightRayHostId < 0 || baseLinePrimeHostId < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescendToB
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, PointB[1], PointB[2])
        timer += dt
        if timer >= DescendDuration
            OdinJuliaBridge.show_point(state_ptr, labelBId)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, BaseLineColor)
            phase = PhaseDrawBaseLine
            timer = 0f0
        end
    elseif phase == PhaseDrawBaseLine
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawEdgeDuration, BaseLineStart, BaseLineEnd,
            EdgeBrush, BaseLineColor, baseLineHostId, baseLineJoint1Id, baseLineJoint2Id)
        if timer >= DrawEdgeDuration * BaseLineAMidShare
            OdinJuliaBridge.show_point(state_ptr, labelAId)
        end
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, labelCId)
            phase = PhaseArcCToA
            timer = 0f0
        end
    elseif phase == PhaseArcCToA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointC, PointA, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.set_pen_active(state_ptr, 0, RightRayColor)
            phase = PhaseDrawRightRay
            timer = 0f0
        end
    elseif phase == PhaseDrawRightRay
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawEdgeDuration, RightRayStart, RightRayEnd,
            EdgeBrush, RightRayColor, rightRayHostId, rightRayJoint1Id, rightRayJoint2Id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, labelDId)
            phase = PhaseArcDToBPrime
            timer = 0f0
        end
    elseif phase == PhaseArcDToBPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointD, PointBPrime, 0.28f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.show_point(state_ptr, labelBPrimeId)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, BaseLineColor)
            phase = PhaseDrawBaseLinePrime
            timer = 0f0
        end
    elseif phase == PhaseDrawBaseLinePrime
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawEdgeDuration, BaseLinePrimeStart, BaseLinePrimeEnd,
            EdgeBrush, BaseLineColor,
            baseLinePrimeHostId, baseLinePrimeJoint1Id, baseLinePrimeJoint2Id)
        if timer >= DrawEdgeDuration * BaseLinePrimeAMidShare
            OdinJuliaBridge.show_point(state_ptr, labelAPrimeId)
        end
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, labelCPrimeId)
            phase = PhaseArcCPrimeToAPrime
            timer = 0f0
        end
    elseif phase == PhaseArcCPrimeToAPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointCPrime, PointAPrime, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.set_pen_active(state_ptr, 0, RightRayColor)
            phase = PhaseDrawRightRayPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawRightRayPrime
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawEdgeDuration, RightRayPrimeStart, RightRayPrimeEnd,
            EdgeBrush, RightRayColor,
            rightRayPrimeHostId, rightRayPrimeJoint1Id, rightRayPrimeJoint2Id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, labelDPrimeId)
            phase = PhasePenRiseBeforeGreenAngles
            timer = 0f0
        end
    elseif phase == PhasePenRiseBeforeGreenAngles
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ, PointDPrime[1], PointDPrime[2])
        timer += dt
        if timer >= PenLiftDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseCompassDescendBAD
            timer = 0f0
        end

    elseif phase == PhaseCompassDescendBAD
        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, DescendDuration, CompassTopZ,
            PointA[1], PointA[2], MarkerBADStart[1], MarkerBADStart[2])
        timer += dt
        if timer >= DescendDuration
            phase = PhaseHighlightBADForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightBADForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerBADStart, AngleBADTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightBADBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightBADBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerBADEnd, -AngleBADTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcBADToCAD
            timer = 0f0
        end
    elseif phase == PhaseCompassArcBADToCAD
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointA, PointA,
            MarkerBADStart, MarkerCADStart, 0.18f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightCADForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightCADForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerCADStart, AngleCADTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightCADBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightCADBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerCADEnd, -AngleCADTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcCADToPrimeBAD
            timer = 0f0
        end
    elseif phase == PhaseCompassArcCADToPrimeBAD
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointA, PointAPrime,
            MarkerCADStart, MarkerBPrimeADPrimeStart, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightPrimeBADForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightPrimeBADForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerBPrimeADPrimeStart,
            AngleBPrimeADPrimeTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightPrimeBADBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPrimeBADBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerBPrimeADPrimeEnd,
            -AngleBPrimeADPrimeTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcPrimeBADToPrimeCAD
            timer = 0f0
        end
    elseif phase == PhaseCompassArcPrimeBADToPrimeCAD
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointAPrime, PointAPrime,
            MarkerBPrimeADPrimeStart, MarkerCPrimeADPrimeStart, 0.18f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightPrimeCADForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightPrimeCADForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerCPrimeADPrimeStart,
            AngleCPrimeADPrimeTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightPrimeCADBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPrimeCADBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerCPrimeADPrimeEnd,
            -AngleCPrimeADPrimeTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassRiseAfterGreenAngles
            timer = 0f0
        end
    elseif phase == PhaseCompassRiseAfterGreenAngles
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassLiftDuration, CompassTopZ,
            PointAPrime[1], PointAPrime[2],
            MarkerCPrimeADPrimeStart[1], MarkerCPrimeADPrimeStart[2])
        timer += dt
        if timer >= CompassLiftDuration
            OdinJuliaBridge.hide_compass(state_ptr)
            phase = PhasePenDescendAForDouble
            timer = 0f0
        end

    elseif phase == PhasePenDescendAForDouble
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, PointA[1], PointA[2])
        timer += dt
        if timer >= DescendDuration
            OdinJuliaBridge.set_pen_active(state_ptr, 0, ContradictionColor)
            phase = PhaseDrawRightRayDouble
            timer = 0f0
        end
    elseif phase == PhaseDrawRightRayDouble
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawEdgeDuration, RightRayStart, RightRayDoubleEnd,
            EdgeBrush, ContradictionColor,
            rightRayDoubleHostId, rightRayDoubleJoint1Id, rightRayDoubleJoint2Id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, labelDDoubleId)
            phase = PhasePenRiseBeforeDoubleAngles
            timer = 0f0
        end
    elseif phase == PhasePenRiseBeforeDoubleAngles
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ, PointDDouble[1], PointDDouble[2])
        timer += dt
        if timer >= PenLiftDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseCompassDescendBADDouble
            timer = 0f0
        end

    elseif phase == PhaseCompassDescendBADDouble
        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, DescendDuration, CompassTopZ,
            PointA[1], PointA[2], MarkerBADDoubleStart[1], MarkerBADDoubleStart[2])
        timer += dt
        if timer >= DescendDuration
            phase = PhaseHighlightBADDoubleForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightBADDoubleForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerBADDoubleStart,
            AngleBADDoubleTheta, MarkerRadius, ContradictionColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightBADDoubleBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightBADDoubleBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerBADDoubleEnd,
            -AngleBADDoubleTheta, MarkerRadius, ContradictionColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcBADDoubleToPrimeBAD
            timer = 0f0
        end
    elseif phase == PhaseCompassArcBADDoubleToPrimeBAD
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointA, PointAPrime,
            MarkerBADDoubleStart, MarkerBPrimeADPrimeStart, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightPrimeBADFireForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightPrimeBADFireForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerBPrimeADPrimeStart,
            AngleBPrimeADPrimeTheta, MarkerRadius, ContradictionColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightPrimeBADFireBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPrimeBADFireBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerBPrimeADPrimeEnd,
            -AngleBPrimeADPrimeTheta, MarkerRadius, ContradictionColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcPrimeBADToCADDouble
            timer = 0f0
        end
    elseif phase == PhaseCompassArcPrimeBADToCADDouble
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointAPrime, PointA,
            MarkerBPrimeADPrimeStart, MarkerCADDoubleStart, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightCADDoubleForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightCADDoubleForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerCADDoubleStart,
            AngleCADDoubleTheta, MarkerRadius, ContradictionColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightCADDoubleBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightCADDoubleBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerCADDoubleEnd,
            -AngleCADDoubleTheta, MarkerRadius, ContradictionColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcCADDoubleToPrimeCAD
            timer = 0f0
        end
    elseif phase == PhaseCompassArcCADDoubleToPrimeCAD
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointA, PointAPrime,
            MarkerCADDoubleStart, MarkerCPrimeADPrimeStart, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightPrimeCADFireForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightPrimeCADFireForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerCPrimeADPrimeStart,
            AngleCPrimeADPrimeTheta, MarkerRadius, ContradictionColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightPrimeCADFireBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPrimeCADFireBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerCPrimeADPrimeEnd,
            -AngleCPrimeADPrimeTheta, MarkerRadius, ContradictionColor)
        timer += dt
        if timer >= CompassSweepDuration
            OdinJuliaBridge.hide_point_batch(state_ptr, [rightRayDoubleHostId, labelDDoubleId])
            phase = PhaseCompassRiseAfterDoubleAngles
            timer = 0f0
        end
    elseif phase == PhaseCompassRiseAfterDoubleAngles
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassLiftDuration, CompassTopZ,
            PointAPrime[1], PointAPrime[2],
            MarkerCPrimeADPrimeStart[1], MarkerCPrimeADPrimeStart[2])
        timer += dt
        if timer >= CompassLiftDuration
            OdinJuliaBridge.hide_compass(state_ptr)
            phase = PhasePenDescendAForTriple
            timer = 0f0
        end

    elseif phase == PhasePenDescendAForTriple
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, PointA[1], PointA[2])
        timer += dt
        if timer >= DescendDuration
            OdinJuliaBridge.set_pen_active(state_ptr, 0, ContradictionColor)
            phase = PhaseDrawRightRayTriple
            timer = 0f0
        end
    elseif phase == PhaseDrawRightRayTriple
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawEdgeDuration, RightRayStart, RightRayTripleEnd,
            EdgeBrush, ContradictionColor,
            rightRayTripleHostId, rightRayTripleJoint1Id, rightRayTripleJoint2Id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, labelDTripleId)
            phase = PhasePenRiseBeforeTripleAngles
            timer = 0f0
        end
    elseif phase == PhasePenRiseBeforeTripleAngles
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ, PointDTriple[1], PointDTriple[2])
        timer += dt
        if timer >= PenLiftDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseCompassDescendBADTriple
            timer = 0f0
        end

    elseif phase == PhaseCompassDescendBADTriple
        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, DescendDuration, CompassTopZ,
            PointA[1], PointA[2], MarkerBADTripleStart[1], MarkerBADTripleStart[2])
        timer += dt
        if timer >= DescendDuration
            phase = PhaseHighlightBADTripleForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightBADTripleForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerBADTripleStart,
            AngleBADTripleTheta, MarkerRadius, ContradictionColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightBADTripleBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightBADTripleBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerBADTripleEnd,
            -AngleBADTripleTheta, MarkerRadius, ContradictionColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcBADTripleToPrimeBAD
            timer = 0f0
        end
    elseif phase == PhaseCompassArcBADTripleToPrimeBAD
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointA, PointAPrime,
            MarkerBADTripleStart, MarkerBPrimeADPrimeStart, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightPrimeBADFireAgainForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightPrimeBADFireAgainForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerBPrimeADPrimeStart,
            AngleBPrimeADPrimeTheta, MarkerRadius, ContradictionColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightPrimeBADFireAgainBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPrimeBADFireAgainBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerBPrimeADPrimeEnd,
            -AngleBPrimeADPrimeTheta, MarkerRadius, ContradictionColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcPrimeBADAgainToCADTriple
            timer = 0f0
        end
    elseif phase == PhaseCompassArcPrimeBADAgainToCADTriple
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointAPrime, PointA,
            MarkerBPrimeADPrimeStart, MarkerCADTripleStart, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightCADTripleForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightCADTripleForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerCADTripleStart,
            AngleCADTripleTheta, MarkerRadius, ContradictionColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightCADTripleBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightCADTripleBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerCADTripleEnd,
            -AngleCADTripleTheta, MarkerRadius, ContradictionColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcCADTripleToPrimeCAD
            timer = 0f0
        end
    elseif phase == PhaseCompassArcCADTripleToPrimeCAD
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointA, PointAPrime,
            MarkerCADTripleStart, MarkerCPrimeADPrimeStart, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightPrimeCADFireAgainForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightPrimeCADFireAgainForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerCPrimeADPrimeStart,
            AngleCPrimeADPrimeTheta, MarkerRadius, ContradictionColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightPrimeCADFireAgainBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPrimeCADFireAgainBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerCPrimeADPrimeEnd,
            -AngleCPrimeADPrimeTheta, MarkerRadius, ContradictionColor)
        timer += dt
        if timer >= CompassSweepDuration
            OdinJuliaBridge.hide_point_batch(state_ptr, [rightRayTripleHostId, labelDTripleId])
            phase = PhaseCompassArcPrimeCADToBAD
            timer = 0f0
        end
    elseif phase == PhaseCompassArcPrimeCADToBAD
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointAPrime, PointA,
            MarkerCPrimeADPrimeStart, MarkerBADStart, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightBADLightForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightBADLightForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerBADStart, AngleBADTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightBADLightBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightBADLightBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerBADEnd, -AngleBADTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcBADToCADAgain
            timer = 0f0
        end
    elseif phase == PhaseCompassArcBADToCADAgain
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointA, PointA,
            MarkerBADStart, MarkerCADStart, 0.18f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightCADLightForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightCADLightForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerCADStart, AngleCADTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightCADLightBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightCADLightBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerCADEnd, -AngleCADTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcCADToPrimeBADLight
            timer = 0f0
        end
    elseif phase == PhaseCompassArcCADToPrimeBADLight
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointA, PointAPrime,
            MarkerCADStart, MarkerBPrimeADPrimeStart, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightPrimeBADLightForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightPrimeBADLightForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerBPrimeADPrimeStart,
            AngleBPrimeADPrimeTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightPrimeBADLightBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPrimeBADLightBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerBPrimeADPrimeEnd,
            -AngleBPrimeADPrimeTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcPrimeBADLightToPrimeCADLight
            timer = 0f0
        end
    elseif phase == PhaseCompassArcPrimeBADLightToPrimeCADLight
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointAPrime, PointAPrime,
            MarkerBPrimeADPrimeStart, MarkerCPrimeADPrimeStart, 0.18f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightPrimeCADLightForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightPrimeCADLightForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerCPrimeADPrimeStart,
            AngleCPrimeADPrimeTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightPrimeCADLightBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPrimeCADLightBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerCPrimeADPrimeEnd,
            -AngleCPrimeADPrimeTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassRiseEnd
            timer = 0f0
        end
    elseif phase == PhaseCompassRiseEnd
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassLiftDuration, CompassTopZ,
            PointAPrime[1], PointAPrime[2],
            MarkerCPrimeADPrimeStart[1], MarkerCPrimeADPrimeStart[2])
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
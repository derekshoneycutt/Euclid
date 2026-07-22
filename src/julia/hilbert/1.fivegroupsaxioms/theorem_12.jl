module HilbertChapterOneTheorem12

using ..OdinJuliaBridge
using ..EuclidAnimations

export get_view_text, initialize, clean, loop

const PointA = [0.10f0, 0.67f0, 0f0]
const PointC = [0.52f0, 0.53f0, 0f0]
const PointD = [0.48f0, 0.91f0, 0f0]

const BOnADParameter = 0.47f0
const PointB = [
    PointA[1] + BOnADParameter * (PointD[1] - PointA[1]),
    PointA[2] + BOnADParameter * (PointD[2] - PointA[2]),
    0f0,
]

const PointAPrime = [0.56f0, 0.18f0, 0f0]
const PointCPrime = [0.95f0, 0.05f0, 0f0]
const PointDPrime = [0.92f0, 0.44f0, 0f0]

const BPrimeOnAPrimeDPrimeParameter = 0.47f0
const PointBPrime = [
    PointAPrime[1] + BPrimeOnAPrimeDPrimeParameter * (PointDPrime[1] - PointAPrime[1]),
    PointAPrime[2] + BPrimeOnAPrimeDPrimeParameter * (PointDPrime[2] - PointAPrime[2]),
    0f0,
]

const EdgeACStart = PointA
const EdgeACEnd = PointC
const EdgeCDStart = PointC
const EdgeCDEnd = PointD
const EdgeDAStart = PointD
const EdgeDAEnd = PointA
const EdgeCBStart = PointC
const EdgeCBEnd = PointB

const EdgeAPrimeCPrimeStart = PointAPrime
const EdgeAPrimeCPrimeEnd = PointCPrime
const EdgeCPrimeDPrimeStart = PointCPrime
const EdgeCPrimeDPrimeEnd = PointDPrime
const EdgeDPrimeAPrimeStart = PointDPrime
const EdgeDPrimeAPrimeEnd = PointAPrime
const EdgeCPrimeBPrimeStart = PointCPrime
const EdgeCPrimeBPrimeEnd = PointBPrime

const MarkerRadius = 0.085f0

const ThetaB_BA = Float32(atan(PointA[2] - PointB[2], PointA[1] - PointB[1]))
const ThetaB_BC = Float32(atan(PointC[2] - PointB[2], PointC[1] - PointB[1]))
const ThetaB_BD = Float32(atan(PointD[2] - PointB[2], PointD[1] - PointB[1]))

const ThetaBPrime_BA = Float32(atan(PointAPrime[2] - PointBPrime[2], PointAPrime[1] - PointBPrime[1]))
const ThetaBPrime_BC = Float32(atan(PointCPrime[2] - PointBPrime[2], PointCPrime[1] - PointBPrime[1]))
const ThetaBPrime_BD = Float32(atan(PointDPrime[2] - PointBPrime[2], PointDPrime[1] - PointBPrime[1]))

const ThetaA_AB = Float32(atan(PointB[2] - PointA[2], PointB[1] - PointA[1]))
const ThetaA_AC = Float32(atan(PointC[2] - PointA[2], PointC[1] - PointA[1]))
const ThetaAPrime_AB = Float32(atan(PointBPrime[2] - PointAPrime[2], PointBPrime[1] - PointAPrime[1]))
const ThetaAPrime_AC = Float32(atan(PointCPrime[2] - PointAPrime[2], PointCPrime[1] - PointAPrime[1]))

const ThetaD_DA = Float32(atan(PointA[2] - PointD[2], PointA[1] - PointD[1]))
const ThetaD_DC = Float32(atan(PointC[2] - PointD[2], PointC[1] - PointD[1]))
const ThetaDPrime_DA = Float32(atan(PointAPrime[2] - PointDPrime[2], PointAPrime[1] - PointDPrime[1]))
const ThetaDPrime_DC = Float32(atan(PointCPrime[2] - PointDPrime[2], PointCPrime[1] - PointDPrime[1]))

const MarkerABCStart = [
    PointB[1] + MarkerRadius * Float32(cos(ThetaB_BA)),
    PointB[2] + MarkerRadius * Float32(sin(ThetaB_BA)),
    0f0,
]
const MarkerABCEnd = [
    PointB[1] + MarkerRadius * Float32(cos(ThetaB_BC)),
    PointB[2] + MarkerRadius * Float32(sin(ThetaB_BC)),
    0f0,
]
const MarkerAPrimeBPrimeCPrimeStart = [
    PointBPrime[1] + MarkerRadius * Float32(cos(ThetaBPrime_BA)),
    PointBPrime[2] + MarkerRadius * Float32(sin(ThetaBPrime_BA)),
    0f0,
]
const MarkerAPrimeBPrimeCPrimeEnd = [
    PointBPrime[1] + MarkerRadius * Float32(cos(ThetaBPrime_BC)),
    PointBPrime[2] + MarkerRadius * Float32(sin(ThetaBPrime_BC)),
    0f0,
]

const MarkerCBDStart = [
    PointB[1] + MarkerRadius * Float32(cos(ThetaB_BC)),
    PointB[2] + MarkerRadius * Float32(sin(ThetaB_BC)),
    0f0,
]
const MarkerCBDEnd = [
    PointB[1] + MarkerRadius * Float32(cos(ThetaB_BD)),
    PointB[2] + MarkerRadius * Float32(sin(ThetaB_BD)),
    0f0,
]
const MarkerCPrimeBPrimeDPrimeStart = [
    PointBPrime[1] + MarkerRadius * Float32(cos(ThetaBPrime_BC)),
    PointBPrime[2] + MarkerRadius * Float32(sin(ThetaBPrime_BC)),
    0f0,
]
const MarkerCPrimeBPrimeDPrimeEnd = [
    PointBPrime[1] + MarkerRadius * Float32(cos(ThetaBPrime_BD)),
    PointBPrime[2] + MarkerRadius * Float32(sin(ThetaBPrime_BD)),
    0f0,
]

const MarkerBACStart = [
    PointA[1] + MarkerRadius * Float32(cos(ThetaA_AB)),
    PointA[2] + MarkerRadius * Float32(sin(ThetaA_AB)),
    0f0,
]
const MarkerBACEnd = [
    PointA[1] + MarkerRadius * Float32(cos(ThetaA_AC)),
    PointA[2] + MarkerRadius * Float32(sin(ThetaA_AC)),
    0f0,
]
const MarkerBPrimeAPrimeCPrimeStart = [
    PointAPrime[1] + MarkerRadius * Float32(cos(ThetaAPrime_AB)),
    PointAPrime[2] + MarkerRadius * Float32(sin(ThetaAPrime_AB)),
    0f0,
]
const MarkerBPrimeAPrimeCPrimeEnd = [
    PointAPrime[1] + MarkerRadius * Float32(cos(ThetaAPrime_AC)),
    PointAPrime[2] + MarkerRadius * Float32(sin(ThetaAPrime_AC)),
    0f0,
]

const MarkerADCStart = [
    PointD[1] + MarkerRadius * Float32(cos(ThetaD_DA)),
    PointD[2] + MarkerRadius * Float32(sin(ThetaD_DA)),
    0f0,
]
const MarkerADCEnd = [
    PointD[1] + MarkerRadius * Float32(cos(ThetaD_DC)),
    PointD[2] + MarkerRadius * Float32(sin(ThetaD_DC)),
    0f0,
]
const MarkerAPrimeDPrimeCPrimeStart = [
    PointDPrime[1] + MarkerRadius * Float32(cos(ThetaDPrime_DA)),
    PointDPrime[2] + MarkerRadius * Float32(sin(ThetaDPrime_DA)),
    0f0,
]
const MarkerAPrimeDPrimeCPrimeEnd = [
    PointDPrime[1] + MarkerRadius * Float32(cos(ThetaDPrime_DC)),
    PointDPrime[2] + MarkerRadius * Float32(sin(ThetaDPrime_DC)),
    0f0,
]

const AngleABCTheta = ThetaB_BC - ThetaB_BA
const AngleAPrimeBPrimeCPrimeTheta = ThetaBPrime_BC - ThetaBPrime_BA
const AngleCBDTheta = ThetaB_BD - ThetaB_BC
const AngleCPrimeBPrimeDPrimeTheta = ThetaBPrime_BD - ThetaBPrime_BC
const AngleBACTheta = ThetaA_AC - ThetaA_AB
const AngleBPrimeAPrimeCPrimeTheta = ThetaAPrime_AC - ThetaAPrime_AB
const AngleADCTheta = ThetaD_DC - ThetaD_DA
const AngleAPrimeDPrimeCPrimeTheta = ThetaDPrime_DC - ThetaDPrime_DA

const LabelColor = :plum1
const HighlightColor = :lightgreen
const MarkerPaleColor = :palevioletred1
const MarkerSteelColor = :steelblue

const EdgeACColor = :steelblue
const EdgeCDColor = :palevioletred1
const EdgeDAColor = :khaki3
const EdgeCBColor = :grey60

const EdgeAPrimeCPrimeColor = :steelblue
const EdgeCPrimeDPrimeColor = :palevioletred1
const EdgeDPrimeAPrimeColor = :khaki3
const EdgeCPrimeBPrimeColor = :grey60

const EdgeBrush = 5f0
const MarkerBrush = 3.2f0
const PenTopZ = 1.4f0
const CompassTopZ = 1.4f0
const ToolResetOffscreenJoint1 = [0.50f0, 1.25f0, 1.55f0]
const ToolResetOffscreenJoint2 = [0.57f0, 1.25f0, 1.55f0]

const LabelAPoint = PointA + [-0.04f0, -0.04f0, 0f0]
const LabelBPoint = PointB + [-0.015f0, 0.035f0, 0f0]
const LabelCPoint = PointC + [0.01f0, -0.02f0, 0f0]
const LabelDPoint = PointD + [0.01f0, 0.04f0, 0f0]

const LabelAPrimePoint = PointAPrime + [-0.04f0, -0.04f0, 0f0]
const LabelBPrimePoint = PointBPrime + [-0.015f0, 0.035f0, 0f0]
const LabelCPrimePoint = PointCPrime + [0.01f0, -0.02f0, 0f0]
const LabelDPrimePoint = PointDPrime + [0.01f0, 0.04f0, 0f0]

const DescendDuration = 1.8f0
const DrawEdgeDuration = 2.2f0
const ArcMoveDuration = 1.35f0
const DragDuration = 1.25f0
const PenLiftDuration = 1.6f0
const CompassLiftDuration = 1.8f0
const CompassSweepDuration = 0.95f0
const FinalHoldDuration = 0.35f0

const MetaEdgeACHostId = 1
const MetaEdgeACJoint1Id = 2
const MetaEdgeACJoint2Id = 3
const MetaEdgeCDHostId = 11
const MetaEdgeCDJoint1Id = 12
const MetaEdgeCDJoint2Id = 13
const MetaEdgeDAHostId = 21
const MetaEdgeDAJoint1Id = 22
const MetaEdgeDAJoint2Id = 23
const MetaEdgeCBHostId = 31
const MetaEdgeCBJoint1Id = 32
const MetaEdgeCBJoint2Id = 33

const MetaEdgeAPrimeCPrimeHostId = 41
const MetaEdgeAPrimeCPrimeJoint1Id = 42
const MetaEdgeAPrimeCPrimeJoint2Id = 43
const MetaEdgeCPrimeDPrimeHostId = 51
const MetaEdgeCPrimeDPrimeJoint1Id = 52
const MetaEdgeCPrimeDPrimeJoint2Id = 53
const MetaEdgeDPrimeAPrimeHostId = 61
const MetaEdgeDPrimeAPrimeJoint1Id = 62
const MetaEdgeDPrimeAPrimeJoint2Id = 63
const MetaEdgeCPrimeBPrimeHostId = 71
const MetaEdgeCPrimeBPrimeJoint1Id = 72
const MetaEdgeCPrimeBPrimeJoint2Id = 73

const MetaLabelAId = 81
const MetaLabelBId = 82
const MetaLabelCId = 83
const MetaLabelDId = 84
const MetaLabelAPrimeId = 85
const MetaLabelBPrimeId = 86
const MetaLabelCPrimeId = 87
const MetaLabelDPrimeId = 88

const MetaMarkerABCHostId = 91
const MetaMarkerABCStartId = 92
const MetaMarkerABCEndId = 93
const MetaMarkerAPrimeBPrimeCPrimeHostId = 94
const MetaMarkerAPrimeBPrimeCPrimeStartId = 95
const MetaMarkerAPrimeBPrimeCPrimeEndId = 96
const MetaMarkerCBDHostId = 97
const MetaMarkerCBDStartId = 98
const MetaMarkerCBDEndId = 99
const MetaMarkerCPrimeBPrimeDPrimeHostId = 100
const MetaMarkerCPrimeBPrimeDPrimeStartId = 103
const MetaMarkerCPrimeBPrimeDPrimeEndId = 104

const MetaPhase = 101
const MetaTimer = 102

const PhaseDescendToA = 0f0
const PhaseDrawAC = 1f0
const PhaseDrawCD = 2f0
const PhaseDrawDA = 3f0
const PhaseArcAToC = 4f0
const PhaseDrawCB = 5f0
const PhaseArcCToAPrime = 6f0
const PhaseDrawAPrimeCPrime = 7f0
const PhaseDrawCPrimeDPrime = 8f0
const PhaseDrawDPrimeAPrime = 9f0
const PhaseArcAPrimeToCPrime = 10f0
const PhaseDrawCPrimeBPrime = 11f0
const PhasePenRiseBeforeMarkers = 12f0

const PhaseCompassDescendABC = 13f0
const PhaseMarkerABC = 14f0
const PhaseCompassArcABCToAPrimeBPrimeCPrime = 15f0
const PhaseMarkerAPrimeBPrimeCPrime = 16f0
const PhaseCompassArcAPrimeBPrimeCPrimeToCBD = 17f0
const PhaseMarkerCBD = 18f0
const PhaseCompassArcCBDToCPrimeBPrimeDPrime = 19f0
const PhaseMarkerCPrimeBPrimeDPrime = 20f0
const PhaseCompassRiseAfterMarkers = 21f0

const PhasePenDescendAForAB = 22f0
const PhaseDragABForward = 23f0
const PhaseDragABBack = 24f0
const PhaseArcAToAPrimeForAB = 25f0
const PhaseDragAPrimeBPrimeForward = 26f0
const PhaseDragAPrimeBPrimeBack = 27f0
const PhaseArcAPrimeToCForCB = 28f0
const PhaseDragCBForward = 29f0
const PhaseDragCBBack = 30f0
const PhaseArcCToCPrimeForCPrimeBPrime = 31f0
const PhaseDragCPrimeBPrimeForward = 32f0
const PhaseDragCPrimeBPrimeBack = 33f0
const PhaseArcCPrimeToDForDB = 34f0
const PhaseDragDBForward = 35f0
const PhaseDragDBBack = 36f0
const PhaseArcDToDPrimeForDPrimeBPrime = 37f0
const PhaseDragDPrimeBPrimeForward = 38f0
const PhaseDragDPrimeBPrimeBack = 39f0
const PhaseArcDPrimeToAForAC = 40f0
const PhaseDragACForward = 41f0
const PhaseDragACBack = 42f0
const PhaseArcAToAPrimeForAPrimeCPrime = 43f0
const PhaseDragAPrimeCPrimeForward = 44f0
const PhaseDragAPrimeCPrimeBack = 45f0
const PhasePenRiseBeforeBAC = 46f0

const PhaseCompassDescendBAC = 47f0
const PhaseHighlightBACForward = 48f0
const PhaseHighlightBACBack = 49f0
const PhaseCompassArcBACToBPrimeAPrimeCPrime = 50f0
const PhaseHighlightBPrimeAPrimeCPrimeForward = 51f0
const PhaseHighlightBPrimeAPrimeCPrimeBack = 52f0
const PhaseCompassRiseAfterBAC = 53f0

const PhasePenDescendAForAD = 54f0
const PhaseDragADForward = 55f0
const PhaseDragADBack = 56f0
const PhaseArcAToAPrimeForAPrimeDPrime = 57f0
const PhaseDragAPrimeDPrimeForward = 58f0
const PhaseDragAPrimeDPrimeBack = 59f0
const PhaseArcAPrimeToCForCD = 60f0
const PhaseDragCDForward = 61f0
const PhaseDragCDBack = 62f0
const PhaseArcCToCPrimeForCPrimeDPrime = 63f0
const PhaseDragCPrimeDPrimeForward = 64f0
const PhaseDragCPrimeDPrimeBack = 65f0
const PhasePenRiseBeforeFinalAngles = 66f0

const PhaseCompassDescendADC = 67f0
const PhaseHighlightADCForward = 68f0
const PhaseHighlightADCBack = 69f0
const PhaseCompassArcADCToAPrimeDPrimeCPrime = 70f0
const PhaseHighlightAPrimeDPrimeCPrimeForward = 71f0
const PhaseHighlightAPrimeDPrimeCPrimeBack = 72f0
const PhaseCompassArcAPrimeDPrimeCPrimeToCBD = 73f0
const PhaseHighlightCBDAgainForward = 74f0
const PhaseHighlightCBDAgainBack = 75f0
const PhaseCompassArcCBDToCPrimeBPrimeDPrimeFinal = 76f0
const PhaseHighlightCPrimeBPrimeDPrimeAgainForward = 77f0
const PhaseHighlightCPrimeBPrimeDPrimeAgainBack = 78f0
const PhaseCompassRiseEnd = 79f0
const PhaseFinalHold = 80f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """David Hilbert - Foundations of Geometry - Theorem 12

If two angles ABC and A'B'C' are congruent to each other, their supplementary angles CBD and C'B'D' are also congruent.

Proof: Take the points A', C', D' upon the sides passing through B' in such a way that

    A'B' ≡ AB, C'B' ≡ CB, D'B' ≡ DB.

Then, in the two triangles ABC and A'B'C', the sides AB and BC are respectively congruent to A'B' and C'B'. Moreover, since the angles included by these sides are congruent to each other by hypothesis, it follows from theorem 10 that these triangles are congruent; that is to say, we have the congruences

    AC ≡ A'C', ∠BAC ≡ ∠B'A'C'.

On the other hand, since by axiom IV, 3 the segments AD and A'D' are congruent to each other, it follows again from theorem 10 that the triangles CAD and C'A'D' are congruent, and, consequently, we have the congruences:

    CD ≡ C'D', ∠ADC ≡ ∠A'D'C'.

From these congruences and the consideration of the triangles BCD and B'C'D', it follows by virtue of axiom IV, 6 that the angles CBD and C'B'D' are congruent."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    edgeACHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeACHostId))
    edgeACJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeACJoint2Id))
    edgeCDHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCDHostId))
    edgeCDJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCDJoint2Id))
    edgeDAHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeDAHostId))
    edgeDAJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeDAJoint2Id))
    edgeCBHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCBHostId))
    edgeCBJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCBJoint2Id))

    edgeAPrimeCPrimeHostId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPrimeCPrimeHostId))
    edgeAPrimeCPrimeJoint2Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPrimeCPrimeJoint2Id))
    edgeCPrimeDPrimeHostId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCPrimeDPrimeHostId))
    edgeCPrimeDPrimeJoint2Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCPrimeDPrimeJoint2Id))
    edgeDPrimeAPrimeHostId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeDPrimeAPrimeHostId))
    edgeDPrimeAPrimeJoint2Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeDPrimeAPrimeJoint2Id))
    edgeCPrimeBPrimeHostId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCPrimeBPrimeHostId))
    edgeCPrimeBPrimeJoint2Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCPrimeBPrimeJoint2Id))

    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labelCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    labelDId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDId))
    labelAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAPrimeId))
    labelBPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBPrimeId))
    labelCPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCPrimeId))
    labelDPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDPrimeId))

    markerABCHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerABCHostId))
    markerABCEndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerABCEndId))
    markerAPrimeBPrimeCPrimeHostId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerAPrimeBPrimeCPrimeHostId))
    markerAPrimeBPrimeCPrimeEndId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerAPrimeBPrimeCPrimeEndId))
    markerCBDHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerCBDHostId))
    markerCBDEndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerCBDEndId))
    markerCPrimeBPrimeDPrimeHostId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerCPrimeBPrimeDPrimeHostId))
    markerCPrimeBPrimeDPrimeEndId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerCPrimeBPrimeDPrimeEndId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [edgeACHostId, edgeCDHostId, edgeDAHostId, edgeCBHostId,
         edgeAPrimeCPrimeHostId, edgeCPrimeDPrimeHostId,
         edgeDPrimeAPrimeHostId, edgeCPrimeBPrimeHostId,
         markerABCHostId, markerAPrimeBPrimeCPrimeHostId,
         markerCBDHostId, markerCPrimeBPrimeDPrimeHostId,
         labelAId, labelBId, labelCId, labelDId,
         labelAPrimeId, labelBPrimeId, labelCPrimeId, labelDPrimeId])

    OdinJuliaBridge.set_point_position(state_ptr, edgeACJoint2Id, EdgeACStart)
    OdinJuliaBridge.set_point_position(state_ptr, edgeCDJoint2Id, EdgeCDStart)
    OdinJuliaBridge.set_point_position(state_ptr, edgeDAJoint2Id, EdgeDAStart)
    OdinJuliaBridge.set_point_position(state_ptr, edgeCBJoint2Id, EdgeCBStart)
    OdinJuliaBridge.set_point_position(state_ptr, edgeAPrimeCPrimeJoint2Id, EdgeAPrimeCPrimeStart)
    OdinJuliaBridge.set_point_position(state_ptr, edgeCPrimeDPrimeJoint2Id, EdgeCPrimeDPrimeStart)
    OdinJuliaBridge.set_point_position(state_ptr, edgeDPrimeAPrimeJoint2Id, EdgeDPrimeAPrimeStart)
    OdinJuliaBridge.set_point_position(state_ptr, edgeCPrimeBPrimeJoint2Id, EdgeCPrimeBPrimeStart)

    OdinJuliaBridge.set_point_position(state_ptr, markerABCEndId, MarkerABCStart)
    OdinJuliaBridge.set_point_position(
        state_ptr, markerAPrimeBPrimeCPrimeEndId, MarkerAPrimeBPrimeCPrimeStart)
    OdinJuliaBridge.set_point_position(state_ptr, markerCBDEndId, MarkerCBDStart)
    OdinJuliaBridge.set_point_position(
        state_ptr, markerCPrimeBPrimeDPrimeEndId, MarkerCPrimeBPrimeDPrimeStart)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescendToA)
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

    OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeACColor)
    OdinJuliaBridge.set_compass_active(state_ptr, 0, HighlightColor)
    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    edgeAC = OdinJuliaBridge.create_new_line(state_ptr, EdgeACStart, EdgeACStart, EdgeACColor, 0f0)
    edgeCD = OdinJuliaBridge.create_new_line(state_ptr, EdgeCDStart, EdgeCDStart, EdgeCDColor, 0f0)
    edgeDA = OdinJuliaBridge.create_new_line(state_ptr, EdgeDAStart, EdgeDAStart, EdgeDAColor, 0f0)
    edgeCB = OdinJuliaBridge.create_new_line(state_ptr, EdgeCBStart, EdgeCBStart, EdgeCBColor, 0f0)

    edgeAPrimeCPrime = OdinJuliaBridge.create_new_line(
        state_ptr, EdgeAPrimeCPrimeStart, EdgeAPrimeCPrimeStart, EdgeAPrimeCPrimeColor, 0f0)
    edgeCPrimeDPrime = OdinJuliaBridge.create_new_line(
        state_ptr, EdgeCPrimeDPrimeStart, EdgeCPrimeDPrimeStart, EdgeCPrimeDPrimeColor, 0f0)
    edgeDPrimeAPrime = OdinJuliaBridge.create_new_line(
        state_ptr, EdgeDPrimeAPrimeStart, EdgeDPrimeAPrimeStart, EdgeDPrimeAPrimeColor, 0f0)
    edgeCPrimeBPrime = OdinJuliaBridge.create_new_line(
        state_ptr, EdgeCPrimeBPrimeStart, EdgeCPrimeBPrimeStart, EdgeCPrimeBPrimeColor, 0f0)

    markerABC = OdinJuliaBridge.create_new_filledcircle(
        state_ptr, PointB[1], PointB[2], PointB[3],
        MarkerRadius, 0f0, 0f0, MarkerPaleColor, 0f0)
    markerAPrimeBPrimeCPrime = OdinJuliaBridge.create_new_filledcircle(
        state_ptr, PointBPrime[1], PointBPrime[2], PointBPrime[3],
        MarkerRadius, 0f0, 0f0, MarkerPaleColor, 0f0)
    markerCBD = OdinJuliaBridge.create_new_filledcircle(
        state_ptr, PointB[1], PointB[2], PointB[3],
        MarkerRadius, 0f0, 0f0, MarkerSteelColor, 0f0)
    markerCPrimeBPrimeDPrime = OdinJuliaBridge.create_new_filledcircle(
        state_ptr, PointBPrime[1], PointBPrime[2], PointBPrime[3],
        MarkerRadius, 0f0, 0f0, MarkerSteelColor, 0f0)

    labelA = OdinJuliaBridge.create_new_label(state_ptr, 'A', LabelAPoint, LabelColor, 16f0)
    labelB = OdinJuliaBridge.create_new_label(state_ptr, 'B', LabelBPoint, LabelColor, 16f0)
    labelC = OdinJuliaBridge.create_new_label(state_ptr, 'C', LabelCPoint, LabelColor, 16f0)
    labelD = OdinJuliaBridge.create_new_label(state_ptr, 'D', LabelDPoint, LabelColor, 16f0)

    labelAPrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'A', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelAPrimePoint, LabelColor, 16f0)
    labelBPrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'B', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelBPrimePoint, LabelColor, 16f0)
    labelCPrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'C', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelCPrimePoint, LabelColor, 16f0)
    labelDPrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'D', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelDPrimePoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeACHostId, Float32(edgeAC.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeACJoint1Id, Float32(edgeAC.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeACJoint2Id, Float32(edgeAC.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeCDHostId, Float32(edgeCD.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeCDJoint1Id, Float32(edgeCD.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeCDJoint2Id, Float32(edgeCD.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeDAHostId, Float32(edgeDA.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeDAJoint1Id, Float32(edgeDA.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeDAJoint2Id, Float32(edgeDA.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeCBHostId, Float32(edgeCB.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeCBJoint1Id, Float32(edgeCB.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeCBJoint2Id, Float32(edgeCB.joint2Id))

    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeAPrimeCPrimeHostId, Float32(edgeAPrimeCPrime.hostId))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeAPrimeCPrimeJoint1Id, Float32(edgeAPrimeCPrime.joint1Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeAPrimeCPrimeJoint2Id, Float32(edgeAPrimeCPrime.joint2Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeCPrimeDPrimeHostId, Float32(edgeCPrimeDPrime.hostId))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeCPrimeDPrimeJoint1Id, Float32(edgeCPrimeDPrime.joint1Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeCPrimeDPrimeJoint2Id, Float32(edgeCPrimeDPrime.joint2Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeDPrimeAPrimeHostId, Float32(edgeDPrimeAPrime.hostId))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeDPrimeAPrimeJoint1Id, Float32(edgeDPrimeAPrime.joint1Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeDPrimeAPrimeJoint2Id, Float32(edgeDPrimeAPrime.joint2Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeCPrimeBPrimeHostId, Float32(edgeCPrimeBPrime.hostId))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeCPrimeBPrimeJoint1Id, Float32(edgeCPrimeBPrime.joint1Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeCPrimeBPrimeJoint2Id, Float32(edgeCPrimeBPrime.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarkerABCHostId, Float32(markerABC.hostId))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaMarkerABCStartId, Float32(markerABC.startId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarkerABCEndId, Float32(markerABC.endId))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaMarkerAPrimeBPrimeCPrimeHostId,
        Float32(markerAPrimeBPrimeCPrime.hostId))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaMarkerAPrimeBPrimeCPrimeStartId,
        Float32(markerAPrimeBPrimeCPrime.startId))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaMarkerAPrimeBPrimeCPrimeEndId,
        Float32(markerAPrimeBPrimeCPrime.endId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarkerCBDHostId, Float32(markerCBD.hostId))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaMarkerCBDStartId, Float32(markerCBD.startId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarkerCBDEndId, Float32(markerCBD.endId))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaMarkerCPrimeBPrimeDPrimeHostId,
        Float32(markerCPrimeBPrimeDPrime.hostId))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaMarkerCPrimeBPrimeDPrimeStartId,
        Float32(markerCPrimeBPrimeDPrime.startId))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaMarkerCPrimeBPrimeDPrimeEndId,
        Float32(markerCPrimeBPrimeDPrime.endId))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAId, Float32(labelA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBId, Float32(labelB.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelCId, Float32(labelC.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelDId, Float32(labelD.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAPrimeId, Float32(labelAPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBPrimeId, Float32(labelBPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelCPrimeId, Float32(labelCPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelDPrimeId, Float32(labelDPrime.index))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    edgeACHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeACHostId))
    edgeACJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeACJoint1Id))
    edgeACJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeACJoint2Id))
    edgeCDHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCDHostId))
    edgeCDJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCDJoint1Id))
    edgeCDJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCDJoint2Id))
    edgeDAHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeDAHostId))
    edgeDAJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeDAJoint1Id))
    edgeDAJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeDAJoint2Id))
    edgeCBHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCBHostId))
    edgeCBJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCBJoint1Id))
    edgeCBJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCBJoint2Id))

    edgeAPrimeCPrimeHostId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPrimeCPrimeHostId))
    edgeAPrimeCPrimeJoint1Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPrimeCPrimeJoint1Id))
    edgeAPrimeCPrimeJoint2Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPrimeCPrimeJoint2Id))
    edgeCPrimeDPrimeHostId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCPrimeDPrimeHostId))
    edgeCPrimeDPrimeJoint1Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCPrimeDPrimeJoint1Id))
    edgeCPrimeDPrimeJoint2Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCPrimeDPrimeJoint2Id))
    edgeDPrimeAPrimeHostId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeDPrimeAPrimeHostId))
    edgeDPrimeAPrimeJoint1Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeDPrimeAPrimeJoint1Id))
    edgeDPrimeAPrimeJoint2Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeDPrimeAPrimeJoint2Id))
    edgeCPrimeBPrimeHostId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCPrimeBPrimeHostId))
    edgeCPrimeBPrimeJoint1Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCPrimeBPrimeJoint1Id))
    edgeCPrimeBPrimeJoint2Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCPrimeBPrimeJoint2Id))

    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labelCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    labelDId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDId))
    labelAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAPrimeId))
    labelBPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBPrimeId))
    labelCPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCPrimeId))
    labelDPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDPrimeId))

    markerABCHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerABCHostId))
    markerABCStartId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerABCStartId))
    markerABCEndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerABCEndId))
    markerAPrimeBPrimeCPrimeHostId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerAPrimeBPrimeCPrimeHostId))
    markerAPrimeBPrimeCPrimeStartId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerAPrimeBPrimeCPrimeStartId))
    markerAPrimeBPrimeCPrimeEndId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerAPrimeBPrimeCPrimeEndId))
    markerCBDHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerCBDHostId))
    markerCBDStartId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerCBDStartId))
    markerCBDEndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerCBDEndId))
    markerCPrimeBPrimeDPrimeHostId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerCPrimeBPrimeDPrimeHostId))
    markerCPrimeBPrimeDPrimeStartId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerCPrimeBPrimeDPrimeStartId))
    markerCPrimeBPrimeDPrimeEndId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerCPrimeBPrimeDPrimeEndId))

    if edgeACHostId < 0 || edgeCDHostId < 0 || edgeDAHostId < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescendToA
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, PointA[1], PointA[2])
        timer += dt
        if timer >= DescendDuration
            OdinJuliaBridge.show_point(state_ptr, labelAId)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeACColor)
            phase = PhaseDrawAC
            timer = 0f0
        end
    elseif phase == PhaseDrawAC
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawEdgeDuration, EdgeACStart, EdgeACEnd,
            EdgeBrush, EdgeACColor, edgeACHostId, edgeACJoint1Id, edgeACJoint2Id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, labelCId)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeCDColor)
            phase = PhaseDrawCD
            timer = 0f0
        end
    elseif phase == PhaseDrawCD
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawEdgeDuration, EdgeCDStart, EdgeCDEnd,
            EdgeBrush, EdgeCDColor, edgeCDHostId, edgeCDJoint1Id, edgeCDJoint2Id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, labelDId)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeDAColor)
            phase = PhaseDrawDA
            timer = 0f0
        end
    elseif phase == PhaseDrawDA
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawEdgeDuration, EdgeDAStart, EdgeDAEnd,
            EdgeBrush, EdgeDAColor, edgeDAHostId, edgeDAJoint1Id, edgeDAJoint2Id)
        timer += dt
        if timer >= DrawEdgeDuration
            phase = PhaseArcAToC
            timer = 0f0
        end
    elseif phase == PhaseArcAToC
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointA, PointC, 0.23f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeCBColor)
            phase = PhaseDrawCB
            timer = 0f0
        end
    elseif phase == PhaseDrawCB
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawEdgeDuration, EdgeCBStart, EdgeCBEnd,
            EdgeBrush, EdgeCBColor, edgeCBHostId, edgeCBJoint1Id, edgeCBJoint2Id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, labelBId)
            phase = PhaseArcCToAPrime
            timer = 0f0
        end
    elseif phase == PhaseArcCToAPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointB, PointAPrime, 0.27f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.show_point(state_ptr, labelAPrimeId)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeAPrimeCPrimeColor)
            phase = PhaseDrawAPrimeCPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawAPrimeCPrime
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawEdgeDuration, EdgeAPrimeCPrimeStart, EdgeAPrimeCPrimeEnd,
            EdgeBrush, EdgeAPrimeCPrimeColor,
            edgeAPrimeCPrimeHostId, edgeAPrimeCPrimeJoint1Id, edgeAPrimeCPrimeJoint2Id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, labelCPrimeId)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeCPrimeDPrimeColor)
            phase = PhaseDrawCPrimeDPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawCPrimeDPrime
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawEdgeDuration, EdgeCPrimeDPrimeStart, EdgeCPrimeDPrimeEnd,
            EdgeBrush, EdgeCPrimeDPrimeColor,
            edgeCPrimeDPrimeHostId, edgeCPrimeDPrimeJoint1Id, edgeCPrimeDPrimeJoint2Id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, labelDPrimeId)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeDPrimeAPrimeColor)
            phase = PhaseDrawDPrimeAPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawDPrimeAPrime
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawEdgeDuration, EdgeDPrimeAPrimeStart, EdgeDPrimeAPrimeEnd,
            EdgeBrush, EdgeDPrimeAPrimeColor,
            edgeDPrimeAPrimeHostId, edgeDPrimeAPrimeJoint1Id, edgeDPrimeAPrimeJoint2Id)
        timer += dt
        if timer >= DrawEdgeDuration
            phase = PhaseArcAPrimeToCPrime
            timer = 0f0
        end
    elseif phase == PhaseArcAPrimeToCPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointAPrime, PointCPrime, 0.23f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeCPrimeBPrimeColor)
            phase = PhaseDrawCPrimeBPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawCPrimeBPrime
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawEdgeDuration, EdgeCPrimeBPrimeStart, EdgeCPrimeBPrimeEnd,
            EdgeBrush, EdgeCPrimeBPrimeColor,
            edgeCPrimeBPrimeHostId, edgeCPrimeBPrimeJoint1Id, edgeCPrimeBPrimeJoint2Id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, labelBPrimeId)
            phase = PhasePenRiseBeforeMarkers
            timer = 0f0
        end
    elseif phase == PhasePenRiseBeforeMarkers
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ, PointBPrime[1], PointBPrime[2])
        timer += dt
        if timer >= PenLiftDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseCompassDescendABC
            timer = 0f0
        end

    elseif phase == PhaseCompassDescendABC
        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, DescendDuration, CompassTopZ,
            PointB[1], PointB[2], MarkerABCStart[1], MarkerABCStart[2])
        timer += dt
        if timer >= DescendDuration
            phase = PhaseMarkerABC
            timer = 0f0
        end
    elseif phase == PhaseMarkerABC
        EuclidAnimations.animate_draw_filledcircle(
            state_ptr, timer, CompassSweepDuration,
            PointB, MarkerABCStart, AngleABCTheta,
            MarkerRadius, MarkerBrush, MarkerPaleColor,
            markerABCHostId, markerABCStartId, markerABCEndId)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcABCToAPrimeBPrimeCPrime
            timer = 0f0
        end
    elseif phase == PhaseCompassArcABCToAPrimeBPrimeCPrime
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointB, PointBPrime,
            MarkerABCEnd, MarkerAPrimeBPrimeCPrimeStart, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseMarkerAPrimeBPrimeCPrime
            timer = 0f0
        end
    elseif phase == PhaseMarkerAPrimeBPrimeCPrime
        EuclidAnimations.animate_draw_filledcircle(
            state_ptr, timer, CompassSweepDuration,
            PointBPrime, MarkerAPrimeBPrimeCPrimeStart,
            AngleAPrimeBPrimeCPrimeTheta,
            MarkerRadius, MarkerBrush, MarkerPaleColor,
            markerAPrimeBPrimeCPrimeHostId,
            markerAPrimeBPrimeCPrimeStartId,
            markerAPrimeBPrimeCPrimeEndId)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcAPrimeBPrimeCPrimeToCBD
            timer = 0f0
        end
    elseif phase == PhaseCompassArcAPrimeBPrimeCPrimeToCBD
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointBPrime, PointB,
            MarkerAPrimeBPrimeCPrimeEnd, MarkerCBDStart, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseMarkerCBD
            timer = 0f0
        end
    elseif phase == PhaseMarkerCBD
        EuclidAnimations.animate_draw_filledcircle(
            state_ptr, timer, CompassSweepDuration,
            PointB, MarkerCBDStart, AngleCBDTheta,
            MarkerRadius, MarkerBrush, MarkerSteelColor,
            markerCBDHostId, markerCBDStartId, markerCBDEndId)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcCBDToCPrimeBPrimeDPrime
            timer = 0f0
        end
    elseif phase == PhaseCompassArcCBDToCPrimeBPrimeDPrime
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointB, PointBPrime,
            MarkerCBDEnd, MarkerCPrimeBPrimeDPrimeStart, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseMarkerCPrimeBPrimeDPrime
            timer = 0f0
        end
    elseif phase == PhaseMarkerCPrimeBPrimeDPrime
        EuclidAnimations.animate_draw_filledcircle(
            state_ptr, timer, CompassSweepDuration,
            PointBPrime, MarkerCPrimeBPrimeDPrimeStart,
            AngleCPrimeBPrimeDPrimeTheta,
            MarkerRadius, MarkerBrush, MarkerSteelColor,
            markerCPrimeBPrimeDPrimeHostId,
            markerCPrimeBPrimeDPrimeStartId,
            markerCPrimeBPrimeDPrimeEndId)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassRiseAfterMarkers
            timer = 0f0
        end
    elseif phase == PhaseCompassRiseAfterMarkers
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassLiftDuration, CompassTopZ,
            PointBPrime[1], PointBPrime[2],
            MarkerCPrimeBPrimeDPrimeStart[1], MarkerCPrimeBPrimeDPrimeStart[2])
        timer += dt
        if timer >= CompassLiftDuration
            OdinJuliaBridge.hide_compass(state_ptr)
            phase = PhasePenDescendAForAB
            timer = 0f0
        end

    elseif phase == PhasePenDescendAForAB
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, PointA[1], PointA[2])
        timer += dt
        if timer >= DescendDuration
            phase = PhaseDragABForward
            timer = 0f0
        end
    elseif phase == PhaseDragABForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointA, PointB, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseDragABBack
            timer = 0f0
        end
    elseif phase == PhaseDragABBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointB, PointA, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseArcAToAPrimeForAB
            timer = 0f0
        end
    elseif phase == PhaseArcAToAPrimeForAB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointA, PointAPrime, 0.24f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragAPrimeBPrimeForward
            timer = 0f0
        end
    elseif phase == PhaseDragAPrimeBPrimeForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointAPrime, PointBPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseDragAPrimeBPrimeBack
            timer = 0f0
        end
    elseif phase == PhaseDragAPrimeBPrimeBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointBPrime, PointAPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseArcAPrimeToCForCB
            timer = 0f0
        end
    elseif phase == PhaseArcAPrimeToCForCB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointAPrime, PointC, 0.24f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragCBForward
            timer = 0f0
        end
    elseif phase == PhaseDragCBForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointC, PointB, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseDragCBBack
            timer = 0f0
        end
    elseif phase == PhaseDragCBBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointB, PointC, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseArcCToCPrimeForCPrimeBPrime
            timer = 0f0
        end
    elseif phase == PhaseArcCToCPrimeForCPrimeBPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointC, PointCPrime, 0.24f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragCPrimeBPrimeForward
            timer = 0f0
        end
    elseif phase == PhaseDragCPrimeBPrimeForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointCPrime, PointBPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseDragCPrimeBPrimeBack
            timer = 0f0
        end
    elseif phase == PhaseDragCPrimeBPrimeBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointBPrime, PointCPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseArcCPrimeToDForDB
            timer = 0f0
        end
    elseif phase == PhaseArcCPrimeToDForDB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointCPrime, PointD, 0.24f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragDBForward
            timer = 0f0
        end
    elseif phase == PhaseDragDBForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointD, PointB, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseDragDBBack
            timer = 0f0
        end
    elseif phase == PhaseDragDBBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointB, PointD, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseArcDToDPrimeForDPrimeBPrime
            timer = 0f0
        end
    elseif phase == PhaseArcDToDPrimeForDPrimeBPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointD, PointDPrime, 0.24f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragDPrimeBPrimeForward
            timer = 0f0
        end
    elseif phase == PhaseDragDPrimeBPrimeForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointDPrime, PointBPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseDragDPrimeBPrimeBack
            timer = 0f0
        end
    elseif phase == PhaseDragDPrimeBPrimeBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointBPrime, PointDPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseArcDPrimeToAForAC
            timer = 0f0
        end
    elseif phase == PhaseArcDPrimeToAForAC
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointDPrime, PointA, 0.24f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragACForward
            timer = 0f0
        end
    elseif phase == PhaseDragACForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointA, PointC, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseDragACBack
            timer = 0f0
        end
    elseif phase == PhaseDragACBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointC, PointA, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseArcAToAPrimeForAPrimeCPrime
            timer = 0f0
        end
    elseif phase == PhaseArcAToAPrimeForAPrimeCPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointA, PointAPrime, 0.24f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragAPrimeCPrimeForward
            timer = 0f0
        end
    elseif phase == PhaseDragAPrimeCPrimeForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointAPrime, PointCPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseDragAPrimeCPrimeBack
            timer = 0f0
        end
    elseif phase == PhaseDragAPrimeCPrimeBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointCPrime, PointAPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhasePenRiseBeforeBAC
            timer = 0f0
        end
    elseif phase == PhasePenRiseBeforeBAC
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ, PointAPrime[1], PointAPrime[2])
        timer += dt
        if timer >= PenLiftDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseCompassDescendBAC
            timer = 0f0
        end

    elseif phase == PhaseCompassDescendBAC
        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, DescendDuration, CompassTopZ,
            PointA[1], PointA[2], MarkerBACStart[1], MarkerBACStart[2])
        timer += dt
        if timer >= DescendDuration
            phase = PhaseHighlightBACForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightBACForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerBACStart, AngleBACTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightBACBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightBACBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerBACEnd, -AngleBACTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcBACToBPrimeAPrimeCPrime
            timer = 0f0
        end
    elseif phase == PhaseCompassArcBACToBPrimeAPrimeCPrime
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointA, PointAPrime,
            MarkerBACStart, MarkerBPrimeAPrimeCPrimeStart, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightBPrimeAPrimeCPrimeForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightBPrimeAPrimeCPrimeForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerBPrimeAPrimeCPrimeStart,
            AngleBPrimeAPrimeCPrimeTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightBPrimeAPrimeCPrimeBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightBPrimeAPrimeCPrimeBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerBPrimeAPrimeCPrimeEnd,
            -AngleBPrimeAPrimeCPrimeTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassRiseAfterBAC
            timer = 0f0
        end
    elseif phase == PhaseCompassRiseAfterBAC
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassLiftDuration, CompassTopZ,
            PointAPrime[1], PointAPrime[2],
            MarkerBPrimeAPrimeCPrimeStart[1], MarkerBPrimeAPrimeCPrimeStart[2])
        timer += dt
        if timer >= CompassLiftDuration
            OdinJuliaBridge.hide_compass(state_ptr)
            phase = PhasePenDescendAForAD
            timer = 0f0
        end

    elseif phase == PhasePenDescendAForAD
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, PointA[1], PointA[2])
        timer += dt
        if timer >= DescendDuration
            phase = PhaseDragADForward
            timer = 0f0
        end
    elseif phase == PhaseDragADForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointA, PointD, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseDragADBack
            timer = 0f0
        end
    elseif phase == PhaseDragADBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointD, PointA, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseArcAToAPrimeForAPrimeDPrime
            timer = 0f0
        end
    elseif phase == PhaseArcAToAPrimeForAPrimeDPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointA, PointAPrime, 0.24f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragAPrimeDPrimeForward
            timer = 0f0
        end
    elseif phase == PhaseDragAPrimeDPrimeForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointAPrime, PointDPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseDragAPrimeDPrimeBack
            timer = 0f0
        end
    elseif phase == PhaseDragAPrimeDPrimeBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointDPrime, PointAPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseArcAPrimeToCForCD
            timer = 0f0
        end
    elseif phase == PhaseArcAPrimeToCForCD
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointAPrime, PointC, 0.24f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragCDForward
            timer = 0f0
        end
    elseif phase == PhaseDragCDForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointC, PointD, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseDragCDBack
            timer = 0f0
        end
    elseif phase == PhaseDragCDBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointD, PointC, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseArcCToCPrimeForCPrimeDPrime
            timer = 0f0
        end
    elseif phase == PhaseArcCToCPrimeForCPrimeDPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointC, PointCPrime, 0.24f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragCPrimeDPrimeForward
            timer = 0f0
        end
    elseif phase == PhaseDragCPrimeDPrimeForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointCPrime, PointDPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseDragCPrimeDPrimeBack
            timer = 0f0
        end
    elseif phase == PhaseDragCPrimeDPrimeBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointDPrime, PointCPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhasePenRiseBeforeFinalAngles
            timer = 0f0
        end
    elseif phase == PhasePenRiseBeforeFinalAngles
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ, PointCPrime[1], PointCPrime[2])
        timer += dt
        if timer >= PenLiftDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseCompassDescendADC
            timer = 0f0
        end

    elseif phase == PhaseCompassDescendADC
        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, DescendDuration, CompassTopZ,
            PointD[1], PointD[2], MarkerADCStart[1], MarkerADCStart[2])
        timer += dt
        if timer >= DescendDuration
            phase = PhaseHighlightADCForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightADCForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointD, MarkerADCStart, AngleADCTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightADCBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightADCBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointD, MarkerADCEnd, -AngleADCTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcADCToAPrimeDPrimeCPrime
            timer = 0f0
        end
    elseif phase == PhaseCompassArcADCToAPrimeDPrimeCPrime
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointD, PointDPrime,
            MarkerADCStart, MarkerAPrimeDPrimeCPrimeStart, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightAPrimeDPrimeCPrimeForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightAPrimeDPrimeCPrimeForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointDPrime, MarkerAPrimeDPrimeCPrimeStart,
            AngleAPrimeDPrimeCPrimeTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightAPrimeDPrimeCPrimeBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightAPrimeDPrimeCPrimeBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointDPrime, MarkerAPrimeDPrimeCPrimeEnd,
            -AngleAPrimeDPrimeCPrimeTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcAPrimeDPrimeCPrimeToCBD
            timer = 0f0
        end
    elseif phase == PhaseCompassArcAPrimeDPrimeCPrimeToCBD
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointDPrime, PointB,
            MarkerAPrimeDPrimeCPrimeStart, MarkerCBDStart, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightCBDAgainForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightCBDAgainForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointB, MarkerCBDStart, AngleCBDTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightCBDAgainBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightCBDAgainBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointB, MarkerCBDEnd, -AngleCBDTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcCBDToCPrimeBPrimeDPrimeFinal
            timer = 0f0
        end
    elseif phase == PhaseCompassArcCBDToCPrimeBPrimeDPrimeFinal
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointB, PointBPrime,
            MarkerCBDStart, MarkerCPrimeBPrimeDPrimeStart, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightCPrimeBPrimeDPrimeAgainForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightCPrimeBPrimeDPrimeAgainForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointBPrime, MarkerCPrimeBPrimeDPrimeStart,
            AngleCPrimeBPrimeDPrimeTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightCPrimeBPrimeDPrimeAgainBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightCPrimeBPrimeDPrimeAgainBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointBPrime, MarkerCPrimeBPrimeDPrimeEnd,
            -AngleCPrimeBPrimeDPrimeTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassRiseEnd
            timer = 0f0
        end
    elseif phase == PhaseCompassRiseEnd
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassLiftDuration, CompassTopZ,
            PointBPrime[1], PointBPrime[2],
            MarkerCPrimeBPrimeDPrimeStart[1], MarkerCPrimeBPrimeDPrimeStart[2])
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

module HilbertChapterOneTheorem13

using ..OdinJuliaBridge
using ..EuclidAnimations

export get_view_text, initialize, clean, loop

const PointO = [0.16f0, 0.70f0, 0f0]
const PointA = [0.38f0, 0.62f0, 0f0]
const PointB = [0.34f0, 0.88f0, 0f0]

const RayHEnd = [0.50f0, 0.58f0, 0f0]
const RayKEnd = [0.42f0, 0.96f0, 0f0]

const PointOPrime = [0.61f0, 0.30f0, 0f0]
const PointAPrime = [0.83f0, 0.22f0, 0f0]
const PointBPrime = [0.79f0, 0.48f0, 0f0]

const RayHPrimeEnd = [0.95f0, 0.18f0, 0f0]
const RayKPrimeEnd = [0.87f0, 0.56f0, 0f0]

const CParameter = 0.55f0
const PointC = [
    PointA[1] + CParameter * (PointB[1] - PointA[1]),
    PointA[2] + CParameter * (PointB[2] - PointA[2]),
    0f0,
]
const PointCPrime = [
    PointAPrime[1] + CParameter * (PointBPrime[1] - PointAPrime[1]),
    PointAPrime[2] + CParameter * (PointBPrime[2] - PointAPrime[2]),
    0f0,
]

const LRayScale = 2.0f0
const LPrimeRayScale = 1.85f0
const RayLEnd = [
    PointO[1] + LRayScale * (PointC[1] - PointO[1]),
    PointO[2] + LRayScale * (PointC[2] - PointO[2]),
    0f0,
]
const RayLPrimeEnd = [
    PointOPrime[1] + LPrimeRayScale * (PointCPrime[1] - PointOPrime[1]),
    PointOPrime[2] + LPrimeRayScale * (PointCPrime[2] - PointOPrime[2]),
    0f0,
]

const RayHStart = PointO
const RayKStart = PointO
const RayHPrimeStart = PointOPrime
const RayKPrimeStart = PointOPrime
const RayLStart = PointO
const RayLPrimeStart = PointOPrime

const SegmentABStart = PointA
const SegmentABEnd = PointB
const SegmentAPrimeBPrimeStart = PointAPrime
const SegmentAPrimeBPrimeEnd = PointBPrime

const MarkerRadius = 0.08f0

const ThetaO_H = Float32(atan(RayHEnd[2] - PointO[2], RayHEnd[1] - PointO[1]))
const ThetaO_K = Float32(atan(RayKEnd[2] - PointO[2], RayKEnd[1] - PointO[1]))
const ThetaOPrime_H = Float32(atan(
    RayHPrimeEnd[2] - PointOPrime[2], RayHPrimeEnd[1] - PointOPrime[1]))
const ThetaOPrime_K = Float32(atan(
    RayKPrimeEnd[2] - PointOPrime[2], RayKPrimeEnd[1] - PointOPrime[1]))

const ThetaA_AO = Float32(atan(PointO[2] - PointA[2], PointO[1] - PointA[1]))
const ThetaA_AB = Float32(atan(PointB[2] - PointA[2], PointB[1] - PointA[1]))
const ThetaAPrime_AO = Float32(atan(
    PointOPrime[2] - PointAPrime[2], PointOPrime[1] - PointAPrime[1]))
const ThetaAPrime_AB = Float32(atan(
    PointBPrime[2] - PointAPrime[2], PointBPrime[1] - PointAPrime[1]))

const ThetaB_BO = Float32(atan(PointO[2] - PointB[2], PointO[1] - PointB[1]))
const ThetaB_BA = Float32(atan(PointA[2] - PointB[2], PointA[1] - PointB[1]))
const ThetaBPrime_BO = Float32(atan(
    PointOPrime[2] - PointBPrime[2], PointOPrime[1] - PointBPrime[1]))
const ThetaBPrime_BA = Float32(atan(
    PointAPrime[2] - PointBPrime[2], PointAPrime[1] - PointBPrime[1]))

const MarkerOHStart = [
    PointO[1] + MarkerRadius * Float32(cos(ThetaO_H)),
    PointO[2] + MarkerRadius * Float32(sin(ThetaO_H)),
    0f0,
]
const MarkerOHEnd = [
    PointO[1] + MarkerRadius * Float32(cos(ThetaO_K)),
    PointO[2] + MarkerRadius * Float32(sin(ThetaO_K)),
    0f0,
]
const MarkerOPrimeHStart = [
    PointOPrime[1] + MarkerRadius * Float32(cos(ThetaOPrime_H)),
    PointOPrime[2] + MarkerRadius * Float32(sin(ThetaOPrime_H)),
    0f0,
]
const MarkerOPrimeHEnd = [
    PointOPrime[1] + MarkerRadius * Float32(cos(ThetaOPrime_K)),
    PointOPrime[2] + MarkerRadius * Float32(sin(ThetaOPrime_K)),
    0f0,
]

const MarkerOABStart = [
    PointA[1] + MarkerRadius * Float32(cos(ThetaA_AO)),
    PointA[2] + MarkerRadius * Float32(sin(ThetaA_AO)),
    0f0,
]
const MarkerOABEnd = [
    PointA[1] + MarkerRadius * Float32(cos(ThetaA_AB)),
    PointA[2] + MarkerRadius * Float32(sin(ThetaA_AB)),
    0f0,
]
const MarkerOPrimeAPrimeBPrimeStart = [
    PointAPrime[1] + MarkerRadius * Float32(cos(ThetaAPrime_AO)),
    PointAPrime[2] + MarkerRadius * Float32(sin(ThetaAPrime_AO)),
    0f0,
]
const MarkerOPrimeAPrimeBPrimeEnd = [
    PointAPrime[1] + MarkerRadius * Float32(cos(ThetaAPrime_AB)),
    PointAPrime[2] + MarkerRadius * Float32(sin(ThetaAPrime_AB)),
    0f0,
]

const MarkerOBAStart = [
    PointB[1] + MarkerRadius * Float32(cos(ThetaB_BO)),
    PointB[2] + MarkerRadius * Float32(sin(ThetaB_BO)),
    0f0,
]
const MarkerOBAEnd = [
    PointB[1] + MarkerRadius * Float32(cos(ThetaB_BA)),
    PointB[2] + MarkerRadius * Float32(sin(ThetaB_BA)),
    0f0,
]
const MarkerOPrimeBPrimeAPrimeStart = [
    PointBPrime[1] + MarkerRadius * Float32(cos(ThetaBPrime_BO)),
    PointBPrime[2] + MarkerRadius * Float32(sin(ThetaBPrime_BO)),
    0f0,
]
const MarkerOPrimeBPrimeAPrimeEnd = [
    PointBPrime[1] + MarkerRadius * Float32(cos(ThetaBPrime_BA)),
    PointBPrime[2] + MarkerRadius * Float32(sin(ThetaBPrime_BA)),
    0f0,
]

const AngleOHKTheta = ThetaO_K - ThetaO_H
const AngleOPrimeHKTheta = ThetaOPrime_K - ThetaOPrime_H
const AngleOABTheta = ThetaA_AB - ThetaA_AO
const AngleOPrimeAPrimeBPrimeTheta = ThetaAPrime_AB - ThetaAPrime_AO
const AngleOBATheta = ThetaB_BA - ThetaB_BO
const AngleOPrimeBPrimeAPrimeTheta = ThetaBPrime_BA - ThetaBPrime_BO

const LabelColor = :plum1
const HighlightColor = :lightgreen

const RayHColor = :steelblue
const RayKColor = :palevioletred1
const RayLColor = :grey60
const SegmentABColor = :khaki3

const PointAuxColor = :grey60
const PointCColor = :steelblue

const EdgeBrush = 5f0
const PointBrush = 6f0
const PenTopZ = 1.4f0
const CompassTopZ = 1.4f0
const ToolResetOffscreenJoint1 = [0.50f0, 1.25f0, 1.55f0]
const ToolResetOffscreenJoint2 = [0.57f0, 1.25f0, 1.55f0]

const LabelOPoint = PointO + [-0.04f0, -0.04f0, 0f0]
const LabelOPrimePoint = PointOPrime + [-0.04f0, -0.04f0, 0f0]
const LabelAPoint = PointA + [0.01f0, -0.04f0, 0f0]
const LabelBPoint = PointB + [0.01f0, 0.04f0, 0f0]
const LabelAPrimePoint = PointAPrime + [0.01f0, -0.04f0, 0f0]
const LabelBPrimePoint = PointBPrime + [0.01f0, 0.04f0, 0f0]
const LabelCPoint = PointC + [0.05f0, 0.00f0, 0f0]
const LabelCPrimePoint = PointCPrime + [0.05f0, 0.00f0, 0f0]
const LabelHPoint = RayHEnd + [0.03f0, -0.01f0, 0f0]
const LabelKPoint = RayKEnd + [0.01f0, 0.03f0, 0f0]
const LabelHPrimePoint = RayHPrimeEnd + [0.03f0, -0.01f0, 0f0]
const LabelKPrimePoint = RayKPrimeEnd + [0.01f0, 0.03f0, 0f0]
const LabelLPoint = RayLEnd + [0.02f0, 0.03f0, 0f0]
const LabelLPrimePoint = RayLPrimeEnd + [0.02f0, 0.03f0, 0f0]

const DescendDuration = 1.8f0
const DrawEdgeDuration = 2.2f0
const DrawPointDuration = 1.5f0
const ArcMoveDuration = 1.35f0
const DragDuration = 1.25f0
const PenLiftDuration = 1.6f0
const CompassLiftDuration = 1.8f0
const CompassSweepDuration = 0.95f0
const FinalHoldDuration = 0.35f0

const MetaRayHHostId = 1
const MetaRayHJoint1Id = 2
const MetaRayHJoint2Id = 3
const MetaRayKHostId = 11
const MetaRayKJoint1Id = 12
const MetaRayKJoint2Id = 13
const MetaRayHPrimeHostId = 21
const MetaRayHPrimeJoint1Id = 22
const MetaRayHPrimeJoint2Id = 23
const MetaRayKPrimeHostId = 31
const MetaRayKPrimeJoint1Id = 32
const MetaRayKPrimeJoint2Id = 33
const MetaRayLHostId = 41
const MetaRayLJoint1Id = 42
const MetaRayLJoint2Id = 43
const MetaRayLPrimeHostId = 51
const MetaRayLPrimeJoint1Id = 52
const MetaRayLPrimeJoint2Id = 53

const MetaSegmentABHostId = 61
const MetaSegmentABJoint1Id = 62
const MetaSegmentABJoint2Id = 63
const MetaSegmentAPrimeBPrimeHostId = 71
const MetaSegmentAPrimeBPrimeJoint1Id = 72
const MetaSegmentAPrimeBPrimeJoint2Id = 73

const MetaPointAId = 81
const MetaPointBId = 82
const MetaPointAPrimeId = 83
const MetaPointBPrimeId = 84
const MetaPointCId = 85
const MetaPointCPrimeId = 86

const MetaLabelOId = 91
const MetaLabelOPrimeId = 92
const MetaLabelAId = 93
const MetaLabelBId = 94
const MetaLabelAPrimeId = 95
const MetaLabelBPrimeId = 96
const MetaLabelCId = 97
const MetaLabelCPrimeId = 98
const MetaLabelHId = 111
const MetaLabelKId = 112
const MetaLabelHPrimeId = 113
const MetaLabelKPrimeId = 114
const MetaLabelLId = 115
const MetaLabelLPrimeId = 116

const MetaPhase = 101
const MetaTimer = 102

const PhaseDescendToO = 0f0
const PhaseDrawRayH = 1f0
const PhaseArcHToO = 2f0
const PhaseDrawRayK = 3f0
const PhaseArcOToOPrime = 4f0
const PhaseDrawRayHPrime = 5f0
const PhaseArcHPrimeToOPrime = 6f0
const PhaseDrawRayKPrime = 7f0
const PhasePenRiseBeforeAngleHK = 8f0

const PhaseCompassDescendHK = 9f0
const PhaseHighlightHKForward = 10f0
const PhaseHighlightHKBack = 11f0
const PhaseCompassArcHKToPrime = 12f0
const PhaseHighlightHPrimeKPrimeForward = 13f0
const PhaseHighlightHPrimeKPrimeBack = 14f0
const PhaseCompassRiseAfterHK = 15f0

const PhasePenDescendOForL = 16f0
const PhaseDrawRayL = 17f0
const PhaseArcOToA = 18f0
const PhaseDrawPointA = 19f0
const PhaseArcAToB = 20f0
const PhaseDrawPointB = 21f0
const PhaseArcBToOPrime = 22f0
const PhaseArcOPrimeToAPrime = 23f0
const PhaseDrawPointAPrime = 24f0
const PhaseArcAPrimeToBPrime = 25f0
const PhaseDrawPointBPrime = 26f0

const PhaseArcBPrimeToOForOA = 27f0
const PhaseDragOAForward = 28f0
const PhaseDragOABack = 29f0
const PhaseArcOToOPrimeForPrimeOA = 30f0
const PhaseDragOPrimeAForward = 31f0
const PhaseDragOPrimeABack = 32f0
const PhaseArcOPrimeToOForOB = 33f0
const PhaseDragOBForward = 34f0
const PhaseDragOBBack = 35f0
const PhaseArcOToOPrimeForPrimeOB = 36f0
const PhaseDragOPrimeBForward = 37f0
const PhaseDragOPrimeBBack = 38f0

const PhaseArcOPrimeToAForAB = 39f0
const PhaseDrawSegmentAB = 40f0
const PhaseArcBToAPrimeForPrimeAB = 41f0
const PhaseDrawSegmentAPrimeBPrime = 42f0
const PhaseArcBPrimeToAForABHighlight = 43f0
const PhaseDragABForward = 44f0
const PhaseDragABBack = 45f0
const PhaseArcAToAPrimeForPrimeABHighlight = 46f0
const PhaseDragAPrimeBPrimeForward = 47f0
const PhaseDragAPrimeBPrimeBack = 48f0
const PhasePenRiseBeforeAngleOAB = 49f0

const PhaseCompassDescendOAB = 50f0
const PhaseHighlightOABForward = 51f0
const PhaseHighlightOABBack = 52f0
const PhaseCompassArcOABToPrime = 53f0
const PhaseHighlightOPrimeAPrimeBPrimeForward = 54f0
const PhaseHighlightOPrimeAPrimeBPrimeBack = 55f0
const PhaseCompassArcPrimeToOBA = 56f0
const PhaseHighlightOBAForward = 57f0
const PhaseHighlightOBABack = 58f0
const PhaseCompassArcOBAToPrime = 59f0
const PhaseHighlightOPrimeBPrimeAPrimeForward = 60f0
const PhaseHighlightOPrimeBPrimeAPrimeBack = 61f0
const PhaseCompassRiseAfterAngleOAB = 62f0

const PhasePenDescendC = 63f0
const PhaseDrawPointC = 64f0
const PhaseArcCToCPrime = 65f0
const PhaseDrawPointCPrime = 66f0
const PhaseArcCPrimeToAForAC = 67f0
const PhaseDragACForward = 68f0
const PhaseDragACBack = 69f0
const PhaseArcAToAPrimeForPrimeAC = 70f0
const PhaseDragAPrimeCPrimeForward = 71f0
const PhaseDragAPrimeCPrimeBack = 72f0
const PhaseArcAPrimeToBForBC = 73f0
const PhaseDragBCForward = 74f0
const PhaseDragBCBack = 75f0
const PhaseArcBToBPrimeForPrimeBC = 76f0
const PhaseDragBPrimeCPrimeForward = 77f0
const PhaseDragBPrimeCPrimeBack = 78f0
const PhaseArcBPrimeToOPrimeForLPrime = 79f0
const PhaseDrawRayLPrime = 80f0
const PhasePenRiseEnd = 81f0
const PhaseFinalHold = 82f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """David Hilbert - Foundations of Geometry - Theorem 13

Let the angle (h, k) of the plane α be congruent to the angle (h', k') of the plane α', and, furthermore, let l be a half-ray in the plane α emanating from the vertex of the angle (h, k) and lying within this angle. Then there always exists in the plane α' a half-ray l' emanating from the vertex of the angle (h', k') and lying within this angle so that we have

    ∠(h, l) ≡ ∠(h', l'),   ∠(k, l) ≡ ∠(k', l').

Proof: We will represent the vertices of the angles (h, k) and (h', k') by O and O', respectively, and so select upon the sides h, k, h', k' the points A, B, A', B' so that the congruences

    OA ≡ O'A',   OB ≡ O'B'

are fulfilled. Because of the congruence of the triangles OAB and O'A'B', we have at once

    AB ≡ A'B',   ∠OAB ≡ ∠O'A'B',   ∠OBA ≡ ∠O'B'A'.

Let the straight line AB intersect l in C. Take the point C' upon the segment A'B' so that A'C' ≡ AC. Then O'C' is the required half-ray. In fact, it follows directly from these congruences, by aid of axiom IV, 3, that BC ≡ B'C'. Furthermore, the triangles OAC and O'A'C' are congruent to each other, and the same is true also of the triangles OCB and O'B'C'. With this our proposition is demonstrated."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    rayHHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHHostId))
    rayHJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHJoint2Id))
    rayKHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKHostId))
    rayKJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKJoint2Id))
    rayHPrimeHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHPrimeHostId))
    rayHPrimeJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHPrimeJoint2Id))
    rayKPrimeHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKPrimeHostId))
    rayKPrimeJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKPrimeJoint2Id))
    rayLHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayLHostId))
    rayLJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayLJoint2Id))
    rayLPrimeHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayLPrimeHostId))
    rayLPrimeJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayLPrimeJoint2Id))

    segmentABHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaSegmentABHostId))
    segmentABJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaSegmentABJoint2Id))
    segmentAPrimeBPrimeHostId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaSegmentAPrimeBPrimeHostId))
    segmentAPrimeBPrimeJoint2Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaSegmentAPrimeBPrimeJoint2Id))

    pointAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    pointBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    pointAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAPrimeId))
    pointBPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBPrimeId))
    pointCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointCId))
    pointCPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointCPrimeId))

    labelOId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelOId))
    labelOPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelOPrimeId))
    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labelAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAPrimeId))
    labelBPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBPrimeId))
    labelCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    labelCPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCPrimeId))
    labelHId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelHId))
    labelKId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelKId))
    labelHPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelHPrimeId))
    labelKPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelKPrimeId))
    labelLId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelLId))
    labelLPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelLPrimeId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [rayHHostId, rayKHostId, rayHPrimeHostId, rayKPrimeHostId,
         rayLHostId, rayLPrimeHostId,
         segmentABHostId, segmentAPrimeBPrimeHostId,
         pointAId, pointBId, pointAPrimeId, pointBPrimeId, pointCId, pointCPrimeId,
         labelOId, labelOPrimeId, labelAId, labelBId,
         labelAPrimeId, labelBPrimeId, labelCId, labelCPrimeId,
         labelHId, labelKId, labelHPrimeId, labelKPrimeId, labelLId, labelLPrimeId])

    OdinJuliaBridge.set_point_position(state_ptr, rayHJoint2Id, RayHStart)
    OdinJuliaBridge.set_point_position(state_ptr, rayKJoint2Id, RayKStart)
    OdinJuliaBridge.set_point_position(state_ptr, rayHPrimeJoint2Id, RayHPrimeStart)
    OdinJuliaBridge.set_point_position(state_ptr, rayKPrimeJoint2Id, RayKPrimeStart)
    OdinJuliaBridge.set_point_position(state_ptr, rayLJoint2Id, RayLStart)
    OdinJuliaBridge.set_point_position(state_ptr, rayLPrimeJoint2Id, RayLPrimeStart)
    OdinJuliaBridge.set_point_position(state_ptr, segmentABJoint2Id, SegmentABStart)
    OdinJuliaBridge.set_point_position(state_ptr, segmentAPrimeBPrimeJoint2Id, SegmentAPrimeBPrimeStart)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescendToO)
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

    OdinJuliaBridge.set_pen_active(state_ptr, 0, RayHColor)
    OdinJuliaBridge.set_compass_active(state_ptr, 0, HighlightColor)
    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    rayH = OdinJuliaBridge.create_new_line(state_ptr, RayHStart, RayHStart, RayHColor, 0f0)
    rayK = OdinJuliaBridge.create_new_line(state_ptr, RayKStart, RayKStart, RayKColor, 0f0)
    rayHPrime = OdinJuliaBridge.create_new_line(
        state_ptr, RayHPrimeStart, RayHPrimeStart, RayHColor, 0f0)
    rayKPrime = OdinJuliaBridge.create_new_line(
        state_ptr, RayKPrimeStart, RayKPrimeStart, RayKColor, 0f0)
    rayL = OdinJuliaBridge.create_new_line(state_ptr, RayLStart, RayLStart, RayLColor, 0f0)
    rayLPrime = OdinJuliaBridge.create_new_line(
        state_ptr, RayLPrimeStart, RayLPrimeStart, RayLColor, 0f0)

    segmentAB = OdinJuliaBridge.create_new_line(
        state_ptr, SegmentABStart, SegmentABStart, SegmentABColor, 0f0)
    segmentAPrimeBPrime = OdinJuliaBridge.create_new_line(
        state_ptr, SegmentAPrimeBPrimeStart, SegmentAPrimeBPrimeStart, SegmentABColor, 0f0)

    pointA = OdinJuliaBridge.create_new_point(state_ptr, PointA, PointAuxColor, 0f0)
    pointB = OdinJuliaBridge.create_new_point(state_ptr, PointB, PointAuxColor, 0f0)
    pointAPrime = OdinJuliaBridge.create_new_point(state_ptr, PointAPrime, PointAuxColor, 0f0)
    pointBPrime = OdinJuliaBridge.create_new_point(state_ptr, PointBPrime, PointAuxColor, 0f0)
    pointC = OdinJuliaBridge.create_new_point(state_ptr, PointC, PointCColor, 0f0)
    pointCPrime = OdinJuliaBridge.create_new_point(state_ptr, PointCPrime, PointCColor, 0f0)

    labelO = OdinJuliaBridge.create_new_label(state_ptr, 'O', LabelOPoint, LabelColor, 16f0)
    labelA = OdinJuliaBridge.create_new_label(state_ptr, 'A', LabelAPoint, LabelColor, 16f0)
    labelB = OdinJuliaBridge.create_new_label(state_ptr, 'B', LabelBPoint, LabelColor, 16f0)
    labelC = OdinJuliaBridge.create_new_label(state_ptr, 'C', LabelCPoint, LabelColor, 16f0)

    labelOPrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'O', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelOPrimePoint, LabelColor, 16f0)
    labelAPrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'A', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelAPrimePoint, LabelColor, 16f0)
    labelBPrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'B', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelBPrimePoint, LabelColor, 16f0)
    labelCPrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'C', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelCPrimePoint, LabelColor, 16f0)
    labelH = OdinJuliaBridge.create_new_label(state_ptr, 'h', LabelHPoint, LabelColor, 16f0)
    labelK = OdinJuliaBridge.create_new_label(state_ptr, 'k', LabelKPoint, LabelColor, 16f0)
    labelL = OdinJuliaBridge.create_new_label(state_ptr, 'l', LabelLPoint, LabelColor, 16f0)
    labelHPrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'h', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelHPrimePoint, LabelColor, 16f0)
    labelKPrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'k', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelKPrimePoint, LabelColor, 16f0)
    labelLPrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'l', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelLPrimePoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayHHostId, Float32(rayH.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayHJoint1Id, Float32(rayH.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayHJoint2Id, Float32(rayH.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayKHostId, Float32(rayK.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayKJoint1Id, Float32(rayK.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayKJoint2Id, Float32(rayK.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayHPrimeHostId, Float32(rayHPrime.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayHPrimeJoint1Id, Float32(rayHPrime.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayHPrimeJoint2Id, Float32(rayHPrime.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayKPrimeHostId, Float32(rayKPrime.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayKPrimeJoint1Id, Float32(rayKPrime.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayKPrimeJoint2Id, Float32(rayKPrime.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayLHostId, Float32(rayL.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayLJoint1Id, Float32(rayL.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayLJoint2Id, Float32(rayL.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayLPrimeHostId, Float32(rayLPrime.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayLPrimeJoint1Id, Float32(rayLPrime.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayLPrimeJoint2Id, Float32(rayLPrime.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaSegmentABHostId, Float32(segmentAB.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaSegmentABJoint1Id, Float32(segmentAB.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaSegmentABJoint2Id, Float32(segmentAB.joint2Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaSegmentAPrimeBPrimeHostId, Float32(segmentAPrimeBPrime.hostId))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaSegmentAPrimeBPrimeJoint1Id, Float32(segmentAPrimeBPrime.joint1Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaSegmentAPrimeBPrimeJoint2Id, Float32(segmentAPrimeBPrime.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointAId, Float32(pointA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointBId, Float32(pointB.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointAPrimeId, Float32(pointAPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointBPrimeId, Float32(pointBPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointCId, Float32(pointC.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointCPrimeId, Float32(pointCPrime.index))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelOId, Float32(labelO.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelOPrimeId, Float32(labelOPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAId, Float32(labelA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBId, Float32(labelB.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAPrimeId, Float32(labelAPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBPrimeId, Float32(labelBPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelCId, Float32(labelC.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelCPrimeId, Float32(labelCPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelHId, Float32(labelH.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelKId, Float32(labelK.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelHPrimeId, Float32(labelHPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelKPrimeId, Float32(labelKPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelLId, Float32(labelL.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelLPrimeId, Float32(labelLPrime.index))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    rayHHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHHostId))
    rayHJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHJoint1Id))
    rayHJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHJoint2Id))
    rayKHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKHostId))
    rayKJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKJoint1Id))
    rayKJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKJoint2Id))
    rayHPrimeHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHPrimeHostId))
    rayHPrimeJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHPrimeJoint1Id))
    rayHPrimeJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHPrimeJoint2Id))
    rayKPrimeHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKPrimeHostId))
    rayKPrimeJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKPrimeJoint1Id))
    rayKPrimeJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKPrimeJoint2Id))
    rayLHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayLHostId))
    rayLJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayLJoint1Id))
    rayLJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayLJoint2Id))
    rayLPrimeHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayLPrimeHostId))
    rayLPrimeJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayLPrimeJoint1Id))
    rayLPrimeJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayLPrimeJoint2Id))

    segmentABHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaSegmentABHostId))
    segmentABJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaSegmentABJoint1Id))
    segmentABJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaSegmentABJoint2Id))
    segmentAPrimeBPrimeHostId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaSegmentAPrimeBPrimeHostId))
    segmentAPrimeBPrimeJoint1Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaSegmentAPrimeBPrimeJoint1Id))
    segmentAPrimeBPrimeJoint2Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaSegmentAPrimeBPrimeJoint2Id))

    pointAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    pointBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    pointAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAPrimeId))
    pointBPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBPrimeId))
    pointCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointCId))
    pointCPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointCPrimeId))

    labelOId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelOId))
    labelOPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelOPrimeId))
    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labelAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAPrimeId))
    labelBPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBPrimeId))
    labelCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    labelCPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCPrimeId))
    labelHId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelHId))
    labelKId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelKId))
    labelHPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelHPrimeId))
    labelKPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelKPrimeId))
    labelLId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelLId))
    labelLPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelLPrimeId))

    if rayHHostId < 0 || rayKHostId < 0 || rayHPrimeHostId < 0 || rayKPrimeHostId < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescendToO
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, PointO[1], PointO[2])
        timer += dt
        if timer >= DescendDuration
            OdinJuliaBridge.show_point(state_ptr, labelOId)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, RayHColor)
            phase = PhaseDrawRayH
            timer = 0f0
        end
    elseif phase == PhaseDrawRayH
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawEdgeDuration, RayHStart, RayHEnd,
            EdgeBrush, RayHColor, rayHHostId, rayHJoint1Id, rayHJoint2Id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, labelHId)
            phase = PhaseArcHToO
            timer = 0f0
        end
    elseif phase == PhaseArcHToO
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, RayHEnd, PointO, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.set_pen_active(state_ptr, 0, RayKColor)
            phase = PhaseDrawRayK
            timer = 0f0
        end
    elseif phase == PhaseDrawRayK
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawEdgeDuration, RayKStart, RayKEnd,
            EdgeBrush, RayKColor, rayKHostId, rayKJoint1Id, rayKJoint2Id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, labelKId)
            phase = PhaseArcOToOPrime
            timer = 0f0
        end
    elseif phase == PhaseArcOToOPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, RayKEnd, PointOPrime, 0.28f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.show_point(state_ptr, labelOPrimeId)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, RayHColor)
            phase = PhaseDrawRayHPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawRayHPrime
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawEdgeDuration, RayHPrimeStart, RayHPrimeEnd,
            EdgeBrush, RayHColor, rayHPrimeHostId, rayHPrimeJoint1Id, rayHPrimeJoint2Id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, labelHPrimeId)
            phase = PhaseArcHPrimeToOPrime
            timer = 0f0
        end
    elseif phase == PhaseArcHPrimeToOPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, RayHPrimeEnd, PointOPrime, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.set_pen_active(state_ptr, 0, RayKColor)
            phase = PhaseDrawRayKPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawRayKPrime
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawEdgeDuration, RayKPrimeStart, RayKPrimeEnd,
            EdgeBrush, RayKColor, rayKPrimeHostId, rayKPrimeJoint1Id, rayKPrimeJoint2Id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, labelKPrimeId)
            phase = PhasePenRiseBeforeAngleHK
            timer = 0f0
        end
    elseif phase == PhasePenRiseBeforeAngleHK
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ, RayKPrimeEnd[1], RayKPrimeEnd[2])
        timer += dt
        if timer >= PenLiftDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseCompassDescendHK
            timer = 0f0
        end

    elseif phase == PhaseCompassDescendHK
        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, DescendDuration, CompassTopZ,
            PointO[1], PointO[2], MarkerOHStart[1], MarkerOHStart[2])
        timer += dt
        if timer >= DescendDuration
            phase = PhaseHighlightHKForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightHKForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointO, MarkerOHStart, AngleOHKTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightHKBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightHKBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointO, MarkerOHEnd, -AngleOHKTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcHKToPrime
            timer = 0f0
        end
    elseif phase == PhaseCompassArcHKToPrime
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointO, PointOPrime,
            MarkerOHStart, MarkerOPrimeHStart, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightHPrimeKPrimeForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightHPrimeKPrimeForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointOPrime, MarkerOPrimeHStart,
            AngleOPrimeHKTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightHPrimeKPrimeBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightHPrimeKPrimeBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointOPrime, MarkerOPrimeHEnd,
            -AngleOPrimeHKTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassRiseAfterHK
            timer = 0f0
        end
    elseif phase == PhaseCompassRiseAfterHK
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassLiftDuration, CompassTopZ,
            PointOPrime[1], PointOPrime[2], MarkerOPrimeHStart[1], MarkerOPrimeHStart[2])
        timer += dt
        if timer >= CompassLiftDuration
            OdinJuliaBridge.hide_compass(state_ptr)
            phase = PhasePenDescendOForL
            timer = 0f0
        end

    elseif phase == PhasePenDescendOForL
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, PointO[1], PointO[2])
        timer += dt
        if timer >= DescendDuration
            OdinJuliaBridge.set_pen_active(state_ptr, 0, RayLColor)
            phase = PhaseDrawRayL
            timer = 0f0
        end
    elseif phase == PhaseDrawRayL
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawEdgeDuration, RayLStart, RayLEnd,
            EdgeBrush, RayLColor, rayLHostId, rayLJoint1Id, rayLJoint2Id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, labelLId)
            phase = PhaseArcOToA
            timer = 0f0
        end
    elseif phase == PhaseArcOToA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, RayLEnd, PointA, 0.20f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.show_point(state_ptr, labelAId)
            phase = PhaseDrawPointA
            timer = 0f0
        end
    elseif phase == PhaseDrawPointA
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration,
            PointA, PointBrush, PointAuxColor, pointAId)
        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseArcAToB
            timer = 0f0
        end
    elseif phase == PhaseArcAToB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointA, PointB, 0.20f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.show_point(state_ptr, labelBId)
            phase = PhaseDrawPointB
            timer = 0f0
        end
    elseif phase == PhaseDrawPointB
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration,
            PointB, PointBrush, PointAuxColor, pointBId)
        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseArcBToOPrime
            timer = 0f0
        end
    elseif phase == PhaseArcBToOPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointB, PointAPrime, 0.30f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.show_point(state_ptr, labelAPrimeId)
            phase = PhaseDrawPointAPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawPointAPrime
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration,
            PointAPrime, PointBrush, PointAuxColor, pointAPrimeId)
        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseArcAPrimeToBPrime
            timer = 0f0
        end
    elseif phase == PhaseArcAPrimeToBPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointAPrime, PointBPrime, 0.20f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.show_point(state_ptr, labelBPrimeId)
            phase = PhaseDrawPointBPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawPointBPrime
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration,
            PointBPrime, PointBrush, PointAuxColor, pointBPrimeId)
        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseArcBPrimeToOForOA
            timer = 0f0
        end

    elseif phase == PhaseArcBPrimeToOForOA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointBPrime, PointO, 0.30f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragOAForward
            timer = 0f0
        end
    elseif phase == PhaseDragOAForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointO, PointA, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseDragOABack
            timer = 0f0
        end
    elseif phase == PhaseDragOABack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointA, PointO, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseArcOToOPrimeForPrimeOA
            timer = 0f0
        end
    elseif phase == PhaseArcOToOPrimeForPrimeOA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointO, PointOPrime, 0.28f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragOPrimeAForward
            timer = 0f0
        end
    elseif phase == PhaseDragOPrimeAForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointOPrime, PointAPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseDragOPrimeABack
            timer = 0f0
        end
    elseif phase == PhaseDragOPrimeABack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointAPrime, PointOPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseArcOPrimeToOForOB
            timer = 0f0
        end
    elseif phase == PhaseArcOPrimeToOForOB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointOPrime, PointO, 0.28f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragOBForward
            timer = 0f0
        end
    elseif phase == PhaseDragOBForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointO, PointB, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseDragOBBack
            timer = 0f0
        end
    elseif phase == PhaseDragOBBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointB, PointO, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseArcOToOPrimeForPrimeOB
            timer = 0f0
        end
    elseif phase == PhaseArcOToOPrimeForPrimeOB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointO, PointOPrime, 0.28f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragOPrimeBForward
            timer = 0f0
        end
    elseif phase == PhaseDragOPrimeBForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointOPrime, PointBPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseDragOPrimeBBack
            timer = 0f0
        end
    elseif phase == PhaseDragOPrimeBBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointBPrime, PointOPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseArcOPrimeToAForAB
            timer = 0f0
        end

    elseif phase == PhaseArcOPrimeToAForAB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointOPrime, PointA, 0.32f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.set_pen_active(state_ptr, 0, SegmentABColor)
            phase = PhaseDrawSegmentAB
            timer = 0f0
        end
    elseif phase == PhaseDrawSegmentAB
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawEdgeDuration, SegmentABStart, SegmentABEnd,
            EdgeBrush, SegmentABColor, segmentABHostId, segmentABJoint1Id, segmentABJoint2Id)
        timer += dt
        if timer >= DrawEdgeDuration
            phase = PhaseArcBToAPrimeForPrimeAB
            timer = 0f0
        end
    elseif phase == PhaseArcBToAPrimeForPrimeAB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointB, PointAPrime, 0.32f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawSegmentAPrimeBPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawSegmentAPrimeBPrime
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawEdgeDuration,
            SegmentAPrimeBPrimeStart, SegmentAPrimeBPrimeEnd,
            EdgeBrush, SegmentABColor,
            segmentAPrimeBPrimeHostId, segmentAPrimeBPrimeJoint1Id, segmentAPrimeBPrimeJoint2Id)
        timer += dt
        if timer >= DrawEdgeDuration
            phase = PhaseArcBPrimeToAForABHighlight
            timer = 0f0
        end
    elseif phase == PhaseArcBPrimeToAForABHighlight
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointBPrime, PointA, 0.32f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
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
            phase = PhaseArcAToAPrimeForPrimeABHighlight
            timer = 0f0
        end
    elseif phase == PhaseArcAToAPrimeForPrimeABHighlight
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointA, PointAPrime, 0.28f0, 1, :none)
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
            phase = PhasePenRiseBeforeAngleOAB
            timer = 0f0
        end
    elseif phase == PhasePenRiseBeforeAngleOAB
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ, PointAPrime[1], PointAPrime[2])
        timer += dt
        if timer >= PenLiftDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseCompassDescendOAB
            timer = 0f0
        end

    elseif phase == PhaseCompassDescendOAB
        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, DescendDuration, CompassTopZ,
            PointA[1], PointA[2], MarkerOABStart[1], MarkerOABStart[2])
        timer += dt
        if timer >= DescendDuration
            phase = PhaseHighlightOABForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightOABForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerOABStart, AngleOABTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightOABBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightOABBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerOABEnd, -AngleOABTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcOABToPrime
            timer = 0f0
        end
    elseif phase == PhaseCompassArcOABToPrime
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointA, PointAPrime,
            MarkerOABStart, MarkerOPrimeAPrimeBPrimeStart, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightOPrimeAPrimeBPrimeForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightOPrimeAPrimeBPrimeForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerOPrimeAPrimeBPrimeStart,
            AngleOPrimeAPrimeBPrimeTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightOPrimeAPrimeBPrimeBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightOPrimeAPrimeBPrimeBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerOPrimeAPrimeBPrimeEnd,
            -AngleOPrimeAPrimeBPrimeTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcPrimeToOBA
            timer = 0f0
        end
    elseif phase == PhaseCompassArcPrimeToOBA
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointAPrime, PointB,
            MarkerOPrimeAPrimeBPrimeStart, MarkerOBAStart, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightOBAForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightOBAForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointB, MarkerOBAStart, AngleOBATheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightOBABack
            timer = 0f0
        end
    elseif phase == PhaseHighlightOBABack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointB, MarkerOBAEnd, -AngleOBATheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcOBAToPrime
            timer = 0f0
        end
    elseif phase == PhaseCompassArcOBAToPrime
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointB, PointBPrime,
            MarkerOBAStart, MarkerOPrimeBPrimeAPrimeStart, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightOPrimeBPrimeAPrimeForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightOPrimeBPrimeAPrimeForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointBPrime, MarkerOPrimeBPrimeAPrimeStart,
            AngleOPrimeBPrimeAPrimeTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightOPrimeBPrimeAPrimeBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightOPrimeBPrimeAPrimeBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointBPrime, MarkerOPrimeBPrimeAPrimeEnd,
            -AngleOPrimeBPrimeAPrimeTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassRiseAfterAngleOAB
            timer = 0f0
        end
    elseif phase == PhaseCompassRiseAfterAngleOAB
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassLiftDuration, CompassTopZ,
            PointBPrime[1], PointBPrime[2],
            MarkerOPrimeBPrimeAPrimeStart[1], MarkerOPrimeBPrimeAPrimeStart[2])
        timer += dt
        if timer >= CompassLiftDuration
            OdinJuliaBridge.hide_compass(state_ptr)
            phase = PhasePenDescendC
            timer = 0f0
        end

    elseif phase == PhasePenDescendC
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, PointC[1], PointC[2])
        timer += dt
        if timer >= DescendDuration
            OdinJuliaBridge.show_point(state_ptr, labelCId)
            phase = PhaseDrawPointC
            timer = 0f0
        end
    elseif phase == PhaseDrawPointC
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration,
            PointC, PointBrush, PointCColor, pointCId)
        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseArcCToCPrime
            timer = 0f0
        end
    elseif phase == PhaseArcCToCPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointC, PointCPrime, 0.26f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.show_point(state_ptr, labelCPrimeId)
            phase = PhaseDrawPointCPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawPointCPrime
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration,
            PointCPrime, PointBrush, PointCColor, pointCPrimeId)
        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseArcCPrimeToAForAC
            timer = 0f0
        end

    elseif phase == PhaseArcCPrimeToAForAC
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointCPrime, PointA, 0.30f0, 1, :none)
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
            phase = PhaseArcAToAPrimeForPrimeAC
            timer = 0f0
        end
    elseif phase == PhaseArcAToAPrimeForPrimeAC
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointA, PointAPrime, 0.26f0, 1, :none)
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
            phase = PhaseArcAPrimeToBForBC
            timer = 0f0
        end
    elseif phase == PhaseArcAPrimeToBForBC
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointAPrime, PointB, 0.30f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragBCForward
            timer = 0f0
        end
    elseif phase == PhaseDragBCForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointB, PointC, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseDragBCBack
            timer = 0f0
        end
    elseif phase == PhaseDragBCBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointC, PointB, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseArcBToBPrimeForPrimeBC
            timer = 0f0
        end
    elseif phase == PhaseArcBToBPrimeForPrimeBC
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointB, PointBPrime, 0.26f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragBPrimeCPrimeForward
            timer = 0f0
        end
    elseif phase == PhaseDragBPrimeCPrimeForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointBPrime, PointCPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseDragBPrimeCPrimeBack
            timer = 0f0
        end
    elseif phase == PhaseDragBPrimeCPrimeBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointCPrime, PointBPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseArcBPrimeToOPrimeForLPrime
            timer = 0f0
        end
    elseif phase == PhaseArcBPrimeToOPrimeForLPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointBPrime, PointOPrime, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.set_pen_active(state_ptr, 0, RayLColor)
            phase = PhaseDrawRayLPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawRayLPrime
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawEdgeDuration, RayLPrimeStart, RayLPrimeEnd,
            EdgeBrush, RayLColor,
            rayLPrimeHostId, rayLPrimeJoint1Id, rayLPrimeJoint2Id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, labelLPrimeId)
            phase = PhasePenRiseEnd
            timer = 0f0
        end
    elseif phase == PhasePenRiseEnd
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ, RayLPrimeEnd[1], RayLPrimeEnd[2])
        timer += dt
        if timer >= PenLiftDuration
            OdinJuliaBridge.hide_pen(state_ptr)
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

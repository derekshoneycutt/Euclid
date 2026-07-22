module HilbertChapterOneDefCongruentTriangles

using ..OdinJuliaBridge
using ..EuclidAnimations

export get_view_text, initialize, clean, loop

const PointA = [0.20f0, 0.66f0, 0f0]
const PointB = [0.52f0, 0.50f0, 0f0]
const PointC = [0.44f0, 0.84f0, 0f0]

const PointAPrime = [0.60f0, 0.58f0, 0f0]
const PointBPrime = [0.90f0, 0.43f0, 0f0]
const PointCPrime = [0.82f0, 0.78f0, 0f0]

const EdgeABStart = PointA
const EdgeABEnd = PointB
const EdgeACStart = PointA
const EdgeACEnd = PointC
const EdgeBCStart = PointB
const EdgeBCEnd = PointC

const EdgeAPrimeBPrimeStart = PointAPrime
const EdgeAPrimeBPrimeEnd = PointBPrime
const EdgeAPrimeCPrimeStart = PointAPrime
const EdgeAPrimeCPrimeEnd = PointCPrime
const EdgeBPrimeCPrimeStart = PointBPrime
const EdgeBPrimeCPrimeEnd = PointCPrime

const MarkerRadius = 0.09f0

const ThetaA_AB = Float32(atan(PointB[2] - PointA[2], PointB[1] - PointA[1]))
const ThetaA_AC = Float32(atan(PointC[2] - PointA[2], PointC[1] - PointA[1]))
const ThetaAPrime_AB = Float32(atan(
    PointBPrime[2] - PointAPrime[2], PointBPrime[1] - PointAPrime[1]))
const ThetaAPrime_AC = Float32(atan(
    PointCPrime[2] - PointAPrime[2], PointCPrime[1] - PointAPrime[1]))

const ThetaB_BC = Float32(atan(PointC[2] - PointB[2], PointC[1] - PointB[1]))
const ThetaB_BA = Float32(atan(PointA[2] - PointB[2], PointA[1] - PointB[1]))
const ThetaBPrime_BC = Float32(atan(
    PointCPrime[2] - PointBPrime[2], PointCPrime[1] - PointBPrime[1]))
const ThetaBPrime_BA = Float32(atan(
    PointAPrime[2] - PointBPrime[2], PointAPrime[1] - PointBPrime[1]))

const ThetaC_CA = Float32(atan(PointA[2] - PointC[2], PointA[1] - PointC[1]))
const ThetaC_CB = Float32(atan(PointB[2] - PointC[2], PointB[1] - PointC[1]))
const ThetaCPrime_CA = Float32(atan(
    PointAPrime[2] - PointCPrime[2], PointAPrime[1] - PointCPrime[1]))
const ThetaCPrime_CB = Float32(atan(
    PointBPrime[2] - PointCPrime[2], PointBPrime[1] - PointCPrime[1]))

const MarkerAStart = [
    PointA[1] + MarkerRadius * Float32(cos(ThetaA_AB)),
    PointA[2] + MarkerRadius * Float32(sin(ThetaA_AB)),
    0f0,
]
const MarkerAEnd = [
    PointA[1] + MarkerRadius * Float32(cos(ThetaA_AC)),
    PointA[2] + MarkerRadius * Float32(sin(ThetaA_AC)),
    0f0,
]
const MarkerAPrimeStart = [
    PointAPrime[1] + MarkerRadius * Float32(cos(ThetaAPrime_AB)),
    PointAPrime[2] + MarkerRadius * Float32(sin(ThetaAPrime_AB)),
    0f0,
]
const MarkerAPrimeEnd = [
    PointAPrime[1] + MarkerRadius * Float32(cos(ThetaAPrime_AC)),
    PointAPrime[2] + MarkerRadius * Float32(sin(ThetaAPrime_AC)),
    0f0,
]

const MarkerBStart = [
    PointB[1] + MarkerRadius * Float32(cos(ThetaB_BC)),
    PointB[2] + MarkerRadius * Float32(sin(ThetaB_BC)),
    0f0,
]
const MarkerBEnd = [
    PointB[1] + MarkerRadius * Float32(cos(ThetaB_BA)),
    PointB[2] + MarkerRadius * Float32(sin(ThetaB_BA)),
    0f0,
]
const MarkerBPrimeStart = [
    PointBPrime[1] + MarkerRadius * Float32(cos(ThetaBPrime_BC)),
    PointBPrime[2] + MarkerRadius * Float32(sin(ThetaBPrime_BC)),
    0f0,
]
const MarkerBPrimeEnd = [
    PointBPrime[1] + MarkerRadius * Float32(cos(ThetaBPrime_BA)),
    PointBPrime[2] + MarkerRadius * Float32(sin(ThetaBPrime_BA)),
    0f0,
]

const MarkerCStart = [
    PointC[1] + MarkerRadius * Float32(cos(ThetaC_CA)),
    PointC[2] + MarkerRadius * Float32(sin(ThetaC_CA)),
    0f0,
]
const MarkerCEnd = [
    PointC[1] + MarkerRadius * Float32(cos(ThetaC_CB)),
    PointC[2] + MarkerRadius * Float32(sin(ThetaC_CB)),
    0f0,
]
const MarkerCPrimeStart = [
    PointCPrime[1] + MarkerRadius * Float32(cos(ThetaCPrime_CA)),
    PointCPrime[2] + MarkerRadius * Float32(sin(ThetaCPrime_CA)),
    0f0,
]
const MarkerCPrimeEnd = [
    PointCPrime[1] + MarkerRadius * Float32(cos(ThetaCPrime_CB)),
    PointCPrime[2] + MarkerRadius * Float32(sin(ThetaCPrime_CB)),
    0f0,
]

const AngleATheta = ThetaA_AC - ThetaA_AB
const AngleAPrimeTheta = ThetaAPrime_AC - ThetaAPrime_AB
const AngleBTheta = ThetaB_BA - ThetaB_BC
const AngleBPrimeTheta = ThetaBPrime_BA - ThetaBPrime_BC
const AngleCTheta = ThetaC_CB - ThetaC_CA
const AngleCPrimeTheta = ThetaCPrime_CB - ThetaCPrime_CA

const LabelColor = :plum1
const HighlightColor = :lightgreen

const EdgeABColor = :steelblue
const EdgeACColor = :palevioletred1
const EdgeBCColor = :khaki3
const EdgeAPrimeBPrimeColor = :grey60
const EdgeAPrimeCPrimeColor = :steelblue
const EdgeBPrimeCPrimeColor = :palevioletred1

const EdgeBrush = 5f0
const ResetPenLength = 0.14f0

const LabelAPoint = PointA + [-0.04f0, -0.04f0, 0f0]
const LabelBPoint = PointB + [0.02f0, -0.03f0, 0f0]
const LabelCPoint = PointC + [-0.01f0, 0.03f0, 0f0]

const LabelAPrimePoint = PointAPrime + [-0.04f0, -0.04f0, 0f0]
const LabelBPrimePoint = PointBPrime + [0.02f0, -0.03f0, 0f0]
const LabelCPrimePoint = PointCPrime + [-0.01f0, 0.03f0, 0f0]

const PenTopZ = 1.4f0
const CompassTopZ = 1.4f0

const DescendDuration = 1.8f0
const DrawEdgeDuration = 2.2f0
const ArcMoveDuration = 1.4f0
const PenLiftDuration = 1.6f0
const CompassLiftDuration = 1.8f0
const CompassSweepDuration = 1.0f0
const DragDuration = 1.5f0
const FinalHoldDuration = 0.9f0

const MetaEdgeABHostId = 1
const MetaEdgeABJoint1Id = 2
const MetaEdgeABJoint2Id = 3
const MetaEdgeACHostId = 11
const MetaEdgeACJoint1Id = 12
const MetaEdgeACJoint2Id = 13
const MetaEdgeBCHostId = 21
const MetaEdgeBCJoint1Id = 22
const MetaEdgeBCJoint2Id = 23

const MetaEdgeAPrimeBPrimeHostId = 31
const MetaEdgeAPrimeBPrimeJoint1Id = 32
const MetaEdgeAPrimeBPrimeJoint2Id = 33
const MetaEdgeAPrimeCPrimeHostId = 41
const MetaEdgeAPrimeCPrimeJoint1Id = 42
const MetaEdgeAPrimeCPrimeJoint2Id = 43
const MetaEdgeBPrimeCPrimeHostId = 51
const MetaEdgeBPrimeCPrimeJoint1Id = 52
const MetaEdgeBPrimeCPrimeJoint2Id = 53

const MetaLabelAId = 61
const MetaLabelBId = 62
const MetaLabelCId = 63
const MetaLabelAPrimeId = 64
const MetaLabelBPrimeId = 65
const MetaLabelCPrimeId = 66

const MetaPhase = 101
const MetaTimer = 102

const PhaseDescendToA = 0f0
const PhaseDrawAB = 1f0
const PhaseArcBToA = 2f0
const PhaseDrawAC = 3f0
const PhaseArcCToB = 4f0
const PhaseDrawBC = 5f0

const PhaseArcCToAPrime = 6f0
const PhaseDescendAtAPrime = 7f0
const PhaseDrawAPrimeBPrime = 8f0
const PhaseArcBPrimeToAPrime = 9f0
const PhaseDrawAPrimeCPrime = 10f0
const PhaseArcCPrimeToBPrime = 11f0
const PhaseDrawBPrimeCPrime = 12f0

const PhaseArcCPrimeToDragA = 13f0
const PhaseDragABForward = 14f0
const PhaseDragABBack = 15f0
const PhaseArcAToDragAPrime = 16f0
const PhaseDragAPrimeBPrimeForward = 17f0
const PhaseDragAPrimeBPrimeBack = 18f0
const PhaseArcAPrimeToDragAForAC = 19f0
const PhaseDragACForward = 20f0
const PhaseDragACBack = 21f0
const PhaseArcAToDragAPrimeForCPrime = 22f0
const PhaseDragAPrimeCPrimeForward = 23f0
const PhaseDragAPrimeCPrimeBack = 24f0
const PhaseArcAPrimeToDragBForBC = 25f0
const PhaseDragBCForward = 26f0
const PhaseDragBCBack = 27f0
const PhaseArcBToDragBPrimeForBPrimeCPrime = 28f0
const PhaseDragBPrimeCPrimeForward = 29f0
const PhaseDragBPrimeCPrimeBack = 30f0

const PhasePenRiseBeforeCompass = 31f0
const PhaseCompassDescendAtA = 32f0
const PhaseHighlightAngleAForward = 33f0
const PhaseHighlightAngleABack = 34f0
const PhaseCompassArcAToAPrime = 35f0
const PhaseHighlightAngleAPrimeForward = 36f0
const PhaseHighlightAngleAPrimeBack = 37f0
const PhaseCompassArcAPrimeToB = 38f0
const PhaseHighlightAngleBForward = 39f0
const PhaseHighlightAngleBBack = 40f0
const PhaseCompassArcBToBPrime = 41f0
const PhaseHighlightAngleBPrimeForward = 42f0
const PhaseHighlightAngleBPrimeBack = 43f0
const PhaseCompassArcBPrimeToC = 44f0
const PhaseHighlightAngleCForward = 45f0
const PhaseHighlightAngleCBack = 46f0
const PhaseCompassArcCToCPrime = 47f0
const PhaseHighlightAngleCPrimeForward = 48f0
const PhaseHighlightAngleCPrimeBack = 49f0

const PhaseCompassLiftEnd = 50f0
const PhaseFinalHold = 51f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """David Hilbert - Foundations of Geometry - Definition: Congruent Triangles

Two triangles ABC and A'B'C' are said to be congruent to one another when all of the following congruences are fulfilled:

    AB ≡ A'B',    AC ≡ A'C',    BC ≡ B'C',
    ∠A ≡ ∠A',    ∠B ≡ ∠B',    ∠C ≡ ∠C'."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    edgeABHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeABHostId))
    edgeABJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeABJoint2Id))
    edgeACHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeACHostId))
    edgeACJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeACJoint2Id))
    edgeBCHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeBCHostId))
    edgeBCJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeBCJoint2Id))

    edgeAPrimeBPrimeHostId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPrimeBPrimeHostId))
    edgeAPrimeBPrimeJoint2Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPrimeBPrimeJoint2Id))
    edgeAPrimeCPrimeHostId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPrimeCPrimeHostId))
    edgeAPrimeCPrimeJoint2Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPrimeCPrimeJoint2Id))
    edgeBPrimeCPrimeHostId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeBPrimeCPrimeHostId))
    edgeBPrimeCPrimeJoint2Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeBPrimeCPrimeJoint2Id))

    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labelCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    labelAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAPrimeId))
    labelBPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBPrimeId))
    labelCPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCPrimeId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [edgeABHostId, edgeACHostId, edgeBCHostId,
         edgeAPrimeBPrimeHostId, edgeAPrimeCPrimeHostId, edgeBPrimeCPrimeHostId,
         labelAId, labelBId, labelCId, labelAPrimeId, labelBPrimeId, labelCPrimeId])

    OdinJuliaBridge.set_point_position(state_ptr, edgeABJoint2Id, EdgeABStart)
    OdinJuliaBridge.set_point_position(state_ptr, edgeACJoint2Id, EdgeACStart)
    OdinJuliaBridge.set_point_position(state_ptr, edgeBCJoint2Id, EdgeBCStart)

    OdinJuliaBridge.set_point_position(state_ptr, edgeAPrimeBPrimeJoint2Id, EdgeAPrimeBPrimeStart)
    OdinJuliaBridge.set_point_position(state_ptr, edgeAPrimeCPrimeJoint2Id, EdgeAPrimeCPrimeStart)
    OdinJuliaBridge.set_point_position(state_ptr, edgeBPrimeCPrimeJoint2Id, EdgeBPrimeCPrimeStart)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescendToA)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.hide_compass(state_ptr)
    OdinJuliaBridge.lock_pen_joint1(state_ptr, PointA[1], PointA[2], PenTopZ)
    OdinJuliaBridge.move_pen_joint2(state_ptr, PointA[1], PointA[2], PenTopZ + ResetPenLength)
    OdinJuliaBridge.lock_compass_joint1(
        state_ptr, PointA[1], PointA[2], CompassTopZ, sweep = false)
    OdinJuliaBridge.lock_compass_joint2(
        state_ptr, MarkerAStart[1], MarkerAStart[2], CompassTopZ, sweep = false)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeABColor)
    OdinJuliaBridge.set_compass_active(state_ptr, 0, HighlightColor)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    edgeAB = OdinJuliaBridge.create_new_line(state_ptr, EdgeABStart, EdgeABStart, EdgeABColor, 0f0)
    edgeAC = OdinJuliaBridge.create_new_line(state_ptr, EdgeACStart, EdgeACStart, EdgeACColor, 0f0)
    edgeBC = OdinJuliaBridge.create_new_line(state_ptr, EdgeBCStart, EdgeBCStart, EdgeBCColor, 0f0)

    edgeAPrimeBPrime = OdinJuliaBridge.create_new_line(
        state_ptr, EdgeAPrimeBPrimeStart, EdgeAPrimeBPrimeStart, EdgeAPrimeBPrimeColor, 0f0)
    edgeAPrimeCPrime = OdinJuliaBridge.create_new_line(
        state_ptr, EdgeAPrimeCPrimeStart, EdgeAPrimeCPrimeStart, EdgeAPrimeCPrimeColor, 0f0)
    edgeBPrimeCPrime = OdinJuliaBridge.create_new_line(
        state_ptr, EdgeBPrimeCPrimeStart, EdgeBPrimeCPrimeStart, EdgeBPrimeCPrimeColor, 0f0)

    labelA = OdinJuliaBridge.create_new_label(state_ptr, 'A', LabelAPoint, LabelColor, 16f0)
    labelB = OdinJuliaBridge.create_new_label(state_ptr, 'B', LabelBPoint, LabelColor, 16f0)
    labelC = OdinJuliaBridge.create_new_label(state_ptr, 'C', LabelCPoint, LabelColor, 16f0)

    labelAPrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'A', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelAPrimePoint, LabelColor, 16f0)
    labelBPrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'B', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelBPrimePoint, LabelColor, 16f0)
    labelCPrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'C', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelCPrimePoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeABHostId, Float32(edgeAB.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeABJoint1Id, Float32(edgeAB.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeABJoint2Id, Float32(edgeAB.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeACHostId, Float32(edgeAC.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeACJoint1Id, Float32(edgeAC.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeACJoint2Id, Float32(edgeAC.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeBCHostId, Float32(edgeBC.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeBCJoint1Id, Float32(edgeBC.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeBCJoint2Id, Float32(edgeBC.joint2Id))

    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeAPrimeBPrimeHostId, Float32(edgeAPrimeBPrime.hostId))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeAPrimeBPrimeJoint1Id, Float32(edgeAPrimeBPrime.joint1Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeAPrimeBPrimeJoint2Id, Float32(edgeAPrimeBPrime.joint2Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeAPrimeCPrimeHostId, Float32(edgeAPrimeCPrime.hostId))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeAPrimeCPrimeJoint1Id, Float32(edgeAPrimeCPrime.joint1Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeAPrimeCPrimeJoint2Id, Float32(edgeAPrimeCPrime.joint2Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeBPrimeCPrimeHostId, Float32(edgeBPrimeCPrime.hostId))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeBPrimeCPrimeJoint1Id, Float32(edgeBPrimeCPrime.joint1Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeBPrimeCPrimeJoint2Id, Float32(edgeBPrimeCPrime.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAId, Float32(labelA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBId, Float32(labelB.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelCId, Float32(labelC.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAPrimeId, Float32(labelAPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBPrimeId, Float32(labelBPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelCPrimeId, Float32(labelCPrime.index))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    edgeABHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeABHostId))
    edgeABJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeABJoint1Id))
    edgeABJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeABJoint2Id))
    edgeACHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeACHostId))
    edgeACJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeACJoint1Id))
    edgeACJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeACJoint2Id))
    edgeBCHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeBCHostId))
    edgeBCJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeBCJoint1Id))
    edgeBCJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeBCJoint2Id))

    edgeAPrimeBPrimeHostId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPrimeBPrimeHostId))
    edgeAPrimeBPrimeJoint1Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPrimeBPrimeJoint1Id))
    edgeAPrimeBPrimeJoint2Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPrimeBPrimeJoint2Id))
    edgeAPrimeCPrimeHostId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPrimeCPrimeHostId))
    edgeAPrimeCPrimeJoint1Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPrimeCPrimeJoint1Id))
    edgeAPrimeCPrimeJoint2Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPrimeCPrimeJoint2Id))
    edgeBPrimeCPrimeHostId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeBPrimeCPrimeHostId))
    edgeBPrimeCPrimeJoint1Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeBPrimeCPrimeJoint1Id))
    edgeBPrimeCPrimeJoint2Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeBPrimeCPrimeJoint2Id))

    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labelCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    labelAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAPrimeId))
    labelBPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBPrimeId))
    labelCPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCPrimeId))

    if edgeABHostId < 0 || edgeACHostId < 0 || edgeBCHostId < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescendToA
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, PointA[1], PointA[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawAB
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelAId)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeABColor)
        end
    elseif phase == PhaseDrawAB
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawEdgeDuration, EdgeABStart, EdgeABEnd,
            EdgeBrush, EdgeABColor,
            edgeABHostId, edgeABJoint1Id, edgeABJoint2Id)

        timer += dt
        if timer >= DrawEdgeDuration
            phase = PhaseArcBToA
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelBId)
        end
    elseif phase == PhaseArcBToA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            EdgeABEnd, PointA, 0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawAC
            timer = 0f0
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeACColor)
        end
    elseif phase == PhaseDrawAC
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawEdgeDuration, EdgeACStart, EdgeACEnd,
            EdgeBrush, EdgeACColor,
            edgeACHostId, edgeACJoint1Id, edgeACJoint2Id)

        timer += dt
        if timer >= DrawEdgeDuration
            phase = PhaseArcCToB
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelCId)
        end
    elseif phase == PhaseArcCToB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            EdgeACEnd, PointB, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawBC
            timer = 0f0
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeBCColor)
        end
    elseif phase == PhaseDrawBC
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawEdgeDuration, EdgeBCStart, EdgeBCEnd,
            EdgeBrush, EdgeBCColor,
            edgeBCHostId, edgeBCJoint1Id, edgeBCJoint2Id)

        timer += dt
        if timer >= DrawEdgeDuration
            phase = PhaseArcCToAPrime
            timer = 0f0
        end

    elseif phase == PhaseArcCToAPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            EdgeBCEnd, PointAPrime, 0.28f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDescendAtAPrime
            timer = 0f0
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeAPrimeBPrimeColor)
        end
    elseif phase == PhaseDescendAtAPrime
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, PointAPrime[1], PointAPrime[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawAPrimeBPrime
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelAPrimeId)
        end
    elseif phase == PhaseDrawAPrimeBPrime
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawEdgeDuration, EdgeAPrimeBPrimeStart, EdgeAPrimeBPrimeEnd,
            EdgeBrush, EdgeAPrimeBPrimeColor,
            edgeAPrimeBPrimeHostId, edgeAPrimeBPrimeJoint1Id, edgeAPrimeBPrimeJoint2Id)

        timer += dt
        if timer >= DrawEdgeDuration
            phase = PhaseArcBPrimeToAPrime
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelBPrimeId)
        end
    elseif phase == PhaseArcBPrimeToAPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            EdgeAPrimeBPrimeEnd, PointAPrime, 0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawAPrimeCPrime
            timer = 0f0
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeAPrimeCPrimeColor)
        end
    elseif phase == PhaseDrawAPrimeCPrime
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawEdgeDuration, EdgeAPrimeCPrimeStart, EdgeAPrimeCPrimeEnd,
            EdgeBrush, EdgeAPrimeCPrimeColor,
            edgeAPrimeCPrimeHostId, edgeAPrimeCPrimeJoint1Id, edgeAPrimeCPrimeJoint2Id)

        timer += dt
        if timer >= DrawEdgeDuration
            phase = PhaseArcCPrimeToBPrime
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelCPrimeId)
        end
    elseif phase == PhaseArcCPrimeToBPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            EdgeAPrimeCPrimeEnd, PointBPrime, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawBPrimeCPrime
            timer = 0f0
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeBPrimeCPrimeColor)
        end
    elseif phase == PhaseDrawBPrimeCPrime
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawEdgeDuration, EdgeBPrimeCPrimeStart, EdgeBPrimeCPrimeEnd,
            EdgeBrush, EdgeBPrimeCPrimeColor,
            edgeBPrimeCPrimeHostId, edgeBPrimeCPrimeJoint1Id, edgeBPrimeCPrimeJoint2Id)

        timer += dt
        if timer >= DrawEdgeDuration
            phase = PhaseArcCPrimeToDragA
            timer = 0f0
        end

    elseif phase == PhaseArcCPrimeToDragA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            EdgeBPrimeCPrimeEnd, EdgeABStart, 0.28f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragABForward
            timer = 0f0
        end
    elseif phase == PhaseDragABForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, EdgeABStart, EdgeABEnd, HighlightColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseDragABBack
            timer = 0f0
        end
    elseif phase == PhaseDragABBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, EdgeABEnd, EdgeABStart, HighlightColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseArcAToDragAPrime
            timer = 0f0
        end
    elseif phase == PhaseArcAToDragAPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            EdgeABStart, EdgeAPrimeBPrimeStart, 0.24f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragAPrimeBPrimeForward
            timer = 0f0
        end
    elseif phase == PhaseDragAPrimeBPrimeForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration,
            EdgeAPrimeBPrimeStart, EdgeAPrimeBPrimeEnd, HighlightColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseDragAPrimeBPrimeBack
            timer = 0f0
        end
    elseif phase == PhaseDragAPrimeBPrimeBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration,
            EdgeAPrimeBPrimeEnd, EdgeAPrimeBPrimeStart, HighlightColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseArcAPrimeToDragAForAC
            timer = 0f0
        end
    elseif phase == PhaseArcAPrimeToDragAForAC
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            EdgeAPrimeBPrimeStart, EdgeACStart, 0.24f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragACForward
            timer = 0f0
        end
    elseif phase == PhaseDragACForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, EdgeACStart, EdgeACEnd, HighlightColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseDragACBack
            timer = 0f0
        end
    elseif phase == PhaseDragACBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, EdgeACEnd, EdgeACStart, HighlightColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseArcAToDragAPrimeForCPrime
            timer = 0f0
        end
    elseif phase == PhaseArcAToDragAPrimeForCPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            EdgeACStart, EdgeAPrimeCPrimeStart, 0.24f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragAPrimeCPrimeForward
            timer = 0f0
        end
    elseif phase == PhaseDragAPrimeCPrimeForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration,
            EdgeAPrimeCPrimeStart, EdgeAPrimeCPrimeEnd, HighlightColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseDragAPrimeCPrimeBack
            timer = 0f0
        end
    elseif phase == PhaseDragAPrimeCPrimeBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration,
            EdgeAPrimeCPrimeEnd, EdgeAPrimeCPrimeStart, HighlightColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseArcAPrimeToDragBForBC
            timer = 0f0
        end
    elseif phase == PhaseArcAPrimeToDragBForBC
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            EdgeAPrimeCPrimeStart, EdgeBCStart, 0.24f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragBCForward
            timer = 0f0
        end
    elseif phase == PhaseDragBCForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, EdgeBCStart, EdgeBCEnd, HighlightColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseDragBCBack
            timer = 0f0
        end
    elseif phase == PhaseDragBCBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, EdgeBCEnd, EdgeBCStart, HighlightColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseArcBToDragBPrimeForBPrimeCPrime
            timer = 0f0
        end
    elseif phase == PhaseArcBToDragBPrimeForBPrimeCPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            EdgeBCStart, EdgeBPrimeCPrimeStart, 0.24f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragBPrimeCPrimeForward
            timer = 0f0
        end
    elseif phase == PhaseDragBPrimeCPrimeForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration,
            EdgeBPrimeCPrimeStart, EdgeBPrimeCPrimeEnd, HighlightColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseDragBPrimeCPrimeBack
            timer = 0f0
        end
    elseif phase == PhaseDragBPrimeCPrimeBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration,
            EdgeBPrimeCPrimeEnd, EdgeBPrimeCPrimeStart, HighlightColor)

        timer += dt
        if timer >= DragDuration
            phase = PhasePenRiseBeforeCompass
            timer = 0f0
        end

    elseif phase == PhasePenRiseBeforeCompass
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ,
            EdgeBPrimeCPrimeStart[1], EdgeBPrimeCPrimeStart[2])

        timer += dt
        if timer >= PenLiftDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseCompassDescendAtA
            timer = 0f0
        end
    elseif phase == PhaseCompassDescendAtA
        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, DescendDuration, CompassTopZ,
            PointA[1], PointA[2], MarkerAStart[1], MarkerAStart[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseHighlightAngleAForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleAForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerAStart,
            AngleATheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightAngleABack
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleABack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerAEnd,
            -AngleATheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcAToAPrime
            timer = 0f0
        end
    elseif phase == PhaseCompassArcAToAPrime
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointA, PointAPrime,
            MarkerAStart, MarkerAPrimeStart,
            0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightAngleAPrimeForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleAPrimeForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerAPrimeStart,
            AngleAPrimeTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightAngleAPrimeBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleAPrimeBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerAPrimeEnd,
            -AngleAPrimeTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcAPrimeToB
            timer = 0f0
        end

    elseif phase == PhaseCompassArcAPrimeToB
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointAPrime, PointB,
            MarkerAPrimeStart, MarkerBStart,
            0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightAngleBForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleBForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointB, MarkerBStart,
            AngleBTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightAngleBBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleBBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointB, MarkerBEnd,
            -AngleBTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcBToBPrime
            timer = 0f0
        end
    elseif phase == PhaseCompassArcBToBPrime
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointB, PointBPrime,
            MarkerBStart, MarkerBPrimeStart,
            0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightAngleBPrimeForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleBPrimeForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointBPrime, MarkerBPrimeStart,
            AngleBPrimeTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightAngleBPrimeBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleBPrimeBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointBPrime, MarkerBPrimeEnd,
            -AngleBPrimeTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcBPrimeToC
            timer = 0f0
        end

    elseif phase == PhaseCompassArcBPrimeToC
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointBPrime, PointC,
            MarkerBPrimeStart, MarkerCStart,
            0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightAngleCForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleCForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointC, MarkerCStart,
            AngleCTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightAngleCBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleCBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointC, MarkerCEnd,
            -AngleCTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcCToCPrime
            timer = 0f0
        end
    elseif phase == PhaseCompassArcCToCPrime
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointC, PointCPrime,
            MarkerCStart, MarkerCPrimeStart,
            0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightAngleCPrimeForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleCPrimeForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointCPrime, MarkerCPrimeStart,
            AngleCPrimeTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightAngleCPrimeBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleCPrimeBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointCPrime, MarkerCPrimeEnd,
            -AngleCPrimeTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassLiftEnd
            timer = 0f0
        end

    elseif phase == PhaseCompassLiftEnd
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassLiftDuration, CompassTopZ,
            PointCPrime[1], PointCPrime[2], MarkerCPrimeStart[1], MarkerCPrimeStart[2])

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

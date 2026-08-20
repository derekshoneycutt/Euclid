module HilbertChapterOneTheorem11

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

export get_view_text, initialize, clean, loop

const PointA = [0.20f0, 0.66f0, 0f0]
const PointB = [0.50f0, 0.54f0, 0f0]
const PointC = [0.42f0, 0.82f0, 0f0]

const PointAPrime = [0.61f0, 0.20f0, 0f0]
const PointBPrime = [0.88f0, 0.09f0, 0f0]
const PointCPrime = [0.80f0, 0.37f0, 0f0]

const EdgeABStart = PointA
const EdgeABEnd = PointB
const EdgeBCStart = PointB
const EdgeBCEnd = PointC
const EdgeCAStart = PointC
const EdgeCAEnd = PointA

const EdgeAPrimeBPrimeStart = PointAPrime
const EdgeAPrimeBPrimeEnd = PointBPrime
const EdgeBPrimeCPrimeStart = PointBPrime
const EdgeBPrimeCPrimeEnd = PointCPrime
const EdgeCPrimeAPrimeStart = PointCPrime
const EdgeCPrimeAPrimeEnd = PointAPrime

const MarkerRadius = 0.08f0

const ThetaAAB = atan(PointB[2] - PointA[2], PointB[1] - PointA[1])
const ThetaAAC = atan(PointC[2] - PointA[2], PointC[1] - PointA[1])
const ThetaAPrimeAB = Float32(atan(
    PointBPrime[2] - PointAPrime[2], PointBPrime[1] - PointAPrime[1]))
const ThetaAPrimeAC = Float32(atan(
    PointCPrime[2] - PointAPrime[2], PointCPrime[1] - PointAPrime[1]))

const ThetaBBC = atan(PointC[2] - PointB[2], PointC[1] - PointB[1])
const ThetaBBA = atan(PointA[2] - PointB[2], PointA[1] - PointB[1])
const ThetaBPrimeBC = Float32(atan(
    PointCPrime[2] - PointBPrime[2], PointCPrime[1] - PointBPrime[1]))
const ThetaBPrimeBA = Float32(atan(
    PointAPrime[2] - PointBPrime[2], PointAPrime[1] - PointBPrime[1]))

const ThetaCCA = atan(PointA[2] - PointC[2], PointA[1] - PointC[1])
const ThetaCCB = atan(PointB[2] - PointC[2], PointB[1] - PointC[1])
const ThetaCPrimeCA = Float32(atan(
    PointAPrime[2] - PointCPrime[2], PointAPrime[1] - PointCPrime[1]))
const ThetaCPrimeCB = Float32(atan(
    PointBPrime[2] - PointCPrime[2], PointBPrime[1] - PointCPrime[1]))

const MarkerAStart = [
    PointA[1] + MarkerRadius * cos(ThetaAAB),
    PointA[2] + MarkerRadius * sin(ThetaAAB),
    0f0,
]
const MarkerAEnd = [
    PointA[1] + MarkerRadius * cos(ThetaAAC),
    PointA[2] + MarkerRadius * sin(ThetaAAC),
    0f0,
]
const MarkerAPrimeStart = [
    PointAPrime[1] + MarkerRadius * cos(ThetaAPrimeAB),
    PointAPrime[2] + MarkerRadius * sin(ThetaAPrimeAB),
    0f0,
]
const MarkerAPrimeEnd = [
    PointAPrime[1] + MarkerRadius * cos(ThetaAPrimeAC),
    PointAPrime[2] + MarkerRadius * sin(ThetaAPrimeAC),
    0f0,
]

const MarkerBStart = [
    PointB[1] + MarkerRadius * cos(ThetaBBC),
    PointB[2] + MarkerRadius * sin(ThetaBBC),
    0f0,
]
const MarkerBEnd = [
    PointB[1] + MarkerRadius * cos(ThetaBBA),
    PointB[2] + MarkerRadius * sin(ThetaBBA),
    0f0,
]
const MarkerBPrimeStart = [
    PointBPrime[1] + MarkerRadius * cos(ThetaBPrimeBC),
    PointBPrime[2] + MarkerRadius * sin(ThetaBPrimeBC),
    0f0,
]
const MarkerBPrimeEnd = [
    PointBPrime[1] + MarkerRadius * cos(ThetaBPrimeBA),
    PointBPrime[2] + MarkerRadius * sin(ThetaBPrimeBA),
    0f0,
]

const MarkerCStart = [
    PointC[1] + MarkerRadius * cos(ThetaCCA),
    PointC[2] + MarkerRadius * sin(ThetaCCA),
    0f0,
]
const MarkerCEnd = [
    PointC[1] + MarkerRadius * cos(ThetaCCB),
    PointC[2] + MarkerRadius * sin(ThetaCCB),
    0f0,
]
const MarkerCPrimeStart = [
    PointCPrime[1] + MarkerRadius * cos(ThetaCPrimeCA),
    PointCPrime[2] + MarkerRadius * sin(ThetaCPrimeCA),
    0f0,
]
const MarkerCPrimeEnd = [
    PointCPrime[1] + MarkerRadius * cos(ThetaCPrimeCB),
    PointCPrime[2] + MarkerRadius * sin(ThetaCPrimeCB),
    0f0,
]

const AngleATheta = ThetaAAC - ThetaAAB
const AngleAPrimeTheta = ThetaAPrimeAC - ThetaAPrimeAB
const AngleBTheta = ThetaBBA - ThetaBBC
const AngleBPrimeTheta = ThetaBPrimeBA - ThetaBPrimeBC
const AngleCTheta = ThetaCCB - ThetaCCA
const AngleCPrimeTheta = ThetaCPrimeCB - ThetaCPrimeCA

const LabelColor = :plum1
const HighlightColor = :lightgreen
const EdgeABColor = :steelblue
const EdgeBCColor = :palevioletred1
const EdgeCAColor = :khaki3
const EdgeAPrimeBPrimeColor = :steelblue
const EdgeBPrimeCPrimeColor = :palevioletred1
const EdgeCPrimeAPrimeColor = :khaki3

const EdgeBrush = 5f0
const PenTopZ = 1.4f0
const CompassTopZ = 1.4f0
const ToolResetOffscreenJoint1 = [0.50f0, 1.25f0, 1.55f0]
const ToolResetOffscreenJoint2 = [0.57f0, 1.25f0, 1.55f0]

const LabelAPoint = PointA + [-0.04f0, -0.04f0, 0f0]
const LabelBPoint = PointB + [0.03f0, -0.01f0, 0f0]
const LabelCPoint = PointC + [0.01f0, 0.05f0, 0f0]
const LabelAPrimePoint = PointAPrime + [-0.04f0, -0.04f0, 0f0]
const LabelBPrimePoint = PointBPrime + [0.03f0, -0.01f0, 0f0]
const LabelCPrimePoint = PointCPrime + [0.01f0, 0.05f0, 0f0]

const DescendDuration = 1.8f0
const DrawEdgeDuration = 2.2f0
const ArcMoveDuration = 1.35f0
const DragDuration = 1.25f0
const PenLiftDuration = 1.6f0
const CompassLiftDuration = 1.8f0
const CompassSweepDuration = 0.95f0
const FinalHoldDuration = 0.35f0

const MetaEdgeABHostId = 1
const MetaEdgeABJoint1Id = 2
const MetaEdgeABJoint2Id = 3
const MetaEdgeBCHostId = 11
const MetaEdgeBCJoint1Id = 12
const MetaEdgeBCJoint2Id = 13
const MetaEdgeCAHostId = 21
const MetaEdgeCAJoint1Id = 22
const MetaEdgeCAJoint2Id = 23

const MetaEdgeAPrimeBPrimeHostId = 31
const MetaEdgeAPrimeBPrimeJoint1Id = 32
const MetaEdgeAPrimeBPrimeJoint2Id = 33
const MetaEdgeBPrimeCPrimeHostId = 41
const MetaEdgeBPrimeCPrimeJoint1Id = 42
const MetaEdgeBPrimeCPrimeJoint2Id = 43
const MetaEdgeCPrimeAPrimeHostId = 51
const MetaEdgeCPrimeAPrimeJoint1Id = 52
const MetaEdgeCPrimeAPrimeJoint2Id = 53

const MetaLabelAId = 71
const MetaLabelBId = 72
const MetaLabelCId = 73
const MetaLabelAPrimeId = 74
const MetaLabelBPrimeId = 75
const MetaLabelCPrimeId = 76

const MetaPhase = 101
const MetaTimer = 102

const PhaseDescendToA = 0f0
const PhaseDrawAB = 1f0
const PhaseDrawBC = 2f0
const PhaseDrawCA = 3f0
const PhaseArcAToAPrime = 4f0
const PhaseDrawAPrimeBPrime = 5f0
const PhaseDrawBPrimeCPrime = 6f0
const PhaseDrawCPrimeAPrime = 7f0

const PhaseArcAPrimeToAForAB = 8f0
const PhaseDragABForward = 9f0
const PhaseDragABBack = 10f0
const PhaseArcAToAPrimeForPrimeAB = 11f0
const PhaseDragAPrimeBPrimeForward = 12f0
const PhaseDragAPrimeBPrimeBack = 13f0

const PhasePenRiseBeforeCompass = 14f0
const PhaseCompassDescendAtA = 15f0
const PhaseHighlightAngleAForward = 16f0
const PhaseHighlightAngleABack = 17f0
const PhaseCompassArcAToAPrime = 18f0
const PhaseHighlightAngleAPrimeForward = 19f0
const PhaseHighlightAngleAPrimeBack = 20f0
const PhaseCompassArcAPrimeToB = 21f0
const PhaseHighlightAngleBForward = 22f0
const PhaseHighlightAngleBBack = 23f0
const PhaseCompassArcBToBPrime = 24f0
const PhaseHighlightAngleBPrimeForward = 25f0
const PhaseHighlightAngleBPrimeBack = 26f0
const PhaseCompassArcBPrimeToC = 27f0
const PhaseHighlightAngleCForward = 28f0
const PhaseHighlightAngleCBack = 29f0
const PhaseCompassArcCToCPrime = 30f0
const PhaseHighlightAngleCPrimeForward = 31f0
const PhaseHighlightAngleCPrimeBack = 32f0
const PhaseCompassRise = 33f0

const PhasePenDescendAtAForAC = 34f0
const PhaseDragACForward = 35f0
const PhaseDragACBack = 36f0
const PhaseArcAToAPrimeForPrimeAC = 37f0
const PhaseDragAPrimeCPrimeForward = 38f0
const PhaseDragAPrimeCPrimeBack = 39f0
const PhaseArcAPrimeToBForBC = 40f0
const PhaseDragBCForward = 41f0
const PhaseDragBCBack = 42f0
const PhaseArcBToBPrimeForPrimeBC = 43f0
const PhaseDragBPrimeCPrimeForward = 44f0
const PhaseDragBPrimeCPrimeBack = 45f0
const PhasePenRiseEnd = 46f0
const PhaseFinalHold = 47f0


"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - Theorem 11 (Second theorem of congruence for triangles)

If in any two triangles one side and the two adjacent angles are respectively congruent, the triangles are congruent."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - Theorem 11 (Second theorem of congruence for triangles)}

If in any two triangles one side and the two adjacent angles are respectively congruent, the triangles are congruent."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset the state of the animation cycle back to the start of the animation"""
function reset_cycle_state(state_ptr::Ptr{Cvoid})
    edge_a_b_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeABHostId))
    edge_a_b_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeABJoint2Id))
    edge_b_c_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeBCHostId))
    edge_b_c_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeBCJoint2Id))
    edge_c_a_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeCAHostId))
    edge_c_a_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeCAJoint2Id))

    edge_a_prime_b_prime_host_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPrimeBPrimeHostId))
    edge_a_prime_b_prime_joint2_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPrimeBPrimeJoint2Id))
    edge_b_prime_c_prime_host_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeBPrimeCPrimeHostId))
    edge_b_prime_c_prime_joint2_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeBPrimeCPrimeJoint2Id))
    edge_c_prime_a_prime_host_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCPrimeAPrimeHostId))
    edge_c_prime_a_prime_joint2_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCPrimeAPrimeJoint2Id))

    label_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    label_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    label_c_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    label_a_prime_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLabelAPrimeId))
    label_b_prime_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLabelBPrimeId))
    label_c_prime_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLabelCPrimeId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [edge_a_b_host_id, edge_b_c_host_id, edge_c_a_host_id,
         edge_a_prime_b_prime_host_id, edge_b_prime_c_prime_host_id,
         edge_c_prime_a_prime_host_id,
         label_a_id, label_b_id, label_c_id,
         label_a_prime_id, label_b_prime_id, label_c_prime_id])

    OdinJuliaBridge.set_point_position(state_ptr, edge_a_b_joint2_id, EdgeABStart)
    OdinJuliaBridge.set_point_position(state_ptr, edge_b_c_joint2_id, EdgeBCStart)
    OdinJuliaBridge.set_point_position(state_ptr, edge_c_a_joint2_id, EdgeCAStart)
    OdinJuliaBridge.set_point_position(
        state_ptr, edge_a_prime_b_prime_joint2_id, EdgeAPrimeBPrimeStart)
    OdinJuliaBridge.set_point_position(
        state_ptr, edge_b_prime_c_prime_joint2_id, EdgeBPrimeCPrimeStart)
    OdinJuliaBridge.set_point_position(
        state_ptr, edge_c_prime_a_prime_joint2_id, EdgeCPrimeAPrimeStart)

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

    OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeABColor)
    OdinJuliaBridge.set_compass_active(state_ptr, 0, HighlightColor)
    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    edge_a_b = OdinJuliaBridge.create_new_line(
        state_ptr, EdgeABStart, EdgeABStart, EdgeABColor, 0f0)
    edge_b_c = OdinJuliaBridge.create_new_line(
        state_ptr, EdgeBCStart, EdgeBCStart, EdgeBCColor, 0f0)
    edge_c_a = OdinJuliaBridge.create_new_line(
        state_ptr, EdgeCAStart, EdgeCAStart, EdgeCAColor, 0f0)

    edge_a_prime_b_prime = OdinJuliaBridge.create_new_line(
        state_ptr, EdgeAPrimeBPrimeStart, EdgeAPrimeBPrimeStart,
        EdgeAPrimeBPrimeColor, 0f0)
    edge_b_prime_c_prime = OdinJuliaBridge.create_new_line(
        state_ptr, EdgeBPrimeCPrimeStart, EdgeBPrimeCPrimeStart,
        EdgeBPrimeCPrimeColor, 0f0)
    edge_c_prime_a_prime = OdinJuliaBridge.create_new_line(
        state_ptr, EdgeCPrimeAPrimeStart, EdgeCPrimeAPrimeStart,
        EdgeCPrimeAPrimeColor, 0f0)

    label_a = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', LabelAPoint, LabelColor, 16f0)
    label_b = OdinJuliaBridge.create_new_label(
        state_ptr, 'B', LabelBPoint, LabelColor, 16f0)
    label_c = OdinJuliaBridge.create_new_label(
        state_ptr, 'C', LabelCPoint, LabelColor, 16f0)
    label_a_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'A', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelAPrimePoint, LabelColor, 16f0)
    label_b_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'B', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelBPrimePoint, LabelColor, 16f0)
    label_c_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'C', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelCPrimePoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeABHostId, edge_a_b.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeABJoint1Id, edge_a_b.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeABJoint2Id, edge_a_b.joint2_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeBCHostId, edge_b_c.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeBCJoint1Id, edge_b_c.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeBCJoint2Id, edge_b_c.joint2_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeCAHostId, edge_c_a.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeCAJoint1Id, edge_c_a.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeCAJoint2Id, edge_c_a.joint2_id)

    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeAPrimeBPrimeHostId, edge_a_prime_b_prime.host_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeAPrimeBPrimeJoint1Id, edge_a_prime_b_prime.joint1_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeAPrimeBPrimeJoint2Id, edge_a_prime_b_prime.joint2_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeBPrimeCPrimeHostId, edge_b_prime_c_prime.host_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeBPrimeCPrimeJoint1Id, edge_b_prime_c_prime.joint1_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeBPrimeCPrimeJoint2Id, edge_b_prime_c_prime.joint2_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeCPrimeAPrimeHostId, edge_c_prime_a_prime.host_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeCPrimeAPrimeJoint1Id, edge_c_prime_a_prime.joint1_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeCPrimeAPrimeJoint2Id, edge_c_prime_a_prime.joint2_id)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAId, label_a.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBId, label_b.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelCId, label_c.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAPrimeId, label_a_prime.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBPrimeId, label_b_prime.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelCPrimeId, label_c_prime.index)

    reset_cycle_state(state_ptr)
end

"""Clean any extra animation data at the end of performance"""
function clean(state_ptr::Ptr{Cvoid})
end

"""Perform an iteration of the animation loop for this animation"""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    edge_a_b_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeABHostId))
    edge_a_b_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeABJoint1Id))
    edge_a_b_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeABJoint2Id))
    edge_b_c_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeBCHostId))
    edge_b_c_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeBCJoint1Id))
    edge_b_c_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeBCJoint2Id))
    edge_c_a_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeCAHostId))
    edge_c_a_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeCAJoint1Id))
    edge_c_a_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeCAJoint2Id))

    edge_a_prime_b_prime_host_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPrimeBPrimeHostId))
    edge_a_prime_b_prime_joint1_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPrimeBPrimeJoint1Id))
    edge_a_prime_b_prime_joint2_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPrimeBPrimeJoint2Id))
    edge_b_prime_c_prime_host_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeBPrimeCPrimeHostId))
    edge_b_prime_c_prime_joint1_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeBPrimeCPrimeJoint1Id))
    edge_b_prime_c_prime_joint2_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeBPrimeCPrimeJoint2Id))
    edge_c_prime_a_prime_host_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCPrimeAPrimeHostId))
    edge_c_prime_a_prime_joint1_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCPrimeAPrimeJoint1Id))
    edge_c_prime_a_prime_joint2_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCPrimeAPrimeJoint2Id))

    label_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    label_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    label_c_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    label_a_prime_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLabelAPrimeId))
    label_b_prime_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLabelBPrimeId))
    label_c_prime_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLabelCPrimeId))

    if edge_a_b_host_id < 0 || edge_b_c_host_id < 0 || edge_c_a_host_id < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescendToA
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, PointA[1], PointA[2])
        timer += dt
        if timer >= DescendDuration
            OdinJuliaBridge.show_point(state_ptr, label_a_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeABColor)
            phase = PhaseDrawAB
            timer = 0f0
        end
    elseif phase == PhaseDrawAB
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawEdgeDuration,
            EdgeABStart, EdgeABEnd;
            penbrush=EdgeBrush,
            pencolor=EdgeABColor,
            line_host_id=edge_a_b_host_id,
            line_joint1_id=edge_a_b_joint1_id,
            line_joint2_id=edge_a_b_joint2_id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, label_b_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeBCColor)
            phase = PhaseDrawBC
            timer = 0f0
        end
    elseif phase == PhaseDrawBC
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawEdgeDuration,
            EdgeBCStart, EdgeBCEnd;
            penbrush=EdgeBrush,
            pencolor=EdgeBCColor,
            line_host_id=edge_b_c_host_id,
            line_joint1_id=edge_b_c_joint1_id,
            line_joint2_id=edge_b_c_joint2_id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, label_c_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeCAColor)
            phase = PhaseDrawCA
            timer = 0f0
        end
    elseif phase == PhaseDrawCA
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawEdgeDuration,
            EdgeCAStart, EdgeCAEnd;
            penbrush=EdgeBrush,
            pencolor=EdgeCAColor,
            line_host_id=edge_c_a_host_id,
            line_joint1_id=edge_c_a_joint1_id,
            line_joint2_id=edge_c_a_joint2_id)
        timer += dt
        if timer >= DrawEdgeDuration
            phase = PhaseArcAToAPrime
            timer = 0f0
        end
    elseif phase == PhaseArcAToAPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointA, PointAPrime, 0.27f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.show_point(state_ptr, label_a_prime_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeAPrimeBPrimeColor)
            phase = PhaseDrawAPrimeBPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawAPrimeBPrime
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawEdgeDuration,
            EdgeAPrimeBPrimeStart, EdgeAPrimeBPrimeEnd;
            penbrush=EdgeBrush,
            pencolor=EdgeAPrimeBPrimeColor,
            line_host_id=edge_a_prime_b_prime_host_id,
            line_joint1_id=edge_a_prime_b_prime_joint1_id,
            line_joint2_id=edge_a_prime_b_prime_joint2_id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, label_b_prime_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeBPrimeCPrimeColor)
            phase = PhaseDrawBPrimeCPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawBPrimeCPrime
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawEdgeDuration,
            EdgeBPrimeCPrimeStart, EdgeBPrimeCPrimeEnd;
            penbrush=EdgeBrush,
            pencolor=EdgeBPrimeCPrimeColor,
            line_host_id=edge_b_prime_c_prime_host_id,
            line_joint1_id=edge_b_prime_c_prime_joint1_id,
            line_joint2_id=edge_b_prime_c_prime_joint2_id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, label_c_prime_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeCPrimeAPrimeColor)
            phase = PhaseDrawCPrimeAPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawCPrimeAPrime
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawEdgeDuration,
            EdgeCPrimeAPrimeStart, EdgeCPrimeAPrimeEnd;
            penbrush=EdgeBrush,
            pencolor=EdgeCPrimeAPrimeColor,
            line_host_id=edge_c_prime_a_prime_host_id,
            line_joint1_id=edge_c_prime_a_prime_joint1_id,
            line_joint2_id=edge_c_prime_a_prime_joint2_id)
        timer += dt
        if timer >= DrawEdgeDuration
            phase = PhaseArcAPrimeToAForAB
            timer = 0f0
        end

    elseif phase == PhaseArcAPrimeToAForAB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointAPrime, PointA, 0.24f0, 1, :none)
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
            phase = PhaseArcAToAPrimeForPrimeAB
            timer = 0f0
        end
    elseif phase == PhaseArcAToAPrimeForPrimeAB
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
            phase = PhasePenRiseBeforeCompass
            timer = 0f0
        end

    elseif phase == PhasePenRiseBeforeCompass
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ, PointAPrime[1], PointAPrime[2])
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
            PointA, MarkerAStart, AngleATheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightAngleABack
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleABack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerAEnd, -AngleATheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcAToAPrime
            timer = 0f0
        end
    elseif phase == PhaseCompassArcAToAPrime
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointA, PointAPrime,
            MarkerAStart, MarkerAPrimeStart)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightAngleAPrimeForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleAPrimeForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerAPrimeStart, AngleAPrimeTheta,
            MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightAngleAPrimeBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleAPrimeBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerAPrimeEnd, -AngleAPrimeTheta,
            MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcAPrimeToB
            timer = 0f0
        end

    elseif phase == PhaseCompassArcAPrimeToB
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointAPrime, PointB,
            MarkerAPrimeStart, MarkerBStart)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightAngleBForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleBForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointB, MarkerBStart, AngleBTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightAngleBBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleBBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointB, MarkerBEnd, -AngleBTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcBToBPrime
            timer = 0f0
        end
    elseif phase == PhaseCompassArcBToBPrime
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointB, PointBPrime,
            MarkerBStart, MarkerBPrimeStart)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightAngleBPrimeForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleBPrimeForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointBPrime, MarkerBPrimeStart, AngleBPrimeTheta,
            MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightAngleBPrimeBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleBPrimeBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointBPrime, MarkerBPrimeEnd, -AngleBPrimeTheta,
            MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcBPrimeToC
            timer = 0f0
        end
    elseif phase == PhaseCompassArcBPrimeToC
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointBPrime, PointC,
            MarkerBPrimeStart, MarkerCStart)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightAngleCForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleCForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointC, MarkerCStart, AngleCTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightAngleCBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleCBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointC, MarkerCEnd, -AngleCTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcCToCPrime
            timer = 0f0
        end
    elseif phase == PhaseCompassArcCToCPrime
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointC, PointCPrime,
            MarkerCStart, MarkerCPrimeStart)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightAngleCPrimeForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleCPrimeForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointCPrime, MarkerCPrimeStart, AngleCPrimeTheta,
            MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightAngleCPrimeBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleCPrimeBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointCPrime, MarkerCPrimeEnd, -AngleCPrimeTheta,
            MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassRise
            timer = 0f0
        end
    elseif phase == PhaseCompassRise
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassLiftDuration, CompassTopZ,
            PointCPrime[1], PointCPrime[2], MarkerCPrimeStart[1], MarkerCPrimeStart[2])
        timer += dt
        if timer >= CompassLiftDuration
            OdinJuliaBridge.hide_compass(state_ptr)
            phase = PhasePenDescendAtAForAC
            timer = 0f0
        end

    elseif phase == PhasePenDescendAtAForAC
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, PointA[1], PointA[2])
        timer += dt
        if timer >= DescendDuration
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
            phase = PhaseArcAPrimeToBForBC
            timer = 0f0
        end
    elseif phase == PhaseArcAPrimeToBForBC
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointAPrime, PointB, 0.24f0, 1, :none)
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
            state_ptr, timer, ArcMoveDuration, PointB, PointBPrime, 0.24f0, 1, :none)
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
            phase = PhasePenRiseEnd
            timer = 0f0
        end
    elseif phase == PhasePenRiseEnd
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ, PointBPrime[1], PointBPrime[2])
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

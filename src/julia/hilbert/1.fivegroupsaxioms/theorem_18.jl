module HilbertChapterOneTheorem18

using ..OdinJuliaBridge
using ..EuclidAnimations

export get_view_text, initialize, clean, loop

const PointA = [0.18f0, 0.82f0, 0f0]
const PointB = [0.46f0, 0.82f0, 0f0]
const PointC = [0.46f0, 0.50f0, 0f0]
const PointD = [0.18f0, 0.50f0, 0f0]
const PointP = [0.07f0, 0.30f0, 0f0]

const PointAPrime = [0.65f0, 0.82f0, 0f0]
const PointBPrime = [0.93f0, 0.82f0, 0f0]
const PointCPrime = [0.93f0, 0.50f0, 0f0]
const PointDPrime = [0.65f0, 0.50f0, 0f0]
const PointPPrime = [0.54f0, 0.30f0, 0f0]

const EdgeBrush = 5f0
const PointBrush = 6f0
const LabelColor = :plum1
const HighlightColor = :lightgreen

const ColorAB = :steelblue
const ColorBC = :palevioletred1
const ColorCD = :khaki3
const ColorDA = :grey60
const ColorAux = :khaki3
const ColorPointP = :grey60

const PenTopZ = 1.4f0
const CompassTopZ = 1.4f0
const ToolResetOffscreenJoint1 = [0.50f0, 1.25f0, 1.55f0]
const ToolResetOffscreenJoint2 = [0.57f0, 1.25f0, 1.55f0]

const DescendDuration = 1.8f0
const DrawDuration = 2.1f0
const DrawPointDuration = 1.4f0
const ArcMoveDuration = 1.35f0
const DragDuration = 1.1f0
const PenLiftDuration = 1.6f0
const CompassLiftDuration = 1.8f0
const FinalHoldDuration = 0.35f0

const LabelAPoint = PointA + [-0.03f0, 0.03f0, 0f0]
const LabelBPoint = PointB + [0.05f0, 0.06f0, 0f0]
const LabelCPoint = PointC + [0.02f0, -0.04f0, 0f0]
const LabelDPoint = PointD + [-0.03f0, -0.04f0, 0f0]
const LabelPPoint = PointP + [-0.04f0, -0.03f0, 0f0]

const LabelAPrimePoint = PointAPrime + [-0.03f0, 0.03f0, 0f0]
const LabelBPrimePoint = PointBPrime + [0.05f0, 0.06f0, 0f0]
const LabelCPrimePoint = PointCPrime + [0.02f0, -0.04f0, 0f0]
const LabelDPrimePoint = PointDPrime + [-0.03f0, -0.04f0, 0f0]
const LabelPPrimePoint = PointPPrime + [-0.04f0, -0.03f0, 0f0]

const MetaEdgeABHostId = 1
const MetaEdgeABJoint1Id = 2
const MetaEdgeABJoint2Id = 3
const MetaEdgeBCHostId = 11
const MetaEdgeBCJoint1Id = 12
const MetaEdgeBCJoint2Id = 13
const MetaEdgeCDHostId = 21
const MetaEdgeCDJoint1Id = 22
const MetaEdgeCDJoint2Id = 23
const MetaEdgeDAHostId = 31
const MetaEdgeDAJoint1Id = 32
const MetaEdgeDAJoint2Id = 33

const MetaEdgeAPrimeBPrimeHostId = 41
const MetaEdgeAPrimeBPrimeJoint1Id = 42
const MetaEdgeAPrimeBPrimeJoint2Id = 43
const MetaEdgeBPrimeCPrimeHostId = 51
const MetaEdgeBPrimeCPrimeJoint1Id = 52
const MetaEdgeBPrimeCPrimeJoint2Id = 53
const MetaEdgeCPrimeDPrimeHostId = 61
const MetaEdgeCPrimeDPrimeJoint1Id = 62
const MetaEdgeCPrimeDPrimeJoint2Id = 63
const MetaEdgeDPrimeAPrimeHostId = 71
const MetaEdgeDPrimeAPrimeJoint1Id = 72
const MetaEdgeDPrimeAPrimeJoint2Id = 73

const MetaEdgeAPHostId = 81
const MetaEdgeAPJoint1Id = 82
const MetaEdgeAPJoint2Id = 83
const MetaEdgePCHostId = 91
const MetaEdgePCJoint1Id = 92
const MetaEdgePCJoint2Id = 93
const MetaEdgeAPrimePPrimeHostId = 101
const MetaEdgeAPrimePPrimeJoint1Id = 102
const MetaEdgeAPrimePPrimeJoint2Id = 103
const MetaEdgePPrimeCPrimeHostId = 111
const MetaEdgePPrimeCPrimeJoint1Id = 112
const MetaEdgePPrimeCPrimeJoint2Id = 113

const MetaPointPId = 121
const MetaPointPPrimeId = 122

const MetaLabelAId = 131
const MetaLabelBId = 132
const MetaLabelCId = 133
const MetaLabelDId = 134
const MetaLabelPId = 135
const MetaLabelAPrimeId = 136
const MetaLabelBPrimeId = 137
const MetaLabelCPrimeId = 138
const MetaLabelDPrimeId = 139
const MetaLabelPPrimeId = 140

const MetaPhase = 201
const MetaTimer = 202

const PhaseDescendA = 0f0
const PhaseDrawAB = 1f0
const PhaseDrawBC = 2f0
const PhaseDrawCD = 3f0
const PhaseDrawDA = 4f0
const PhaseArcToAPrime = 5f0
const PhaseDrawAPrimeBPrime = 6f0
const PhaseDrawBPrimeCPrime = 7f0
const PhaseDrawCPrimeDPrime = 8f0
const PhaseDrawDPrimeAPrime = 9f0
const PhaseArcToP = 10f0
const PhaseDrawP = 11f0
const PhaseArcToPPrime = 12f0
const PhaseDrawPPrime = 13f0
const PhaseArcToAForAP = 14f0
const PhaseDrawAP = 15f0
const PhaseArcToPForPC = 16f0
const PhaseDrawPC = 17f0
const PhaseArcToAPrimeForAPrimePPrime = 18f0
const PhaseDrawAPrimePPrime = 19f0
const PhaseArcToPPrimeForPPrimeCPrime = 20f0
const PhaseDrawPPrimeCPrime = 21f0
const PhasePenRiseBeforeHighlights = 22f0

const PhaseCompassDescendAB = 23f0
const PhaseHighlightPath1ABForward = 24f0
const PhaseHighlightPath1BCForward = 25f0
const PhaseHighlightPath1CPForward = 26f0
const PhaseHighlightPath1PAForward = 27f0
const PhaseHighlightPath1APBack = 28f0
const PhaseHighlightPath1PCBack = 29f0
const PhaseHighlightPath1CBBack = 30f0
const PhaseHighlightPath1BABack = 31f0

const PhaseCompassArcToPrime = 32f0
const PhaseHighlightPath2ABForward = 33f0
const PhaseHighlightPath2BCForward = 34f0
const PhaseHighlightPath2CPForward = 35f0
const PhaseHighlightPath2PAForward = 36f0
const PhaseHighlightPath2APBack = 37f0
const PhaseHighlightPath2PCBack = 38f0
const PhaseHighlightPath2CBBack = 39f0
const PhaseHighlightPath2BABack = 40f0
const PhaseCompassRiseEnd = 41f0
const PhaseFinalHold = 42f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """David Hilbert - Foundations of Geometry - Theorem 18

If (A, B, C, ...) and (A', B', C', ...) are congruent figures and P represents any arbitrary point, then there can always be found a point P' so that the two figures (A, B, C, ..., P) and (A', B', C', ..., P') shall likewise be congruent. If the figure (A, B, C, ..., P) contains at least four points not lying in the same plane, then the determination of P' can be made in but one way.

This theorem contains an important result; namely, that all the facts concerning space which have reference to congruence, that is to say, to displacements in space, are (by the addition of the axioms of groups I and II) exclusively the consequences of the six linear and plane axioms mentioned above. Hence, it is not necessary to assume the axiom of parallels in order to establish these facts."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    edgeABHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeABHostId))
    edgeABJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeABJoint2Id))
    edgeBCHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeBCHostId))
    edgeBCJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeBCJoint2Id))
    edgeCDHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCDHostId))
    edgeCDJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCDJoint2Id))
    edgeDAHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeDAHostId))
    edgeDAJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeDAJoint2Id))

    edgeAPrimeBPrimeHostId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPrimeBPrimeHostId))
    edgeAPrimeBPrimeJoint2Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPrimeBPrimeJoint2Id))
    edgeBPrimeCPrimeHostId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeBPrimeCPrimeHostId))
    edgeBPrimeCPrimeJoint2Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeBPrimeCPrimeJoint2Id))
    edgeCPrimeDPrimeHostId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCPrimeDPrimeHostId))
    edgeCPrimeDPrimeJoint2Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCPrimeDPrimeJoint2Id))
    edgeDPrimeAPrimeHostId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeDPrimeAPrimeHostId))
    edgeDPrimeAPrimeJoint2Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeDPrimeAPrimeJoint2Id))

    edgeAPHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPHostId))
    edgeAPJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPJoint2Id))
    edgePCHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgePCHostId))
    edgePCJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgePCJoint2Id))
    edgeAPrimePPrimeHostId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPrimePPrimeHostId))
    edgeAPrimePPrimeJoint2Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPrimePPrimeJoint2Id))
    edgePPrimeCPrimeHostId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgePPrimeCPrimeHostId))
    edgePPrimeCPrimeJoint2Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgePPrimeCPrimeJoint2Id))

    pointPId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointPId))
    pointPPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointPPrimeId))

    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labelCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    labelDId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDId))
    labelPId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelPId))
    labelAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAPrimeId))
    labelBPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBPrimeId))
    labelCPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCPrimeId))
    labelDPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDPrimeId))
    labelPPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelPPrimeId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [edgeABHostId, edgeBCHostId, edgeCDHostId, edgeDAHostId,
         edgeAPrimeBPrimeHostId, edgeBPrimeCPrimeHostId,
         edgeCPrimeDPrimeHostId, edgeDPrimeAPrimeHostId,
         edgeAPHostId, edgePCHostId, edgeAPrimePPrimeHostId, edgePPrimeCPrimeHostId,
         pointPId, pointPPrimeId,
         labelAId, labelBId, labelCId, labelDId, labelPId,
         labelAPrimeId, labelBPrimeId, labelCPrimeId, labelDPrimeId, labelPPrimeId])

    OdinJuliaBridge.set_point_position(state_ptr, edgeABJoint2Id, PointA)
    OdinJuliaBridge.set_point_position(state_ptr, edgeBCJoint2Id, PointB)
    OdinJuliaBridge.set_point_position(state_ptr, edgeCDJoint2Id, PointC)
    OdinJuliaBridge.set_point_position(state_ptr, edgeDAJoint2Id, PointD)

    OdinJuliaBridge.set_point_position(state_ptr, edgeAPrimeBPrimeJoint2Id, PointAPrime)
    OdinJuliaBridge.set_point_position(state_ptr, edgeBPrimeCPrimeJoint2Id, PointBPrime)
    OdinJuliaBridge.set_point_position(state_ptr, edgeCPrimeDPrimeJoint2Id, PointCPrime)
    OdinJuliaBridge.set_point_position(state_ptr, edgeDPrimeAPrimeJoint2Id, PointDPrime)

    OdinJuliaBridge.set_point_position(state_ptr, edgeAPJoint2Id, PointA)
    OdinJuliaBridge.set_point_position(state_ptr, edgePCJoint2Id, PointP)
    OdinJuliaBridge.set_point_position(state_ptr, edgeAPrimePPrimeJoint2Id, PointAPrime)
    OdinJuliaBridge.set_point_position(state_ptr, edgePPrimeCPrimeJoint2Id, PointPPrime)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescendA)
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

    OdinJuliaBridge.set_pen_active(state_ptr, 0, ColorAB)
    OdinJuliaBridge.set_compass_active(state_ptr, 0, HighlightColor)
    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    edgeAB = OdinJuliaBridge.create_new_line(state_ptr, PointA, PointA, ColorAB, 0f0)
    edgeBC = OdinJuliaBridge.create_new_line(state_ptr, PointB, PointB, ColorBC, 0f0)
    edgeCD = OdinJuliaBridge.create_new_line(state_ptr, PointC, PointC, ColorCD, 0f0)
    edgeDA = OdinJuliaBridge.create_new_line(state_ptr, PointD, PointD, ColorDA, 0f0)

    edgeAPrimeBPrime = OdinJuliaBridge.create_new_line(
        state_ptr, PointAPrime, PointAPrime, ColorAB, 0f0)
    edgeBPrimeCPrime = OdinJuliaBridge.create_new_line(
        state_ptr, PointBPrime, PointBPrime, ColorBC, 0f0)
    edgeCPrimeDPrime = OdinJuliaBridge.create_new_line(
        state_ptr, PointCPrime, PointCPrime, ColorCD, 0f0)
    edgeDPrimeAPrime = OdinJuliaBridge.create_new_line(
        state_ptr, PointDPrime, PointDPrime, ColorDA, 0f0)

    edgeAP = OdinJuliaBridge.create_new_line(state_ptr, PointA, PointA, ColorAux, 0f0)
    edgePC = OdinJuliaBridge.create_new_line(state_ptr, PointP, PointP, ColorAux, 0f0)
    edgeAPrimePPrime = OdinJuliaBridge.create_new_line(
        state_ptr, PointAPrime, PointAPrime, ColorAux, 0f0)
    edgePPrimeCPrime = OdinJuliaBridge.create_new_line(
        state_ptr, PointPPrime, PointPPrime, ColorAux, 0f0)

    pointP = OdinJuliaBridge.create_new_point(state_ptr, PointP, ColorPointP, 0f0)
    pointPPrime = OdinJuliaBridge.create_new_point(state_ptr, PointPPrime, ColorPointP, 0f0)

    labelA = OdinJuliaBridge.create_new_label(state_ptr, 'A', LabelAPoint, LabelColor, 16f0)
    labelB = OdinJuliaBridge.create_new_label(state_ptr, 'B', LabelBPoint, LabelColor, 16f0)
    labelC = OdinJuliaBridge.create_new_label(state_ptr, 'C', LabelCPoint, LabelColor, 16f0)
    labelD = OdinJuliaBridge.create_new_label(state_ptr, 'D', LabelDPoint, LabelColor, 16f0)
    labelP = OdinJuliaBridge.create_new_label(state_ptr, 'P', LabelPPoint, LabelColor, 16f0)

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
    labelPPrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'P', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelPPrimePoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeABHostId, Float32(edgeAB.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeABJoint1Id, Float32(edgeAB.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeABJoint2Id, Float32(edgeAB.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeBCHostId, Float32(edgeBC.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeBCJoint1Id, Float32(edgeBC.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeBCJoint2Id, Float32(edgeBC.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeCDHostId, Float32(edgeCD.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeCDJoint1Id, Float32(edgeCD.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeCDJoint2Id, Float32(edgeCD.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeDAHostId, Float32(edgeDA.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeDAJoint1Id, Float32(edgeDA.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeDAJoint2Id, Float32(edgeDA.joint2Id))

    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeAPrimeBPrimeHostId, Float32(edgeAPrimeBPrime.hostId))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeAPrimeBPrimeJoint1Id, Float32(edgeAPrimeBPrime.joint1Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeAPrimeBPrimeJoint2Id, Float32(edgeAPrimeBPrime.joint2Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeBPrimeCPrimeHostId, Float32(edgeBPrimeCPrime.hostId))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeBPrimeCPrimeJoint1Id, Float32(edgeBPrimeCPrime.joint1Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeBPrimeCPrimeJoint2Id, Float32(edgeBPrimeCPrime.joint2Id))
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

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeAPHostId, Float32(edgeAP.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeAPJoint1Id, Float32(edgeAP.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeAPJoint2Id, Float32(edgeAP.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgePCHostId, Float32(edgePC.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgePCJoint1Id, Float32(edgePC.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgePCJoint2Id, Float32(edgePC.joint2Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeAPrimePPrimeHostId, Float32(edgeAPrimePPrime.hostId))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeAPrimePPrimeJoint1Id, Float32(edgeAPrimePPrime.joint1Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeAPrimePPrimeJoint2Id, Float32(edgeAPrimePPrime.joint2Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgePPrimeCPrimeHostId, Float32(edgePPrimeCPrime.hostId))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgePPrimeCPrimeJoint1Id, Float32(edgePPrimeCPrime.joint1Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgePPrimeCPrimeJoint2Id, Float32(edgePPrimeCPrime.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointPId, Float32(pointP.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointPPrimeId, Float32(pointPPrime.index))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAId, Float32(labelA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBId, Float32(labelB.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelCId, Float32(labelC.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelDId, Float32(labelD.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelPId, Float32(labelP.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAPrimeId, Float32(labelAPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBPrimeId, Float32(labelBPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelCPrimeId, Float32(labelCPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelDPrimeId, Float32(labelDPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelPPrimeId, Float32(labelPPrime.index))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    edgeABHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeABHostId))
    edgeABJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeABJoint1Id))
    edgeABJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeABJoint2Id))
    edgeBCHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeBCHostId))
    edgeBCJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeBCJoint1Id))
    edgeBCJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeBCJoint2Id))
    edgeCDHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCDHostId))
    edgeCDJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCDJoint1Id))
    edgeCDJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCDJoint2Id))
    edgeDAHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeDAHostId))
    edgeDAJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeDAJoint1Id))
    edgeDAJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeDAJoint2Id))

    edgeAPrimeBPrimeHostId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPrimeBPrimeHostId))
    edgeAPrimeBPrimeJoint1Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPrimeBPrimeJoint1Id))
    edgeAPrimeBPrimeJoint2Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPrimeBPrimeJoint2Id))
    edgeBPrimeCPrimeHostId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeBPrimeCPrimeHostId))
    edgeBPrimeCPrimeJoint1Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeBPrimeCPrimeJoint1Id))
    edgeBPrimeCPrimeJoint2Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeBPrimeCPrimeJoint2Id))
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

    edgeAPHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPHostId))
    edgeAPJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPJoint1Id))
    edgeAPJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPJoint2Id))
    edgePCHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgePCHostId))
    edgePCJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgePCJoint1Id))
    edgePCJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgePCJoint2Id))
    edgeAPrimePPrimeHostId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPrimePPrimeHostId))
    edgeAPrimePPrimeJoint1Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPrimePPrimeJoint1Id))
    edgeAPrimePPrimeJoint2Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPrimePPrimeJoint2Id))
    edgePPrimeCPrimeHostId = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgePPrimeCPrimeHostId))
    edgePPrimeCPrimeJoint1Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgePPrimeCPrimeJoint1Id))
    edgePPrimeCPrimeJoint2Id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgePPrimeCPrimeJoint2Id))

    pointPId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointPId))
    pointPPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointPPrimeId))

    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labelCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    labelDId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDId))
    labelPId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelPId))
    labelAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAPrimeId))
    labelBPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBPrimeId))
    labelCPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCPrimeId))
    labelDPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDPrimeId))
    labelPPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelPPrimeId))

    if edgeABHostId < 0 || edgeAPrimeBPrimeHostId < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescendA
        EuclidAnimations.animate_pen_descend(state_ptr, timer, DescendDuration, PenTopZ, PointA[1], PointA[2])
        timer += dt
        if timer >= DescendDuration
            OdinJuliaBridge.show_point(state_ptr, labelAId)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, ColorAB)
            phase = PhaseDrawAB
            timer = 0f0
        end
    elseif phase == PhaseDrawAB
        EuclidAnimations.animate_draw_line(state_ptr, timer, DrawDuration, PointA, PointB,
            EdgeBrush, ColorAB, edgeABHostId, edgeABJoint1Id, edgeABJoint2Id)
        timer += dt
        if timer >= DrawDuration
            OdinJuliaBridge.show_point(state_ptr, labelBId)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, ColorBC)
            phase = PhaseDrawBC
            timer = 0f0
        end
    elseif phase == PhaseDrawBC
        EuclidAnimations.animate_draw_line(state_ptr, timer, DrawDuration, PointB, PointC,
            EdgeBrush, ColorBC, edgeBCHostId, edgeBCJoint1Id, edgeBCJoint2Id)
        timer += dt
        if timer >= DrawDuration
            OdinJuliaBridge.show_point(state_ptr, labelCId)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, ColorCD)
            phase = PhaseDrawCD
            timer = 0f0
        end
    elseif phase == PhaseDrawCD
        EuclidAnimations.animate_draw_line(state_ptr, timer, DrawDuration, PointC, PointD,
            EdgeBrush, ColorCD, edgeCDHostId, edgeCDJoint1Id, edgeCDJoint2Id)
        timer += dt
        if timer >= DrawDuration
            OdinJuliaBridge.show_point(state_ptr, labelDId)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, ColorDA)
            phase = PhaseDrawDA
            timer = 0f0
        end
    elseif phase == PhaseDrawDA
        EuclidAnimations.animate_draw_line(state_ptr, timer, DrawDuration, PointD, PointA,
            EdgeBrush, ColorDA, edgeDAHostId, edgeDAJoint1Id, edgeDAJoint2Id)
        timer += dt
        if timer >= DrawDuration
            phase = PhaseArcToAPrime
            timer = 0f0
        end

    elseif phase == PhaseArcToAPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointA, PointAPrime, 0.24f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.show_point(state_ptr, labelAPrimeId)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, ColorAB)
            phase = PhaseDrawAPrimeBPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawAPrimeBPrime
        EuclidAnimations.animate_draw_line(state_ptr, timer, DrawDuration, PointAPrime, PointBPrime,
            EdgeBrush, ColorAB,
            edgeAPrimeBPrimeHostId, edgeAPrimeBPrimeJoint1Id, edgeAPrimeBPrimeJoint2Id)
        timer += dt
        if timer >= DrawDuration
            OdinJuliaBridge.show_point(state_ptr, labelBPrimeId)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, ColorBC)
            phase = PhaseDrawBPrimeCPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawBPrimeCPrime
        EuclidAnimations.animate_draw_line(state_ptr, timer, DrawDuration, PointBPrime, PointCPrime,
            EdgeBrush, ColorBC,
            edgeBPrimeCPrimeHostId, edgeBPrimeCPrimeJoint1Id, edgeBPrimeCPrimeJoint2Id)
        timer += dt
        if timer >= DrawDuration
            OdinJuliaBridge.show_point(state_ptr, labelCPrimeId)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, ColorCD)
            phase = PhaseDrawCPrimeDPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawCPrimeDPrime
        EuclidAnimations.animate_draw_line(state_ptr, timer, DrawDuration, PointCPrime, PointDPrime,
            EdgeBrush, ColorCD,
            edgeCPrimeDPrimeHostId, edgeCPrimeDPrimeJoint1Id, edgeCPrimeDPrimeJoint2Id)
        timer += dt
        if timer >= DrawDuration
            OdinJuliaBridge.show_point(state_ptr, labelDPrimeId)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, ColorDA)
            phase = PhaseDrawDPrimeAPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawDPrimeAPrime
        EuclidAnimations.animate_draw_line(state_ptr, timer, DrawDuration, PointDPrime, PointAPrime,
            EdgeBrush, ColorDA,
            edgeDPrimeAPrimeHostId, edgeDPrimeAPrimeJoint1Id, edgeDPrimeAPrimeJoint2Id)
        timer += dt
        if timer >= DrawDuration
            phase = PhaseArcToP
            timer = 0f0
        end

    elseif phase == PhaseArcToP
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointAPrime, PointP, 0.24f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawP
            timer = 0f0
        end
    elseif phase == PhaseDrawP
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointP, PointBrush, ColorPointP, pointPId)
        timer += dt
        if timer >= DrawPointDuration
            OdinJuliaBridge.show_point(state_ptr, labelPId)
            phase = PhaseArcToPPrime
            timer = 0f0
        end
    elseif phase == PhaseArcToPPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointP, PointPPrime, 0.24f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawPPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawPPrime
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointPPrime, PointBrush, ColorPointP, pointPPrimeId)
        timer += dt
        if timer >= DrawPointDuration
            OdinJuliaBridge.show_point(state_ptr, labelPPrimeId)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, ColorAux)
            phase = PhaseArcToAForAP
            timer = 0f0
        end

    elseif phase == PhaseArcToAForAP
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointPPrime, PointA, 0.24f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawAP
            timer = 0f0
        end
    elseif phase == PhaseDrawAP
        EuclidAnimations.animate_draw_line(state_ptr, timer, DrawDuration, PointA, PointP,
            EdgeBrush, ColorAux, edgeAPHostId, edgeAPJoint1Id, edgeAPJoint2Id)
        timer += dt
        if timer >= DrawDuration
            phase = PhaseDrawPC
            timer = 0f0
        end
    elseif phase == PhaseDrawPC
        EuclidAnimations.animate_draw_line(state_ptr, timer, DrawDuration, PointP, PointC,
            EdgeBrush, ColorAux, edgePCHostId, edgePCJoint1Id, edgePCJoint2Id)
        timer += dt
        if timer >= DrawDuration
            phase = PhaseArcToAPrimeForAPrimePPrime
            timer = 0f0
        end
    elseif phase == PhaseArcToAPrimeForAPrimePPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointC, PointAPrime, 0.24f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawAPrimePPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawAPrimePPrime
        EuclidAnimations.animate_draw_line(state_ptr, timer, DrawDuration, PointAPrime, PointPPrime,
            EdgeBrush, ColorAux,
            edgeAPrimePPrimeHostId, edgeAPrimePPrimeJoint1Id, edgeAPrimePPrimeJoint2Id)
        timer += dt
        if timer >= DrawDuration
            phase = PhaseDrawPPrimeCPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawPPrimeCPrime
        EuclidAnimations.animate_draw_line(state_ptr, timer, DrawDuration, PointPPrime, PointCPrime,
            EdgeBrush, ColorAux,
            edgePPrimeCPrimeHostId, edgePPrimeCPrimeJoint1Id, edgePPrimeCPrimeJoint2Id)
        timer += dt
        if timer >= DrawDuration
            phase = PhasePenRiseBeforeHighlights
            timer = 0f0
        end
    elseif phase == PhasePenRiseBeforeHighlights
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ, PointCPrime[1], PointCPrime[2])
        timer += dt
        if timer >= PenLiftDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseCompassDescendAB
            timer = 0f0
        end

    elseif phase == PhaseCompassDescendAB
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, PointA[1], PointA[2])
        timer += dt
        if timer >= DescendDuration
            phase = PhaseHighlightPath1ABForward
            timer = 0f0
        end

    elseif phase == PhaseHighlightPath1ABForward
        EuclidAnimations.animate_pen_tilt_and_drag(state_ptr, timer, DragDuration, PointA, PointB, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath1BCForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath1BCForward
        EuclidAnimations.animate_pen_tilt_and_drag(state_ptr, timer, DragDuration, PointB, PointC, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath1CPForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath1CPForward
        EuclidAnimations.animate_pen_tilt_and_drag(state_ptr, timer, DragDuration, PointC, PointP, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath1PAForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath1PAForward
        EuclidAnimations.animate_pen_tilt_and_drag(state_ptr, timer, DragDuration, PointP, PointA, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath1APBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath1APBack
        EuclidAnimations.animate_pen_tilt_and_drag(state_ptr, timer, DragDuration, PointA, PointP, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath1PCBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath1PCBack
        EuclidAnimations.animate_pen_tilt_and_drag(state_ptr, timer, DragDuration, PointP, PointC, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath1CBBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath1CBBack
        EuclidAnimations.animate_pen_tilt_and_drag(state_ptr, timer, DragDuration, PointC, PointB, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath1BABack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath1BABack
        EuclidAnimations.animate_pen_tilt_and_drag(state_ptr, timer, DragDuration, PointB, PointA, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseCompassArcToPrime
            timer = 0f0
        end

    elseif phase == PhaseCompassArcToPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointA, PointAPrime, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightPath2ABForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath2ABForward
        EuclidAnimations.animate_pen_tilt_and_drag(state_ptr, timer, DragDuration, PointAPrime, PointBPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath2BCForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath2BCForward
        EuclidAnimations.animate_pen_tilt_and_drag(state_ptr, timer, DragDuration, PointBPrime, PointCPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath2CPForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath2CPForward
        EuclidAnimations.animate_pen_tilt_and_drag(state_ptr, timer, DragDuration, PointCPrime, PointPPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath2PAForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath2PAForward
        EuclidAnimations.animate_pen_tilt_and_drag(state_ptr, timer, DragDuration, PointPPrime, PointAPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath2APBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath2APBack
        EuclidAnimations.animate_pen_tilt_and_drag(state_ptr, timer, DragDuration, PointAPrime, PointPPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath2PCBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath2PCBack
        EuclidAnimations.animate_pen_tilt_and_drag(state_ptr, timer, DragDuration, PointPPrime, PointCPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath2CBBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath2CBBack
        EuclidAnimations.animate_pen_tilt_and_drag(state_ptr, timer, DragDuration, PointCPrime, PointBPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath2BABack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath2BABack
        EuclidAnimations.animate_pen_tilt_and_drag(state_ptr, timer, DragDuration, PointBPrime, PointAPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseCompassRiseEnd
            timer = 0f0
        end

    elseif phase == PhaseCompassRiseEnd
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ, PointAPrime[1], PointAPrime[2])
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

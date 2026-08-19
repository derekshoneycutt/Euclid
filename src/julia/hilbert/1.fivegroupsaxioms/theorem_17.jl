module HilbertChapterOneTheorem17

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

export get_view_text, initialize, clean, loop

const PointA = [0.10f0, 0.82f0, 0f0]
const PointB = [0.38f0, 0.82f0, 0f0]
const PointC = [0.38f0, 0.50f0, 0f0]
const PointD = [0.10f0, 0.50f0, 0f0]
const PointP = [0.17f0, 0.60f0, 0f0]

const PointAPrime = [0.57f0, 0.82f0, 0f0]
const PointBPrime = [0.85f0, 0.82f0, 0f0]
const PointCPrime = [0.85f0, 0.50f0, 0f0]
const PointDPrime = [0.57f0, 0.50f0, 0f0]
const PointPPrime = [0.64f0, 0.60f0, 0f0]

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
const LabelPPoint = PointP + [0.05f0, -0.05f0, 0f0]

const LabelAPrimePoint = PointAPrime + [-0.03f0, 0.03f0, 0f0]
const LabelBPrimePoint = PointBPrime + [0.05f0, 0.06f0, 0f0]
const LabelCPrimePoint = PointCPrime + [0.02f0, -0.04f0, 0f0]
const LabelDPrimePoint = PointDPrime + [-0.03f0, -0.04f0, 0f0]
const LabelPPrimePoint = PointPPrime + [0.05f0, -0.05f0, 0f0]

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
    fallback = """David Hilbert - Foundations of Geometry - Theorem 17

If (A, B, C, ...) and (A', B', C', ...) are congruent plane figures and P is a point in the plane of the first, then it is always possible to find a point P' in the plane of the second figure so that (A, B, C, ..., P) and (A', B', C', ..., P') shall likewise be congruent figures. If the two figures have at least three points not lying in a straight line, then the selection of P' can be made in only one way."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - Theorem 17}

If $(A, B, C, ...)$ \euclidbox[height=2,width=2,thickness=2,edge1_color=grey60,edge2_color=khaki3,edge3_color=palevioletred1,edge4_color=steelblue] and
$(A', B', C', ...)$ \euclidbox[height=2,width=2,thickness=2,edge1_color=grey60,edge2_color=khaki3,edge3_color=palevioletred1,edge4_color=steelblue] are
congruent plane figures and $P$ \euclidpoint[color=grey60,size=1] is a point in the plane of the first, then it is always possible to find a point
$P'$ \euclidpoint[color=grey60,size=1] in the plane of the second figure so that
$(A, B, C, ..., P)$ \euclidbox[height=2,width=3,thickness=2,edge1_color=grey60,edge2_color=khaki3,edge3_color=khaki3,edge4_color=khaki3] and
$(A', B', C', ..., P')$ \euclidbox[height=2,width=3,thickness=2,edge1_color=grey60,edge2_color=khaki3,edge3_color=khaki3,edge4_color=khaki3]
shall likewise be congruent figures. If the two figures have at least three points not lying in a straight line, then the selection of
$P'$ \euclidpoint[color=grey60,size=1] can be made in only one way."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    edge_a_b_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeABHostId))
    edge_a_b_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeABJoint2Id))
    edge_b_c_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeBCHostId))
    edge_b_c_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeBCJoint2Id))
    edge_c_d_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeCDHostId))
    edge_c_d_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeCDJoint2Id))
    edge_d_a_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeDAHostId))
    edge_d_a_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeDAJoint2Id))

    edge_a_prime_b_prime_host_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPrimeBPrimeHostId))
    edge_a_prime_b_prime_joint2_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPrimeBPrimeJoint2Id))
    edge_b_prime_c_prime_host_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeBPrimeCPrimeHostId))
    edge_b_prime_c_prime_joint2_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeBPrimeCPrimeJoint2Id))
    edge_c_prime_d_prime_host_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCPrimeDPrimeHostId))
    edge_c_prime_d_prime_joint2_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCPrimeDPrimeJoint2Id))
    edge_d_prime_a_prime_host_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeDPrimeAPrimeHostId))
    edge_d_prime_a_prime_joint2_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeDPrimeAPrimeJoint2Id))

    edge_a_p_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeAPHostId))
    edge_a_p_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeAPJoint2Id))
    edge_p_c_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgePCHostId))
    edge_p_c_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgePCJoint2Id))
    edge_a_prime_p_prime_host_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPrimePPrimeHostId))
    edge_a_prime_p_prime_joint2_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPrimePPrimeJoint2Id))
    edge_p_prime_c_prime_host_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgePPrimeCPrimeHostId))
    edge_p_prime_c_prime_joint2_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgePPrimeCPrimeJoint2Id))

    point_p_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointPId))
    point_p_prime_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaPointPPrimeId))

    label_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    label_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    label_c_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    label_d_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDId))
    label_p_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelPId))
    label_a_prime_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLabelAPrimeId))
    label_b_prime_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLabelBPrimeId))
    label_c_prime_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLabelCPrimeId))
    label_d_prime_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLabelDPrimeId))
    label_p_prime_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLabelPPrimeId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [edge_a_b_host_id, edge_b_c_host_id, edge_c_d_host_id, edge_d_a_host_id,
         edge_a_prime_b_prime_host_id, edge_b_prime_c_prime_host_id,
         edge_c_prime_d_prime_host_id, edge_d_prime_a_prime_host_id,
         edge_a_p_host_id, edge_p_c_host_id,
         edge_a_prime_p_prime_host_id, edge_p_prime_c_prime_host_id,
         point_p_id, point_p_prime_id,
         label_a_id, label_b_id, label_c_id, label_d_id, label_p_id,
         label_a_prime_id, label_b_prime_id, label_c_prime_id,
         label_d_prime_id, label_p_prime_id])

    OdinJuliaBridge.set_point_position(state_ptr, edge_a_b_joint2_id, PointA)
    OdinJuliaBridge.set_point_position(state_ptr, edge_b_c_joint2_id, PointB)
    OdinJuliaBridge.set_point_position(state_ptr, edge_c_d_joint2_id, PointC)
    OdinJuliaBridge.set_point_position(state_ptr, edge_d_a_joint2_id, PointD)

    OdinJuliaBridge.set_point_position(
        state_ptr, edge_a_prime_b_prime_joint2_id, PointAPrime)
    OdinJuliaBridge.set_point_position(
        state_ptr, edge_b_prime_c_prime_joint2_id, PointBPrime)
    OdinJuliaBridge.set_point_position(
        state_ptr, edge_c_prime_d_prime_joint2_id, PointCPrime)
    OdinJuliaBridge.set_point_position(
        state_ptr, edge_d_prime_a_prime_joint2_id, PointDPrime)

    OdinJuliaBridge.set_point_position(state_ptr, edge_a_p_joint2_id, PointA)
    OdinJuliaBridge.set_point_position(state_ptr, edge_p_c_joint2_id, PointP)
    OdinJuliaBridge.set_point_position(
        state_ptr, edge_a_prime_p_prime_joint2_id, PointAPrime)
    OdinJuliaBridge.set_point_position(
        state_ptr, edge_p_prime_c_prime_joint2_id, PointPPrime)

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
    edge_a_b = OdinJuliaBridge.create_new_line(state_ptr, PointA, PointA, ColorAB, 0f0)
    edge_b_c = OdinJuliaBridge.create_new_line(state_ptr, PointB, PointB, ColorBC, 0f0)
    edge_c_d = OdinJuliaBridge.create_new_line(state_ptr, PointC, PointC, ColorCD, 0f0)
    edge_d_a = OdinJuliaBridge.create_new_line(state_ptr, PointD, PointD, ColorDA, 0f0)

    edge_a_prime_b_prime = OdinJuliaBridge.create_new_line(
        state_ptr, PointAPrime, PointAPrime, ColorAB, 0f0)
    edge_b_prime_c_prime = OdinJuliaBridge.create_new_line(
        state_ptr, PointBPrime, PointBPrime, ColorBC, 0f0)
    edge_c_prime_d_prime = OdinJuliaBridge.create_new_line(
        state_ptr, PointCPrime, PointCPrime, ColorCD, 0f0)
    edge_d_prime_a_prime = OdinJuliaBridge.create_new_line(
        state_ptr, PointDPrime, PointDPrime, ColorDA, 0f0)

    edge_a_p = OdinJuliaBridge.create_new_line(state_ptr, PointA, PointA, ColorAux, 0f0)
    edge_p_c = OdinJuliaBridge.create_new_line(state_ptr, PointP, PointP, ColorAux, 0f0)
    edge_a_prime_p_prime = OdinJuliaBridge.create_new_line(
        state_ptr, PointAPrime, PointAPrime, ColorAux, 0f0)
    edge_p_prime_c_prime = OdinJuliaBridge.create_new_line(
        state_ptr, PointPPrime, PointPPrime, ColorAux, 0f0)

    point_p = OdinJuliaBridge.create_new_point(state_ptr, PointP, ColorPointP, 0f0)
    point_p_prime = OdinJuliaBridge.create_new_point(
        state_ptr, PointPPrime, ColorPointP, 0f0)

    label_a = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', LabelAPoint, LabelColor, 16f0)
    label_b = OdinJuliaBridge.create_new_label(
        state_ptr, 'B', LabelBPoint, LabelColor, 16f0)
    label_c = OdinJuliaBridge.create_new_label(
        state_ptr, 'C', LabelCPoint, LabelColor, 16f0)
    label_d = OdinJuliaBridge.create_new_label(
        state_ptr, 'D', LabelDPoint, LabelColor, 16f0)
    label_p = OdinJuliaBridge.create_new_label(
        state_ptr, 'P', LabelPPoint, LabelColor, 16f0)

    label_a_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'A', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelAPrimePoint, LabelColor, 16f0)
    label_b_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'B', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelBPrimePoint, LabelColor, 16f0)
    label_c_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'C', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelCPrimePoint, LabelColor, 16f0)
    label_d_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'D', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelDPrimePoint, LabelColor, 16f0)
    label_p_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'P', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelPPrimePoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeABHostId, edge_a_b.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeABJoint1Id, edge_a_b.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeABJoint2Id, edge_a_b.joint2_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeBCHostId, edge_b_c.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeBCJoint1Id, edge_b_c.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeBCJoint2Id, edge_b_c.joint2_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeCDHostId, edge_c_d.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeCDJoint1Id, edge_c_d.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeCDJoint2Id, edge_c_d.joint2_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeDAHostId, edge_d_a.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeDAJoint1Id, edge_d_a.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeDAJoint2Id, edge_d_a.joint2_id)

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
        state_ptr, MetaEdgeCPrimeDPrimeHostId, edge_c_prime_d_prime.host_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeCPrimeDPrimeJoint1Id, edge_c_prime_d_prime.joint1_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeCPrimeDPrimeJoint2Id, edge_c_prime_d_prime.joint2_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeDPrimeAPrimeHostId, edge_d_prime_a_prime.host_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeDPrimeAPrimeJoint1Id, edge_d_prime_a_prime.joint1_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeDPrimeAPrimeJoint2Id, edge_d_prime_a_prime.joint2_id)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeAPHostId, edge_a_p.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeAPJoint1Id, edge_a_p.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeAPJoint2Id, edge_a_p.joint2_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgePCHostId, edge_p_c.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgePCJoint1Id, edge_p_c.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgePCJoint2Id, edge_p_c.joint2_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeAPrimePPrimeHostId, edge_a_prime_p_prime.host_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeAPrimePPrimeJoint1Id, edge_a_prime_p_prime.joint1_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgeAPrimePPrimeJoint2Id, edge_a_prime_p_prime.joint2_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgePPrimeCPrimeHostId, edge_p_prime_c_prime.host_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgePPrimeCPrimeJoint1Id, edge_p_prime_c_prime.joint1_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaEdgePPrimeCPrimeJoint2Id, edge_p_prime_c_prime.joint2_id)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointPId, point_p.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointPPrimeId, point_p_prime.index)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAId, label_a.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBId, label_b.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelCId, label_c.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelDId, label_d.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelPId, label_p.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAPrimeId, label_a_prime.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBPrimeId, label_b_prime.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelCPrimeId, label_c_prime.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelDPrimeId, label_d_prime.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelPPrimeId, label_p_prime.index)

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

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
    edge_c_d_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeCDHostId))
    edge_c_d_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeCDJoint1Id))
    edge_c_d_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeCDJoint2Id))
    edge_d_a_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeDAHostId))
    edge_d_a_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeDAJoint1Id))
    edge_d_a_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeDAJoint2Id))

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
    edge_c_prime_d_prime_host_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCPrimeDPrimeHostId))
    edge_c_prime_d_prime_joint1_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCPrimeDPrimeJoint1Id))
    edge_c_prime_d_prime_joint2_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCPrimeDPrimeJoint2Id))
    edge_d_prime_a_prime_host_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeDPrimeAPrimeHostId))
    edge_d_prime_a_prime_joint1_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeDPrimeAPrimeJoint1Id))
    edge_d_prime_a_prime_joint2_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeDPrimeAPrimeJoint2Id))

    edge_a_p_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeAPHostId))
    edge_a_p_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeAPJoint1Id))
    edge_a_p_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeAPJoint2Id))
    edge_p_c_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgePCHostId))
    edge_p_c_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgePCJoint1Id))
    edge_p_c_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgePCJoint2Id))
    edge_a_prime_p_prime_host_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPrimePPrimeHostId))
    edge_a_prime_p_prime_joint1_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPrimePPrimeJoint1Id))
    edge_a_prime_p_prime_joint2_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeAPrimePPrimeJoint2Id))
    edge_p_prime_c_prime_host_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgePPrimeCPrimeHostId))
    edge_p_prime_c_prime_joint1_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgePPrimeCPrimeJoint1Id))
    edge_p_prime_c_prime_joint2_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgePPrimeCPrimeJoint2Id))

    point_p_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointPId))
    point_p_prime_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaPointPPrimeId))

    label_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    label_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    label_c_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    label_d_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDId))
    label_p_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelPId))
    label_a_prime_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLabelAPrimeId))
    label_b_prime_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLabelBPrimeId))
    label_c_prime_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLabelCPrimeId))
    label_d_prime_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLabelDPrimeId))
    label_p_prime_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLabelPPrimeId))

    if edge_a_b_host_id < 0 || edge_a_prime_b_prime_host_id < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescendA
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, PointA[1], PointA[2])
        timer += dt
        if timer >= DescendDuration
            OdinJuliaBridge.show_point(state_ptr, label_a_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, ColorAB)
            phase = PhaseDrawAB
            timer = 0f0
        end
    elseif phase == PhaseDrawAB
        EuclidAnimations.animate_draw_line(state_ptr, timer, DrawDuration, PointA, PointB,
            EdgeBrush, ColorAB, edge_a_b_host_id, edge_a_b_joint1_id, edge_a_b_joint2_id)
        timer += dt
        if timer >= DrawDuration
            OdinJuliaBridge.show_point(state_ptr, label_b_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, ColorBC)
            phase = PhaseDrawBC
            timer = 0f0
        end
    elseif phase == PhaseDrawBC
        EuclidAnimations.animate_draw_line(state_ptr, timer, DrawDuration, PointB, PointC,
            EdgeBrush, ColorBC, edge_b_c_host_id, edge_b_c_joint1_id, edge_b_c_joint2_id)
        timer += dt
        if timer >= DrawDuration
            OdinJuliaBridge.show_point(state_ptr, label_c_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, ColorCD)
            phase = PhaseDrawCD
            timer = 0f0
        end
    elseif phase == PhaseDrawCD
        EuclidAnimations.animate_draw_line(state_ptr, timer, DrawDuration, PointC, PointD,
            EdgeBrush, ColorCD, edge_c_d_host_id, edge_c_d_joint1_id, edge_c_d_joint2_id)
        timer += dt
        if timer >= DrawDuration
            OdinJuliaBridge.show_point(state_ptr, label_d_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, ColorDA)
            phase = PhaseDrawDA
            timer = 0f0
        end
    elseif phase == PhaseDrawDA
        EuclidAnimations.animate_draw_line(state_ptr, timer, DrawDuration, PointD, PointA,
            EdgeBrush, ColorDA, edge_d_a_host_id, edge_d_a_joint1_id, edge_d_a_joint2_id)
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
            OdinJuliaBridge.show_point(state_ptr, label_a_prime_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, ColorAB)
            phase = PhaseDrawAPrimeBPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawAPrimeBPrime
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawDuration, PointAPrime, PointBPrime,
            EdgeBrush, ColorAB,
            edge_a_prime_b_prime_host_id, edge_a_prime_b_prime_joint1_id,
            edge_a_prime_b_prime_joint2_id)
        timer += dt
        if timer >= DrawDuration
            OdinJuliaBridge.show_point(state_ptr, label_b_prime_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, ColorBC)
            phase = PhaseDrawBPrimeCPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawBPrimeCPrime
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawDuration, PointBPrime, PointCPrime,
            EdgeBrush, ColorBC,
            edge_b_prime_c_prime_host_id, edge_b_prime_c_prime_joint1_id,
            edge_b_prime_c_prime_joint2_id)
        timer += dt
        if timer >= DrawDuration
            OdinJuliaBridge.show_point(state_ptr, label_c_prime_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, ColorCD)
            phase = PhaseDrawCPrimeDPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawCPrimeDPrime
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawDuration, PointCPrime, PointDPrime,
            EdgeBrush, ColorCD,
            edge_c_prime_d_prime_host_id, edge_c_prime_d_prime_joint1_id,
            edge_c_prime_d_prime_joint2_id)
        timer += dt
        if timer >= DrawDuration
            OdinJuliaBridge.show_point(state_ptr, label_d_prime_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, ColorDA)
            phase = PhaseDrawDPrimeAPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawDPrimeAPrime
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawDuration, PointDPrime, PointAPrime,
            EdgeBrush, ColorDA,
            edge_d_prime_a_prime_host_id, edge_d_prime_a_prime_joint1_id,
            edge_d_prime_a_prime_joint2_id)
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
            state_ptr, timer, DrawPointDuration, PointP,
            PointBrush, ColorPointP, point_p_id)
        timer += dt
        if timer >= DrawPointDuration
            OdinJuliaBridge.show_point(state_ptr, label_p_id)
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
            state_ptr, timer, DrawPointDuration, PointPPrime,
            PointBrush, ColorPointP, point_p_prime_id)
        timer += dt
        if timer >= DrawPointDuration
            OdinJuliaBridge.show_point(state_ptr, label_p_prime_id)
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
            EdgeBrush, ColorAux, edge_a_p_host_id, edge_a_p_joint1_id, edge_a_p_joint2_id)
        timer += dt
        if timer >= DrawDuration
            phase = PhaseDrawPC
            timer = 0f0
        end
    elseif phase == PhaseDrawPC
        EuclidAnimations.animate_draw_line(state_ptr, timer, DrawDuration, PointP, PointC,
            EdgeBrush, ColorAux, edge_p_c_host_id, edge_p_c_joint1_id, edge_p_c_joint2_id)
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
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawDuration, PointAPrime, PointPPrime,
            EdgeBrush, ColorAux,
            edge_a_prime_p_prime_host_id, edge_a_prime_p_prime_joint1_id,
            edge_a_prime_p_prime_joint2_id)
        timer += dt
        if timer >= DrawDuration
            phase = PhaseDrawPPrimeCPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawPPrimeCPrime
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawDuration, PointPPrime, PointCPrime,
            EdgeBrush, ColorAux,
            edge_p_prime_c_prime_host_id, edge_p_prime_c_prime_joint1_id,
            edge_p_prime_c_prime_joint2_id)
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
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointA, PointB, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath1BCForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath1BCForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointB, PointC, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath1CPForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath1CPForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointC, PointP, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath1PAForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath1PAForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointP, PointA, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath1APBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath1APBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointA, PointP, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath1PCBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath1PCBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointP, PointC, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath1CBBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath1CBBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointC, PointB, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath1BABack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath1BABack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointB, PointA, HighlightColor)
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
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointAPrime, PointBPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath2BCForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath2BCForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointBPrime, PointCPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath2CPForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath2CPForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointCPrime, PointPPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath2PAForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath2PAForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointPPrime, PointAPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath2APBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath2APBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointAPrime, PointPPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath2PCBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath2PCBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointPPrime, PointCPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath2CBBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath2CBBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointCPrime, PointBPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath2BABack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath2BABack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointBPrime, PointAPrime, HighlightColor)
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

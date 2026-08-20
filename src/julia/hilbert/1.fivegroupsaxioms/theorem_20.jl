module HilbertChapterOneTheorem20

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

export get_view_text, initialize, clean, loop

const PointB = [0.26f0, 0.32f0, 0f0]
const PointC = [0.62f0, 0.32f0, 0f0]
const PointA = [0.44f0, 0.66f0, 0f0]
const PointD = [0.84f0, 0.32f0, 0f0]
const PointE = [0.75f0, 0.56f0, 0f0]

const EdgeCBStart = PointC
const EdgeCBEnd = PointB
const EdgeBAStart = PointB
const EdgeBAEnd = PointA
const EdgeACStart = PointA
const EdgeACEnd = PointC
const EdgeCDStart = PointC
const EdgeCDEnd = PointD
const EdgeCEStart = PointC
const EdgeCEEnd = PointE

const MarkerRadius = 0.08f0

const ThetaASegAB = atan(PointB[2] - PointA[2], PointB[1] - PointA[1])
const ThetaASegAC = atan(PointC[2] - PointA[2], PointC[1] - PointA[1])
const ThetaBSegBA = atan(PointA[2] - PointB[2], PointA[1] - PointB[1])
const ThetaBSegBC = atan(PointC[2] - PointB[2], PointC[1] - PointB[1])
const ThetaCSegCA = atan(PointA[2] - PointC[2], PointA[1] - PointC[1])
const ThetaCSegCB = atan(PointB[2] - PointC[2], PointB[1] - PointC[1])
const ThetaCSegCD = atan(PointD[2] - PointC[2], PointD[1] - PointC[1])
const ThetaCSegCE = atan(PointE[2] - PointC[2], PointE[1] - PointC[1])

const MarkerAStart = [
    PointA[1] + MarkerRadius * cos(ThetaASegAB),
    PointA[2] + MarkerRadius * sin(ThetaASegAB),
    0f0,
]
const MarkerAEnd = [
    PointA[1] + MarkerRadius * cos(ThetaASegAC),
    PointA[2] + MarkerRadius * sin(ThetaASegAC),
    0f0,
]

const MarkerBStart = [
    PointB[1] + MarkerRadius * cos(ThetaBSegBC),
    PointB[2] + MarkerRadius * sin(ThetaBSegBC),
    0f0,
]
const MarkerBEnd = [
    PointB[1] + MarkerRadius * cos(ThetaBSegBA),
    PointB[2] + MarkerRadius * sin(ThetaBSegBA),
    0f0,
]

const MarkerCACEStart = [
    PointC[1] + MarkerRadius * cos(ThetaCSegCA),
    PointC[2] + MarkerRadius * sin(ThetaCSegCA),
    0f0,
]
const MarkerCACEEnd = [
    PointC[1] + MarkerRadius * cos(ThetaCSegCE),
    PointC[2] + MarkerRadius * sin(ThetaCSegCE),
    0f0,
]

const MarkerCECDStart = [
    PointC[1] + MarkerRadius * cos(ThetaCSegCE),
    PointC[2] + MarkerRadius * sin(ThetaCSegCE),
    0f0,
]
const MarkerCECDEnd = [
    PointC[1] + MarkerRadius * cos(ThetaCSegCD),
    PointC[2] + MarkerRadius * sin(ThetaCSegCD),
    0f0,
]

const MarkerCACBStart = [
    PointC[1] + MarkerRadius * cos(ThetaCSegCA),
    PointC[2] + MarkerRadius * sin(ThetaCSegCA),
    0f0,
]
const MarkerCACBEnd = [
    PointC[1] + MarkerRadius * cos(ThetaCSegCB),
    PointC[2] + MarkerRadius * sin(ThetaCSegCB),
    0f0,
]

const MarkerBCDStart = [
    PointC[1] + MarkerRadius * cos(ThetaCSegCD),
    PointC[2] + MarkerRadius * sin(ThetaCSegCD),
    0f0,
]
const MarkerBCDEnd = [
    PointC[1] + MarkerRadius * cos(ThetaCSegCB),
    PointC[2] + MarkerRadius * sin(ThetaCSegCB),
    0f0,
]

const AngleBACTheta = ThetaASegAC - ThetaASegAB
const AngleABCTheta = ThetaBSegBA - ThetaBSegBC
const AngleACETheta = ThetaCSegCE - ThetaCSegCA
const AngleECDTheta = ThetaCSegCD - ThetaCSegCE
const AngleACBTheta = ThetaCSegCB - ThetaCSegCA
const AngleBCDTheta = π

const LabelColor = :plum1
const HighlightColor = :lightgreen
const EdgeCBColor = :steelblue
const EdgeBAColor = :palevioletred1
const EdgeACColor = :khaki3
const EdgeCDColor = :steelblue
const EdgeCEColor = :palevioletred1
const PointColor = :grey60

const EdgeBrush = 5f0
const PointBrush = 6f0
const PenTopZ = 1.4f0
const CompassTopZ = 1.4f0
const ToolResetOffscreenJoint1 = [0.50f0, 1.25f0, 1.55f0]
const ToolResetOffscreenJoint2 = [0.57f0, 1.25f0, 1.55f0]

const LabelBPoint = PointB + [-0.03f0, -0.04f0, 0f0]
const LabelCPoint = PointC + [0.02f0, -0.04f0, 0f0]
const LabelAPoint = PointA + [0.00f0, 0.04f0, 0f0]
const LabelDPoint = PointD + [0.02f0, -0.04f0, 0f0]
const LabelEPoint = PointE + [0.05f0, 0.07f0, 0f0]

const DescendDuration = 1.8f0
const DrawPointDuration = 1.5f0
const DrawEdgeDuration = 2.1f0
const ArcMoveDuration = 1.35f0
const CompassSweepDuration = 0.95f0
const PenLiftDuration = 1.6f0
const CompassLiftDuration = 1.8f0
const FinalHoldDuration = 0.35f0
const EmphasisSweepDuration = 1.2f0

const MetaEdgeCBHostId = 1
const MetaEdgeCBJoint1Id = 2
const MetaEdgeCBJoint2Id = 3
const MetaEdgeBAHostId = 11
const MetaEdgeBAJoint1Id = 12
const MetaEdgeBAJoint2Id = 13
const MetaEdgeACHostId = 21
const MetaEdgeACJoint1Id = 22
const MetaEdgeACJoint2Id = 23
const MetaEdgeCDHostId = 31
const MetaEdgeCDJoint1Id = 32
const MetaEdgeCDJoint2Id = 33
const MetaEdgeCEHostId = 41
const MetaEdgeCEJoint1Id = 42
const MetaEdgeCEJoint2Id = 43

const MetaPointBId = 51
const MetaPointCId = 52
const MetaPointAId = 53
const MetaPointDId = 54
const MetaPointEId = 55

const MetaLabelBId = 61
const MetaLabelCId = 62
const MetaLabelAId = 63
const MetaLabelDId = 64
const MetaLabelEId = 65

const MetaPhase = 101
const MetaTimer = 102

const PhaseDescendB = 0f0
const PhaseDrawPointB = 1f0
const PhaseArcToC = 2f0
const PhaseDrawPointC = 3f0
const PhaseArcToA = 4f0
const PhaseDrawPointA = 5f0
const PhaseArcToCForCB = 6f0
const PhaseDrawCB = 7f0
const PhaseDrawBA = 8f0
const PhaseDrawAC = 9f0
const PhaseDrawCD = 10f0
const PhaseDrawPointD = 11f0
const PhaseArcDToCForCE = 11.5f0
const PhaseDrawCE = 12f0
const PhaseDrawPointE = 13f0
const PhasePenRise = 14f0

const PhaseCompassDescendBAC = 15f0
const PhaseHighlightBACForward = 16f0
const PhaseHighlightBACBack = 17f0
const PhaseCompassArcToACE = 18f0
const PhaseHighlightACEForward = 19f0
const PhaseHighlightACEBack = 20f0
const PhaseCompassArcToECD = 21f0
const PhaseHighlightECDForward = 22f0
const PhaseHighlightECDBack = 23f0
const PhaseCompassArcToABC = 24f0
const PhaseHighlightABCForward = 25f0
const PhaseHighlightABCBack = 26f0
const PhaseCompassArcToCCombine = 27f0
const PhaseHighlightACBForward = 28f0
const PhaseHighlightACBBack = 29f0
const PhaseHighlightBCDForward = 30f0
const PhaseHighlightBCDBack = 31f0
const PhaseCompassRise = 32f0
const PhaseFinalHold = 33f0

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - Theorem 20

The sum of the angles of a triangle is two right angles."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - Theorem 20}

The sum of the angles of a triangle is two right angles."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset the state of the animation cycle back to the start of the animation"""
function reset_cycle_state(state_ptr::Ptr{Cvoid})
    edge_c_b_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeCBHostId))
    edge_c_b_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeCBJoint2Id))
    edge_b_a_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeBAHostId))
    edge_b_a_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeBAJoint2Id))
    edge_a_c_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeACHostId))
    edge_a_c_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeACJoint2Id))
    edge_c_d_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeCDHostId))
    edge_c_d_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeCDJoint2Id))
    edge_c_e_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeCEHostId))
    edge_c_e_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeCEJoint2Id))

    point_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    point_c_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointCId))
    point_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    point_d_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointDId))
    point_e_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointEId))

    label_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    label_c_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    label_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    label_d_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDId))
    label_e_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelEId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [edge_c_b_host_id, edge_b_a_host_id, edge_a_c_host_id,
         edge_c_d_host_id, edge_c_e_host_id,
         point_b_id, point_c_id, point_a_id, point_d_id, point_e_id,
         label_b_id, label_c_id, label_a_id, label_d_id, label_e_id])

    OdinJuliaBridge.set_point_position(state_ptr, edge_c_b_joint2_id, EdgeCBStart)
    OdinJuliaBridge.set_point_position(state_ptr, edge_b_a_joint2_id, EdgeBAStart)
    OdinJuliaBridge.set_point_position(state_ptr, edge_a_c_joint2_id, EdgeACStart)
    OdinJuliaBridge.set_point_position(state_ptr, edge_c_d_joint2_id, EdgeCDStart)
    OdinJuliaBridge.set_point_position(state_ptr, edge_c_e_joint2_id, EdgeCEStart)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescendB)
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

    OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeCBColor)
    OdinJuliaBridge.set_compass_active(state_ptr, 0, HighlightColor)
    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    edge_c_b = OdinJuliaBridge.create_new_line(
        state_ptr, EdgeCBStart, EdgeCBStart, EdgeCBColor, 0f0)
    edge_b_a = OdinJuliaBridge.create_new_line(
        state_ptr, EdgeBAStart, EdgeBAStart, EdgeBAColor, 0f0)
    edge_a_c = OdinJuliaBridge.create_new_line(
        state_ptr, EdgeACStart, EdgeACStart, EdgeACColor, 0f0)
    edge_c_d = OdinJuliaBridge.create_new_line(
        state_ptr, EdgeCDStart, EdgeCDStart, EdgeCDColor, 0f0)
    edge_c_e = OdinJuliaBridge.create_new_line(
        state_ptr, EdgeCEStart, EdgeCEStart, EdgeCEColor, 0f0)

    point_b = OdinJuliaBridge.create_new_point(state_ptr, PointB, PointColor, 0f0)
    point_c = OdinJuliaBridge.create_new_point(state_ptr, PointC, PointColor, 0f0)
    point_a = OdinJuliaBridge.create_new_point(state_ptr, PointA, PointColor, 0f0)
    point_d = OdinJuliaBridge.create_new_point(state_ptr, PointD, PointColor, 0f0)
    point_e = OdinJuliaBridge.create_new_point(state_ptr, PointE, PointColor, 0f0)

    label_b = OdinJuliaBridge.create_new_label(
        state_ptr, 'B', LabelBPoint, LabelColor, 16f0)
    label_c = OdinJuliaBridge.create_new_label(
        state_ptr, 'C', LabelCPoint, LabelColor, 16f0)
    label_a = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', LabelAPoint, LabelColor, 16f0)
    label_d = OdinJuliaBridge.create_new_label(
        state_ptr, 'D', LabelDPoint, LabelColor, 16f0)
    label_e = OdinJuliaBridge.create_new_label(
        state_ptr, 'E', LabelEPoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeCBHostId, edge_c_b.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeCBJoint1Id, edge_c_b.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeCBJoint2Id, edge_c_b.joint2_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeBAHostId, edge_b_a.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeBAJoint1Id, edge_b_a.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeBAJoint2Id, edge_b_a.joint2_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeACHostId, edge_a_c.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeACJoint1Id, edge_a_c.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeACJoint2Id, edge_a_c.joint2_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeCDHostId, edge_c_d.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeCDJoint1Id, edge_c_d.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeCDJoint2Id, edge_c_d.joint2_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeCEHostId, edge_c_e.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeCEJoint1Id, edge_c_e.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeCEJoint2Id, edge_c_e.joint2_id)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointBId, point_b.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointCId, point_c.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointAId, point_a.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointDId, point_d.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointEId, point_e.index)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBId, label_b.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelCId, label_c.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAId, label_a.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelDId, label_d.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelEId, label_e.index)

    reset_cycle_state(state_ptr)
end

"""Clean any extra animation data at the end of performance"""
function clean(state_ptr::Ptr{Cvoid})
end

"""Perform an iteration of the animation loop for this animation"""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    edge_c_b_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeCBHostId))
    edge_c_b_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeCBJoint1Id))
    edge_c_b_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeCBJoint2Id))
    edge_b_a_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeBAHostId))
    edge_b_a_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeBAJoint1Id))
    edge_b_a_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeBAJoint2Id))
    edge_a_c_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeACHostId))
    edge_a_c_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeACJoint1Id))
    edge_a_c_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeACJoint2Id))
    edge_c_d_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeCDHostId))
    edge_c_d_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeCDJoint1Id))
    edge_c_d_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeCDJoint2Id))
    edge_c_e_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeCEHostId))
    edge_c_e_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeCEJoint1Id))
    edge_c_e_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeCEJoint2Id))

    point_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    point_c_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointCId))
    point_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    point_d_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointDId))
    point_e_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointEId))

    label_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    label_c_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    label_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    label_d_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDId))
    label_e_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelEId))

    if edge_c_b_host_id < 0 || edge_b_a_host_id < 0 || edge_a_c_host_id < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescendB
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, PointB[1], PointB[2])
        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawPointB
            timer = 0f0
        end
    elseif phase == PhaseDrawPointB
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointB,
            PointBrush, PointColor, point_b_id)
        timer += dt
        if timer >= DrawPointDuration
            OdinJuliaBridge.show_point(state_ptr, label_b_id)
            phase = PhaseArcToC
            timer = 0f0
        end
    elseif phase == PhaseArcToC
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointB, PointC, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawPointC
            timer = 0f0
        end
    elseif phase == PhaseDrawPointC
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointC,
            PointBrush, PointColor, point_c_id)
        timer += dt
        if timer >= DrawPointDuration
            OdinJuliaBridge.show_point(state_ptr, label_c_id)
            phase = PhaseArcToA
            timer = 0f0
        end
    elseif phase == PhaseArcToA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointC, PointA, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawPointA
            timer = 0f0
        end
    elseif phase == PhaseDrawPointA
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointA,
            PointBrush, PointColor, point_a_id)
        timer += dt
        if timer >= DrawPointDuration
            OdinJuliaBridge.show_point(state_ptr, label_a_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeCBColor)
            phase = PhaseArcToCForCB
            timer = 0f0
        end
    elseif phase == PhaseArcToCForCB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointA, PointC, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawCB
            timer = 0f0
        end
    elseif phase == PhaseDrawCB
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawEdgeDuration,
            EdgeCBStart, EdgeCBEnd;
            penbrush=EdgeBrush,
            pencolor=EdgeCBColor,
            line_host_id=edge_c_b_host_id,
            line_joint1_id=edge_c_b_joint1_id,
            line_joint2_id=edge_c_b_joint2_id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeBAColor)
            phase = PhaseDrawBA
            timer = 0f0
        end
    elseif phase == PhaseDrawBA
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawEdgeDuration,
            EdgeBAStart, EdgeBAEnd;
            penbrush=EdgeBrush,
            pencolor=EdgeBAColor,
            line_host_id=edge_b_a_host_id,
            line_joint1_id=edge_b_a_joint1_id,
            line_joint2_id=edge_b_a_joint2_id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeACColor)
            phase = PhaseDrawAC
            timer = 0f0
        end
    elseif phase == PhaseDrawAC
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawEdgeDuration,
            EdgeACStart, EdgeACEnd;
            penbrush=EdgeBrush,
            pencolor=EdgeACColor,
            line_host_id=edge_a_c_host_id,
            line_joint1_id=edge_a_c_joint1_id,
            line_joint2_id=edge_a_c_joint2_id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeCDColor)
            phase = PhaseDrawCD
            timer = 0f0
        end
    elseif phase == PhaseDrawCD
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawEdgeDuration,
            EdgeCDStart, EdgeCDEnd;
            penbrush=EdgeBrush,
            pencolor=EdgeCDColor,
            line_host_id=edge_c_d_host_id,
            line_joint1_id=edge_c_d_joint1_id,
            line_joint2_id=edge_c_d_joint2_id)
        timer += dt
        if timer >= DrawEdgeDuration
            phase = PhaseDrawPointD
            timer = 0f0
        end
    elseif phase == PhaseDrawPointD
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointD,
            PointBrush, PointColor, point_d_id)
        timer += dt
        if timer >= DrawPointDuration
            OdinJuliaBridge.show_point(state_ptr, label_d_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeCEColor)
            phase = PhaseArcDToCForCE
            timer = 0f0
        end
    elseif phase == PhaseArcDToCForCE
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointD, PointC, 0.20f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawCE
            timer = 0f0
        end
    elseif phase == PhaseDrawCE
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawEdgeDuration,
            EdgeCEStart, EdgeCEEnd;
            penbrush=EdgeBrush,
            pencolor=EdgeCEColor,
            line_host_id=edge_c_e_host_id,
            line_joint1_id=edge_c_e_joint1_id,
            line_joint2_id=edge_c_e_joint2_id)
        timer += dt
        if timer >= DrawEdgeDuration
            phase = PhaseDrawPointE
            timer = 0f0
        end
    elseif phase == PhaseDrawPointE
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointE,
            PointBrush, PointColor, point_e_id)
        timer += dt
        if timer >= DrawPointDuration
            OdinJuliaBridge.show_point(state_ptr, label_e_id)
            phase = PhasePenRise
            timer = 0f0
        end
    elseif phase == PhasePenRise
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ, PointE[1], PointE[2])
        timer += dt
        if timer >= PenLiftDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseCompassDescendBAC
            timer = 0f0
        end

    elseif phase == PhaseCompassDescendBAC
        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, DescendDuration, CompassTopZ,
            PointA[1], PointA[2], MarkerAStart[1], MarkerAStart[2])
        timer += dt
        if timer >= DescendDuration
            phase = PhaseHighlightBACForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightBACForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerAStart, AngleBACTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightBACBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightBACBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerAEnd, -AngleBACTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcToACE
            timer = 0f0
        end
    elseif phase == PhaseCompassArcToACE
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointA, PointC,
            MarkerAStart, MarkerCACEStart)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightACEForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightACEForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointC, MarkerCACEStart, AngleACETheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightACEBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightACEBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointC, MarkerCACEEnd, -AngleACETheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcToECD
            timer = 0f0
        end
    elseif phase == PhaseCompassArcToECD
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointC, PointC,
            MarkerCACEStart, MarkerCECDStart; height=0.18f0)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightECDForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightECDForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointC, MarkerCECDStart, AngleECDTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightECDBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightECDBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointC, MarkerCECDEnd, -AngleECDTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcToABC
            timer = 0f0
        end
    elseif phase == PhaseCompassArcToABC
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointC, PointB,
            MarkerCECDStart, MarkerBStart)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightABCForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightABCForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointB, MarkerBStart, AngleABCTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightABCBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightABCBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointB, MarkerBEnd, -AngleABCTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcToCCombine
            timer = 0f0
        end
    elseif phase == PhaseCompassArcToCCombine
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointB, PointC,
            MarkerBStart, MarkerCACBStart)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightACBForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightACBForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointC, MarkerCACBStart, AngleACBTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightACBBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightACBBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointC, MarkerCACBEnd, -AngleACBTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightBCDForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightBCDForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, EmphasisSweepDuration,
            PointC, MarkerBCDStart, AngleBCDTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= EmphasisSweepDuration
            phase = PhaseHighlightBCDBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightBCDBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, EmphasisSweepDuration,
            PointC, MarkerBCDEnd, -AngleBCDTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= EmphasisSweepDuration
            phase = PhaseCompassRise
            timer = 0f0
        end
    elseif phase == PhaseCompassRise
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassLiftDuration, CompassTopZ,
            PointC[1], PointC[2], MarkerBCDStart[1], MarkerBCDStart[2])
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

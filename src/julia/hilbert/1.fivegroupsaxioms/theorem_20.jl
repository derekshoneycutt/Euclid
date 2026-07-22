module HilbertChapterOneTheorem20

using ..OdinJuliaBridge
using ..EuclidAnimations

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

const ThetaA_AB = Float32(atan(PointB[2] - PointA[2], PointB[1] - PointA[1]))
const ThetaA_AC = Float32(atan(PointC[2] - PointA[2], PointC[1] - PointA[1]))
const ThetaB_BA = Float32(atan(PointA[2] - PointB[2], PointA[1] - PointB[1]))
const ThetaB_BC = Float32(atan(PointC[2] - PointB[2], PointC[1] - PointB[1]))
const ThetaC_CA = Float32(atan(PointA[2] - PointC[2], PointA[1] - PointC[1]))
const ThetaC_CB = Float32(atan(PointB[2] - PointC[2], PointB[1] - PointC[1]))
const ThetaC_CD = Float32(atan(PointD[2] - PointC[2], PointD[1] - PointC[1]))
const ThetaC_CE = Float32(atan(PointE[2] - PointC[2], PointE[1] - PointC[1]))

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

const MarkerCACEStart = [
    PointC[1] + MarkerRadius * Float32(cos(ThetaC_CA)),
    PointC[2] + MarkerRadius * Float32(sin(ThetaC_CA)),
    0f0,
]
const MarkerCACEEnd = [
    PointC[1] + MarkerRadius * Float32(cos(ThetaC_CE)),
    PointC[2] + MarkerRadius * Float32(sin(ThetaC_CE)),
    0f0,
]

const MarkerCECDStart = [
    PointC[1] + MarkerRadius * Float32(cos(ThetaC_CE)),
    PointC[2] + MarkerRadius * Float32(sin(ThetaC_CE)),
    0f0,
]
const MarkerCECDEnd = [
    PointC[1] + MarkerRadius * Float32(cos(ThetaC_CD)),
    PointC[2] + MarkerRadius * Float32(sin(ThetaC_CD)),
    0f0,
]

const MarkerCACBStart = [
    PointC[1] + MarkerRadius * Float32(cos(ThetaC_CA)),
    PointC[2] + MarkerRadius * Float32(sin(ThetaC_CA)),
    0f0,
]
const MarkerCACBEnd = [
    PointC[1] + MarkerRadius * Float32(cos(ThetaC_CB)),
    PointC[2] + MarkerRadius * Float32(sin(ThetaC_CB)),
    0f0,
]

const MarkerBCDStart = [
    PointC[1] + MarkerRadius * Float32(cos(ThetaC_CD)),
    PointC[2] + MarkerRadius * Float32(sin(ThetaC_CD)),
    0f0,
]
const MarkerBCDEnd = [
    PointC[1] + MarkerRadius * Float32(cos(ThetaC_CB)),
    PointC[2] + MarkerRadius * Float32(sin(ThetaC_CB)),
    0f0,
]

const AngleBACTheta = ThetaA_AC - ThetaA_AB
const AngleABCTheta = ThetaB_BA - ThetaB_BC
const AngleACETheta = ThetaC_CE - ThetaC_CA
const AngleECDTheta = ThetaC_CD - ThetaC_CE
const AngleACBTheta = ThetaC_CB - ThetaC_CA
const AngleBCDTheta = Float32(π)

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


function get_view_text(state_ptr::Ptr{Cvoid})
    """David Hilbert - Foundations of Geometry - Theorem 20

The sum of the angles of a triangle is two right angles."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    edgeCBHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCBHostId))
    edgeCBJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCBJoint2Id))
    edgeBAHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeBAHostId))
    edgeBAJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeBAJoint2Id))
    edgeACHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeACHostId))
    edgeACJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeACJoint2Id))
    edgeCDHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCDHostId))
    edgeCDJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCDJoint2Id))
    edgeCEHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCEHostId))
    edgeCEJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCEJoint2Id))

    pointBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    pointCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointCId))
    pointAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    pointDId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointDId))
    pointEId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointEId))

    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labelCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelDId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDId))
    labelEId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelEId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [edgeCBHostId, edgeBAHostId, edgeACHostId, edgeCDHostId, edgeCEHostId,
         pointBId, pointCId, pointAId, pointDId, pointEId,
         labelBId, labelCId, labelAId, labelDId, labelEId])

    OdinJuliaBridge.set_point_position(state_ptr, edgeCBJoint2Id, EdgeCBStart)
    OdinJuliaBridge.set_point_position(state_ptr, edgeBAJoint2Id, EdgeBAStart)
    OdinJuliaBridge.set_point_position(state_ptr, edgeACJoint2Id, EdgeACStart)
    OdinJuliaBridge.set_point_position(state_ptr, edgeCDJoint2Id, EdgeCDStart)
    OdinJuliaBridge.set_point_position(state_ptr, edgeCEJoint2Id, EdgeCEStart)

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

function initialize(state_ptr::Ptr{Cvoid})
    edgeCB = OdinJuliaBridge.create_new_line(state_ptr, EdgeCBStart, EdgeCBStart, EdgeCBColor, 0f0)
    edgeBA = OdinJuliaBridge.create_new_line(state_ptr, EdgeBAStart, EdgeBAStart, EdgeBAColor, 0f0)
    edgeAC = OdinJuliaBridge.create_new_line(state_ptr, EdgeACStart, EdgeACStart, EdgeACColor, 0f0)
    edgeCD = OdinJuliaBridge.create_new_line(state_ptr, EdgeCDStart, EdgeCDStart, EdgeCDColor, 0f0)
    edgeCE = OdinJuliaBridge.create_new_line(state_ptr, EdgeCEStart, EdgeCEStart, EdgeCEColor, 0f0)

    pointB = OdinJuliaBridge.create_new_point(state_ptr, PointB, PointColor, 0f0)
    pointC = OdinJuliaBridge.create_new_point(state_ptr, PointC, PointColor, 0f0)
    pointA = OdinJuliaBridge.create_new_point(state_ptr, PointA, PointColor, 0f0)
    pointD = OdinJuliaBridge.create_new_point(state_ptr, PointD, PointColor, 0f0)
    pointE = OdinJuliaBridge.create_new_point(state_ptr, PointE, PointColor, 0f0)

    labelB = OdinJuliaBridge.create_new_label(state_ptr, 'B', LabelBPoint, LabelColor, 16f0)
    labelC = OdinJuliaBridge.create_new_label(state_ptr, 'C', LabelCPoint, LabelColor, 16f0)
    labelA = OdinJuliaBridge.create_new_label(state_ptr, 'A', LabelAPoint, LabelColor, 16f0)
    labelD = OdinJuliaBridge.create_new_label(state_ptr, 'D', LabelDPoint, LabelColor, 16f0)
    labelE = OdinJuliaBridge.create_new_label(state_ptr, 'E', LabelEPoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeCBHostId, Float32(edgeCB.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeCBJoint1Id, Float32(edgeCB.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeCBJoint2Id, Float32(edgeCB.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeBAHostId, Float32(edgeBA.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeBAJoint1Id, Float32(edgeBA.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeBAJoint2Id, Float32(edgeBA.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeACHostId, Float32(edgeAC.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeACJoint1Id, Float32(edgeAC.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeACJoint2Id, Float32(edgeAC.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeCDHostId, Float32(edgeCD.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeCDJoint1Id, Float32(edgeCD.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeCDJoint2Id, Float32(edgeCD.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeCEHostId, Float32(edgeCE.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeCEJoint1Id, Float32(edgeCE.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeCEJoint2Id, Float32(edgeCE.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointBId, Float32(pointB.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointCId, Float32(pointC.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointAId, Float32(pointA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointDId, Float32(pointD.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointEId, Float32(pointE.index))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBId, Float32(labelB.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelCId, Float32(labelC.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAId, Float32(labelA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelDId, Float32(labelD.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelEId, Float32(labelE.index))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    edgeCBHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCBHostId))
    edgeCBJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCBJoint1Id))
    edgeCBJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCBJoint2Id))
    edgeBAHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeBAHostId))
    edgeBAJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeBAJoint1Id))
    edgeBAJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeBAJoint2Id))
    edgeACHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeACHostId))
    edgeACJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeACJoint1Id))
    edgeACJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeACJoint2Id))
    edgeCDHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCDHostId))
    edgeCDJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCDJoint1Id))
    edgeCDJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCDJoint2Id))
    edgeCEHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCEHostId))
    edgeCEJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCEJoint1Id))
    edgeCEJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaEdgeCEJoint2Id))

    pointBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    pointCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointCId))
    pointAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    pointDId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointDId))
    pointEId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointEId))

    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labelCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelDId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDId))
    labelEId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelEId))

    if edgeCBHostId < 0 || edgeBAHostId < 0 || edgeACHostId < 0
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
            state_ptr, timer, DrawPointDuration, PointB, PointBrush, PointColor, pointBId)
        timer += dt
        if timer >= DrawPointDuration
            OdinJuliaBridge.show_point(state_ptr, labelBId)
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
            state_ptr, timer, DrawPointDuration, PointC, PointBrush, PointColor, pointCId)
        timer += dt
        if timer >= DrawPointDuration
            OdinJuliaBridge.show_point(state_ptr, labelCId)
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
            state_ptr, timer, DrawPointDuration, PointA, PointBrush, PointColor, pointAId)
        timer += dt
        if timer >= DrawPointDuration
            OdinJuliaBridge.show_point(state_ptr, labelAId)
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
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawEdgeDuration, EdgeCBStart, EdgeCBEnd,
            EdgeBrush, EdgeCBColor, edgeCBHostId, edgeCBJoint1Id, edgeCBJoint2Id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeBAColor)
            phase = PhaseDrawBA
            timer = 0f0
        end
    elseif phase == PhaseDrawBA
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawEdgeDuration, EdgeBAStart, EdgeBAEnd,
            EdgeBrush, EdgeBAColor, edgeBAHostId, edgeBAJoint1Id, edgeBAJoint2Id)
        timer += dt
        if timer >= DrawEdgeDuration
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
            phase = PhaseDrawPointD
            timer = 0f0
        end
    elseif phase == PhaseDrawPointD
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointD, PointBrush, PointColor, pointDId)
        timer += dt
        if timer >= DrawPointDuration
            OdinJuliaBridge.show_point(state_ptr, labelDId)
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
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawEdgeDuration, EdgeCEStart, EdgeCEEnd,
            EdgeBrush, EdgeCEColor, edgeCEHostId, edgeCEJoint1Id, edgeCEJoint2Id)
        timer += dt
        if timer >= DrawEdgeDuration
            phase = PhaseDrawPointE
            timer = 0f0
        end
    elseif phase == PhaseDrawPointE
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointE, PointBrush, PointColor, pointEId)
        timer += dt
        if timer >= DrawPointDuration
            OdinJuliaBridge.show_point(state_ptr, labelEId)
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
            MarkerAStart, MarkerCACEStart, 0.22f0, 1, :none)
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
            MarkerCACEStart, MarkerCECDStart, 0.18f0, 1, :none)
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
            MarkerCECDStart, MarkerBStart, 0.22f0, 1, :none)
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
            MarkerBStart, MarkerCACBStart, 0.22f0, 1, :none)
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

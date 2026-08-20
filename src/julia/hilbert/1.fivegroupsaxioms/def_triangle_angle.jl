module HilbertChapterOneDefTriangleAngle

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

export get_view_text, initialize, clean, loop

const PointA = [0.26f0, 0.44f0, 0f0]
const PointB = [0.58f0, 0.34f0, 0f0]
const PointC = [0.44f0, 0.74f0, 0f0]

const EdgeABStart = PointA
const EdgeABEnd = PointB
const EdgeACStart = PointA
const EdgeACEnd = PointC
const EdgeBCStart = PointB
const EdgeBCEnd = PointC

const VecAB = PointB - PointA
const VecAC = PointC - PointA
const ThetaAB = atan(VecAB[2], VecAB[1])
const ThetaAC = atan(VecAC[2], VecAC[1])
const AngleTheta = ThetaAC - ThetaAB

const MarkerRadius = 0.13f0
const MarkerStart = [
    PointA[1] + MarkerRadius * cos(ThetaAB),
    PointA[2] + MarkerRadius * sin(ThetaAB),
    0f0,
]
const MarkerEnd = [
    PointA[1] + MarkerRadius * cos(ThetaAB + AngleTheta),
    PointA[2] + MarkerRadius * sin(ThetaAB + AngleTheta),
    0f0,
]

const LabelColor = :plum1
const EdgeABColor = :steelblue
const EdgeACColor = :palevioletred1
const EdgeBCColor = :khaki3
const MarkerColor = :khaki3

const EdgeBrush = 5f0
const MarkerBrush = 1f0
const ResetPenLength = 0.14f0

const LabelAPoint = PointA + [-0.04f0, -0.04f0, 0f0]
const LabelBPoint = PointB + [0.02f0, -0.03f0, 0f0]
const LabelCPoint = PointC + [-0.01f0, 0.03f0, 0f0]
const LabelHPoint = PointA + [0.20f0, -0.08f0, 0f0]
const LabelKPoint = PointA + [0.16f0, 0.19f0, 0f0]

const PenTopZ = 1.4f0
const CompassTopZ = 1.4f0

const DescendDuration = 1.8f0
const DrawEdgeDuration = 2.4f0
const ArcMoveDuration = 1.4f0
const PenLiftDuration = 1.6f0
const MarkerDrawDuration = 1.2f0
const CompassLiftDuration = 1.8f0
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

const MetaMarkerHostId = 31
const MetaMarkerStartId = 32
const MetaMarkerEndId = 33

const MetaLabelAId = 41
const MetaLabelBId = 42
const MetaLabelCId = 43
const MetaLabelHId = 44
const MetaLabelKId = 45

const MetaPhase = 101
const MetaTimer = 102

const PhaseDescendToA = 0f0
const PhaseDrawAB = 1f0
const PhaseArcToAForAC = 2f0
const PhaseDrawAC = 3f0
const PhaseArcToBForBC = 4f0
const PhaseDrawBC = 5f0
const PhasePenLiftForMarker = 6f0
const PhaseDrawMarker = 7f0
const PhaseCompassLift = 8f0
const PhaseFinalHold = 9f0

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - Definition: Triangle Angle

Suppose we have given a triangle ABC. Denote by h, k the two half-rays emanating from A and passing respectively through B and C. The angle (h, k) is then said to be the angle included by the sides AB and AC, or the one opposite to the side BC in the triangle ABC. It contains all of the interior points of the triangle ABC and is represented by the symbol ∠BAC, or by ∠A."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - Definition}: \textit{Triangle Angle}

Suppose we have given a triangle $ABC$ \euclidtriangle[height=2,width=3,thickness=2,edge1_color=palevioletred1,edge2_color=steelblue,edge3_color=khaki3].
Denote by $h$ \euclidline[color=steelblue,length=3,thickness=4], $k$ \euclidline[color=palevioletred1,length=3,thickness=4]
the two half-rays emanating from $A$ \euclidpoint[color=plum1,size=0.5] and passing respectively through
$B$ \euclidpoint[color=plum1,size=0.5] and $C$ \euclidpoint[color=plum1,size=0.5].
The angle $(h, k)$ \euclidangle[color=khaki3,radius=2,end=60,filled] is then said to be the angle included
by the sides $AB$ \euclidline[color=steelblue,length=3,thickness=4] and $AC$ \euclidline[color=palevioletred1,length=3,thickness=4],
or the one opposite to the side $BC$ \euclidline[color=khaki3,length=3,thickness=4] in the
triangle $ABC$ \euclidtriangle[height=2,width=3,thickness=2,edge1_color=palevioletred1,edge2_color=steelblue,edge3_color=khaki3].
It contains all of the interior points of the triangle
$ABC$ \euclidtriangle[height=2,width=3,thickness=2,edge1_color=palevioletred1,edge2_color=steelblue,edge3_color=khaki3]
and is represented by the symbol $\angle BAC$ \euclidangle[color=khaki3,radius=2,end=60,filled], or by $\angle A$ \euclidangle[color=khaki3,radius=2,end=60,filled]."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset the state of the animation cycle back to the start of the animation"""
function reset_cycle_state(state_ptr::Ptr{Cvoid})
    edge_a_b_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeABHostId))
    edge_a_b_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeABJoint2Id))
    edge_a_c_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeACHostId))
    edge_a_c_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeACJoint2Id))
    edge_b_c_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeBCHostId))
    edge_b_c_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeBCJoint2Id))

    marker_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaMarkerHostId))
    marker_end_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaMarkerEndId))

    label_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    label_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    label_c_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    label_h_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelHId))
    label_k_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelKId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [edge_a_b_host_id, edge_a_c_host_id, edge_b_c_host_id, marker_host_id,
         label_a_id, label_b_id, label_c_id, label_h_id, label_k_id])

    OdinJuliaBridge.set_point_position(state_ptr, edge_a_b_joint2_id, EdgeABStart)
    OdinJuliaBridge.set_point_position(state_ptr, edge_a_c_joint2_id, EdgeACStart)
    OdinJuliaBridge.set_point_position(state_ptr, edge_b_c_joint2_id, EdgeBCStart)
    OdinJuliaBridge.set_point_position(state_ptr, marker_end_id, MarkerStart)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescendToA)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.hide_compass(state_ptr)
    OdinJuliaBridge.lock_pen_joint1(state_ptr, PointA[1], PointA[2], PenTopZ)
    OdinJuliaBridge.move_pen_joint2(
        state_ptr, PointA[1], PointA[2], PenTopZ + ResetPenLength)
    OdinJuliaBridge.lock_compass_joint1(
        state_ptr, PointA[1], PointA[2], CompassTopZ, sweep = false)
    OdinJuliaBridge.lock_compass_joint2(
        state_ptr, MarkerStart[1], MarkerStart[2], CompassTopZ, sweep = false)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeABColor)
    OdinJuliaBridge.set_compass_active(state_ptr, 0, MarkerColor)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    edge_a_b = OdinJuliaBridge.create_new_line(
        state_ptr, EdgeABStart, EdgeABStart, EdgeABColor, 0f0)
    edge_a_c = OdinJuliaBridge.create_new_line(
        state_ptr, EdgeACStart, EdgeACStart, EdgeACColor, 0f0)
    edge_b_c = OdinJuliaBridge.create_new_line(
        state_ptr, EdgeBCStart, EdgeBCStart, EdgeBCColor, 0f0)

    marker = OdinJuliaBridge.create_new_filledcircle(state_ptr,
        PointA, MarkerRadius, 0f0, 0f0,
        MarkerColor, 0f0)

    label_a = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', LabelAPoint, LabelColor, 16f0)
    label_b = OdinJuliaBridge.create_new_label(
        state_ptr, 'B', LabelBPoint, LabelColor, 16f0)
    label_c = OdinJuliaBridge.create_new_label(
        state_ptr, 'C', LabelCPoint, LabelColor, 16f0)
    label_h = OdinJuliaBridge.create_new_label(
        state_ptr, 'h', LabelHPoint, LabelColor, 16f0)
    label_k = OdinJuliaBridge.create_new_label(
        state_ptr, 'k', LabelKPoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeABHostId, edge_a_b.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeABJoint1Id, edge_a_b.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeABJoint2Id, edge_a_b.joint2_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeACHostId, edge_a_c.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeACJoint1Id, edge_a_c.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeACJoint2Id, edge_a_c.joint2_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeBCHostId, edge_b_c.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeBCJoint1Id, edge_b_c.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdgeBCJoint2Id, edge_b_c.joint2_id)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarkerHostId, marker.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarkerStartId, marker.start_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarkerEndId, marker.end_id)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAId, label_a.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBId, label_b.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelCId, label_c.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelHId, label_h.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelKId, label_k.index)

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
    edge_a_c_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeACHostId))
    edge_a_c_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeACJoint1Id))
    edge_a_c_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeACJoint2Id))
    edge_b_c_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeBCHostId))
    edge_b_c_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeBCJoint1Id))
    edge_b_c_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdgeBCJoint2Id))

    marker_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaMarkerHostId))
    marker_start_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaMarkerStartId))
    marker_end_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaMarkerEndId))

    label_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    label_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    label_c_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    label_h_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelHId))
    label_k_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelKId))

    if edge_a_b_host_id < 0 || edge_a_c_host_id < 0 || edge_b_c_host_id < 0
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
            OdinJuliaBridge.show_point(state_ptr, label_a_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeABColor)
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
            phase = PhaseArcToAForAC
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_b_id)
        end
    elseif phase == PhaseArcToAForAC
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
            phase = PhaseArcToBForBC
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_c_id)
            OdinJuliaBridge.show_point(state_ptr, label_h_id)
            OdinJuliaBridge.show_point(state_ptr, label_k_id)
        end
    elseif phase == PhaseArcToBForBC
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
            phase = PhasePenLiftForMarker
            timer = 0f0
        end
    elseif phase == PhasePenLiftForMarker
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ, EdgeBCEnd[1], EdgeBCEnd[2])
        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, PenLiftDuration, CompassTopZ,
            PointA[1], PointA[2], MarkerStart[1], MarkerStart[2])

        timer += dt
        if timer >= PenLiftDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseDrawMarker
            timer = 0f0
        end
    elseif phase == PhaseDrawMarker
        EuclidAnimations.animate_draw_filledcircle(state_ptr,
            timer, MarkerDrawDuration, PointA,
            MarkerStart, AngleTheta, MarkerRadius;
            brush=MarkerBrush,
            color=MarkerColor,
            marker_host_id=marker_host_id,
            marker_start_id=marker_start_id,
            marker_end_id=marker_end_id)

        timer += dt
        if timer >= MarkerDrawDuration
            phase = PhaseCompassLift
            timer = 0f0
        end
    elseif phase == PhaseCompassLift
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassLiftDuration, CompassTopZ,
            PointA[1], PointA[2], MarkerEnd[1], MarkerEnd[2])

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

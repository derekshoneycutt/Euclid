module HilbertChapterOneAxiomV

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

export get_view_text, initialize, clean, loop

const LineStart = [0.10f0, 0.55f0, 0f0]
const LineEnd = [0.90f0, 0.55f0, 0f0]

const PointA = [0.24f0, 0.55f0, 0f0]
const PointB = [0.50f0, 0.55f0, 0f0]

const StepSize = 0.07f0
const PointA1 = [PointA[1] + StepSize, PointA[2], 0f0]
const PointA2 = [PointA1[1] + StepSize, PointA1[2], 0f0]
const PointA3 = [PointA2[1] + StepSize, PointA2[2], 0f0]
const PointA4 = [PointA3[1] + StepSize, PointA3[2], 0f0]

const LabelColor = :plum1
const HighlightColor = :palevioletred1
const LineColor = :khaki3
const PointAColor = :steelblue
const PointBColor = :palevioletred1
const StepPointColor = :grey60

const EdgeBrush = 5f0
const PointBrush = 6f0
const PenTopZ = 1.4f0
const ToolResetOffscreenJoint1 = [0.50f0, 1.25f0, 1.55f0]
const ToolResetOffscreenJoint2 = [0.57f0, 1.25f0, 1.55f0]

const LabelAPoint = PointA + [-0.02f0, 0.04f0, 0f0]
const LabelBPoint = PointB + [-0.02f0, 0.04f0, 0f0]
const LabelA1Point = PointA1 + [-0.02f0, -0.05f0, 0f0]
const LabelA2Point = PointA2 + [-0.02f0, -0.05f0, 0f0]
const LabelA3Point = PointA3 + [-0.02f0, -0.05f0, 0f0]
const LabelA4Point = PointA4 + [-0.02f0, -0.05f0, 0f0]

const DescendDuration = 1.7f0
const DrawLineDuration = 2.2f0
const DrawPointDuration = 1.2f0
const ArcMoveDuration = 1.2f0
const DragDuration = 1.1f0
const PenLiftDuration = 1.5f0
const FinalHoldDuration = 0.35f0

const MetaLineHostId = 1
const MetaLineJoint1Id = 2
const MetaLineJoint2Id = 3
const MetaPointAId = 11
const MetaPointBId = 12
const MetaPointA1Id = 13
const MetaPointA2Id = 14
const MetaPointA3Id = 15
const MetaPointA4Id = 16
const MetaLabelAId = 21
const MetaLabelBId = 22
const MetaLabelA1Id = 23
const MetaLabelA2Id = 24
const MetaLabelA3Id = 25
const MetaLabelA4Id = 26
const MetaPhase = 101
const MetaTimer = 102

const PhaseDescendStart = 0f0
const PhaseDrawLine = 1f0
const PhaseArcToA = 2f0
const PhaseDrawA = 3f0
const PhaseArcToB = 4f0
const PhaseDrawB = 5f0
const PhaseArcToA1 = 6f0
const PhaseDrawA1 = 7f0
const PhaseArcToA2 = 8f0
const PhaseDrawA2 = 9f0
const PhaseArcToA3 = 10f0
const PhaseDrawA3 = 11f0
const PhaseArcToA4 = 12f0
const PhaseDrawA4 = 13f0
const PhaseArcBackToA = 14f0
const PhaseHighlightForwardAB = 15f0
const PhaseHighlightForwardBA4 = 16f0
const PhaseHighlightBackA4B = 17f0
const PhaseHighlightBackBA = 18f0
const PhasePenRise = 19f0
const PhaseFinalHold = 20f0

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - Axiom V

Let A₁ be any point upon a straight line between the arbitrarily chosen points A and B. Take the points A₂, A₃, A₄, ... so that A₁ lies between A and A₂, A₂ between A₁ and A₃, A₃ between A₂ and A₄, etc. Moreover, let the segments

    AA₁, A₁A₂, A₂A₃, A₃A₄, ...

be equal to one another. Then, among this series of points, there always exists a certain point Aₙ such that B lies between A and Aₙ."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - Axiom V}

Let $A_1$ \euclidpoint[color=grey60,size=1] be any point upon a straight line \euclidline[color=khaki3,length=3,thickness=4] between the arbitrarily chosen points
$A$ \euclidpoint[color=steelblue,size=1] and $B$ \euclidpoint[color=palevioletred1,size=1]. Take the points
$A_2$ \euclidpoint[color=grey60,size=1], $A_3$ \euclidpoint[color=grey60,size=1], $A_4$ \euclidpoint[color=grey60,size=1],
... so that $A_1$ \euclidpoint[color=grey60,size=1] lies between $A$ \euclidpoint[color=steelblue,size=1] and
$A_2$ \euclidpoint[color=grey60,size=1], $A_2$ \euclidpoint[color=grey60,size=1] between $A_1$ \euclidpoint[color=grey60,size=1]
and $A_3$ \euclidpoint[color=grey60,size=1], $A_3$ \euclidpoint[color=grey60,size=1] between $A_2$ \euclidpoint[color=grey60,size=1]
and $A_4$ \euclidpoint[color=grey60,size=1], etc. Moreover, let the segments

    $AA_1$ \euclidline[color=khaki3,length=3,thickness=4], $A_1A_2$ \euclidline[color=khaki3,length=3,thickness=4], $A_2A_3$ \euclidline[color=khaki3,length=3,thickness=4], $A_3A_4$ \euclidline[color=khaki3,length=3,thickness=4], ...

be equal to one another. Then, among this series of points, there always exists a certain point
$A_n$ \euclidpoint[color=grey60,size=1] such that $B$ \euclidpoint[color=palevioletred1,size=1] lies between
$A$ \euclidpoint[color=steelblue,size=1] and $A_n$ \euclidpoint[color=grey60,size=1]."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset the state of the animation cycle back to the start of the animation"""
function reset_cycle_state(state_ptr::Ptr{Cvoid})
    line_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineHostId))
    line_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineJoint2Id))

    point_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    point_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    point_a1_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointA1Id))
    point_a2_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointA2Id))
    point_a3_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointA3Id))
    point_a4_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointA4Id))

    label_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    label_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    label_a1_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelA1Id))
    label_a2_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelA2Id))
    label_a3_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelA3Id))
    label_a4_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelA4Id))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [line_host_id,
         point_a_id, point_b_id, point_a1_id, point_a2_id, point_a3_id, point_a4_id,
         label_a_id, label_b_id, label_a1_id, label_a2_id, label_a3_id, label_a4_id])

    OdinJuliaBridge.set_point_position(state_ptr, line_joint2_id, LineStart)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescendStart)
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

    OdinJuliaBridge.set_pen_active(state_ptr, 0, LineColor)
    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    baseline = OdinJuliaBridge.create_new_line(
        state_ptr, LineStart, LineStart, LineColor, 0f0)

    point_a = OdinJuliaBridge.create_new_point(state_ptr, PointA, PointAColor, 0f0)
    point_b = OdinJuliaBridge.create_new_point(state_ptr, PointB, PointBColor, 0f0)
    point_a1 = OdinJuliaBridge.create_new_point(state_ptr, PointA1, StepPointColor, 0f0)
    point_a2 = OdinJuliaBridge.create_new_point(state_ptr, PointA2, StepPointColor, 0f0)
    point_a3 = OdinJuliaBridge.create_new_point(state_ptr, PointA3, StepPointColor, 0f0)
    point_a4 = OdinJuliaBridge.create_new_point(state_ptr, PointA4, StepPointColor, 0f0)

    label_a = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', LabelAPoint, LabelColor, 16f0)
    label_b = OdinJuliaBridge.create_new_label(
        state_ptr, 'B', LabelBPoint, LabelColor, 16f0)
    label_a1 = OdinJuliaBridge.create_new_label(
        state_ptr, '1', LabelA1Point, LabelColor, 16f0)
    label_a2 = OdinJuliaBridge.create_new_label(
        state_ptr, '2', LabelA2Point, LabelColor, 16f0)
    label_a3 = OdinJuliaBridge.create_new_label(
        state_ptr, '3', LabelA3Point, LabelColor, 16f0)
    label_a4 = OdinJuliaBridge.create_new_label(
        state_ptr, '4', LabelA4Point, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineHostId, baseline.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineJoint1Id, baseline.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineJoint2Id, baseline.joint2_id)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointAId, point_a.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointBId, point_b.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointA1Id, point_a1.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointA2Id, point_a2.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointA3Id, point_a3.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointA4Id, point_a4.index)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAId, label_a.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBId, label_b.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelA1Id, label_a1.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelA2Id, label_a2.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelA3Id, label_a3.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelA4Id, label_a4.index)

    reset_cycle_state(state_ptr)
end

"""Clean any extra animation data at the end of performance"""
function clean(state_ptr::Ptr{Cvoid})
end

"""Perform an iteration of the animation loop for this animation"""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    line_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineHostId))
    line_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineJoint1Id))
    line_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineJoint2Id))

    point_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    point_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    point_a1_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointA1Id))
    point_a2_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointA2Id))
    point_a3_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointA3Id))
    point_a4_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointA4Id))

    label_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    label_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    label_a1_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelA1Id))
    label_a2_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelA2Id))
    label_a3_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelA3Id))
    label_a4_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelA4Id))

    if line_host_id < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescendStart
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, LineStart[1], LineStart[2])
        timer += dt
        if timer >= DescendDuration
            OdinJuliaBridge.set_pen_active(state_ptr, 0, LineColor)
            phase = PhaseDrawLine
            timer = 0f0
        end
    elseif phase == PhaseDrawLine
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawLineDuration,
            LineStart, LineEnd;
            penbrush=EdgeBrush,
            pencolor=LineColor,
            line_host_id=line_host_id,
            line_joint1_id=line_joint1_id,
            line_joint2_id=line_joint2_id)
        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseArcToA
            timer = 0f0
        end

    elseif phase == PhaseArcToA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, LineEnd, PointA, 0.18f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawA
            timer = 0f0
        end
    elseif phase == PhaseDrawA
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointA,
            PointBrush, PointAColor, point_a_id)
        timer += dt
        if timer >= DrawPointDuration
            OdinJuliaBridge.show_point(state_ptr, label_a_id)
            phase = PhaseArcToB
            timer = 0f0
        end

    elseif phase == PhaseArcToB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointA, PointB, 0.18f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawB
            timer = 0f0
        end
    elseif phase == PhaseDrawB
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointB,
            PointBrush, PointBColor, point_b_id)
        timer += dt
        if timer >= DrawPointDuration
            OdinJuliaBridge.show_point(state_ptr, label_b_id)
            phase = PhaseArcToA1
            timer = 0f0
        end

    elseif phase == PhaseArcToA1
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointB, PointA1, 0.18f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawA1
            timer = 0f0
        end
    elseif phase == PhaseDrawA1
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointA1,
            PointBrush, StepPointColor, point_a1_id)
        timer += dt
        if timer >= DrawPointDuration
            OdinJuliaBridge.show_point(state_ptr, label_a1_id)
            phase = PhaseArcToA2
            timer = 0f0
        end

    elseif phase == PhaseArcToA2
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointA1, PointA2, 0.18f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawA2
            timer = 0f0
        end
    elseif phase == PhaseDrawA2
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointA2,
            PointBrush, StepPointColor, point_a2_id)
        timer += dt
        if timer >= DrawPointDuration
            OdinJuliaBridge.show_point(state_ptr, label_a2_id)
            phase = PhaseArcToA3
            timer = 0f0
        end

    elseif phase == PhaseArcToA3
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointA2, PointA3, 0.18f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawA3
            timer = 0f0
        end
    elseif phase == PhaseDrawA3
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointA3,
            PointBrush, StepPointColor, point_a3_id)
        timer += dt
        if timer >= DrawPointDuration
            OdinJuliaBridge.show_point(state_ptr, label_a3_id)
            phase = PhaseArcToA4
            timer = 0f0
        end

    elseif phase == PhaseArcToA4
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointA3, PointA4, 0.18f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawA4
            timer = 0f0
        end
    elseif phase == PhaseDrawA4
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointA4,
            PointBrush, StepPointColor, point_a4_id)
        timer += dt
        if timer >= DrawPointDuration
            OdinJuliaBridge.show_point(state_ptr, label_a4_id)
            phase = PhaseArcBackToA
            timer = 0f0
        end

    elseif phase == PhaseArcBackToA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointA4, PointA, 0.18f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightForwardAB
            timer = 0f0
        end

    elseif phase == PhaseHighlightForwardAB
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointA, PointB, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightForwardBA4
            timer = 0f0
        end
    elseif phase == PhaseHighlightForwardBA4
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointB, PointA4, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightBackA4B
            timer = 0f0
        end
    elseif phase == PhaseHighlightBackA4B
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointA4, PointB, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightBackBA
            timer = 0f0
        end
    elseif phase == PhaseHighlightBackBA
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointB, PointA, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhasePenRise
            timer = 0f0
        end

    elseif phase == PhasePenRise
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ, PointA[1], PointA[2])
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

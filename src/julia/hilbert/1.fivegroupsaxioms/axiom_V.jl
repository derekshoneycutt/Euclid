module HilbertChapterOneAxiomV

using ..OdinJuliaBridge
using ..EuclidAnimations

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


function get_view_text(state_ptr::Ptr{Cvoid})
    """David Hilbert - Foundations of Geometry - Axiom V

Let A₁ be any point upon a straight line between the arbitrarily chosen points A and B. Take the points A₂, A₃, A₄, ... so that A₁ lies between A and A₂, A₂ between A₁ and A₃, A₃ between A₂ and A₄, etc. Moreover, let the segments

    AA₁, A₁A₂, A₂A₃, A₃A₄, ...

be equal to one another. Then, among this series of points, there always exists a certain point Aₙ such that B lies between A and Aₙ."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    lineHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineHostId))
    lineJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineJoint2Id))

    pointAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    pointBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    pointA1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointA1Id))
    pointA2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointA2Id))
    pointA3Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointA3Id))
    pointA4Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointA4Id))

    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labelA1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelA1Id))
    labelA2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelA2Id))
    labelA3Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelA3Id))
    labelA4Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelA4Id))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [lineHostId,
         pointAId, pointBId, pointA1Id, pointA2Id, pointA3Id, pointA4Id,
         labelAId, labelBId, labelA1Id, labelA2Id, labelA3Id, labelA4Id])

    OdinJuliaBridge.set_point_position(state_ptr, lineJoint2Id, LineStart)

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

function initialize(state_ptr::Ptr{Cvoid})
    baseline = OdinJuliaBridge.create_new_line(state_ptr, LineStart, LineStart, LineColor, 0f0)

    pointA = OdinJuliaBridge.create_new_point(state_ptr, PointA, PointAColor, 0f0)
    pointB = OdinJuliaBridge.create_new_point(state_ptr, PointB, PointBColor, 0f0)
    pointA1 = OdinJuliaBridge.create_new_point(state_ptr, PointA1, StepPointColor, 0f0)
    pointA2 = OdinJuliaBridge.create_new_point(state_ptr, PointA2, StepPointColor, 0f0)
    pointA3 = OdinJuliaBridge.create_new_point(state_ptr, PointA3, StepPointColor, 0f0)
    pointA4 = OdinJuliaBridge.create_new_point(state_ptr, PointA4, StepPointColor, 0f0)

    labelA = OdinJuliaBridge.create_new_label(state_ptr, 'A', LabelAPoint, LabelColor, 16f0)
    labelB = OdinJuliaBridge.create_new_label(state_ptr, 'B', LabelBPoint, LabelColor, 16f0)
    labelA1 = OdinJuliaBridge.create_new_label(state_ptr, '1', LabelA1Point, LabelColor, 16f0)
    labelA2 = OdinJuliaBridge.create_new_label(state_ptr, '2', LabelA2Point, LabelColor, 16f0)
    labelA3 = OdinJuliaBridge.create_new_label(state_ptr, '3', LabelA3Point, LabelColor, 16f0)
    labelA4 = OdinJuliaBridge.create_new_label(state_ptr, '4', LabelA4Point, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineHostId, Float32(baseline.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineJoint1Id, Float32(baseline.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineJoint2Id, Float32(baseline.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointAId, Float32(pointA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointBId, Float32(pointB.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointA1Id, Float32(pointA1.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointA2Id, Float32(pointA2.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointA3Id, Float32(pointA3.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointA4Id, Float32(pointA4.index))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAId, Float32(labelA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBId, Float32(labelB.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelA1Id, Float32(labelA1.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelA2Id, Float32(labelA2.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelA3Id, Float32(labelA3.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelA4Id, Float32(labelA4.index))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    lineHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineHostId))
    lineJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineJoint1Id))
    lineJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineJoint2Id))

    pointAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    pointBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    pointA1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointA1Id))
    pointA2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointA2Id))
    pointA3Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointA3Id))
    pointA4Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointA4Id))

    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labelA1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelA1Id))
    labelA2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelA2Id))
    labelA3Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelA3Id))
    labelA4Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelA4Id))

    if lineHostId < 0
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
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, LineStart, LineEnd,
            EdgeBrush, LineColor, lineHostId, lineJoint1Id, lineJoint2Id)
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
            state_ptr, timer, DrawPointDuration, PointA, PointBrush, PointAColor, pointAId)
        timer += dt
        if timer >= DrawPointDuration
            OdinJuliaBridge.show_point(state_ptr, labelAId)
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
            state_ptr, timer, DrawPointDuration, PointB, PointBrush, PointBColor, pointBId)
        timer += dt
        if timer >= DrawPointDuration
            OdinJuliaBridge.show_point(state_ptr, labelBId)
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
            state_ptr, timer, DrawPointDuration, PointA1, PointBrush, StepPointColor, pointA1Id)
        timer += dt
        if timer >= DrawPointDuration
            OdinJuliaBridge.show_point(state_ptr, labelA1Id)
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
            state_ptr, timer, DrawPointDuration, PointA2, PointBrush, StepPointColor, pointA2Id)
        timer += dt
        if timer >= DrawPointDuration
            OdinJuliaBridge.show_point(state_ptr, labelA2Id)
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
            state_ptr, timer, DrawPointDuration, PointA3, PointBrush, StepPointColor, pointA3Id)
        timer += dt
        if timer >= DrawPointDuration
            OdinJuliaBridge.show_point(state_ptr, labelA3Id)
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
            state_ptr, timer, DrawPointDuration, PointA4, PointBrush, StepPointColor, pointA4Id)
        timer += dt
        if timer >= DrawPointDuration
            OdinJuliaBridge.show_point(state_ptr, labelA4Id)
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

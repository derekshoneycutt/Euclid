module HilbertChapterOneAxiomI1

using ..OdinJuliaBridge
using ..EuclidAnimations

using LinearAlgebra

export get_view_text, initialize, clean, loop

const StartPoint = [0.25f0, 0.75f0, 0f0]
const EndPoint = [0.75f0, 0.25f0, 0f0]
const PenTopZ = 1.4f0

const ALabelPoint = StartPoint + [-0.03f0, 0.01f0, 0f0]
const BLabelPoint = EndPoint + [0.01f0, -0.02f0, 0f0]
const lineaLabelPoint = [0.55f0, 0.55f0, 0f0]
const LabelColor = :plum1

const LineColor = :steelblue
const Point1Color = :palevioletred1
const Point2Color = :khaki3
const LineMaxBrush = 5f0
const PointMaxBrush = 5f0

const DescendDuration = 1.8f0
const DrawLineDuration = 4.2f0
const EndMoveToJoint1Duration = 2f0
const ExtremityTrailDuration = 2f0
const EndMoveToJoint2Duration = 2f0
const EndLiftDuration = 1.8f0

const MetaLineHostId = 1
const MetaLineJoint1Id = 2
const MetaLineJoint2Id = 3
const MetaPhase = 4
const MetaTimer = 5
const MetaPoint1Id = 6
const MetaPoint2Id = 7
const MetaLabelAId = 51
const MetaLabelBId = 52
const MetaLabellineaId = 53

const PhaseDescend = 0f0
const PhasePutJoint1 = 1f0
const PhaseMoveToJoint2 = 2f0
const PhasePutJoint2 = 3f0
const PhaseMoveToJoint1 = 4f0
const PhaseDrawLine = 5f0
const PhaseEndLift = 6f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """David Hilbert - Foundations of Geometry - Axiom I, 1

I, 1. Two distinct points A and B always completely determine a straight line a. We write AB = a or BA = a.

Instead of "determine," we may also employ other forms of expression; for example, we may say A "lies upon" a, A "is a point of" a, a "goes through" A "and through" B, a "joins" A "and" or "with" B, etc. If A lies upon a and at the same time upon another straight line b, we make use also of the expression: "The straight lines" a "and" b "have the point A in common," etc."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    lineHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineHostId))
    lineJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineJoint1Id))
    lineJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineJoint2Id))
    point1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoint1Id))
    point2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoint2Id))

    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labellineaId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabellineaId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [labelAId, labelBId, labellineaId,
         lineHostId, point1Id, point2Id,
        ])

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.set_point_position(
        state_ptr, lineJoint1Id, StartPoint[1], StartPoint[2], StartPoint[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, lineJoint2Id, StartPoint[1], StartPoint[2], StartPoint[3])

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, LineColor)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    point1 = OdinJuliaBridge.create_new_point(
        state_ptr,
        StartPoint[1], StartPoint[2], StartPoint[3],
        Point1Color,
        0f0)
    point2 = OdinJuliaBridge.create_new_point(
        state_ptr,
        EndPoint[1], EndPoint[2], EndPoint[3],
        Point2Color,
        0f0)
    line = OdinJuliaBridge.create_new_line(
        state_ptr,
        StartPoint[1], StartPoint[2], StartPoint[3],
        StartPoint[1], StartPoint[2], StartPoint[3],
        LineColor, 0f0)
    labelA = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', ALabelPoint, LabelColor, 16f0)
    labelB = OdinJuliaBridge.create_new_label(
        state_ptr, 'B', BLabelPoint, LabelColor, 16f0)
    labellinea = OdinJuliaBridge.create_new_label(
        state_ptr, 'a', lineaLabelPoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineHostId, Float32(line.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineJoint1Id, Float32(line.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineJoint2Id, Float32(line.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPoint1Id, Float32(point1.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPoint2Id, Float32(point2.index))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAId, Float32(labelA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBId, Float32(labelB.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabellineaId, Float32(labellinea.index))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    lineHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineHostId))
    lineJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineJoint1Id))
    lineJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineJoint2Id))
    point1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoint1Id))
    point2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoint2Id))

    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labellineaId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabellineaId))

    if lineHostId < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, StartPoint[1], StartPoint[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhasePutJoint1
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelAId)
        end
    elseif phase == PhasePutJoint1
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, ExtremityTrailDuration, StartPoint,
            PointMaxBrush, Point1Color, point1Id)

        timer += dt
        if timer >= ExtremityTrailDuration
            phase = PhaseMoveToJoint2
            timer = 0f0
        end
    elseif phase == PhaseMoveToJoint2
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, EndMoveToJoint2Duration,
            StartPoint, EndPoint, 0.25f0, 1, :none)

        timer += dt
        if timer >= EndMoveToJoint2Duration
            phase = PhasePutJoint2
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelBId)
        end
    elseif phase == PhasePutJoint2
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, ExtremityTrailDuration, EndPoint,
            PointMaxBrush, Point2Color, point2Id)

        timer += dt
        if timer >= ExtremityTrailDuration
            phase = PhaseMoveToJoint1
            timer = 0f0
        end
    elseif phase == PhaseMoveToJoint1
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, EndMoveToJoint1Duration,
            EndPoint, StartPoint, 0.25f0, 1, :none)

        timer += dt
        if timer >= EndMoveToJoint1Duration
            phase = PhaseDrawLine
            timer = 0f0
        end
    elseif phase == PhaseDrawLine
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, StartPoint, EndPoint,
            LineMaxBrush, LineColor, lineHostId, lineJoint1Id, lineJoint2Id)

        if timer / DrawLineDuration >= 0.5
            OdinJuliaBridge.show_point(state_ptr, labellineaId)
        end

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ, EndPoint[1], EndPoint[2])

        timer += dt
        if timer >= EndLiftDuration
            reset_cycle_state(state_ptr)
            return
        end
    end

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, phase)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, timer)
end

end

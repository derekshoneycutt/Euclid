module HilbertChapterOneDefHalfRays

using ..OdinJuliaBridge
using ..EuclidAnimations

export get_view_text, initialize, clean, loop

const LineStart = [0.14f0, 0.52f0, 0f0]
const LineEnd = [0.86f0, 0.52f0, 0f0]
const PointA = [0.31f0, 0.52f0, 0f0]
const PointAPrime = [0.41f0, 0.52f0, 0f0]
const PointO = [0.55f0, 0.52f0, 0f0]
const PointB = [0.72f0, 0.52f0, 0f0]
const HalfRayLeftEnd = [0.08f0, 0.52f0, 0f0]
const HalfRayRightEnd = [0.92f0, 0.52f0, 0f0]
const PenTopZ = 1.4f0

const ALabelPoint = PointA + [-0.02f0, 0.072f0, 0f0]
const APrimeLabelPoint = PointAPrime + [0.012f0, 0.072f0, 0f0]
const OLabelPoint = PointO + [-0.008f0, 0.078f0, 0f0]
const BLabelPoint = PointB + [0.0f0, 0.072f0, 0f0]

const LabelColor = :plum1
const LineColor = :grey60
const PointAColor = :steelblue
const PointAPrimeColor = :steelblue
const PointOColor = :khaki3
const PointBColor = :palevioletred1
const LineMaxBrush = 5f0
const PointMaxBrush = 5f0

const DescendDuration = 1.8f0
const DrawLineDuration = 3.8f0
const ArcMoveDuration = 1.4f0
const DrawPointDuration = 1.5f0
const DragDuration = 2.2f0
const EndLiftDuration = 1.8f0
const FinalHoldDuration = 0.9f0

const MetaLineHostId = 1
const MetaLineJoint1Id = 2
const MetaLineJoint2Id = 3
const MetaPointAId = 11
const MetaPointAPrimeId = 12
const MetaPointOId = 13
const MetaPointBId = 14
const MetaLabelAId = 21
const MetaLabelAPrimeId = 22
const MetaLabelOId = 23
const MetaLabelBId = 24
const MetaPhase = 101
const MetaTimer = 102

const PhaseDescend = 0f0
const PhaseDrawLine = 1f0
const PhaseMoveToPointA = 2f0
const PhasePutPointA = 3f0
const PhaseMoveToPointAPrime = 4f0
const PhasePutPointAPrime = 5f0
const PhaseMoveToPointO = 6f0
const PhasePutPointO = 7f0
const PhaseMoveToPointB = 8f0
const PhasePutPointB = 9f0
const PhaseMoveToPointOForLeftHalfRay = 10f0
const PhaseDragLeftHalfRay = 11f0
const PhaseMoveToPointOForRightHalfRay = 12f0
const PhaseDragRightHalfRay = 13f0
const PhaseEndLift = 14f0
const PhaseFinalHold = 15f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """David Hilbert - Foundations of Geometry - Definition: Half-rays

If A, A', O, B are four points of a straight line a, where O lies between A and B but not between A and A', then points A and A' are on the same side of O, and points A and B are on different sides of O.

All points of a that lie on the same side of O, taken together, are called a half-ray emanating from O."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    lineHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineHostId))
    lineJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineJoint1Id))
    lineJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineJoint2Id))
    pointAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    pointAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAPrimeId))
    pointOId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointOId))
    pointBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAPrimeId))
    labelOId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelOId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [lineHostId,
         pointAId, pointAPrimeId, pointOId, pointBId,
         labelAId, labelAPrimeId, labelOId, labelBId])

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.set_point_position(state_ptr, lineJoint1Id, LineStart)
    OdinJuliaBridge.set_point_position(state_ptr, lineJoint2Id, LineStart)

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, LineColor)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    line = OdinJuliaBridge.create_new_line(
        state_ptr, LineStart, LineStart, LineColor, 0f0)
    pointA = OdinJuliaBridge.create_new_point(
        state_ptr, PointA, PointAColor, 0f0)
    pointAPrime = OdinJuliaBridge.create_new_point(
        state_ptr, PointAPrime, PointAPrimeColor, 0f0)
    pointO = OdinJuliaBridge.create_new_point(
        state_ptr, PointO, PointOColor, 0f0)
    pointB = OdinJuliaBridge.create_new_point(
        state_ptr, PointB, PointBColor, 0f0)

    labelA = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', ALabelPoint, LabelColor, 16f0)
    labelAPrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'A', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        APrimeLabelPoint, LabelColor, 16f0)
    labelO = OdinJuliaBridge.create_new_label(
        state_ptr, 'O', OLabelPoint, LabelColor, 16f0)
    labelB = OdinJuliaBridge.create_new_label(
        state_ptr, 'B', BLabelPoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineHostId, Float32(line.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineJoint1Id, Float32(line.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineJoint2Id, Float32(line.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointAId, Float32(pointA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointAPrimeId, Float32(pointAPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointOId, Float32(pointO.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointBId, Float32(pointB.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAId, Float32(labelA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAPrimeId, Float32(labelAPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelOId, Float32(labelO.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBId, Float32(labelB.index))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    lineHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineHostId))
    lineJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineJoint1Id))
    lineJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineJoint2Id))
    pointAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    pointAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAPrimeId))
    pointOId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointOId))
    pointBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAPrimeId))
    labelOId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelOId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))

    if lineHostId < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, LineStart[1], LineStart[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawLine
            timer = 0f0
        end
    elseif phase == PhaseDrawLine
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, LineStart, LineEnd,
            LineMaxBrush, LineColor, lineHostId, lineJoint1Id, lineJoint2Id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseMoveToPointA
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            LineEnd, PointA, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePutPointA
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelAId)
        end
    elseif phase == PhasePutPointA
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointA,
            PointMaxBrush, PointAColor, pointAId)

        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseMoveToPointAPrime
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointAPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointA, PointAPrime, 0.2f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePutPointAPrime
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelAPrimeId)
        end
    elseif phase == PhasePutPointAPrime
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointAPrime,
            PointMaxBrush, PointAPrimeColor, pointAPrimeId)

        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseMoveToPointO
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointO
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointAPrime, PointO, 0.2f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePutPointO
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelOId)
        end
    elseif phase == PhasePutPointO
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointO,
            PointMaxBrush, PointOColor, pointOId)

        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseMoveToPointB
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointO, PointB, 0.2f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePutPointB
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelBId)
        end
    elseif phase == PhasePutPointB
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointB,
            PointMaxBrush, PointBColor, pointBId)

        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseMoveToPointOForLeftHalfRay
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointOForLeftHalfRay
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointB, PointO, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragLeftHalfRay
            timer = 0f0
            OdinJuliaBridge.set_pen_active(state_ptr, 0, PointOColor)
        end
    elseif phase == PhaseDragLeftHalfRay
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration,
            PointO, HalfRayLeftEnd, PointOColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseMoveToPointOForRightHalfRay
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointOForRightHalfRay
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            HalfRayLeftEnd, PointO, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragRightHalfRay
            timer = 0f0
        end
    elseif phase == PhaseDragRightHalfRay
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration,
            PointO, HalfRayRightEnd, PointOColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ,
            HalfRayRightEnd[1], HalfRayRightEnd[2])

        timer += dt
        if timer >= EndLiftDuration
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

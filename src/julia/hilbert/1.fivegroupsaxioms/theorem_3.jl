module HilbertChapterOneTheorem3

using ..OdinJuliaBridge
using ..EuclidAnimations

export get_view_text, initialize, clean, loop

const LineStart = [0.16f0, 0.52f0, 0f0]
const LineEnd = [0.84f0, 0.52f0, 0f0]
const PointA = [0.34f0, 0.52f0, 0f0]
const PointB = [0.68f0, 0.52f0, 0f0]
const PenTopZ = 1.4f0

const LineColor = :grey60
const PointAColor = :steelblue
const PointBColor = :palevioletred1
const PointTapColor = :khaki3
const LineMaxBrush = 5f0
const PointMaxBrush = 5f0

const DescendDuration = 1.8f0
const DrawLineDuration = 4.2f0
const ArcMoveDuration = 2f0
const PointTrailDuration = 2f0
const TapSweepDuration = 5f0
const EndLiftDuration = 1.8f0

const MetaLineHostId = 1
const MetaLineJoint1Id = 2
const MetaLineJoint2Id = 3
const MetaPointAId = 11
const MetaPointBId = 12
const MetaPhase = 101
const MetaTimer = 102

const PhaseDescend = 0f0
const PhaseDrawLine = 1f0
const PhaseMoveToPointA = 2f0
const PhasePutPointA = 3f0
const PhaseMoveToPointB = 4f0
const PhasePutPointB = 5f0
const PhaseTapToPointA = 6f0
const PhaseTapToPointB = 7f0
const PhaseEndLift = 8f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """David Hilbert - Foundations of Geometry - Theorem 3

Between any two points of a straight line, there always exists an unlimited number of points."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    lineHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineHostId))
    lineJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineJoint1Id))
    lineJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineJoint2Id))
    pointAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    pointBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))

    OdinJuliaBridge.hide_point_batch(state_ptr, [lineHostId, pointAId, pointBId])

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
    pointB = OdinJuliaBridge.create_new_point(
        state_ptr, PointB, PointBColor, 0f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineHostId, Float32(line.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineJoint1Id, Float32(line.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineJoint2Id, Float32(line.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointAId, Float32(pointA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointBId, Float32(pointB.index))

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
        end
    elseif phase == PhasePutPointA
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointTrailDuration, PointA,
            PointMaxBrush, PointAColor, pointAId)

        timer += dt
        if timer >= PointTrailDuration
            phase = PhaseMoveToPointB
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointA, PointB, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePutPointB
            timer = 0f0
        end
    elseif phase == PhasePutPointB
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointTrailDuration, PointB,
            PointMaxBrush, PointBColor, pointBId)

        timer += dt
        if timer >= PointTrailDuration
            phase = PhaseTapToPointA
            timer = 0f0
        end
    elseif phase == PhaseTapToPointA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, TapSweepDuration,
            PointB, PointA, 0.15f0, 10, PointTapColor)

        timer += dt
        if timer >= TapSweepDuration
            phase = PhaseTapToPointB
            timer = 0f0
        end
    elseif phase == PhaseTapToPointB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, TapSweepDuration,
            PointA, PointB, 0.15f0, 10, PointTapColor)

        timer += dt
        if timer >= TapSweepDuration
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ, PointB[1], PointB[2])

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
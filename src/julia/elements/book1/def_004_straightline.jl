module ElementsOneDefinitionStraightLine

using ..OdinJuliaBridge
using ..EuclidAnimations

using LinearAlgebra

export get_view_text, initialize, clean, loop

const StartPoint = [0.25f0, 0.75f0, 0f0]
const EndPoint = [0.75f0, 0.25f0, 0f0]
const PenTopZ = 1.4f0

const LineColor = :steelblue
const PointColor = :palevioletred1
const LineMaxBrush = 5f0
const PointMaxBrush = 5f0

const DescendDuration = 1.8f0
const EndMoveToPutJoint2Duration = 2f0
const ExtremityTrailDuration = 2f0
const EndMoveToStartDuration = 2f0
const DrawLineDuration = 4.2f0
const EndMoveToJoint1Duration = 5f0
const EndMoveToJoint2Duration = 5f0
const EndLiftDuration = 1.8f0

const MetaLineHostId = 1
const MetaLineJoint1Id = 2
const MetaLineJoint2Id = 3
const MetaPhase = 4
const MetaTimer = 5
const MetaPoint1Id = 6
const MetaPoint2Id = 7

const PhaseDescend = 0f0
const PhasePutJoint1 = 1f0
const PhaseMoveToPutJoint2 = 2f0
const PhasePutJoint2 = 3f0
const PhaseMoveToStart = 4f0
const PhaseDrawLine = 5f0
const PhaseMoveToJoint1 = 6f0
const PhaseMoveToJoint2 = 7f0
const PhaseEndLift = 8f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """Euclid Elements - Book I - Definition: Straight Line

A straight line is a line which lies evenly with the points on itself."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    lineHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineHostId))
    lineJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineJoint1Id))
    lineJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineJoint2Id))
    point1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoint1Id))
    point2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.hide_point(state_ptr, lineHostId)
    OdinJuliaBridge.set_point_position(
        state_ptr, lineJoint1Id, StartPoint[1], StartPoint[2], StartPoint[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, lineJoint2Id, StartPoint[1], StartPoint[2], StartPoint[3])

    OdinJuliaBridge.hide_point_batch(state_ptr, [point1Id, point2Id])

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, LineColor)
end

function initialize(state_ptr::Ptr{Cvoid})
    point1 = OdinJuliaBridge.create_new_point(
        state_ptr,
        StartPoint[1], StartPoint[2], StartPoint[3],
        PointColor,
        0f0)
    point2 = OdinJuliaBridge.create_new_point(
        state_ptr,
        EndPoint[1], EndPoint[2], EndPoint[3],
        PointColor,
        0f0)
    line = OdinJuliaBridge.create_new_line(
        state_ptr,
        StartPoint[1], StartPoint[2], StartPoint[3],
        StartPoint[1], StartPoint[2], StartPoint[3],
        LineColor, 0f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineHostId, Float32(line.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineJoint1Id, Float32(line.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineJoint2Id, Float32(line.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPoint1Id, Float32(point1.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPoint2Id, Float32(point2.index))

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
        end
    elseif phase == PhasePutJoint1
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, ExtremityTrailDuration, StartPoint,
            PointMaxBrush, PointColor, point1Id)

        timer += dt
        if timer >= ExtremityTrailDuration
            phase = PhaseMoveToPutJoint2
            timer = 0f0
        end
    elseif phase == PhaseMoveToPutJoint2
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, EndMoveToPutJoint2Duration,
            StartPoint, EndPoint, 0.25f0, 1, :none)

        timer += dt
        if timer >= EndMoveToPutJoint2Duration
            phase = PhasePutJoint2
            timer = 0f0
        end
    elseif phase == PhasePutJoint2
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, ExtremityTrailDuration, EndPoint,
            PointMaxBrush, PointColor, point2Id)

        timer += dt
        if timer >= ExtremityTrailDuration
            phase = PhaseMoveToStart
            timer = 0f0
        end
    elseif phase == PhaseMoveToStart
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, EndMoveToStartDuration,
            EndPoint, StartPoint, 0.25f0, 1, :none)

        timer += dt
        if timer >= EndMoveToStartDuration
            phase = PhaseDrawLine
            timer = 0f0
        end
    elseif phase == PhaseDrawLine
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, StartPoint, EndPoint,
            LineMaxBrush, LineColor, lineHostId, lineJoint1Id, lineJoint2Id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseMoveToJoint1
            timer = 0f0
        end
    elseif phase == PhaseMoveToJoint1
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, EndMoveToJoint1Duration,
            EndPoint, StartPoint, 0.15f0, 10, PointColor)

        timer += dt
        if timer >= EndMoveToJoint1Duration
            phase = PhaseMoveToJoint2
            timer = 0f0
        end
    elseif phase == PhaseMoveToJoint2
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, EndMoveToJoint1Duration,
            StartPoint, EndPoint, 0.15f0, 10, PointColor)

        timer += dt
        if timer >= EndMoveToJoint2Duration
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

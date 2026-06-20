module ElementsOneDefinitionLineExtremities

using ..EuclidBridge
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

const PhaseDescend = 0f0
const PhaseDrawLine = 1f0
const PhaseMoveToJoint1 = 2f0
const PhasePutJoint1 = 3f0
const PhaseMoveToJoint2 = 4f0
const PhasePutJoint2 = 5f0
const PhaseEndLift = 6f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """Euclid Elements - Book I - Definition: Line Extremities

The extremities of a line are points."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    lineHostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLineHostId))
    lineJoint1Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLineJoint1Id))
    lineJoint2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLineJoint2Id))
    point1Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaPoint1Id))
    point2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaPoint2Id))

    EuclidBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    EuclidBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    EuclidBridge.hide_point(state_ptr, lineHostId)
    EuclidBridge.set_point_position(
        state_ptr, lineJoint1Id, StartPoint[1], StartPoint[2], StartPoint[3])
    EuclidBridge.set_point_position(
        state_ptr, lineJoint2Id, StartPoint[1], StartPoint[2], StartPoint[3])

    EuclidBridge.hide_point_batch(state_ptr, [point1Id, point2Id])

    EuclidBridge.show_pen(state_ptr)
    EuclidBridge.set_pen_active(state_ptr, 1, LineColor)
end

function initialize(state_ptr::Ptr{Cvoid})
    line = EuclidBridge.create_new_line(
        state_ptr,
        StartPoint[1], StartPoint[2], StartPoint[3],
        StartPoint[1], StartPoint[2], StartPoint[3],
        LineColor, 0f0)
    point1 = EuclidBridge.create_new_point(
        state_ptr,
        StartPoint[1], StartPoint[2], StartPoint[3],
        PointColor,
        0f0)
    point2 = EuclidBridge.create_new_point(
        state_ptr,
        EndPoint[1], EndPoint[2], EndPoint[3],
        PointColor,
        0f0)

    EuclidBridge.set_animation_meta(state_ptr, MetaLineHostId, Float32(line.hostId))
    EuclidBridge.set_animation_meta(state_ptr, MetaLineJoint1Id, Float32(line.joint1Id))
    EuclidBridge.set_animation_meta(state_ptr, MetaLineJoint2Id, Float32(line.joint2Id))
    EuclidBridge.set_animation_meta(state_ptr, MetaPoint1Id, Float32(point1.index))
    EuclidBridge.set_animation_meta(state_ptr, MetaPoint2Id, Float32(point2.index))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    lineHostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLineHostId))
    lineJoint1Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLineJoint1Id))
    lineJoint2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLineJoint2Id))
    point1Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaPoint1Id))
    point2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaPoint2Id))

    if lineHostId < 0
        return
    end

    phase = EuclidBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = EuclidBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, StartPoint[1], StartPoint[2])

        timer += dt
        if timer >= DescendDuration
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
            EndPoint, StartPoint, 0.25f0, 1, :none)

        timer += dt
        if timer >= EndMoveToJoint1Duration
            phase = PhasePutJoint1
            timer = 0f0
        end
    elseif phase == PhasePutJoint1
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, ExtremityTrailDuration, StartPoint,
            PointMaxBrush, PointColor, point1Id)

        timer += dt
        if timer >= ExtremityTrailDuration
            phase = PhaseMoveToJoint2
            timer = 0f0
        end
    elseif phase == PhaseMoveToJoint2
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, EndMoveToJoint1Duration,
            StartPoint, EndPoint, 0.25f0, 1, :none)
        timer += dt
        if timer >= EndMoveToJoint2Duration
            phase = PhasePutJoint2
            timer = 0f0
        end
    elseif phase == PhasePutJoint2
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, ExtremityTrailDuration, EndPoint,
            PointMaxBrush, PointColor, point2Id)

        timer += dt
        if timer >= ExtremityTrailDuration
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

    EuclidBridge.set_animation_meta(state_ptr, MetaPhase, phase)
    EuclidBridge.set_animation_meta(state_ptr, MetaTimer, timer)
end

end

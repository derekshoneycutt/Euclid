module ElementsOnePostulatesFiniteLine

using ..EuclidBridge
using ..EuclidAnimations

using LinearAlgebra

export get_view_text, initialize, clean, loop

const StartPoint = [0.25f0, 0.75f0, 0f0]
const MidPoint = [0.3f0, 0.7f0, 0f0]
const EndPoint = [0.75f0, 0.25f0, 0f0]
const PenTopZ = 1.4f0

const LineColor = :steelblue
const Point1Color = :palevioletred1
const Point2Color = :khaki3
const LineMaxBrush = 5f0
const PointMaxBrush = 5f0

const DescendDuration = 1.8f0
const MoveToJoint1Duration = 1f0
const MoveToJoint2Duration = 1f0
const ExtremityTrailDuration = 2f0
const DrawInitLineDuration = 1f0
const DrawLineDuration = 4.2f0
const EndLiftDuration = 1.8f0

const MetaInitLineHostId = 1
const MetaInitLineJoint1Id = 2
const MetaInitLineJoint2Id = 3
const MetaLineHostId = 4
const MetaLineJoint1Id = 5
const MetaLineJoint2Id = 6
const MetaPoint1Id = 7
const MetaPoint2Id = 8
const MetaPhase = 9
const MetaTimer = 10

const PhaseDescend = 0f0
const PhasePutJoint1 = 1f0
const PhaseMoveToJoint2 = 2f0
const PhasePutJoint2 = 3f0
const PhaseMoveToJoint1 = 4f0
const PhaseDrawInitLine = 5f0
const PhaseMoveToJoint1Again = 6f0
const PhaseDrawLine = 7f0
const PhaseEndLift = 8f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """Euclid Elements - Book I - Postulates: Produce a Finite Line

Let the following be postulated:

To produce a finite straight line continuously in a straight line."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    point1Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaPoint1Id))
    point2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaPoint2Id))
    initLineHostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaInitLineHostId))
    initLineJoint1Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaInitLineJoint1Id))
    initLineJoint2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaInitLineJoint2Id))
    lineHostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLineHostId))
    lineJoint1Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLineJoint1Id))
    lineJoint2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLineJoint2Id))

    EuclidBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    EuclidBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    EuclidBridge.hide_point(state_ptr, initLineHostId)
    EuclidBridge.set_point_position(
        state_ptr, initLineJoint1Id, StartPoint[1], StartPoint[2], StartPoint[3])
    EuclidBridge.set_point_position(
        state_ptr, initLineJoint2Id, StartPoint[1], StartPoint[2], StartPoint[3])

    EuclidBridge.hide_point(state_ptr, lineHostId)
    EuclidBridge.set_point_position(
        state_ptr, lineJoint1Id, StartPoint[1], StartPoint[2], StartPoint[3])
    EuclidBridge.set_point_position(
        state_ptr, lineJoint2Id, StartPoint[1], StartPoint[2], StartPoint[3])

    EuclidBridge.hide_point(state_ptr, point1Id)
    EuclidBridge.hide_point(state_ptr, point2Id)

    EuclidBridge.show_pen(state_ptr)
    EuclidBridge.set_pen_active(state_ptr, 0, LineColor)
end

function initialize(state_ptr::Ptr{Cvoid})
    point1 = EuclidBridge.create_new_point(
        state_ptr,
        StartPoint[1], StartPoint[2], StartPoint[3],
        Point1Color,
        0f0)
    point2 = EuclidBridge.create_new_point(
        state_ptr,
        EndPoint[1], EndPoint[2], EndPoint[3],
        Point2Color,
        0f0)

    initLine = EuclidBridge.create_new_line(
        state_ptr,
        StartPoint[1], StartPoint[2], StartPoint[3],
        MidPoint[1], MidPoint[2], MidPoint[3],
        LineColor, 5f0)
    EuclidBridge.show_point(state_ptr, initLine.hostId)

    line = EuclidBridge.create_new_line(
        state_ptr,
        StartPoint[1], StartPoint[2], StartPoint[3],
        StartPoint[1], StartPoint[2], StartPoint[3],
        LineColor, 0f0)

    EuclidBridge.set_animation_meta(state_ptr, MetaPoint1Id, Float32(point1.index))
    EuclidBridge.set_animation_meta(state_ptr, MetaPoint2Id, Float32(point2.index))
    EuclidBridge.set_animation_meta(state_ptr, MetaInitLineHostId, Float32(initLine.hostId))
    EuclidBridge.set_animation_meta(state_ptr, MetaInitLineJoint1Id, Float32(initLine.joint1Id))
    EuclidBridge.set_animation_meta(state_ptr, MetaInitLineJoint2Id, Float32(initLine.joint2Id))
    EuclidBridge.set_animation_meta(state_ptr, MetaLineHostId, Float32(line.hostId))
    EuclidBridge.set_animation_meta(state_ptr, MetaLineJoint1Id, Float32(line.joint1Id))
    EuclidBridge.set_animation_meta(state_ptr, MetaLineJoint2Id, Float32(line.joint2Id))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    point1Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaPoint1Id))
    point2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaPoint2Id))
    initLineHostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaInitLineHostId))
    initLineJoint1Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaInitLineJoint1Id))
    initLineJoint2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaInitLineJoint2Id))
    lineHostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLineHostId))
    lineJoint1Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLineJoint1Id))
    lineJoint2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLineJoint2Id))

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
            phase = PhasePutJoint1
            timer = 0f0
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
            state_ptr, timer, MoveToJoint2Duration,
            StartPoint, MidPoint, 0.15f0, 1, :none)

        timer += dt
        if timer >= MoveToJoint2Duration
            phase = PhasePutJoint2
            timer = 0f0
        end
    elseif phase == PhasePutJoint2
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, ExtremityTrailDuration, MidPoint,
            PointMaxBrush, Point2Color, point2Id)

        timer += dt
        if timer >= ExtremityTrailDuration
            phase = PhaseMoveToJoint1
            timer = 0f0
        end
    elseif phase == PhaseMoveToJoint1
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, MoveToJoint1Duration,
            MidPoint, StartPoint, 0.15f0, 1, :none)

        timer += dt
        if timer >= MoveToJoint1Duration
            phase = PhaseDrawInitLine
            timer = 0f0
        end
    elseif phase == PhaseDrawInitLine
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawInitLineDuration, StartPoint, MidPoint,
            LineMaxBrush, LineColor, initLineHostId, initLineJoint1Id, initLineJoint2Id)

        timer += dt
        if timer >= DrawInitLineDuration
            phase = PhaseMoveToJoint1Again
            timer = 0f0
        end
    elseif phase == PhaseMoveToJoint1Again
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, MoveToJoint1Duration,
            MidPoint, StartPoint, 0.25f0, 1, :none)

        timer += dt
        if timer >= MoveToJoint1Duration
            phase = PhaseDrawLine
            timer = 0f0
        end
    elseif phase == PhaseDrawLine
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, StartPoint, EndPoint,
            LineMaxBrush, LineColor, lineHostId, lineJoint1Id, lineJoint2Id)

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

    EuclidBridge.set_animation_meta(state_ptr, MetaPhase, phase)
    EuclidBridge.set_animation_meta(state_ptr, MetaTimer, timer)
end

end

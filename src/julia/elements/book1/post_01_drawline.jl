module ElementsOnePostulatesDrawLine

using LinearAlgebra

include("../../euclidbridge.jl")

export get_view_text, initialize, clean, loop

const StartPoint = [0.25f0, 0.75f0, 0f0]
const EndPoint = [0.75f0, 0.25f0, 0f0]

const LineColor = :steelblue
const Point1Color = :palevioletred1
const Point2Color = :khaki3
const LineMaxBrush = 5f0
const PointMaxBrush = 5f0

const PenTopZ = 1.4f0
const PenLength = 0.14f0
const PenTiltFloorAngle = π / 4f0
const PenConeRadius = 0.02f0
const PenConeSpinSpeed = 8f0
const PenConeTipHeight = Float32(sqrt(PenLength * PenLength - PenConeRadius * PenConeRadius))

const DescendDuration = 1.8f0
const TiltDuration = 0.4f0
const DrawDuration = 2.7f0
const EndStraightenDuration = 0.4f0
const EndMoveToJoint1Duration = 2f0
const ExtremityTrailDuration = 2f0
const EndMoveToJoint2Duration = 2f0
const EndLiftDuration = 1.8f0

const SegmentVec = EndPoint - StartPoint
const SegmentVecLen = norm(SegmentVec)
const PenDirX = SegmentVecLen > 0f0 ? SegmentVec[1] / SegmentVecLen : 1f0
const PenDirY = SegmentVecLen > 0f0 ? SegmentVec[2] / SegmentVecLen : 0f0

const MetaLineHostId = 1
const MetaLineJoint1Id = 2
const MetaLineJoint2Id = 3
const MetaPhase = 4
const MetaTimer = 5
const MetaPoint1Id = 6
const MetaPoint2Id = 7

const PhaseDescend = 0f0
const PhasePutJoint1 = 1f0
const PhaseMoveToJoint2 = 2f0
const PhasePutJoint2 = 3f0
const PhaseMoveToJoint1 = 4f0
const PhaseTilt = 5f0
const PhaseDraw = 6f0
const PhaseEndStraighten = 7f0
const PhaseEndLift = 8f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """Euclid Elements - Book I - Proposition: Draw a Line:

Let the following be postulated:

To draw a straight line from any point to any point."""
end

function show_full_point(
    state_ptr::Ptr{Cvoid}, pointId::Integer, color::Symbol,
    pointX::Float32, pointY::Float32, pointZ::Float32)

    EuclidBridge.show_point(state_ptr, pointId)
    EuclidBridge.set_point_color(state_ptr, pointId, color)
    EuclidBridge.set_point_position(state_ptr, pointId, pointX, pointY, pointZ)
    EuclidBridge.set_point_brush(state_ptr, pointId, PointMaxBrush)
end

function show_full_line(
    state_ptr::Ptr{Cvoid}, lineHostId::Integer, lineJoint1Id::Integer, lineJoint2Id::Integer)
    EuclidBridge.show_point(state_ptr, lineHostId)
    EuclidBridge.set_point_color(state_ptr, lineHostId, LineColor)
    EuclidBridge.set_point_brush(state_ptr, lineHostId, LineMaxBrush)
    EuclidBridge.set_point_position(
        state_ptr, lineJoint1Id, StartPoint[1], StartPoint[2], StartPoint[3])
    EuclidBridge.set_point_position(
        state_ptr, lineJoint2Id, EndPoint[1], EndPoint[2], EndPoint[3])
end

function hide_line(
    state_ptr::Ptr{Cvoid}, lineHostId::Integer, lineJoint1Id::Integer, lineJoint2Id::Integer)
    EuclidBridge.hide_point(state_ptr, lineHostId)
    EuclidBridge.set_point_position(
        state_ptr, lineJoint1Id, StartPoint[1], StartPoint[2], StartPoint[3])
    EuclidBridge.set_point_position(
        state_ptr, lineJoint2Id, StartPoint[1], StartPoint[2], StartPoint[3])
end

function place_pen_at_floor_angle(
    state_ptr::Ptr{Cvoid}, tipX::Float32, tipY::Float32, tipZ::Float32, floorAngle::Float32)
    horizontalLength = PenLength * Float32(cos(floorAngle))
    verticalLength = PenLength * Float32(sin(floorAngle))

    shaftX = tipX + PenDirX * horizontalLength
    shaftY = tipY + PenDirY * horizontalLength
    shaftZ = tipZ + verticalLength

    EuclidBridge.lock_pen_joint1(state_ptr, tipX, tipY, tipZ)
    EuclidBridge.move_pen_joint2(state_ptr, shaftX, shaftY, shaftZ)
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    lineHostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLineHostId))
    lineJoint1Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLineJoint1Id))
    lineJoint2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLineJoint2Id))
    point1Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaPoint1Id))
    point2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaPoint2Id))

    EuclidBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    EuclidBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    hide_line(state_ptr, lineHostId, lineJoint1Id, lineJoint2Id)

    EuclidBridge.hide_point(state_ptr, point1Id)
    EuclidBridge.hide_point(state_ptr, point2Id)

    EuclidBridge.show_pen(state_ptr)
    EuclidBridge.set_pen_active(state_ptr, 1, LineColor)
    place_pen_at_floor_angle(state_ptr, StartPoint[1], StartPoint[2], PenTopZ, π / 2f0)
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
    line = EuclidBridge.create_new_line(
        state_ptr,
        StartPoint[1], StartPoint[2], StartPoint[3],
        StartPoint[1], StartPoint[2], StartPoint[3],
        LineColor, 0f0)

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
        t = clamp(timer / DescendDuration, 0f0, 1f0)

        tipZ = PenTopZ + (StartPoint[3] - PenTopZ) * t
        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 0, LineColor)
        place_pen_at_floor_angle(
            state_ptr, StartPoint[1], StartPoint[2], tipZ, π / 2f0)

        timer += dt
        if timer >= DescendDuration
            phase = PhasePutJoint1
            timer = 0f0
            place_pen_at_floor_angle(
                state_ptr, StartPoint[1], StartPoint[2], StartPoint[3], π / 2f0)
        end
    elseif phase == PhasePutJoint1
        t = clamp(timer / ExtremityTrailDuration, 0f0, 1f0)
        EuclidBridge.set_pen_active(state_ptr, 1, Point1Color)

        theta = timer * PenConeSpinSpeed
        join2Pos = StartPoint + [
            PenConeRadius * Float32(cos(theta)),
            PenConeRadius * Float32(sin(theta)),
            PenConeTipHeight ]

        EuclidBridge.lock_pen_joint1(state_ptr, StartPoint[1], StartPoint[2], StartPoint[3])
        EuclidBridge.move_pen_joint2(state_ptr, join2Pos[1], join2Pos[2], join2Pos[3])

        show_full_point(state_ptr, point1Id, Point1Color,
            StartPoint[1], StartPoint[2], StartPoint[3])

        EuclidBridge.emit_trailing_particle(state_ptr, StartPoint[1], StartPoint[2], Point1Color)

        timer += dt
        if timer >= ExtremityTrailDuration
            phase = PhaseMoveToJoint2
            timer = 0f0
            place_pen_at_floor_angle(
                state_ptr, StartPoint[1], StartPoint[2], StartPoint[3], π / 2f0)
        end
    elseif phase == PhaseMoveToJoint2
        t = clamp(timer / EndMoveToJoint2Duration, 0f0, 1f0)
        EuclidBridge.set_pen_active(state_ptr, 0, Point1Color)

        vec = EndPoint - StartPoint
        tvec = t * vec
        tvec[3] = sin(t * π) * 0.25f0
        usePoint = StartPoint + tvec
        usePoint[3] = clamp(usePoint[3], 0f0, 1f0)
        place_pen_at_floor_angle(
            state_ptr, usePoint[1], usePoint[2], usePoint[3], π / 2f0)

        timer += dt
        if timer >= EndMoveToJoint2Duration
            phase = PhasePutJoint2
            timer = 0f0
            place_pen_at_floor_angle(
                state_ptr, EndPoint[1], EndPoint[2], EndPoint[3], π / 2f0)
        end
    elseif phase == PhasePutJoint2
        t = clamp(timer / ExtremityTrailDuration, 0f0, 1f0)
        EuclidBridge.set_pen_active(state_ptr, 1, Point2Color)

        theta = timer * PenConeSpinSpeed
        join2Pos = EndPoint + [
            PenConeRadius * Float32(cos(theta)),
            PenConeRadius * Float32(sin(theta)),
            PenConeTipHeight ]

        EuclidBridge.lock_pen_joint1(state_ptr, EndPoint[1], EndPoint[2], EndPoint[3])
        EuclidBridge.move_pen_joint2(state_ptr, join2Pos[1], join2Pos[2], join2Pos[3])

        show_full_point(state_ptr, point2Id, Point2Color,
            EndPoint[1], EndPoint[2], EndPoint[3])

        EuclidBridge.emit_trailing_particle(state_ptr, EndPoint[1], EndPoint[2], Point2Color)

        timer += dt
        if timer >= ExtremityTrailDuration
            phase = PhaseMoveToJoint1
            timer = 0f0
            place_pen_at_floor_angle(
                state_ptr, EndPoint[1], EndPoint[2], EndPoint[3], π / 2f0)
        end
    elseif phase == PhaseMoveToJoint1
        t = clamp(timer / EndMoveToJoint1Duration, 0f0, 1f0)
        EuclidBridge.set_pen_active(state_ptr, 0, Point2Color)

        vec = StartPoint - EndPoint
        tvec = t * vec
        tvec[3] = sin(t * π) * 0.25f0
        usePoint = EndPoint + tvec
        usePoint[3] = clamp(usePoint[3], 0f0, 1f0)
        place_pen_at_floor_angle(
            state_ptr, usePoint[1], usePoint[2], usePoint[3], π / 2f0)

        timer += dt
        if timer >= EndMoveToJoint1Duration
            phase = PhaseTilt
            timer = 0f0
            place_pen_at_floor_angle(
                state_ptr, StartPoint[1], StartPoint[2], StartPoint[3], π / 2f0)
        end
    elseif phase == PhaseTilt
        t = clamp(timer / TiltDuration, 0f0, 1f0)
        floorAngle = π / 2f0 + (PenTiltFloorAngle - π / 2f0) * t

        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 0, LineColor)
        place_pen_at_floor_angle(state_ptr, StartPoint[1], StartPoint[2], StartPoint[3], floorAngle)

        timer += dt
        if timer >= TiltDuration
            phase = PhaseDraw
            timer = 0f0
            place_pen_at_floor_angle(
                state_ptr, StartPoint[1], StartPoint[2], StartPoint[3], PenTiltFloorAngle)
        end
    elseif phase == PhaseDraw
        t = clamp(timer / DrawDuration, 0f0, 1f0)

        tipX = StartPoint[1] + (EndPoint[1] - StartPoint[1]) * t
        tipY = StartPoint[2] + (EndPoint[2] - StartPoint[2]) * t
        tipZ = StartPoint[3] + (EndPoint[3] - StartPoint[3]) * t

        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 1, LineColor)
        place_pen_at_floor_angle(state_ptr, tipX, tipY, tipZ, PenTiltFloorAngle)

        EuclidBridge.show_point(state_ptr, lineHostId)
        EuclidBridge.set_point_color(state_ptr, lineHostId, LineColor)
        EuclidBridge.set_point_brush(state_ptr, lineHostId, LineMaxBrush)
        EuclidBridge.set_point_position(
            state_ptr, lineJoint1Id, StartPoint[1], StartPoint[2], StartPoint[3])
        EuclidBridge.set_point_position(state_ptr, lineJoint2Id, tipX, tipY, tipZ)

        EuclidBridge.emit_trailing_particle(state_ptr, tipX, tipY, LineColor)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseEndStraighten
            timer = 0f0
            show_full_line(state_ptr, lineHostId, lineJoint1Id, lineJoint2Id)
            place_pen_at_floor_angle(
                state_ptr, EndPoint[1], EndPoint[2], EndPoint[3], PenTiltFloorAngle)
        end
    elseif phase == PhaseEndStraighten
        t = clamp(timer / EndStraightenDuration, 0f0, 1f0)
        floorAngle = PenTiltFloorAngle + (π / 2f0 - PenTiltFloorAngle) * t

        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 0, LineColor)
        place_pen_at_floor_angle(state_ptr, EndPoint[1], EndPoint[2], EndPoint[3], floorAngle)

        show_full_line(state_ptr, lineHostId, lineJoint1Id, lineJoint2Id)

        timer += dt
        if timer >= EndStraightenDuration
            phase = PhaseEndLift
            timer = 0f0
            place_pen_at_floor_angle(
                state_ptr, EndPoint[1], EndPoint[2], EndPoint[3], π / 2f0)
        end
    elseif phase == PhaseEndLift
        t = clamp(timer / EndLiftDuration, 0f0, 1f0)
        tipZ = EndPoint[3] + (PenTopZ - EndPoint[3]) * t

        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 0, LineColor)
        place_pen_at_floor_angle(state_ptr, EndPoint[1], EndPoint[2], tipZ, π / 2f0)

        show_full_line(state_ptr, lineHostId, lineJoint1Id, lineJoint2Id)

        timer += dt
        if timer >= EndLiftDuration
            EuclidBridge.hide_pen(state_ptr)
            place_pen_at_floor_angle(state_ptr, EndPoint[1], EndPoint[2], PenTopZ, π / 2f0)
            EuclidBridge.hide_point(state_ptr, point1Id)
            EuclidBridge.hide_point(state_ptr, point2Id)
            hide_line(state_ptr, lineHostId, lineJoint1Id, lineJoint2Id)
            reset_cycle_state(state_ptr)
            return
        end
    end

    EuclidBridge.set_animation_meta(state_ptr, MetaPhase, phase)
    EuclidBridge.set_animation_meta(state_ptr, MetaTimer, timer)
end

end

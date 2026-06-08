module ElementsOneDefinitionLine

import ..EuclidBridge

export get_view_text, initialize, clean, loop

const StartPoint = [0.25f0, 0.75f0, 0f0]
const EndPoint = [0.75f0, 0.25f0, 0f0]

const LineColor = :steelblue
const LineMaxBrush = 5f0

const PenTopZ = 1.4f0
const PenLength = 0.14f0
const PenTiltFloorAngle = Float32(pi / 4)

const DescendDuration = 3f0
const TiltDuration = 1.2f0
const DrawDuration = 2.8f0
const EndStraightenDuration = 1.2f0
const EndLiftDuration = 1.8f0
const LineFadeSpeed = 8f0

const SegmentDx = EndPoint[1] - StartPoint[1]
const SegmentDy = EndPoint[2] - StartPoint[2]
const SegmentLenXY = Float32(sqrt(SegmentDx * SegmentDx + SegmentDy * SegmentDy))
const PenDirX = SegmentLenXY > 0f0 ? SegmentDx / SegmentLenXY : 1f0
const PenDirY = SegmentLenXY > 0f0 ? SegmentDy / SegmentLenXY : 0f0

const MetaLineHostId = 1
const MetaLineJoint1Id = 2
const MetaLineJoint2Id = 3
const MetaPhase = 4
const MetaTimer = 5

const PhaseDescend = 0f0
const PhaseTilt = 1f0
const PhaseDraw = 2f0
const PhaseEndStraighten = 3f0
const PhaseEndLift = 4f0
const PhaseLineFade = 5f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """Euclid Elements - Book I - Definition: 2. Line:

A line is breadthless length."""
end

function clamp01(t::Float32)
    if t < 0f0
        return 0f0
    elseif t > 1f0
        return 1f0
    end
    return t
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
    EuclidBridge.set_point_brush(state_ptr, lineHostId, 0f0)
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

    EuclidBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    EuclidBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    hide_line(state_ptr, lineHostId, lineJoint1Id, lineJoint2Id)

    EuclidBridge.show_pen(state_ptr)
    EuclidBridge.set_pen_active(state_ptr, 1, LineColor)
    place_pen_at_floor_angle(state_ptr, StartPoint[1], StartPoint[2], PenTopZ, Float32(pi / 2))
end

function initialize(state_ptr::Ptr{Cvoid})
    line = EuclidBridge.create_new_line(
        state_ptr,
        StartPoint[1], StartPoint[2], StartPoint[3],
        StartPoint[1], StartPoint[2], StartPoint[3],
        LineColor, 0f0)

    EuclidBridge.set_animation_meta(state_ptr, MetaLineHostId, Float32(line.hostId))
    EuclidBridge.set_animation_meta(state_ptr, MetaLineJoint1Id, Float32(line.joint1Id))
    EuclidBridge.set_animation_meta(state_ptr, MetaLineJoint2Id, Float32(line.joint2Id))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
    lineHostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLineHostId))
    lineJoint1Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLineJoint1Id))
    lineJoint2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLineJoint2Id))

    hide_line(state_ptr, lineHostId, lineJoint1Id, lineJoint2Id)
    EuclidBridge.hide_pen(state_ptr)
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    lineHostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLineHostId))
    lineJoint1Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLineJoint1Id))
    lineJoint2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLineJoint2Id))

    if lineHostId < 0
        return
    end

    phase = EuclidBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = EuclidBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescend
        t = clamp01(timer / DescendDuration)

        tipZ = PenTopZ + (StartPoint[3] - PenTopZ) * t
        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 1, LineColor)
        place_pen_at_floor_angle(
            state_ptr, StartPoint[1], StartPoint[2], tipZ, Float32(pi / 2))

        timer += dt
        if timer >= DescendDuration
            phase = PhaseTilt
            timer = 0f0
            place_pen_at_floor_angle(
                state_ptr, StartPoint[1], StartPoint[2], StartPoint[3], Float32(pi / 2))
        end
    elseif phase == PhaseTilt
        t = clamp01(timer / TiltDuration)
        floorAngle = Float32(pi / 2) + (PenTiltFloorAngle - Float32(pi / 2)) * t

        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 1, LineColor)
        place_pen_at_floor_angle(state_ptr, StartPoint[1], StartPoint[2], StartPoint[3], floorAngle)

        timer += dt
        if timer >= TiltDuration
            phase = PhaseDraw
            timer = 0f0
            place_pen_at_floor_angle(
                state_ptr, StartPoint[1], StartPoint[2], StartPoint[3], PenTiltFloorAngle)
        end
    elseif phase == PhaseDraw
        t = clamp01(timer / DrawDuration)

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
        t = clamp01(timer / EndStraightenDuration)
        floorAngle = PenTiltFloorAngle + (Float32(pi / 2) - PenTiltFloorAngle) * t

        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 1, LineColor)
        place_pen_at_floor_angle(state_ptr, EndPoint[1], EndPoint[2], EndPoint[3], floorAngle)

        show_full_line(state_ptr, lineHostId, lineJoint1Id, lineJoint2Id)

        timer += dt
        if timer >= EndStraightenDuration
            phase = PhaseEndLift
            timer = 0f0
            place_pen_at_floor_angle(
                state_ptr, EndPoint[1], EndPoint[2], EndPoint[3], Float32(pi / 2))
        end
    elseif phase == PhaseEndLift
        t = clamp01(timer / EndLiftDuration)
        tipZ = EndPoint[3] + (PenTopZ - EndPoint[3]) * t

        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 1, LineColor)
        place_pen_at_floor_angle(state_ptr, EndPoint[1], EndPoint[2], tipZ, Float32(pi / 2))

        show_full_line(state_ptr, lineHostId, lineJoint1Id, lineJoint2Id)

        timer += dt
        if timer >= EndLiftDuration
            phase = PhaseLineFade
            timer = 0f0
            EuclidBridge.hide_pen(state_ptr)
            place_pen_at_floor_angle(state_ptr, EndPoint[1], EndPoint[2], PenTopZ, Float32(pi / 2))
        end
    else
        lineHost = EuclidBridge.get_point(state_ptr, lineHostId)
        nextBrush = lineHost.brushSize - LineFadeSpeed * dt

        if nextBrush <= 0f0
            hide_line(state_ptr, lineHostId, lineJoint1Id, lineJoint2Id)
            reset_cycle_state(state_ptr)
            return
        else
            EuclidBridge.show_point(state_ptr, lineHostId)
            EuclidBridge.set_point_color(state_ptr, lineHostId, LineColor)
            EuclidBridge.set_point_brush(state_ptr, lineHostId, nextBrush)
            EuclidBridge.set_point_position(
                state_ptr, lineJoint1Id, StartPoint[1], StartPoint[2], StartPoint[3])
            EuclidBridge.set_point_position(
                state_ptr, lineJoint2Id, EndPoint[1], EndPoint[2], EndPoint[3])
        end
    end

    EuclidBridge.set_animation_meta(state_ptr, MetaPhase, phase)
    EuclidBridge.set_animation_meta(state_ptr, MetaTimer, timer)
end

end

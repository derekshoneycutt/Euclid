module ElementsOneDefinitionLine

using LinearAlgebra

include("../../euclidbridge.jl")

export get_view_text, initialize, clean, loop

const StartPoint = [0.25f0, 0.75f0, 0f0]
const EndPoint = [0.75f0, 0.25f0, 0f0]

const LineColor = :steelblue
const LineMaxBrush = 5f0

const PenTopZ = 1.4f0
const PenLength = 0.14f0
const PenTiltFloorAngle = Float32(pi / 4)

const DescendDuration = 1.8f0
const TiltDuration = 0.8f0
const DrawDuration = 2.7f0
const EndStraightenDuration = 0.8f0
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

const PhaseDescend = 0f0
const PhaseTilt = 1f0
const PhaseDraw = 2f0
const PhaseEndStraighten = 3f0
const PhaseEndLift = 4f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """Euclid Elements - Book I - Definition: 2. Line:

A line is breadthless length."""
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
        t = clamp(timer / DescendDuration, 0f0, 1f0)

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
        t = clamp(timer / TiltDuration, 0f0, 1f0)
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
        t = clamp(timer / EndLiftDuration, 0f0, 1f0)
        tipZ = EndPoint[3] + (PenTopZ - EndPoint[3]) * t

        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 1, LineColor)
        place_pen_at_floor_angle(state_ptr, EndPoint[1], EndPoint[2], tipZ, Float32(pi / 2))

        show_full_line(state_ptr, lineHostId, lineJoint1Id, lineJoint2Id)

        timer += dt
        if timer >= EndLiftDuration
            EuclidBridge.hide_pen(state_ptr)
            place_pen_at_floor_angle(state_ptr, EndPoint[1], EndPoint[2], PenTopZ, Float32(pi / 2))
            hide_line(state_ptr, lineHostId, lineJoint1Id, lineJoint2Id)
            reset_cycle_state(state_ptr)
            return
        end
    end

    EuclidBridge.set_animation_meta(state_ptr, MetaPhase, phase)
    EuclidBridge.set_animation_meta(state_ptr, MetaTimer, timer)
end

end

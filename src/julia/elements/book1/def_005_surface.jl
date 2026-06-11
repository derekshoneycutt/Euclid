module ElementsOneDefinitionSurface

using LinearAlgebra

include("../../euclidbridge.jl")

export get_view_text, initialize, clean, loop

const StartPoint1 = [0.5f0, 0f0, 0f0]
const EndPoint1 = [0.5f0, 1f0, 0f0]
const StartPoint2 = [0f0, 0.5f0, 0f0]
const EndPoint2 = [1f0, 0.5f0, 0f0]

const LineColor1 = :steelblue
const LineColor2 = :palevioletred1

const PenTopZ = 1.4f0
const PenLength = 0.14f0
const PenTiltFloorAngle = π / 4f0

const SegmentVec1 = EndPoint1 - StartPoint1
const SegmentVecLen1 = norm(SegmentVec1)
const PenDirX1 = SegmentVecLen1 > 0f0 ? SegmentVec1[1] / SegmentVecLen1 : 1f0
const PenDirY1 = SegmentVecLen1 > 0f0 ? SegmentVec1[2] / SegmentVecLen1 : 0f0
const SegmentVec2 = EndPoint2 - StartPoint2
const SegmentVecLen2 = norm(SegmentVec2)
const PenDirX2 = SegmentVecLen2 > 0f0 ? SegmentVec2[1] / SegmentVecLen2 : 1f0
const PenDirY2 = SegmentVecLen2 > 0f0 ? SegmentVec2[2] / SegmentVecLen2 : 0f0

const DescendDuration = 1.8f0
const TiltDuration = 0.8f0
const DrawDuration = 2.7f0
const ArcMoveDuration = 2.1f0
const EndStraightenDuration = 0.8f0
const EndLiftDuration = 1.8f0
const ArcWaveHeight = 0.35f0

const MetaPhase = 1
const MetaTimer = 2

const PhaseDescend = 0f0
const PhaseTilt1 = 1f0
const PhaseDraw1 = 2f0
const PhaseEndStraighten1 = 3f0
const PhaseArcMove1To2 = 4f0
const PhaseTilt2 = 5f0
const PhaseDraw2 = 6f0
const PhaseEndStraighten2 = 7f0
const PhaseEndLift = 8f0

function get_view_text(state_ptr::Ptr{Cvoid})
    """Euclid Elements - Book I - Definition: 5. Surface:

A surface is that which has length and breadth only."""
end

function place_pen_at_floor_angle(
    state_ptr::Ptr{Cvoid}, tipX::Float32, tipY::Float32, tipZ::Float32, floorAngle::Float32)
    place_pen_at_floor_angle(state_ptr, tipX, tipY, tipZ, floorAngle, PenDirX1, PenDirY1)
end

function place_pen_at_floor_angle(
    state_ptr::Ptr{Cvoid}, tipX::Float32, tipY::Float32, tipZ::Float32, floorAngle::Float32,
    dirX::Float32, dirY::Float32)
    horizontalLength = PenLength * Float32(cos(floorAngle))
    verticalLength = PenLength * Float32(sin(floorAngle))

    shaftX = tipX + dirX * horizontalLength
    shaftY = tipY + dirY * horizontalLength
    shaftZ = tipZ + verticalLength

    EuclidBridge.lock_pen_joint1(state_ptr, tipX, tipY, tipZ)
    EuclidBridge.move_pen_joint2(state_ptr, shaftX, shaftY, shaftZ)
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    EuclidBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    EuclidBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)
end

function initialize(state_ptr::Ptr{Cvoid})
    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    phase = EuclidBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = EuclidBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescend
        t = clamp(timer / DescendDuration, 0f0, 1f0)

        tipZ = PenTopZ + (StartPoint1[3] - PenTopZ) * t
        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 0, LineColor1)
        place_pen_at_floor_angle(
            state_ptr, StartPoint1[1], StartPoint1[2], tipZ, π / 2f0)

        timer += dt
        if timer >= DescendDuration
            phase = PhaseTilt1
            timer = 0f0
            place_pen_at_floor_angle(
                state_ptr, StartPoint1[1], StartPoint1[2], StartPoint1[3], π / 2f0)
        end
    elseif phase == PhaseTilt1
        t = clamp(timer / TiltDuration, 0f0, 1f0)
        floorAngle = π / 2f0 + (PenTiltFloorAngle - π / 2f0) * t

        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 0, LineColor1)
        place_pen_at_floor_angle(state_ptr, StartPoint1[1], StartPoint1[2], StartPoint1[3], floorAngle)

        timer += dt
        if timer >= TiltDuration
            phase = PhaseDraw1
            timer = 0f0
            place_pen_at_floor_angle(
                state_ptr, StartPoint1[1], StartPoint1[2], StartPoint1[3], PenTiltFloorAngle)
        end
    elseif phase == PhaseDraw1
        t = clamp(timer / DrawDuration, 0f0, 1f0)

        tipX = StartPoint1[1] + (EndPoint1[1] - StartPoint1[1]) * t
        tipY = StartPoint1[2] + (EndPoint1[2] - StartPoint1[2]) * t
        tipZ = StartPoint1[3] + (EndPoint1[3] - StartPoint1[3]) * t

        EuclidBridge.show_pen(state_ptr)
        place_pen_at_floor_angle(state_ptr, tipX, tipY, tipZ, PenTiltFloorAngle)

        EuclidBridge.set_pen_active(state_ptr, 1, LineColor1)
        EuclidBridge.emit_trailing_particle(state_ptr, tipX, tipY, LineColor1)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseEndStraighten1
            timer = 0f0
            place_pen_at_floor_angle(
                state_ptr, EndPoint1[1], EndPoint1[2], EndPoint1[3], PenTiltFloorAngle)
        end
    elseif phase == PhaseEndStraighten1
        t = clamp(timer / EndStraightenDuration, 0f0, 1f0)
        floorAngle = PenTiltFloorAngle + (π / 2f0 - PenTiltFloorAngle) * t

        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 0, LineColor1)
        place_pen_at_floor_angle(state_ptr, EndPoint1[1], EndPoint1[2], EndPoint1[3], floorAngle)

        timer += dt
        if timer >= EndStraightenDuration
            phase = PhaseArcMove1To2
            timer = 0f0
            place_pen_at_floor_angle(
                state_ptr, EndPoint1[1], EndPoint1[2], EndPoint1[3], π / 2f0)
        end
    elseif phase == PhaseArcMove1To2
        t = clamp(timer / ArcMoveDuration, 0f0, 1f0)

        tipX = EndPoint1[1] + (StartPoint2[1] - EndPoint1[1]) * t
        tipY = EndPoint1[2] + (StartPoint2[2] - EndPoint1[2]) * t
        baseZ = EndPoint1[3] + (StartPoint2[3] - EndPoint1[3]) * t
        tipZ = baseZ + ArcWaveHeight * Float32(sin(π * t))

        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 0, LineColor2)
        place_pen_at_floor_angle(state_ptr, tipX, tipY, tipZ, π / 2f0)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseTilt2
            timer = 0f0
            place_pen_at_floor_angle(
                state_ptr, StartPoint2[1], StartPoint2[2], StartPoint2[3], π / 2f0)
        end
    elseif phase == PhaseTilt2
        t = clamp(timer / TiltDuration, 0f0, 1f0)
        floorAngle = π / 2f0 + (PenTiltFloorAngle - π / 2f0) * t

        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 0, LineColor2)
        place_pen_at_floor_angle(
            state_ptr, StartPoint2[1], StartPoint2[2], StartPoint2[3], floorAngle,
            PenDirX2, PenDirY2)

        timer += dt
        if timer >= TiltDuration
            phase = PhaseDraw2
            timer = 0f0
            place_pen_at_floor_angle(
                state_ptr, StartPoint2[1], StartPoint2[2], StartPoint2[3], PenTiltFloorAngle,
                PenDirX2, PenDirY2)
        end
    elseif phase == PhaseDraw2
        t = clamp(timer / DrawDuration, 0f0, 1f0)

        tipX = StartPoint2[1] + (EndPoint2[1] - StartPoint2[1]) * t
        tipY = StartPoint2[2] + (EndPoint2[2] - StartPoint2[2]) * t
        tipZ = StartPoint2[3] + (EndPoint2[3] - StartPoint2[3]) * t

        EuclidBridge.show_pen(state_ptr)
        place_pen_at_floor_angle(state_ptr, tipX, tipY, tipZ, PenTiltFloorAngle, PenDirX2, PenDirY2)

        EuclidBridge.set_pen_active(state_ptr, 1, LineColor2)
        EuclidBridge.emit_trailing_particle(state_ptr, tipX, tipY, LineColor2)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseEndStraighten2
            timer = 0f0
            place_pen_at_floor_angle(
                state_ptr, EndPoint2[1], EndPoint2[2], EndPoint2[3], PenTiltFloorAngle,
                PenDirX2, PenDirY2)
        end
    elseif phase == PhaseEndStraighten2
        t = clamp(timer / EndStraightenDuration, 0f0, 1f0)
        floorAngle = PenTiltFloorAngle + (π / 2f0 - PenTiltFloorAngle) * t

        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 0, LineColor2)
        place_pen_at_floor_angle(
            state_ptr, EndPoint2[1], EndPoint2[2], EndPoint2[3], floorAngle, PenDirX2, PenDirY2)

        timer += dt
        if timer >= EndStraightenDuration
            phase = PhaseEndLift
            timer = 0f0
            place_pen_at_floor_angle(
                state_ptr, EndPoint2[1], EndPoint2[2], EndPoint2[3], π / 2f0)
        end
    elseif phase == PhaseEndLift
        t = clamp(timer / EndLiftDuration, 0f0, 1f0)
        tipZ = EndPoint2[3] + (PenTopZ - EndPoint2[3]) * t

        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 0, LineColor2)
        place_pen_at_floor_angle(state_ptr, EndPoint2[1], EndPoint2[2], tipZ, π / 2f0)

        timer += dt
        if timer >= EndLiftDuration
            EuclidBridge.hide_pen(state_ptr)
            place_pen_at_floor_angle(state_ptr, EndPoint2[1], EndPoint2[2], PenTopZ, π / 2f0)
            reset_cycle_state(state_ptr)
            return
        end
    end

    EuclidBridge.set_animation_meta(state_ptr, MetaPhase, phase)
    EuclidBridge.set_animation_meta(state_ptr, MetaTimer, timer)
end

end

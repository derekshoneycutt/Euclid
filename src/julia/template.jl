module AnimationTemplateStyle

using LinearAlgebra

include("./euclidbridge.jl")

export get_view_text, initialize, clean, loop

const StartPoint = [0.25f0, 0.75f0, 0f0]
const EndPoint = [0.75f0, 0.25f0, 0f0]

const SegmentVec = EndPoint - StartPoint
const SegmentVecLen = norm(SegmentVec)
const PenDirX = SegmentVecLen > 0f0 ? SegmentVec[1] / SegmentVecLen : 1f0
const PenDirY = SegmentVecLen > 0f0 ? SegmentVec[2] / SegmentVecLen : 0f0

const LineColor = :steelblue
const LineMaxBrush = 5f0

const PenTopZ = 1.4f0
const PenLength = 0.14f0
const PenTiltFloorAngle = π / 4f0

const DescendDuration = 1.8f0
const TiltDuration = 0.8f0
const DrawDuration = 2.7f0
const EndStraightenDuration = 0.8f0
const EndLiftDuration = 1.8f0

const MetaPhase = 1
const MetaTimer = 2

const PhaseDescend = 0f0
const PhaseTilt = 1f0
const PhaseDraw = 2f0
const PhaseEndStraighten = 3f0
const PhaseEndLift = 4f0

function get_view_text(state_ptr::Ptr{Cvoid})
    """Euclid Elements - Book XX - Head: N. alsdkjasdklfj:

."""
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

        timer += dt
        if timer >= DescendDuration
            phase = PhaseTilt
            timer = 0f0
            place_pen_at_floor_angle(
                state_ptr, StartPoint[1], StartPoint[2], StartPoint[3], π / 2f0)
        end
    elseif phase == PhaseTilt
        t = clamp(timer / TiltDuration, 0f0, 1f0)

        timer += dt
        if timer >= TiltDuration
            phase = PhaseDraw
            timer = 0f0
            place_pen_at_floor_angle(
                state_ptr, StartPoint[1], StartPoint[2], StartPoint[3], PenTiltFloorAngle)
        end
    elseif phase == PhaseDraw
        t = clamp(timer / DrawDuration, 0f0, 1f0)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseEndStraighten
            timer = 0f0
            place_pen_at_floor_angle(
                state_ptr, EndPoint[1], EndPoint[2], EndPoint[3], PenTiltFloorAngle)
        end
    elseif phase == PhaseEndStraighten
        t = clamp(timer / EndStraightenDuration, 0f0, 1f0)

        timer += dt
        if timer >= EndStraightenDuration
            phase = PhaseEndLift
            timer = 0f0
            place_pen_at_floor_angle(
                state_ptr, EndPoint[1], EndPoint[2], EndPoint[3], π / 2f0)
        end
    elseif phase == PhaseEndLift
        t = clamp(timer / EndLiftDuration, 0f0, 1f0)

        timer += dt
        if timer >= EndLiftDuration
            EuclidBridge.hide_pen(state_ptr)
            place_pen_at_floor_angle(state_ptr, EndPoint[1], EndPoint[2], PenTopZ, π / 2f0)
            reset_cycle_state(state_ptr)
            return
        end
    end

    EuclidBridge.set_animation_meta(state_ptr, MetaPhase, phase)
    EuclidBridge.set_animation_meta(state_ptr, MetaTimer, timer)
end

end

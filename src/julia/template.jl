module AnimationTemplateStyle

using ..OdinJuliaBridge
using ..EuclidAnimations

using LinearAlgebra

export get_view_text, initialize, clean, loop

const StartPoint = [0.25f0, 0.75f0, 0f0]
const EndPoint = [0.75f0, 0.25f0, 0f0]
const PenTopZ = 1.4f0

const LineColor = :steelblue
const LineMaxBrush = 5f0

const DescendDuration = 1.8f0
const DrawDuration = 2.7f0
const EndLiftDuration = 1.8f0

const MetaPhase = 1
const MetaTimer = 2

const PhaseDescend = 0f0
const PhaseDraw = 2f0
const PhaseEndLift = 4f0

function get_view_text(state_ptr::Ptr{Cvoid})
    """Euclid Elements - Book XX - Head: N. alsdkjasdklfj:

."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)
end

function initialize(state_ptr::Ptr{Cvoid})
    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescend
        t = clamp(timer / DescendDuration, 0f0, 1f0)

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDraw
            timer = 0f0
            place_pen_at_floor_angle(
                state_ptr, StartPoint[1], StartPoint[2], StartPoint[3], π / 2f0)
        end
    elseif phase == PhaseDraw
        t = clamp(timer / DrawDuration, 0f0, 1f0)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseEndLift
            timer = 0f0
            place_pen_at_floor_angle(
                state_ptr, EndPoint[1], EndPoint[2], EndPoint[3], PenTiltFloorAngle)
        end
    elseif phase == PhaseEndLift
        t = clamp(timer / EndLiftDuration, 0f0, 1f0)

        timer += dt
        if timer >= EndLiftDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            place_pen_at_floor_angle(state_ptr, EndPoint[1], EndPoint[2], PenTopZ, π / 2f0)
            reset_cycle_state(state_ptr)
            return
        end
    end

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, phase)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, timer)
end

end

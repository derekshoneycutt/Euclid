module ElementsOneDefinitionPlaneSurface

using ..EuclidBridge
using ..EuclidAnimations

using LinearAlgebra

export get_view_text, initialize, clean, loop

const StartPoint1 = [0.5f0, 0f0, 0f0]
const EndPoint1 = [0.5f0, 1f0, 0f0]
const StartPoint2 = [0f0, 0.5f0, 0f0]
const EndPoint2 = [1f0, 0.5f0, 0f0]
const PenTopZ = 1.4f0

const LineColor1 = :steelblue
const LineColor2 = :palevioletred1

const DescendDuration = 1.8f0
const DragDuration = 4.2f0
const ArcMoveDuration = 2.1f0
const EndLiftDuration = 1.8f0
const ArcWaveHeight = 0.35f0

const MetaPhase = 1
const MetaTimer = 2

const PhaseDescend = 0f0
const PhaseDrag1 = 1f0
const PhaseArcMove1To2 = 2f0
const PhaseDrag2 = 3f0
const PhaseEndLift = 4f0

function get_view_text(state_ptr::Ptr{Cvoid})
    """Euclid Elements - Book I - Definition: Plane Surface:

A plane surface is a surface which lies evenly with the straight lines on itself."""
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
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, StartPoint1[1], StartPoint1[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrag1
            timer = 0f0
        end
    elseif phase == PhaseDrag1
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, StartPoint1, EndPoint1, LineColor1)

        timer += dt
        if timer >= DragDuration
            phase = PhaseArcMove1To2
            timer = 0f0
        end
    elseif phase == PhaseArcMove1To2
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            EndPoint1, StartPoint2, ArcWaveHeight, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrag2
            timer = 0f0
        end
    elseif phase == PhaseDrag2
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, StartPoint2, EndPoint2, LineColor2)

        timer += dt
        if timer >= DragDuration
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ, EndPoint2[1], EndPoint2[2])

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

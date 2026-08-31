module ElementsOneDefinitionSurface

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

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

"""Complete immutable timing state for one surface animation generation."""
struct AnimationState
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhaseDescend = 0f0
const PhaseDrag1 = 1f0
const PhaseArcMove1To2 = 2f0
const PhaseDrag2 = 3f0
const PhaseEndLift = 4f0

"""Return a surface animation state with updated cycle timing."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(phase, timer)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """Euclid Elements - Book I - Definition: Surface

A surface is that which has length and breadth only."""
    latex = raw"""\textbf{Euclid Elements - Book I - Definition}: \textit{Surface}

A surface is that which has length and breadth only."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset the animation cycle timing to its initial phase."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhaseDescend, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    reset_cycle_state(state_ptr, AnimationState(PhaseDescend, 0f0))
end

"""Clean any extra animation data at the end of performance"""
function clean(state_ptr::Ptr{Cvoid})
end

"""Perform an iteration of the animation loop for this animation"""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    state, status = OdinJuliaBridge.get_animation_value(state_ptr, StateKey)
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return
    phase = state.phase
    timer = state.timer

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
            reset_cycle_state(state_ptr, state)
            return
        end
    end

    OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, phase, timer))
end

end

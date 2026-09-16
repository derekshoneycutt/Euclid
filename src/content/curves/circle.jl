module EuclidCurvesCircle

using UUIDs
using ..AnimationCatalog
using ..OdinJuliaBridge
using ..EuclidLatex

export get_view_content, initialize, clean, loop, animation_entry

const AnimationId = UUID("5eae70a6-d48e-4b85-9fe3-db3b2e82cb3b")

const Center = Float32[0.50f0, 0.50f0, 0f0]
const Radius = 0.24f0
const StartParameter = 0f0
const FinishParameter = 2f0 * Float32(pi)
const CurveColor = :steelblue
const TopZ = 1.2f0
const DescendDuration = 1.5f0
const DrawDuration = 5f0
const RiseDuration = 1.5f0
const HoldDuration = 2.5f0

const PhaseDescend = UInt8(0)
const PhaseDraw = UInt8(1)
const PhaseRise = UInt8(2)
const PhaseHold = UInt8(3)

"""Immutable native identity and cycle timing for the circle construction."""
struct AnimationState
    curve_id::UInt64
    phase::UInt8
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

"""Return state with updated cycle timing and unchanged curve identity."""
function with_timing(state::AnimationState, phase::UInt8, timer::Float32)
    return AnimationState(state.curve_id, phase, timer)
end

"""Return explanatory content for the constant-radius circle construction."""
function get_view_content(_state_ptr::Ptr{Cvoid})
    return tex"""\textbf{Circle}

A circle is the plane curve traced by a point kept at a constant distance from a fixed center."""
end

"""Return the fixed pivot and rotating pencil positions at one elevation."""
function instrument_pose(parameter::Real, elevation::Real)
    pivot = Float32[Center[1], Center[2], elevation]
    pencil = Float32[Center[1] + Radius * cos(parameter),
        Center[2] + Radius * sin(parameter), elevation]
    return pivot, pencil
end

"""Place the compass at one angular parameter and elevation."""
function place_compass(state_ptr::Ptr{Cvoid}, parameter::Real, elevation::Real)
    pivot, pencil = instrument_pose(parameter, elevation)
    OdinJuliaBridge.lock_compass_joint1(state_ptr, pivot; sweep=false)
    OdinJuliaBridge.lock_compass_joint2(state_ptr, pencil; sweep=false)
end

"""Reset the hidden arc and elevated compass for a fresh cycle."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    OdinJuliaBridge.hide_point(state_ptr, state.curve_id)
    OdinJuliaBridge.set_arc_geometry(
        state_ptr, state.curve_id, Radius, StartParameter, 0f0)
    OdinJuliaBridge.hide_compass(state_ptr)
    place_compass(state_ptr, StartParameter, TopZ)
    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhaseDescend, 0f0))
    return status == OdinJuliaBridge.BRIDGE_STATUS_OK
end

"""Create the persistent circle and initialize its first construction cycle."""
function initialize(state_ptr::Ptr{Cvoid})
    curve = OdinJuliaBridge.create_new_circle(state_ptr, Center, Radius,
        StartParameter, 0f0, CurveColor, 5f0)
    state = AnimationState(curve.host_id, PhaseDescend, 0f0)
    reset_cycle_state(state_ptr, state)
    OdinJuliaBridge.set_compass_active(state_ptr, 3, CurveColor)
    OdinJuliaBridge.publish_view_content(state_ptr, get_view_content)
end

"""Hide the process-global compass when the animation is deselected."""
function clean(state_ptr::Ptr{Cvoid})
    OdinJuliaBridge.hide_compass(state_ptr)
end

"""Advance one compass and arc-sweep drawing step."""
function advance_draw_phase(state_ptr::Ptr{Cvoid}, state::AnimationState,
    timer::Float32, dt::Float32)
    progress = clamp(timer / DrawDuration, 0f0, 1f0)
    parameter = FinishParameter * progress
    place_compass(state_ptr, parameter, 0f0)
    OdinJuliaBridge.set_arc_geometry(
        state_ptr, state.curve_id, Radius, StartParameter, parameter)
    _, pencil = instrument_pose(parameter, 0f0)
    OdinJuliaBridge.emit_trailing_particle(state_ptr, pencil, CurveColor)
    next_timer = timer + dt
    next_timer < DrawDuration && return PhaseDraw, next_timer
    OdinJuliaBridge.set_arc_geometry(
        state_ptr, state.curve_id, Radius, StartParameter, FinishParameter)
    return PhaseRise, 0f0
end

"""Advance the synchronized compass and persistent circle construction."""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    state, status = OdinJuliaBridge.get_animation_value(state_ptr, StateKey)
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return
    phase, timer = state.phase, state.timer
    if phase == PhaseDescend
        progress = clamp(timer / DescendDuration, 0f0, 1f0)
        place_compass(state_ptr, StartParameter, TopZ * (1f0 - progress))
        OdinJuliaBridge.show_compass(state_ptr)
        timer += dt
        if timer >= DescendDuration
            phase, timer = PhaseDraw, 0f0
            OdinJuliaBridge.show_point(state_ptr, state.curve_id)
        end
    elseif phase == PhaseDraw
        phase, timer = advance_draw_phase(state_ptr, state, timer, dt)
    elseif phase == PhaseRise
        progress = clamp(timer / RiseDuration, 0f0, 1f0)
        place_compass(state_ptr, FinishParameter, TopZ * progress)
        timer += dt
        if timer >= RiseDuration
            OdinJuliaBridge.hide_compass(state_ptr)
            phase, timer = PhaseHold, 0f0
            OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
        end
    elseif phase == PhaseHold
        timer += dt
        if timer >= HoldDuration
            reset_cycle_state(state_ptr, state)
            return
        end
    end
    OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, phase, timer))
end

"""Dispatch one bridge-stable lifecycle operation for the Circle animation."""
function animation_entry(
    state_ptr::Ptr{Cvoid}, operation::Int32, dt::Float32)::Bool
    if operation == OdinJuliaBridge.ANIMATION_OPERATION_ENTER
        initialize(state_ptr)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_TICK
        loop(state_ptr, dt)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_EXIT
        clean(state_ptr)
    else
        return false
    end
    return true
end

end

AnimationCatalog.animation(
    EuclidCurvesCircle.AnimationId, EuclidCurvesCircle.animation_entry)
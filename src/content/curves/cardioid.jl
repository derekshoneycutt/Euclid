module EuclidCurvesCardioid

using UUIDs
using ..AnimationCatalog
using ..OdinJuliaBridge
using ..EuclidGeometry
using ..EuclidLatex

export get_view_content, initialize, clean, loop, animation_entry

const AnimationId = UUID("bad550b7-54c6-40df-adf1-c19e2e88fe25")

const Center = Float32[0.50f0, 0.50f0, 0f0]
const Radius = 0.12f0
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

struct AnimationState
    curve_id::UInt64
    phase::UInt8
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

"""Return state with updated cycle timing and unchanged curve identity."""
function with_timing(state::AnimationState, phase::UInt8, timer::Float32)
    AnimationState(state.curve_id, phase, timer)
end

"""Return explanatory content for the rolling-circle cardioid construction."""
function get_view_content(_state_ptr::Ptr{Cvoid})
    return tex"""\textbf{Cardioid}

A cardioid (from Greek καρδιά (kardiá) 'heart') is a plane curve traced by a point on the perimeter of a circle that is rolling around a fixed circle of the same radius."""
end

"""Return rolling-center and tracer positions at one parameter and elevation."""
function instrument_pose(parameter::Real, elevation::Real)
    pose = EuclidGeometry.trochoid_tool_pose(Center,
        EuclidGeometry.TrochoidExternal, Radius, Radius, parameter)
    tracer = EuclidGeometry.trochoid_point(Center,
        EuclidGeometry.TrochoidExternal, Radius, Radius, Radius, parameter)
    pose.rolling_center[3] = Float32(elevation)
    tracer[3] = Float32(elevation)
    return pose.rolling_center, tracer
end

"""Place the guide and compass together at one parameter and elevation."""
function place_instruments(state_ptr::Ptr{Cvoid}, parameter::Real, elevation::Real)
    rolling_center, tracer = instrument_pose(parameter, elevation)
    OdinJuliaBridge.set_trochoid_tool_position(
        state_ptr, Float32[Center[1], Center[2], elevation])
    OdinJuliaBridge.set_trochoid_tool_parameter(state_ptr, parameter)
    OdinJuliaBridge.lock_compass_joint1(state_ptr, rolling_center; sweep=false)
    OdinJuliaBridge.lock_compass_joint2(state_ptr, tracer; sweep=false)
end

"""Reset the hidden curve and elevated instruments for a fresh cycle."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    OdinJuliaBridge.hide_point(state_ptr, state.curve_id)
    OdinJuliaBridge.set_trochoid_frontier(state_ptr, state.curve_id, StartParameter)
    OdinJuliaBridge.hide_trochoid_tool(state_ptr)
    OdinJuliaBridge.hide_compass(state_ptr)
    OdinJuliaBridge.set_trochoid_tool_geometry(state_ptr;
        mode=OdinJuliaBridge.TROCHOID_EXTERNAL,
        fixed_radius=Radius, rolling_radius=Radius, parameter=StartParameter,
        rotation=0f0, orientation_phase=0f0)
    place_instruments(state_ptr, StartParameter, TopZ)
    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhaseDescend, 0f0))
    return status == OdinJuliaBridge.BRIDGE_STATUS_OK
end

"""Create the persistent cardioid and initialize its first construction cycle."""
function initialize(state_ptr::Ptr{Cvoid})
    curve = OdinJuliaBridge.create_new_cardioid(state_ptr, Center, Radius;
        draw_parameter=StartParameter, color=CurveColor, brush_size=5f0)
    state = AnimationState(curve.host_id, PhaseDescend, 0f0)
    reset_cycle_state(state_ptr, state)
    OdinJuliaBridge.publish_view_content(state_ptr, get_view_content)
end

"""Hide process-global instruments when the animation is deselected."""
function clean(state_ptr::Ptr{Cvoid})
    OdinJuliaBridge.hide_trochoid_tool(state_ptr)
    OdinJuliaBridge.hide_compass(state_ptr)
end

"""Advance one atomic guide, compass, curve-frontier, and particle draw step."""
function advance_draw_phase(state_ptr::Ptr{Cvoid}, state::AnimationState,
    timer::Float32, dt::Float32)
    progress = clamp(timer / DrawDuration, 0f0, 1f0)
    parameter = StartParameter + (FinishParameter - StartParameter) * progress
    place_instruments(state_ptr, parameter, 0f0)
    OdinJuliaBridge.set_trochoid_frontier(state_ptr, state.curve_id, parameter)
    _, tracer = instrument_pose(parameter, 0f0)
    OdinJuliaBridge.emit_trailing_particle(state_ptr, tracer, CurveColor)
    next_timer = timer + dt
    if next_timer < DrawDuration
        return PhaseDraw, next_timer
    end
    OdinJuliaBridge.set_trochoid_frontier(
        state_ptr, state.curve_id, FinishParameter)
    return PhaseRise, 0f0
end

"""Advance the synchronized guide, compass, and persistent cardioid construction."""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    state, status = OdinJuliaBridge.get_animation_value(state_ptr, StateKey)
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return
    phase = state.phase
    timer = state.timer

    if phase == PhaseDescend
        progress = clamp(timer / DescendDuration, 0f0, 1f0)
        place_instruments(state_ptr, StartParameter, TopZ * (1f0 - progress))
        OdinJuliaBridge.show_trochoid_tool(state_ptr)
        OdinJuliaBridge.show_compass(state_ptr)
        timer += dt
        if timer >= DescendDuration
            phase = PhaseDraw
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, state.curve_id)
        end
    elseif phase == PhaseDraw
        phase, timer = advance_draw_phase(state_ptr, state, timer, dt)
    elseif phase == PhaseRise
        progress = clamp(timer / RiseDuration, 0f0, 1f0)
        place_instruments(state_ptr, FinishParameter, TopZ * progress)
        timer += dt
        if timer >= RiseDuration
            OdinJuliaBridge.hide_trochoid_tool(state_ptr)
            OdinJuliaBridge.hide_compass(state_ptr)
            phase = PhaseHold
            timer = 0f0
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

"""Dispatch one bridge-stable lifecycle operation for the Cardioid animation."""
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
    EuclidCurvesCardioid.AnimationId, EuclidCurvesCardioid.animation_entry)

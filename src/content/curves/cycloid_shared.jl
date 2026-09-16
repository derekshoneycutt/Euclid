const First = Float32[0.04f0, 0.38f0, 0f0]
const Second = Float32[0.96f0, 0.38f0, 0f0]
const Radius = 0.06f0
const StartParameter = 0f0
const FinishParameter = 4f0 * Float32(pi)
const CurveColor = :steelblue
const TopZ = 1.2f0
const DescendDuration = 1.5f0
const DrawDuration = 10f0
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

"""Resolved guide and compass positions for one construction parameter."""
struct InstrumentPose
    first::Vector{Float32}
    second::Vector{Float32}
    rolling_center::Vector{Float32}
    tracer::Vector{Float32}
end

"""Return state with updated cycle timing and unchanged curve identity."""
function with_timing(state::AnimationState, phase::UInt8, timer::Float32)
    AnimationState(state.curve_id, phase, timer)
end

"""Return elevated rail endpoints, rolling center, and tracer at one parameter."""
function instrument_pose(parameter::Real, elevation::Real)
    first = Float32[First[1], First[2], elevation]
    second = Float32[Second[1], Second[2], elevation]
    pose = EuclidGeometry.cycloid_tool_pose(first, second, Radius, parameter;
        parameter_start=StartParameter, parameter_finish=FinishParameter)
    tracer = EuclidGeometry.cycloid_point(first, second, Radius,
        TracerDistance, parameter; parameter_start=StartParameter,
        parameter_finish=FinishParameter)
    return InstrumentPose(first, second, pose.rolling_center, tracer)
end

"""Place the literal-line guide and compass together at one pose."""
function place_instruments(state_ptr::Ptr{Cvoid}, parameter::Real, elevation::Real)
    pose = instrument_pose(parameter, elevation)
    OdinJuliaBridge.set_cycloid_tool_line(state_ptr, pose.first, pose.second)
    OdinJuliaBridge.set_cycloid_tool_parameter(state_ptr, parameter)
    OdinJuliaBridge.lock_compass_joint1(state_ptr, pose.rolling_center; sweep=false)
    OdinJuliaBridge.lock_compass_joint2(state_ptr, pose.tracer; sweep=false)
end

"""Reset the hidden curve and elevated instruments for a fresh cycle."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    OdinJuliaBridge.hide_point(state_ptr, state.curve_id)
    OdinJuliaBridge.set_cycloid_frontier(state_ptr, state.curve_id, StartParameter)
    OdinJuliaBridge.hide_cycloid_tool(state_ptr)
    OdinJuliaBridge.hide_compass(state_ptr)
    OdinJuliaBridge.set_cycloid_tool_geometry(state_ptr;
        rolling_radius=Radius, parameter_start=StartParameter,
        parameter_finish=FinishParameter, parameter=StartParameter)
    place_instruments(state_ptr, StartParameter, TopZ)
    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhaseDescend, 0f0))
    return status == OdinJuliaBridge.BRIDGE_STATUS_OK
end

"""Create the persistent Cycloid-family curve and initialize construction."""
function initialize(state_ptr::Ptr{Cvoid})
    curve = OdinJuliaBridge.create_new_cycloid(state_ptr, First, Second;
        rolling_radius=Radius, tracer_distance=TracerDistance,
        parameter_start=StartParameter, parameter_finish=FinishParameter,
        draw_parameter=StartParameter, color=CurveColor, brush_size=5f0)
    state = AnimationState(curve.host_id, PhaseDescend, 0f0)
    reset_cycle_state(state_ptr, state)
    publish_content(state_ptr)
end

"""Hide process-global instruments when this animation is deselected."""
function clean(state_ptr::Ptr{Cvoid})
    OdinJuliaBridge.hide_cycloid_tool(state_ptr)
    OdinJuliaBridge.hide_compass(state_ptr)
end

"""Advance one atomic guide, compass, curve-frontier, and particle draw step."""
function advance_draw_phase(state_ptr::Ptr{Cvoid}, state::AnimationState,
    timer::Float32, dt::Float32)
    progress = clamp(timer / DrawDuration, 0f0, 1f0)
    parameter = StartParameter + (FinishParameter - StartParameter) * progress
    place_instruments(state_ptr, parameter, 0f0)
    OdinJuliaBridge.set_cycloid_frontier(state_ptr, state.curve_id, parameter)
    pose = instrument_pose(parameter, 0f0)
    OdinJuliaBridge.emit_trailing_particle(state_ptr, pose.tracer, CurveColor)
    next_timer = timer + dt
    if next_timer < DrawDuration
        return PhaseDraw, next_timer
    end
    OdinJuliaBridge.set_cycloid_frontier(
        state_ptr, state.curve_id, FinishParameter)
    return PhaseRise, 0f0
end

"""Advance the synchronized guide, compass, and persistent curve construction."""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    state, status = OdinJuliaBridge.get_animation_value(state_ptr, StateKey)
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return
    phase = state.phase
    timer = state.timer
    if phase == PhaseDescend
        progress = clamp(timer / DescendDuration, 0f0, 1f0)
        place_instruments(state_ptr, StartParameter, TopZ * (1f0 - progress))
        OdinJuliaBridge.show_cycloid_tool(state_ptr)
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
            OdinJuliaBridge.hide_cycloid_tool(state_ptr)
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

"""Dispatch one bridge-stable lifecycle operation for this curve animation."""
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
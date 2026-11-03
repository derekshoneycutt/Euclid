module EuclidCurvesProlateCycloid

using UUIDs
using ..AnimationCatalog
using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

include("prolate_cycloid_content.jl")

export get_view_content, initialize, clean, loop, animation_entry

const AnimationId = UUID("83f8bc57-b9ad-4956-b6d0-d8483c584e2e")
const TracerDistance = 0.09f0

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

"""Return state with updated cycle timing and unchanged curve identity."""
function with_timing(state::AnimationState, phase::UInt8, timer::Float32)
    AnimationState(state.curve_id, phase, timer)
end

"""Return explanatory content for a two-revolution prolate Cycloid."""
function get_view_content(_state_ptr::Ptr{Cvoid})
    return EuclidCurvesProlateCycloidContent.get_view_content()
end

"""Publish this leaf's prolate-Cycloid explanation."""
function publish_content(state_ptr::Ptr{Cvoid})
    OdinJuliaBridge.publish_view_content(state_ptr, get_view_content)
end

"""Reset the hidden curve and elevated instruments for a fresh cycle."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    EuclidAnimations.checked_curve_status(
        OdinJuliaBridge.hide_point(state_ptr, state.curve_id))
    EuclidAnimations.checked_curve_status(
        OdinJuliaBridge.set_cycloid_frontier(state_ptr, state.curve_id, StartParameter))
    EuclidAnimations.checked_curve_status(
        OdinJuliaBridge.set_cycloid_tool_geometry(state_ptr;
            rolling_radius=Radius, parameter_start=StartParameter,
            parameter_finish=FinishParameter, parameter=StartParameter))
    clean(state_ptr)
    EuclidAnimations.place_cycloid_tools(state_ptr, First, Second, Radius,
        TracerDistance, StartParameter, TopZ; parameter_start=StartParameter,
        parameter_finish=FinishParameter)
    EuclidAnimations.checked_curve_status(OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhaseDescend, 0f0)))
    return true
end

"""Create the persistent Cycloid-family curve and initialize construction."""
function initialize(state_ptr::Ptr{Cvoid})
    curve = OdinJuliaBridge.create_new_cycloid(state_ptr, First, Second;
        rolling_radius=Radius, tracer_distance=TracerDistance,
        parameter_start=StartParameter, parameter_finish=FinishParameter,
        draw_parameter=StartParameter, color=CurveColor, brush_size=5f0)
    EuclidAnimations.checked_curve_status(curve.status)
    state = AnimationState(curve.host_id, PhaseDescend, 0f0)
    reset_cycle_state(state_ptr, state)
    publish_content(state_ptr)
end

"""Hide process-global instruments when this animation is deselected."""
function clean(state_ptr::Ptr{Cvoid})
    OdinJuliaBridge.set_compass_active(state_ptr, 0, CurveColor)
    EuclidAnimations.checked_curve_status(OdinJuliaBridge.hide_cycloid_tool(state_ptr))
    OdinJuliaBridge.hide_compass(state_ptr)
end

"""Establish the full curve directly after dispersing its previous visible material."""
function show_completed(state_ptr::Ptr{Cvoid})::Bool
    state, status = OdinJuliaBridge.get_animation_value(state_ptr, StateKey)
    EuclidAnimations.checked_curve_status(status)
    EuclidAnimations.checked_curve_status(
        OdinJuliaBridge.hide_point(state_ptr, state.curve_id))
    EuclidAnimations.checked_curve_status(
        OdinJuliaBridge.set_cycloid_frontier(
            state_ptr, state.curve_id, FinishParameter))
    EuclidAnimations.checked_curve_status(
        OdinJuliaBridge.show_point(state_ptr, state.curve_id))
    clean(state_ptr)
    return true
end

"""Advance the synchronized guide, compass, and persistent curve construction."""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    state, status = OdinJuliaBridge.get_animation_value(state_ptr, StateKey)
    EuclidAnimations.checked_curve_status(status)
    phase, timer = state.phase, state.timer
    if phase == PhaseDescend
        timer = min(timer + dt, DescendDuration)
        EuclidAnimations.animate_cycloid_descend(
            state_ptr, timer, DescendDuration, TopZ, First, Second, Radius;
            tracer_distance=TracerDistance, parameter_start=StartParameter,
            parameter_finish=FinishParameter)
        if timer >= DescendDuration
            phase, timer = PhaseDraw, 0f0
        end
    elseif phase == PhaseDraw
        timer = min(timer + dt, DrawDuration)
        EuclidAnimations.animate_draw_cycloid(
            state_ptr, timer, DrawDuration, First, Second, Radius;
            tracer_distance=TracerDistance, parameter_start=StartParameter,
            parameter_finish=FinishParameter, curve_id=state.curve_id,
            color=CurveColor, brush=5f0)
        if timer >= DrawDuration
            OdinJuliaBridge.set_compass_active(state_ptr, 0, CurveColor)
            phase, timer = PhaseRise, 0f0
        end
    elseif phase == PhaseRise
        timer = min(timer + dt, RiseDuration)
        EuclidAnimations.animate_cycloid_rise(
            state_ptr, timer, RiseDuration, TopZ, First, Second, Radius;
            tracer_distance=TracerDistance, parameter_start=StartParameter,
            parameter_finish=FinishParameter)
        if timer >= RiseDuration
            clean(state_ptr)
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
    EuclidAnimations.checked_curve_status(OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, phase, timer)))
end

"""Dispatch one bridge-stable lifecycle operation for this curve animation."""
function animation_entry(
    state_ptr::Ptr{Cvoid}, operation::Int32, dt::Float32)::Bool
    if operation == OdinJuliaBridge.ANIMATION_OPERATION_PRESENTATION_SELECTION_CHANGED
        return true
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_ENTER
        OdinJuliaBridge.animation_content_specification(state_ptr)
        initialize(state_ptr)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_SHOW_COMPLETED
        return show_completed(state_ptr)
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

AnimationCatalog.animation(EuclidCurvesProlateCycloid.AnimationId,
    EuclidCurvesProlateCycloid.animation_entry)

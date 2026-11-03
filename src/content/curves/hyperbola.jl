module EuclidCurvesHyperbola

using UUIDs
using ..AnimationCatalog
using ..OdinJuliaBridge
using ..EuclidAnimations

include("hyperbola_content.jl")

export get_view_content, initialize, clean, loop, animation_entry

const AnimationId = UUID("6913c945-308b-47bd-8145-9d97a8500c02")
const Center = (0.50f0, 0.50f0, 0f0)
const Semimajor = 0.12f0
const Semiminor = 0.10f0
const RailHalfLength = 0.40f0
const StartParameter = -1.35f0
const FinishParameter = 1.35f0
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

"""Keep the complete hyperbola identity and its local drawing clock."""
struct AnimationState
    curve_id::UInt64
    branches::Int32
    phase::UInt8
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

"""Surface rejected native work through the animation runtime's error reporting."""
function checked(status::Int32)
    status == OdinJuliaBridge.BRIDGE_STATUS_OK ||
        error("Hyperbola bridge operation failed with status $status")
    return nothing
end

"""Return the pure content sidecar for the paired-branch presentation."""
function get_view_content(_state_ptr::Ptr{Cvoid})
    return EuclidCurvesHyperbolaContent.get_view_content()
end

"""Deactivate both integrated tips and hide the permanent three-rail guide."""
function clean(state_ptr::Ptr{Cvoid})
    checked(OdinJuliaBridge.set_hyperbola_tool_active(state_ptr, 0, CurveColor))
    checked(OdinJuliaBridge.hide_hyperbola_tool(state_ptr))
end

"""Disperse both old branches and restore the hidden elevated apparatus."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    checked(OdinJuliaBridge.hide_point(state_ptr, state.curve_id))
    checked(OdinJuliaBridge.set_hyperbola_frontier(
        state_ptr, state.curve_id, StartParameter))
    clean(state_ptr)
    EuclidAnimations.place_hyperbola_tool(state_ptr, Center, StartParameter, TopZ)
    checked(OdinJuliaBridge.set_animation_value!(state_ptr, StateKey,
        AnimationState(state.curve_id, state.branches, PhaseDescend, 0f0)))
end

"""Create one complete hyperbola and configure its paired-tracer guide."""
function initialize(state_ptr::Ptr{Cvoid}; branches::Symbol=:both)
    selection = OdinJuliaBridge.hyperbola_branches(branches)
    result = OdinJuliaBridge.create_new_hyperbola(state_ptr, Center;
        branches,
        semimajor=Semimajor, semiminor=Semiminor,
        parameter_start=StartParameter, parameter_finish=FinishParameter,
        draw_parameter=StartParameter, color=CurveColor, brush_size=5f0)
    checked(result.status)
    checked(OdinJuliaBridge.set_hyperbola_tool_geometry(state_ptr;
        semimajor=Semimajor, semiminor=Semiminor,
        parameter_start=StartParameter, parameter_finish=FinishParameter,
        rail_half_length=RailHalfLength))
    state = AnimationState(result.host_id, selection, PhaseDescend, 0f0)
    reset_cycle_state(state_ptr, state)
    OdinJuliaBridge.publish_view_content(state_ptr, get_view_content)
end

"""Show both completed finite branches immediately with the instrument hidden."""
function show_completed(state_ptr::Ptr{Cvoid})::Bool
    state, status = OdinJuliaBridge.get_animation_value(state_ptr, StateKey)
    checked(status)
    checked(OdinJuliaBridge.hide_point(state_ptr, state.curve_id))
    checked(OdinJuliaBridge.set_hyperbola_frontier(
        state_ptr, state.curve_id, FinishParameter))
    checked(OdinJuliaBridge.show_point(state_ptr, state.curve_id))
    clean(state_ptr)
    return true
end

"""Draw both branches with opposing analytic tips and normal authored trails."""
function advance_draw_phase(state_ptr::Ptr{Cvoid}, state::AnimationState,
    timer::Float32, dt::Float32)
    next_timer = min(timer + dt, DrawDuration)
    EuclidAnimations.animate_draw_hyperbola(state_ptr, next_timer, DrawDuration,
        Center, Semimajor, Semiminor, StartParameter, FinishParameter;
        curve_id=state.curve_id, color=CurveColor,
        branches=OdinJuliaBridge.hyperbola_branch_mode(state.branches))
    next_timer < DrawDuration && return PhaseDraw, next_timer
    checked(OdinJuliaBridge.set_hyperbola_tool_active(state_ptr, 0, CurveColor))
    return PhaseRise, 0f0
end

"""Lower both pens and activate selected ink contacts only on reaching the board."""
function advance_descend_phase(state_ptr::Ptr{Cvoid}, state::AnimationState,
    timer::Float32, dt::Float32)
    next_timer = min(timer + dt, DescendDuration)
    EuclidAnimations.animate_hyperbola_descend(state_ptr, next_timer,
        DescendDuration, TopZ, Center, StartParameter; color=CurveColor)
    next_timer < DescendDuration && return PhaseDescend, next_timer
    checked(OdinJuliaBridge.set_hyperbola_tool_active(state_ptr, 1, CurveColor;
        branches=OdinJuliaBridge.hyperbola_branch_mode(state.branches)))
    return PhaseDraw, 0f0
end

"""Lift both pens from their final endpoints before the finished hold."""
function advance_rise_phase(state_ptr::Ptr{Cvoid}, timer::Float32, dt::Float32)
    next_timer = min(timer + dt, RiseDuration)
    EuclidAnimations.animate_hyperbola_rise(state_ptr, next_timer, RiseDuration,
        TopZ, Center, FinishParameter; color=CurveColor)
    next_timer < RiseDuration && return PhaseRise, next_timer
    clean(state_ptr)
    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return PhaseHold, 0f0
end

"""Run one shape's drawing cycle while keeping its branch strokes disconnected."""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    state, status = OdinJuliaBridge.get_animation_value(state_ptr, StateKey)
    checked(status)
    phase, timer = state.phase, state.timer
    if phase == PhaseDescend
        phase, timer = advance_descend_phase(state_ptr, state, timer, dt)
        if phase == PhaseDraw
            checked(OdinJuliaBridge.show_point(state_ptr, state.curve_id))
        end
    elseif phase == PhaseDraw
        phase, timer = advance_draw_phase(state_ptr, state, timer, dt)
    elseif phase == PhaseRise
        phase, timer = advance_rise_phase(state_ptr, timer, dt)
    elseif timer + dt >= HoldDuration
        reset_cycle_state(state_ptr, state)
        return
    else
        timer += dt
    end
    checked(OdinJuliaBridge.set_animation_value!(state_ptr, StateKey,
        AnimationState(state.curve_id, state.branches, phase, timer)))
end

"""Dispatch the complete native animation lifecycle for Hyperbola."""
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

AnimationCatalog.animation(
    EuclidCurvesHyperbola.AnimationId, EuclidCurvesHyperbola.animation_entry)

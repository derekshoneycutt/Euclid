module EuclidCurvesParabola

using UUIDs
using ..AnimationCatalog
using ..OdinJuliaBridge
using ..EuclidGeometry

include("parabola_content.jl")

export get_view_content, initialize, clean, loop, animation_entry

const AnimationId = UUID("7a30689b-72db-480b-965a-92e681786c01")
const Vertex = (0.37f0, 0.50f0, 0f0)
const FocalDistance = 0.075f0
const LinkLength = 0.16f0
const StartParameter = -1.6f0
const FinishParameter = 1.6f0
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

"""Retain one native curve identity and immutable phase timing per animation."""
struct AnimationState
    curve_id::UInt64
    phase::UInt8
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

"""Surface rejected native work through the animation runtime's error reporting."""
function checked(status::Int32)
    status == OdinJuliaBridge.BRIDGE_STATUS_OK ||
        error("Parabola bridge operation failed with status $status")
    return nothing
end

"""Return the pure content sidecar for the parabola presentation."""
function get_view_content(_state_ptr::Ptr{Cvoid})
    return EuclidCurvesParabolaContent.get_view_content()
end

"""Place the entire instrument using one tracing parameter and elevation."""
function place_instrument(state_ptr::Ptr{Cvoid}, parameter::Float32, z::Float32)
    checked(OdinJuliaBridge.set_parabola_tool_position(
        state_ptr, (Vertex[1], Vertex[2], z)))
    checked(OdinJuliaBridge.set_parabola_tool_parameter(state_ptr, parameter))
end

"""Deactivate and hide the permanent apparatus at selection and phase boundaries."""
function clean(state_ptr::Ptr{Cvoid})
    checked(OdinJuliaBridge.set_parabola_tool_active(state_ptr, 0, CurveColor))
    checked(OdinJuliaBridge.hide_parabola_tool(state_ptr))
end

"""Disperse old ink and restore the hidden instrument's initial elevated pose."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    checked(OdinJuliaBridge.hide_point(state_ptr, state.curve_id))
    checked(OdinJuliaBridge.set_parabola_frontier(
        state_ptr, state.curve_id, StartParameter))
    clean(state_ptr)
    place_instrument(state_ptr, StartParameter, TopZ)
    checked(OdinJuliaBridge.set_animation_value!(state_ptr, StateKey,
        AnimationState(state.curve_id, PhaseDescend, 0f0)))
end

"""Construct one finite parabola and configure its permanent articulated guide."""
function initialize(state_ptr::Ptr{Cvoid})
    curve = OdinJuliaBridge.create_new_parabola(state_ptr, Vertex;
        focal_distance=FocalDistance, parameter_start=StartParameter,
        parameter_finish=FinishParameter, draw_parameter=StartParameter,
        color=CurveColor, brush_size=5f0)
    checked(curve.status)
    checked(OdinJuliaBridge.set_parabola_tool_geometry(state_ptr;
        focal_distance=FocalDistance, link_length=LinkLength,
        parameter_start=StartParameter, parameter_finish=FinishParameter))
    state = AnimationState(curve.host_id, PhaseDescend, 0f0)
    reset_cycle_state(state_ptr, state)
    OdinJuliaBridge.publish_view_content(state_ptr, get_view_content)
end

"""Publish the completed arc directly with no visible instrument."""
function show_completed(state_ptr::Ptr{Cvoid})::Bool
    state, status = OdinJuliaBridge.get_animation_value(state_ptr, StateKey)
    checked(status)
    checked(OdinJuliaBridge.hide_point(state_ptr, state.curve_id))
    checked(OdinJuliaBridge.set_parabola_frontier(
        state_ptr, state.curve_id, FinishParameter))
    checked(OdinJuliaBridge.show_point(state_ptr, state.curve_id))
    clean(state_ptr)
    return true
end

"""Advance the analytic frontier and instrument together, including the final tip."""
function advance_draw_phase(state_ptr::Ptr{Cvoid}, state::AnimationState,
    timer::Float32, dt::Float32)
    next_timer = min(timer + dt, DrawDuration)
    progress = next_timer / DrawDuration
    parameter = StartParameter + (FinishParameter - StartParameter) * progress
    place_instrument(state_ptr, parameter, 0f0)
    checked(OdinJuliaBridge.set_parabola_frontier(
        state_ptr, state.curve_id, parameter))
    tip = EuclidGeometry.parabola_point(Vertex, FocalDistance, parameter)
    OdinJuliaBridge.emit_trailing_particle(state_ptr, tip[1], tip[2], tip[3],
        CurveColor)
    next_timer < DrawDuration && return PhaseDraw, next_timer
    return PhaseRise, 0f0
end

"""Lower the apparatus and establish surface contact before revealing ink."""
function advance_descend_phase(state_ptr::Ptr{Cvoid}, timer::Float32, dt::Float32)
    next_timer = min(timer + dt, DescendDuration)
    place_instrument(state_ptr, StartParameter,
        TopZ * (1f0 - next_timer / DescendDuration))
    checked(OdinJuliaBridge.show_parabola_tool(state_ptr))
    next_timer < DescendDuration && return PhaseDescend, next_timer
    checked(OdinJuliaBridge.set_parabola_tool_active(state_ptr, 1, CurveColor))
    return PhaseDraw, 0f0
end

"""Lift from the actual final endpoint and announce the completed drawing."""
function advance_rise_phase(state_ptr::Ptr{Cvoid}, timer::Float32, dt::Float32)
    checked(OdinJuliaBridge.set_parabola_tool_active(state_ptr, 0, CurveColor))
    next_timer = min(timer + dt, RiseDuration)
    place_instrument(state_ptr, FinishParameter, TopZ * next_timer / RiseDuration)
    next_timer < RiseDuration && return PhaseRise, next_timer
    clean(state_ptr)
    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return PhaseHold, 0f0
end

"""Drive the ordinary descend, draw, rise, and readable-hold cycle."""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    state, status = OdinJuliaBridge.get_animation_value(state_ptr, StateKey)
    checked(status)
    phase, timer = state.phase, state.timer
    if phase == PhaseDescend
        phase, timer = advance_descend_phase(state_ptr, timer, dt)
        phase == PhaseDraw &&
            checked(OdinJuliaBridge.show_point(state_ptr, state.curve_id))
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
        AnimationState(state.curve_id, phase, timer)))
end

"""Dispatch the complete native animation lifecycle for Parabola."""
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
    EuclidCurvesParabola.AnimationId, EuclidCurvesParabola.animation_entry)

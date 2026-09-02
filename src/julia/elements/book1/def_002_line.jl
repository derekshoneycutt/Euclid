module ElementsOneDefinitionLine

using UUIDs
using ..AnimationCatalog

const AnimationId = UUID("168548ed-ed4a-5d8b-8ac6-fb573f5637cd")

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

using LinearAlgebra

export get_view_text, initialize, clean, loop, animation_entry

const StartPoint = [0.25f0, 0.75f0, 0f0]
const EndPoint = [0.75f0, 0.25f0, 0f0]
const PenTopZ = 1.4f0

const LineColor = :steelblue
const LineMaxBrush = 5f0

const DescendDuration = 1.8f0
const LineDrawDuration = 4.2f0
const EndLiftDuration = 1.8f0

"""Stable native handles for the line owned by the animation."""
struct LineIds
    host::Int64
    joint1::Int64
    joint2::Int64
end

"""Complete immutable state for one line-definition animation generation."""
struct AnimationState
    line::LineIds
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhaseDescend = 0f0
const PhaseDrawLine = 1f0
const PhaseEndLift = 2f0

const DefinitionViewText = """Euclid Elements - Book I - Definition: Line

A line is breadthless length."""

const DefinitionLatexDocument = raw"""\textbf{Euclid Elements - Book I - Definition}: \textit{Line}

A line \euclidline[color=steelblue,length=3,thickness=4] is breadthless length."""

"""Return state with updated cycle timing and the same native line handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(state.line, phase, timer)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    EuclidLatex.emit_latex_view_text!(
        state_ptr, DefinitionLatexDocument, DefinitionViewText)
end

"""Reset the animation cycle while preserving its native line handles."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    line_host_id = state.line.host
    line_joint2_id = state.line.joint2

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.hide_point(state_ptr, line_host_id)
    OdinJuliaBridge.set_point_position(
        state_ptr, line_joint2_id, StartPoint[1], StartPoint[2], StartPoint[3])

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhaseDescend, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    line = OdinJuliaBridge.create_new_line(
        state_ptr, StartPoint, StartPoint,
        LineColor, 0f0)

    state = AnimationState(
        LineIds(line.host_id, line.joint1_id, line.joint2_id), PhaseDescend, 0f0)
    reset_cycle_state(state_ptr, state)
    OdinJuliaBridge.publish_view_update(state_ptr, get_view_text)
end

"""Clean any extra animation data at the end of performance"""
function clean(state_ptr::Ptr{Cvoid})
end

"""Perform an iteration of the animation loop for this animation"""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    state, status = OdinJuliaBridge.get_animation_value(state_ptr, StateKey)
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return
    line_host_id = state.line.host
    line_joint1_id = state.line.joint1
    line_joint2_id = state.line.joint2

    if line_host_id < 0
        return
    end

    phase = state.phase
    timer = state.timer

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, StartPoint[1], StartPoint[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawLine
            timer = 0f0
        end
    elseif phase == PhaseDrawLine
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, LineDrawDuration,
            StartPoint, EndPoint;
            penbrush=LineMaxBrush,
            pencolor=LineColor,
            line_host_id=line_host_id,
            line_joint1_id=line_joint1_id,
            line_joint2_id=line_joint2_id)

        timer += dt
        if timer >= LineDrawDuration
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ, EndPoint[1], EndPoint[2])

        timer += dt
        if timer >= EndLiftDuration
            reset_cycle_state(state_ptr, state)
            return
        end
    end

    OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, phase, timer))
end


"""Dispatch one bridge-stable lifecycle operation for this animation."""
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
    ElementsOneDefinitionLine.AnimationId, ElementsOneDefinitionLine.animation_entry)

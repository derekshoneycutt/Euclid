module ElementsOneDefinitionParallel

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

export get_view_text, initialize, clean, loop

const Line1Start = [0.00f0, 0.70f0, 0f0]
const Line1End = [1.00f0, 0.70f0, 0f0]
const Line2Start = [0.00f0, 0.30f0, 0f0]
const Line2End = [1.00f0, 0.30f0, 0f0]

const PenTopZ = 1.4f0
const LineMaxBrush = 5f0

const Line1Color = :steelblue
const Line2Color = :khaki3

const DescendDuration = 1.8f0
const DrawDuration = 3.2f0
const ArcMoveDuration = 2.2f0
const ArcMoveHeight = 0.22f0
const RiseDuration = 1.8f0
const HidePauseDuration = 1.5f0

"""Stable native handles for one line owned by the animation."""
struct LineIds
    host::Int64
    joint1::Int64
    joint2::Int64
end

"""Complete immutable state for one parallel-lines animation generation."""
struct AnimationState
    lines::NTuple{2,LineIds}
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhaseDescendLine1 = 0f0
const PhaseDrawLine1 = 1f0
const PhaseArcToLine2 = 2f0
const PhaseDrawLine2 = 3f0
const PhaseRiseLine2 = 4f0
const PhaseHideAll = 5f0

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(state.lines, phase, timer)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """Euclid Elements - Book I - Definition: Parallel Straight Lines

Parallel straight lines are straight lines which, being in the same plane and being produced indefinitely in both directions, do not meet one another in either direction."""
    latex = raw"""\textbf{Euclid Elements - Book I - Definition}: \textit{Parallel Straight Lines}

Parallel straight lines \euclidline[color=steelblue,length=3,thickness=4] \euclidline[color=khaki3,length=3,thickness=4] are straight lines which, being in the same plane and being produced indefinitely in both directions, do not meet one another in either direction."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset visible objects and transactionally publish initial cycle timing."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    line1_host_id = state.lines[1].host
    line1_joint2_id = state.lines[1].joint2
    line2_host_id = state.lines[2].host
    line2_joint2_id = state.lines[2].joint2

    OdinJuliaBridge.hide_point_batch(state_ptr, [line1_host_id, line2_host_id])

    OdinJuliaBridge.set_point_position(
        state_ptr, line1_joint2_id,
        Line1Start[1], Line1Start[2], Line1Start[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, line2_joint2_id,
        Line2Start[1], Line2Start[2], Line2Start[3])

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, Line1Color)

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhaseDescendLine1, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    line1 = OdinJuliaBridge.create_new_line(
        state_ptr, Line1Start, Line1Start,
        Line1Color, 0f0)
    line2 = OdinJuliaBridge.create_new_line(
        state_ptr, Line2Start, Line2Start,
        Line2Color, 0f0)

    state = AnimationState((
        LineIds(line1.host_id, line1.joint1_id, line1.joint2_id),
        LineIds(line2.host_id, line2.joint1_id, line2.joint2_id)),
        PhaseDescendLine1, 0f0)
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
    line1_host_id = state.lines[1].host
    line1_joint1_id = state.lines[1].joint1
    line1_joint2_id = state.lines[1].joint2
    line2_host_id = state.lines[2].host
    line2_joint1_id = state.lines[2].joint1
    line2_joint2_id = state.lines[2].joint2

    if line1_host_id < 0
        return
    end

    phase = state.phase
    timer = state.timer

    if phase == PhaseDescendLine1
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, Line1Start[1], Line1Start[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawLine1
            timer = 0f0
        end
    elseif phase == PhaseDrawLine1
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawDuration,
            Line1Start, Line1End;
            penbrush=LineMaxBrush,
            pencolor=Line1Color,
            line_host_id=line1_host_id,
            line_joint1_id=line1_joint1_id,
            line_joint2_id=line1_joint2_id)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseArcToLine2
            timer = 0f0
        end
    elseif phase == PhaseArcToLine2
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            Line1End, Line2Start, ArcMoveHeight, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.set_pen_active(state_ptr, 0, Line2Color)
            phase = PhaseDrawLine2
            timer = 0f0
        end
    elseif phase == PhaseDrawLine2
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawDuration,
            Line2Start, Line2End;
            penbrush=LineMaxBrush,
            pencolor=Line2Color,
            line_host_id=line2_host_id,
            line_joint1_id=line2_joint1_id,
            line_joint2_id=line2_joint2_id)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseRiseLine2
            timer = 0f0
        end
    elseif phase == PhaseRiseLine2
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, RiseDuration, PenTopZ, Line2End[1], Line2End[2])

        timer += dt
        if timer >= RiseDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseHideAll
            timer = 0f0
        end
    elseif phase == PhaseHideAll
        timer += dt
        if timer >= HidePauseDuration
            reset_cycle_state(state_ptr, state)
            return
        end
    end

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, phase, timer))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return
end

end

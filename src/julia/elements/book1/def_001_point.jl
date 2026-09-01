module ElementsOneDefinitionPoint

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

export get_view_text, initialize, clean, loop

const Point = [0.5f0, 0.5f0, 0f0]

const PointColor = :steelblue
const PointMaxBrush = 5f0

const PenTopZ = 1.4f0

const DescendDuration = 3f0
const DrawDuration = 4f0
const RiseDuration = 3f0

"""Complete immutable state for one point-definition animation generation."""
struct AnimationState
    point_id::Int64
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhaseDescend = 0f0
const PhaseDraw = 1f0
const PhaseRise = 2f0

const DefinitionViewText = """Euclid Elements - Book I - Definition: Point

A point is that which has no part."""

const DefinitionLatexDocument = raw"""\textbf{Euclid Elements - Book I - Definition}: \textit{Point}

A point \euclidpoint[color=steelblue,size=1] is that which has no part."""

"""Return state with updated cycle timing and the same native point handle."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(state.point_id, phase, timer)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    EuclidLatex.emit_latex_view_text!(
        state_ptr, DefinitionLatexDocument, DefinitionViewText)
end

"""Reset the animation cycle while preserving its native point handle."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    pointid = state.point_id

    OdinJuliaBridge.hide_point(state_ptr, pointid)

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, PointColor)

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhaseDescend, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    point = OdinJuliaBridge.create_new_point(
        state_ptr, Point, PointColor, 0f0)

    state = AnimationState(point.index, PhaseDescend, 0f0)
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
    pointid = state.point_id
    if pointid < 0
        return
    end

    phase = state.phase
    timer = state.timer

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, Point[1], Point[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDraw
            timer = 0f0
        end
    elseif phase == PhaseDraw
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawDuration, Point,
            PointMaxBrush, PointColor, pointid)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseRise
            timer = 0f0
        end
    elseif phase == PhaseRise
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, RiseDuration, PenTopZ, Point[1], Point[2])

        timer += dt
        if timer >= RiseDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            OdinJuliaBridge.hide_point(state_ptr, pointid)
            reset_cycle_state(state_ptr, state)
            return
        end
    end

    OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, phase, timer))
end

end

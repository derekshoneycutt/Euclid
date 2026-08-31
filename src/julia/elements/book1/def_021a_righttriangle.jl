module ElementsOneDefinitionRightTriangle

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

using LinearAlgebra

export get_view_text, initialize, clean, loop

const VertexA = [0.30f0, 0.22f0, 0f0]
const VertexB = [0.30f0, 0.78f0, 0f0]
const VertexC = [0.88f0, 0.78f0, 0f0]

const MarkerCenter = [VertexB[1], VertexB[2], 0f0]
const MarkerRadius = 0.175f0
const MarkerStart = [MarkerCenter[1], MarkerCenter[2] - MarkerRadius, 0f0]
const MarkerSweepTheta = Float32(π / 2f0)
const MarkerEnd = MarkerCenter +
    [MarkerRadius * cos(MarkerSweepTheta - π/2f0),
     MarkerRadius * sin(MarkerSweepTheta - π/2f0), 0f0]

const PenTopZ = 1.4f0
const CompassTopZ = 1.4f0

const LegColor = :palevioletred1
const HypotenuseColor = :khaki3
const MarkerColor = :steelblue
const TriangleMaxBrush = 5f0
const MarkerBrush = 5f0

const PenDescendDuration = 1.8f0
const DrawDuration = 3.1f0
const PenRiseDuration = 1.8f0
const CompassDescendDuration = 1.8f0
const MarkerDrawDuration = 2.2f0
const CompassRiseDuration = 2.0f0
const HidePauseDuration = 1.5f0

"""Stable native handles for one line owned by the animation."""
struct LineIds
    host::Int64
    joint1::Int64
    joint2::Int64
end

"""Stable native handles for one angle marker owned by the animation."""
struct CircleIds
    host::Int64
    start::Int64
    finish::Int64
end

"""Complete immutable state for one right-triangle animation generation."""
struct AnimationState
    lines::NTuple{3,LineIds}
    marker::CircleIds
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhaseDescend = 0f0
const PhaseDrawSide1 = 1f0
const PhaseDrawSide2 = 2f0
const PhaseDrawSide3 = 3f0
const PhasePenRise = 4f0
const PhaseCompassDescend = 5f0
const PhaseDrawMarker = 6f0
const PhaseCompassRise = 7f0
const PhaseHideAll = 8f0

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(state.lines, state.marker, phase, timer)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """Euclid Elements - Book I - Definition: Right-Angled Triangle

Further, of trilateral figures, a right-angled triangle is that which has a right angle, ..."""
    latex = raw"""\textbf{Euclid Elements - Book I - Definition}: \textit{Right-Angled Triangle}

Further, of trilateral figures, a right-angled triangle \euclidtriangle[height=2,width=3,thickness=2,edge1_color=palevioletred1,edge2_color=palevioletred1,edge3_color=khaki3] is that which has a right angle \euclidangle[color=steelblue,radius=2,thickness=2], ..."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset visible objects and transactionally publish initial cycle timing."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    line1_host_id = state.lines[1].host
    line1_joint2_id = state.lines[1].joint2
    line2_host_id = state.lines[2].host
    line2_joint2_id = state.lines[2].joint2
    line3_host_id = state.lines[3].host
    line3_joint2_id = state.lines[3].joint2
    marker_host_id = state.marker.host
    marker_end_id = state.marker.finish

    OdinJuliaBridge.hide_point_batch(state_ptr, [
        line1_host_id, line2_host_id, line3_host_id, marker_host_id])

    OdinJuliaBridge.set_point_position(
        state_ptr, line1_joint2_id, VertexA[1], VertexA[2], VertexA[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, line2_joint2_id, VertexB[1], VertexB[2], VertexB[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, line3_joint2_id, VertexC[1], VertexC[2], VertexC[3])

    OdinJuliaBridge.set_point_position(
        state_ptr, marker_end_id, MarkerStart[1], MarkerStart[2], MarkerStart[3])

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.hide_compass(state_ptr)

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, LegColor)
    OdinJuliaBridge.set_compass_active(state_ptr, 0, MarkerColor)
    OdinJuliaBridge.lock_compass_joint1(
        state_ptr, MarkerCenter[1], MarkerCenter[2], CompassTopZ)
    OdinJuliaBridge.lock_compass_joint2(
        state_ptr, MarkerStart[1], MarkerStart[2], CompassTopZ)

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhaseDescend, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    marker = OdinJuliaBridge.create_new_circle(
        state_ptr, MarkerCenter, MarkerRadius,
        3f0 * π / 2f0, 3f0 * π / 2f0, MarkerColor, 0f0)
    line1 = OdinJuliaBridge.create_new_line(
        state_ptr, VertexA, VertexA,
        LegColor, 0f0)
    line2 = OdinJuliaBridge.create_new_line(
        state_ptr, VertexB, VertexB,
        LegColor, 0f0)
    line3 = OdinJuliaBridge.create_new_line(
        state_ptr, VertexC, VertexC,
        HypotenuseColor, 0f0)

    state = AnimationState((
        LineIds(line1.host_id, line1.joint1_id, line1.joint2_id),
        LineIds(line2.host_id, line2.joint1_id, line2.joint2_id),
        LineIds(line3.host_id, line3.joint1_id, line3.joint2_id)),
        CircleIds(marker.host_id, marker.start_id, marker.end_id), PhaseDescend, 0f0)
    reset_cycle_state(state_ptr, state)
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
    line3_host_id = state.lines[3].host
    line3_joint1_id = state.lines[3].joint1
    line3_joint2_id = state.lines[3].joint2
    marker_host_id = state.marker.host
    marker_start_id = state.marker.start
    marker_end_id = state.marker.finish

    if line1_host_id < 0
        return
    end

    phase = state.phase
    timer = state.timer

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, PenDescendDuration, PenTopZ, VertexA[1], VertexA[2])

        timer += dt
        if timer >= PenDescendDuration
            phase = PhaseDrawSide1
            timer = 0f0
        end
    elseif phase == PhaseDrawSide1
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawDuration,
            VertexA, VertexB;
            penbrush=TriangleMaxBrush,
            pencolor=LegColor,
            line_host_id=line1_host_id,
            line_joint1_id=line1_joint1_id,
            line_joint2_id=line1_joint2_id)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseDrawSide2
            timer = 0f0
        end
    elseif phase == PhaseDrawSide2
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawDuration,
            VertexB, VertexC;
            penbrush=TriangleMaxBrush,
            pencolor=LegColor,
            line_host_id=line2_host_id,
            line_joint1_id=line2_joint1_id,
            line_joint2_id=line2_joint2_id)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseDrawSide3
            timer = 0f0
        end
    elseif phase == PhaseDrawSide3
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawDuration,
            VertexC, VertexA;
            penbrush=TriangleMaxBrush,
            pencolor=HypotenuseColor,
            line_host_id=line3_host_id,
            line_joint1_id=line3_joint1_id,
            line_joint2_id=line3_joint2_id)

        timer += dt
        if timer >= DrawDuration
            phase = PhasePenRise
            timer = 0f0
        end
    elseif phase == PhasePenRise
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenRiseDuration, PenTopZ, VertexA[1], VertexA[2])

        timer += dt
        if timer >= PenRiseDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseCompassDescend
            timer = 0f0
        end
    elseif phase == PhaseCompassDescend
        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, CompassDescendDuration, CompassTopZ,
            MarkerCenter[1], MarkerCenter[2], MarkerStart[1], MarkerStart[2])

        timer += dt
        if timer >= CompassDescendDuration
            phase = PhaseDrawMarker
            timer = 0f0
        end
    elseif phase == PhaseDrawMarker
        EuclidAnimations.animate_draw_circle(state_ptr,
            timer, MarkerDrawDuration, MarkerCenter,
            MarkerStart, MarkerSweepTheta, MarkerRadius;
            brush=MarkerBrush,
            color=MarkerColor,
            marker_host_id=marker_host_id,
            marker_start_id=marker_start_id,
            marker_end_id=marker_end_id)

        timer += dt
        if timer >= MarkerDrawDuration
            phase = PhaseCompassRise
            timer = 0f0
        end
    elseif phase == PhaseCompassRise
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassRiseDuration, CompassTopZ,
            MarkerCenter[1], MarkerCenter[2], MarkerEnd[1], MarkerEnd[2])

        timer += dt
        if timer >= CompassRiseDuration
            OdinJuliaBridge.hide_compass(state_ptr)
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

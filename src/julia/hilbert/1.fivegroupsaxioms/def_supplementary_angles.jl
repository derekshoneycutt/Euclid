module HilbertChapterOneDefSupplementaryAngles

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

using LinearAlgebra

export get_view_text, initialize, clean, loop

const StartPoint = [0.25f0, 0.75f0, 0f0]
const EndPoint = [0.75f0, 0.25f0, 0f0]
const PerpStartPoint = [0.5f0, 0.5f0, 0f0]
const PerpEndPoint = [1f0, 1f0, 0f0]

const MarkerRadius = 0.20f0
const MainLineUnit =
    normalize(Float32[EndPoint[1] - StartPoint[1], EndPoint[2] - StartPoint[2]])
const MarkerStart = [
    PerpStartPoint[1] + MarkerRadius * MainLineUnit[1],
    PerpStartPoint[2] + MarkerRadius * MainLineUnit[2],
    0f0]
const MarkerEnd = [
    PerpStartPoint[1] - MarkerRadius * MainLineUnit[1],
    PerpStartPoint[2] - MarkerRadius * MainLineUnit[2],
    0f0]
const AngleTheta = π

const PenTopZ = 1.4f0
const CompassTopZ = 1.4f0

const LineColor = :steelblue
const PerpLineColor = :palevioletred1
const MarkerColor = :khaki3
const LineMaxBrush = 5f0
const MarkerRadialTrailSamples = 8f0

const DescendDuration = 1.8f0
const LineDrawDuration = 4.2f0
const ArcMoveDuration = 1.2f0
const ArcMoveHeight = 0.175f0
const EndLiftDuration = 1.8f0
const CompassDrawDuration = 2.25f0
const CompassLiftDuration = 3f0
const HidePauseDuration = 2f0

struct AnimationState
    line_host::Int64
    line_joint1::Int64
    line_joint2::Int64
    perp_line_host::Int64
    perp_line_joint1::Int64
    perp_line_joint2::Int64
    marker_host::Int64
    marker_start::Int64
    marker_end::Int64
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhaseDescend = 0f0
const PhaseDrawLine1 = 1f0
const PhasePenArcToPivot = 2f0
const PhaseDrawLine2 = 3f0
const PhaseEndLift = 4f0
const PhaseCompassDrawMarker = 5f0
const PhaseCompassLift = 6f0
const PhaseHideAll = 7f0

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(
        state.line_host, state.line_joint1, state.line_joint2,
        state.perp_line_host, state.perp_line_joint1, state.perp_line_joint2,
        state.marker_host, state.marker_start, state.marker_end, phase, timer)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - Definition: Supplementary Angles

Two angles having the same vertex and one side in common, while the sides not common form a straight line, are called supplementary angles. Two angles having a common vertex and whose sides form straight lines are called vertical angles. An angle which is congruent to its supplementary angle is called a right angle."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - Definition}: \textit{Supplementary Angles}

Two angles \euclidangle[color=khaki3,radius=2,thickness=2,start=90,end=180]\euclidangle[color=khaki3,radius=2,thickness=2] having the same vertex and one side in common, while the sides not common form a straight line, are called supplementary angles.
Two angles \euclidangle[color=khaki3,radius=2,thickness=2,start=90,end=180]\euclidangle[color=khaki3,radius=2,thickness=2] having a common vertex and whose sides form straight lines are called vertical angles.
An angle which is congruent to its supplementary angle is called a right angle \euclidangle[color=khaki3,radius=2,thickness=2,start=90,end=180]\euclidangle[color=khaki3,radius=2,thickness=2]."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset the animation objects and transactionally restart cycle timing."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    line_host_id = state.line_host
    line_joint2_id = state.line_joint2
    perpline_host_id = state.perp_line_host
    perpline_joint2_id = state.perp_line_joint2
    marker_host_id = state.marker_host
    marker_end_id = state.marker_end

    OdinJuliaBridge.hide_point_batch(state_ptr, [
        marker_host_id, line_host_id, perpline_host_id])

    OdinJuliaBridge.set_point_position(
        state_ptr, marker_end_id, MarkerStart[1], MarkerStart[2], MarkerStart[3])

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.set_point_position(
        state_ptr, line_joint2_id, StartPoint[1], StartPoint[2], StartPoint[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, perpline_joint2_id,
        PerpStartPoint[1], PerpStartPoint[2], PerpStartPoint[3])

    OdinJuliaBridge.hide_compass(state_ptr)
    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, LineColor)
    OdinJuliaBridge.set_compass_active(state_ptr, 0, MarkerColor)
    OdinJuliaBridge.lock_compass_joint1(
        state_ptr, PerpStartPoint[1], PerpStartPoint[2], CompassTopZ)
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
        state_ptr,
        PerpStartPoint, MarkerRadius, 7f0 * π / 4f0, 7f0 * π / 4f0,
        MarkerColor, 0f0)
    line = OdinJuliaBridge.create_new_line(
        state_ptr, StartPoint, StartPoint,
        LineColor, 0f0)
    perpline = OdinJuliaBridge.create_new_line(
        state_ptr, PerpStartPoint, PerpStartPoint,
        PerpLineColor, 0f0)

    state = AnimationState(
        line.host_id, line.joint1_id, line.joint2_id,
        perpline.host_id, perpline.joint1_id, perpline.joint2_id,
        marker.host_id, marker.start_id, marker.end_id, PhaseDescend, 0f0)
    reset_cycle_state(state_ptr, state)
end

"""Clean any extra animation data at the end of performance"""
function clean(state_ptr::Ptr{Cvoid})
end

"""Perform an iteration of the animation loop for this animation"""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    state, status = OdinJuliaBridge.get_animation_value(state_ptr, StateKey)
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return
    line_host_id = state.line_host
    line_joint1_id = state.line_joint1
    line_joint2_id = state.line_joint2
    perpline_host_id = state.perp_line_host
    perpline_joint1_id = state.perp_line_joint1
    perpline_joint2_id = state.perp_line_joint2
    marker_host_id = state.marker_host
    marker_start_id = state.marker_start
    marker_end_id = state.marker_end

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
            phase = PhaseDrawLine1
            timer = 0f0
        end
    elseif phase == PhaseDrawLine1
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
            phase = PhasePenArcToPivot
            timer = 0f0
        end
    elseif phase == PhasePenArcToPivot
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            EndPoint, PerpStartPoint, ArcMoveHeight, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawLine2
            timer = 0f0
        end
    elseif phase == PhaseDrawLine2
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, LineDrawDuration,
            PerpStartPoint, PerpEndPoint;
            penbrush=LineMaxBrush,
            pencolor=PerpLineColor,
            line_host_id=perpline_host_id,
            line_joint1_id=perpline_joint1_id,
            line_joint2_id=perpline_joint2_id)

        timer += dt
        if timer >= LineDrawDuration
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ, PerpEndPoint[1], PerpEndPoint[2])

        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, EndLiftDuration, CompassTopZ,
            PerpStartPoint[1], PerpStartPoint[2], MarkerStart[1], MarkerStart[2])

        timer += dt
        if timer >= EndLiftDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseCompassDrawMarker
            timer = 0f0
        end
    elseif phase == PhaseCompassDrawMarker
        EuclidAnimations.animate_draw_circle(state_ptr,
            timer, CompassDrawDuration, PerpStartPoint,
            MarkerStart, AngleTheta, MarkerRadius;
            brush=LineMaxBrush,
            color=MarkerColor,
            marker_host_id=marker_host_id,
            marker_start_id=marker_start_id,
            marker_end_id=marker_end_id)

        timer += dt
        if timer >= CompassDrawDuration
            phase = PhaseCompassLift
            timer = 0f0
        end
    elseif phase == PhaseCompassLift
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassLiftDuration, CompassTopZ,
            PerpStartPoint[1], PerpStartPoint[2], MarkerEnd[1], MarkerEnd[2])

        timer += dt
        if timer >= CompassLiftDuration
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

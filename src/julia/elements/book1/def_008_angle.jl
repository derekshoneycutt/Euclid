module ElementsOneDefinitionPlaneAngle

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

using LinearAlgebra

export get_view_text, initialize, clean, loop

const JointPoint = [0.30f0, 0.30f0, 0f0]
const LineLength = 0.55f0
const AngleTheta = π / 3f0

const Line1Start = JointPoint
const Line1End = [JointPoint[1] + LineLength, JointPoint[2], 0f0]
const Line2Start = JointPoint
const Line2End = [
    JointPoint[1] + LineLength * cos(AngleTheta),
    JointPoint[2] + LineLength * sin(AngleTheta),
    0f0,
]

const MarkerRadius = 0.20f0
const MarkerStart = [JointPoint[1] + MarkerRadius, JointPoint[2], 0f0]
const MarkerEnd = [
    JointPoint[1] + MarkerRadius * cos(AngleTheta),
    JointPoint[2] + MarkerRadius * sin(AngleTheta)
]

const LineColor1 = :steelblue
const LineColor2 = :palevioletred1
const MarkerColor = :khaki3
const LineMaxBrush = 5f0
const MarkerBrush = 1f0
const MarkerRadialTrailSamples = 8f0

const PenTopZ = 1.4f0
const CompassTopZ = 1.4f0

const DescendDuration = 1.8f0
const DrawLineDuration = 3.4f0
const ArcMoveDuration = 2.0f0
const ArcMoveHeight = 0.25f0
const EndLiftDuration = 1.6f0
const CompassDrawDuration = 1.25f0
const CompassLiftDuration = 3f0
const HidePauseDuration = 2f0

"""Stable native handles for one line owned by the animation."""
struct LineIds
    host::Int64
    joint1::Int64
    joint2::Int64
end

"""Stable native handles for the angle marker owned by the animation."""
struct CircleIds
    host::Int64
    start::Int64
    finish::Int64
end

"""Complete immutable state for one plane-angle animation generation."""
struct AnimationState
    line1::LineIds
    line2::LineIds
    marker::CircleIds
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhasePenDescend = 0f0
const PhaseDrawLine1 = 1f0
const PhasePenArcToPivot = 2f0
const PhaseDrawLine2 = 3f0
const PhasePenLift = 4f0
const PhaseCompassDrawMarker = 5f0
const PhaseCompassLift = 6f0
const PhaseHideAll = 7f0

"""Return state with updated cycle timing and the same native geometry handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(state.line1, state.line2, state.marker, phase, timer)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """Euclid Elements - Book I - Definition: Plane Angle

A plane angle is the inclination to one another of two lines in a plane which meet one another and do not lie in a straight line.

And when the lines containing the angle are straight, the angle is called rectilinear."""
    latex = raw"""\textbf{Euclid Elements - Book I - Definition}: \textit{Plane Angle}

A plane angle \euclidangle[color=khaki3,radius=2,end=60,filled] is the inclination to one another of two lines \euclidline[color=steelblue,length=3,thickness=4] \euclidline[color=palevioletred1,length=3,thickness=4] in a plane which meet one another and do not lie in a straight line.

And when the lines containing the angle are straight, the angle is called rectilinear."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset the animation cycle while preserving its native geometry handles."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    line1_host_id = state.line1.host
    line1_joint2_id = state.line1.joint2
    line2_host_id = state.line2.host
    line2_joint2_id = state.line2.joint2
    marker_host_id = state.marker.host
    marker_end_id = state.marker.finish

    OdinJuliaBridge.hide_point_batch(state_ptr, [
        marker_host_id, line2_host_id, line1_host_id])
    OdinJuliaBridge.set_point_position(
        state_ptr, marker_end_id, MarkerStart[1], MarkerStart[2], MarkerStart[3])

    OdinJuliaBridge.set_point_position(
        state_ptr, line2_joint2_id, Line2Start[1], Line2Start[2], Line2Start[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, line1_joint2_id, Line1Start[1], Line1Start[2], Line1Start[3])

    OdinJuliaBridge.hide_compass(state_ptr)
    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, LineColor1)
    OdinJuliaBridge.set_compass_active(state_ptr, 0, LineColor1)
    OdinJuliaBridge.lock_compass_joint1(
        state_ptr, JointPoint[1], JointPoint[2], CompassTopZ)
    OdinJuliaBridge.lock_compass_joint2(
        state_ptr, MarkerStart[1], MarkerStart[2], CompassTopZ)

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhasePenDescend, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    marker = OdinJuliaBridge.create_new_filledcircle(
        state_ptr, JointPoint, MarkerRadius, 0f0, 0f0,
        MarkerColor, 0f0)
    line1 = OdinJuliaBridge.create_new_line(
        state_ptr, Line1Start, Line1Start,
        LineColor1, 0f0)
    line2 = OdinJuliaBridge.create_new_line(
        state_ptr, Line2Start, Line2Start,
        LineColor2, 0f0)

    state = AnimationState(
        LineIds(line1.host_id, line1.joint1_id, line1.joint2_id),
        LineIds(line2.host_id, line2.joint1_id, line2.joint2_id),
        CircleIds(marker.host_id, marker.start_id, marker.end_id),
        PhasePenDescend, 0f0)
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
    line1_host_id = state.line1.host
    line1_joint1_id = state.line1.joint1
    line1_joint2_id = state.line1.joint2
    line2_host_id = state.line2.host
    line2_joint1_id = state.line2.joint1
    line2_joint2_id = state.line2.joint2
    marker_host_id = state.marker.host
    marker_start_id = state.marker.start
    marker_end_id = state.marker.finish

    if line1_host_id < 0
        return
    end

    phase = state.phase
    timer = state.timer

    if phase == PhasePenDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, Line1Start[1], Line1Start[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawLine1
            timer = 0f0
        end
    elseif phase == PhaseDrawLine1
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawLineDuration,
            Line1Start, Line1End;
            penbrush=LineMaxBrush,
            pencolor=LineColor1,
            line_host_id=line1_host_id,
            line_joint1_id=line1_joint1_id,
            line_joint2_id=line1_joint2_id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhasePenArcToPivot
            timer = 0f0
        end
    elseif phase == PhasePenArcToPivot
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            Line1End, JointPoint, ArcMoveHeight, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawLine2
            timer = 0f0
        end
    elseif phase == PhaseDrawLine2
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawLineDuration,
            Line2Start, Line2End;
            penbrush=LineMaxBrush,
            pencolor=LineColor2,
            line_host_id=line2_host_id,
            line_joint1_id=line2_joint1_id,
            line_joint2_id=line2_joint2_id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhasePenLift
            timer = 0f0
        end
    elseif phase == PhasePenLift
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ, Line2End[1], Line2End[2])

        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, EndLiftDuration, CompassTopZ,
            JointPoint[1], JointPoint[2], MarkerStart[1], MarkerStart[2])

        timer += dt
        if timer >= EndLiftDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseCompassDrawMarker
            timer = 0f0
        end
    elseif phase == PhaseCompassDrawMarker
        EuclidAnimations.animate_draw_filledcircle(state_ptr,
            timer, CompassDrawDuration, JointPoint,
            MarkerStart, AngleTheta, MarkerRadius;
            brush=MarkerBrush,
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
            JointPoint[1], JointPoint[2], MarkerEnd[1], MarkerEnd[2])

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

    OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, phase, timer))
end

end

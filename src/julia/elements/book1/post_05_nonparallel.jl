module ElementsOnePostulatesNonParallelLines

using UUIDs
using ..AnimationCatalog

const AnimationId = UUID("4d98d3cf-e73a-5e6e-9e1d-6fa1141934e6")

using ..OdinJuliaBridge
using ..EuclidGeometry
using ..EuclidAnimations
using ..EuclidLatex

using LinearAlgebra

export get_view_text, initialize, clean, loop, animation_entry

const StartPoint1 = [0.25f0, 0.1f0, 0f0]
const EndPoint12 = [0.51f0, 0.9f0, 0f0]
const EndPoint11 = StartPoint1 + (EndPoint12 - StartPoint1) * 0.4f0
const Angle1StartΘ =
    atan(EndPoint12[2] - StartPoint1[2], EndPoint12[1] - StartPoint1[1])

const StartPoint2 = [0.75f0, 0.1f0, 0f0]
const EndPoint22 = [0.49f0, 0.9f0, 0f0]
const EndPoint21 = StartPoint2 + (EndPoint22 - StartPoint2) * 0.4f0
const Angle2StartΘ =
    atan(EndPoint22[2] - StartPoint2[2], EndPoint22[1] - StartPoint2[1])

const StartPoint3 = [0.15f0, 0.2f0, 0f0]
const EndPoint3 = [0.85f0, 0.2f0, 0f0]

const MarkerRadius = 0.15f0

const Marker1Center =
    line_intersection_3d(StartPoint1, EndPoint11, StartPoint3, EndPoint3)
const Marker1Start = Marker1Center + normalize(EndPoint3 - Marker1Center) * MarkerRadius
const Marker1End = Marker1Center + normalize(EndPoint12 - Marker1Center) * MarkerRadius

const Marker2Center =
    line_intersection_3d(StartPoint2, EndPoint21, StartPoint3, EndPoint3)
const Marker2Start =
    Marker2Center + normalize(EndPoint22 - Marker2Center) * MarkerRadius
const Marker2End = Marker2Center + normalize(StartPoint3 - Marker2Center) * MarkerRadius

const Intersection =
    line_intersection_3d(StartPoint1, EndPoint12, StartPoint2, EndPoint22)

const PenTopZ = 1.4f0
const CompassTopZ = 1.4f0

const Line1Color = :steelblue
const Line2Color = :palevioletred1
const Line3Color = :grey60
const Marker1Color = :palevioletred1
const Marker2Color = :khaki3
const PointColor = :khaki3
const PointMaxBrush = 5f0
const LineMaxBrush = 5f0
const MarkerBrush = 5f0

const PenDescendDuration1 = 1.8f0
const LineDrawDuration = 2.1f0
const ArcMoveDuration = 1.25f0
const ArcMoveHeight = 0.25f0
const PenRiseDuration1 = 1.8f0
const MarkerDrawDuration = 1.5f0
const CompassArcMoveDuration = 1.25f0
const CompassRiseDuration = 1.8f0
const PointDrawDuration = 4f0
const HidePauseDuration = 1.5f0

"""Stable native handles for one line owned by the animation."""
struct LineIds
    host::Int64
    joint1::Int64
    joint2::Int64
end

"""Stable native handles for one filled circle owned by the animation."""
struct CircleIds
    host::Int64
    start::Int64
    finish::Int64
end

"""Complete immutable state for one non-parallel-lines animation generation."""
struct AnimationState
    lines::NTuple{3,LineIds}
    markers::NTuple{2,CircleIds}
    point::Int64
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhaseDescend = 0f0
const PhaseDrawLine1 = 1f0
const PhasePenArcToLine2 = 11f0
const PhaseDrawLine2 = 12f0
const PhasePenArcToLine3 = 21f0
const PhaseDrawLine3 = 22f0
const PhasePenLift = 30f0
const PhaseDrawMarker1 = 111f0
const PhaseCompassArcToMarker2 = 120f0
const PhaseDrawMarker2 = 121f0
const PhaseCompassRise = 150f0
const PhaseDrawLine12 = 201f0
const PhasePenArcToLine22 = 210f0
const PhaseDrawLine22 = 211f0
const PhasePenArcToIntersect = 220f0
const PhaseDrawIntersect = 221f0
const PhasePenLift2 = 250f0
const PhaseHideAll = 500f0

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(state.lines, state.markers, state.point, phase, timer)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """Euclid Elements - Book I - Postulate: Non-Parallel Lines

Let the following be postulated:

That, if a straight line falling on two straight lines make the interior angles on the same side less than two right angles, the two straight lines, if produced indefinitely, meet on the side on which are the angles less than the two right angles."""
    latex = raw"""\textbf{Euclid Elements - Book I - Postulate}: \textit{Non-Parallel Lines}

\textit{Let the following be postulated:}

That, if a straight line \euclidline[color=grey60,length=3,thickness=4] falling on two straight lines \euclidline[color=steelblue,length=3,thickness=4] \euclidline[color=palevioletred1,length=3,thickness=4] make the interior angles on the same side less than two right angles, the two straight lines, if produced indefinitely, meet on the side on which are the angles less than the two right angles."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset the animation cycle while preserving its native handles."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    line1_host_id = state.lines[1].host
    line1_joint2_id = state.lines[1].joint2
    line2_host_id = state.lines[2].host
    line2_joint2_id = state.lines[2].joint2
    line3_host_id = state.lines[3].host
    line3_joint2_id = state.lines[3].joint2
    marker1_host_id = state.markers[1].host
    marker1_start_id = state.markers[1].start
    marker1_end_id = state.markers[1].finish
    marker2_host_id = state.markers[2].host
    marker2_start_id = state.markers[2].start
    marker2_end_id = state.markers[2].finish
    pointid = state.point

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhaseDescend, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.hide_point_batch(
        state_ptr, [marker1_host_id, marker2_host_id, line1_host_id,
        line2_host_id, line3_host_id, pointid])

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.set_point_position(
        state_ptr, line1_joint2_id, StartPoint1)
    OdinJuliaBridge.set_point_position(
        state_ptr, line2_joint2_id, StartPoint2)
    OdinJuliaBridge.set_point_position(
        state_ptr, line3_joint2_id, StartPoint3)

    OdinJuliaBridge.hide_compass(state_ptr)
    OdinJuliaBridge.lock_compass_joint1(
        state_ptr, Marker1Center[1], Marker1Center[2], CompassTopZ)
    OdinJuliaBridge.lock_compass_joint2(
        state_ptr, Marker1Start[1], Marker1Start[2], CompassTopZ)
    OdinJuliaBridge.set_point_position(
        state_ptr, marker1_host_id, Marker1Center)
    OdinJuliaBridge.set_point_position(
        state_ptr, marker1_start_id, Marker1Start)
    OdinJuliaBridge.set_point_position(
        state_ptr, marker1_end_id, Marker1Start)
    OdinJuliaBridge.set_point_position(
        state_ptr, marker2_host_id, Marker2Center)
    OdinJuliaBridge.set_point_position(
        state_ptr, marker2_start_id, Marker2Start)
    OdinJuliaBridge.set_point_position(
        state_ptr, marker2_end_id, Marker2Start)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    marker1 = OdinJuliaBridge.create_new_filledcircle(state_ptr,
        Marker1Center, MarkerRadius, 0f0, 0f0,
        Marker1Color, 0f0)
    marker2 = OdinJuliaBridge.create_new_filledcircle(state_ptr,
        Marker2Center, MarkerRadius, Angle2StartΘ, Angle2StartΘ,
        Marker2Color, 0f0)
    line1 = OdinJuliaBridge.create_new_line(
        state_ptr, StartPoint1, StartPoint1, Line1Color, 0f0)
    line2 = OdinJuliaBridge.create_new_line(
        state_ptr, StartPoint2, StartPoint2, Line2Color, 0f0)
    line3 = OdinJuliaBridge.create_new_line(
        state_ptr, StartPoint3, StartPoint3, Line3Color, 0f0)
    point = OdinJuliaBridge.create_new_point(
        state_ptr, Intersection, PointColor, 0f0)

    lines = (
        LineIds(line1.host_id, line1.joint1_id, line1.joint2_id),
        LineIds(line2.host_id, line2.joint1_id, line2.joint2_id),
        LineIds(line3.host_id, line3.joint1_id, line3.joint2_id))
    markers = (
        CircleIds(marker1.host_id, marker1.start_id, marker1.end_id),
        CircleIds(marker2.host_id, marker2.start_id, marker2.end_id))
    reset_cycle_state(
        state_ptr, AnimationState(lines, markers, point.index, PhaseDescend, 0f0))
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
    line3_host_id = state.lines[3].host
    line3_joint1_id = state.lines[3].joint1
    line3_joint2_id = state.lines[3].joint2
    marker1_host_id = state.markers[1].host
    marker1_start_id = state.markers[1].start
    marker1_end_id = state.markers[1].finish
    marker2_host_id = state.markers[2].host
    marker2_start_id = state.markers[2].start
    marker2_end_id = state.markers[2].finish
    pointid = state.point

    if line1_host_id < 0 || line2_host_id < 0 || line3_host_id < 0 ||
        marker1_host_id < 0 || marker1_host_id < 0 ||
        marker2_host_id < 0 || marker2_host_id < 0 || pointid < 0
        return
    end

    phase = state.phase
    timer = state.timer

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, PenDescendDuration1, PenTopZ,
            StartPoint1[1], StartPoint1[2])

        timer += dt
        if timer >= PenDescendDuration1
            phase = PhaseDrawLine1
            timer = 0f0
        end
    elseif phase == PhaseDrawLine1
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, LineDrawDuration,
            StartPoint1, EndPoint11;
            penbrush=LineMaxBrush,
            pencolor=Line1Color,
            line_host_id=line1_host_id,
            line_joint1_id=line1_joint1_id,
            line_joint2_id=line1_joint2_id)

        timer += dt
        if timer >= LineDrawDuration
            phase = PhasePenArcToLine2
            timer = 0f0
        end
    elseif phase == PhasePenArcToLine2
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            EndPoint11, StartPoint2, ArcMoveHeight, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawLine2
            timer = 0f0
        end
    elseif phase == PhaseDrawLine2
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, LineDrawDuration,
            StartPoint2, EndPoint21;
            penbrush=LineMaxBrush,
            pencolor=Line2Color,
            line_host_id=line2_host_id,
            line_joint1_id=line2_joint1_id,
            line_joint2_id=line2_joint2_id)

        timer += dt
        if timer >= LineDrawDuration
            phase = PhasePenArcToLine3
            timer = 0f0
        end
    elseif phase == PhasePenArcToLine3
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            EndPoint21, StartPoint3, ArcMoveHeight, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawLine3
            timer = 0f0
        end
    elseif phase == PhaseDrawLine3
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, LineDrawDuration,
            StartPoint3, EndPoint3;
            penbrush=LineMaxBrush,
            pencolor=Line3Color,
            line_host_id=line3_host_id,
            line_joint1_id=line3_joint1_id,
            line_joint2_id=line3_joint2_id)

        timer += dt
        if timer >= LineDrawDuration
            phase = PhasePenLift
            timer = 0f0
        end
    elseif phase == PhasePenLift
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenRiseDuration1, PenTopZ, EndPoint3[1], EndPoint3[2])

        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, PenRiseDuration1, CompassTopZ,
            Marker1Center[1], Marker1Center[2], Marker1Start[1], Marker1Start[2])

        timer += dt
        if timer >= PenRiseDuration1
            phase = PhaseDrawMarker1
            timer = 0f0
        end
    elseif phase == PhaseDrawMarker1
        EuclidAnimations.animate_draw_filledcircle(state_ptr,
            timer, MarkerDrawDuration, Marker1Center,
            Marker1Start, Angle1StartΘ, MarkerRadius;
            brush=MarkerBrush,
            color=Marker1Color,
            marker_host_id=marker1_host_id,
            marker_start_id=marker1_start_id,
            marker_end_id=marker1_end_id)

        timer += dt
        if timer >= MarkerDrawDuration
            phase = PhaseCompassArcToMarker2
            timer = 0f0
        end
    elseif phase == PhaseCompassArcToMarker2
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, CompassArcMoveDuration,
            Marker1Center, Marker2Center, Marker1End, Marker2Start)

        timer += dt
        if timer >= CompassArcMoveDuration
            phase = PhaseDrawMarker2
            timer = 0f0
        end
    elseif phase == PhaseDrawMarker2
        EuclidAnimations.animate_draw_filledcircle(
            state_ptr, timer, MarkerDrawDuration, Marker2Center, Marker2Start,
            π - Angle2StartΘ, MarkerRadius, MarkerBrush, Marker2Color,
            marker2_host_id, marker2_start_id, marker2_end_id)

        timer += dt
        if timer >= MarkerDrawDuration
            phase = PhaseCompassRise
            timer = 0f0
        end
    elseif phase == PhaseCompassRise
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassRiseDuration, CompassTopZ,
            Marker2Center[1], Marker2Center[2], Marker2End[1], Marker2End[2])

        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, CompassRiseDuration, PenTopZ,
            EndPoint11[1], EndPoint11[2])

        timer += dt
        if timer >= CompassRiseDuration
            OdinJuliaBridge.hide_compass(state_ptr)
            phase = PhaseDrawLine12
            timer = 0f0
        end
    elseif phase == PhaseDrawLine12
        EuclidAnimations.animate_extend_line(
            state_ptr, timer, LineDrawDuration, StartPoint1, EndPoint11, EndPoint12,
            LineMaxBrush, Line1Color;
            line_host_id=line1_host_id,
            line_joint1_id=line1_joint1_id,
            line_joint2_id=line1_joint2_id)

        timer += dt
        if timer >= LineDrawDuration
            phase = PhasePenArcToLine22
            timer = 0f0
        end
    elseif phase == PhasePenArcToLine22
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            EndPoint12, EndPoint21, ArcMoveHeight, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawLine22
            timer = 0f0
        end
    elseif phase == PhaseDrawLine22
        EuclidAnimations.animate_extend_line(
            state_ptr, timer, LineDrawDuration, StartPoint2, EndPoint21, EndPoint22,
            LineMaxBrush, Line2Color;
            line_host_id=line2_host_id,
            line_joint1_id=line2_joint1_id,
            line_joint2_id=line2_joint2_id)

        timer += dt
        if timer >= LineDrawDuration
            phase = PhasePenArcToIntersect
            timer = 0f0
        end
    elseif phase == PhasePenArcToIntersect
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            EndPoint22, Intersection, ArcMoveHeight, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawIntersect
            timer = 0f0
        end
    elseif phase == PhaseDrawIntersect
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, Intersection,
            PointMaxBrush, PointColor, pointid)

        timer += dt
        if timer >= PointDrawDuration
            phase = PhasePenLift2
            timer = 0f0
        end
    elseif phase == PhasePenLift2
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenRiseDuration1, PenTopZ,
            Intersection[1], Intersection[2])

        timer += dt
        if timer >= PenRiseDuration1
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
    ElementsOnePostulatesNonParallelLines.AnimationId,
    ElementsOnePostulatesNonParallelLines.animation_entry)

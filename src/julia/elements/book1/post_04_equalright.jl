module ElementsOnePostulatesEqualRightAngles

using UUIDs
using ..AnimationCatalog

const AnimationId = UUID("7f6f36f4-a711-59c8-b22d-76f7157b29df")

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

using LinearAlgebra

export get_view_text, initialize, clean, loop, animation_entry

const LineLength = 0.3f0
const MarkerRadius = 0.15f0

const Angle1JointPoint = [0.1f0, 0.1f0, 0f0]
const Angle1StartΘ = 0f0
const Angle1End1Point = Angle1JointPoint +
    [LineLength * cos(Angle1StartΘ), LineLength * sin(Angle1StartΘ), 0f0]
const Angle1End2Point = Angle1JointPoint +
    [LineLength * cos(Angle1StartΘ + π/2f0),
     LineLength * sin(Angle1StartΘ + π/2f0), 0f0]
const Marker1Start = Angle1JointPoint +
    [MarkerRadius * cos(Angle1StartΘ), MarkerRadius * sin(Angle1StartΘ), 0f0]
const Marker1End = Angle1JointPoint +
    [MarkerRadius * cos(Angle1StartΘ + π/2f0),
     MarkerRadius * sin(Angle1StartΘ + π/2f0), 0f0]

const Angle2JointPoint = [0.35f0, 0.65f0, 0f0]
const Angle2StartΘ = 5f0π/3f0
const Angle2End1Point = Angle2JointPoint +
    [LineLength * cos(Angle2StartΘ), LineLength * sin(Angle2StartΘ), 0f0]
const Angle2End2Point = Angle2JointPoint +
    [LineLength * cos(Angle2StartΘ + π/2f0),
     LineLength * sin(Angle2StartΘ + π/2f0), 0f0]
const Marker2Start = Angle2JointPoint +
    [MarkerRadius * cos(Angle2StartΘ), MarkerRadius * sin(Angle2StartΘ), 0f0]
const Marker2End = Angle2JointPoint +
    [MarkerRadius * cos(Angle2StartΘ + π/2f0),
     MarkerRadius * sin(Angle2StartΘ + π/2f0), 0f0]

const Angle3JointPoint = [0.85f0, 0.55f0, 0f0]
const Angle3StartΘ = 5f0π/6f0
const Angle3End1Point = Angle3JointPoint +
    [LineLength * cos(Angle3StartΘ), LineLength * sin(Angle3StartΘ), 0f0]
const Angle3End2Point = Angle3JointPoint +
    [LineLength * cos(Angle3StartΘ + π/2f0),
     LineLength * sin(Angle3StartΘ + π/2f0), 0f0]
const Marker3Start = Angle3JointPoint +
    [MarkerRadius * cos(Angle3StartΘ),
     MarkerRadius * sin(Angle3StartΘ), 0f0]
const Marker3End = Angle3JointPoint +
    [MarkerRadius * cos(Angle3StartΘ + π/2f0),
     MarkerRadius * sin(Angle3StartΘ + π/2f0), 0f0]

const PenTopZ = 1.4f0
const CompassTopZ = 1.4f0

const Angle1LineColor = :steelblue
const Angle2LineColor = :palevioletred1
const Angle3LineColor = :khaki3
const MarkerColor = :grey60
const LineMaxBrush = 5f0
const MarkerBrush = 6f0

const PenDescendDuration = 1.8f0
const LineDrawDuration = 2.0f0
const ArcMoveDuration = 1.25f0
const ArcMoveHeight = 0.25f0
const PenRiseDuration = 1.8f0
const MarkerDrawDuration = 1.5f0
const CompassArcMoveDuration = 1.25f0
const CompassRiseDuration = 1.8f0
const MoveAngleDuration = 2.0f0
const HidePauseDuration = 1.5f0

"""Stable native handles for one line owned by the animation."""
struct LineIds
    host::Int64
    joint1::Int64
    joint2::Int64
end

"""Stable native handles for one circle owned by the animation."""
struct CircleIds
    host::Int64
    start::Int64
    finish::Int64
end

"""Complete immutable state for one equal-right-angles animation generation."""
struct AnimationState
    lines::NTuple{6,LineIds}
    markers::NTuple{3,CircleIds}
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhaseDescend = 0f0
const PhaseDrawLine = 10f0
const PhasePenArcToPivot = 11f0
const PhaseDrawLine2 = 12f0
const PhasePenArcToAngle2 = 20f0
const PhaseDrawLine3 = 21f0
const PhasePenArcToPivot2 = 22f0
const PhaseDrawLine4 = 23f0
const PhasePenArcToAngle3 = 30f0
const PhaseDrawLine5 = 31f0
const PhasePenArcToPivot3 = 32f0
const PhaseDrawLine6 = 33f0
const PhasePenLift = 50f0
const PhaseDrawMarker1 = 111f0
const PhaseCompassArcToMarker2 = 120f0
const PhaseDrawMarker2 = 121f0
const PhaseCompassArcToMarker3 = 130f0
const PhaseDrawMarker3 = 131f0
const PhaseCompassRise = 150f0
const PhaseMoveAngle2 = 200f0
const PhaseMoveAngle3 = 201f0
const PhaseHideAll = 500f0

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(state.lines, state.markers, phase, timer)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """Euclid Elements - Book I - Postulate: Equal Right Angles

Let the following be postulated:

That all right angles are equal to one another."""
    latex = raw"""\textbf{Euclid Elements - Book I - Postulate}: \textit{Equal Right Angles}

\textit{Let the following be postulated:}

That all right angles \euclidangle[color=grey60,radius=2,thickness=2] are equal to one another."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset the animation cycle while preserving its native handles."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    angle1_line1_host_id = state.lines[1].host
    angle1_line1_joint1_id = state.lines[1].joint1
    angle1_line1_joint2_id = state.lines[1].joint2
    angle1_line2_host_id = state.lines[2].host
    angle1_line2_joint1_id = state.lines[2].joint1
    angle1_line2_joint2_id = state.lines[2].joint2
    angle2_line1_host_id = state.lines[3].host
    angle2_line1_joint1_id = state.lines[3].joint1
    angle2_line1_joint2_id = state.lines[3].joint2
    angle2_line2_host_id = state.lines[4].host
    angle2_line2_joint1_id = state.lines[4].joint1
    angle2_line2_joint2_id = state.lines[4].joint2
    angle3_line1_host_id = state.lines[5].host
    angle3_line1_joint1_id = state.lines[5].joint1
    angle3_line1_joint2_id = state.lines[5].joint2
    angle3_line2_host_id = state.lines[6].host
    angle3_line2_joint1_id = state.lines[6].joint1
    angle3_line2_joint2_id = state.lines[6].joint2
    marker1_host_id = state.markers[1].host
    marker1_start_id = state.markers[1].start
    marker1_end_id = state.markers[1].finish
    marker2_host_id = state.markers[2].host
    marker2_start_id = state.markers[2].start
    marker2_end_id = state.markers[2].finish
    marker3_host_id = state.markers[3].host
    marker3_start_id = state.markers[3].start
    marker3_end_id = state.markers[3].finish

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhaseDescend, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [marker1_host_id, marker2_host_id, marker3_host_id,
         angle1_line1_host_id, angle1_line2_host_id,
         angle2_line1_host_id, angle2_line2_host_id,
         angle3_line1_host_id, angle3_line2_host_id
        ])

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.set_point_position(
        state_ptr, angle1_line1_joint1_id, Angle1JointPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, angle1_line1_joint2_id, Angle1JointPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, angle1_line2_joint1_id, Angle1JointPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, angle1_line2_joint2_id, Angle1JointPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, angle2_line1_joint1_id, Angle2JointPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, angle2_line1_joint2_id, Angle2JointPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, angle2_line2_joint1_id, Angle2JointPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, angle2_line2_joint2_id, Angle2JointPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, angle3_line1_joint1_id, Angle3JointPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, angle3_line1_joint2_id, Angle3JointPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, angle3_line2_joint1_id, Angle3JointPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, angle3_line2_joint2_id, Angle3JointPoint)

    OdinJuliaBridge.hide_compass(state_ptr)
    OdinJuliaBridge.lock_compass_joint1(
        state_ptr, Angle1JointPoint[1], Angle1JointPoint[2], CompassTopZ)
    OdinJuliaBridge.lock_compass_joint2(
        state_ptr, Marker1Start[1], Marker1Start[2], CompassTopZ)
    OdinJuliaBridge.set_point_position(
        state_ptr, marker1_host_id, Angle1JointPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, marker1_start_id, Marker1Start)
    OdinJuliaBridge.set_point_position(
        state_ptr, marker1_end_id, Marker1Start)
    OdinJuliaBridge.set_point_position(
        state_ptr, marker2_host_id, Angle2JointPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, marker2_start_id, Marker2Start)
    OdinJuliaBridge.set_point_position(
        state_ptr, marker2_end_id, Marker2Start)
    OdinJuliaBridge.set_point_position(
        state_ptr, marker3_host_id, Angle3JointPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, marker3_start_id, Marker3Start)
    OdinJuliaBridge.set_point_position(
        state_ptr, marker3_end_id, Marker3Start)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    marker1 = OdinJuliaBridge.create_new_circle(
        state_ptr,
        Angle1JointPoint,
        MarkerRadius, Angle1StartΘ, Angle1StartΘ,
        MarkerColor, 0f0)
    marker2 = OdinJuliaBridge.create_new_circle(
        state_ptr,
        Angle2JointPoint,
        MarkerRadius, Angle2StartΘ, Angle2StartΘ,
        MarkerColor, 0f0)
    marker3 = OdinJuliaBridge.create_new_circle(
        state_ptr,
        Angle3JointPoint,
        MarkerRadius, Angle3StartΘ, Angle3StartΘ,
        MarkerColor, 0f0)
    angle1_line1 = OdinJuliaBridge.create_new_line(
        state_ptr, Angle1JointPoint, Angle1JointPoint,
        Angle1LineColor, 0f0)
    angle1_line2 = OdinJuliaBridge.create_new_line(
        state_ptr, Angle1JointPoint, Angle1JointPoint,
        Angle1LineColor, 0f0)
    angle2_line1 = OdinJuliaBridge.create_new_line(
        state_ptr, Angle2JointPoint, Angle2JointPoint,
        Angle2LineColor, 0f0)
    angle2_line2 = OdinJuliaBridge.create_new_line(
        state_ptr, Angle2JointPoint, Angle2JointPoint,
        Angle2LineColor, 0f0)
    angle3_line1 = OdinJuliaBridge.create_new_line(
        state_ptr, Angle3JointPoint, Angle3JointPoint,
        Angle2LineColor, 0f0)
    angle3_line2 = OdinJuliaBridge.create_new_line(
        state_ptr, Angle3JointPoint, Angle3JointPoint,
        Angle3LineColor, 0f0)


    lines = (
        LineIds(angle1_line1.host_id, angle1_line1.joint1_id, angle1_line1.joint2_id),
        LineIds(angle1_line2.host_id, angle1_line2.joint1_id, angle1_line2.joint2_id),
        LineIds(angle2_line1.host_id, angle2_line1.joint1_id, angle2_line1.joint2_id),
        LineIds(angle2_line2.host_id, angle2_line2.joint1_id, angle2_line2.joint2_id),
        LineIds(angle3_line1.host_id, angle3_line1.joint1_id, angle3_line1.joint2_id),
        LineIds(angle3_line2.host_id, angle3_line2.joint1_id, angle3_line2.joint2_id))
    markers = (
        CircleIds(marker1.host_id, marker1.start_id, marker1.end_id),
        CircleIds(marker2.host_id, marker2.start_id, marker2.end_id),
        CircleIds(marker3.host_id, marker3.start_id, marker3.end_id))
    reset_cycle_state(
        state_ptr, AnimationState(lines, markers, PhaseDescend, 0f0))
    OdinJuliaBridge.publish_view_update(state_ptr, get_view_text)
end

"""Clean any extra animation data at the end of performance"""
function clean(state_ptr::Ptr{Cvoid})
end

"""Perform an iteration of the animation loop for this animation"""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    state, status = OdinJuliaBridge.get_animation_value(state_ptr, StateKey)
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return
    angle1_line1_host_id = state.lines[1].host
    angle1_line1_joint1_id = state.lines[1].joint1
    angle1_line1_joint2_id = state.lines[1].joint2
    angle1_line2_host_id = state.lines[2].host
    angle1_line2_joint1_id = state.lines[2].joint1
    angle1_line2_joint2_id = state.lines[2].joint2
    angle2_line1_host_id = state.lines[3].host
    angle2_line1_joint1_id = state.lines[3].joint1
    angle2_line1_joint2_id = state.lines[3].joint2
    angle2_line2_host_id = state.lines[4].host
    angle2_line2_joint1_id = state.lines[4].joint1
    angle2_line2_joint2_id = state.lines[4].joint2
    angle3_line1_host_id = state.lines[5].host
    angle3_line1_joint1_id = state.lines[5].joint1
    angle3_line1_joint2_id = state.lines[5].joint2
    angle3_line2_host_id = state.lines[6].host
    angle3_line2_joint1_id = state.lines[6].joint1
    angle3_line2_joint2_id = state.lines[6].joint2
    marker1_host_id = state.markers[1].host
    marker1_start_id = state.markers[1].start
    marker1_end_id = state.markers[1].finish
    marker2_host_id = state.markers[2].host
    marker2_start_id = state.markers[2].start
    marker2_end_id = state.markers[2].finish
    marker3_host_id = state.markers[3].host
    marker3_start_id = state.markers[3].start
    marker3_end_id = state.markers[3].finish

    if angle1_line1_host_id < 0 || angle1_line2_host_id < 0 ||
        angle2_line1_host_id < 0 || angle2_line2_host_id < 0 ||
        angle3_line1_host_id < 0 || angle3_line2_host_id < 0 ||
        marker1_host_id < 0 || marker1_host_id < 0 ||
        marker2_host_id < 0 || marker2_host_id < 0 ||
        marker3_host_id < 0 || marker3_host_id < 0
        return
    end

    phase = state.phase
    timer = state.timer

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, PenDescendDuration, PenTopZ,
            Angle1JointPoint[1], Angle1JointPoint[2])

        timer += dt
        if timer >= PenDescendDuration
            phase = PhaseDrawLine
            timer = 0f0
        end
    elseif phase == PhaseDrawLine
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, LineDrawDuration,
            Angle1JointPoint, Angle1End1Point;
            penbrush=LineMaxBrush,
            pencolor=Angle1LineColor,
            line_host_id=angle1_line1_host_id,
            line_joint1_id=angle1_line1_joint1_id,
            line_joint2_id=angle1_line1_joint2_id)

        timer += dt
        if timer >= LineDrawDuration
            phase = PhasePenArcToPivot
            timer = 0f0
        end
    elseif phase == PhasePenArcToPivot
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            Angle1End1Point, Angle1JointPoint, ArcMoveHeight, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawLine2
            timer = 0f0
        end
    elseif phase == PhaseDrawLine2
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, LineDrawDuration,
            Angle1JointPoint, Angle1End2Point;
            penbrush=LineMaxBrush,
            pencolor=Angle1LineColor,
            line_host_id=angle1_line2_host_id,
            line_joint1_id=angle1_line2_joint1_id,
            line_joint2_id=angle1_line2_joint2_id)

        timer += dt
        if timer >= LineDrawDuration
            phase = PhasePenArcToAngle2
            timer = 0f0
        end
    elseif phase == PhasePenArcToAngle2
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            Angle1End2Point, Angle2JointPoint, ArcMoveHeight, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawLine3
            timer = 0f0
        end
    elseif phase == PhaseDrawLine3
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, LineDrawDuration,
            Angle2JointPoint, Angle2End1Point;
            penbrush=LineMaxBrush,
            pencolor=Angle2LineColor,
            line_host_id=angle2_line1_host_id,
            line_joint1_id=angle2_line1_joint1_id,
            line_joint2_id=angle2_line1_joint2_id)

        timer += dt
        if timer >= LineDrawDuration
            phase = PhasePenArcToPivot2
            timer = 0f0
        end
    elseif phase == PhasePenArcToPivot2
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            Angle2End1Point, Angle2JointPoint, ArcMoveHeight, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawLine4
            timer = 0f0
        end
    elseif phase == PhaseDrawLine4
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, LineDrawDuration,
            Angle2JointPoint, Angle2End2Point;
            penbrush=LineMaxBrush,
            pencolor=Angle2LineColor,
            line_host_id=angle2_line2_host_id,
            line_joint1_id=angle2_line2_joint1_id,
            line_joint2_id=angle2_line2_joint2_id)

        timer += dt
        if timer >= LineDrawDuration
            phase = PhasePenArcToAngle3
            timer = 0f0
        end
    elseif phase == PhasePenArcToAngle3
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            Angle2End2Point, Angle3JointPoint, ArcMoveHeight, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawLine5
            timer = 0f0
        end
    elseif phase == PhaseDrawLine5
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, LineDrawDuration,
            Angle3JointPoint, Angle3End1Point;
            penbrush=LineMaxBrush,
            pencolor=Angle3LineColor,
            line_host_id=angle3_line1_host_id,
            line_joint1_id=angle3_line1_joint1_id,
            line_joint2_id=angle3_line1_joint2_id)

        timer += dt
        if timer >= LineDrawDuration
            phase = PhasePenArcToPivot3
            timer = 0f0
        end
    elseif phase == PhasePenArcToPivot3
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            Angle3End1Point, Angle3JointPoint, ArcMoveHeight, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawLine6
            timer = 0f0
        end
    elseif phase == PhaseDrawLine6
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, LineDrawDuration,
            Angle3JointPoint, Angle3End2Point;
            penbrush=LineMaxBrush,
            pencolor=Angle3LineColor,
            line_host_id=angle3_line2_host_id,
            line_joint1_id=angle3_line2_joint1_id,
            line_joint2_id=angle3_line2_joint2_id)

        timer += dt
        if timer >= LineDrawDuration
            phase = PhasePenLift
            timer = 0f0
        end
    elseif phase == PhasePenLift
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenRiseDuration, PenTopZ,
            Angle3End2Point[1], Angle3End2Point[2])

        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, PenRiseDuration, CompassTopZ,
            Angle1JointPoint[1], Angle1JointPoint[2],
            Marker1Start[1], Marker1Start[2])

        timer += dt
        if timer >= PenRiseDuration
            phase = PhaseDrawMarker1
            timer = 0f0
        end
    elseif phase == PhaseDrawMarker1
        EuclidAnimations.animate_draw_circle(state_ptr,
            timer, MarkerDrawDuration, Angle1JointPoint,
            Marker1Start, π/2f0, MarkerRadius;
            brush=MarkerBrush,
            color=MarkerColor,
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
            Angle1JointPoint, Angle2JointPoint, Marker1End, Marker2Start)

        timer += dt
        if timer >= CompassArcMoveDuration
            phase = PhaseDrawMarker2
            timer = 0f0
        end
    elseif phase == PhaseDrawMarker2
        EuclidAnimations.animate_draw_circle(state_ptr,
            timer, MarkerDrawDuration, Angle2JointPoint,
            Marker2Start, π/2f0, MarkerRadius;
            brush=MarkerBrush,
            color=MarkerColor,
            marker_host_id=marker2_host_id,
            marker_start_id=marker2_start_id,
            marker_end_id=marker2_end_id)

        timer += dt
        if timer >= MarkerDrawDuration
            phase = PhaseCompassArcToMarker3
            timer = 0f0
        end
    elseif phase == PhaseCompassArcToMarker3
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, CompassArcMoveDuration,
            Angle2JointPoint, Angle3JointPoint, Marker2End, Marker3Start)

        timer += dt
        if timer >= CompassArcMoveDuration
            phase = PhaseDrawMarker3
            timer = 0f0
        end
    elseif phase == PhaseDrawMarker3
        EuclidAnimations.animate_draw_circle(state_ptr,
            timer, MarkerDrawDuration, Angle3JointPoint,
            Marker3Start, π/2f0, MarkerRadius;
            brush=MarkerBrush,
            color=MarkerColor,
            marker_host_id=marker3_host_id,
            marker_start_id=marker3_start_id,
            marker_end_id=marker3_end_id)

        timer += dt
        if timer >= MarkerDrawDuration
            phase = PhaseCompassRise
            timer = 0f0
        end
    elseif phase == PhaseCompassRise
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassRiseDuration, CompassTopZ,
            Angle3JointPoint[1], Angle3JointPoint[2], Marker3End[1], Marker3End[2])

        timer += dt
        if timer >= CompassRiseDuration
            OdinJuliaBridge.hide_compass(state_ptr)
            phase = PhaseMoveAngle2
            timer = 0f0
        end
    elseif phase == PhaseMoveAngle2
        t = clamp(timer / MoveAngleDuration, 0f0, 1f0)
        
        movvec = Angle1JointPoint - Angle2JointPoint
        new_angle2_joint = Angle2JointPoint + movvec * t

        newθ = Angle2StartΘ + (2f0π - Angle2StartΘ) * t
        angle2_end1_point = new_angle2_joint +
            [LineLength * cos(newθ), LineLength * sin(newθ), 0f0]
        angle2_end2_point = new_angle2_joint +
            [LineLength * cos(newθ + π/2f0), LineLength * sin(newθ + π/2f0), 0f0]

        marker2_start = new_angle2_joint +
            [MarkerRadius * cos(newθ), MarkerRadius * sin(newθ), 0f0]
        marker2_end = new_angle2_joint +
            [MarkerRadius * cos(newθ + π/2f0), MarkerRadius * sin(newθ + π/2f0), 0f0]

        OdinJuliaBridge.set_point_position(
            state_ptr, angle2_line1_joint1_id, new_angle2_joint)
        OdinJuliaBridge.set_point_position(
            state_ptr, angle2_line1_joint2_id, angle2_end1_point)
        OdinJuliaBridge.set_point_position(
            state_ptr, angle2_line2_joint1_id, new_angle2_joint)
        OdinJuliaBridge.set_point_position(
            state_ptr, angle2_line2_joint2_id, angle2_end2_point)
        OdinJuliaBridge.set_point_position(
            state_ptr, marker2_host_id, new_angle2_joint)
        OdinJuliaBridge.set_point_position(
            state_ptr, marker2_start_id, marker2_start)
        OdinJuliaBridge.set_point_position(
            state_ptr, marker2_end_id, marker2_end)
        
        timer += dt
        if timer >= MoveAngleDuration
            OdinJuliaBridge.hide_compass(state_ptr)
            phase = PhaseMoveAngle3
            timer = 0f0
        end
    elseif phase == PhaseMoveAngle3
        t = clamp(timer / MoveAngleDuration, 0f0, 1f0)
        
        movvec = Angle1JointPoint - Angle3JointPoint
        new_angle3_joint = Angle3JointPoint + movvec * t

        newθ = Angle3StartΘ + (2f0π - Angle3StartΘ) * t
        angle3_end1_point = new_angle3_joint +
            [LineLength * cos(newθ), LineLength * sin(newθ), 0f0]
        angle3_end2_point = new_angle3_joint +
            [LineLength * cos(newθ + π/2f0), LineLength * sin(newθ + π/2f0), 0f0]

        marker3_start = new_angle3_joint +
            [MarkerRadius * cos(newθ), MarkerRadius * sin(newθ), 0f0]
        marker3_end = new_angle3_joint +
            [MarkerRadius * cos(newθ + π/2f0), MarkerRadius * sin(newθ + π/2f0), 0f0]

        OdinJuliaBridge.set_point_position(
            state_ptr, angle3_line1_joint1_id, new_angle3_joint)
        OdinJuliaBridge.set_point_position(
            state_ptr, angle3_line1_joint2_id, angle3_end1_point)
        OdinJuliaBridge.set_point_position(
            state_ptr, angle3_line2_joint1_id, new_angle3_joint)
        OdinJuliaBridge.set_point_position(
            state_ptr, angle3_line2_joint2_id, angle3_end2_point)
        OdinJuliaBridge.set_point_position(
            state_ptr, marker3_host_id, new_angle3_joint)
        OdinJuliaBridge.set_point_position(
            state_ptr, marker3_start_id, marker3_start)
        OdinJuliaBridge.set_point_position(
            state_ptr, marker3_end_id, marker3_end)

        timer += dt
        if timer >= MoveAngleDuration
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
    ElementsOnePostulatesEqualRightAngles.AnimationId,
    ElementsOnePostulatesEqualRightAngles.animation_entry)

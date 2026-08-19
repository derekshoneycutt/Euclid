module ElementsOneDefinitionObtuseAngle

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

using LinearAlgebra

export get_view_text, initialize, clean, loop

const JointPoint = [0.375f0, 0.30f0, 0f0]
const LineLength = 0.55f0
const AngleTheta = 2f0π / 3f0

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

const MetaLine1HostId = 1
const MetaLine1Joint1Id = 2
const MetaLine1Joint2Id = 3
const MetaLine2HostId = 4
const MetaLine2Joint1Id = 5
const MetaLine2Joint2Id = 6
const MetaMarkerHostId = 7
const MetaMarkerStartId = 8
const MetaMarkerEndId = 9
const MetaPhase = 10
const MetaTimer = 11

const PhasePenDescend = 0f0
const PhaseDrawLine1 = 1f0
const PhasePenArcToPivot = 2f0
const PhaseDrawLine2 = 3f0
const PhasePenLift = 4f0
const PhaseCompassDrawMarker = 5f0
const PhaseCompassLift = 6f0
const PhaseHideAll = 7f0

function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """Euclid Elements - Book I - Definition: Obtuse Angle

An obtuse angle is an angle greater than a right angle."""
    latex = raw"""\textbf{Euclid Elements - Book I - Definition}: \textit{Obtuse Angle}

An obtuse angle \euclidangle[color=khaki3,radius=2,end=120,filled] is an angle greater than a right angle."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end


function reset_cycle_state(state_ptr::Ptr{Cvoid})
    line1_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine1HostId))
    line1_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine1Joint2Id))

    line2_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine2HostId))
    line2_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine2Joint2Id))

    marker_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaMarkerHostId))
    marker_end_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaMarkerEndId))

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

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhasePenDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    marker = OdinJuliaBridge.create_new_filledcircle(
        state_ptr,
        JointPoint[1], JointPoint[2], JointPoint[3],
        MarkerRadius, 0f0, 0f0,
        MarkerColor, 0f0)
    line1 = OdinJuliaBridge.create_new_line(
        state_ptr,
        Line1Start[1], Line1Start[2], Line1Start[3],
        Line1Start[1], Line1Start[2], Line1Start[3],
        LineColor1, 0f0)
    line2 = OdinJuliaBridge.create_new_line(
        state_ptr,
        Line2Start[1], Line2Start[2], Line2Start[3],
        Line2Start[1], Line2Start[2], Line2Start[3],
        LineColor2, 0f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine1HostId, line1.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine1Joint1Id, line1.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine1Joint2Id, line1.joint2_id)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine2HostId, line2.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine2Joint1Id, line2.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine2Joint2Id, line2.joint2_id)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarkerHostId, marker.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarkerStartId, marker.start_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarkerEndId, marker.end_id)

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    line1_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine1HostId))
    line1_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine1Joint1Id))
    line1_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine1Joint2Id))

    line2_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine2HostId))
    line2_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine2Joint1Id))
    line2_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine2Joint2Id))

    marker_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaMarkerHostId))
    marker_start_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaMarkerStartId))
    marker_end_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaMarkerEndId))

    if line1_host_id < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhasePenDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, Line1Start[1], Line1Start[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawLine1
            timer = 0f0
        end
    elseif phase == PhaseDrawLine1
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, Line1Start, Line1End,
            LineMaxBrush, LineColor1, line1_host_id, line1_joint1_id, line1_joint2_id)

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
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, Line2Start, Line2End,
            LineMaxBrush, LineColor2, line2_host_id, line2_joint1_id, line2_joint2_id)

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
        EuclidAnimations.animate_draw_filledcircle(
            state_ptr, timer, CompassDrawDuration, JointPoint, MarkerStart,
            AngleTheta, MarkerRadius, MarkerBrush, MarkerColor,
            marker_host_id, marker_start_id, marker_end_id)

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
            reset_cycle_state(state_ptr)
            return
        end
    end

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, phase)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, timer)
end

end

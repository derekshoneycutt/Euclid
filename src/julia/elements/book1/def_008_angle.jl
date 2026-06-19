module ElementsOneDefinitionPlaneAngle

using ..EuclidBridge
using ..EuclidAnimations

using LinearAlgebra

export get_view_text, initialize, clean, loop

const JointPoint = [0.30f0, 0.30f0, 0f0]
const LineLength = 0.55f0
const AngleTheta = π / 3f0

const Line1Start = JointPoint
const Line1End = [JointPoint[1] + LineLength, JointPoint[2], 0f0]
const Line2Start = JointPoint
const Line2End = [
    JointPoint[1] + LineLength * Float32(cos(AngleTheta)),
    JointPoint[2] + LineLength * Float32(sin(AngleTheta)),
    0f0,
]

const MarkerRadius = 0.20f0
const MarkerStart = [JointPoint[1] + MarkerRadius, JointPoint[2], 0f0]
const MarkerEnd = [
    JointPoint[1] + MarkerRadius * Float32(cos(AngleTheta)),
    JointPoint[2] + MarkerRadius * Float32(sin(AngleTheta))
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
    """Euclid Elements - Book I - Definition: Plane Angle

A plane angle is the inclination to one another of two lines in a plane which meet one another and do not lie in a straight line.

And when the lines containing the angle are straight, the angle is called rectilinear."""
end


function reset_cycle_state(state_ptr::Ptr{Cvoid})
    line1HostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine1HostId))
    line1Joint2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine1Joint2Id))

    line2HostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine2HostId))
    line2Joint2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine2Joint2Id))

    markerHostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaMarkerHostId))
    markerEndId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaMarkerEndId))

    EuclidBridge.hide_point(state_ptr, markerHostId)
    EuclidBridge.set_point_position(
        state_ptr, markerEndId, MarkerStart[1], MarkerStart[2], MarkerStart[3])

    EuclidBridge.hide_point(state_ptr, line2HostId)
    EuclidBridge.set_point_position(
        state_ptr, line2Joint2Id, Line2Start[1], Line2Start[2], Line2Start[3])
    EuclidBridge.hide_point(state_ptr, line1HostId)
    EuclidBridge.set_point_position(
        state_ptr, line1Joint2Id, Line1Start[1], Line1Start[2], Line1Start[3])

    EuclidBridge.hide_compass(state_ptr)
    EuclidBridge.show_pen(state_ptr)
    EuclidBridge.set_pen_active(state_ptr, 0, LineColor1)
    EuclidBridge.set_compass_active(state_ptr, 0, LineColor1)
    EuclidBridge.lock_compass_joint1(state_ptr, JointPoint[1], JointPoint[2], CompassTopZ)
    EuclidBridge.lock_compass_joint2(state_ptr, MarkerStart[1], MarkerStart[2], CompassTopZ)

    EuclidBridge.set_animation_meta(state_ptr, MetaPhase, PhasePenDescend)
    EuclidBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)
end

function initialize(state_ptr::Ptr{Cvoid})
    marker = EuclidBridge.create_new_filledcircle(
        state_ptr,
        JointPoint[1], JointPoint[2], JointPoint[3],
        MarkerRadius, 0f0, 0f0,
        MarkerColor, 0f0)
    line1 = EuclidBridge.create_new_line(
        state_ptr,
        Line1Start[1], Line1Start[2], Line1Start[3],
        Line1Start[1], Line1Start[2], Line1Start[3],
        LineColor1, 0f0)
    line2 = EuclidBridge.create_new_line(
        state_ptr,
        Line2Start[1], Line2Start[2], Line2Start[3],
        Line2Start[1], Line2Start[2], Line2Start[3],
        LineColor2, 0f0)

    EuclidBridge.set_animation_meta(state_ptr, MetaLine1HostId, Float32(line1.hostId))
    EuclidBridge.set_animation_meta(state_ptr, MetaLine1Joint1Id, Float32(line1.joint1Id))
    EuclidBridge.set_animation_meta(state_ptr, MetaLine1Joint2Id, Float32(line1.joint2Id))

    EuclidBridge.set_animation_meta(state_ptr, MetaLine2HostId, Float32(line2.hostId))
    EuclidBridge.set_animation_meta(state_ptr, MetaLine2Joint1Id, Float32(line2.joint1Id))
    EuclidBridge.set_animation_meta(state_ptr, MetaLine2Joint2Id, Float32(line2.joint2Id))

    EuclidBridge.set_animation_meta(state_ptr, MetaMarkerHostId, Float32(marker.hostId))
    EuclidBridge.set_animation_meta(state_ptr, MetaMarkerStartId, Float32(marker.startId))
    EuclidBridge.set_animation_meta(state_ptr, MetaMarkerEndId, Float32(marker.endId))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    line1HostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine1HostId))
    line1Joint1Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine1Joint1Id))
    line1Joint2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine1Joint2Id))

    line2HostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine2HostId))
    line2Joint1Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine2Joint1Id))
    line2Joint2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine2Joint2Id))

    markerHostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaMarkerHostId))
    markerStartId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaMarkerStartId))
    markerEndId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaMarkerEndId))

    if line1HostId < 0
        return
    end

    phase = EuclidBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = EuclidBridge.get_animation_meta(state_ptr, MetaTimer)

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
            LineMaxBrush, LineColor1, line1HostId, line1Joint1Id, line1Joint2Id)

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
            LineMaxBrush, LineColor2, line2HostId, line2Joint1Id, line2Joint2Id)

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
            EuclidBridge.hide_pen(state_ptr)
            phase = PhaseCompassDrawMarker
            timer = 0f0
        end
    elseif phase == PhaseCompassDrawMarker
        EuclidAnimations.animate_draw_filledcircle(
            state_ptr, timer, CompassDrawDuration, JointPoint, MarkerStart,
            AngleTheta, MarkerRadius, MarkerBrush, MarkerColor,
            markerHostId, markerStartId, markerEndId)

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
            EuclidBridge.hide_compass(state_ptr)
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

    EuclidBridge.set_animation_meta(state_ptr, MetaPhase, phase)
    EuclidBridge.set_animation_meta(state_ptr, MetaTimer, timer)
end

end

module ElementsOneDefinitionPerpendicular

using ..OdinJuliaBridge
using ..EuclidAnimations

using LinearAlgebra

export get_view_text, initialize, clean, loop

const StartPoint = [0.25f0, 0.75f0, 0f0]
const EndPoint = [0.75f0, 0.25f0, 0f0]
const PerpStartPoint = [0.5f0, 0.5f0, 0f0]
const PerpEndPoint = [1f0, 1f0, 0f0]

const MarkerRadius = 0.20f0
const MainLineUnit = normalize(Float32[EndPoint[1] - StartPoint[1], EndPoint[2] - StartPoint[2]])
const MarkerStart = [
    PerpStartPoint[1] + MarkerRadius * MainLineUnit[1],
    PerpStartPoint[2] + MarkerRadius * MainLineUnit[2],
    0f0]
const MarkerEnd = [
    PerpStartPoint[1] - MarkerRadius * MainLineUnit[1],
    PerpStartPoint[2] - MarkerRadius * MainLineUnit[2],
    0f0]
const AngleTheta = Float32(π)

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

const MetaLineHostId = 1
const MetaLineJoint1Id = 2
const MetaLineJoint2Id = 3
const MetaPerpLineHostId = 4
const MetaPerpLineJoint1Id = 5
const MetaPerpLineJoint2Id = 6
const MetaMarkerHostId = 7
const MetaMarkerStartId = 8
const MetaMarkerEndId = 9
const MetaPhase = 10
const MetaTimer = 11

const PhaseDescend = 0f0
const PhaseDrawLine1 = 1f0
const PhasePenArcToPivot = 2f0
const PhaseDrawLine2 = 3f0
const PhaseEndLift = 4f0
const PhaseCompassDrawMarker = 5f0
const PhaseCompassLift = 6f0
const PhaseHideAll = 7f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """Euclid Elements - Book I - Definition: Right Angles and Perpendicular

When a straight line set up on a straight line makes the adjacent angles equal to one another, each of the equal angles is right, and the straight line standing on the other is called a perpendicular to that on which it stands."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    lineHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineHostId))
    lineJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineJoint2Id))

    perplineHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPerpLineHostId))
    perplineJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPerpLineJoint2Id))

    markerHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerHostId))
    markerEndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerEndId))

    OdinJuliaBridge.hide_point_batch(state_ptr, [markerHostId, lineHostId, perplineHostId])

    OdinJuliaBridge.set_point_position(
        state_ptr, markerEndId, MarkerStart[1], MarkerStart[2], MarkerStart[3])

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.set_point_position(
        state_ptr, lineJoint2Id, StartPoint[1], StartPoint[2], StartPoint[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, perplineJoint2Id, PerpStartPoint[1], PerpStartPoint[2], PerpStartPoint[3])

    OdinJuliaBridge.hide_compass(state_ptr)
    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, LineColor)
    OdinJuliaBridge.set_compass_active(state_ptr, 0, MarkerColor)
    OdinJuliaBridge.lock_compass_joint1(state_ptr, PerpStartPoint[1], PerpStartPoint[2], CompassTopZ)
    OdinJuliaBridge.lock_compass_joint2(state_ptr, MarkerStart[1], MarkerStart[2], CompassTopZ)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)
end

function initialize(state_ptr::Ptr{Cvoid})
    marker = OdinJuliaBridge.create_new_circle(
        state_ptr,
        PerpStartPoint, MarkerRadius, 7f0 * π / 4f0, 7f0 * π / 4f0,
        MarkerColor, 0f0)
    line = OdinJuliaBridge.create_new_line(
        state_ptr,
        StartPoint[1], StartPoint[2], StartPoint[3],
        StartPoint[1], StartPoint[2], StartPoint[3],
        LineColor, 0f0)
    perpline = OdinJuliaBridge.create_new_line(
        state_ptr,
        PerpStartPoint[1], PerpStartPoint[2], PerpStartPoint[3],
        PerpStartPoint[1], PerpStartPoint[2], PerpStartPoint[3],
        PerpLineColor, 0f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineHostId, Float32(line.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineJoint1Id, Float32(line.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineJoint2Id, Float32(line.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPerpLineHostId, Float32(perpline.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPerpLineJoint1Id, Float32(perpline.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPerpLineJoint2Id, Float32(perpline.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarkerHostId, Float32(marker.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarkerStartId, Float32(marker.startId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarkerEndId, Float32(marker.endId))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    lineHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineHostId))
    lineJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineJoint1Id))
    lineJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineJoint2Id))

    perplineHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPerpLineHostId))
    perplineJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPerpLineJoint1Id))
    perplineJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPerpLineJoint2Id))

    markerHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerHostId))
    markerStartId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerStartId))
    markerEndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerEndId))

    if lineHostId < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, StartPoint[1], StartPoint[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawLine1
            timer = 0f0
        end
    elseif phase == PhaseDrawLine1
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, LineDrawDuration, StartPoint, EndPoint,
            LineMaxBrush, LineColor, lineHostId, lineJoint1Id, lineJoint2Id)

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
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, LineDrawDuration, PerpStartPoint, PerpEndPoint,
            LineMaxBrush, PerpLineColor, perplineHostId, perplineJoint1Id, perplineJoint2Id)

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
        EuclidAnimations.animate_draw_circle(
            state_ptr, timer, CompassDrawDuration, PerpStartPoint, MarkerStart,
            AngleTheta, MarkerRadius, LineMaxBrush, MarkerColor,
            markerHostId, markerStartId, markerEndId)

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
            reset_cycle_state(state_ptr)
            return
        end
    end

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, phase)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, timer)
end

end

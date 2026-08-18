module ElementsOnePostulatesNonParallelLines

using ..OdinJuliaBridge
using ..EuclidGeometry
using ..EuclidAnimations
using ..EuclidLatex

using LinearAlgebra

export get_view_text, initialize, clean, loop

const StartPoint1 = [0.25f0, 0.1f0, 0f0]
const EndPoint1_2 = [0.51f0, 0.9f0, 0f0]
const EndPoint1_1 = StartPoint1 + (EndPoint1_2 - StartPoint1) * 0.4f0
const Angle1StartΘ = Float32(atan(EndPoint1_2[2] - StartPoint1[2], EndPoint1_2[1] - StartPoint1[1]))

const StartPoint2 = [0.75f0, 0.1f0, 0f0]
const EndPoint2_2 = [0.49f0, 0.9f0, 0f0]
const EndPoint2_1 = StartPoint2 + (EndPoint2_2 - StartPoint2) * 0.4f0
const Angle2StartΘ = Float32(atan(EndPoint2_2[2] - StartPoint2[2], EndPoint2_2[1] - StartPoint2[1]))

const StartPoint3 = [0.15f0, 0.2f0, 0f0]
const EndPoint3 = [0.85f0, 0.2f0, 0f0]

const MarkerRadius = 0.15f0

const Marker1Center = line_intersection_3d(StartPoint1, EndPoint1_1, StartPoint3, EndPoint3)
const Marker1Start = Marker1Center + normalize(EndPoint3 - Marker1Center) * MarkerRadius
const Marker1End = Marker1Center + normalize(EndPoint1_2 - Marker1Center) * MarkerRadius

const Marker2Center = line_intersection_3d(StartPoint2, EndPoint2_1, StartPoint3, EndPoint3)
const Marker2Start = Marker2Center + normalize(EndPoint2_2 - Marker2Center) * MarkerRadius
const Marker2End = Marker2Center + normalize(StartPoint3 - Marker2Center) * MarkerRadius

const Intersection = line_intersection_3d(StartPoint1, EndPoint1_2, StartPoint2, EndPoint2_2)

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
const CompassArcMoveHeight = 0.25f0
const CompassRiseDuration = 1.8f0
const PointDrawDuration = 4f0
const HidePauseDuration = 1.5f0

const MetaLine1HostId = 1
const MetaLine1Joint1Id = 2
const MetaLine1Joint2Id = 3
const MetaLine2HostId = 11
const MetaLine2Joint1Id = 12
const MetaLine2Joint2Id = 13
const MetaLine3HostId = 21
const MetaLine3Joint1Id = 22
const MetaLine3Joint2Id = 23
const MetaMarker1HostId = 31
const MetaMarker1StartId = 32
const MetaMarker1EndId = 33
const MetaMarker2HostId = 41
const MetaMarker2StartId = 42
const MetaMarker2EndId = 43
const MetaPointId = 51
const MetaPhase = 200
const MetaTimer = 201

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
const PhaseDrawLine1_2 = 201f0
const PhasePenArcToLine2_2 = 210f0
const PhaseDrawLine2_2 = 211f0
const PhasePenArcToIntersect = 220f0
const PhaseDrawIntersect = 221f0
const PhasePenLift2 = 250f0
const PhaseHideAll = 500f0


function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """Euclid Elements - Book I - Postulate: Non-Parallel Lines

Let the following be postulated:

That, if a straight line falling on two straight lines make the interior angles on the same side less than two right angles, the two straight lines, if produced indefinitely, meet on the side on which are the angles less than the two right angles."""
    latex = raw"""\textbf{Euclid Elements - Book I - Postulate}: \textit{Non-Parallel Lines}

\textit{Let the following be postulated:}

That, if a straight line \euclidline[color=grey60,length=3,thickness=4] falling on two straight lines \euclidline[color=steelblue,length=3,thickness=4] \euclidline[color=palevioletred1,length=3,thickness=4] make the interior angles on the same side less than two right angles, the two straight lines, if produced indefinitely, meet on the side on which are the angles less than the two right angles."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    line1_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine1HostId))
    line1_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine1Joint2Id))

    line2_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine2HostId))
    line2_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine2Joint2Id))

    line3_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine3HostId))
    line3_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine3Joint2Id))

    marker1_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker1HostId))
    marker1_start_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker1StartId))
    marker1_end_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker1EndId))

    marker2_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker2HostId))
    marker2_start_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker2StartId))
    marker2_end_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker2EndId))

    pointid = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointId))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.hide_point_batch(
        state_ptr, [marker1_host_id, marker2_host_id, line1_host_id, line2_host_id, line3_host_id, pointid])

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
end

function initialize(state_ptr::Ptr{Cvoid})
    marker1 = OdinJuliaBridge.create_new_filledcircle(
        state_ptr,
        Marker1Center,
        MarkerRadius, 0f0, 0f0,
        Marker1Color, 0f0)
    marker2 = OdinJuliaBridge.create_new_filledcircle(
        state_ptr,
        Marker2Center,
        MarkerRadius, Angle2StartΘ, Angle2StartΘ,
        Marker2Color, 0f0)
    line1 = OdinJuliaBridge.create_new_line(
        state_ptr, StartPoint1, StartPoint1, Line1Color, 0f0)
    line2 = OdinJuliaBridge.create_new_line(
        state_ptr, StartPoint2, StartPoint2, Line2Color, 0f0)
    line3 = OdinJuliaBridge.create_new_line(
        state_ptr, StartPoint3, StartPoint3, Line3Color, 0f0)
    point = OdinJuliaBridge.create_new_point(
        state_ptr, Intersection, PointColor, 0f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker1HostId, Float32(marker1.host_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker1StartId, Float32(marker1.start_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker1EndId, Float32(marker1.end_id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker2HostId, Float32(marker2.host_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker2StartId, Float32(marker2.start_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker2EndId, Float32(marker2.end_id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine1HostId, Float32(line1.host_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine1Joint1Id, Float32(line1.joint1_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine1Joint2Id, Float32(line1.joint2_id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine2HostId, Float32(line2.host_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine2Joint1Id, Float32(line2.joint1_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine2Joint2Id, Float32(line2.joint2_id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine3HostId, Float32(line3.host_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine3Joint1Id, Float32(line3.joint1_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine3Joint2Id, Float32(line3.joint2_id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointId, Float32(point.index))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    line1_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine1HostId))
    line1_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine1Joint1Id))
    line1_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine1Joint2Id))

    line2_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine2HostId))
    line2_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine2Joint1Id))
    line2_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine2Joint2Id))

    line3_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine3HostId))
    line3_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine3Joint1Id))
    line3_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine3Joint2Id))

    marker1_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker1HostId))
    marker1_start_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker1StartId))
    marker1_end_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker1EndId))

    marker2_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker2HostId))
    marker2_start_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker2StartId))
    marker2_end_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker2EndId))

    pointid = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointId))

    if line1_host_id < 0 || line2_host_id < 0 || line3_host_id < 0 ||
        marker1_host_id < 0 || marker1_host_id < 0 ||
        marker2_host_id < 0 || marker2_host_id < 0 || pointid < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, PenDescendDuration1, PenTopZ, StartPoint1[1], StartPoint1[2])

        timer += dt
        if timer >= PenDescendDuration1
            phase = PhaseDrawLine1
            timer = 0f0
        end
    elseif phase == PhaseDrawLine1
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, LineDrawDuration, StartPoint1, EndPoint1_1,
            LineMaxBrush, Line1Color, line1_host_id, line1_joint1_id, line1_joint2_id)

        timer += dt
        if timer >= LineDrawDuration
            phase = PhasePenArcToLine2
            timer = 0f0
        end
    elseif phase == PhasePenArcToLine2
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            EndPoint1_1, StartPoint2, ArcMoveHeight, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawLine2
            timer = 0f0
        end
    elseif phase == PhaseDrawLine2
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, LineDrawDuration, StartPoint2, EndPoint2_1,
            LineMaxBrush, Line2Color, line2_host_id, line2_joint1_id, line2_joint2_id)

        timer += dt
        if timer >= LineDrawDuration
            phase = PhasePenArcToLine3
            timer = 0f0
        end
    elseif phase == PhasePenArcToLine3
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            EndPoint2_1, StartPoint3, ArcMoveHeight, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawLine3
            timer = 0f0
        end
    elseif phase == PhaseDrawLine3
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, LineDrawDuration, StartPoint3, EndPoint3,
            LineMaxBrush, Line3Color, line3_host_id, line3_joint1_id, line3_joint2_id)

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
        EuclidAnimations.animate_draw_filledcircle(
            state_ptr, timer, MarkerDrawDuration, Marker1Center, Marker1Start,
            Angle1StartΘ, MarkerRadius, MarkerBrush, Marker1Color,
            marker1_host_id, marker1_start_id, marker1_end_id)

        timer += dt
        if timer >= MarkerDrawDuration
            phase = PhaseCompassArcToMarker2
            timer = 0f0
        end
    elseif phase == PhaseCompassArcToMarker2
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, CompassArcMoveDuration,
            Marker1Center, Marker2Center, Marker1End, Marker2Start,
            CompassArcMoveHeight, 1, :none)

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
            state_ptr, timer, CompassRiseDuration, PenTopZ, EndPoint1_1[1], EndPoint1_1[2])

        timer += dt
        if timer >= CompassRiseDuration
            OdinJuliaBridge.hide_compass(state_ptr)
            phase = PhaseDrawLine1_2
            timer = 0f0
        end
    elseif phase == PhaseDrawLine1_2
        EuclidAnimations.animate_extend_line(
            state_ptr, timer, LineDrawDuration, StartPoint1, EndPoint1_1, EndPoint1_2,
            LineMaxBrush, Line1Color, line1_host_id, line1_joint1_id, line1_joint2_id)

        timer += dt
        if timer >= LineDrawDuration
            phase = PhasePenArcToLine2_2
            timer = 0f0
        end
    elseif phase == PhasePenArcToLine2_2
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            EndPoint1_2, EndPoint2_1, ArcMoveHeight, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawLine2_2
            timer = 0f0
        end
    elseif phase == PhaseDrawLine2_2
        EuclidAnimations.animate_extend_line(
            state_ptr, timer, LineDrawDuration, StartPoint2, EndPoint2_1, EndPoint2_2,
            LineMaxBrush, Line2Color, line2_host_id, line2_joint1_id, line2_joint2_id)

        timer += dt
        if timer >= LineDrawDuration
            phase = PhasePenArcToIntersect
            timer = 0f0
        end
    elseif phase == PhasePenArcToIntersect
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            EndPoint2_2, Intersection, ArcMoveHeight, 1, :none)

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
            state_ptr, timer, PenRiseDuration1, PenTopZ, Intersection[1], Intersection[2])

        timer += dt
        if timer >= PenRiseDuration1
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

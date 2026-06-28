module ElementsOnePostulatesEqualRightAngles

using ..OdinJuliaBridge
using ..EuclidAnimations

using LinearAlgebra

export get_view_text, initialize, clean, loop

const LineLength = 0.3f0
const MarkerRadius = 0.15f0

const Angle1JointPoint = [0.1f0, 0.1f0, 0f0]
const Angle1StartΘ = 0f0
const Angle1End1Point = Angle1JointPoint +
    [LineLength * cos(Angle1StartΘ), LineLength * sin(Angle1StartΘ), 0f0]
const Angle1End2Point = Angle1JointPoint +
    [LineLength * cos(Angle1StartΘ + π/2f0), LineLength * sin(Angle1StartΘ + π/2f0), 0f0]
const Marker1Start = Angle1JointPoint +
    [MarkerRadius * cos(Angle1StartΘ), MarkerRadius * sin(Angle1StartΘ), 0f0]
const Marker1End = Angle1JointPoint +
    [MarkerRadius * cos(Angle1StartΘ + π/2f0), MarkerRadius * sin(Angle1StartΘ + π/2f0), 0f0]

const Angle2JointPoint = [0.35f0, 0.65f0, 0f0]
const Angle2StartΘ = 5f0π/3f0
const Angle2End1Point = Angle2JointPoint +
    [LineLength * cos(Angle2StartΘ), LineLength * sin(Angle2StartΘ), 0f0]
const Angle2End2Point = Angle2JointPoint +
    [LineLength * cos(Angle2StartΘ + π/2f0), LineLength * sin(Angle2StartΘ + π/2f0), 0f0]
const Marker2Start = Angle2JointPoint +
    [MarkerRadius * cos(Angle2StartΘ), MarkerRadius * sin(Angle2StartΘ), 0f0]
const Marker2End = Angle2JointPoint +
    [MarkerRadius * cos(Angle2StartΘ + π/2f0), MarkerRadius * sin(Angle2StartΘ + π/2f0), 0f0]

const Angle3JointPoint = [0.85f0, 0.55f0, 0f0]
const Angle3StartΘ = 5f0π/6f0
const Angle3End1Point = Angle3JointPoint +
    [LineLength * cos(Angle3StartΘ), LineLength * sin(Angle3StartΘ), 0f0]
const Angle3End2Point = Angle3JointPoint +
    [LineLength * cos(Angle3StartΘ + π/2f0), LineLength * sin(Angle3StartΘ + π/2f0), 0f0]
const Marker3Start = Angle3JointPoint +
    [MarkerRadius * cos(Angle3StartΘ), MarkerRadius * sin(Angle3StartΘ), 0f0]
const Marker3End = Angle3JointPoint +
    [MarkerRadius * cos(Angle3StartΘ + π/2f0), MarkerRadius * sin(Angle3StartΘ + π/2f0), 0f0]

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
const CompassArcMoveHeight = 0.25f0
const CompassRiseDuration = 1.8f0
const MoveAngleDuration = 2.0f0
const HidePauseDuration = 1.5f0

const MetaAngle1Line1HostId = 1
const MetaAngle1Line1Joint1Id = 2
const MetaAngle1Line1Joint2Id = 3
const MetaAngle1Line2HostId = 4
const MetaAngle1Line2Joint1Id = 5
const MetaAngle1Line2Joint2Id = 6
const MetaMarker1HostId = 7
const MetaMarker1StartId = 8
const MetaMarker1EndId = 9
const MetaAngle2Line1HostId = 11
const MetaAngle2Line1Joint1Id = 12
const MetaAngle2Line1Joint2Id = 13
const MetaAngle2Line2HostId = 14
const MetaAngle2Line2Joint1Id = 15
const MetaAngle2Line2Joint2Id = 16
const MetaMarker2HostId = 17
const MetaMarker2StartId = 18
const MetaMarker2EndId = 19
const MetaAngle3Line1HostId = 21
const MetaAngle3Line1Joint1Id = 22
const MetaAngle3Line1Joint2Id = 23
const MetaAngle3Line2HostId = 24
const MetaAngle3Line2Joint1Id = 25
const MetaAngle3Line2Joint2Id = 26
const MetaMarker3HostId = 27
const MetaMarker3StartId = 28
const MetaMarker3EndId = 29
const MetaPhase = 200
const MetaTimer = 201

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


function get_view_text(state_ptr::Ptr{Cvoid})
    """Euclid Elements - Book I - Postulate: Equal Right Angles

Let the following be postulated:

That all right angles are equal to one another."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    angle1Line1HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAngle1Line1HostId))
    angle1Line1Joint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAngle1Line1Joint1Id))
    angle1Line1Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAngle1Line1Joint2Id))
    angle1Line2HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAngle1Line2HostId))
    angle1Line2Joint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAngle1Line2Joint1Id))
    angle1Line2Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAngle1Line2Joint2Id))

    angle2Line1HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAngle2Line1HostId))
    angle2Line1Joint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAngle2Line1Joint1Id))
    angle2Line1Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAngle2Line1Joint2Id))
    angle2Line2HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAngle2Line2HostId))
    angle2Line2Joint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAngle2Line2Joint1Id))
    angle2Line2Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAngle2Line2Joint2Id))

    angle3Line1HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAngle3Line1HostId))
    angle3Line1Joint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAngle3Line1Joint1Id))
    angle3Line1Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAngle3Line1Joint2Id))
    angle3Line2HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAngle3Line2HostId))
    angle3Line2Joint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAngle3Line2Joint1Id))
    angle3Line2Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAngle3Line2Joint2Id))

    marker1HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker1HostId))
    marker1StartId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker1StartId))
    marker1EndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker1EndId))

    marker2HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker2HostId))
    marker2StartId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker2StartId))
    marker2EndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker2EndId))

    marker3HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker3HostId))
    marker3StartId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker3StartId))
    marker3EndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker3EndId))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [marker1HostId, marker2HostId, marker3HostId,
         angle1Line1HostId, angle1Line2HostId,
         angle2Line1HostId, angle2Line2HostId,
         angle3Line1HostId, angle3Line2HostId
        ])

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.set_point_position(
        state_ptr, angle1Line1Joint1Id, Angle1JointPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, angle1Line1Joint2Id, Angle1JointPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, angle1Line2Joint1Id, Angle1JointPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, angle1Line2Joint2Id, Angle1JointPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, angle2Line1Joint1Id, Angle2JointPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, angle2Line1Joint2Id, Angle2JointPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, angle2Line2Joint1Id, Angle2JointPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, angle2Line2Joint2Id, Angle2JointPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, angle3Line1Joint1Id, Angle3JointPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, angle3Line1Joint2Id, Angle3JointPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, angle3Line2Joint1Id, Angle3JointPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, angle3Line2Joint2Id, Angle3JointPoint)

    OdinJuliaBridge.hide_compass(state_ptr)
    OdinJuliaBridge.lock_compass_joint1(
        state_ptr, Angle1JointPoint[1], Angle1JointPoint[2], CompassTopZ)
    OdinJuliaBridge.lock_compass_joint2(
        state_ptr, Marker1Start[1], Marker1Start[2], CompassTopZ)
    OdinJuliaBridge.set_point_position(
        state_ptr, marker1HostId, Angle1JointPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, marker1StartId, Marker1Start)
    OdinJuliaBridge.set_point_position(
        state_ptr, marker1EndId, Marker1Start)
    OdinJuliaBridge.set_point_position(
        state_ptr, marker2HostId, Angle2JointPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, marker2StartId, Marker2Start)
    OdinJuliaBridge.set_point_position(
        state_ptr, marker2EndId, Marker2Start)
    OdinJuliaBridge.set_point_position(
        state_ptr, marker3HostId, Angle3JointPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, marker3StartId, Marker3Start)
    OdinJuliaBridge.set_point_position(
        state_ptr, marker3EndId, Marker3Start)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

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
    angle1Line1 = OdinJuliaBridge.create_new_line(
        state_ptr, Angle1JointPoint, Angle1JointPoint,
        Angle1LineColor, 0f0)
    angle1Line2 = OdinJuliaBridge.create_new_line(
        state_ptr, Angle1JointPoint, Angle1JointPoint,
        Angle1LineColor, 0f0)
    angle2Line1 = OdinJuliaBridge.create_new_line(
        state_ptr, Angle2JointPoint, Angle2JointPoint,
        Angle2LineColor, 0f0)
    angle2Line2 = OdinJuliaBridge.create_new_line(
        state_ptr, Angle2JointPoint, Angle2JointPoint,
        Angle2LineColor, 0f0)
    angle3Line1 = OdinJuliaBridge.create_new_line(
        state_ptr, Angle3JointPoint, Angle3JointPoint,
        Angle2LineColor, 0f0)
    angle3Line2 = OdinJuliaBridge.create_new_line(
        state_ptr, Angle3JointPoint, Angle3JointPoint,
        Angle3LineColor, 0f0)


    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker1HostId, Float32(marker1.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker1StartId, Float32(marker1.startId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker1EndId, Float32(marker1.endId))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker2HostId, Float32(marker2.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker2StartId, Float32(marker2.startId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker2EndId, Float32(marker2.endId))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker3HostId, Float32(marker3.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker3StartId, Float32(marker3.startId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker3EndId, Float32(marker3.endId))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaAngle1Line1HostId, Float32(angle1Line1.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaAngle1Line1Joint1Id, Float32(angle1Line1.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaAngle1Line1Joint2Id, Float32(angle1Line1.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaAngle1Line2HostId, Float32(angle1Line2.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaAngle1Line2Joint1Id, Float32(angle1Line2.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaAngle1Line2Joint2Id, Float32(angle1Line2.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaAngle2Line1HostId, Float32(angle2Line1.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaAngle2Line1Joint1Id, Float32(angle2Line1.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaAngle2Line1Joint2Id, Float32(angle2Line1.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaAngle2Line2HostId, Float32(angle2Line2.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaAngle2Line2Joint1Id, Float32(angle2Line2.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaAngle2Line2Joint2Id, Float32(angle2Line2.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaAngle3Line1HostId, Float32(angle3Line1.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaAngle3Line1Joint1Id, Float32(angle3Line1.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaAngle3Line1Joint2Id, Float32(angle3Line1.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaAngle3Line2HostId, Float32(angle3Line2.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaAngle3Line2Joint1Id, Float32(angle3Line2.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaAngle3Line2Joint2Id, Float32(angle3Line2.joint2Id))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    angle1Line1HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAngle1Line1HostId))
    angle1Line1Joint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAngle1Line1Joint1Id))
    angle1Line1Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAngle1Line1Joint2Id))
    angle1Line2HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAngle1Line2HostId))
    angle1Line2Joint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAngle1Line2Joint1Id))
    angle1Line2Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAngle1Line2Joint2Id))

    angle2Line1HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAngle2Line1HostId))
    angle2Line1Joint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAngle2Line1Joint1Id))
    angle2Line1Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAngle2Line1Joint2Id))
    angle2Line2HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAngle2Line2HostId))
    angle2Line2Joint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAngle2Line2Joint1Id))
    angle2Line2Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAngle2Line2Joint2Id))

    angle3Line1HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAngle3Line1HostId))
    angle3Line1Joint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAngle3Line1Joint1Id))
    angle3Line1Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAngle3Line1Joint2Id))
    angle3Line2HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAngle3Line2HostId))
    angle3Line2Joint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAngle3Line2Joint1Id))
    angle3Line2Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAngle3Line2Joint2Id))

    marker1HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker1HostId))
    marker1StartId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker1StartId))
    marker1EndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker1EndId))

    marker2HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker2HostId))
    marker2StartId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker2StartId))
    marker2EndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker2EndId))

    marker3HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker3HostId))
    marker3StartId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker3StartId))
    marker3EndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker3EndId))

    if angle1Line1HostId < 0 || angle1Line2HostId < 0 ||
        angle2Line1HostId < 0 || angle2Line2HostId < 0 ||
        angle3Line1HostId < 0 || angle3Line2HostId < 0 ||
        marker1HostId < 0 || marker1HostId < 0 ||
        marker2HostId < 0 || marker2HostId < 0 ||
        marker3HostId < 0 || marker3HostId < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, PenDescendDuration, PenTopZ, Angle1JointPoint[1], Angle1JointPoint[2])

        timer += dt
        if timer >= PenDescendDuration
            phase = PhaseDrawLine
            timer = 0f0
        end
    elseif phase == PhaseDrawLine
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, LineDrawDuration, Angle1JointPoint, Angle1End1Point,
            LineMaxBrush, Angle1LineColor, angle1Line1HostId, angle1Line1Joint1Id, angle1Line1Joint2Id)

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
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, LineDrawDuration, Angle1JointPoint, Angle1End2Point,
            LineMaxBrush, Angle1LineColor, angle1Line2HostId, angle1Line2Joint1Id, angle1Line2Joint2Id)

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
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, LineDrawDuration, Angle2JointPoint, Angle2End1Point,
            LineMaxBrush, Angle2LineColor, angle2Line1HostId, angle2Line1Joint1Id, angle2Line1Joint2Id)

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
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, LineDrawDuration, Angle2JointPoint, Angle2End2Point,
            LineMaxBrush, Angle2LineColor, angle2Line2HostId, angle2Line2Joint1Id, angle2Line2Joint2Id)

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
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, LineDrawDuration, Angle3JointPoint, Angle3End1Point,
            LineMaxBrush, Angle3LineColor, angle3Line1HostId, angle3Line1Joint1Id, angle3Line1Joint2Id)

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
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, LineDrawDuration, Angle3JointPoint, Angle3End2Point,
            LineMaxBrush, Angle3LineColor, angle3Line2HostId, angle3Line2Joint1Id, angle3Line2Joint2Id)

        timer += dt
        if timer >= LineDrawDuration
            phase = PhasePenLift
            timer = 0f0
        end
    elseif phase == PhasePenLift
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenRiseDuration, PenTopZ, Angle3End2Point[1], Angle3End2Point[2])

        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, PenRiseDuration, CompassTopZ,
            Angle1JointPoint[1], Angle1JointPoint[2], Marker1Start[1], Marker1Start[2])

        timer += dt
        if timer >= PenRiseDuration
            phase = PhaseDrawMarker1
            timer = 0f0
        end
    elseif phase == PhaseDrawMarker1
        EuclidAnimations.animate_draw_circle(
            state_ptr, timer, MarkerDrawDuration, Angle1JointPoint, Marker1Start,
            π/2f0, MarkerRadius, MarkerBrush, MarkerColor,
            marker1HostId, marker1StartId, marker1EndId)

        timer += dt
        if timer >= MarkerDrawDuration
            phase = PhaseCompassArcToMarker2
            timer = 0f0
        end
    elseif phase == PhaseCompassArcToMarker2
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, CompassArcMoveDuration,
            Angle1JointPoint, Angle2JointPoint, Marker1End, Marker2Start,
            CompassArcMoveHeight, 1, :none)

        timer += dt
        if timer >= CompassArcMoveDuration
            phase = PhaseDrawMarker2
            timer = 0f0
        end
    elseif phase == PhaseDrawMarker2
        EuclidAnimations.animate_draw_circle(
            state_ptr, timer, MarkerDrawDuration, Angle2JointPoint, Marker2Start,
            π/2f0, MarkerRadius, MarkerBrush, MarkerColor,
            marker2HostId, marker2StartId, marker2EndId)

        timer += dt
        if timer >= MarkerDrawDuration
            phase = PhaseCompassArcToMarker3
            timer = 0f0
        end
    elseif phase == PhaseCompassArcToMarker3
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, CompassArcMoveDuration,
            Angle2JointPoint, Angle3JointPoint, Marker2End, Marker3Start,
            CompassArcMoveHeight, 1, :none)

        timer += dt
        if timer >= CompassArcMoveDuration
            phase = PhaseDrawMarker3
            timer = 0f0
        end
    elseif phase == PhaseDrawMarker3
        EuclidAnimations.animate_draw_circle(
            state_ptr, timer, MarkerDrawDuration, Angle3JointPoint, Marker3Start,
            π/2f0, MarkerRadius, MarkerBrush, MarkerColor,
            marker3HostId, marker3StartId, marker3EndId)

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
        newAngle2Joint = Angle2JointPoint + movvec * t

        newθ = Angle2StartΘ + (2f0π - Angle2StartΘ) * t
        angle2End1Point = newAngle2Joint +
            [LineLength * cos(newθ), LineLength * sin(newθ), 0f0]
        angle2End2Point = newAngle2Joint +
            [LineLength * cos(newθ + π/2f0), LineLength * sin(newθ + π/2f0), 0f0]

        marker2Start = newAngle2Joint +
            [MarkerRadius * cos(newθ), MarkerRadius * sin(newθ), 0f0]
        marker2End = newAngle2Joint +
            [MarkerRadius * cos(newθ + π/2f0), MarkerRadius * sin(newθ + π/2f0), 0f0]

        OdinJuliaBridge.set_point_position(
            state_ptr, angle2Line1Joint1Id, newAngle2Joint)
        OdinJuliaBridge.set_point_position(
            state_ptr, angle2Line1Joint2Id, angle2End1Point)
        OdinJuliaBridge.set_point_position(
            state_ptr, angle2Line2Joint1Id, newAngle2Joint)
        OdinJuliaBridge.set_point_position(
            state_ptr, angle2Line2Joint2Id, angle2End2Point)
        OdinJuliaBridge.set_point_position(
            state_ptr, marker2HostId, newAngle2Joint)
        OdinJuliaBridge.set_point_position(
            state_ptr, marker2StartId, marker2Start)
        OdinJuliaBridge.set_point_position(
            state_ptr, marker2EndId, marker2End)
        
        timer += dt
        if timer >= MoveAngleDuration
            OdinJuliaBridge.hide_compass(state_ptr)
            phase = PhaseMoveAngle3
            timer = 0f0
        end
    elseif phase == PhaseMoveAngle3
        t = clamp(timer / MoveAngleDuration, 0f0, 1f0)
        
        movvec = Angle1JointPoint - Angle3JointPoint
        newAngle3Joint = Angle3JointPoint + movvec * t

        newθ = Angle3StartΘ + (2f0π - Angle3StartΘ) * t
        angle3End1Point = newAngle3Joint +
            [LineLength * cos(newθ), LineLength * sin(newθ), 0f0]
        angle3End2Point = newAngle3Joint +
            [LineLength * cos(newθ + π/2f0), LineLength * sin(newθ + π/2f0), 0f0]

        marker3Start = newAngle3Joint +
            [MarkerRadius * cos(newθ), MarkerRadius * sin(newθ), 0f0]
        marker3End = newAngle3Joint +
            [MarkerRadius * cos(newθ + π/2f0), MarkerRadius * sin(newθ + π/2f0), 0f0]

        OdinJuliaBridge.set_point_position(
            state_ptr, angle3Line1Joint1Id, newAngle3Joint)
        OdinJuliaBridge.set_point_position(
            state_ptr, angle3Line1Joint2Id, angle3End1Point)
        OdinJuliaBridge.set_point_position(
            state_ptr, angle3Line2Joint1Id, newAngle3Joint)
        OdinJuliaBridge.set_point_position(
            state_ptr, angle3Line2Joint2Id, angle3End2Point)
        OdinJuliaBridge.set_point_position(
            state_ptr, marker3HostId, newAngle3Joint)
        OdinJuliaBridge.set_point_position(
            state_ptr, marker3StartId, marker3Start)
        OdinJuliaBridge.set_point_position(
            state_ptr, marker3EndId, marker3End)

        timer += dt
        if timer >= MoveAngleDuration
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

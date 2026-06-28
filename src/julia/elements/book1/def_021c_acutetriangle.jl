module ElementsOneDefinitionAcuteTriangle

using ..OdinJuliaBridge
using ..EuclidAnimations

using LinearAlgebra

export get_view_text, initialize, clean, loop

const VertexA = [0.08f0, 0.22f0, 0f0]
const VertexB = [0.50f0, 0.90f0, 0f0]
const VertexC = [0.92f0, 0.28f0, 0f0]

const MarkerRadius = 0.175f0

const Marker1Center = [VertexA[1], VertexA[2], 0f0]
const Marker1Vec1 = normalize(Float32[VertexB[1] - VertexA[1], VertexB[2] - VertexA[2]])
const Marker1Vec2 = normalize(Float32[VertexC[1] - VertexA[1], VertexC[2] - VertexA[2]])
const Marker1Cross = Marker1Vec1[1] * Marker1Vec2[2] - Marker1Vec1[2] * Marker1Vec2[1]
const Marker1StartVec = Marker1Cross >= 0f0 ? Marker1Vec1 : Marker1Vec2
const Marker1Start = [
    Marker1Center[1] + MarkerRadius * Marker1StartVec[1],
    Marker1Center[2] + MarkerRadius * Marker1StartVec[2],
    0f0,
]
const Marker1StartTheta = Float32(atan(Marker1StartVec[2], Marker1StartVec[1]))
const Marker1SweepTheta = Float32(acos(clamp(dot(Marker1Vec1, Marker1Vec2), -1f0, 1f0)))
const Marker1EndTheta = Marker1StartTheta + Marker1SweepTheta
const Marker1End = [
    Marker1Center[1] + MarkerRadius * Float32(cos(Marker1EndTheta)),
    Marker1Center[2] + MarkerRadius * Float32(sin(Marker1EndTheta)),
    0f0,
]

const Marker2Center = [VertexB[1], VertexB[2], 0f0]
const Marker2Vec1 = normalize(Float32[VertexA[1] - VertexB[1], VertexA[2] - VertexB[2]])
const Marker2Vec2 = normalize(Float32[VertexC[1] - VertexB[1], VertexC[2] - VertexB[2]])
const Marker2Cross = Marker2Vec1[1] * Marker2Vec2[2] - Marker2Vec1[2] * Marker2Vec2[1]
const Marker2StartVec = Marker2Cross >= 0f0 ? Marker2Vec1 : Marker2Vec2
const Marker2Start = [
    Marker2Center[1] + MarkerRadius * Marker2StartVec[1],
    Marker2Center[2] + MarkerRadius * Marker2StartVec[2],
    0f0,
]
const Marker2StartTheta = Float32(atan(Marker2StartVec[2], Marker2StartVec[1]))
const Marker2SweepTheta = Float32(acos(clamp(dot(Marker2Vec1, Marker2Vec2), -1f0, 1f0)))
const Marker2EndTheta = Marker2StartTheta + Marker2SweepTheta
const Marker2End = [
    Marker2Center[1] + MarkerRadius * Float32(cos(Marker2EndTheta)),
    Marker2Center[2] + MarkerRadius * Float32(sin(Marker2EndTheta)),
    0f0,
]

const Marker3Center = [VertexC[1], VertexC[2], 0f0]
const Marker3Vec1 = normalize(Float32[VertexB[1] - VertexC[1], VertexB[2] - VertexC[2]])
const Marker3Vec2 = normalize(Float32[VertexA[1] - VertexC[1], VertexA[2] - VertexC[2]])
const Marker3Cross = Marker3Vec1[1] * Marker3Vec2[2] - Marker3Vec1[2] * Marker3Vec2[1]
const Marker3StartVec = Marker3Cross >= 0f0 ? Marker3Vec1 : Marker3Vec2
const Marker3Start = [
    Marker3Center[1] + MarkerRadius * Marker3StartVec[1],
    Marker3Center[2] + MarkerRadius * Marker3StartVec[2],
    0f0,
]
const Marker3StartTheta = Float32(atan(Marker3StartVec[2], Marker3StartVec[1]))
const Marker3SweepTheta = Float32(acos(clamp(dot(Marker3Vec1, Marker3Vec2), -1f0, 1f0)))
const Marker3EndTheta = Marker3StartTheta + Marker3SweepTheta
const Marker3End = [
    Marker3Center[1] + MarkerRadius * Float32(cos(Marker3EndTheta)),
    Marker3Center[2] + MarkerRadius * Float32(sin(Marker3EndTheta)),
    0f0,
]

const PenTopZ = 1.4f0
const CompassTopZ = 1.4f0

const SideColor = :palevioletred1
const MarkerColor = :steelblue
const TriangleMaxBrush = 5f0
const MarkerBrush = 5f0

const PenDescendDuration = 1.8f0
const DrawDuration = 3.1f0
const PenRiseDuration = 1.8f0
const CompassDescendDuration = 1.8f0
const MarkerDrawDuration = 1f0
const CompassArcMoveDuration = 1.6f0
const CompassArcMoveHeight = 0.25f0
const CompassRiseDuration = 2.0f0
const HidePauseDuration = 1.5f0

const MetaLine1HostId = 1
const MetaLine1Joint1Id = 2
const MetaLine1Joint2Id = 3
const MetaLine2HostId = 4
const MetaLine2Joint1Id = 5
const MetaLine2Joint2Id = 6
const MetaLine3HostId = 7
const MetaLine3Joint1Id = 8
const MetaLine3Joint2Id = 9
const MetaMarker1HostId = 10
const MetaMarker1StartId = 11
const MetaMarker1EndId = 12
const MetaMarker2HostId = 13
const MetaMarker2StartId = 14
const MetaMarker2EndId = 15
const MetaMarker3HostId = 16
const MetaMarker3StartId = 17
const MetaMarker3EndId = 18
const MetaPhase = 19
const MetaTimer = 20

const PhaseDescend = 0f0
const PhaseDrawSide1 = 1f0
const PhaseDrawSide2 = 2f0
const PhaseDrawSide3 = 3f0
const PhasePenRise = 4f0
const PhaseCompassDescend = 5f0
const PhaseDrawMarker1 = 6f0
const PhaseCompassArcToMarker2 = 7f0
const PhaseDrawMarker2 = 8f0
const PhaseCompassArcToMarker3 = 9f0
const PhaseDrawMarker3 = 10f0
const PhaseCompassRise = 11f0
const PhaseHideAll = 12f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """Euclid Elements - Book I - Definition: Acute-Angled Triangle

Further, of trilateral figures, ... an acute-angled triangle that which has its three angles acute."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    line1HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine1HostId))
    line1Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine1Joint2Id))

    line2HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine2HostId))
    line2Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine2Joint2Id))

    line3HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine3HostId))
    line3Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine3Joint2Id))

    marker1HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker1HostId))
    marker1EndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker1EndId))

    marker2HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker2HostId))
    marker2EndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker2EndId))

    marker3HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker3HostId))
    marker3EndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker3EndId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [marker1HostId, marker2HostId, marker3HostId, line1HostId, line2HostId, line3HostId])

    OdinJuliaBridge.set_point_position(
        state_ptr, line1Joint2Id, VertexA[1], VertexA[2], VertexA[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, line2Joint2Id, VertexB[1], VertexB[2], VertexB[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, line3Joint2Id, VertexC[1], VertexC[2], VertexC[3])

    OdinJuliaBridge.set_point_position(
        state_ptr, marker1EndId, Marker1Start[1], Marker1Start[2], Marker1Start[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, marker2EndId, Marker2Start[1], Marker2Start[2], Marker2Start[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, marker3EndId, Marker3Start[1], Marker3Start[2], Marker3Start[3])

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.hide_compass(state_ptr)

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, SideColor)
    OdinJuliaBridge.set_compass_active(state_ptr, 0, MarkerColor)
    OdinJuliaBridge.lock_compass_joint1(
        state_ptr, Marker1Center[1], Marker1Center[2], CompassTopZ)
    OdinJuliaBridge.lock_compass_joint2(
        state_ptr, Marker1Start[1], Marker1Start[2], CompassTopZ)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    marker1 = OdinJuliaBridge.create_new_filledcircle(
        state_ptr,
        Marker1Center[1], Marker1Center[2], Marker1Center[3],
        MarkerRadius, Marker1StartTheta, Marker1StartTheta,
        MarkerColor, 0f0)
    marker2 = OdinJuliaBridge.create_new_filledcircle(
        state_ptr,
        Marker2Center[1], Marker2Center[2], Marker2Center[3],
        MarkerRadius, Marker2StartTheta, Marker2StartTheta,
        MarkerColor, 0f0)
    marker3 = OdinJuliaBridge.create_new_filledcircle(
        state_ptr,
        Marker3Center[1], Marker3Center[2], Marker3Center[3],
        MarkerRadius, Marker3StartTheta, Marker3StartTheta,
        MarkerColor, 0f0)
    line1 = OdinJuliaBridge.create_new_line(
        state_ptr,
        VertexA[1], VertexA[2], VertexA[3],
        VertexA[1], VertexA[2], VertexA[3],
        SideColor, 0f0)
    line2 = OdinJuliaBridge.create_new_line(
        state_ptr,
        VertexB[1], VertexB[2], VertexB[3],
        VertexB[1], VertexB[2], VertexB[3],
        SideColor, 0f0)
    line3 = OdinJuliaBridge.create_new_line(
        state_ptr,
        VertexC[1], VertexC[2], VertexC[3],
        VertexC[1], VertexC[2], VertexC[3],
        SideColor, 0f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine1HostId, Float32(line1.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine1Joint1Id, Float32(line1.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine1Joint2Id, Float32(line1.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine2HostId, Float32(line2.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine2Joint1Id, Float32(line2.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine2Joint2Id, Float32(line2.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine3HostId, Float32(line3.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine3Joint1Id, Float32(line3.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine3Joint2Id, Float32(line3.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker1HostId, Float32(marker1.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker1StartId, Float32(marker1.startId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker1EndId, Float32(marker1.endId))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker2HostId, Float32(marker2.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker2StartId, Float32(marker2.startId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker2EndId, Float32(marker2.endId))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker3HostId, Float32(marker3.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker3StartId, Float32(marker3.startId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker3EndId, Float32(marker3.endId))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    line1HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine1HostId))
    line1Joint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine1Joint1Id))
    line1Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine1Joint2Id))

    line2HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine2HostId))
    line2Joint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine2Joint1Id))
    line2Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine2Joint2Id))

    line3HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine3HostId))
    line3Joint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine3Joint1Id))
    line3Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine3Joint2Id))

    marker1HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker1HostId))
    marker1StartId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker1StartId))
    marker1EndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker1EndId))

    marker2HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker2HostId))
    marker2StartId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker2StartId))
    marker2EndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker2EndId))

    marker3HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker3HostId))
    marker3StartId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker3StartId))
    marker3EndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker3EndId))

    if line1HostId < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, PenDescendDuration, PenTopZ, VertexA[1], VertexA[2])

        timer += dt
        if timer >= PenDescendDuration
            phase = PhaseDrawSide1
            timer = 0f0
        end
    elseif phase == PhaseDrawSide1
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawDuration, VertexA, VertexB,
            TriangleMaxBrush, SideColor, line1HostId, line1Joint1Id, line1Joint2Id)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseDrawSide2
            timer = 0f0
        end
    elseif phase == PhaseDrawSide2
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawDuration, VertexB, VertexC,
            TriangleMaxBrush, SideColor, line2HostId, line2Joint1Id, line2Joint2Id)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseDrawSide3
            timer = 0f0
        end
    elseif phase == PhaseDrawSide3
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawDuration, VertexC, VertexA,
            TriangleMaxBrush, SideColor, line3HostId, line3Joint1Id, line3Joint2Id)

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
            Marker1Center[1], Marker1Center[2], Marker1Start[1], Marker1Start[2])

        timer += dt
        if timer >= CompassDescendDuration
            phase = PhaseDrawMarker1
            timer = 0f0
        end
    elseif phase == PhaseDrawMarker1
        EuclidAnimations.animate_draw_filledcircle(
            state_ptr, timer, MarkerDrawDuration, Marker1Center, Marker1Start,
            Marker1SweepTheta, MarkerRadius, MarkerBrush, MarkerColor,
            marker1HostId, marker1StartId, marker1EndId)

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
            Marker2SweepTheta, MarkerRadius, MarkerBrush, MarkerColor,
            marker2HostId, marker2StartId, marker2EndId)

        timer += dt
        if timer >= MarkerDrawDuration
            phase = PhaseCompassArcToMarker3
            timer = 0f0
        end
    elseif phase == PhaseCompassArcToMarker3
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, CompassArcMoveDuration,
            Marker2Center, Marker3Center, Marker2End, Marker3Start,
            CompassArcMoveHeight, 1, :none)

        timer += dt
        if timer >= CompassArcMoveDuration
            phase = PhaseDrawMarker3
            timer = 0f0
        end
    elseif phase == PhaseDrawMarker3
        EuclidAnimations.animate_draw_filledcircle(
            state_ptr, timer, MarkerDrawDuration, Marker3Center, Marker3Start,
            Marker3SweepTheta, MarkerRadius, MarkerBrush, MarkerColor,
            marker3HostId, marker3StartId, marker3EndId)

        timer += dt
        if timer >= MarkerDrawDuration
            phase = PhaseCompassRise
            timer = 0f0
        end
    elseif phase == PhaseCompassRise
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassRiseDuration, CompassTopZ,
            Marker3Center[1], Marker3Center[2], Marker3End[1], Marker3End[2])

        timer += dt
        if timer >= CompassRiseDuration
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

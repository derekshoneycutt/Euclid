module ElementsOneDefinitionRightTriangle

using ..EuclidBridge
using ..EuclidAnimations

using LinearAlgebra

export get_view_text, initialize, clean, loop

const VertexA = [0.30f0, 0.22f0, 0f0]
const VertexB = [0.30f0, 0.78f0, 0f0]
const VertexC = [0.88f0, 0.78f0, 0f0]

const MarkerCenter = [VertexB[1], VertexB[2], 0f0]
const MarkerRadius = 0.175f0
const MarkerStart = [MarkerCenter[1], MarkerCenter[2] - MarkerRadius, 0f0]
const MarkerSweepTheta = Float32(π / 2f0)

const PenTopZ = 1.4f0
const CompassTopZ = 1.4f0

const LegColor = :palevioletred1
const HypotenuseColor = :khaki3
const MarkerColor = :steelblue
const TriangleMaxBrush = 5f0
const MarkerBrush = 5f0

const PenDescendDuration = 1.8f0
const DrawDuration = 3.1f0
const PenRiseDuration = 1.8f0
const CompassDescendDuration = 1.8f0
const MarkerDrawDuration = 2.2f0
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
const MetaMarkerHostId = 10
const MetaMarkerStartId = 11
const MetaMarkerEndId = 12
const MetaPhase = 13
const MetaTimer = 14

const PhaseDescend = 0f0
const PhaseDrawSide1 = 1f0
const PhaseDrawSide2 = 2f0
const PhaseDrawSide3 = 3f0
const PhasePenRise = 4f0
const PhaseCompassDescend = 5f0
const PhaseDrawMarker = 6f0
const PhaseCompassRise = 7f0
const PhaseHideAll = 8f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """Euclid Elements - Book I - Definition: Right-Angled Triangle

Further, of trilateral figures, a right-angled triangle is that which has a right angle, ..."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    line1HostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine1HostId))
    line1Joint2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine1Joint2Id))

    line2HostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine2HostId))
    line2Joint2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine2Joint2Id))

    line3HostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine3HostId))
    line3Joint2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine3Joint2Id))

    markerHostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaMarkerHostId))
    markerEndId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaMarkerEndId))

    EuclidBridge.hide_point(state_ptr, line1HostId)
    EuclidBridge.hide_point(state_ptr, line2HostId)
    EuclidBridge.hide_point(state_ptr, line3HostId)
    EuclidBridge.hide_point(state_ptr, markerHostId)

    EuclidBridge.set_point_position(
        state_ptr, line1Joint2Id, VertexA[1], VertexA[2], VertexA[3])
    EuclidBridge.set_point_position(
        state_ptr, line2Joint2Id, VertexB[1], VertexB[2], VertexB[3])
    EuclidBridge.set_point_position(
        state_ptr, line3Joint2Id, VertexC[1], VertexC[2], VertexC[3])

    EuclidBridge.set_point_position(
        state_ptr, markerEndId, MarkerStart[1], MarkerStart[2], MarkerStart[3])

    EuclidBridge.hide_pen(state_ptr)
    EuclidBridge.hide_compass(state_ptr)

    EuclidBridge.show_pen(state_ptr)
    EuclidBridge.set_pen_active(state_ptr, 0, LegColor)
    EuclidBridge.set_compass_active(state_ptr, 0, MarkerColor)
    EuclidBridge.lock_compass_joint1(
        state_ptr, MarkerCenter[1], MarkerCenter[2], CompassTopZ)
    EuclidBridge.lock_compass_joint2(
        state_ptr, MarkerStart[1], MarkerStart[2], CompassTopZ)

    EuclidBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    EuclidBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)
end

function initialize(state_ptr::Ptr{Cvoid})
    marker = EuclidBridge.create_new_circle(
        state_ptr, MarkerCenter, MarkerRadius, 3f0 * π / 2f0, 3f0 * π / 2f0, MarkerColor, 0f0)
    line1 = EuclidBridge.create_new_line(
        state_ptr,
        VertexA[1], VertexA[2], VertexA[3],
        VertexA[1], VertexA[2], VertexA[3],
        LegColor, 0f0)
    line2 = EuclidBridge.create_new_line(
        state_ptr,
        VertexB[1], VertexB[2], VertexB[3],
        VertexB[1], VertexB[2], VertexB[3],
        LegColor, 0f0)
    line3 = EuclidBridge.create_new_line(
        state_ptr,
        VertexC[1], VertexC[2], VertexC[3],
        VertexC[1], VertexC[2], VertexC[3],
        HypotenuseColor, 0f0)

    EuclidBridge.set_animation_meta(state_ptr, MetaLine1HostId, Float32(line1.hostId))
    EuclidBridge.set_animation_meta(state_ptr, MetaLine1Joint1Id, Float32(line1.joint1Id))
    EuclidBridge.set_animation_meta(state_ptr, MetaLine1Joint2Id, Float32(line1.joint2Id))

    EuclidBridge.set_animation_meta(state_ptr, MetaLine2HostId, Float32(line2.hostId))
    EuclidBridge.set_animation_meta(state_ptr, MetaLine2Joint1Id, Float32(line2.joint1Id))
    EuclidBridge.set_animation_meta(state_ptr, MetaLine2Joint2Id, Float32(line2.joint2Id))

    EuclidBridge.set_animation_meta(state_ptr, MetaLine3HostId, Float32(line3.hostId))
    EuclidBridge.set_animation_meta(state_ptr, MetaLine3Joint1Id, Float32(line3.joint1Id))
    EuclidBridge.set_animation_meta(state_ptr, MetaLine3Joint2Id, Float32(line3.joint2Id))

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

    line3HostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine3HostId))
    line3Joint1Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine3Joint1Id))
    line3Joint2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine3Joint2Id))

    markerHostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaMarkerHostId))
    markerStartId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaMarkerStartId))
    markerEndId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaMarkerEndId))

    if line1HostId < 0
        return
    end

    phase = EuclidBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = EuclidBridge.get_animation_meta(state_ptr, MetaTimer)

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
            TriangleMaxBrush, LegColor, line1HostId, line1Joint1Id, line1Joint2Id)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseDrawSide2
            timer = 0f0
        end
    elseif phase == PhaseDrawSide2
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawDuration, VertexB, VertexC,
            TriangleMaxBrush, LegColor, line2HostId, line2Joint1Id, line2Joint2Id)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseDrawSide3
            timer = 0f0
        end
    elseif phase == PhaseDrawSide3
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawDuration, VertexC, VertexA,
            TriangleMaxBrush, HypotenuseColor, line3HostId, line3Joint1Id, line3Joint2Id)

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
            EuclidBridge.hide_pen(state_ptr)
            phase = PhaseCompassDescend
            timer = 0f0
        end
    elseif phase == PhaseCompassDescend
        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, CompassDescendDuration, CompassTopZ,
            MarkerCenter[1], MarkerCenter[2], MarkerStart[1], MarkerStart[2])

        timer += dt
        if timer >= CompassDescendDuration
            phase = PhaseDrawMarker
            timer = 0f0
        end
    elseif phase == PhaseDrawMarker
        EuclidAnimations.animate_draw_circle(
            state_ptr, timer, MarkerDrawDuration, MarkerCenter, MarkerStart,
            MarkerSweepTheta, MarkerRadius, MarkerBrush, MarkerColor,
            markerHostId, markerStartId, markerEndId)

        timer += dt
        if timer >= MarkerDrawDuration
            phase = PhaseCompassRise
            timer = 0f0
        end
    elseif phase == PhaseCompassRise
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassRiseDuration, CompassTopZ,
            MarkerCenter[1], MarkerCenter[2], MarkerStart[1], MarkerStart[2])

        timer += dt
        if timer >= CompassRiseDuration
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

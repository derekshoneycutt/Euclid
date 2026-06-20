module ElementsOneDefinitionRhombus

using ..EuclidBridge
using ..EuclidAnimations

using LinearAlgebra

export get_view_text, initialize, clean, loop

const VertexA = [0.16f0, 0.78f0, 0f0]
const VertexB = [0.58f0, 0.78f0, 0f0]
const VertexC = [0.79f0, 0.416f0, 0f0]
const VertexD = [0.37f0, 0.416f0, 0f0]

const SideStarts = (VertexA, VertexB, VertexC, VertexD)
const SideEnds = (VertexB, VertexC, VertexD, VertexA)
const SideColors = (:palevioletred1, :palevioletred1, :palevioletred1, :palevioletred1)

const MarkerRadius = 0.15f0
const MarkerCenters = (VertexA, VertexB, VertexC, VertexD)
const MarkerColors = (:steelblue, :khaki3, :steelblue, :khaki3)

function marker_geometry(prev::Vector{Float32}, curr::Vector{Float32}, nxt::Vector{Float32}, radius)
    v1 = normalize(Float32[prev[1] - curr[1], prev[2] - curr[2]])
    v2 = normalize(Float32[nxt[1] - curr[1], nxt[2] - curr[2]])
    cross = v1[1] * v2[2] - v1[2] * v2[1]
    startVec = cross >= 0f0 ? v1 : v2

    start = [
        curr[1] + radius * startVec[1],
        curr[2] + radius * startVec[2],
        0f0,
    ]

    startTheta = Float32(atan(startVec[2], startVec[1]))
    sweepTheta = Float32(acos(clamp(dot(v1, v2), -1f0, 1f0)))
    endTheta = startTheta + sweepTheta

    finish = [
        curr[1] + radius * Float32(cos(endTheta)),
        curr[2] + radius * Float32(sin(endTheta)),
        0f0,
    ]

    return start, sweepTheta, startTheta, finish
end

const MarkerGeom1 = marker_geometry(VertexD, VertexA, VertexB, MarkerRadius)
const MarkerGeom2 = marker_geometry(VertexA, VertexB, VertexC, MarkerRadius)
const MarkerGeom3 = marker_geometry(VertexB, VertexC, VertexD, MarkerRadius)
const MarkerGeom4 = marker_geometry(VertexC, VertexD, VertexA, MarkerRadius)

const MarkerStarts = (MarkerGeom1[1], MarkerGeom2[1], MarkerGeom3[1], MarkerGeom4[1])
const MarkerSweeps = (MarkerGeom1[2], MarkerGeom2[2], MarkerGeom3[2], MarkerGeom4[2])
const MarkerStartThetas = (MarkerGeom1[3], MarkerGeom2[3], MarkerGeom3[3], MarkerGeom4[3])
const MarkerEnds = (MarkerGeom1[4], MarkerGeom2[4], MarkerGeom3[4], MarkerGeom4[4])

const PenTopZ = 1.4f0
const CompassTopZ = 1.4f0

const TriangleMaxBrush = 5f0
const MarkerBrush = 5f0

const PenDescendDuration = 1.8f0
const DrawDuration = 2.6f0
const PenRiseDuration = 1.8f0
const CompassDescendDuration = 1.8f0
const MarkerDrawDuration = 1.0f0
const CompassArcMoveDuration = 1.5f0
const CompassArcMoveHeight = 0.25f0
const CompassRiseDuration = 2.0f0
const HidePauseDuration = 1.5f0

const MetaLineHostIds = (1, 4, 7, 10)
const MetaLineJoint1Ids = (2, 5, 8, 11)
const MetaLineJoint2Ids = (3, 6, 9, 12)

const MetaMarkerHostIds = (13, 16, 19, 22)
const MetaMarkerStartIds = (14, 17, 20, 23)
const MetaMarkerEndIds = (15, 18, 21, 24)

const MetaPhase = 25
const MetaTimer = 26

const PhaseDescend = 0f0
const PhaseDrawSide1 = 1f0
const PhaseDrawSide2 = 2f0
const PhaseDrawSide3 = 3f0
const PhaseDrawSide4 = 4f0
const PhasePenRise = 5f0
const PhaseCompassDescend = 6f0
const PhaseDrawMarker1 = 7f0
const PhaseCompassArcToMarker2 = 8f0
const PhaseDrawMarker2 = 9f0
const PhaseCompassArcToMarker3 = 10f0
const PhaseDrawMarker3 = 11f0
const PhaseCompassArcToMarker4 = 12f0
const PhaseDrawMarker4 = 13f0
const PhaseCompassRise = 14f0
const PhaseHideAll = 15f0

function get_view_text(state_ptr::Ptr{Cvoid})
    """Euclid Elements - Book I - Definition: Rhombus

Of quadrilateral figures, ... a rhombus that which is equilateral but not right angled; ..."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    for i in 1:4
        lineHostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLineHostIds[i]))
        lineJoint2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLineJoint2Ids[i]))

        markerHostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaMarkerHostIds[i]))
        markerEndId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaMarkerEndIds[i]))

        EuclidBridge.hide_point(state_ptr, lineHostId)
        EuclidBridge.hide_point(state_ptr, markerHostId)

        EuclidBridge.set_point_position(
            state_ptr, lineJoint2Id,
            SideStarts[i][1], SideStarts[i][2], SideStarts[i][3])

        EuclidBridge.set_point_position(
            state_ptr, markerEndId,
            MarkerStarts[i][1], MarkerStarts[i][2], MarkerStarts[i][3])
    end

    EuclidBridge.hide_pen(state_ptr)
    EuclidBridge.hide_compass(state_ptr)

    EuclidBridge.show_pen(state_ptr)
    EuclidBridge.set_pen_active(state_ptr, 0, SideColors[1])

    EuclidBridge.set_compass_active(state_ptr, 0, MarkerColors[1])
    EuclidBridge.lock_compass_joint1(
        state_ptr, MarkerCenters[1][1], MarkerCenters[1][2], CompassTopZ)
    EuclidBridge.lock_compass_joint2(
        state_ptr, MarkerStarts[1][1], MarkerStarts[1][2], CompassTopZ)

    EuclidBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    EuclidBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)
end

function initialize(state_ptr::Ptr{Cvoid})
    for i in 1:4
        marker = EuclidBridge.create_new_filledcircle(
            state_ptr,
            MarkerCenters[i][1], MarkerCenters[i][2], MarkerCenters[i][3],
            MarkerRadius, MarkerStartThetas[i], MarkerStartThetas[i],
            MarkerColors[i], 0f0)
        line = EuclidBridge.create_new_line(
            state_ptr,
            SideStarts[i][1], SideStarts[i][2], SideStarts[i][3],
            SideStarts[i][1], SideStarts[i][2], SideStarts[i][3],
            SideColors[i], 0f0)

        EuclidBridge.set_animation_meta(state_ptr, MetaLineHostIds[i], Float32(line.hostId))
        EuclidBridge.set_animation_meta(state_ptr, MetaLineJoint1Ids[i], Float32(line.joint1Id))
        EuclidBridge.set_animation_meta(state_ptr, MetaLineJoint2Ids[i], Float32(line.joint2Id))

        EuclidBridge.set_animation_meta(state_ptr, MetaMarkerHostIds[i], Float32(marker.hostId))
        EuclidBridge.set_animation_meta(state_ptr, MetaMarkerStartIds[i], Float32(marker.startId))
        EuclidBridge.set_animation_meta(state_ptr, MetaMarkerEndIds[i], Float32(marker.endId))
    end

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    line1HostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLineHostIds[1]))

    lineHostIds = ntuple(i -> Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLineHostIds[i])), 4)
    lineJoint1Ids = ntuple(i -> Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLineJoint1Ids[i])), 4)
    lineJoint2Ids = ntuple(i -> Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLineJoint2Ids[i])), 4)

    markerHostIds = ntuple(i -> Integer(EuclidBridge.get_animation_meta(state_ptr, MetaMarkerHostIds[i])), 4)
    markerStartIds = ntuple(i -> Integer(EuclidBridge.get_animation_meta(state_ptr, MetaMarkerStartIds[i])), 4)
    markerEndIds = ntuple(i -> Integer(EuclidBridge.get_animation_meta(state_ptr, MetaMarkerEndIds[i])), 4)

    if line1HostId < 0
        return
    end

    phase = EuclidBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = EuclidBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, PenDescendDuration, PenTopZ, SideStarts[1][1], SideStarts[1][2])

        timer += dt
        if timer >= PenDescendDuration
            phase = PhaseDrawSide1
            timer = 0f0
        end
    elseif phase == PhaseDrawSide1 || phase == PhaseDrawSide2 || phase == PhaseDrawSide3 || phase == PhaseDrawSide4
        sideIndex = Int(phase)
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawDuration, SideStarts[sideIndex], SideEnds[sideIndex],
            TriangleMaxBrush, SideColors[sideIndex],
            lineHostIds[sideIndex], lineJoint1Ids[sideIndex], lineJoint2Ids[sideIndex])

        timer += dt
        if timer >= DrawDuration
            if phase == PhaseDrawSide4
                phase = PhasePenRise
            else
                phase += 1f0
            end
            timer = 0f0
        end
    elseif phase == PhasePenRise
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenRiseDuration, PenTopZ, SideStarts[1][1], SideStarts[1][2])

        timer += dt
        if timer >= PenRiseDuration
            EuclidBridge.hide_pen(state_ptr)
            phase = PhaseCompassDescend
            timer = 0f0
        end
    elseif phase == PhaseCompassDescend
        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, CompassDescendDuration, CompassTopZ,
            MarkerCenters[1][1], MarkerCenters[1][2], MarkerStarts[1][1], MarkerStarts[1][2])

        timer += dt
        if timer >= CompassDescendDuration
            phase = PhaseDrawMarker1
            timer = 0f0
        end
    elseif phase == PhaseDrawMarker1 || phase == PhaseDrawMarker2 || phase == PhaseDrawMarker3 || phase == PhaseDrawMarker4
        markerIndex = Int((phase - PhaseDrawMarker1) / 2f0 + 1f0)
        EuclidAnimations.animate_draw_filledcircle(
            state_ptr, timer, MarkerDrawDuration, MarkerCenters[markerIndex], MarkerStarts[markerIndex],
            MarkerSweeps[markerIndex], MarkerRadius, MarkerBrush, MarkerColors[markerIndex],
            markerHostIds[markerIndex], markerStartIds[markerIndex], markerEndIds[markerIndex])

        timer += dt
        if timer >= MarkerDrawDuration
            if phase == PhaseDrawMarker1
                phase = PhaseCompassArcToMarker2
            elseif phase == PhaseDrawMarker2
                phase = PhaseCompassArcToMarker3
            elseif phase == PhaseDrawMarker3
                phase = PhaseCompassArcToMarker4
            else
                phase = PhaseCompassRise
            end
            timer = 0f0
        end
    elseif phase == PhaseCompassArcToMarker2 || phase == PhaseCompassArcToMarker3 || phase == PhaseCompassArcToMarker4
        fromIndex = Int((phase - PhaseCompassArcToMarker2) / 2f0 + 1f0)
        toIndex = fromIndex + 1

        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, CompassArcMoveDuration,
            MarkerCenters[fromIndex], MarkerCenters[toIndex], MarkerEnds[fromIndex], MarkerStarts[toIndex],
            CompassArcMoveHeight, 1, :none)

        timer += dt
        if timer >= CompassArcMoveDuration
            phase += 1f0
            timer = 0f0
        end
    elseif phase == PhaseCompassRise
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassRiseDuration, CompassTopZ,
            MarkerCenters[4][1], MarkerCenters[4][2], MarkerEnds[4][1], MarkerEnds[4][2])

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

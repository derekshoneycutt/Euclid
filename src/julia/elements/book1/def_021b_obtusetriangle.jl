module ElementsOneDefinitionObtuseTriangle

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

using LinearAlgebra

export get_view_text, initialize, clean, loop

const VertexA = [0.02f0, 0.22f0, 0f0]
const VertexB = [0.34f0, 0.74f0, 0f0]
const VertexC = [0.88f0, 0.86f0, 0f0]

const MarkerCenter = [VertexB[1], VertexB[2], 0f0]
const MarkerRadius = 0.1f0
const MarkerVec1 = normalize(Float32[VertexA[1] - VertexB[1], VertexA[2] - VertexB[2]])
const MarkerVec2 = normalize(Float32[VertexC[1] - VertexB[1], VertexC[2] - VertexB[2]])
const MarkerStart = [
    MarkerCenter[1] + MarkerRadius * MarkerVec1[1],
    MarkerCenter[2] + MarkerRadius * MarkerVec1[2],
    0f0,
]
const MarkerStartTheta = Float32(atan(MarkerVec1[2], MarkerVec1[1]))
const MarkerSweepTheta = Float32(acos(clamp(MarkerVec1 ⋅ MarkerVec2, -1f0, 1f0)))

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
    fallback = """Euclid Elements - Book I - Definition: Obtuse-Angled Triangle

Further, of trilateral figures, ... an obtuse-angled triangle that which has an obtuse angle, ..."""
    latex = raw"""\textbf{Euclid Elements - Book I - Definition}: \textit{Obtuse-Angled Triangle}

Further, of trilateral figures, ... an obtuse-angled triangle \euclidtriangle[height=2,width=3,thickness=2,edge1_color=palevioletred1,edge2_color=palevioletred1,edge3_color=khaki3] that which has an obtuse angle \euclidangle[color=steelblue,radius=2,end=120,filled], ..."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    line1_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine1HostId))
    line1_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine1Joint2Id))

    line2_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine2HostId))
    line2_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine2Joint2Id))

    line3_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine3HostId))
    line3_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine3Joint2Id))

    marker_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerHostId))
    marker_end_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerEndId))

    OdinJuliaBridge.hide_point_batch(state_ptr, [line1_host_id, line2_host_id, line3_host_id, marker_host_id])

    OdinJuliaBridge.set_point_position(
        state_ptr, line1_joint2_id, VertexA[1], VertexA[2], VertexA[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, line2_joint2_id, VertexB[1], VertexB[2], VertexB[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, line3_joint2_id, VertexC[1], VertexC[2], VertexC[3])

    OdinJuliaBridge.set_point_position(
        state_ptr, marker_end_id, MarkerStart[1], MarkerStart[2], MarkerStart[3])

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.hide_compass(state_ptr)

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, LegColor)
    OdinJuliaBridge.set_compass_active(state_ptr, 0, MarkerColor)
    OdinJuliaBridge.lock_compass_joint1(
        state_ptr, MarkerCenter[1], MarkerCenter[2], CompassTopZ)
    OdinJuliaBridge.lock_compass_joint2(
        state_ptr, MarkerStart[1], MarkerStart[2], CompassTopZ)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    marker = OdinJuliaBridge.create_new_filledcircle(
        state_ptr,
        MarkerCenter[1], MarkerCenter[2], MarkerCenter[3],
        MarkerRadius, MarkerStartTheta, MarkerStartTheta,
        MarkerColor, 0f0)
    line1 = OdinJuliaBridge.create_new_line(
        state_ptr,
        VertexA[1], VertexA[2], VertexA[3],
        VertexA[1], VertexA[2], VertexA[3],
        LegColor, 0f0)
    line2 = OdinJuliaBridge.create_new_line(
        state_ptr,
        VertexB[1], VertexB[2], VertexB[3],
        VertexB[1], VertexB[2], VertexB[3],
        LegColor, 0f0)
    line3 = OdinJuliaBridge.create_new_line(
        state_ptr,
        VertexC[1], VertexC[2], VertexC[3],
        VertexC[1], VertexC[2], VertexC[3],
        HypotenuseColor, 0f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine1HostId, Float32(line1.host_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine1Joint1Id, Float32(line1.joint1_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine1Joint2Id, Float32(line1.joint2_id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine2HostId, Float32(line2.host_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine2Joint1Id, Float32(line2.joint1_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine2Joint2Id, Float32(line2.joint2_id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine3HostId, Float32(line3.host_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine3Joint1Id, Float32(line3.joint1_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine3Joint2Id, Float32(line3.joint2_id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarkerHostId, Float32(marker.host_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarkerStartId, Float32(marker.start_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarkerEndId, Float32(marker.end_id))

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

    marker_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerHostId))
    marker_start_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerStartId))
    marker_end_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerEndId))

    if line1_host_id < 0
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
            TriangleMaxBrush, LegColor, line1_host_id, line1_joint1_id, line1_joint2_id)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseDrawSide2
            timer = 0f0
        end
    elseif phase == PhaseDrawSide2
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawDuration, VertexB, VertexC,
            TriangleMaxBrush, LegColor, line2_host_id, line2_joint1_id, line2_joint2_id)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseDrawSide3
            timer = 0f0
        end
    elseif phase == PhaseDrawSide3
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawDuration, VertexC, VertexA,
            TriangleMaxBrush, HypotenuseColor, line3_host_id, line3_joint1_id, line3_joint2_id)

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
            MarkerCenter[1], MarkerCenter[2], MarkerStart[1], MarkerStart[2])

        timer += dt
        if timer >= CompassDescendDuration
            phase = PhaseDrawMarker
            timer = 0f0
        end
    elseif phase == PhaseDrawMarker
        EuclidAnimations.animate_draw_filledcircle(
            state_ptr, timer, MarkerDrawDuration, MarkerCenter, MarkerStart,
            MarkerSweepTheta, MarkerRadius, MarkerBrush, MarkerColor,
            marker_host_id, marker_start_id, marker_end_id)

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

module ElementsOneDefinitionOblong

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex
using ..EuclidGeometry

using LinearAlgebra

export get_view_text, initialize, clean, loop

const VertexA = [0.19f0, 0.76f0, 0f0]
const VertexB = [0.81f0, 0.76f0, 0f0]
const VertexC = [0.81f0, 0.40f0, 0f0]
const VertexD = [0.19f0, 0.40f0, 0f0]

const SideStarts = (VertexA, VertexB, VertexC, VertexD)
const SideEnds = (VertexB, VertexC, VertexD, VertexA)
const SideColors = (:palevioletred1, :khaki3, :palevioletred1, :khaki3)

const MarkerRadius = 0.15f0
const MarkerCenters = (VertexA, VertexB, VertexC, VertexD)
const MarkerColors = (:steelblue, :steelblue, :steelblue, :steelblue)

const MarkerGeom1 =
    EuclidGeometry.marker_geometry(VertexD, VertexA, VertexB, MarkerRadius)
const MarkerGeom2 =
    EuclidGeometry.marker_geometry(VertexA, VertexB, VertexC, MarkerRadius)
const MarkerGeom3 =
    EuclidGeometry.marker_geometry(VertexB, VertexC, VertexD, MarkerRadius)
const MarkerGeom4 =
    EuclidGeometry.marker_geometry(VertexC, VertexD, VertexA, MarkerRadius)

const MarkerStarts = (
    MarkerGeom1.start, MarkerGeom2.start, MarkerGeom3.start, MarkerGeom4.start)
const MarkerSweeps = (
    MarkerGeom1.sweep_theta, MarkerGeom2.sweep_theta,
    MarkerGeom3.sweep_theta, MarkerGeom4.sweep_theta)
const MarkerStartThetas = (
    MarkerGeom1.start_theta, MarkerGeom2.start_theta,
    MarkerGeom3.start_theta, MarkerGeom4.start_theta)
const MarkerEnds = (
    MarkerGeom1.finish, MarkerGeom2.finish, MarkerGeom3.finish, MarkerGeom4.finish)

const PenTopZ = 1.4f0
const CompassTopZ = 1.4f0

const TriangleMaxBrush = 5f0
const MarkerBrush = 4f0

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
    fallback = """Euclid Elements - Book I - Definition: Oblong

Of quadrilateral figures, ... an oblong that which is right-angled but not equilateral; ..."""
    latex = raw"""\textbf{Euclid Elements - Book I - Definition}: \textit{Oblong}

Of quadrilateral figures, ... an oblong \euclidbox[height=2,width=3,thickness=2,edge1_color=khaki3,edge2_color=palevioletred1,edge3_color=khaki3,edge4_color=palevioletred1] that which is right-angled \euclidangle[color=steelblue,radius=2,thickness=2] but not equilateral \euclidline[color=palevioletred1,length=3,thickness=4] \euclidline[color=khaki3,length=3,thickness=4]; ..."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    lineHostIds_r = ntuple(i ->
        Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineHostIds[i])), 4)
    lineJoint2Ids_r = ntuple(i ->
        Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineJoint2Ids[i])), 4)
    markerHostIds_r = ntuple(i ->
        Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerHostIds[i])), 4)
    markerEndIds_r = ntuple(i ->
        Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerEndIds[i])), 4)

    OdinJuliaBridge.hide_point_batch(state_ptr, [markerHostIds_r..., lineHostIds_r...])

    for i in 1:4
        OdinJuliaBridge.set_point_position(
            state_ptr, lineJoint2Ids_r[i],
            SideStarts[i][1], SideStarts[i][2], SideStarts[i][3])

        OdinJuliaBridge.set_point_position(
            state_ptr, markerEndIds_r[i],
            MarkerStarts[i][1], MarkerStarts[i][2], MarkerStarts[i][3])
    end

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.hide_compass(state_ptr)

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, SideColors[1])

    OdinJuliaBridge.set_compass_active(state_ptr, 0, MarkerColors[1])
    OdinJuliaBridge.lock_compass_joint1(
        state_ptr, MarkerCenters[1][1], MarkerCenters[1][2], CompassTopZ)
    OdinJuliaBridge.lock_compass_joint2(
        state_ptr, MarkerStarts[1][1], MarkerStarts[1][2], CompassTopZ)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    for i in 1:4
        marker = OdinJuliaBridge.create_new_circle(
            state_ptr,
            MarkerCenters[i], MarkerRadius,
            MarkerStartThetas[i], MarkerStartThetas[i],
            MarkerColors[i], 0f0)

        OdinJuliaBridge.set_animation_meta(state_ptr,
            MetaMarkerHostIds[i], Float32(marker.host_id))
        OdinJuliaBridge.set_animation_meta(state_ptr,
            MetaMarkerStartIds[i], Float32(marker.start_id))
        OdinJuliaBridge.set_animation_meta(state_ptr,
            MetaMarkerEndIds[i], Float32(marker.end_id))
    end
    for i in 1:4
        line = OdinJuliaBridge.create_new_line(
            state_ptr,
            SideStarts[i][1], SideStarts[i][2], SideStarts[i][3],
            SideStarts[i][1], SideStarts[i][2], SideStarts[i][3],
            SideColors[i], 0f0)

        OdinJuliaBridge.set_animation_meta(state_ptr,
            MetaLineHostIds[i], Float32(line.host_id))
        OdinJuliaBridge.set_animation_meta(state_ptr,
            MetaLineJoint1Ids[i], Float32(line.joint1_id))
        OdinJuliaBridge.set_animation_meta(state_ptr,
            MetaLineJoint2Ids[i], Float32(line.joint2_id))
    end

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    line1_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineHostIds[1]))

    line_host_ids = ntuple(i ->
        Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineHostIds[i])), 4)
    line_joint1_ids = ntuple(i ->
        Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineJoint1Ids[i])), 4)
    line_joint2_ids = ntuple(i ->
        Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineJoint2Ids[i])), 4)

    marker_host_ids = ntuple(i ->
        Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerHostIds[i])), 4)
    marker_start_ids = ntuple(i ->
        Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerStartIds[i])), 4)
    marker_end_ids = ntuple(i ->
        Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerEndIds[i])), 4)

    if line1_host_id < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, PenDescendDuration, PenTopZ,
            SideStarts[1][1], SideStarts[1][2])

        timer += dt
        if timer >= PenDescendDuration
            phase = PhaseDrawSide1
            timer = 0f0
        end
    elseif phase == PhaseDrawSide1 || phase == PhaseDrawSide2 ||
           phase == PhaseDrawSide3 || phase == PhaseDrawSide4
        side_index = Int(phase)
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawDuration, SideStarts[side_index], SideEnds[side_index],
            TriangleMaxBrush, SideColors[side_index],
            line_host_ids[side_index], line_joint1_ids[side_index],
            line_joint2_ids[side_index])

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
            state_ptr, timer, PenRiseDuration, PenTopZ,
            SideStarts[1][1], SideStarts[1][2])

        timer += dt
        if timer >= PenRiseDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseCompassDescend
            timer = 0f0
        end
    elseif phase == PhaseCompassDescend
        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, CompassDescendDuration, CompassTopZ,
            MarkerCenters[1][1], MarkerCenters[1][2],
            MarkerStarts[1][1], MarkerStarts[1][2])

        timer += dt
        if timer >= CompassDescendDuration
            phase = PhaseDrawMarker1
            timer = 0f0
        end
    elseif phase == PhaseDrawMarker1 || phase == PhaseDrawMarker2 ||
           phase == PhaseDrawMarker3 || phase == PhaseDrawMarker4
        marker_index = Int((phase - PhaseDrawMarker1) / 2f0 + 1f0)
        EuclidAnimations.animate_draw_circle(
            state_ptr, timer, MarkerDrawDuration, MarkerCenters[marker_index],
            MarkerStarts[marker_index], MarkerSweeps[marker_index],
            MarkerRadius, MarkerBrush, MarkerColors[marker_index],
            marker_host_ids[marker_index], marker_start_ids[marker_index],
            marker_end_ids[marker_index])

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
    elseif phase == PhaseCompassArcToMarker2 || phase == PhaseCompassArcToMarker3 ||
           phase == PhaseCompassArcToMarker4
        from_index = Int((phase - PhaseCompassArcToMarker2) / 2f0 + 1f0)
        to_index = from_index + 1

        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, CompassArcMoveDuration,
            MarkerCenters[from_index], MarkerCenters[to_index],
            MarkerEnds[from_index], MarkerStarts[to_index],
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

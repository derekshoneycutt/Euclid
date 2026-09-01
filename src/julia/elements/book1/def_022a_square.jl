module ElementsOneDefinitionSquare

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex
using ..EuclidGeometry

using LinearAlgebra

export get_view_text, initialize, clean, loop, animation_entry

const VertexA = [0.24f0, 0.80f0, 0f0]
const VertexB = [0.76f0, 0.80f0, 0f0]
const VertexC = [0.76f0, 0.28f0, 0f0]
const VertexD = [0.24f0, 0.28f0, 0f0]

const SideStarts = (VertexA, VertexB, VertexC, VertexD)
const SideEnds = (VertexB, VertexC, VertexD, VertexA)
const SideColors = (:palevioletred1, :palevioletred1, :palevioletred1, :palevioletred1)

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
const CompassRiseDuration = 2.0f0
const HidePauseDuration = 1.5f0

"""Stable native handles for one line owned by the animation."""
struct LineIds
    host::Int64
    joint1::Int64
    joint2::Int64
end

"""Stable native handles for one angle marker owned by the animation."""
struct CircleIds
    host::Int64
    start::Int64
    finish::Int64
end

"""Complete immutable state for one square animation generation."""
struct AnimationState
    lines::NTuple{4,LineIds}
    markers::NTuple{4,CircleIds}
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

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

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(state.lines, state.markers, phase, timer)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """Euclid Elements - Book I - Definition: Square

Of quadrilateral figures, a square is that which is both equilateral and right-angled; ..."""
    latex = raw"""\textbf{Euclid Elements - Book I - Definition}: \textit{Square}

Of quadrilateral figures, a square \euclidbox[height=2,width=2,thickness=2,edge1_color=palevioletred1,edge2_color=palevioletred1,edge3_color=palevioletred1,edge4_color=palevioletred1] is that which is both equilateral \euclidline[color=palevioletred1,length=3,thickness=4] and right-angled \euclidangle[color=steelblue,radius=2,thickness=2]; ..."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset visible objects and transactionally publish initial cycle timing."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    line_host_ids = ntuple(i -> state.lines[i].host, 4)
    line_joint2_ids = ntuple(i -> state.lines[i].joint2, 4)
    marker_host_ids = ntuple(i -> state.markers[i].host, 4)
    marker_end_ids = ntuple(i -> state.markers[i].finish, 4)

    OdinJuliaBridge.hide_point_batch(state_ptr, [marker_host_ids..., line_host_ids...])

    for i in 1:4
        OdinJuliaBridge.set_point_position(
            state_ptr, line_joint2_ids[i],
            SideStarts[i][1], SideStarts[i][2], SideStarts[i][3])

        OdinJuliaBridge.set_point_position(
            state_ptr, marker_end_ids[i],
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

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhaseDescend, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    markers = ntuple(4) do i
        marker = OdinJuliaBridge.create_new_circle(
            state_ptr,
            MarkerCenters[i], MarkerRadius,
            MarkerStartThetas[i], MarkerStartThetas[i],
            MarkerColors[i], 0f0)
        CircleIds(marker.host_id, marker.start_id, marker.end_id)
    end
    lines = ntuple(4) do i
        line = OdinJuliaBridge.create_new_line(
            state_ptr, SideStarts[i], SideStarts[i],
            SideColors[i], 0f0)
        LineIds(line.host_id, line.joint1_id, line.joint2_id)
    end

    state = AnimationState(lines, markers, PhaseDescend, 0f0)
    reset_cycle_state(state_ptr, state)
    OdinJuliaBridge.publish_view_update(state_ptr, get_view_text)
end

"""Clean any extra animation data at the end of performance"""
function clean(state_ptr::Ptr{Cvoid})
end

"""Perform an iteration of the animation loop for this animation"""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    state, status = OdinJuliaBridge.get_animation_value(state_ptr, StateKey)
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return
    line1_host_id = state.lines[1].host
    line_host_ids = ntuple(i -> state.lines[i].host, 4)
    line_joint1_ids = ntuple(i -> state.lines[i].joint1, 4)
    line_joint2_ids = ntuple(i -> state.lines[i].joint2, 4)
    marker_host_ids = ntuple(i -> state.markers[i].host, 4)
    marker_start_ids = ntuple(i -> state.markers[i].start, 4)
    marker_end_ids = ntuple(i -> state.markers[i].finish, 4)

    if line1_host_id < 0
        return
    end

    phase = state.phase
    timer = state.timer

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
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawDuration,
            SideStarts[side_index], SideEnds[side_index];
            penbrush=TriangleMaxBrush,
            pencolor=SideColors[side_index],
            line_host_id=line_host_ids[side_index],
            line_joint1_id=line_joint1_ids[side_index],
            line_joint2_id=line_joint2_ids[side_index])

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
        EuclidAnimations.animate_draw_circle(state_ptr,
            timer, MarkerDrawDuration, MarkerCenters[marker_index],
            MarkerStarts[marker_index], MarkerSweeps[marker_index], MarkerRadius;
            brush=MarkerBrush,
            color=MarkerColors[marker_index],
            marker_host_id=marker_host_ids[marker_index],
            marker_start_id=marker_start_ids[marker_index],
            marker_end_id=marker_end_ids[marker_index])

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
            MarkerEnds[from_index], MarkerStarts[to_index])

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
            reset_cycle_state(state_ptr, state)
            return
        end
    end

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, phase, timer))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return
end


"""Dispatch one bridge-stable lifecycle operation for this animation."""
function animation_entry(
    state_ptr::Ptr{Cvoid}, operation::Int32, dt::Float32)::Bool

    if operation == OdinJuliaBridge.ANIMATION_OPERATION_ENTER
        initialize(state_ptr)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_TICK
        loop(state_ptr, dt)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_EXIT
        clean(state_ptr)
    else
        return false
    end
    return true
end

end

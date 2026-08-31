module ElementsOneDefinitionSurfaceExtremity

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

using LinearAlgebra

export get_view_text, initialize, clean, loop

const Corner1 = [0f0, 0f0, 0f0]
const Corner2 = [1f0, 0f0, 0f0]
const Corner3 = [1f0, 1f0, 0f0]
const Corner4 = [0f0, 1f0, 0f0]

const LineColor1 = :steelblue
const LineColor2 = :palevioletred1
const LineColor3 = :steelblue
const LineColor4 = :palevioletred1
const LineBrush = 5f0

const PenTopZ = 1.4f0
const PenLength = 0.14f0
const PenTiltFloorAngle = π / 4f0

const DescendDuration = 1.8f0
const DrawLineDuration = 3f0
const EndLiftDuration = 1.6f0
const HidePauseDuration = 0.35f0

"""Stable native handles for one edge owned by the animation."""
struct LineIds
    host::Int64
    joint1::Int64
    joint2::Int64
end

"""Complete immutable state for one surface-extremities animation generation."""
struct AnimationState
    edges::NTuple{4,LineIds}
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhaseDescend = 0f0
const PhaseDrawLine1 = 1f0
const PhaseDrawLine2 = 2f0
const PhaseDrawLine3 = 3f0
const PhaseDrawLine4 = 4f0
const PhaseEndLift = 13f0
const PhaseHideLines = 14f0

"""Return state with updated cycle timing and the same native edge handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(state.edges, phase, timer)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """Euclid Elements - Book I - Definition: Surface Extremities

The extremities of a surface are lines."""
    latex = raw"""\textbf{Euclid Elements - Book I - Definition}: \textit{Surface Extremities}

The extremities of a surface are lines \euclidline[color=steelblue,length=3,thickness=4]."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Hide a line's edge and collapse it onto a corner point."""
function hide_edge_and_collapse(
    state_ptr::Ptr{Cvoid}, host_id::Integer, joint1_id::Integer, joint2_id::Integer,
    corner::Vector{Float32})

    OdinJuliaBridge.hide_point(state_ptr, host_id)
    OdinJuliaBridge.set_point_position(
        state_ptr, joint1_id, corner[1], corner[2], corner[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, joint2_id, corner[1], corner[2], corner[3])
end

"""Reset the animation cycle while preserving its native edge handles."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    edge1_host_id = state.edges[1].host
    edge1_joint1_id = state.edges[1].joint1
    edge1_joint2_id = state.edges[1].joint2
    edge2_host_id = state.edges[2].host
    edge2_joint1_id = state.edges[2].joint1
    edge2_joint2_id = state.edges[2].joint2
    edge3_host_id = state.edges[3].host
    edge3_joint1_id = state.edges[3].joint1
    edge3_joint2_id = state.edges[3].joint2
    edge4_host_id = state.edges[4].host
    edge4_joint1_id = state.edges[4].joint1
    edge4_joint2_id = state.edges[4].joint2

    hide_edge_and_collapse(
        state_ptr, edge1_host_id, edge1_joint1_id, edge1_joint2_id, Corner1)
    hide_edge_and_collapse(
        state_ptr, edge2_host_id, edge2_joint1_id, edge2_joint2_id, Corner2)
    hide_edge_and_collapse(
        state_ptr, edge3_host_id, edge3_joint1_id, edge3_joint2_id, Corner3)
    hide_edge_and_collapse(
        state_ptr, edge4_host_id, edge4_joint1_id, edge4_joint2_id, Corner4)

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, LineColor1)

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhaseDescend, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    edge1 = OdinJuliaBridge.create_new_line(
        state_ptr, Corner1, Corner1,
        LineColor1, 0f0)
    edge2 = OdinJuliaBridge.create_new_line(
        state_ptr, Corner2, Corner2,
        LineColor2, 0f0)
    edge3 = OdinJuliaBridge.create_new_line(
        state_ptr, Corner3, Corner3,
        LineColor3, 0f0)
    edge4 = OdinJuliaBridge.create_new_line(
        state_ptr, Corner4, Corner4,
        LineColor4, 0f0)

    state = AnimationState((
        LineIds(edge1.host_id, edge1.joint1_id, edge1.joint2_id),
        LineIds(edge2.host_id, edge2.joint1_id, edge2.joint2_id),
        LineIds(edge3.host_id, edge3.joint1_id, edge3.joint2_id),
        LineIds(edge4.host_id, edge4.joint1_id, edge4.joint2_id)),
        PhaseDescend, 0f0)
    reset_cycle_state(state_ptr, state)
end

"""Clean any extra animation data at the end of performance"""
function clean(state_ptr::Ptr{Cvoid})
end

"""Perform an iteration of the animation loop for this animation"""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    state, status = OdinJuliaBridge.get_animation_value(state_ptr, StateKey)
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return
    edge1_host_id = state.edges[1].host
    edge1_joint1_id = state.edges[1].joint1
    edge1_joint2_id = state.edges[1].joint2
    edge2_host_id = state.edges[2].host
    edge2_joint1_id = state.edges[2].joint1
    edge2_joint2_id = state.edges[2].joint2
    edge3_host_id = state.edges[3].host
    edge3_joint1_id = state.edges[3].joint1
    edge3_joint2_id = state.edges[3].joint2
    edge4_host_id = state.edges[4].host
    edge4_joint1_id = state.edges[4].joint1
    edge4_joint2_id = state.edges[4].joint2

    if edge1_host_id < 0
        return
    end

    phase = state.phase
    timer = state.timer

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, Corner1[1], Corner1[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawLine1
            timer = 0f0
        end
    elseif phase == PhaseDrawLine1
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawLineDuration,
            Corner1, Corner2;
            penbrush=LineBrush,
            pencolor=LineColor1,
            line_host_id=edge1_host_id,
            line_joint1_id=edge1_joint1_id,
            line_joint2_id=edge1_joint2_id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseDrawLine2
            timer = 0f0
        end
    elseif phase == PhaseDrawLine2
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawLineDuration,
            Corner2, Corner3;
            penbrush=LineBrush,
            pencolor=LineColor2,
            line_host_id=edge2_host_id,
            line_joint1_id=edge2_joint1_id,
            line_joint2_id=edge2_joint2_id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseDrawLine3
            timer = 0f0
        end
    elseif phase == PhaseDrawLine3
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawLineDuration,
            Corner3, Corner4;
            penbrush=LineBrush,
            pencolor=LineColor3,
            line_host_id=edge3_host_id,
            line_joint1_id=edge3_joint1_id,
            line_joint2_id=edge3_joint2_id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseDrawLine4
            timer = 0f0
        end
    elseif phase == PhaseDrawLine4
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawLineDuration,
            Corner4, Corner1;
            penbrush=LineBrush,
            pencolor=LineColor4,
            line_host_id=edge4_host_id,
            line_joint1_id=edge4_joint1_id,
            line_joint2_id=edge4_joint2_id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ, Corner1[1], Corner1[2])

        timer += dt
        if timer >= EndLiftDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseHideLines
            timer = 0f0
        end
    elseif phase == PhaseHideLines
        hide_edge_and_collapse(
            state_ptr, edge1_host_id, edge1_joint1_id, edge1_joint2_id, Corner1)
        hide_edge_and_collapse(
            state_ptr, edge2_host_id, edge2_joint1_id, edge2_joint2_id, Corner2)
        hide_edge_and_collapse(
            state_ptr, edge3_host_id, edge3_joint1_id, edge3_joint2_id, Corner3)
        hide_edge_and_collapse(
            state_ptr, edge4_host_id, edge4_joint1_id, edge4_joint2_id, Corner4)

        timer += dt
        if timer >= HidePauseDuration
            reset_cycle_state(state_ptr, state)
            return
        end
    end

    OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, phase, timer))
end

end

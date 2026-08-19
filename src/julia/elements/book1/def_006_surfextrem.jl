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

const MetaEdge1HostId = 1
const MetaEdge1Joint1Id = 2
const MetaEdge1Joint2Id = 3
const MetaEdge2HostId = 4
const MetaEdge2Joint1Id = 5
const MetaEdge2Joint2Id = 6
const MetaEdge3HostId = 7
const MetaEdge3Joint1Id = 8
const MetaEdge3Joint2Id = 9
const MetaEdge4HostId = 10
const MetaEdge4Joint1Id = 11
const MetaEdge4Joint2Id = 12
const MetaPhase = 13
const MetaTimer = 14

const PhaseDescend = 0f0
const PhaseDrawLine1 = 1f0
const PhaseDrawLine2 = 2f0
const PhaseDrawLine3 = 3f0
const PhaseDrawLine4 = 4f0
const PhaseEndLift = 13f0
const PhaseHideLines = 14f0

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

"""Reset the state of the animation cycle back to the start of the animation"""
function reset_cycle_state(state_ptr::Ptr{Cvoid})
    edge1_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdge1HostId))
    edge1_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdge1Joint1Id))
    edge1_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdge1Joint2Id))

    edge2_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdge2HostId))
    edge2_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdge2Joint1Id))
    edge2_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdge2Joint2Id))

    edge3_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdge3HostId))
    edge3_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdge3Joint1Id))
    edge3_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdge3Joint2Id))

    edge4_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdge4HostId))
    edge4_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdge4Joint1Id))
    edge4_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdge4Joint2Id))

    hide_edge_and_collapse(
        state_ptr, edge1_host_id, edge1_joint1_id, edge1_joint2_id, Corner1)
    hide_edge_and_collapse(
        state_ptr, edge2_host_id, edge2_joint1_id, edge2_joint2_id, Corner2)
    hide_edge_and_collapse(
        state_ptr, edge3_host_id, edge3_joint1_id, edge3_joint2_id, Corner3)
    hide_edge_and_collapse(
        state_ptr, edge4_host_id, edge4_joint1_id, edge4_joint2_id, Corner4)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, LineColor1)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    edge1 = OdinJuliaBridge.create_new_line(
        state_ptr,
        Corner1[1], Corner1[2], Corner1[3],
        Corner1[1], Corner1[2], Corner1[3],
        LineColor1, 0f0)
    edge2 = OdinJuliaBridge.create_new_line(
        state_ptr,
        Corner2[1], Corner2[2], Corner2[3],
        Corner2[1], Corner2[2], Corner2[3],
        LineColor2, 0f0)
    edge3 = OdinJuliaBridge.create_new_line(
        state_ptr,
        Corner3[1], Corner3[2], Corner3[3],
        Corner3[1], Corner3[2], Corner3[3],
        LineColor3, 0f0)
    edge4 = OdinJuliaBridge.create_new_line(
        state_ptr,
        Corner4[1], Corner4[2], Corner4[3],
        Corner4[1], Corner4[2], Corner4[3],
        LineColor4, 0f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdge1HostId, edge1.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdge1Joint1Id, edge1.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdge1Joint2Id, edge1.joint2_id)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdge2HostId, edge2.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdge2Joint1Id, edge2.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdge2Joint2Id, edge2.joint2_id)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdge3HostId, edge3.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdge3Joint1Id, edge3.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdge3Joint2Id, edge3.joint2_id)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdge4HostId, edge4.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdge4Joint1Id, edge4.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaEdge4Joint2Id, edge4.joint2_id)

    reset_cycle_state(state_ptr)
end

"""Clean any extra animation data at the end of performance"""
function clean(state_ptr::Ptr{Cvoid})
end

"""Perform an iteration of the animation loop for this animation"""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    edge1_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdge1HostId))
    edge1_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdge1Joint1Id))
    edge1_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdge1Joint2Id))

    edge2_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdge2HostId))
    edge2_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdge2Joint1Id))
    edge2_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdge2Joint2Id))

    edge3_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdge3HostId))
    edge3_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdge3Joint1Id))
    edge3_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdge3Joint2Id))

    edge4_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdge4HostId))
    edge4_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdge4Joint1Id))
    edge4_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaEdge4Joint2Id))

    if edge1_host_id < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, Corner1[1], Corner1[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawLine1
            timer = 0f0
        end
    elseif phase == PhaseDrawLine1
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, Corner1, Corner2,
            LineBrush, LineColor1, edge1_host_id, edge1_joint1_id, edge1_joint2_id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseDrawLine2
            timer = 0f0
        end
    elseif phase == PhaseDrawLine2
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, Corner2, Corner3,
            LineBrush, LineColor2, edge2_host_id, edge2_joint1_id, edge2_joint2_id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseDrawLine3
            timer = 0f0
        end
    elseif phase == PhaseDrawLine3
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, Corner3, Corner4,
            LineBrush, LineColor3, edge3_host_id, edge3_joint1_id, edge3_joint2_id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseDrawLine4
            timer = 0f0
        end
    elseif phase == PhaseDrawLine4
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, Corner4, Corner1,
            LineBrush, LineColor4, edge4_host_id, edge4_joint1_id, edge4_joint2_id)

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
            reset_cycle_state(state_ptr)
            return
        end
    end

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, phase)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, timer)
end

end

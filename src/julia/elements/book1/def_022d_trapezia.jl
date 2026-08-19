module ElementsOneDefinitionTrapezia

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

export get_view_text, initialize, clean, loop

const VertexA = [0.14f0, 0.76f0, 0f0]
const VertexB = [0.86f0, 0.76f0, 0f0]
const VertexC = [0.72f0, 0.42f0, 0f0]
const VertexD = [0.28f0, 0.42f0, 0f0]

const SideStarts = (VertexA, VertexB, VertexC, VertexD)
const SideEnds = (VertexB, VertexC, VertexD, VertexA)
const SideColors = (:steelblue, :palevioletred1, :khaki3, :grey60)

const PenTopZ = 1.4f0
const QuadMaxBrush = 5f0

const PenDescendDuration = 1.8f0
const DrawDuration = 2.6f0
const PenRiseDuration = 1.8f0
const HidePauseDuration = 1.5f0

const MetaLineHostIds = (1, 4, 7, 10)
const MetaLineJoint1Ids = (2, 5, 8, 11)
const MetaLineJoint2Ids = (3, 6, 9, 12)
const MetaPhase = 13
const MetaTimer = 14

const PhaseDescend = 0f0
const PhaseDrawSide1 = 1f0
const PhaseDrawSide2 = 2f0
const PhaseDrawSide3 = 3f0
const PhaseDrawSide4 = 4f0
const PhaseRise = 5f0
const PhaseHideAll = 6f0

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """Euclid Elements - Book I - Definition: Trapezia

And let quadrilateral figures besides these be called trapezia."""
    latex = raw"""\textbf{Euclid Elements - Book I - Definition}: \textit{Trapezia}

And let quadrilateral figures besides these be called trapezia \euclidbox[height=2,width=3,thickness=2,edge1_color=steelblue,edge2_color=palevioletred1,edge3_color=khaki3,edge4_color=grey60]."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset the state of the animation cycle back to the start of the animation"""
function reset_cycle_state(state_ptr::Ptr{Cvoid})
    line_host_ids = ntuple(i ->
        Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineHostIds[i])), 4)
    line_joint2_ids = ntuple(i ->
        Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineJoint2Ids[i])), 4)

    OdinJuliaBridge.hide_point_batch(state_ptr, line_host_ids)

    for i in 1:4
        OdinJuliaBridge.set_point_position(
            state_ptr, line_joint2_ids[i],
            SideStarts[i][1], SideStarts[i][2], SideStarts[i][3])
    end

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, SideColors[1])

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
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

"""Clean any extra animation data at the end of performance"""
function clean(state_ptr::Ptr{Cvoid})
end

"""Perform an iteration of the animation loop for this animation"""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    line1_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineHostIds[1]))

    line_host_ids = ntuple(i ->
        Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineHostIds[i])), 4)
    line_joint1_ids = ntuple(i ->
        Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineJoint1Ids[i])), 4)
    line_joint2_ids = ntuple(i ->
        Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineJoint2Ids[i])), 4)

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
            QuadMaxBrush, SideColors[side_index],
            line_host_ids[side_index], line_joint1_ids[side_index],
            line_joint2_ids[side_index])

        timer += dt
        if timer >= DrawDuration
            if phase == PhaseDrawSide4
                phase = PhaseRise
            else
                phase += 1f0
            end
            timer = 0f0
        end
    elseif phase == PhaseRise
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenRiseDuration, PenTopZ,
            SideStarts[1][1], SideStarts[1][2])

        timer += dt
        if timer >= PenRiseDuration
            OdinJuliaBridge.hide_pen(state_ptr)
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

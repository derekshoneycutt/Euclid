module HilbertChapterOneTheorem8

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

export get_view_text, initialize, clean, loop

const LineAStart = [0.14f0, 0.74f0, 0f0]
const LineAEnd = [0.86f0, 0.74f0, 0f0]
const LineBStart = [0.14f0, 0.28f0, 0f0]
const LineBEnd = [0.86f0, 0.28f0, 0f0]
const LineCStart = [0.14f0, 0.51f0, 0f0]
const LineCEnd = [0.86f0, 0.51f0, 0f0]
const PenTopZ = 1.4f0

const LabelColor = :plum1
const LineAColor = :steelblue
const LineBColor = :palevioletred1
const LineCColor = :khaki3
const LineMaxBrush = 5f0

const LabelaPoint = LineAStart + [0.03f0, 0.06f0, 0f0]
const LabelbPoint = LineBStart + [0.03f0, 0.06f0, 0f0]
const LabelcPoint = LineCStart + [0.03f0, 0.06f0, 0f0]

const DescendDuration = 1.8f0
const DrawLineDuration = 3.8f0
const ArcMoveDuration = 1.8f0
const EndLiftDuration = 1.8f0
const FinalHoldDuration = 0.9f0

const MetaLineAHostId = 1
const MetaLineAJoint1Id = 2
const MetaLineAJoint2Id = 3
const MetaLineBHostId = 11
const MetaLineBJoint1Id = 12
const MetaLineBJoint2Id = 13
const MetaLineCHostId = 21
const MetaLineCJoint1Id = 22
const MetaLineCJoint2Id = 23
const MetaLabelaId = 31
const MetaLabelbId = 32
const MetaLabelcId = 33
const MetaPhase = 101
const MetaTimer = 102

const PhaseDescend = 0f0
const PhaseDrawLineA = 1f0
const PhaseMoveToLineB = 2f0
const PhaseDrawLineB = 3f0
const PhaseMoveToLineC = 4f0
const PhaseDrawLineC = 5f0
const PhaseEndLift = 6f0
const PhaseFinalHold = 7f0


function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - Theorem 8

If two straight lines a, b of a plane do not meet a third straight line c of the same plane, then they do not meet each other.

For, if a, b had a point A in common, there would then exist in the same plane with c two straight lines a and b each passing through the point A and not meeting the straight line c. This condition of affairs is, however, contradictory to the second assertion contained in the axiom of parallels as originally stated. Conversely, the second part of the axiom of parallels, in its original form, follows as a consequence of theorem 8."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - Theorem 8}

If two straight lines $a$ \euclidline[color=steelblue,length=3,thickness=4], $b$ \euclidline[color=palevioletred1,length=3,thickness=4] of a plane do not meet a third straight line $c$ \euclidline[color=khaki3,length=3,thickness=4] of the same plane, then they do not meet each other.

For, if $a$ \euclidline[color=steelblue,length=3,thickness=4], $b$ \euclidline[color=palevioletred1,length=3,thickness=4] had a point $A$ \euclidpoint[color=plum1,size=0.5] in common, there would then exist in the same plane with $c$ \euclidline[color=khaki3,length=3,thickness=4] two straight lines $a$ \euclidline[color=steelblue,length=3,thickness=4] and $b$ \euclidline[color=palevioletred1,length=3,thickness=4] each passing through the point $A$ \euclidpoint[color=plum1,size=0.5] and not meeting the straight line $c$ \euclidline[color=khaki3,length=3,thickness=4]. This condition of affairs is, however, contradictory to the second assertion contained in the axiom of parallels as originally stated. Conversely, the second part of the axiom of parallels, in its original form, follows as a consequence of \textit{theorem 8}."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    line_a_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAHostId))
    line_a_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAJoint1Id))
    line_a_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAJoint2Id))
    line_b_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineBHostId))
    line_b_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineBJoint1Id))
    line_b_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineBJoint2Id))
    line_c_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineCHostId))
    line_c_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineCJoint1Id))
    line_c_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineCJoint2Id))
    labela_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelaId))
    labelb_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelbId))
    labelc_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelcId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [line_a_host_id, line_b_host_id, line_c_host_id, labela_id, labelb_id, labelc_id])

    OdinJuliaBridge.set_point_position(state_ptr, line_a_joint1_id, LineAStart)
    OdinJuliaBridge.set_point_position(state_ptr, line_a_joint2_id, LineAStart)
    OdinJuliaBridge.set_point_position(state_ptr, line_b_joint1_id, LineBStart)
    OdinJuliaBridge.set_point_position(state_ptr, line_b_joint2_id, LineBStart)
    OdinJuliaBridge.set_point_position(state_ptr, line_c_joint1_id, LineCStart)
    OdinJuliaBridge.set_point_position(state_ptr, line_c_joint2_id, LineCStart)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, LineAColor)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    line_a = OdinJuliaBridge.create_new_line(
        state_ptr, LineAStart, LineAStart, LineAColor, 0f0)
    line_b = OdinJuliaBridge.create_new_line(
        state_ptr, LineBStart, LineBStart, LineBColor, 0f0)
    line_c = OdinJuliaBridge.create_new_line(
        state_ptr, LineCStart, LineCStart, LineCColor, 0f0)

    labela = OdinJuliaBridge.create_new_label(
        state_ptr, 'a', LabelaPoint, LabelColor, 16f0)
    labelb = OdinJuliaBridge.create_new_label(
        state_ptr, 'b', LabelbPoint, LabelColor, 16f0)
    labelc = OdinJuliaBridge.create_new_label(
        state_ptr, 'c', LabelcPoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineAHostId, Float32(line_a.host_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineAJoint1Id, Float32(line_a.joint1_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineAJoint2Id, Float32(line_a.joint2_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineBHostId, Float32(line_b.host_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineBJoint1Id, Float32(line_b.joint1_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineBJoint2Id, Float32(line_b.joint2_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineCHostId, Float32(line_c.host_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineCJoint1Id, Float32(line_c.joint1_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineCJoint2Id, Float32(line_c.joint2_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelaId, Float32(labela.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelbId, Float32(labelb.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelcId, Float32(labelc.index))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    line_a_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAHostId))
    line_a_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAJoint1Id))
    line_a_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAJoint2Id))
    line_b_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineBHostId))
    line_b_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineBJoint1Id))
    line_b_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineBJoint2Id))
    line_c_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineCHostId))
    line_c_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineCJoint1Id))
    line_c_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineCJoint2Id))
    labela_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelaId))
    labelb_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelbId))
    labelc_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelcId))

    if line_a_host_id < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, LineAStart[1], LineAStart[2])

        timer += dt
        if timer >= DescendDuration
            OdinJuliaBridge.show_point(state_ptr, labela_id)
            phase = PhaseDrawLineA
            timer = 0f0
        end
    elseif phase == PhaseDrawLineA
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, LineAStart, LineAEnd,
            LineMaxBrush, LineAColor, line_a_host_id, line_a_joint1_id, line_a_joint2_id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseMoveToLineB
            timer = 0f0
        end
    elseif phase == PhaseMoveToLineB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            LineAEnd, LineBStart, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.set_pen_active(state_ptr, 0, LineBColor)
            OdinJuliaBridge.show_point(state_ptr, labelb_id)
            phase = PhaseDrawLineB
            timer = 0f0
        end
    elseif phase == PhaseDrawLineB
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, LineBStart, LineBEnd,
            LineMaxBrush, LineBColor, line_b_host_id, line_b_joint1_id, line_b_joint2_id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseMoveToLineC
            timer = 0f0
        end
    elseif phase == PhaseMoveToLineC
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            LineBEnd, LineCStart, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.set_pen_active(state_ptr, 0, LineCColor)
            OdinJuliaBridge.show_point(state_ptr, labelc_id)
            phase = PhaseDrawLineC
            timer = 0f0
        end
    elseif phase == PhaseDrawLineC
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, LineCStart, LineCEnd,
            LineMaxBrush, LineCColor, line_c_host_id, line_c_joint1_id, line_c_joint2_id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ, LineCEnd[1], LineCEnd[2])

        timer += dt
        if timer >= EndLiftDuration
            phase = PhaseFinalHold
            timer = 0f0
        end
    elseif phase == PhaseFinalHold
        timer += dt
        if timer >= FinalHoldDuration
            reset_cycle_state(state_ptr)
            return
        end
    end

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, phase)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, timer)
end

end

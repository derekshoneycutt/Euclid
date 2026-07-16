module HilbertChapterOneTheorem8

using ..OdinJuliaBridge
using ..EuclidAnimations

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
    """David Hilbert - Foundations of Geometry - Theorem 8

If two straight lines a, b of a plane do not meet a third straight line c of the same plane, then they do not meet each other.

For, if a, b had a point A in common, there would then exist in the same plane with c two straight lines a and b each passing through the point A and not meeting the straight line c. This condition of affairs is, however, contradictory to the second assertion contained in the axiom of parallels as originally stated. Conversely, the second part of the axiom of parallels, in its original form, follows as a consequence of theorem 8."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    lineAHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAHostId))
    lineAJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAJoint1Id))
    lineAJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAJoint2Id))
    lineBHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineBHostId))
    lineBJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineBJoint1Id))
    lineBJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineBJoint2Id))
    lineCHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineCHostId))
    lineCJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineCJoint1Id))
    lineCJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineCJoint2Id))
    labelaId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelaId))
    labelbId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelbId))
    labelcId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelcId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [lineAHostId, lineBHostId, lineCHostId, labelaId, labelbId, labelcId])

    OdinJuliaBridge.set_point_position(state_ptr, lineAJoint1Id, LineAStart)
    OdinJuliaBridge.set_point_position(state_ptr, lineAJoint2Id, LineAStart)
    OdinJuliaBridge.set_point_position(state_ptr, lineBJoint1Id, LineBStart)
    OdinJuliaBridge.set_point_position(state_ptr, lineBJoint2Id, LineBStart)
    OdinJuliaBridge.set_point_position(state_ptr, lineCJoint1Id, LineCStart)
    OdinJuliaBridge.set_point_position(state_ptr, lineCJoint2Id, LineCStart)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, LineAColor)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    lineA = OdinJuliaBridge.create_new_line(
        state_ptr, LineAStart, LineAStart, LineAColor, 0f0)
    lineB = OdinJuliaBridge.create_new_line(
        state_ptr, LineBStart, LineBStart, LineBColor, 0f0)
    lineC = OdinJuliaBridge.create_new_line(
        state_ptr, LineCStart, LineCStart, LineCColor, 0f0)

    labela = OdinJuliaBridge.create_new_label(
        state_ptr, 'a', LabelaPoint, LabelColor, 16f0)
    labelb = OdinJuliaBridge.create_new_label(
        state_ptr, 'b', LabelbPoint, LabelColor, 16f0)
    labelc = OdinJuliaBridge.create_new_label(
        state_ptr, 'c', LabelcPoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineAHostId, Float32(lineA.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineAJoint1Id, Float32(lineA.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineAJoint2Id, Float32(lineA.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineBHostId, Float32(lineB.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineBJoint1Id, Float32(lineB.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineBJoint2Id, Float32(lineB.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineCHostId, Float32(lineC.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineCJoint1Id, Float32(lineC.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineCJoint2Id, Float32(lineC.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelaId, Float32(labela.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelbId, Float32(labelb.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelcId, Float32(labelc.index))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    lineAHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAHostId))
    lineAJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAJoint1Id))
    lineAJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAJoint2Id))
    lineBHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineBHostId))
    lineBJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineBJoint1Id))
    lineBJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineBJoint2Id))
    lineCHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineCHostId))
    lineCJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineCJoint1Id))
    lineCJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineCJoint2Id))
    labelaId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelaId))
    labelbId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelbId))
    labelcId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelcId))

    if lineAHostId < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, LineAStart[1], LineAStart[2])

        timer += dt
        if timer >= DescendDuration
            OdinJuliaBridge.show_point(state_ptr, labelaId)
            phase = PhaseDrawLineA
            timer = 0f0
        end
    elseif phase == PhaseDrawLineA
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, LineAStart, LineAEnd,
            LineMaxBrush, LineAColor, lineAHostId, lineAJoint1Id, lineAJoint2Id)

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
            OdinJuliaBridge.show_point(state_ptr, labelbId)
            phase = PhaseDrawLineB
            timer = 0f0
        end
    elseif phase == PhaseDrawLineB
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, LineBStart, LineBEnd,
            LineMaxBrush, LineBColor, lineBHostId, lineBJoint1Id, lineBJoint2Id)

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
            OdinJuliaBridge.show_point(state_ptr, labelcId)
            phase = PhaseDrawLineC
            timer = 0f0
        end
    elseif phase == PhaseDrawLineC
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, LineCStart, LineCEnd,
            LineMaxBrush, LineCColor, lineCHostId, lineCJoint1Id, lineCJoint2Id)

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

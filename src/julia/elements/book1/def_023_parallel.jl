module ElementsOneDefinitionParallel

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

export get_view_text, initialize, clean, loop

const Line1Start = [0.00f0, 0.70f0, 0f0]
const Line1End = [1.00f0, 0.70f0, 0f0]
const Line2Start = [0.00f0, 0.30f0, 0f0]
const Line2End = [1.00f0, 0.30f0, 0f0]

const PenTopZ = 1.4f0
const LineMaxBrush = 5f0

const Line1Color = :steelblue
const Line2Color = :khaki3

const DescendDuration = 1.8f0
const DrawDuration = 3.2f0
const ArcMoveDuration = 2.2f0
const ArcMoveHeight = 0.22f0
const RiseDuration = 1.8f0
const HidePauseDuration = 1.5f0

const MetaLine1HostId = 1
const MetaLine1Joint1Id = 2
const MetaLine1Joint2Id = 3
const MetaLine2HostId = 4
const MetaLine2Joint1Id = 5
const MetaLine2Joint2Id = 6
const MetaPhase = 7
const MetaTimer = 8

const PhaseDescendLine1 = 0f0
const PhaseDrawLine1 = 1f0
const PhaseArcToLine2 = 2f0
const PhaseDrawLine2 = 3f0
const PhaseRiseLine2 = 4f0
const PhaseHideAll = 5f0

function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """Euclid Elements - Book I - Definition: Parallel Straight Lines

Parallel straight lines are straight lines which, being in the same plane and being produced indefinitely in both directions, do not meet one another in either direction."""
    latex = raw"""\textbf{Euclid Elements - Book I - Definition}: \textit{Parallel Straight Lines}

Parallel straight lines \euclidline[color=steelblue,length=3,thickness=4] \euclidline[color=khaki3,length=3,thickness=4] are straight lines which, being in the same plane and being produced indefinitely in both directions, do not meet one another in either direction."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    line1_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine1HostId))
    line1_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine1Joint2Id))

    line2_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine2HostId))
    line2_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine2Joint2Id))

    OdinJuliaBridge.hide_point_batch(state_ptr, [line1_host_id, line2_host_id])

    OdinJuliaBridge.set_point_position(
        state_ptr, line1_joint2_id,
        Line1Start[1], Line1Start[2], Line1Start[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, line2_joint2_id,
        Line2Start[1], Line2Start[2], Line2Start[3])

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, Line1Color)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescendLine1)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    line1 = OdinJuliaBridge.create_new_line(
        state_ptr,
        Line1Start[1], Line1Start[2], Line1Start[3],
        Line1Start[1], Line1Start[2], Line1Start[3],
        Line1Color, 0f0)
    line2 = OdinJuliaBridge.create_new_line(
        state_ptr,
        Line2Start[1], Line2Start[2], Line2Start[3],
        Line2Start[1], Line2Start[2], Line2Start[3],
        Line2Color, 0f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine1HostId, line1.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine1Joint1Id, line1.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine1Joint2Id, line1.joint2_id)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine2HostId, line2.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine2Joint1Id, line2.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine2Joint2Id, line2.joint2_id)

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    line1_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine1HostId))
    line1_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine1Joint1Id))
    line1_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine1Joint2Id))

    line2_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine2HostId))
    line2_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine2Joint1Id))
    line2_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine2Joint2Id))

    if line1_host_id < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescendLine1
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, Line1Start[1], Line1Start[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawLine1
            timer = 0f0
        end
    elseif phase == PhaseDrawLine1
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawDuration, Line1Start, Line1End,
            LineMaxBrush, Line1Color, line1_host_id, line1_joint1_id, line1_joint2_id)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseArcToLine2
            timer = 0f0
        end
    elseif phase == PhaseArcToLine2
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            Line1End, Line2Start, ArcMoveHeight, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.set_pen_active(state_ptr, 0, Line2Color)
            phase = PhaseDrawLine2
            timer = 0f0
        end
    elseif phase == PhaseDrawLine2
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawDuration, Line2Start, Line2End,
            LineMaxBrush, Line2Color, line2_host_id, line2_joint1_id, line2_joint2_id)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseRiseLine2
            timer = 0f0
        end
    elseif phase == PhaseRiseLine2
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, RiseDuration, PenTopZ, Line2End[1], Line2End[2])

        timer += dt
        if timer >= RiseDuration
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

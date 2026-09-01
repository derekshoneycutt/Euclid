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

"""Complete immutable state for one Theorem 8 animation generation."""
struct AnimationState
    line_ahost_id::Int64
    line_ajoint1_id::Int64
    line_ajoint2_id::Int64
    line_bhost_id::Int64
    line_bjoint1_id::Int64
    line_bjoint2_id::Int64
    line_chost_id::Int64
    line_cjoint1_id::Int64
    line_cjoint2_id::Int64
    labela_id::Int64
    labelb_id::Int64
    labelc_id::Int64
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhaseDescend = 0f0
const PhaseDrawLineA = 1f0
const PhaseMoveToLineB = 2f0
const PhaseDrawLineB = 3f0
const PhaseMoveToLineC = 4f0
const PhaseDrawLineC = 5f0
const PhaseEndLift = 6f0
const PhaseFinalHold = 7f0

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(
        state.line_ahost_id, state.line_ajoint1_id, state.line_ajoint2_id,
        state.line_bhost_id, state.line_bjoint1_id, state.line_bjoint2_id,
        state.line_chost_id, state.line_cjoint1_id, state.line_cjoint2_id,
        state.labela_id, state.labelb_id, state.labelc_id,
        phase, timer)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - Theorem 8

If two straight lines a, b of a plane do not meet a third straight line c of the same plane, then they do not meet each other.

For, if a, b had a point A in common, there would then exist in the same plane with c two straight lines a and b each passing through the point A and not meeting the straight line c. This condition of affairs is, however, contradictory to the second assertion contained in the axiom of parallels as originally stated. Conversely, the second part of the axiom of parallels, in its original form, follows as a consequence of theorem 8."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - Theorem 8}

If two straight lines $a$ \euclidline[color=steelblue,length=3,thickness=4], $b$ \euclidline[color=palevioletred1,length=3,thickness=4] of a plane do not meet a third straight line $c$ \euclidline[color=khaki3,length=3,thickness=4] of the same plane, then they do not meet each other.

For, if $a$ \euclidline[color=steelblue,length=3,thickness=4], $b$ \euclidline[color=palevioletred1,length=3,thickness=4] had a point $A$ \euclidpoint[color=plum1,size=0.5] in common, there would then exist in the same plane with $c$ \euclidline[color=khaki3,length=3,thickness=4] two straight lines $a$ \euclidline[color=steelblue,length=3,thickness=4] and $b$ \euclidline[color=palevioletred1,length=3,thickness=4] each passing through the point $A$ \euclidpoint[color=plum1,size=0.5] and not meeting the straight line $c$ \euclidline[color=khaki3,length=3,thickness=4]. This condition of affairs is, however, contradictory to the second assertion contained in the axiom of parallels as originally stated. Conversely, the second part of the axiom of parallels, in its original form, follows as a consequence of \textit{theorem 8}."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset the animation cycle while preserving its native handles."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    line_a_host_id = state.line_ahost_id
    line_a_joint1_id = state.line_ajoint1_id
    line_a_joint2_id = state.line_ajoint2_id
    line_b_host_id = state.line_bhost_id
    line_b_joint1_id = state.line_bjoint1_id
    line_b_joint2_id = state.line_bjoint2_id
    line_c_host_id = state.line_chost_id
    line_c_joint1_id = state.line_cjoint1_id
    line_c_joint2_id = state.line_cjoint2_id
    labela_id = state.labela_id
    labelb_id = state.labelb_id
    labelc_id = state.labelc_id

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [line_a_host_id, line_b_host_id, line_c_host_id,
         labela_id, labelb_id, labelc_id])

    OdinJuliaBridge.set_point_position(state_ptr, line_a_joint1_id, LineAStart)
    OdinJuliaBridge.set_point_position(state_ptr, line_a_joint2_id, LineAStart)
    OdinJuliaBridge.set_point_position(state_ptr, line_b_joint1_id, LineBStart)
    OdinJuliaBridge.set_point_position(state_ptr, line_b_joint2_id, LineBStart)
    OdinJuliaBridge.set_point_position(state_ptr, line_c_joint1_id, LineCStart)
    OdinJuliaBridge.set_point_position(state_ptr, line_c_joint2_id, LineCStart)


    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, LineAColor)

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, 0f0, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
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


    state = AnimationState(
        line_a.host_id, line_a.joint1_id, line_a.joint2_id, line_b.host_id,
        line_b.joint1_id, line_b.joint2_id, line_c.host_id, line_c.joint1_id,
        line_c.joint2_id, labela.index, labelb.index, labelc.index,
        0f0, 0f0)
    reset_cycle_state(state_ptr, state)
end

"""Clean any extra animation data at the end of performance"""
function clean(state_ptr::Ptr{Cvoid})
end

"""Perform an iteration of the animation loop for this animation"""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    state, status = OdinJuliaBridge.get_animation_value(state_ptr, StateKey)
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return
    line_a_host_id = state.line_ahost_id
    line_a_joint1_id = state.line_ajoint1_id
    line_a_joint2_id = state.line_ajoint2_id
    line_b_host_id = state.line_bhost_id
    line_b_joint1_id = state.line_bjoint1_id
    line_b_joint2_id = state.line_bjoint2_id
    line_c_host_id = state.line_chost_id
    line_c_joint1_id = state.line_cjoint1_id
    line_c_joint2_id = state.line_cjoint2_id
    labela_id = state.labela_id
    labelb_id = state.labelb_id
    labelc_id = state.labelc_id

    if line_a_host_id < 0
        return
    end

    phase = state.phase
    timer = state.timer

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
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawLineDuration,
            LineAStart, LineAEnd;
            penbrush=LineMaxBrush,
            pencolor=LineAColor,
            line_host_id=line_a_host_id,
            line_joint1_id=line_a_joint1_id,
            line_joint2_id=line_a_joint2_id)

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
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawLineDuration,
            LineBStart, LineBEnd;
            penbrush=LineMaxBrush,
            pencolor=LineBColor,
            line_host_id=line_b_host_id,
            line_joint1_id=line_b_joint1_id,
            line_joint2_id=line_b_joint2_id)

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
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawLineDuration,
            LineCStart, LineCEnd;
            penbrush=LineMaxBrush,
            pencolor=LineCColor,
            line_host_id=line_c_host_id,
            line_joint1_id=line_c_joint1_id,
            line_joint2_id=line_c_joint2_id)

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
            reset_cycle_state(state_ptr, state)
            return
        end
    end

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, phase, timer))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return
end

end

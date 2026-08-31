module HilbertChapterOneTheorem4

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

export get_view_text, initialize, clean, loop

const LineStart = [0.14f0, 0.52f0, 0f0]
const LineEnd = [0.86f0, 0.52f0, 0f0]
const PointA = [0.30f0, 0.52f0, 0f0]
const PointB = [0.45f0, 0.52f0, 0f0]
const PointC = [0.50f0, 0.52f0, 0f0]
const PointD = [0.54f0, 0.52f0, 0f0]
const PointE = [0.60f0, 0.52f0, 0f0]
const PointK = [0.79f0, 0.52f0, 0f0]
const PenTopZ = 1.4f0

const ALabelPoint = PointA + [-0.005f0, 0.04f0, 0f0]
const BLabelPoint = PointB + [-0.005f0, 0.04f0, 0f0]
const CLabelPoint = PointC + [-0.005f0, 0.04f0, 0f0]
const DLabelPoint = PointD + [-0.005f0, 0.04f0, 0f0]
const ELabelPoint = PointE + [-0.005f0, 0.04f0, 0f0]
const KLabelPoint = PointK + [-0.005f0, 0.04f0, 0f0]
const LabelColor = :plum1

const LineColor = :grey60
const PointAColor = :steelblue
const PointBColor = :palevioletred1
const PointCColor = :khaki3
const PointDColor = :steelblue
const PointEColor = :khaki3
const PointKColor = :steelblue
const LineMaxBrush = 5f0
const PointMaxBrush = 5f0

const DescendDuration = 1.8f0
const DrawLineDuration = 4.2f0
const ArcMoveDuration = 1.8f0
const PointTrailDuration = 2f0
const DragSegmentDuration = 2.1f0
const EndLiftDuration = 1.8f0

"""Stable native handles for one line owned by the animation."""
struct LineIds
    host::Int64
    joint1::Int64
    joint2::Int64
end

"""Complete immutable state for one Theorem 4 animation generation."""
struct AnimationState
    line::LineIds
    point_a::Int64
    point_b::Int64
    point_c::Int64
    point_d::Int64
    point_e::Int64
    point_k::Int64
    label_a::Int64
    label_b::Int64
    label_c::Int64
    label_d::Int64
    label_e::Int64
    label_k::Int64
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhaseDescend = 0f0
const PhaseDrawLine = 1f0
const PhaseMoveToPointA = 2f0
const PhasePutPointA = 3f0
const PhaseMoveToPointB = 4f0
const PhasePutPointB = 5f0
const PhaseMoveToPointC = 6f0
const PhasePutPointC = 7f0
const PhaseMoveToPointD = 8f0
const PhasePutPointD = 9f0
const PhaseMoveToPointE = 10f0
const PhasePutPointE = 11f0
const PhaseMoveToPointK = 12f0
const PhasePutPointK = 13f0
const PhaseMoveToPointAForDrag = 14f0
const PhaseDragAB = 15f0
const PhaseDragBK = 16f0
const PhaseMoveToPointCForDrag = 17f0
const PhaseDragCD = 18f0
const PhaseDragDE = 19f0
const PhaseMoveToPointBForDrag = 20f0
const PhaseDragBC = 21f0
const PhaseDragCK = 22f0
const PhaseMoveToPointDForDrag = 23f0
const PhaseDragDESecond = 24f0
const PhaseDragEK = 25f0
const PhaseEndLift = 26f0

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(
        state.line, state.point_a, state.point_b, state.point_c, state.point_d,
        state.point_e, state.point_k, state.label_a, state.label_b, state.label_c,
        state.label_d, state.label_e, state.label_k, phase, timer)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - Theorem 4

If we have given any finite number of points situated upon a straight line, we can always arrange them in a sequence A, B, C, D, E, ... , K so that B shall lie between A and C, D, E, ... , K; C between A, B and D, E, ... , K; D between A, B, C and E, ... , K, etc. Aside from this order of sequence, there exists but one other possessing this property, namely, the reverse order K, ... , E, D, C, B, A."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - Theorem 4}

If we have given any finite number of points situated upon a straight line \euclidline[color=grey60,length=3,thickness=4], we can always arrange them in a sequence $A, B, C, D, E, ... , K$ so that $B$ \euclidpoint[color=palevioletred1,size=1] shall lie between $A$ and $C, D, E, ... , K$; $C$ \euclidpoint[color=khaki3,size=1] between $A, B$ and $D, E, ... , K$; $D$ between $A, B, C$ and $E, ... , K$, etc. Aside from this order of sequence, there exists but one other possessing this property, namely, the reverse order $K, ... , E, D, C, B, A$."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset the animation cycle while preserving its native handles."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    line_host_id = state.line.host
    line_joint1_id = state.line.joint1
    line_joint2_id = state.line.joint2
    point_a_id = state.point_a
    point_b_id = state.point_b
    point_c_id = state.point_c
    point_d_id = state.point_d
    point_e_id = state.point_e
    point_k_id = state.point_k
    label_a_id = state.label_a
    label_b_id = state.label_b
    label_c_id = state.label_c
    label_d_id = state.label_d
    label_e_id = state.label_e
    label_k_id = state.label_k

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [line_host_id,
         point_a_id, point_b_id, point_c_id, point_d_id, point_e_id, point_k_id,
         label_a_id, label_b_id, label_c_id, label_d_id, label_e_id, label_k_id])

    OdinJuliaBridge.set_point_position(state_ptr, line_joint1_id, LineStart)
    OdinJuliaBridge.set_point_position(state_ptr, line_joint2_id, LineStart)

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, LineColor)

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhaseDescend, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    line = OdinJuliaBridge.create_new_line(
        state_ptr, LineStart, LineStart, LineColor, 0f0)
    point_a = OdinJuliaBridge.create_new_point(
        state_ptr, PointA, PointAColor, 0f0)
    point_b = OdinJuliaBridge.create_new_point(
        state_ptr, PointB, PointBColor, 0f0)
    point_c = OdinJuliaBridge.create_new_point(
        state_ptr, PointC, PointCColor, 0f0)
    point_d = OdinJuliaBridge.create_new_point(
        state_ptr, PointD, PointDColor, 0f0)
    point_e = OdinJuliaBridge.create_new_point(
        state_ptr, PointE, PointEColor, 0f0)
    point_k = OdinJuliaBridge.create_new_point(
        state_ptr, PointK, PointKColor, 0f0)
    label_a = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', ALabelPoint, LabelColor, 16f0)
    label_b = OdinJuliaBridge.create_new_label(
        state_ptr, 'B', BLabelPoint, LabelColor, 16f0)
    label_c = OdinJuliaBridge.create_new_label(
        state_ptr, 'C', CLabelPoint, LabelColor, 16f0)
    label_d = OdinJuliaBridge.create_new_label(
        state_ptr, 'D', DLabelPoint, LabelColor, 16f0)
    label_e = OdinJuliaBridge.create_new_label(
        state_ptr, 'E', ELabelPoint, LabelColor, 16f0)
    label_k = OdinJuliaBridge.create_new_label(
        state_ptr, 'K', KLabelPoint, LabelColor, 16f0)

    state = AnimationState(
        LineIds(line.host_id, line.joint1_id, line.joint2_id),
        point_a.index, point_b.index, point_c.index, point_d.index,
        point_e.index, point_k.index, label_a.index, label_b.index,
        label_c.index, label_d.index, label_e.index, label_k.index,
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
    line_host_id = state.line.host
    line_joint1_id = state.line.joint1
    line_joint2_id = state.line.joint2
    point_a_id = state.point_a
    point_b_id = state.point_b
    point_c_id = state.point_c
    point_d_id = state.point_d
    point_e_id = state.point_e
    point_k_id = state.point_k
    label_a_id = state.label_a
    label_b_id = state.label_b
    label_c_id = state.label_c
    label_d_id = state.label_d
    label_e_id = state.label_e
    label_k_id = state.label_k

    if line_host_id < 0
        return
    end

    phase = state.phase
    timer = state.timer

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, LineStart[1], LineStart[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawLine
            timer = 0f0
        end
    elseif phase == PhaseDrawLine
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawLineDuration,
            LineStart, LineEnd;
            penbrush=LineMaxBrush,
            pencolor=LineColor,
            line_host_id=line_host_id,
            line_joint1_id=line_joint1_id,
            line_joint2_id=line_joint2_id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseMoveToPointA
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            LineEnd, PointA, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePutPointA
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_a_id)
        end
    elseif phase == PhasePutPointA
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointTrailDuration, PointA,
            PointMaxBrush, PointAColor, point_a_id)

        timer += dt
        if timer >= PointTrailDuration
            phase = PhaseMoveToPointB
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointA, PointB, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePutPointB
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_b_id)
        end
    elseif phase == PhasePutPointB
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointTrailDuration, PointB,
            PointMaxBrush, PointBColor, point_b_id)

        timer += dt
        if timer >= PointTrailDuration
            phase = PhaseMoveToPointC
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointC
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointB, PointC, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePutPointC
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_c_id)
        end
    elseif phase == PhasePutPointC
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointTrailDuration, PointC,
            PointMaxBrush, PointCColor, point_c_id)

        timer += dt
        if timer >= PointTrailDuration
            phase = PhaseMoveToPointD
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointD
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointC, PointD, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePutPointD
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_d_id)
        end
    elseif phase == PhasePutPointD
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointTrailDuration, PointD,
            PointMaxBrush, PointDColor, point_d_id)

        timer += dt
        if timer >= PointTrailDuration
            phase = PhaseMoveToPointE
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointE
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointD, PointE, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePutPointE
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_e_id)
        end
    elseif phase == PhasePutPointE
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointTrailDuration, PointE,
            PointMaxBrush, PointEColor, point_e_id)

        timer += dt
        if timer >= PointTrailDuration
            phase = PhaseMoveToPointK
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointK
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointE, PointK, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePutPointK
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_k_id)
        end
    elseif phase == PhasePutPointK
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointTrailDuration, PointK,
            PointMaxBrush, PointKColor, point_k_id)

        timer += dt
        if timer >= PointTrailDuration
            phase = PhaseMoveToPointAForDrag
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointAForDrag
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointK, PointA, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragAB
            timer = 0f0
        end
    elseif phase == PhaseDragAB
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragSegmentDuration,
            PointA, PointB, PointBColor)

        timer += dt
        if timer >= DragSegmentDuration
            phase = PhaseDragBK
            timer = 0f0
        end
    elseif phase == PhaseDragBK
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragSegmentDuration,
            PointB, PointK, PointBColor)

        timer += dt
        if timer >= DragSegmentDuration
            phase = PhaseMoveToPointCForDrag
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointCForDrag
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointK, PointC, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragCD
            timer = 0f0
        end
    elseif phase == PhaseDragCD
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragSegmentDuration,
            PointC, PointD, PointDColor)

        timer += dt
        if timer >= DragSegmentDuration
            phase = PhaseDragDE
            timer = 0f0
        end
    elseif phase == PhaseDragDE
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragSegmentDuration,
            PointD, PointE, PointDColor)

        timer += dt
        if timer >= DragSegmentDuration
            phase = PhaseMoveToPointBForDrag
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointBForDrag
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointE, PointB, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragBC
            timer = 0f0
        end
    elseif phase == PhaseDragBC
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragSegmentDuration,
            PointB, PointC, PointCColor)

        timer += dt
        if timer >= DragSegmentDuration
            phase = PhaseDragCK
            timer = 0f0
        end
    elseif phase == PhaseDragCK
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragSegmentDuration,
            PointC, PointK, PointCColor)

        timer += dt
        if timer >= DragSegmentDuration
            phase = PhaseMoveToPointDForDrag
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointDForDrag
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointK, PointD, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragDESecond
            timer = 0f0
        end
    elseif phase == PhaseDragDESecond
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragSegmentDuration,
            PointD, PointE, PointEColor)

        timer += dt
        if timer >= DragSegmentDuration
            phase = PhaseDragEK
            timer = 0f0
        end
    elseif phase == PhaseDragEK
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragSegmentDuration,
            PointE, PointK, PointEColor)

        timer += dt
        if timer >= DragSegmentDuration
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ, PointK[1], PointK[2])

        timer += dt
        if timer >= EndLiftDuration
            reset_cycle_state(state_ptr, state)
            return
        end
    end

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, phase, timer))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return
end

end
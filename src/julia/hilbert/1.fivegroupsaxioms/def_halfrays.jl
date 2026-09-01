module HilbertChapterOneDefHalfRays

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

export get_view_text, initialize, clean, loop, animation_entry

const LineStart = [0.14f0, 0.52f0, 0f0]
const LineEnd = [0.86f0, 0.52f0, 0f0]
const PointA = [0.31f0, 0.52f0, 0f0]
const PointAPrime = [0.41f0, 0.52f0, 0f0]
const PointO = [0.55f0, 0.52f0, 0f0]
const PointB = [0.72f0, 0.52f0, 0f0]
const HalfRayLeftEnd = [0.08f0, 0.52f0, 0f0]
const HalfRayRightEnd = [0.92f0, 0.52f0, 0f0]
const PenTopZ = 1.4f0

const ALabelPoint = PointA + [-0.02f0, 0.072f0, 0f0]
const APrimeLabelPoint = PointAPrime + [0.012f0, 0.072f0, 0f0]
const OLabelPoint = PointO + [-0.008f0, 0.078f0, 0f0]
const BLabelPoint = PointB + [0.0f0, 0.072f0, 0f0]

const LabelColor = :plum1
const LineColor = :grey60
const PointAColor = :steelblue
const PointAPrimeColor = :steelblue
const PointOColor = :khaki3
const PointBColor = :palevioletred1
const LineMaxBrush = 5f0
const PointMaxBrush = 5f0

const DescendDuration = 1.8f0
const DrawLineDuration = 3.8f0
const ArcMoveDuration = 1.4f0
const DrawPointDuration = 1.5f0
const DragDuration = 2.2f0
const EndLiftDuration = 1.8f0
const FinalHoldDuration = 0.9f0

struct AnimationState
    line_host::Int64
    line_joint1::Int64
    line_joint2::Int64
    point_a::Int64
    point_a_prime::Int64
    point_o::Int64
    point_b::Int64
    label_a::Int64
    label_a_prime::Int64
    label_o::Int64
    label_b::Int64
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhaseDescend = 0f0
const PhaseDrawLine = 1f0
const PhaseMoveToPointA = 2f0
const PhasePutPointA = 3f0
const PhaseMoveToPointAPrime = 4f0
const PhasePutPointAPrime = 5f0
const PhaseMoveToPointO = 6f0
const PhasePutPointO = 7f0
const PhaseMoveToPointB = 8f0
const PhasePutPointB = 9f0
const PhaseMoveToPointOForLeftHalfRay = 10f0
const PhaseDragLeftHalfRay = 11f0
const PhaseMoveToPointOForRightHalfRay = 12f0
const PhaseDragRightHalfRay = 13f0
const PhaseEndLift = 14f0
const PhaseFinalHold = 15f0

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(
        state.line_host, state.line_joint1, state.line_joint2,
        state.point_a, state.point_a_prime, state.point_o, state.point_b,
        state.label_a, state.label_a_prime, state.label_o, state.label_b,
        phase, timer)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - Definition: Half-rays

If A, A', O, B are four points of a straight line a, where O lies between A and B but not between A and A', then points A and A' are on the same side of O, and points A and B are on different sides of O.

All points of a that lie on the same side of O, taken together, are called a half-ray emanating from O."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - Definition}: \textit{Half-rays}

If $A$ \euclidpoint[color=steelblue,size=1], $A'$ \euclidpoint[color=steelblue,size=1], $O$ \euclidpoint[color=khaki3,size=1], $B$ \euclidpoint[color=palevioletred1,size=1] are four points of a straight line $a$ \euclidline[color=grey60,length=3,thickness=4], where $O$ \euclidpoint[color=khaki3,size=1] lies between $A$ \euclidpoint[color=steelblue,size=1] and $B$ \euclidpoint[color=palevioletred1,size=1] but not between $A$ \euclidpoint[color=steelblue,size=1] and $A'$ \euclidpoint[color=steelblue,size=1], then points $A$ \euclidpoint[color=steelblue,size=1] and $A'$ \euclidpoint[color=steelblue,size=1] are on the same side of $O$ \euclidpoint[color=khaki3,size=1], and points $A$ \euclidpoint[color=steelblue,size=1] and $B$ \euclidpoint[color=palevioletred1,size=1] are on different sides of $O$ \euclidpoint[color=grey60,size=1].

All points of a that lie on the same side of $O$ \euclidpoint[color=khaki3,size=1], taken together, are called a half-ray emanating from $O$ \euclidpoint[color=khaki3,size=1]."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset the animation objects and transactionally restart cycle timing."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    line_host_id = state.line_host
    line_joint1_id = state.line_joint1
    line_joint2_id = state.line_joint2
    point_a_id = state.point_a
    point_a_prime_id = state.point_a_prime
    point_o_id = state.point_o
    point_b_id = state.point_b
    label_a_id = state.label_a
    label_a_prime_id = state.label_a_prime
    label_o_id = state.label_o
    label_b_id = state.label_b

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [line_host_id,
         point_a_id, point_a_prime_id, point_o_id, point_b_id,
         label_a_id, label_a_prime_id, label_o_id, label_b_id])

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhaseDescend, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.set_point_position(state_ptr, line_joint1_id, LineStart)
    OdinJuliaBridge.set_point_position(state_ptr, line_joint2_id, LineStart)

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, LineColor)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    line = OdinJuliaBridge.create_new_line(
        state_ptr, LineStart, LineStart, LineColor, 0f0)
    point_a = OdinJuliaBridge.create_new_point(
        state_ptr, PointA, PointAColor, 0f0)
    point_a_prime = OdinJuliaBridge.create_new_point(
        state_ptr, PointAPrime, PointAPrimeColor, 0f0)
    point_o = OdinJuliaBridge.create_new_point(
        state_ptr, PointO, PointOColor, 0f0)
    point_b = OdinJuliaBridge.create_new_point(
        state_ptr, PointB, PointBColor, 0f0)

    label_a = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', ALabelPoint, LabelColor, 16f0)
    label_a_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'A', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        APrimeLabelPoint, LabelColor, 16f0)
    label_o = OdinJuliaBridge.create_new_label(
        state_ptr, 'O', OLabelPoint, LabelColor, 16f0)
    label_b = OdinJuliaBridge.create_new_label(
        state_ptr, 'B', BLabelPoint, LabelColor, 16f0)

    state = AnimationState(
        line.host_id, line.joint1_id, line.joint2_id,
        point_a.index, point_a_prime.index, point_o.index, point_b.index,
        label_a.index, label_a_prime.index, label_o.index, label_b.index,
        PhaseDescend, 0f0)
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
    line_host_id = state.line_host
    line_joint1_id = state.line_joint1
    line_joint2_id = state.line_joint2
    point_a_id = state.point_a
    point_a_prime_id = state.point_a_prime
    point_o_id = state.point_o
    point_b_id = state.point_b
    label_a_id = state.label_a
    label_a_prime_id = state.label_a_prime
    label_o_id = state.label_o
    label_b_id = state.label_b

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
            state_ptr, timer, DrawPointDuration, PointA,
            PointMaxBrush, PointAColor, point_a_id)

        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseMoveToPointAPrime
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointAPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointA, PointAPrime, 0.2f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePutPointAPrime
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_a_prime_id)
        end
    elseif phase == PhasePutPointAPrime
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointAPrime,
            PointMaxBrush, PointAPrimeColor, point_a_prime_id)

        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseMoveToPointO
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointO
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointAPrime, PointO, 0.2f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePutPointO
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_o_id)
        end
    elseif phase == PhasePutPointO
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointO,
            PointMaxBrush, PointOColor, point_o_id)

        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseMoveToPointB
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointO, PointB, 0.2f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePutPointB
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_b_id)
        end
    elseif phase == PhasePutPointB
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointB,
            PointMaxBrush, PointBColor, point_b_id)

        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseMoveToPointOForLeftHalfRay
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointOForLeftHalfRay
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointB, PointO, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragLeftHalfRay
            timer = 0f0
            OdinJuliaBridge.set_pen_active(state_ptr, 0, PointOColor)
        end
    elseif phase == PhaseDragLeftHalfRay
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration,
            PointO, HalfRayLeftEnd, PointOColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseMoveToPointOForRightHalfRay
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointOForRightHalfRay
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            HalfRayLeftEnd, PointO, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragRightHalfRay
            timer = 0f0
        end
    elseif phase == PhaseDragRightHalfRay
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration,
            PointO, HalfRayRightEnd, PointOColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ,
            HalfRayRightEnd[1], HalfRayRightEnd[2])

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

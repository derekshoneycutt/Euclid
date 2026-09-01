module HilbertChapterOneAxiomIV3

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

export get_view_text, initialize, clean, loop, animation_entry

const LineAStart = [0.14f0, 0.66f0, 0f0]
const LineAEnd = [0.86f0, 0.66f0, 0f0]
const LineAPrimeStart = [0.14f0, 0.34f0, 0f0]
const LineAPrimeEnd = [0.86f0, 0.34f0, 0f0]

const PointA = [0.30f0, 0.66f0, 0f0]
const PointB = [0.46f0, 0.66f0, 0f0]
const PointC = [0.62f0, 0.66f0, 0f0]
const PointAPrime = [0.30f0, 0.34f0, 0f0]
const PointBPrime = [0.46f0, 0.34f0, 0f0]
const PointCPrime = [0.62f0, 0.34f0, 0f0]

const PenTopZ = 1.4f0

const LabelColor = :plum1
const DragColor = :lightgreen
const LineAColor = :steelblue
const LineAPrimeColor = :khaki3
const PointAColor = :palevioletred1
const PointBColor = :khaki3
const PointCColor = :grey60
const PointAPrimeColor = :palevioletred1
const PointBPrimeColor = :steelblue
const PointCPrimeColor = :grey60
const LineMaxBrush = 5f0
const PointMaxBrush = 5f0

const LabelAPoint = PointA + [0f0, 0.07f0, 0f0]
const LabelBPoint = PointB + [0f0, 0.07f0, 0f0]
const LabelCPoint = PointC + [0f0, 0.07f0, 0f0]
const LabelaPoint = LineAStart + [0.03f0, 0.06f0, 0f0]
const LabelAPrimePoint = PointAPrime + [0f0, 0.07f0, 0f0]
const LabelBPrimePoint = PointBPrime + [0f0, 0.07f0, 0f0]
const LabelCPrimePoint = PointCPrime + [0f0, 0.07f0, 0f0]
const LabelAPrimeLinePoint = LineAPrimeStart + [0.03f0, 0.06f0, 0f0]

const DescendDuration = 1.8f0
const DrawLineDuration = 2.6f0
const ArcMoveDuration = 1.4f0
const PointDrawDuration = 1.6f0
const DragDuration = 1.5f0
const EndLiftDuration = 1.8f0
const FinalHoldDuration = 0.9f0

"""Stable native handles for one line owned by the animation."""
struct LineIds
    host::Int64
    joint1::Int64
    joint2::Int64
end

"""Complete immutable state for one Axiom IV,3 animation generation."""
struct AnimationState
    line_a::LineIds
    line_a_prime::LineIds
    point_a::Int64
    point_b::Int64
    point_c::Int64
    point_a_prime::Int64
    point_b_prime::Int64
    point_c_prime::Int64
    label_a::Int64
    label_b::Int64
    label_c::Int64
    label_a_prime::Int64
    label_b_prime::Int64
    label_c_prime::Int64
    label_line_a::Int64
    label_line_a_prime::Int64
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhaseDescend = 0f0
const PhaseDrawLineA = 1f0
const PhaseMoveToA = 2f0
const PhaseDrawA = 3f0
const PhaseMoveToB = 4f0
const PhaseDrawB = 5f0
const PhaseMoveToC = 6f0
const PhaseDrawC = 7f0
const PhaseMoveToLineAPrimeStart = 8f0
const PhaseDrawLineAPrime = 9f0
const PhaseMoveToAPrime = 10f0
const PhaseDrawAPrime = 11f0
const PhaseMoveToBPrime = 12f0
const PhaseDrawBPrime = 13f0
const PhaseMoveToCPrime = 14f0
const PhaseDrawCPrime = 15f0
const PhaseArcToA = 16f0
const PhaseDragAToB = 17f0
const PhaseDragBToA = 18f0
const PhaseArcToAPrime = 19f0
const PhaseDragAPrimeToBPrime = 20f0
const PhaseDragBPrimeToAPrime = 21f0
const PhaseArcToB = 22f0
const PhaseDragBToC = 23f0
const PhaseDragCToB = 24f0
const PhaseArcToBPrime = 25f0
const PhaseDragBPrimeToCPrime = 26f0
const PhaseDragCPrimeToBPrime = 27f0
const PhaseArcToASecond = 28f0
const PhaseDragAToC = 29f0
const PhaseDragCToA = 30f0
const PhaseArcToAPrimeSecond = 31f0
const PhaseDragAPrimeToCPrime = 32f0
const PhaseDragCPrimeToAPrime = 33f0
const PhaseEndLift = 34f0
const PhaseFinalHold = 35f0

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(
        state.line_a, state.line_a_prime, state.point_a, state.point_b,
        state.point_c, state.point_a_prime, state.point_b_prime,
        state.point_c_prime, state.label_a, state.label_b, state.label_c,
        state.label_a_prime, state.label_b_prime, state.label_c_prime,
        state.label_line_a, state.label_line_a_prime, phase, timer)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - Axiom IV,3

IV, 3. Let AB and BC be two segments of a straight line a which have no points in common aside from the point B, and, furthermore, let A'B' and B'C' be two segments of the same or of another straight line a' having, likewise, no point other than B' in common. Then, if AB ≡ A'B' and BC ≡ B'C', we have AC ≡ A'C'."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - Axiom IV,3}

\textbf{IV, 3.} Let $AB$ \euclidline[color=steelblue,length=3,thickness=4] and $BC$ \euclidline[color=steelblue,length=3,thickness=4] be two segments
of a straight line $a$ \euclidline[color=steelblue,length=3,thickness=4] which have no points in common aside from the point $B$ \euclidpoint[color=khaki3,size=1],
and, furthermore, let $A'B'$ \euclidline[color=khaki3,length=3,thickness=4] and $B'C'$ \euclidline[color=khaki3,length=3,thickness=4] be two segments of the same
or of another straight line $a'$ \euclidline[color=khaki3,length=3,thickness=4] having, likewise, no point other than $B'$ \euclidpoint[color=steelblue,size=1] in common.
Then, if $AB$ \euclidline[color=steelblue,length=3,thickness=4] $\equiv A'B'$ \euclidline[color=khaki3,length=3,thickness=4] and
$BC$ \euclidline[color=steelblue,length=3,thickness=4] $\equiv B'C'$ \euclidline[color=khaki3,length=3,thickness=4],
we have $AC$ \euclidline[color=steelblue,length=3,thickness=4] $\equiv A'C'$ \euclidline[color=khaki3,length=3,thickness=4]."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset the animation cycle and transactionally publish its initial timing."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    line_a_host_id = state.line_a.host
    line_a_joint1_id = state.line_a.joint1
    line_a_joint2_id = state.line_a.joint2
    line_a_prime_host_id = state.line_a_prime.host
    line_a_prime_joint1_id = state.line_a_prime.joint1
    line_a_prime_joint2_id = state.line_a_prime.joint2

    point_a_id = state.point_a
    point_b_id = state.point_b
    point_c_id = state.point_c
    point_a_prime_id = state.point_a_prime
    point_b_prime_id = state.point_b_prime
    point_c_prime_id = state.point_c_prime

    label_a_id = state.label_a
    label_b_id = state.label_b
    label_c_id = state.label_c
    label_a_prime_id = state.label_a_prime
    label_b_prime_id = state.label_b_prime
    label_c_prime_id = state.label_c_prime
    labela_id = state.label_line_a
    label_a_prime_line_id = state.label_line_a_prime

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [line_a_host_id, line_a_prime_host_id,
         point_a_id, point_b_id, point_c_id,
         point_a_prime_id, point_b_prime_id, point_c_prime_id,
         label_a_id, label_b_id, label_c_id,
         label_a_prime_id, label_b_prime_id, label_c_prime_id,
         labela_id, label_a_prime_line_id])

    OdinJuliaBridge.set_point_position(state_ptr, line_a_joint1_id, LineAStart)
    OdinJuliaBridge.set_point_position(state_ptr, line_a_joint2_id, LineAStart)
    OdinJuliaBridge.set_point_position(
        state_ptr, line_a_prime_joint1_id, LineAPrimeStart)
    OdinJuliaBridge.set_point_position(
        state_ptr, line_a_prime_joint2_id, LineAPrimeStart)

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhaseDescend, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, LineAColor)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    line_a = OdinJuliaBridge.create_new_line(
        state_ptr, LineAStart, LineAStart,
        LineAColor, 0f0)
    line_a_prime = OdinJuliaBridge.create_new_line(
        state_ptr, LineAPrimeStart, LineAPrimeStart,
        LineAPrimeColor, 0f0)

    point_a = OdinJuliaBridge.create_new_point(state_ptr, PointA, PointAColor, 0f0)
    point_b = OdinJuliaBridge.create_new_point(state_ptr, PointB, PointBColor, 0f0)
    point_c = OdinJuliaBridge.create_new_point(state_ptr, PointC, PointCColor, 0f0)
    point_a_prime = OdinJuliaBridge.create_new_point(
        state_ptr, PointAPrime, PointAPrimeColor, 0f0)
    point_b_prime = OdinJuliaBridge.create_new_point(
        state_ptr, PointBPrime, PointBPrimeColor, 0f0)
    point_c_prime = OdinJuliaBridge.create_new_point(
        state_ptr, PointCPrime, PointCPrimeColor, 0f0)

    label_a = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', LabelAPoint, LabelColor, 16f0)
    label_b = OdinJuliaBridge.create_new_label(
        state_ptr, 'B', LabelBPoint, LabelColor, 16f0)
    label_c = OdinJuliaBridge.create_new_label(
        state_ptr, 'C', LabelCPoint, LabelColor, 16f0)
    labela = OdinJuliaBridge.create_new_label(
        state_ptr, 'a', LabelaPoint, LabelColor, 16f0)
    label_a_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'A', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelAPrimePoint, LabelColor, 16f0)
    label_b_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'B', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelBPrimePoint, LabelColor, 16f0)
    label_c_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'C', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelCPrimePoint, LabelColor, 16f0)
    label_a_prime_line = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'a', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelAPrimeLinePoint, LabelColor, 16f0)

    state = AnimationState(
        LineIds(line_a.host_id, line_a.joint1_id, line_a.joint2_id),
        LineIds(line_a_prime.host_id, line_a_prime.joint1_id,
            line_a_prime.joint2_id),
        point_a.index, point_b.index, point_c.index, point_a_prime.index,
        point_b_prime.index, point_c_prime.index, label_a.index, label_b.index,
        label_c.index, label_a_prime.index, label_b_prime.index,
        label_c_prime.index, labela.index, label_a_prime_line.index,
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
    line_a_host_id = state.line_a.host
    line_a_joint1_id = state.line_a.joint1
    line_a_joint2_id = state.line_a.joint2
    line_a_prime_host_id = state.line_a_prime.host
    line_a_prime_joint1_id = state.line_a_prime.joint1
    line_a_prime_joint2_id = state.line_a_prime.joint2

    point_a_id = state.point_a
    point_b_id = state.point_b
    point_c_id = state.point_c
    point_a_prime_id = state.point_a_prime
    point_b_prime_id = state.point_b_prime
    point_c_prime_id = state.point_c_prime

    label_a_id = state.label_a
    label_b_id = state.label_b
    label_c_id = state.label_c
    label_a_prime_id = state.label_a_prime
    label_b_prime_id = state.label_b_prime
    label_c_prime_id = state.label_c_prime
    labela_id = state.label_line_a
    label_a_prime_line_id = state.label_line_a_prime

    if line_a_host_id < 0 || line_a_prime_host_id < 0
        return
    end

    phase = state.phase
    timer = state.timer

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, LineAStart[1], LineAStart[2])

        timer += dt
        if timer >= DescendDuration
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
            phase = PhaseMoveToA
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labela_id)
        end
    elseif phase == PhaseMoveToA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, LineAEnd, PointA, 0.24f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawA
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_a_id)
        end
    elseif phase == PhaseDrawA
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, PointA,
            PointMaxBrush, PointAColor, point_a_id)

        timer += dt
        if timer >= PointDrawDuration
            phase = PhaseMoveToB
            timer = 0f0
        end
    elseif phase == PhaseMoveToB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointA, PointB, 0.18f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawB
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_b_id)
        end
    elseif phase == PhaseDrawB
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, PointB,
            PointMaxBrush, PointBColor, point_b_id)

        timer += dt
        if timer >= PointDrawDuration
            phase = PhaseMoveToC
            timer = 0f0
        end
    elseif phase == PhaseMoveToC
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointB, PointC, 0.18f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawC
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_c_id)
        end
    elseif phase == PhaseDrawC
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, PointC,
            PointMaxBrush, PointCColor, point_c_id)

        timer += dt
        if timer >= PointDrawDuration
            phase = PhaseMoveToLineAPrimeStart
            timer = 0f0
        end
    elseif phase == PhaseMoveToLineAPrimeStart
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointC, LineAPrimeStart, 0.26f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawLineAPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawLineAPrime
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawLineDuration,
            LineAPrimeStart, LineAPrimeEnd;
            penbrush=LineMaxBrush,
            pencolor=LineAPrimeColor,
            line_host_id=line_a_prime_host_id,
            line_joint1_id=line_a_prime_joint1_id,
            line_joint2_id=line_a_prime_joint2_id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseMoveToAPrime
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_a_prime_line_id)
        end
    elseif phase == PhaseMoveToAPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, LineAPrimeEnd,
            PointAPrime, 0.24f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawAPrime
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_a_prime_id)
        end
    elseif phase == PhaseDrawAPrime
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, PointAPrime,
            PointMaxBrush, PointAPrimeColor, point_a_prime_id)

        timer += dt
        if timer >= PointDrawDuration
            phase = PhaseMoveToBPrime
            timer = 0f0
        end
    elseif phase == PhaseMoveToBPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointAPrime,
            PointBPrime, 0.18f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawBPrime
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_b_prime_id)
        end
    elseif phase == PhaseDrawBPrime
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, PointBPrime,
            PointMaxBrush, PointBPrimeColor, point_b_prime_id)

        timer += dt
        if timer >= PointDrawDuration
            phase = PhaseMoveToCPrime
            timer = 0f0
        end
    elseif phase == PhaseMoveToCPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointBPrime,
            PointCPrime, 0.18f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawCPrime
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_c_prime_id)
        end
    elseif phase == PhaseDrawCPrime
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, PointCPrime,
            PointMaxBrush, PointCPrimeColor, point_c_prime_id)

        timer += dt
        if timer >= PointDrawDuration
            phase = PhaseArcToA
            timer = 0f0
        end
    elseif phase == PhaseArcToA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointCPrime, PointA, 0.24f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragAToB
            timer = 0f0
        end
    elseif phase == PhaseDragAToB
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointA, PointB, DragColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseDragBToA
            timer = 0f0
        end
    elseif phase == PhaseDragBToA
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointB, PointA, DragColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseArcToAPrime
            timer = 0f0
        end
    elseif phase == PhaseArcToAPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointA, PointAPrime, 0.24f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragAPrimeToBPrime
            timer = 0f0
        end
    elseif phase == PhaseDragAPrimeToBPrime
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointAPrime, PointBPrime, DragColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseDragBPrimeToAPrime
            timer = 0f0
        end
    elseif phase == PhaseDragBPrimeToAPrime
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointBPrime, PointAPrime, DragColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseArcToB
            timer = 0f0
        end
    elseif phase == PhaseArcToB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointAPrime, PointB, 0.24f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragBToC
            timer = 0f0
        end
    elseif phase == PhaseDragBToC
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointB, PointC, DragColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseDragCToB
            timer = 0f0
        end
    elseif phase == PhaseDragCToB
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointC, PointB, DragColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseArcToBPrime
            timer = 0f0
        end
    elseif phase == PhaseArcToBPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointB, PointBPrime, 0.24f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragBPrimeToCPrime
            timer = 0f0
        end
    elseif phase == PhaseDragBPrimeToCPrime
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointBPrime, PointCPrime, DragColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseDragCPrimeToBPrime
            timer = 0f0
        end
    elseif phase == PhaseDragCPrimeToBPrime
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointCPrime, PointBPrime, DragColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseArcToASecond
            timer = 0f0
        end
    elseif phase == PhaseArcToASecond
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointBPrime, PointA, 0.24f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragAToC
            timer = 0f0
        end
    elseif phase == PhaseDragAToC
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointA, PointC, DragColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseDragCToA
            timer = 0f0
        end
    elseif phase == PhaseDragCToA
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointC, PointA, DragColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseArcToAPrimeSecond
            timer = 0f0
        end
    elseif phase == PhaseArcToAPrimeSecond
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointA, PointAPrime, 0.24f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragAPrimeToCPrime
            timer = 0f0
        end
    elseif phase == PhaseDragAPrimeToCPrime
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointAPrime, PointCPrime, DragColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseDragCPrimeToAPrime
            timer = 0f0
        end
    elseif phase == PhaseDragCPrimeToAPrime
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointCPrime, PointAPrime, DragColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ, PointAPrime[1], PointAPrime[2])

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

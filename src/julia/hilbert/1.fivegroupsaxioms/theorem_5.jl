module HilbertChapterOneTheorem5

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

export get_view_text, initialize, clean, loop

const LineStart = [0.14f0, 0.50f0, 0f0]
const LineEnd = [0.86f0, 0.50f0, 0f0]

const PointA = [0.34f0, 0.57f0, 0f0]
const PointB = [0.58f0, 0.28f0, 0f0]
const PointAPrime = [0.55f0, 0.74f0, 0f0]
const PenTopZ = 1.4f0

const AlphaLabelPoint = [0.12f0, 0.87f0, 0f0]
const LineLabelPoint = [0.80f0, 0.58f0, 0f0]
const ALabelPoint = PointA + [-0.02f0, 0.015f0, 0f0]
const BLabelPoint = PointB + [0.01f0, -0.02f0, 0f0]
const APrimeLabelPoint = PointAPrime + [0.034f0, 0.058f0, 0f0]

const LabelColor = :plum1
const LineColor = :grey60
const PointAColor = :steelblue
const PointBColor = :palevioletred1
const PointAPrimeColor = :khaki3
const SegmentABColor = :steelblue
const SegmentAAPrimeColor = PointAPrimeColor

const LineMaxBrush = 5f0
const PointMaxBrush = 5f0

const DescendDuration = 1.8f0
const ArcMoveDuration = 1.9f0
const DrawLineDuration = 4.0f0
const DrawPointDuration = 1.9f0
const DrawSegmentDuration = 2.4f0
const EndLiftDuration = 1.8f0

"""Stable native handles for one line owned by the animation."""
struct LineIds
    host::Int64
    joint1::Int64
    joint2::Int64
end

"""Complete immutable state for one Theorem 5 animation generation."""
struct AnimationState
    boundary_line::LineIds
    point_a::Int64
    point_b::Int64
    point_a_prime::Int64
    segment_a_b::LineIds
    segment_a_a_prime::LineIds
    alpha_label::Int64
    line_label::Int64
    label_a::Int64
    label_b::Int64
    label_a_prime::Int64
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhaseDescendToLine = 0f0
const PhaseDrawBoundaryLine = 1f0
const PhaseMoveToPointA = 2f0
const PhasePutPointA = 3f0
const PhaseMoveToPointB = 4f0
const PhasePutPointB = 5f0
const PhaseMoveToPointAForAB = 6f0
const PhaseDrawSegmentAB = 7f0
const PhaseMoveToPointAPrime = 8f0
const PhasePutPointAPrime = 9f0
const PhaseMoveToPointAForAAPrime = 10f0
const PhaseDrawSegmentAAPrime = 11f0
const PhaseEndLift = 12f0

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(
        state.boundary_line, state.point_a, state.point_b, state.point_a_prime,
        state.segment_a_b, state.segment_a_a_prime, state.alpha_label,
        state.line_label, state.label_a, state.label_b, state.label_a_prime,
        phase, timer)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - Theorem 5

Every straight line a, which lies in a plane α, divides the remaining points of this plane into two regions having the following properties: Every point A of the one region determines with each point B of the other region a segment AB containing a point of the straight line a. On the other hand, any two points A, A' of the same region determine a segment AA' containing no point of a."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - Theorem 5}

Every straight line $a$ \euclidline[color=grey60,length=3,thickness=4], which lies in a plane $\alpha$, divides the remaining points of this plane into two regions having the following properties: Every point $A$ \euclidpoint[color=steelblue,size=1] of the one region determines with each point $B$ \euclidpoint[color=palevioletred1,size=1] of the other region a segment $AB$ \euclidline[color=steelblue,length=3,thickness=4] containing a point of the straight line $a$ \euclidline[color=grey60,length=3,thickness=4]. On the other hand, any two points $A$ \euclidpoint[color=steelblue,size=1], $A'$ \euclidpoint[color=khaki3,size=1] of the same region determine a segment $AA'$ \euclidline[color=khaki3,length=3,thickness=4] containing no point of $a$ \euclidline[color=grey60,length=3,thickness=4]."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset the animation cycle while preserving its native handles."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    boundary_line_host_id = state.boundary_line.host
    boundary_line_joint1_id = state.boundary_line.joint1
    boundary_line_joint2_id = state.boundary_line.joint2
    point_a_id = state.point_a
    point_b_id = state.point_b
    point_a_prime_id = state.point_a_prime
    segment_a_b_host_id = state.segment_a_b.host
    segment_a_b_joint1_id = state.segment_a_b.joint1
    segment_a_b_joint2_id = state.segment_a_b.joint2
    segment_a_a_prime_host_id = state.segment_a_a_prime.host
    segment_a_a_prime_joint1_id = state.segment_a_a_prime.joint1
    segment_a_a_prime_joint2_id = state.segment_a_a_prime.joint2
    alpha_label_id = state.alpha_label
    line_label_id = state.line_label
    label_a_id = state.label_a
    label_b_id = state.label_b
    label_a_prime_id = state.label_a_prime

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [boundary_line_host_id,
         point_a_id, point_b_id, point_a_prime_id,
         segment_a_b_host_id, segment_a_a_prime_host_id,
         alpha_label_id, line_label_id, label_a_id, label_b_id, label_a_prime_id])

    OdinJuliaBridge.set_point_position(state_ptr, boundary_line_joint1_id, LineStart)
    OdinJuliaBridge.set_point_position(state_ptr, boundary_line_joint2_id, LineStart)

    OdinJuliaBridge.set_point_position(state_ptr, segment_a_b_joint1_id, PointA)
    OdinJuliaBridge.set_point_position(state_ptr, segment_a_b_joint2_id, PointA)
    OdinJuliaBridge.set_point_position(state_ptr, segment_a_a_prime_joint1_id, PointA)
    OdinJuliaBridge.set_point_position(state_ptr, segment_a_a_prime_joint2_id, PointA)

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, LineColor)

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhaseDescendToLine, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    boundary_line = OdinJuliaBridge.create_new_line(
        state_ptr, LineStart, LineStart, LineColor, 0f0)
    point_a = OdinJuliaBridge.create_new_point(
        state_ptr, PointA, PointAColor, 0f0)
    point_b = OdinJuliaBridge.create_new_point(
        state_ptr, PointB, PointBColor, 0f0)
    point_a_prime = OdinJuliaBridge.create_new_point(
        state_ptr, PointAPrime, PointAPrimeColor, 0f0)

    segment_a_b = OdinJuliaBridge.create_new_line(
        state_ptr, PointA, PointA, SegmentABColor, 0f0)
    segment_a_a_prime = OdinJuliaBridge.create_new_line(
        state_ptr, PointA, PointA, SegmentAAPrimeColor, 0f0)

    alpha_label = OdinJuliaBridge.create_new_label(
        state_ptr, 'α', AlphaLabelPoint, LabelColor, 16f0)
    line_label = OdinJuliaBridge.create_new_label(
        state_ptr, 'a', LineLabelPoint, LabelColor, 16f0)
    label_a = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', ALabelPoint, LabelColor, 16f0)
    label_b = OdinJuliaBridge.create_new_label(
        state_ptr, 'B', BLabelPoint, LabelColor, 16f0)
    label_a_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'A', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        APrimeLabelPoint, LabelColor, 16f0)

    state = AnimationState(
        LineIds(boundary_line.host_id, boundary_line.joint1_id,
            boundary_line.joint2_id),
        point_a.index, point_b.index, point_a_prime.index,
        LineIds(segment_a_b.host_id, segment_a_b.joint1_id, segment_a_b.joint2_id),
        LineIds(segment_a_a_prime.host_id, segment_a_a_prime.joint1_id,
            segment_a_a_prime.joint2_id),
        alpha_label.index, line_label.index, label_a.index, label_b.index,
        label_a_prime.index, PhaseDescendToLine, 0f0)
    reset_cycle_state(state_ptr, state)
end

"""Clean any extra animation data at the end of performance"""
function clean(state_ptr::Ptr{Cvoid})
end

"""Perform an iteration of the animation loop for this animation"""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    state, status = OdinJuliaBridge.get_animation_value(state_ptr, StateKey)
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return
    boundary_line_host_id = state.boundary_line.host
    boundary_line_joint1_id = state.boundary_line.joint1
    boundary_line_joint2_id = state.boundary_line.joint2
    point_a_id = state.point_a
    point_b_id = state.point_b
    point_a_prime_id = state.point_a_prime
    segment_a_b_host_id = state.segment_a_b.host
    segment_a_b_joint1_id = state.segment_a_b.joint1
    segment_a_b_joint2_id = state.segment_a_b.joint2
    segment_a_a_prime_host_id = state.segment_a_a_prime.host
    segment_a_a_prime_joint1_id = state.segment_a_a_prime.joint1
    segment_a_a_prime_joint2_id = state.segment_a_a_prime.joint2
    alpha_label_id = state.alpha_label
    line_label_id = state.line_label
    label_a_id = state.label_a
    label_b_id = state.label_b
    label_a_prime_id = state.label_a_prime

    if boundary_line_host_id < 0
        return
    end

    phase = state.phase
    timer = state.timer

    if phase == PhaseDescendToLine
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ,
            LineStart[1], LineStart[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawBoundaryLine
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, alpha_label_id)
        end
    elseif phase == PhaseDrawBoundaryLine
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawLineDuration,
            LineStart, LineEnd;
            penbrush=LineMaxBrush,
            pencolor=LineColor,
            line_host_id=boundary_line_host_id,
            line_joint1_id=boundary_line_joint1_id,
            line_joint2_id=boundary_line_joint2_id)

        if timer / DrawLineDuration >= 0.5f0
            OdinJuliaBridge.show_point(state_ptr, line_label_id)
        end

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
            state_ptr, timer, DrawPointDuration, PointB,
            PointMaxBrush, PointBColor, point_b_id)

        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseMoveToPointAForAB
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointAForAB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointB, PointA, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawSegmentAB
            timer = 0f0
            OdinJuliaBridge.set_pen_active(state_ptr, 0, SegmentABColor)
        end
    elseif phase == PhaseDrawSegmentAB
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawSegmentDuration,
            PointA, PointB;
            penbrush=LineMaxBrush,
            pencolor=SegmentABColor,
            line_host_id=segment_a_b_host_id,
            line_joint1_id=segment_a_b_joint1_id,
            line_joint2_id=segment_a_b_joint2_id)

        timer += dt
        if timer >= DrawSegmentDuration
            phase = PhaseMoveToPointAPrime
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointAPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointB, PointAPrime, 0.22f0, 1, :none)

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
            phase = PhaseMoveToPointAForAAPrime
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointAForAAPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointAPrime, PointA, 0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawSegmentAAPrime
            timer = 0f0
            OdinJuliaBridge.set_pen_active(state_ptr, 0, SegmentAAPrimeColor)
        end
    elseif phase == PhaseDrawSegmentAAPrime
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawSegmentDuration,
            PointA, PointAPrime;
            penbrush=LineMaxBrush,
            pencolor=SegmentAAPrimeColor,
            line_host_id=segment_a_a_prime_host_id,
            line_joint1_id=segment_a_a_prime_joint1_id,
            line_joint2_id=segment_a_a_prime_joint2_id)

        timer += dt
        if timer >= DrawSegmentDuration
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ,
            PointAPrime[1], PointAPrime[2])

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

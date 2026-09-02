module HilbertChapterOneAxiomIII1

using UUIDs
using ..AnimationCatalog

const AnimationId = UUID("6fe08874-492a-50e6-a69c-b993b39369d0")

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

export get_view_text, initialize, clean, loop, animation_entry

const LineAStart = [0.14f0, 0.36f0, 0f0]
const LineAEnd = [0.84f0, 0.36f0, 0f0]
const PointA = [0.58f0, 0.68f0, 0f0]
const ParallelStart = [0.16f0, PointA[2], 0f0]
const ParallelEnd = [0.86f0, PointA[2], 0f0]
const PenTopZ = 1.4f0

const LabelColor = :plum1
const LineAColor = :steelblue
const ParallelColor = :khaki3
const PointAColor = :palevioletred1
const LineMaxBrush = 5f0
const PointMaxBrush = 5f0

const ALabelPoint = PointA + [0.02f0, 0.07f0, 0f0]
const LineaLabelPoint = LineAStart + [0.03f0, 0.06f0, 0f0]

const DescendDuration = 1.8f0
const DrawLineDuration = 3.8f0
const ArcMoveDuration = 1.8f0
const PointDrawDuration = 2f0
const EndLiftDuration = 1.8f0
const FinalHoldDuration = 0.8f0

"""Stable native handles for one line owned by the animation."""
struct LineIds
    host::Int64
    joint1::Int64
    joint2::Int64
end

"""Complete immutable state for one Axiom III,1 animation generation."""
struct AnimationState
    line_a::LineIds
    point_a::Int64
    parallel::LineIds
    label_line_a::Int64
    label_a::Int64
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhaseDescend = 0f0
const PhaseDrawLineA = 1f0
const PhaseMoveToPointA = 2f0
const PhaseDrawPointA = 3f0
const PhaseMoveToParallelStart = 4f0
const PhaseDrawParallel = 5f0
const PhaseEndLift = 6f0
const PhaseFinalHold = 7f0

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(
        state.line_a, state.point_a, state.parallel, state.label_line_a,
        state.label_a, phase, timer)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - Axiom III

III. In a plane α there can be drawn through any point A, lying outside of a straight line a, one and only one straight line which does not intersect the line a. This straight line is called the parallel to a through the given point A.

This statement of the axiom of parallels contains two assertions. The first of these is that, in the plane α, there is always a straight line passing through A which does not intersect the given line a. The second states that only one such line is possible. The latter of these statements is the essential one, and it may also be expressed as Theorem 8."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - Axiom III}

\textbf{III.} In a plane $\alpha$ there can be drawn through any point $A$ \euclidpoint[color=palevioletred1,size=1], lying outside of a straight line $a$ \euclidline[color=steelblue,length=3,thickness=4], one and only one straight line \euclidline[color=khaki3,length=3,thickness=4] which does not intersect the line $a$ \euclidline[color=steelblue,length=3,thickness=4]. This straight line \euclidline[color=khaki3,length=3,thickness=4] is called the parallel to $a$ \euclidline[color=steelblue,length=3,thickness=4] through the given point $A$ \euclidpoint[color=palevioletred1,size=1].

This statement of the axiom of parallels contains two assertions. The first of these is that, in the plane $\alpha$, there is always a straight line \euclidline[color=khaki3,length=3,thickness=4] passing through $A$ \euclidpoint[color=palevioletred1,size=1] which does not intersect the given line $a$ \euclidline[color=steelblue,length=3,thickness=4]. The second states that only one such line is possible. The latter of these statements is the essential one, and it may also be expressed as \textit{Theorem 8}."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset the animation cycle and transactionally publish its initial timing."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    line_a_host_id = state.line_a.host
    line_a_joint1_id = state.line_a.joint1
    line_a_joint2_id = state.line_a.joint2
    point_a_id = state.point_a
    parallel_host_id = state.parallel.host
    parallel_joint1_id = state.parallel.joint1
    parallel_joint2_id = state.parallel.joint2
    labela_id = state.label_line_a
    label_a_id = state.label_a

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [line_a_host_id, point_a_id, parallel_host_id, labela_id, label_a_id])

    OdinJuliaBridge.set_point_position(state_ptr, line_a_joint1_id, LineAStart)
    OdinJuliaBridge.set_point_position(state_ptr, line_a_joint2_id, LineAStart)
    OdinJuliaBridge.set_point_position(state_ptr, parallel_joint1_id, ParallelStart)
    OdinJuliaBridge.set_point_position(state_ptr, parallel_joint2_id, ParallelStart)

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
    point_a = OdinJuliaBridge.create_new_point(
        state_ptr, PointA, PointAColor, 0f0)
    parallel_line = OdinJuliaBridge.create_new_line(
        state_ptr, ParallelStart, ParallelStart,
        ParallelColor, 0f0)
    labela = OdinJuliaBridge.create_new_label(
        state_ptr, 'a', LineaLabelPoint, LabelColor, 16f0)
    label_a = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', ALabelPoint, LabelColor, 16f0)

    state = AnimationState(
        LineIds(line_a.host_id, line_a.joint1_id, line_a.joint2_id),
        point_a.index,
        LineIds(parallel_line.host_id, parallel_line.joint1_id,
            parallel_line.joint2_id),
        labela.index, label_a.index, PhaseDescend, 0f0)
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
    point_a_id = state.point_a
    parallel_host_id = state.parallel.host
    parallel_joint1_id = state.parallel.joint1
    parallel_joint2_id = state.parallel.joint2
    labela_id = state.label_line_a
    label_a_id = state.label_a

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
            phase = PhaseDrawLineA
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labela_id)
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
            phase = PhaseMoveToPointA
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            LineAEnd, PointA, 0.24f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.show_point(state_ptr, label_a_id)
            phase = PhaseDrawPointA
            timer = 0f0
        end
    elseif phase == PhaseDrawPointA
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, PointA,
            PointMaxBrush, PointAColor, point_a_id)

        timer += dt
        if timer >= PointDrawDuration
            phase = PhaseMoveToParallelStart
            timer = 0f0
        end
    elseif phase == PhaseMoveToParallelStart
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointA, ParallelStart, 0.24f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.set_pen_active(state_ptr, 0, ParallelColor)
            phase = PhaseDrawParallel
            timer = 0f0
        end
    elseif phase == PhaseDrawParallel
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawLineDuration,
            ParallelStart, ParallelEnd;
            penbrush=LineMaxBrush,
            pencolor=ParallelColor,
            line_host_id=parallel_host_id,
            line_joint1_id=parallel_joint1_id,
            line_joint2_id=parallel_joint2_id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ, ParallelEnd[1], ParallelEnd[2])

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

AnimationCatalog.animation(
    HilbertChapterOneAxiomIII1.AnimationId, HilbertChapterOneAxiomIII1.animation_entry)

module HilbertChapterOneAxiomI5

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

using LinearAlgebra

export get_view_text, initialize, clean, loop

const APoint = [0.25f0, 0.75f0, 0f0]
const BPoint = [0.75f0, 0.25f0, 0f0]
const PenTopZ = 1.4f0

const ALabelPoint = APoint + [-0.03f0, 0.01f0, 0f0]
const BLabelPoint = BPoint + [0.01f0, -0.02f0, 0f0]
const LineaLabelPoint = [0.55f0, 0.55f0, 0f0]
const LabelColor = :plum1

const LineColor = :steelblue
const PointAColor = :palevioletred1
const PointBColor = :khaki3
const SurfaceLineColorAB = :steelblue
const LineMaxBrush = 5f0
const PointMaxBrush = 5f0

const DescendDuration = 1.8f0
const DrawLineDuration = 4.2f0
const SurfaceDragDuration = 4.2f0
const SurfaceArcMoveDuration = 2.1f0
const SurfaceArcWaveHeight = 0.35f0
const EndMoveToPointADuration = 2f0
const ExtremityTrailDuration = 2f0
const EndMoveToPointBDuration = 2f0
const EndMoveToPointCDuration = 2f0
const EndLiftDuration = 1.8f0

const SurfaceSweepABStart = [0f0, 1f0, 0f0]
const SurfaceSweepABEnd = [1f0, 0f0, 0f0]

"""Complete immutable state for one Axiom I,5 animation generation."""
struct AnimationState
    line_host::Int64
    line_point_a::Int64
    line_point_b::Int64
    point_a::Int64
    point_b::Int64
    label_a::Int64
    label_b::Int64
    label_line_a::Int64
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhaseDescend = 0f0
const PhasePutPointA = 1f0
const PhaseMoveToPointB = 2f0
const PhasePutPointB = 3f0
const PhaseMoveToPointA = 6f0
const PhaseDrawLine = 7f0
const PhaseArcToSurfaceAB = 8f0
const PhaseDragSurfaceAB = 9f0
const PhaseEndLift = 14f0

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(
        state.line_host, state.line_point_a, state.line_point_b,
        state.point_a, state.point_b, state.label_a, state.label_b,
        state.label_line_a, phase, timer)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - Axiom I,5

I, 5. If two points A, B of a straight line a lie in a plane α, then every point of a lies in α.

In this case we say: "The straight line a lies in the plane α," etc."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - Axiom I,5}

\textbf{I, 5.} If two points $A$ \euclidpoint[color=palevioletred1,size=1], $B$ \euclidpoint[color=khaki3,size=1] of a straight line $a$ \euclidline[color=steelblue,length=3,thickness=4] lie in a plane $\alpha$, then every point of $a$ \euclidline[color=steelblue,length=3,thickness=4] lies in $\alpha$.

In this case we say: "The straight line $a$ \euclidline[color=steelblue,length=3,thickness=4] lies in the plane $\alpha$," etc."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset cycle timing transactionally before restoring visible animation state."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    line_host_id = state.line_host
    line_point_a_id = state.line_point_a
    line_point_b_id = state.line_point_b
    point_a_id = state.point_a
    point_b_id = state.point_b
    label_a_id = state.label_a
    label_b_id = state.label_b
    labellinea_id = state.label_line_a

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhaseDescend, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [label_a_id, label_b_id, labellinea_id,
         line_host_id, point_a_id, point_b_id,
        ])

    OdinJuliaBridge.set_point_position(
        state_ptr, line_point_a_id, APoint[1], APoint[2], APoint[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, line_point_b_id, APoint[1], APoint[2], APoint[3])

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, LineColor)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    point_a = OdinJuliaBridge.create_new_point(
        state_ptr, APoint, PointAColor, 0f0)
    point_b = OdinJuliaBridge.create_new_point(
        state_ptr, BPoint, PointBColor, 0f0)
    line = OdinJuliaBridge.create_new_line(
        state_ptr, APoint, APoint, LineColor, 0f0)
    label_a = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', ALabelPoint, LabelColor, 16f0)
    label_b = OdinJuliaBridge.create_new_label(
        state_ptr, 'B', BLabelPoint, LabelColor, 16f0)
    labellinea = OdinJuliaBridge.create_new_label(
        state_ptr, 'a', LineaLabelPoint, LabelColor, 16f0)

    state = AnimationState(
        line.host_id, line.joint1_id, line.joint2_id,
        point_a.index, point_b.index,
        label_a.index, label_b.index, labellinea.index,
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
    line_host_id = state.line_host
    line_point_a_id = state.line_point_a
    line_point_b_id = state.line_point_b
    point_a_id = state.point_a
    point_b_id = state.point_b
    label_a_id = state.label_a
    label_b_id = state.label_b
    labellinea_id = state.label_line_a

    if line_host_id < 0
        return
    end

    phase = state.phase
    timer = state.timer

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, APoint[1], APoint[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhasePutPointA
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_a_id)
        end
    elseif phase == PhasePutPointA
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, ExtremityTrailDuration, APoint,
            PointMaxBrush, PointAColor, point_a_id)

        timer += dt
        if timer >= ExtremityTrailDuration
            phase = PhaseMoveToPointB
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, EndMoveToPointBDuration,
            APoint, BPoint, 0.25f0, 1, :none)

        timer += dt
        if timer >= EndMoveToPointBDuration
            phase = PhasePutPointB
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_b_id)
        end
    elseif phase == PhasePutPointB
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, ExtremityTrailDuration, BPoint,
            PointMaxBrush, PointBColor, point_b_id)

        timer += dt
        if timer >= ExtremityTrailDuration
            phase = PhaseMoveToPointA
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, EndMoveToPointADuration,
            BPoint, APoint, 0.25f0, 1, :none)

        timer += dt
        if timer >= EndMoveToPointADuration
            phase = PhaseDrawLine
            timer = 0f0
        end
    elseif phase == PhaseDrawLine
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawLineDuration,
            APoint, BPoint;
            penbrush=LineMaxBrush,
            pencolor=LineColor,
            line_host_id=line_host_id,
            line_joint1_id=line_point_a_id,
            line_joint2_id=line_point_b_id)

        if timer / DrawLineDuration >= 0.5
            OdinJuliaBridge.show_point(state_ptr, labellinea_id)
        end

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseArcToSurfaceAB
            timer = 0f0
        end
    elseif phase == PhaseArcToSurfaceAB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, SurfaceArcMoveDuration,
            BPoint, SurfaceSweepABStart, SurfaceArcWaveHeight, 1, :none)

        timer += dt
        if timer >= SurfaceArcMoveDuration
            phase = PhaseDragSurfaceAB
            timer = 0f0
        end
    elseif phase == PhaseDragSurfaceAB
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, SurfaceDragDuration,
            SurfaceSweepABStart, SurfaceSweepABEnd, SurfaceLineColorAB)

        timer += dt
        if timer >= SurfaceDragDuration
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ,
            SurfaceSweepABEnd[1], SurfaceSweepABEnd[2])

        timer += dt
        if timer >= EndLiftDuration
            reset_cycle_state(state_ptr, state)
            return
        end
    end

    OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, phase, timer))
end

end

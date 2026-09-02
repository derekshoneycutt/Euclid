module HilbertChapterOneDefTriangleAngle

using UUIDs
using ..AnimationCatalog

const AnimationId = UUID("93310d74-5fee-5cae-b308-1e8da917a619")

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

export get_view_text, initialize, clean, loop, animation_entry

const PointA = [0.26f0, 0.44f0, 0f0]
const PointB = [0.58f0, 0.34f0, 0f0]
const PointC = [0.44f0, 0.74f0, 0f0]

const EdgeABStart = PointA
const EdgeABEnd = PointB
const EdgeACStart = PointA
const EdgeACEnd = PointC
const EdgeBCStart = PointB
const EdgeBCEnd = PointC

const VecAB = PointB - PointA
const VecAC = PointC - PointA
const ThetaAB = atan(VecAB[2], VecAB[1])
const ThetaAC = atan(VecAC[2], VecAC[1])
const AngleTheta = ThetaAC - ThetaAB

const MarkerRadius = 0.13f0
const MarkerStart = [
    PointA[1] + MarkerRadius * cos(ThetaAB),
    PointA[2] + MarkerRadius * sin(ThetaAB),
    0f0,
]
const MarkerEnd = [
    PointA[1] + MarkerRadius * cos(ThetaAB + AngleTheta),
    PointA[2] + MarkerRadius * sin(ThetaAB + AngleTheta),
    0f0,
]

const LabelColor = :plum1
const EdgeABColor = :steelblue
const EdgeACColor = :palevioletred1
const EdgeBCColor = :khaki3
const MarkerColor = :khaki3

const EdgeBrush = 5f0
const MarkerBrush = 1f0
const ResetPenLength = 0.14f0

const LabelAPoint = PointA + [-0.04f0, -0.04f0, 0f0]
const LabelBPoint = PointB + [0.02f0, -0.03f0, 0f0]
const LabelCPoint = PointC + [-0.01f0, 0.03f0, 0f0]
const LabelHPoint = PointA + [0.20f0, -0.08f0, 0f0]
const LabelKPoint = PointA + [0.16f0, 0.19f0, 0f0]

const PenTopZ = 1.4f0
const CompassTopZ = 1.4f0

const DescendDuration = 1.8f0
const DrawEdgeDuration = 2.4f0
const ArcMoveDuration = 1.4f0
const PenLiftDuration = 1.6f0
const MarkerDrawDuration = 1.2f0
const CompassLiftDuration = 1.8f0
const FinalHoldDuration = 0.9f0

struct AnimationState
    edge_a_b_host::Int64
    edge_a_b_joint1::Int64
    edge_a_b_joint2::Int64
    edge_a_c_host::Int64
    edge_a_c_joint1::Int64
    edge_a_c_joint2::Int64
    edge_b_c_host::Int64
    edge_b_c_joint1::Int64
    edge_b_c_joint2::Int64
    marker_host::Int64
    marker_start::Int64
    marker_end::Int64
    label_a::Int64
    label_b::Int64
    label_c::Int64
    label_h::Int64
    label_k::Int64
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhaseDescendToA = 0f0
const PhaseDrawAB = 1f0
const PhaseArcToAForAC = 2f0
const PhaseDrawAC = 3f0
const PhaseArcToBForBC = 4f0
const PhaseDrawBC = 5f0
const PhasePenLiftForMarker = 6f0
const PhaseDrawMarker = 7f0
const PhaseCompassLift = 8f0
const PhaseFinalHold = 9f0

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(
        state.edge_a_b_host, state.edge_a_b_joint1, state.edge_a_b_joint2,
        state.edge_a_c_host, state.edge_a_c_joint1, state.edge_a_c_joint2,
        state.edge_b_c_host, state.edge_b_c_joint1, state.edge_b_c_joint2,
        state.marker_host, state.marker_start, state.marker_end,
        state.label_a, state.label_b, state.label_c, state.label_h,
        state.label_k, phase, timer)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - Definition: Triangle Angle

Suppose we have given a triangle ABC. Denote by h, k the two half-rays emanating from A and passing respectively through B and C. The angle (h, k) is then said to be the angle included by the sides AB and AC, or the one opposite to the side BC in the triangle ABC. It contains all of the interior points of the triangle ABC and is represented by the symbol ∠BAC, or by ∠A."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - Definition}: \textit{Triangle Angle}

Suppose we have given a triangle $ABC$ \euclidtriangle[height=2,width=3,thickness=2,edge1_color=palevioletred1,edge2_color=steelblue,edge3_color=khaki3].
Denote by $h$ \euclidline[color=steelblue,length=3,thickness=4], $k$ \euclidline[color=palevioletred1,length=3,thickness=4]
the two half-rays emanating from $A$ \euclidpoint[color=plum1,size=0.5] and passing respectively through
$B$ \euclidpoint[color=plum1,size=0.5] and $C$ \euclidpoint[color=plum1,size=0.5].
The angle $(h, k)$ \euclidangle[color=khaki3,radius=2,end=60,filled] is then said to be the angle included
by the sides $AB$ \euclidline[color=steelblue,length=3,thickness=4] and $AC$ \euclidline[color=palevioletred1,length=3,thickness=4],
or the one opposite to the side $BC$ \euclidline[color=khaki3,length=3,thickness=4] in the
triangle $ABC$ \euclidtriangle[height=2,width=3,thickness=2,edge1_color=palevioletred1,edge2_color=steelblue,edge3_color=khaki3].
It contains all of the interior points of the triangle
$ABC$ \euclidtriangle[height=2,width=3,thickness=2,edge1_color=palevioletred1,edge2_color=steelblue,edge3_color=khaki3]
and is represented by the symbol $\angle BAC$ \euclidangle[color=khaki3,radius=2,end=60,filled], or by $\angle A$ \euclidangle[color=khaki3,radius=2,end=60,filled]."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset the animation objects and transactionally restart cycle timing."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    edge_a_b_host_id = state.edge_a_b_host
    edge_a_b_joint2_id = state.edge_a_b_joint2
    edge_a_c_host_id = state.edge_a_c_host
    edge_a_c_joint2_id = state.edge_a_c_joint2
    edge_b_c_host_id = state.edge_b_c_host
    edge_b_c_joint2_id = state.edge_b_c_joint2
    marker_host_id = state.marker_host
    marker_end_id = state.marker_end
    label_a_id = state.label_a
    label_b_id = state.label_b
    label_c_id = state.label_c
    label_h_id = state.label_h
    label_k_id = state.label_k

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [edge_a_b_host_id, edge_a_c_host_id, edge_b_c_host_id, marker_host_id,
         label_a_id, label_b_id, label_c_id, label_h_id, label_k_id])

    OdinJuliaBridge.set_point_position(state_ptr, edge_a_b_joint2_id, EdgeABStart)
    OdinJuliaBridge.set_point_position(state_ptr, edge_a_c_joint2_id, EdgeACStart)
    OdinJuliaBridge.set_point_position(state_ptr, edge_b_c_joint2_id, EdgeBCStart)
    OdinJuliaBridge.set_point_position(state_ptr, marker_end_id, MarkerStart)

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhaseDescendToA, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.hide_compass(state_ptr)
    OdinJuliaBridge.lock_pen_joint1(state_ptr, PointA[1], PointA[2], PenTopZ)
    OdinJuliaBridge.move_pen_joint2(
        state_ptr, PointA[1], PointA[2], PenTopZ + ResetPenLength)
    OdinJuliaBridge.lock_compass_joint1(
        state_ptr, PointA[1], PointA[2], CompassTopZ, sweep = false)
    OdinJuliaBridge.lock_compass_joint2(
        state_ptr, MarkerStart[1], MarkerStart[2], CompassTopZ, sweep = false)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeABColor)
    OdinJuliaBridge.set_compass_active(state_ptr, 0, MarkerColor)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    edge_a_b = OdinJuliaBridge.create_new_line(
        state_ptr, EdgeABStart, EdgeABStart, EdgeABColor, 0f0)
    edge_a_c = OdinJuliaBridge.create_new_line(
        state_ptr, EdgeACStart, EdgeACStart, EdgeACColor, 0f0)
    edge_b_c = OdinJuliaBridge.create_new_line(
        state_ptr, EdgeBCStart, EdgeBCStart, EdgeBCColor, 0f0)

    marker = OdinJuliaBridge.create_new_filledcircle(state_ptr,
        PointA, MarkerRadius, 0f0, 0f0,
        MarkerColor, 0f0)

    label_a = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', LabelAPoint, LabelColor, 16f0)
    label_b = OdinJuliaBridge.create_new_label(
        state_ptr, 'B', LabelBPoint, LabelColor, 16f0)
    label_c = OdinJuliaBridge.create_new_label(
        state_ptr, 'C', LabelCPoint, LabelColor, 16f0)
    label_h = OdinJuliaBridge.create_new_label(
        state_ptr, 'h', LabelHPoint, LabelColor, 16f0)
    label_k = OdinJuliaBridge.create_new_label(
        state_ptr, 'k', LabelKPoint, LabelColor, 16f0)

    state = AnimationState(
        edge_a_b.host_id, edge_a_b.joint1_id, edge_a_b.joint2_id,
        edge_a_c.host_id, edge_a_c.joint1_id, edge_a_c.joint2_id,
        edge_b_c.host_id, edge_b_c.joint1_id, edge_b_c.joint2_id,
        marker.host_id, marker.start_id, marker.end_id,
        label_a.index, label_b.index, label_c.index, label_h.index, label_k.index,
        PhaseDescendToA, 0f0)
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
    edge_a_b_host_id = state.edge_a_b_host
    edge_a_b_joint1_id = state.edge_a_b_joint1
    edge_a_b_joint2_id = state.edge_a_b_joint2
    edge_a_c_host_id = state.edge_a_c_host
    edge_a_c_joint1_id = state.edge_a_c_joint1
    edge_a_c_joint2_id = state.edge_a_c_joint2
    edge_b_c_host_id = state.edge_b_c_host
    edge_b_c_joint1_id = state.edge_b_c_joint1
    edge_b_c_joint2_id = state.edge_b_c_joint2
    marker_host_id = state.marker_host
    marker_start_id = state.marker_start
    marker_end_id = state.marker_end
    label_a_id = state.label_a
    label_b_id = state.label_b
    label_c_id = state.label_c
    label_h_id = state.label_h
    label_k_id = state.label_k

    if edge_a_b_host_id < 0 || edge_a_c_host_id < 0 || edge_b_c_host_id < 0
        return
    end

    phase = state.phase
    timer = state.timer

    if phase == PhaseDescendToA
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, PointA[1], PointA[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawAB
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_a_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeABColor)
        end
    elseif phase == PhaseDrawAB
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawEdgeDuration,
            EdgeABStart, EdgeABEnd;
            penbrush=EdgeBrush,
            pencolor=EdgeABColor,
            line_host_id=edge_a_b_host_id,
            line_joint1_id=edge_a_b_joint1_id,
            line_joint2_id=edge_a_b_joint2_id)

        timer += dt
        if timer >= DrawEdgeDuration
            phase = PhaseArcToAForAC
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_b_id)
        end
    elseif phase == PhaseArcToAForAC
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            EdgeABEnd, PointA, 0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawAC
            timer = 0f0
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeACColor)
        end
    elseif phase == PhaseDrawAC
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawEdgeDuration,
            EdgeACStart, EdgeACEnd;
            penbrush=EdgeBrush,
            pencolor=EdgeACColor,
            line_host_id=edge_a_c_host_id,
            line_joint1_id=edge_a_c_joint1_id,
            line_joint2_id=edge_a_c_joint2_id)

        timer += dt
        if timer >= DrawEdgeDuration
            phase = PhaseArcToBForBC
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_c_id)
            OdinJuliaBridge.show_point(state_ptr, label_h_id)
            OdinJuliaBridge.show_point(state_ptr, label_k_id)
        end
    elseif phase == PhaseArcToBForBC
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            EdgeACEnd, PointB, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawBC
            timer = 0f0
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeBCColor)
        end
    elseif phase == PhaseDrawBC
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawEdgeDuration,
            EdgeBCStart, EdgeBCEnd;
            penbrush=EdgeBrush,
            pencolor=EdgeBCColor,
            line_host_id=edge_b_c_host_id,
            line_joint1_id=edge_b_c_joint1_id,
            line_joint2_id=edge_b_c_joint2_id)

        timer += dt
        if timer >= DrawEdgeDuration
            phase = PhasePenLiftForMarker
            timer = 0f0
        end
    elseif phase == PhasePenLiftForMarker
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ, EdgeBCEnd[1], EdgeBCEnd[2])
        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, PenLiftDuration, CompassTopZ,
            PointA[1], PointA[2], MarkerStart[1], MarkerStart[2])

        timer += dt
        if timer >= PenLiftDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseDrawMarker
            timer = 0f0
        end
    elseif phase == PhaseDrawMarker
        EuclidAnimations.animate_draw_filledcircle(state_ptr,
            timer, MarkerDrawDuration, PointA,
            MarkerStart, AngleTheta, MarkerRadius;
            brush=MarkerBrush,
            color=MarkerColor,
            marker_host_id=marker_host_id,
            marker_start_id=marker_start_id,
            marker_end_id=marker_end_id)

        timer += dt
        if timer >= MarkerDrawDuration
            phase = PhaseCompassLift
            timer = 0f0
        end
    elseif phase == PhaseCompassLift
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassLiftDuration, CompassTopZ,
            PointA[1], PointA[2], MarkerEnd[1], MarkerEnd[2])

        timer += dt
        if timer >= CompassLiftDuration
            OdinJuliaBridge.hide_compass(state_ptr)
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
    HilbertChapterOneDefTriangleAngle.AnimationId,
    HilbertChapterOneDefTriangleAngle.animation_entry)

module HilbertChapterOneAxiomII5

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

export get_view_text, initialize, clean, loop, animation_entry

const APoint = [0.20f0, 0.32f0, 0f0]
const BPoint = [0.80f0, 0.32f0, 0f0]
const CPoint = [0.56f0, 0.72f0, 0f0]
const LineABStart = APoint
const LineABEnd = BPoint
const LineACStart = APoint
const LineACEnd = CPoint
const LineBCStart = BPoint
const LineBCEnd = CPoint
const LineaStart = [0.44f0, 0.06f0, 0f0]
const LineaEnd = [0.70f0, 0.86f0, 0f0]
const PenTopZ = 1.4f0

const ALabelPoint = APoint + [-0.04f0, -0.01f0, 0f0]
const BLabelPoint = BPoint + [0.02f0, -0.01f0, 0f0]
const CLabelPoint = CPoint + [-0.01f0, 0.04f0, 0f0]
const LineaLabelPoint = [0.45f0, 0.18f0, 0f0]
const LabelColor = :plum1

const PointAColor = :steelblue
const PointBColor = :palevioletred1
const PointCColor = :khaki3
const LineABColor = :khaki3
const LineACColor = :grey60
const LineBCColor = :grey60
const LineaColor = :steelblue
const LineMaxBrush = 5f0
const PointMaxBrush = 5f0

const DescendDuration = 1.8f0
const PointTrailDuration = 2f0
const ArcMoveDuration = 1.8f0
const DrawLineDuration = 4.2f0
const EndLiftDuration = 1.8f0

"""Stable native handles for one line owned by the animation."""
struct LineIds
    host::Int64
    joint1::Int64
    joint2::Int64
end

"""Complete immutable state for one Axiom II,5 animation generation."""
struct AnimationState
    point_a::Int64
    point_b::Int64
    point_c::Int64
    line_a_b::LineIds
    line_a_c::LineIds
    line_b_c::LineIds
    line_a::LineIds
    label_a::Int64
    label_b::Int64
    label_c::Int64
    label_line_a::Int64
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhaseDescend = 0f0
const PhasePutPointA = 1f0
const PhaseMoveToPointB = 2f0
const PhasePutPointB = 3f0
const PhaseMoveToPointA = 4f0
const PhaseDrawLineAB = 5f0
const PhaseMoveToPointC = 6f0
const PhasePutPointC = 7f0
const PhaseMoveToPointASecond = 8f0
const PhaseDrawLineAC = 9f0
const PhaseMoveToPointBSecond = 10f0
const PhaseDrawLineBC = 11f0
const PhaseMoveToLineaStart = 12f0
const PhaseDrawLinea = 13f0
const PhaseEndLift = 14f0

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(
        state.point_a, state.point_b, state.point_c,
        state.line_a_b, state.line_a_c, state.line_b_c, state.line_a,
        state.label_a, state.label_b, state.label_c, state.label_line_a,
        phase, timer)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - Axiom II,5

II, 5. Let A, B, C be three points not lying in the same straight line and let a be a straight line lying in the plane ABC and not passing through any of the points A, B, C. Then, if the straight line a passes through a point of the segment AB, it will also pass through either a point of the segment BC or a point of the segment AC."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - Axiom II,5}

\textbf{II, 5.} Let $A$ \euclidpoint[color=steelblue,size=1], $B$ \euclidpoint[color=palevioletred1,size=1], $C$ \euclidpoint[color=khaki3,size=1] be three points not lying in the same straight line \euclidline[color=khaki3,length=3,thickness=4] and let $a$ \euclidline[color=steelblue,length=3,thickness=4] be a straight line lying in the plane $ABC$ and not passing through any of the points $A$ \euclidpoint[color=steelblue,size=1], $B$ \euclidpoint[color=palevioletred1,size=1], $C$ \euclidpoint[color=khaki3,size=1]. Then, if the straight line a passes through a point of the segment $AB$ \euclidline[color=khaki3,length=3,thickness=4], it will also pass through either a point of the segment $BC$ \euclidline[color=grey60,length=3,thickness=4] or a point of the segment $AC$ \euclidline[color=grey60,length=3,thickness=4]."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset cycle timing transactionally before restoring visible animation state."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    point_a_id = state.point_a
    point_b_id = state.point_b
    point_c_id = state.point_c
    line_a_b_host_id = state.line_a_b.host
    line_a_b_joint1_id = state.line_a_b.joint1
    line_a_b_joint2_id = state.line_a_b.joint2
    line_a_c_host_id = state.line_a_c.host
    line_a_c_joint1_id = state.line_a_c.joint1
    line_a_c_joint2_id = state.line_a_c.joint2
    line_b_c_host_id = state.line_b_c.host
    line_b_c_joint1_id = state.line_b_c.joint1
    line_b_c_joint2_id = state.line_b_c.joint2
    linea_host_id = state.line_a.host
    linea_joint1_id = state.line_a.joint1
    linea_joint2_id = state.line_a.joint2
    label_a_id = state.label_a
    label_b_id = state.label_b
    label_c_id = state.label_c
    labela_id = state.label_line_a

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhaseDescend, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [point_a_id, point_b_id, point_c_id,
         line_a_b_host_id, line_a_c_host_id, line_b_c_host_id, linea_host_id,
         label_a_id, label_b_id, label_c_id, labela_id])

    OdinJuliaBridge.set_point_position(state_ptr, line_a_b_joint1_id, LineABStart)
    OdinJuliaBridge.set_point_position(state_ptr, line_a_b_joint2_id, LineABStart)
    OdinJuliaBridge.set_point_position(state_ptr, line_a_c_joint1_id, LineACStart)
    OdinJuliaBridge.set_point_position(state_ptr, line_a_c_joint2_id, LineACStart)
    OdinJuliaBridge.set_point_position(state_ptr, line_b_c_joint1_id, LineBCStart)
    OdinJuliaBridge.set_point_position(state_ptr, line_b_c_joint2_id, LineBCStart)
    OdinJuliaBridge.set_point_position(state_ptr, linea_joint1_id, LineaStart)
    OdinJuliaBridge.set_point_position(state_ptr, linea_joint2_id, LineaStart)

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, PointAColor)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    point_a = OdinJuliaBridge.create_new_point(
        state_ptr, APoint, PointAColor, 0f0)
    point_b = OdinJuliaBridge.create_new_point(
        state_ptr, BPoint, PointBColor, 0f0)
    point_c = OdinJuliaBridge.create_new_point(
        state_ptr, CPoint, PointCColor, 0f0)
    line_a_b = OdinJuliaBridge.create_new_line(
        state_ptr, LineABStart, LineABStart,
        LineABColor, 0f0)
    line_a_c = OdinJuliaBridge.create_new_line(
        state_ptr, LineACStart, LineACStart,
        LineACColor, 0f0)
    line_b_c = OdinJuliaBridge.create_new_line(
        state_ptr, LineBCStart, LineBCStart,
        LineBCColor, 0f0)
    linea = OdinJuliaBridge.create_new_line(
        state_ptr, LineaStart, LineaStart,
        LineaColor, 0f0)
    label_a = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', ALabelPoint, LabelColor, 16f0)
    label_b = OdinJuliaBridge.create_new_label(
        state_ptr, 'B', BLabelPoint, LabelColor, 16f0)
    label_c = OdinJuliaBridge.create_new_label(
        state_ptr, 'C', CLabelPoint, LabelColor, 16f0)
    labela = OdinJuliaBridge.create_new_label(
        state_ptr, 'a', LineaLabelPoint, LabelColor, 16f0)

    state = AnimationState(
        point_a.index, point_b.index, point_c.index,
        LineIds(line_a_b.host_id, line_a_b.joint1_id, line_a_b.joint2_id),
        LineIds(line_a_c.host_id, line_a_c.joint1_id, line_a_c.joint2_id),
        LineIds(line_b_c.host_id, line_b_c.joint1_id, line_b_c.joint2_id),
        LineIds(linea.host_id, linea.joint1_id, linea.joint2_id),
        label_a.index, label_b.index, label_c.index, labela.index,
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
    point_a_id = state.point_a
    point_b_id = state.point_b
    point_c_id = state.point_c
    line_a_b_host_id = state.line_a_b.host
    line_a_b_joint1_id = state.line_a_b.joint1
    line_a_b_joint2_id = state.line_a_b.joint2
    line_a_c_host_id = state.line_a_c.host
    line_a_c_joint1_id = state.line_a_c.joint1
    line_a_c_joint2_id = state.line_a_c.joint2
    line_b_c_host_id = state.line_b_c.host
    line_b_c_joint1_id = state.line_b_c.joint1
    line_b_c_joint2_id = state.line_b_c.joint2
    linea_host_id = state.line_a.host
    linea_joint1_id = state.line_a.joint1
    linea_joint2_id = state.line_a.joint2
    label_a_id = state.label_a
    label_b_id = state.label_b
    label_c_id = state.label_c
    labela_id = state.label_line_a

    if linea_host_id < 0
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
            state_ptr, timer, PointTrailDuration, APoint,
            PointMaxBrush, PointAColor, point_a_id)

        timer += dt
        if timer >= PointTrailDuration
            phase = PhaseMoveToPointB
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            APoint, BPoint, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePutPointB
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_b_id)
        end
    elseif phase == PhasePutPointB
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointTrailDuration, BPoint,
            PointMaxBrush, PointBColor, point_b_id)

        timer += dt
        if timer >= PointTrailDuration
            phase = PhaseMoveToPointA
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            BPoint, APoint, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawLineAB
            timer = 0f0
        end
    elseif phase == PhaseDrawLineAB
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawLineDuration,
            LineABStart, LineABEnd;
            penbrush=LineMaxBrush,
            pencolor=LineABColor,
            line_host_id=line_a_b_host_id,
            line_joint1_id=line_a_b_joint1_id,
            line_joint2_id=line_a_b_joint2_id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseMoveToPointC
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointC
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            BPoint, CPoint, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePutPointC
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_c_id)
        end
    elseif phase == PhasePutPointC
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointTrailDuration, CPoint,
            PointMaxBrush, PointCColor, point_c_id)

        timer += dt
        if timer >= PointTrailDuration
            phase = PhaseMoveToPointASecond
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointASecond
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            CPoint, APoint, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawLineAC
            timer = 0f0
        end
    elseif phase == PhaseDrawLineAC
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawLineDuration,
            LineACStart, LineACEnd;
            penbrush=LineMaxBrush,
            pencolor=LineACColor,
            line_host_id=line_a_c_host_id,
            line_joint1_id=line_a_c_joint1_id,
            line_joint2_id=line_a_c_joint2_id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseMoveToPointBSecond
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointBSecond
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            CPoint, BPoint, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawLineBC
            timer = 0f0
        end
    elseif phase == PhaseDrawLineBC
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawLineDuration,
            LineBCStart, LineBCEnd;
            penbrush=LineMaxBrush,
            pencolor=LineBCColor,
            line_host_id=line_b_c_host_id,
            line_joint1_id=line_b_c_joint1_id,
            line_joint2_id=line_b_c_joint2_id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseMoveToLineaStart
            timer = 0f0
        end
    elseif phase == PhaseMoveToLineaStart
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            CPoint, LineaStart, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawLinea
            timer = 0f0
        end
    elseif phase == PhaseDrawLinea
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawLineDuration,
            LineaStart, LineaEnd;
            penbrush=LineMaxBrush,
            pencolor=LineaColor,
            line_host_id=linea_host_id,
            line_joint1_id=linea_joint1_id,
            line_joint2_id=linea_joint2_id)

        if timer / DrawLineDuration >= 0.18f0
            OdinJuliaBridge.show_point(state_ptr, labela_id)
        end

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ, LineaEnd[1], LineaEnd[2])

        timer += dt
        if timer >= EndLiftDuration
            reset_cycle_state(state_ptr, state)
            return
        end
    end

    OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, phase, timer))
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

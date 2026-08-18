module HilbertChapterOneAxiomII2

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

export get_view_text, initialize, clean, loop

const LineStart = [0.12f0, 0.56f0, 0f0]
const LineEnd = [0.88f0, 0.56f0, 0f0]
const APoint = [0.28f0, 0.56f0, 0f0]
const BPoint = [0.50f0, 0.56f0, 0f0]
const CPoint = [0.62f0, 0.56f0, 0f0]
const DPoint = [0.80f0, 0.56f0, 0f0]
const PenTopZ = 1.4f0

const ALabelPoint = APoint + [-0.01f0, 0.04f0, 0f0]
const BLabelPoint = BPoint + [-0.005f0, 0.04f0, 0f0]
const CLabelPoint = CPoint + [-0.005f0, 0.04f0, 0f0]
const DLabelPoint = DPoint + [-0.005f0, 0.04f0, 0f0]
const LabelColor = :plum1

const LineColor = :grey60
const PointAColor = :palevioletred1
const PointBColor = :steelblue
const PointCColor = :khaki3
const PointDColor = :steelblue
const LineMaxBrush = 5f0
const PointMaxBrush = 5f0

const DescendDuration = 1.8f0
const DrawLineDuration = 4.2f0
const MoveToPointADuration = 1.8f0
const MoveToPointCDuration = 1.8f0
const MoveToPointBDuration = 1.8f0
const MoveToPointDDuration = 1.8f0
const ReturnToPointADuration = 2f0
const PointTrailDuration = 2f0
const DragSegmentDuration = 2.2f0
const EndLiftDuration = 1.8f0

const MetaLineHostId = 1
const MetaLinePointAId = 2
const MetaLinePointBId = 3
const MetaPointAId = 11
const MetaPointBId = 12
const MetaPointCId = 13
const MetaPointDId = 14
const MetaLabelAId = 21
const MetaLabelBId = 22
const MetaLabelCId = 23
const MetaLabelDId = 24
const MetaPhase = 101
const MetaTimer = 102

const PhaseDescend = 0f0
const PhaseDrawLine = 1f0
const PhaseMoveToPointA = 2f0
const PhasePutPointA = 3f0
const PhaseMoveToPointC = 4f0
const PhasePutPointC = 5f0
const PhaseMoveToPointB = 6f0
const PhasePutPointB = 7f0
const PhaseReturnToPointA = 8f0
const PhaseDragAB = 9f0
const PhaseDragBC = 10f0
const PhaseMoveToPointD = 11f0
const PhasePutPointD = 12f0
const PhaseReturnToPointASecond = 13f0
const PhaseDragAC = 14f0
const PhaseDragCD = 15f0
const PhaseEndLift = 16f0


function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - Axiom II,2

II, 2. If A and C are two points of a straight line, then there exists at least one point B lying between A and C and at least one point D so situated that C lies between A and D."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - Axiom II,2}

\textbf{II, 2.} If $A$ \euclidpoint[color=palevioletred1,size=1] and $C$ \euclidpoint[color=khaki3,size=1] are two points of a straight line \euclidline[color=grey60,length=3,thickness=4], then there exists at least one point $B$ \euclidpoint[color=steelblue,size=1] lying between $A$ \euclidpoint[color=palevioletred1,size=1] and $C$ \euclidpoint[color=khaki3,size=1] and at least one point $D$ \euclidpoint[color=steelblue,size=1] so situated that $C$ \euclidpoint[color=khaki3,size=1] lies between $A$ \euclidpoint[color=palevioletred1,size=1] and $D$ \euclidpoint[color=steelblue,size=1]."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    line_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineHostId))
    line_point_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLinePointAId))
    line_point_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLinePointBId))
    point_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    point_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    point_c_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointCId))
    point_d_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointDId))
    label_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    label_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    label_c_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    label_d_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [line_host_id, point_a_id, point_b_id, point_c_id, point_d_id,
         label_a_id, label_b_id, label_c_id, label_d_id])

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.set_point_position(state_ptr, line_point_a_id, LineStart)
    OdinJuliaBridge.set_point_position(state_ptr, line_point_b_id, LineStart)

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, LineColor)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    line = OdinJuliaBridge.create_new_line(
        state_ptr, LineStart, LineStart, LineColor, 0f0)
    point_a = OdinJuliaBridge.create_new_point(
        state_ptr, APoint, PointAColor, 0f0)
    point_b = OdinJuliaBridge.create_new_point(
        state_ptr, BPoint, PointBColor, 0f0)
    point_c = OdinJuliaBridge.create_new_point(
        state_ptr, CPoint, PointCColor, 0f0)
    point_d = OdinJuliaBridge.create_new_point(
        state_ptr, DPoint, PointDColor, 0f0)
    label_a = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', ALabelPoint, LabelColor, 16f0)
    label_b = OdinJuliaBridge.create_new_label(
        state_ptr, 'B', BLabelPoint, LabelColor, 16f0)
    label_c = OdinJuliaBridge.create_new_label(
        state_ptr, 'C', CLabelPoint, LabelColor, 16f0)
    label_d = OdinJuliaBridge.create_new_label(
        state_ptr, 'D', DLabelPoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineHostId, Float32(line.host_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLinePointAId, Float32(line.joint1_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLinePointBId, Float32(line.joint2_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointAId, Float32(point_a.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointBId, Float32(point_b.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointCId, Float32(point_c.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointDId, Float32(point_d.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAId, Float32(label_a.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBId, Float32(label_b.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelCId, Float32(label_c.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelDId, Float32(label_d.index))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    line_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineHostId))
    line_point_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLinePointAId))
    line_point_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLinePointBId))
    point_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    point_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    point_c_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointCId))
    point_d_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointDId))
    label_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    label_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    label_c_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    label_d_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDId))

    if line_host_id < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, LineStart[1], LineStart[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawLine
            timer = 0f0
        end
    elseif phase == PhaseDrawLine
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, LineStart, LineEnd,
            LineMaxBrush, LineColor, line_host_id, line_point_a_id, line_point_b_id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseMoveToPointA
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, MoveToPointADuration,
            LineEnd, APoint, 0.25f0, 1, :none)

        timer += dt
        if timer >= MoveToPointADuration
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
            phase = PhaseMoveToPointC
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointC
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, MoveToPointCDuration,
            APoint, CPoint, 0.25f0, 1, :none)

        timer += dt
        if timer >= MoveToPointCDuration
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
            phase = PhaseMoveToPointB
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, MoveToPointBDuration,
            CPoint, BPoint, 0.25f0, 1, :none)

        timer += dt
        if timer >= MoveToPointBDuration
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
            phase = PhaseReturnToPointA
            timer = 0f0
        end
    elseif phase == PhaseReturnToPointA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ReturnToPointADuration,
            BPoint, APoint, 0.3f0, 1, :none)

        timer += dt
        if timer >= ReturnToPointADuration
            phase = PhaseDragAB
            timer = 0f0
        end
    elseif phase == PhaseDragAB
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragSegmentDuration, APoint, BPoint, PointBColor)

        timer += dt
        if timer >= DragSegmentDuration
            phase = PhaseDragBC
            timer = 0f0
        end
    elseif phase == PhaseDragBC
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragSegmentDuration, BPoint, CPoint, PointBColor)

        timer += dt
        if timer >= DragSegmentDuration
            phase = PhaseMoveToPointD
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointD
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, MoveToPointDDuration,
            CPoint, DPoint, 0.25f0, 1, :none)

        timer += dt
        if timer >= MoveToPointDDuration
            phase = PhasePutPointD
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_d_id)
        end
    elseif phase == PhasePutPointD
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointTrailDuration, DPoint,
            PointMaxBrush, PointDColor, point_d_id)

        timer += dt
        if timer >= PointTrailDuration
            phase = PhaseReturnToPointASecond
            timer = 0f0
        end
    elseif phase == PhaseReturnToPointASecond
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ReturnToPointADuration,
            DPoint, APoint, 0.3f0, 1, :none)

        timer += dt
        if timer >= ReturnToPointADuration
            phase = PhaseDragAC
            timer = 0f0
        end
    elseif phase == PhaseDragAC
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragSegmentDuration, APoint, CPoint, PointBColor)

        timer += dt
        if timer >= DragSegmentDuration
            phase = PhaseDragCD
            timer = 0f0
        end
    elseif phase == PhaseDragCD
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragSegmentDuration, CPoint, DPoint, PointBColor)

        timer += dt
        if timer >= DragSegmentDuration
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ, DPoint[1], DPoint[2])

        timer += dt
        if timer >= EndLiftDuration
            reset_cycle_state(state_ptr)
            return
        end
    end

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, phase)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, timer)
end

end
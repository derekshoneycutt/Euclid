module HilbertChapterOneAxiomII5

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

export get_view_text, initialize, clean, loop

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

const MetaPointAId = 11
const MetaPointBId = 12
const MetaPointCId = 13
const MetaLineABHostId = 21
const MetaLineABJoint1Id = 22
const MetaLineABJoint2Id = 23
const MetaLineACHostId = 24
const MetaLineACJoint1Id = 25
const MetaLineACJoint2Id = 26
const MetaLineBCHostId = 27
const MetaLineBCJoint1Id = 28
const MetaLineBCJoint2Id = 29
const MetaLineaHostId = 30
const MetaLineaJoint1Id = 31
const MetaLineaJoint2Id = 32
const MetaLabelAId = 41
const MetaLabelBId = 42
const MetaLabelCId = 43
const MetaLabelaId = 44
const MetaPhase = 101
const MetaTimer = 102

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


function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - Axiom II,5

II, 5. Let A, B, C be three points not lying in the same straight line and let a be a straight line lying in the plane ABC and not passing through any of the points A, B, C. Then, if the straight line a passes through a point of the segment AB, it will also pass through either a point of the segment BC or a point of the segment AC."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - Axiom II,5}

\textbf{II, 5.} Let $A$ \euclidpoint[color=steelblue,size=1], $B$ \euclidpoint[color=palevioletred1,size=1], $C$ \euclidpoint[color=khaki3,size=1] be three points not lying in the same straight line \euclidline[color=khaki3,length=3,thickness=4] and let $a$ \euclidline[color=steelblue,length=3,thickness=4] be a straight line lying in the plane $ABC$ and not passing through any of the points $A$ \euclidpoint[color=steelblue,size=1], $B$ \euclidpoint[color=palevioletred1,size=1], $C$ \euclidpoint[color=khaki3,size=1]. Then, if the straight line a passes through a point of the segment $AB$ \euclidline[color=khaki3,length=3,thickness=4], it will also pass through either a point of the segment $BC$ \euclidline[color=grey60,length=3,thickness=4] or a point of the segment $AC$ \euclidline[color=grey60,length=3,thickness=4]."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    point_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    point_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    point_c_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointCId))
    line_a_b_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineABHostId))
    line_a_b_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineABJoint1Id))
    line_a_b_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineABJoint2Id))
    line_a_c_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineACHostId))
    line_a_c_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineACJoint1Id))
    line_a_c_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineACJoint2Id))
    line_b_c_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineBCHostId))
    line_b_c_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineBCJoint1Id))
    line_b_c_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineBCJoint2Id))
    linea_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineaHostId))
    linea_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineaJoint1Id))
    linea_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineaJoint2Id))
    label_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    label_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    label_c_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    labela_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelaId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [point_a_id, point_b_id, point_c_id,
         line_a_b_host_id, line_a_c_host_id, line_b_c_host_id, linea_host_id,
         label_a_id, label_b_id, label_c_id, labela_id])

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

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
end

function initialize(state_ptr::Ptr{Cvoid})
    point_a = OdinJuliaBridge.create_new_point(
        state_ptr, APoint, PointAColor, 0f0)
    point_b = OdinJuliaBridge.create_new_point(
        state_ptr, BPoint, PointBColor, 0f0)
    point_c = OdinJuliaBridge.create_new_point(
        state_ptr, CPoint, PointCColor, 0f0)
    line_a_b = OdinJuliaBridge.create_new_line(
        state_ptr, LineABStart, LineABStart, LineABColor, 0f0)
    line_a_c = OdinJuliaBridge.create_new_line(
        state_ptr, LineACStart, LineACStart, LineACColor, 0f0)
    line_b_c = OdinJuliaBridge.create_new_line(
        state_ptr, LineBCStart, LineBCStart, LineBCColor, 0f0)
    linea = OdinJuliaBridge.create_new_line(
        state_ptr, LineaStart, LineaStart, LineaColor, 0f0)
    label_a = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', ALabelPoint, LabelColor, 16f0)
    label_b = OdinJuliaBridge.create_new_label(
        state_ptr, 'B', BLabelPoint, LabelColor, 16f0)
    label_c = OdinJuliaBridge.create_new_label(
        state_ptr, 'C', CLabelPoint, LabelColor, 16f0)
    labela = OdinJuliaBridge.create_new_label(
        state_ptr, 'a', LineaLabelPoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointAId, point_a.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointBId, point_b.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointCId, point_c.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineABHostId, line_a_b.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineABJoint1Id, line_a_b.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineABJoint2Id, line_a_b.joint2_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineACHostId, line_a_c.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineACJoint1Id, line_a_c.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineACJoint2Id, line_a_c.joint2_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineBCHostId, line_b_c.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineBCJoint1Id, line_b_c.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineBCJoint2Id, line_b_c.joint2_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineaHostId, linea.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineaJoint1Id, linea.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineaJoint2Id, linea.joint2_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAId, label_a.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBId, label_b.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelCId, label_c.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelaId, labela.index)

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    point_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    point_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    point_c_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointCId))
    line_a_b_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineABHostId))
    line_a_b_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineABJoint1Id))
    line_a_b_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineABJoint2Id))
    line_a_c_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineACHostId))
    line_a_c_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineACJoint1Id))
    line_a_c_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineACJoint2Id))
    line_b_c_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineBCHostId))
    line_b_c_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineBCJoint1Id))
    line_b_c_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineBCJoint2Id))
    linea_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineaHostId))
    linea_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineaJoint1Id))
    linea_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineaJoint2Id))
    label_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    label_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    label_c_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    labela_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelaId))

    if linea_host_id < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

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
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, LineABStart, LineABEnd,
            LineMaxBrush, LineABColor,
            line_a_b_host_id, line_a_b_joint1_id, line_a_b_joint2_id)

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
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, LineACStart, LineACEnd,
            LineMaxBrush, LineACColor,
            line_a_c_host_id, line_a_c_joint1_id, line_a_c_joint2_id)

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
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, LineBCStart, LineBCEnd,
            LineMaxBrush, LineBCColor,
            line_b_c_host_id, line_b_c_joint1_id, line_b_c_joint2_id)

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
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, LineaStart, LineaEnd,
            LineMaxBrush, LineaColor,
            linea_host_id, linea_joint1_id, linea_joint2_id)

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
            reset_cycle_state(state_ptr)
            return
        end
    end

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, phase)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, timer)
end

end
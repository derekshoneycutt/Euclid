module HilbertChapterOneAxiomII5

using ..OdinJuliaBridge
using ..EuclidAnimations

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
    """David Hilbert - Foundations of Geometry - Axiom II,5

II, 5. Let A, B, C be three points not lying in the same straight line and let a be a straight line lying in the plane ABC and not passing through any of the points A, B, C. Then, if the straight line a passes through a point of the segment AB, it will also pass through either a point of the segment BC or a point of the segment AC."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    pointAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    pointBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    pointCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointCId))
    lineABHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineABHostId))
    lineABJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineABJoint1Id))
    lineABJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineABJoint2Id))
    lineACHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineACHostId))
    lineACJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineACJoint1Id))
    lineACJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineACJoint2Id))
    lineBCHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineBCHostId))
    lineBCJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineBCJoint1Id))
    lineBCJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineBCJoint2Id))
    lineaHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineaHostId))
    lineaJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineaJoint1Id))
    lineaJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineaJoint2Id))
    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labelCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    labelaId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelaId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [pointAId, pointBId, pointCId,
         lineABHostId, lineACHostId, lineBCHostId, lineaHostId,
         labelAId, labelBId, labelCId, labelaId])

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.set_point_position(state_ptr, lineABJoint1Id, LineABStart)
    OdinJuliaBridge.set_point_position(state_ptr, lineABJoint2Id, LineABStart)
    OdinJuliaBridge.set_point_position(state_ptr, lineACJoint1Id, LineACStart)
    OdinJuliaBridge.set_point_position(state_ptr, lineACJoint2Id, LineACStart)
    OdinJuliaBridge.set_point_position(state_ptr, lineBCJoint1Id, LineBCStart)
    OdinJuliaBridge.set_point_position(state_ptr, lineBCJoint2Id, LineBCStart)
    OdinJuliaBridge.set_point_position(state_ptr, lineaJoint1Id, LineaStart)
    OdinJuliaBridge.set_point_position(state_ptr, lineaJoint2Id, LineaStart)

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, PointAColor)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    pointA = OdinJuliaBridge.create_new_point(
        state_ptr, APoint, PointAColor, 0f0)
    pointB = OdinJuliaBridge.create_new_point(
        state_ptr, BPoint, PointBColor, 0f0)
    pointC = OdinJuliaBridge.create_new_point(
        state_ptr, CPoint, PointCColor, 0f0)
    lineAB = OdinJuliaBridge.create_new_line(
        state_ptr, LineABStart, LineABStart, LineABColor, 0f0)
    lineAC = OdinJuliaBridge.create_new_line(
        state_ptr, LineACStart, LineACStart, LineACColor, 0f0)
    lineBC = OdinJuliaBridge.create_new_line(
        state_ptr, LineBCStart, LineBCStart, LineBCColor, 0f0)
    linea = OdinJuliaBridge.create_new_line(
        state_ptr, LineaStart, LineaStart, LineaColor, 0f0)
    labelA = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', ALabelPoint, LabelColor, 16f0)
    labelB = OdinJuliaBridge.create_new_label(
        state_ptr, 'B', BLabelPoint, LabelColor, 16f0)
    labelC = OdinJuliaBridge.create_new_label(
        state_ptr, 'C', CLabelPoint, LabelColor, 16f0)
    labela = OdinJuliaBridge.create_new_label(
        state_ptr, 'a', LineaLabelPoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointAId, Float32(pointA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointBId, Float32(pointB.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointCId, Float32(pointC.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineABHostId, Float32(lineAB.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineABJoint1Id, Float32(lineAB.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineABJoint2Id, Float32(lineAB.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineACHostId, Float32(lineAC.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineACJoint1Id, Float32(lineAC.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineACJoint2Id, Float32(lineAC.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineBCHostId, Float32(lineBC.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineBCJoint1Id, Float32(lineBC.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineBCJoint2Id, Float32(lineBC.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineaHostId, Float32(linea.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineaJoint1Id, Float32(linea.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineaJoint2Id, Float32(linea.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAId, Float32(labelA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBId, Float32(labelB.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelCId, Float32(labelC.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelaId, Float32(labela.index))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    pointAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    pointBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    pointCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointCId))
    lineABHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineABHostId))
    lineABJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineABJoint1Id))
    lineABJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineABJoint2Id))
    lineACHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineACHostId))
    lineACJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineACJoint1Id))
    lineACJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineACJoint2Id))
    lineBCHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineBCHostId))
    lineBCJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineBCJoint1Id))
    lineBCJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineBCJoint2Id))
    lineaHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineaHostId))
    lineaJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineaJoint1Id))
    lineaJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineaJoint2Id))
    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labelCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    labelaId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelaId))

    if lineaHostId < 0
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
            OdinJuliaBridge.show_point(state_ptr, labelAId)
        end
    elseif phase == PhasePutPointA
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointTrailDuration, APoint,
            PointMaxBrush, PointAColor, pointAId)

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
            OdinJuliaBridge.show_point(state_ptr, labelBId)
        end
    elseif phase == PhasePutPointB
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointTrailDuration, BPoint,
            PointMaxBrush, PointBColor, pointBId)

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
            lineABHostId, lineABJoint1Id, lineABJoint2Id)

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
            OdinJuliaBridge.show_point(state_ptr, labelCId)
        end
    elseif phase == PhasePutPointC
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointTrailDuration, CPoint,
            PointMaxBrush, PointCColor, pointCId)

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
            lineACHostId, lineACJoint1Id, lineACJoint2Id)

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
            lineBCHostId, lineBCJoint1Id, lineBCJoint2Id)

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
            lineaHostId, lineaJoint1Id, lineaJoint2Id)

        if timer / DrawLineDuration >= 0.18f0
            OdinJuliaBridge.show_point(state_ptr, labelaId)
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
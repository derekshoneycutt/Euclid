module HilbertChapterOneAxiomIII1

using ..OdinJuliaBridge
using ..EuclidAnimations

export get_view_text, initialize, clean, loop

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

const MetaLineAHostId = 1
const MetaLineAJoint1Id = 2
const MetaLineAJoint2Id = 3
const MetaPointAId = 11
const MetaParallelHostId = 21
const MetaParallelJoint1Id = 22
const MetaParallelJoint2Id = 23
const MetaLabelaId = 31
const MetaLabelAId = 32
const MetaPhase = 101
const MetaTimer = 102

const PhaseDescend = 0f0
const PhaseDrawLineA = 1f0
const PhaseMoveToPointA = 2f0
const PhaseDrawPointA = 3f0
const PhaseMoveToParallelStart = 4f0
const PhaseDrawParallel = 5f0
const PhaseEndLift = 6f0
const PhaseFinalHold = 7f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """David Hilbert - Foundations of Geometry - Axiom III

III. In a plane α there can be drawn through any point A, lying outside of a straight line a, one and only one straight line which does not intersect the line a. This straight line is called the parallel to a through the given point A.

This statement of the axiom of parallels contains two assertions. The first of these is that, in the plane α, there is always a straight line passing through A which does not intersect the given line a. The second states that only one such line is possible. The latter of these statements is the essential one, and it may also be expressed as Theorem 8."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    lineAHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAHostId))
    lineAJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAJoint1Id))
    lineAJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAJoint2Id))
    pointAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    parallelHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaParallelHostId))
    parallelJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaParallelJoint1Id))
    parallelJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaParallelJoint2Id))
    labelaId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelaId))
    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [lineAHostId, pointAId, parallelHostId, labelaId, labelAId])

    OdinJuliaBridge.set_point_position(state_ptr, lineAJoint1Id, LineAStart)
    OdinJuliaBridge.set_point_position(state_ptr, lineAJoint2Id, LineAStart)
    OdinJuliaBridge.set_point_position(state_ptr, parallelJoint1Id, ParallelStart)
    OdinJuliaBridge.set_point_position(state_ptr, parallelJoint2Id, ParallelStart)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, LineAColor)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    lineA = OdinJuliaBridge.create_new_line(
        state_ptr, LineAStart, LineAStart, LineAColor, 0f0)
    pointA = OdinJuliaBridge.create_new_point(
        state_ptr, PointA, PointAColor, 0f0)
    parallelLine = OdinJuliaBridge.create_new_line(
        state_ptr, ParallelStart, ParallelStart, ParallelColor, 0f0)
    labela = OdinJuliaBridge.create_new_label(
        state_ptr, 'a', LineaLabelPoint, LabelColor, 16f0)
    labelA = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', ALabelPoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineAHostId, Float32(lineA.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineAJoint1Id, Float32(lineA.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineAJoint2Id, Float32(lineA.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointAId, Float32(pointA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaParallelHostId, Float32(parallelLine.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaParallelJoint1Id, Float32(parallelLine.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaParallelJoint2Id, Float32(parallelLine.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelaId, Float32(labela.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAId, Float32(labelA.index))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    lineAHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAHostId))
    lineAJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAJoint1Id))
    lineAJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAJoint2Id))
    pointAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    parallelHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaParallelHostId))
    parallelJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaParallelJoint1Id))
    parallelJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaParallelJoint2Id))
    labelaId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelaId))
    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))

    if lineAHostId < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, LineAStart[1], LineAStart[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawLineA
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelaId)
        end
    elseif phase == PhaseDrawLineA
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, LineAStart, LineAEnd,
            LineMaxBrush, LineAColor, lineAHostId, lineAJoint1Id, lineAJoint2Id)

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
            OdinJuliaBridge.show_point(state_ptr, labelAId)
            phase = PhaseDrawPointA
            timer = 0f0
        end
    elseif phase == PhaseDrawPointA
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, PointA,
            PointMaxBrush, PointAColor, pointAId)

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
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, ParallelStart, ParallelEnd,
            LineMaxBrush, ParallelColor,
            parallelHostId, parallelJoint1Id, parallelJoint2Id)

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
            reset_cycle_state(state_ptr)
            return
        end
    end

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, phase)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, timer)
end

end

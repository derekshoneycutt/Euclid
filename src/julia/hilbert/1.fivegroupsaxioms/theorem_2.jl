module HilbertChapterOneTheorem2

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidGeometry

using LinearAlgebra

export get_view_text, initialize, clean, loop

const LineAStart = [0.20f0, 0.64f0, 0f0]
const LineAEnd = [0.84f0, 0.40f0, 0f0]
const PointOffLine = [0.34f0, 0.27f0, 0f0]
const LineBStart = [0.18f0, 0.38f0, 0f0]
const LineBEnd = [0.78f0, 0.76f0, 0f0]
const IntersectionPoint = line_intersection_3d(LineAStart, LineAEnd, LineBStart, LineBEnd)
const PenTopZ = 1.4f0

const SurfaceSweepAStart = [0f0, 0.715f0, 0f0]
const SurfaceSweepAEnd = [1f0, 0.34f0, 0f0]
const SurfaceSweepBStart = [0f0, 0.266f0, 0f0]
const SurfaceSweepBEnd = [1f0, 0.89933336f0, 0f0]
const SurfaceSweepCStart = [0.237f0, 0f0, 0f0]
const SurfaceSweepCEnd = [0.617f0, 1f0, 0f0]

const LineAColor = :steelblue
const PointOffLineColor = :palevioletred1
const LineBColor = :khaki3
const IntersectionColor = :grey60
const SurfaceSweepAColor = :steelblue
const SurfaceSweepBColor = :khaki3
const SurfaceSweepCColor = :palevioletred1
const LineMaxBrush = 5f0
const PointMaxBrush = 5f0

const DescendDuration = 1.8f0
const LineDrawDuration = 4.2f0
const ArcMoveDuration = 2.0f0
const PointTrailDuration = 2.0f0
const SurfaceDragDuration = 3.8f0
const EndLiftDuration = 1.8f0
const FinalHoldDuration = 0.35f0

const MetaLineAHostId = 1
const MetaLineAJoint1Id = 2
const MetaLineAJoint2Id = 3
const MetaLineBHostId = 4
const MetaLineBJoint1Id = 5
const MetaLineBJoint2Id = 6
const MetaPointOffLineId = 11
const MetaIntersectionPointId = 12
const MetaPhase = 101
const MetaTimer = 102

const PhaseDescend = 0f0
const PhaseDrawLineA = 1f0
const PhaseMoveToPointOffLine = 2f0
const PhaseDrawPointOffLine = 3f0
const PhaseMoveToLineBStart = 4f0
const PhaseDrawLineB = 5f0
const PhaseMoveToIntersection = 6f0
const PhaseDrawIntersection = 7f0
const PhaseArcToSurfaceSweepA = 8f0
const PhaseDragSurfaceSweepA = 9f0
const PhaseArcToSurfaceSweepB = 10f0
const PhaseDragSurfaceSweepB = 11f0
const PhaseArcToSurfaceSweepC = 12f0
const PhaseDragSurfaceSweepC = 13f0
const PhaseEndLift = 14f0
const PhaseFinalHold = 15f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """David Hilbert - Foundations of Geometry - Theorem 2

Through a straight line and a point not lying in it, or through two distinct straight lines having a common point, one and only one plane may be made to pass."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    lineAHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAHostId))
    lineAJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAJoint1Id))
    lineAJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAJoint2Id))
    lineBHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineBHostId))
    lineBJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineBJoint1Id))
    lineBJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineBJoint2Id))
    pointOffLineId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointOffLineId))
    intersectionPointId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaIntersectionPointId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [lineAHostId, lineBHostId, pointOffLineId, intersectionPointId])

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.set_point_position(
        state_ptr, lineAJoint1Id, LineAStart[1], LineAStart[2], LineAStart[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, lineAJoint2Id, LineAStart[1], LineAStart[2], LineAStart[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, lineBJoint1Id, LineBStart[1], LineBStart[2], LineBStart[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, lineBJoint2Id, LineBStart[1], LineBStart[2], LineBStart[3])

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, LineAColor)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    lineA = OdinJuliaBridge.create_new_line(
        state_ptr, LineAStart, LineAStart, LineAColor, 0f0)
    pointOffLine = OdinJuliaBridge.create_new_point(
        state_ptr, PointOffLine, PointOffLineColor, 0f0)
    lineB = OdinJuliaBridge.create_new_line(
        state_ptr, LineBStart, LineBStart, LineBColor, 0f0)
    intersectionPoint = OdinJuliaBridge.create_new_point(
        state_ptr, IntersectionPoint, IntersectionColor, 0f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineAHostId, Float32(lineA.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineAJoint1Id, Float32(lineA.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineAJoint2Id, Float32(lineA.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineBHostId, Float32(lineB.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineBJoint1Id, Float32(lineB.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineBJoint2Id, Float32(lineB.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointOffLineId, Float32(pointOffLine.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaIntersectionPointId, Float32(intersectionPoint.index))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    lineAHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAHostId))
    lineAJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAJoint1Id))
    lineAJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAJoint2Id))
    lineBHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineBHostId))
    lineBJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineBJoint1Id))
    lineBJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineBJoint2Id))
    pointOffLineId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointOffLineId))
    intersectionPointId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaIntersectionPointId))

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
        end
    elseif phase == PhaseDrawLineA
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, LineDrawDuration, LineAStart, LineAEnd,
            LineMaxBrush, LineAColor, lineAHostId, lineAJoint1Id, lineAJoint2Id)

        timer += dt
        if timer >= LineDrawDuration
            phase = PhaseMoveToPointOffLine
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointOffLine
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            LineAEnd, PointOffLine, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawPointOffLine
            timer = 0f0
        end
    elseif phase == PhaseDrawPointOffLine
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointTrailDuration, PointOffLine,
            PointMaxBrush, PointOffLineColor, pointOffLineId)

        timer += dt
        if timer >= PointTrailDuration
            phase = PhaseMoveToLineBStart
            timer = 0f0
        end
    elseif phase == PhaseMoveToLineBStart
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointOffLine, LineBStart, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawLineB
            timer = 0f0
        end
    elseif phase == PhaseDrawLineB
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, LineDrawDuration, LineBStart, LineBEnd,
            LineMaxBrush, LineBColor, lineBHostId, lineBJoint1Id, lineBJoint2Id)

        timer += dt
        if timer >= LineDrawDuration
            phase = PhaseMoveToIntersection
            timer = 0f0
        end
    elseif phase == PhaseMoveToIntersection
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            LineBEnd, IntersectionPoint, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawIntersection
            timer = 0f0
        end
    elseif phase == PhaseDrawIntersection
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointTrailDuration, IntersectionPoint,
            PointMaxBrush, IntersectionColor, intersectionPointId)

        timer += dt
        if timer >= PointTrailDuration
            phase = PhaseArcToSurfaceSweepA
            timer = 0f0
        end
    elseif phase == PhaseArcToSurfaceSweepA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            IntersectionPoint, SurfaceSweepAStart, 0.28f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragSurfaceSweepA
            timer = 0f0
        end
    elseif phase == PhaseDragSurfaceSweepA
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, SurfaceDragDuration,
            SurfaceSweepAStart, SurfaceSweepAEnd, SurfaceSweepAColor)

        timer += dt
        if timer >= SurfaceDragDuration
            phase = PhaseArcToSurfaceSweepB
            timer = 0f0
        end
    elseif phase == PhaseArcToSurfaceSweepB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            SurfaceSweepAEnd, SurfaceSweepBStart, 0.28f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragSurfaceSweepB
            timer = 0f0
        end
    elseif phase == PhaseDragSurfaceSweepB
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, SurfaceDragDuration,
            SurfaceSweepBStart, SurfaceSweepBEnd, SurfaceSweepBColor)

        timer += dt
        if timer >= SurfaceDragDuration
            phase = PhaseArcToSurfaceSweepC
            timer = 0f0
        end
    elseif phase == PhaseArcToSurfaceSweepC
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            SurfaceSweepBEnd, SurfaceSweepCStart, 0.28f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragSurfaceSweepC
            timer = 0f0
        end
    elseif phase == PhaseDragSurfaceSweepC
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, SurfaceDragDuration,
            SurfaceSweepCStart, SurfaceSweepCEnd, SurfaceSweepCColor)

        timer += dt
        if timer >= SurfaceDragDuration
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ,
            SurfaceSweepCEnd[1], SurfaceSweepCEnd[2])

        timer += dt
        if timer >= EndLiftDuration
            phase = PhaseFinalHold
            timer = 0f0
        end
    elseif phase == PhaseFinalHold
        OdinJuliaBridge.show_pen(state_ptr)
        OdinJuliaBridge.set_pen_active(state_ptr, 0, LineAColor)

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

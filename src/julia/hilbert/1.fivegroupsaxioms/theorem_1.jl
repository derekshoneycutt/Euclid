module HilbertChapterOneTheorem1

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidGeometry

using LinearAlgebra

export get_view_text, initialize, clean, loop

const PlaneEdgeLeft = [0.18f0, 0.58f0, 0f0]
const PlaneEdgeRight = [0.82f0, 0.58f0, 0f0]
const PlaneTopRight = [0.82f0, 0.58f0, 0.45f0]
const PlaneTopLeft = [0.18f0, 0.58f0, 0.45f0]

const LineAStart = [0.18f0, 0.58f0, 0f0]
const LineAEnd = [0.82f0, 0.58f0, 0f0]
const LineBStart = [0.34f0, 0.78f0, 0f0]
const LineBEnd = [0.56f0, 0.36f0, 0f0]
const IntersectionPoint = line_intersection_3d(LineAStart, LineAEnd, LineBStart, LineBEnd)
const PenTopZ = 1.4f0

const PlaneColor = :palevioletred1
const PlaneBaseColor = OdinJuliaBridge.bridge_color(PlaneColor)
const PlaneMaxAlpha01 = 0.45f0
const FlickerColor = :palevioletred1
const FlickerSamplesPerFrame = 8

const LineAColor = :steelblue
const LineBColor = :palevioletred1
const IntersectionColor = :khaki3
const HighlightColor = :grey60
const LineMaxBrush = 5f0
const PointMaxBrush = 5f0

const FadeInDuration = 2.5f0
const DescendDuration = 1.8f0
const LineDrawDuration = 4.2f0
const MoveToLineBDuration = 2.0f0
const PointTrailDuration = 2.0f0
const PlaneRevealDuration = 2.5f0
const PlaneHoldDuration = 0.8f0
const SurfaceSweepDuration = 3.6f0
const SurfaceHoverDuration = 1.8f0
const EndLiftDuration = 1.8f0
const FinalHoldDuration = 1.2f0

const MetaPlaneHostId = 1
const MetaLineAHostId = 2
const MetaLineAJoint1Id = 3
const MetaLineAJoint2Id = 4
const MetaLineBHostId = 5
const MetaLineBJoint1Id = 6
const MetaLineBJoint2Id = 7
const MetaIntersectionPointId = 11
const MetaPhase = 101
const MetaTimer = 102

const PhaseDescend = 0f0
const PhaseDrawLineA = 1f0
const PhaseMoveToLineB = 2f0
const PhaseDrawLineB = 3f0
const PhaseMoveToIntersection = 4f0
const PhaseDrawIntersection = 5f0
const PhasePlaneReveal = 6f0
const PhaseSweepSurface = 8f0
const PhaseMoveToIntersectionHover = 9f0
const PhaseHoverIntersection = 10f0
const PhaseEndLift = 11f0
const PhaseFinalHold = 12f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """David Hilbert - Foundations of Geometry - Theorem 1

Two straight lines of a plane have either one point or no point in common; two planes have no point in common or a straight line in common; a plane and a straight line not lying in it have no point or one point in common."""
end

function set_plane_alpha(state_ptr::Ptr{Cvoid}, hostId, alpha01)
    t = clamp(alpha01, 0f0, PlaneMaxAlpha01)
    alpha = UInt8(round(Int, Float32(PlaneBaseColor.a) * t))
    color = OdinJuliaBridge.BridgeColor(
        PlaneBaseColor.r,
        PlaneBaseColor.g,
        PlaneBaseColor.b,
        alpha)
    OdinJuliaBridge.set_point_color(state_ptr, hostId, color)
end

function random_triangle_point(a::Vector{Float32}, b::Vector{Float32}, c::Vector{Float32})
    u = rand(Float32)
    v = rand(Float32)

    if u + v > 1f0
        u = 1f0 - u
        v = 1f0 - v
    end

    [
        a[1] + u * (b[1] - a[1]) + v * (c[1] - a[1]),
        a[2] + u * (b[2] - a[2]) + v * (c[2] - a[2]),
        a[3] + u * (b[3] - a[3]) + v * (c[3] - a[3]),
    ]
end

function random_vertical_plane_point()
    if rand(Float32) < 0.5f0
        return random_triangle_point(PlaneEdgeLeft, PlaneTopLeft, PlaneTopRight)
    end

    random_triangle_point(PlaneEdgeLeft, PlaneTopRight, PlaneEdgeRight)
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    planeHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPlaneHostId))
    lineAHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAHostId))
    lineAJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAJoint1Id))
    lineAJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAJoint2Id))
    lineBHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineBHostId))
    lineBJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineBJoint1Id))
    lineBJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineBJoint2Id))
    intersectionPointId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaIntersectionPointId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [planeHostId, lineAHostId, lineBHostId, intersectionPointId])

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

    set_plane_alpha(state_ptr, planeHostId, 0f0)
    OdinJuliaBridge.hide_point(state_ptr, planeHostId)

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, LineAColor)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    lineA = OdinJuliaBridge.create_new_line(
        state_ptr, LineAStart, LineAStart, LineAColor, 0f0)
    lineB = OdinJuliaBridge.create_new_line(
        state_ptr, LineBStart, LineBStart, LineBColor, 0f0)
    intersectionPoint = OdinJuliaBridge.create_new_point(
        state_ptr, IntersectionPoint, IntersectionColor, 0f0)
    planeBeta = OdinJuliaBridge.create_new_square(
        state_ptr,
        PlaneEdgeLeft,
        PlaneEdgeRight,
        PlaneTopRight,
        PlaneTopLeft,
        PlaneColor)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPlaneHostId, Float32(planeBeta.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineAHostId, Float32(lineA.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineAJoint1Id, Float32(lineA.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineAJoint2Id, Float32(lineA.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineBHostId, Float32(lineB.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineBJoint1Id, Float32(lineB.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineBJoint2Id, Float32(lineB.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaIntersectionPointId, Float32(intersectionPoint.index))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    planeHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPlaneHostId))
    lineAHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAHostId))
    lineAJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAJoint1Id))
    lineAJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineAJoint2Id))
    lineBHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineBHostId))
    lineBJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineBJoint1Id))
    lineBJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineBJoint2Id))
    intersectionPointId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaIntersectionPointId))

    if planeHostId < 0
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
            phase = PhaseMoveToLineB
            timer = 0f0
        end
    elseif phase == PhaseMoveToLineB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, MoveToLineBDuration,
            LineAEnd, LineBStart, 0.25f0, 1, :none)

        timer += dt
        if timer >= MoveToLineBDuration
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
            state_ptr, timer, MoveToLineBDuration,
            LineBEnd, IntersectionPoint, 0.25f0, 1, :none)

        timer += dt
        if timer >= MoveToLineBDuration
            phase = PhaseDrawIntersection
            timer = 0f0
        end
    elseif phase == PhaseDrawIntersection
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointTrailDuration, IntersectionPoint,
            PointMaxBrush, IntersectionColor, intersectionPointId)

        timer += dt
        if timer >= PointTrailDuration
            phase = PhasePlaneReveal
            timer = 0f0
        end
    elseif phase == PhasePlaneReveal
        set_plane_alpha(state_ptr, planeHostId, (timer / PlaneRevealDuration) * PlaneMaxAlpha01)
        OdinJuliaBridge.show_point(state_ptr, planeHostId)

        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, PlaneRevealDuration,
            IntersectionPoint, LineAStart, 0.25f0, 1, :none)

        for _ in 1:FlickerSamplesPerFrame
            samplePos = random_vertical_plane_point()
            OdinJuliaBridge.emit_flicker_particle(state_ptr, samplePos, FlickerColor)
        end

        timer += dt
        if timer >= PlaneRevealDuration
            phase = PhaseSweepSurface
            timer = 0f0
            set_plane_alpha(state_ptr, planeHostId, PlaneMaxAlpha01)
        end
    elseif phase == PhaseSweepSurface
        set_plane_alpha(state_ptr, planeHostId, PlaneMaxAlpha01)
        OdinJuliaBridge.show_point(state_ptr, planeHostId)

        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, SurfaceSweepDuration,
            LineAStart, LineAEnd, HighlightColor)

        timer += dt
        if timer >= SurfaceSweepDuration
            phase = PhaseMoveToIntersectionHover
            timer = 0f0
        end
    elseif phase == PhaseMoveToIntersectionHover
        set_plane_alpha(state_ptr, planeHostId, PlaneMaxAlpha01)
        OdinJuliaBridge.show_point(state_ptr, planeHostId)

        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, MoveToLineBDuration,
            LineAEnd, IntersectionPoint, 0.25f0, 1, :none)

        timer += dt
        if timer >= MoveToLineBDuration
            phase = PhaseHoverIntersection
            timer = 0f0
        end
    elseif phase == PhaseHoverIntersection
        set_plane_alpha(state_ptr, planeHostId, PlaneMaxAlpha01)
        OdinJuliaBridge.show_point(state_ptr, planeHostId)

        EuclidAnimations.animate_highlight_point(state_ptr, timer, SurfaceHoverDuration,
            IntersectionPoint, HighlightColor)

        timer += dt
        if timer >= SurfaceHoverDuration
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        set_plane_alpha(state_ptr, planeHostId, PlaneMaxAlpha01)
        OdinJuliaBridge.show_point(state_ptr, planeHostId)

        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ, IntersectionPoint[1], IntersectionPoint[2])

        timer += dt
        if timer >= EndLiftDuration
            phase = PhaseFinalHold
            timer = 0f0
        end
    elseif phase == PhaseFinalHold
        set_plane_alpha(state_ptr, planeHostId, PlaneMaxAlpha01)
        OdinJuliaBridge.show_point(state_ptr, planeHostId)
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
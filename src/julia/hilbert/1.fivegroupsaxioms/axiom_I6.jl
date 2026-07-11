module HilbertChapterOneAxiomI6

using ..OdinJuliaBridge
using ..EuclidAnimations

using LinearAlgebra

export get_view_text, initialize, clean, loop

const PlaneEdgeLeft = [1f0, 0f0, 0f0]
const PlaneEdgeRight = [0f0, 1f0, 0f0]
const PlaneTopRight = [0f0, 1f0, 0.45f0]
const PlaneTopLeft = [1f0, 0f0, 0.45f0]

const PointA = [0.58f0, 0.42f0, 0f0]
const PointB = [0.42f0, 0.58f0, 0f0]
const PenTopZ = 1.4f0

const LabelAlphaPoint = [0.1f0, 0.1f0, 0f0]
const LabelBetaPoint = [0.56f0, 0.44f0, 0.34f0]
const LabelAPoint = PointA + [-0.03f0, 0.01f0, 0f0]
const LabelBPoint = PointB + [0.01f0, -0.02f0, 0f0]
const LabelColor = :plum1

const PlaneColor = :khaki3
const PlaneBaseColor = OdinJuliaBridge.bridge_color(PlaneColor)
const PlaneMaxAlpha01 = 0.45f0
const PointAColor = :steelblue
const PointBColor = :palevioletred1
const FlickerColor = :white
const FlickerSamplesPerFrame = 8
const PointMaxBrush = 5f0

const FadeInDuration = 2.5f0
const DescendDuration = 1.8f0
const PointTrailDuration = 2f0
const MoveToPointBDuration = 2f0
const EndLiftDuration = 1.8f0

const MetaPlaneHostId = 1
const MetaPointAId = 11
const MetaPointBId = 12
const MetaLabelAlphaId = 21
const MetaLabelBetaId = 22
const MetaLabelAId = 23
const MetaLabelBId = 24
const MetaPhase = 101
const MetaTimer = 102

const PhaseFadeInPlane = 0f0
const PhaseDescendToA = 1f0
const PhasePutPointA = 2f0
const PhaseMoveToPointB = 3f0
const PhasePutPointB = 4f0
const PhaseEndLift = 5f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """David Hilbert - Foundations of Geometry - Axiom I,6

I, 6. If two planes α, β have a point A in common, then they have at least a second point B in common."""
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

function random_plane_point()
    if rand(Float32) < 0.5f0
        return random_triangle_point(PlaneEdgeLeft, PlaneTopLeft, PlaneTopRight)
    end

    random_triangle_point(PlaneEdgeLeft, PlaneTopRight, PlaneEdgeRight)
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    planeHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPlaneHostId))
    pointAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    pointBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))

    labelAlphaId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAlphaId))
    labelBetaId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBetaId))
    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [labelAlphaId, labelBetaId, labelAId, labelBId,
         pointAId, pointBId,
         planeHostId,
        ])

    set_plane_alpha(state_ptr, planeHostId, 0f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseFadeInPlane)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, PointAColor)

    OdinJuliaBridge.lock_pen_joint1(state_ptr, PointA[1], PointA[2], PenTopZ)
    OdinJuliaBridge.move_pen_joint2(state_ptr, PointA[1], PointA[2], PenTopZ + 0.14f0)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    planeBeta = OdinJuliaBridge.create_new_square(
        state_ptr,
        PlaneEdgeLeft,
        PlaneTopLeft,
        PlaneTopRight,
        PlaneEdgeRight,
        PlaneColor)
    pointA = OdinJuliaBridge.create_new_point(
        state_ptr, PointA, PointAColor, 0f0)
    pointB = OdinJuliaBridge.create_new_point(
        state_ptr, PointB, PointBColor, 0f0)
    labelAlpha = OdinJuliaBridge.create_new_label(
        state_ptr, 'α', LabelAlphaPoint, LabelColor, 16f0)
    labelBeta = OdinJuliaBridge.create_new_label(
        state_ptr, 'β', LabelBetaPoint, LabelColor, 16f0)
    labelA = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', LabelAPoint, LabelColor, 16f0)
    labelB = OdinJuliaBridge.create_new_label(
        state_ptr, 'B', LabelBPoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPlaneHostId, Float32(planeBeta.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointAId, Float32(pointA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointBId, Float32(pointB.index))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAlphaId, Float32(labelAlpha.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBetaId, Float32(labelBeta.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAId, Float32(labelA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBId, Float32(labelB.index))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    planeHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPlaneHostId))
    pointAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    pointBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))

    labelAlphaId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAlphaId))
    labelBetaId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBetaId))
    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))

    if planeHostId < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseFadeInPlane
        set_plane_alpha(state_ptr, planeHostId, (timer / FadeInDuration) * PlaneMaxAlpha01)
        OdinJuliaBridge.show_point(state_ptr, planeHostId)

        for _ in 1:FlickerSamplesPerFrame
            samplePos = random_plane_point()
            OdinJuliaBridge.emit_flicker_particle(state_ptr, samplePos, FlickerColor)
        end

        if timer >= FadeInDuration * 0.35f0
            OdinJuliaBridge.show_point(state_ptr, labelAlphaId)
            OdinJuliaBridge.show_point(state_ptr, labelBetaId)
        end

        timer += dt
        if timer >= FadeInDuration
            phase = PhaseDescendToA
            timer = 0f0
            set_plane_alpha(state_ptr, planeHostId, PlaneMaxAlpha01)
        end
    elseif phase == PhaseDescendToA
        set_plane_alpha(state_ptr, planeHostId, PlaneMaxAlpha01)
        OdinJuliaBridge.show_point(state_ptr, planeHostId)
        OdinJuliaBridge.show_pen(state_ptr)

        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, PointA[1], PointA[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhasePutPointA
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelAId)
        end
    elseif phase == PhasePutPointA
        set_plane_alpha(state_ptr, planeHostId, PlaneMaxAlpha01)
        OdinJuliaBridge.show_point(state_ptr, planeHostId)

        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointTrailDuration, PointA,
            PointMaxBrush, PointAColor, pointAId)

        timer += dt
        if timer >= PointTrailDuration
            phase = PhaseMoveToPointB
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointB
        set_plane_alpha(state_ptr, planeHostId, PlaneMaxAlpha01)
        OdinJuliaBridge.show_point(state_ptr, planeHostId)

        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, MoveToPointBDuration,
            PointA, PointB, 0.25f0, 1, :none)

        timer += dt
        if timer >= MoveToPointBDuration
            phase = PhasePutPointB
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelBId)
        end
    elseif phase == PhasePutPointB
        set_plane_alpha(state_ptr, planeHostId, PlaneMaxAlpha01)
        OdinJuliaBridge.show_point(state_ptr, planeHostId)

        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointTrailDuration, PointB,
            PointMaxBrush, PointBColor, pointBId)

        timer += dt
        if timer >= PointTrailDuration
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        set_plane_alpha(state_ptr, planeHostId, PlaneMaxAlpha01)
        OdinJuliaBridge.show_point(state_ptr, planeHostId)

        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ, PointB[1], PointB[2])

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

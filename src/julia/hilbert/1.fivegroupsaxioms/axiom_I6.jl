module HilbertChapterOneAxiomI6

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

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
const StartHoldDuration = 1f0

const MetaPlaneHostId = 1
const MetaPointAId = 11
const MetaPointBId = 12
const MetaLabelAlphaId = 21
const MetaLabelBetaId = 22
const MetaLabelAId = 23
const MetaLabelBId = 24
const MetaPhase = 101
const MetaTimer = 102

const PhaseStartHold = 0f0
const PhaseFadeInPlane = 1f0
const PhaseDescendToA = 2f0
const PhasePutPointA = 3f0
const PhaseMoveToPointB = 4f0
const PhasePutPointB = 5f0
const PhaseEndLift = 6f0

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - Axiom I,6

I, 6. If two planes α, β have a point A in common, then they have at least a second point B in common."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - Axiom I,6}

\textbf{I, 6.} If two planes $\alpha$, $\beta$ have a point $A$ \euclidpoint[color=steelblue,size=1] in common, then they have at least a second point $B$ \euclidpoint[color=palevioletred1,size=1] in common."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Set the plane's fill alpha from a normalized [0, 1] opacity."""
function set_plane_alpha(state_ptr::Ptr{Cvoid}, host_id, alpha01)
    t = clamp(alpha01, 0f0, PlaneMaxAlpha01)
    alpha = UInt8(round(Int, PlaneBaseColor.a * t))
    color = OdinJuliaBridge.BridgeColor(
        PlaneBaseColor.r,
        PlaneBaseColor.g,
        PlaneBaseColor.b,
        alpha)
    OdinJuliaBridge.set_point_color(state_ptr, host_id, color)
end

"""Pick a random interior point of the triangle with vertices a, b, and c."""
function random_triangle_point(
    a::Vector{Float32}, b::Vector{Float32}, c::Vector{Float32})
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

"""Pick a random interior point of the plane built from the current vertices."""
function random_plane_point()
    if rand(Float32) < 0.5f0
        return random_triangle_point(PlaneEdgeLeft, PlaneTopLeft, PlaneTopRight)
    end

    random_triangle_point(PlaneEdgeLeft, PlaneTopRight, PlaneEdgeRight)
end

"""Reset the state of the animation cycle back to the start of the animation"""
function reset_cycle_state(state_ptr::Ptr{Cvoid})
    plane_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaPlaneHostId))
    point_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    point_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))

    label_alpha_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLabelAlphaId))
    label_beta_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLabelBetaId))
    label_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    label_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [
            plane_host_id,
            label_alpha_id, label_beta_id, label_a_id, label_b_id,
            point_a_id, point_b_id,
        ])

    set_plane_alpha(state_ptr, plane_host_id, 0f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseStartHold)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, PointAColor)

    OdinJuliaBridge.lock_pen_joint1(state_ptr, PointA[1], PointA[2], PenTopZ)
    OdinJuliaBridge.move_pen_joint2(state_ptr, PointA[1], PointA[2], PenTopZ + 0.14f0)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    plane_beta = OdinJuliaBridge.create_new_square(state_ptr,
        PlaneEdgeLeft, PlaneTopLeft, PlaneTopRight, PlaneEdgeRight, PlaneColor)
    point_a = OdinJuliaBridge.create_new_point(
        state_ptr, PointA, PointAColor, 0f0)
    point_b = OdinJuliaBridge.create_new_point(
        state_ptr, PointB, PointBColor, 0f0)
    label_alpha = OdinJuliaBridge.create_new_label(
        state_ptr, 'α', LabelAlphaPoint, LabelColor, 16f0)
    label_beta = OdinJuliaBridge.create_new_label(
        state_ptr, 'β', LabelBetaPoint, LabelColor, 16f0)
    label_a = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', LabelAPoint, LabelColor, 16f0)
    label_b = OdinJuliaBridge.create_new_label(
        state_ptr, 'B', LabelBPoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPlaneHostId, plane_beta.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointAId, point_a.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointBId, point_b.index)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAlphaId, label_alpha.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBetaId, label_beta.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAId, label_a.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBId, label_b.index)

    reset_cycle_state(state_ptr)
end

"""Clean any extra animation data at the end of performance"""
function clean(state_ptr::Ptr{Cvoid})
end

"""Perform an iteration of the animation loop for this animation"""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    plane_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaPlaneHostId))
    point_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    point_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))

    label_alpha_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLabelAlphaId))
    label_beta_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLabelBetaId))
    label_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    label_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))

    if plane_host_id < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseStartHold
        timer += dt
        if timer >= StartHoldDuration
            phase = PhaseFadeInPlane
            timer = 0f0
        end
    elseif phase == PhaseFadeInPlane
        set_plane_alpha(
            state_ptr, plane_host_id, (timer / FadeInDuration) * PlaneMaxAlpha01)
        OdinJuliaBridge.show_point(state_ptr, plane_host_id)

        for _ in 1:FlickerSamplesPerFrame
            sample_pos = random_plane_point()
            OdinJuliaBridge.emit_flicker_particle(state_ptr, sample_pos, FlickerColor)
        end

        if timer >= FadeInDuration * 0.35f0
            OdinJuliaBridge.show_point(state_ptr, label_alpha_id)
            OdinJuliaBridge.show_point(state_ptr, label_beta_id)
        end

        timer += dt
        if timer >= FadeInDuration
            phase = PhaseDescendToA
            timer = 0f0
            set_plane_alpha(state_ptr, plane_host_id, PlaneMaxAlpha01)
        end
    elseif phase == PhaseDescendToA
        set_plane_alpha(state_ptr, plane_host_id, PlaneMaxAlpha01)
        OdinJuliaBridge.show_point(state_ptr, plane_host_id)
        OdinJuliaBridge.show_pen(state_ptr)

        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, PointA[1], PointA[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhasePutPointA
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_a_id)
        end
    elseif phase == PhasePutPointA
        set_plane_alpha(state_ptr, plane_host_id, PlaneMaxAlpha01)
        OdinJuliaBridge.show_point(state_ptr, plane_host_id)

        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointTrailDuration, PointA,
            PointMaxBrush, PointAColor, point_a_id)

        timer += dt
        if timer >= PointTrailDuration
            phase = PhaseMoveToPointB
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointB
        set_plane_alpha(state_ptr, plane_host_id, PlaneMaxAlpha01)
        OdinJuliaBridge.show_point(state_ptr, plane_host_id)

        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, MoveToPointBDuration,
            PointA, PointB, 0.25f0, 1, :none)

        timer += dt
        if timer >= MoveToPointBDuration
            phase = PhasePutPointB
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_b_id)
        end
    elseif phase == PhasePutPointB
        set_plane_alpha(state_ptr, plane_host_id, PlaneMaxAlpha01)
        OdinJuliaBridge.show_point(state_ptr, plane_host_id)

        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointTrailDuration, PointB,
            PointMaxBrush, PointBColor, point_b_id)

        timer += dt
        if timer >= PointTrailDuration
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        set_plane_alpha(state_ptr, plane_host_id, PlaneMaxAlpha01)
        OdinJuliaBridge.show_point(state_ptr, plane_host_id)

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

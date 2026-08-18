module HilbertChapterOneTheorem14

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

export get_view_text, initialize, clean, loop

const PointO = [0.18f0, 0.70f0, 0f0]
const RayHEnd = [0.50f0, 0.58f0, 0f0]
const RayKEnd = [0.42f0, 0.94f0, 0f0]
const RayLEnd = [0.58f0, 0.83f0, 0f0]

const PointOPrime = [0.63f0, 0.27f0, 0f0]
const RayHPrimeEnd = [0.95f0, 0.15f0, 0f0]
const RayKPrimeEnd = [0.87f0, 0.51f0, 0f0]
const RayLPrimeEnd = [0.98f0, 0.40f0, 0f0]

const RayHStart = PointO
const RayKStart = PointO
const RayLStart = PointO
const RayHPrimeStart = PointOPrime
const RayKPrimeStart = PointOPrime
const RayLPrimeStart = PointOPrime

const MarkerRadius = 0.08f0

const ThetaOH = Float32(atan(RayHEnd[2] - PointO[2], RayHEnd[1] - PointO[1]))
const ThetaOK = Float32(atan(RayKEnd[2] - PointO[2], RayKEnd[1] - PointO[1]))
const ThetaOL = Float32(atan(RayLEnd[2] - PointO[2], RayLEnd[1] - PointO[1]))

const ThetaOPrimeH = Float32(atan(
    RayHPrimeEnd[2] - PointOPrime[2], RayHPrimeEnd[1] - PointOPrime[1]))
const ThetaOPrimeK = Float32(atan(
    RayKPrimeEnd[2] - PointOPrime[2], RayKPrimeEnd[1] - PointOPrime[1]))
const ThetaOPrimeL = Float32(atan(
    RayLPrimeEnd[2] - PointOPrime[2], RayLPrimeEnd[1] - PointOPrime[1]))

const MarkerHStart = [
    PointO[1] + MarkerRadius * Float32(cos(ThetaOH)),
    PointO[2] + MarkerRadius * Float32(sin(ThetaOH)),
    0f0,
]
const MarkerKStart = [
    PointO[1] + MarkerRadius * Float32(cos(ThetaOK)),
    PointO[2] + MarkerRadius * Float32(sin(ThetaOK)),
    0f0,
]
const MarkerLStart = [
    PointO[1] + MarkerRadius * Float32(cos(ThetaOL)),
    PointO[2] + MarkerRadius * Float32(sin(ThetaOL)),
    0f0,
]

const MarkerHPrimeStart = [
    PointOPrime[1] + MarkerRadius * Float32(cos(ThetaOPrimeH)),
    PointOPrime[2] + MarkerRadius * Float32(sin(ThetaOPrimeH)),
    0f0,
]
const MarkerKPrimeStart = [
    PointOPrime[1] + MarkerRadius * Float32(cos(ThetaOPrimeK)),
    PointOPrime[2] + MarkerRadius * Float32(sin(ThetaOPrimeK)),
    0f0,
]
const MarkerLPrimeStart = [
    PointOPrime[1] + MarkerRadius * Float32(cos(ThetaOPrimeL)),
    PointOPrime[2] + MarkerRadius * Float32(sin(ThetaOPrimeL)),
    0f0,
]

const AngleHLTheta = ThetaOL - ThetaOH
const AngleKLTheta = ThetaOL - ThetaOK
const AngleHKTheta = ThetaOK - ThetaOH
const AngleHPrimeLPrimeTheta = ThetaOPrimeL - ThetaOPrimeH
const AngleKPrimeLPrimeTheta = ThetaOPrimeL - ThetaOPrimeK
const AngleHPrimeKPrimeTheta = ThetaOPrimeK - ThetaOPrimeH

const LabelColor = :plum1
const HighlightColor = :lightgreen
const RayHColor = :steelblue
const RayKColor = :palevioletred1
const RayLColor = :grey60

const EdgeBrush = 5f0
const PenTopZ = 1.4f0
const CompassTopZ = 1.4f0
const ToolResetOffscreenJoint1 = [0.50f0, 1.25f0, 1.55f0]
const ToolResetOffscreenJoint2 = [0.57f0, 1.25f0, 1.55f0]

const LabelHPoint = RayHEnd + [0.03f0, -0.01f0, 0f0]
const LabelKPoint = RayKEnd + [0.01f0, 0.03f0, 0f0]
const LabelLPoint = RayLEnd + [0.02f0, 0.03f0, 0f0]
const LabelHPrimePoint = RayHPrimeEnd + [0.03f0, -0.01f0, 0f0]
const LabelKPrimePoint = RayKPrimeEnd + [0.01f0, 0.03f0, 0f0]
const LabelLPrimePoint = RayLPrimeEnd + [0.02f0, 0.03f0, 0f0]

const DescendDuration = 1.8f0
const DrawEdgeDuration = 2.2f0
const ArcMoveDuration = 1.35f0
const DragDuration = 1.25f0
const PenLiftDuration = 1.6f0
const CompassLiftDuration = 1.8f0
const CompassSweepDuration = 0.95f0
const FinalHoldDuration = 0.35f0

const MetaRayHHostId = 1
const MetaRayHJoint1Id = 2
const MetaRayHJoint2Id = 3
const MetaRayKHostId = 11
const MetaRayKJoint1Id = 12
const MetaRayKJoint2Id = 13
const MetaRayLHostId = 21
const MetaRayLJoint1Id = 22
const MetaRayLJoint2Id = 23
const MetaRayHPrimeHostId = 31
const MetaRayHPrimeJoint1Id = 32
const MetaRayHPrimeJoint2Id = 33
const MetaRayKPrimeHostId = 41
const MetaRayKPrimeJoint1Id = 42
const MetaRayKPrimeJoint2Id = 43
const MetaRayLPrimeHostId = 51
const MetaRayLPrimeJoint1Id = 52
const MetaRayLPrimeJoint2Id = 53

const MetaLabelHId = 61
const MetaLabelKId = 62
const MetaLabelLId = 63
const MetaLabelHPrimeId = 64
const MetaLabelKPrimeId = 65
const MetaLabelLPrimeId = 66

const MetaPhase = 101
const MetaTimer = 102

const PhaseDescendToO = 0f0
const PhaseDrawRayH = 1f0
const PhaseArcHToO = 2f0
const PhaseDrawRayK = 3f0
const PhaseArcKToO = 4f0
const PhaseDrawRayL = 5f0
const PhaseArcLToOPrime = 6f0
const PhaseDrawRayHPrime = 7f0
const PhaseArcHPrimeToOPrime = 8f0
const PhaseDrawRayKPrime = 9f0
const PhaseArcKPrimeToOPrime = 10f0
const PhaseDrawRayLPrime = 11f0
const PhasePenRiseBeforeCompass = 12f0

const PhaseCompassDescendHL = 13f0
const PhaseHighlightHLForward = 14f0
const PhaseHighlightHLBack = 15f0
const PhaseCompassArcHLToPrime = 16f0
const PhaseHighlightHPrimeLPrimeForward = 17f0
const PhaseHighlightHPrimeLPrimeBack = 18f0
const PhaseCompassArcPrimeToKL = 19f0
const PhaseHighlightKLForward = 20f0
const PhaseHighlightKLBack = 21f0
const PhaseCompassArcKLToPrime = 22f0
const PhaseHighlightKPrimeLPrimeForward = 23f0
const PhaseHighlightKPrimeLPrimeBack = 24f0
const PhaseCompassArcPrimeToHK = 25f0
const PhaseHighlightHKForward = 26f0
const PhaseHighlightHKBack = 27f0
const PhaseCompassArcHKToPrime = 28f0
const PhaseHighlightHPrimeKPrimeForward = 29f0
const PhaseHighlightHPrimeKPrimeBack = 30f0
const PhaseCompassRise = 31f0
const PhaseFinalHold = 32f0


function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - Theorem 14

Let h, k, l and h', k', l' be two sets of three half-rays, where those of each set emanate from the same point and lie in the same plane. Then, if the congruences

    ∠(h, l) ≡ ∠(h', l'),   ∠(k, l) ≡ ∠(k', l')

are fulfilled, the following congruence is also valid; viz.:

    ∠(h, k) ≡ ∠(h', k')."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - Theorem 14}

Let $h$ \euclidline[color=steelblue,length=3,thickness=4], $k$ \euclidline[color=palevioletred1,length=3,thickness=4],
$l$ \euclidline[color=grey60,length=3,thickness=4] and
$h'$ \euclidline[color=steelblue,length=3,thickness=4], $k'$ \euclidline[color=palevioletred1,length=3,thickness=4],
$l'$ \euclidline[color=grey60,length=3,thickness=4] be two sets of three half-rays, where those of each set emanate
from the same point and lie in the same plane. Then, if the congruences

    $\angle(h, l) \equiv \angle(h', l')$ \euclidangle[color=lightgreen,radius=2,end=60,filled],   $\angle(k, l) \equiv \angle(k', l')$ \euclidangle[color=lightgreen,radius=2,end=60,filled]

are fulfilled, the following congruence is also valid; viz.:

    $\angle(h, k) \equiv \angle(h', k')$ \euclidangle[color=lightgreen,radius=2,end=60,filled]."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    ray_h_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHHostId))
    ray_h_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHJoint2Id))
    ray_k_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKHostId))
    ray_k_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKJoint2Id))
    ray_l_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayLHostId))
    ray_l_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayLJoint2Id))

    ray_h_prime_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHPrimeHostId))
    ray_h_prime_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHPrimeJoint2Id))
    ray_k_prime_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKPrimeHostId))
    ray_k_prime_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKPrimeJoint2Id))
    ray_l_prime_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayLPrimeHostId))
    ray_l_prime_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayLPrimeJoint2Id))

    label_h_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelHId))
    label_k_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelKId))
    label_l_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelLId))
    label_h_prime_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelHPrimeId))
    label_k_prime_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelKPrimeId))
    label_l_prime_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelLPrimeId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [ray_h_host_id, ray_k_host_id, ray_l_host_id,
         ray_h_prime_host_id, ray_k_prime_host_id, ray_l_prime_host_id,
         label_h_id, label_k_id, label_l_id, label_h_prime_id, label_k_prime_id, label_l_prime_id])

    OdinJuliaBridge.set_point_position(state_ptr, ray_h_joint2_id, RayHStart)
    OdinJuliaBridge.set_point_position(state_ptr, ray_k_joint2_id, RayKStart)
    OdinJuliaBridge.set_point_position(state_ptr, ray_l_joint2_id, RayLStart)
    OdinJuliaBridge.set_point_position(state_ptr, ray_h_prime_joint2_id, RayHPrimeStart)
    OdinJuliaBridge.set_point_position(state_ptr, ray_k_prime_joint2_id, RayKPrimeStart)
    OdinJuliaBridge.set_point_position(state_ptr, ray_l_prime_joint2_id, RayLPrimeStart)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescendToO)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.hide_compass(state_ptr)
    OdinJuliaBridge.lock_pen_joint1(
        state_ptr, ToolResetOffscreenJoint1[1], ToolResetOffscreenJoint1[2],
        ToolResetOffscreenJoint1[3])
    OdinJuliaBridge.move_pen_joint2(
        state_ptr, ToolResetOffscreenJoint2[1], ToolResetOffscreenJoint2[2],
        ToolResetOffscreenJoint2[3])
    OdinJuliaBridge.lock_compass_joint1(
        state_ptr, ToolResetOffscreenJoint1[1], ToolResetOffscreenJoint1[2],
        ToolResetOffscreenJoint1[3], sweep = false)
    OdinJuliaBridge.lock_compass_joint2(
        state_ptr, ToolResetOffscreenJoint2[1], ToolResetOffscreenJoint2[2],
        ToolResetOffscreenJoint2[3], sweep = false)

    OdinJuliaBridge.set_pen_active(state_ptr, 0, RayHColor)
    OdinJuliaBridge.set_compass_active(state_ptr, 0, HighlightColor)
    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    ray_h = OdinJuliaBridge.create_new_line(state_ptr, RayHStart, RayHStart, RayHColor, 0f0)
    ray_k = OdinJuliaBridge.create_new_line(state_ptr, RayKStart, RayKStart, RayKColor, 0f0)
    ray_l = OdinJuliaBridge.create_new_line(state_ptr, RayLStart, RayLStart, RayLColor, 0f0)

    ray_h_prime = OdinJuliaBridge.create_new_line(
        state_ptr, RayHPrimeStart, RayHPrimeStart, RayHColor, 0f0)
    ray_k_prime = OdinJuliaBridge.create_new_line(
        state_ptr, RayKPrimeStart, RayKPrimeStart, RayKColor, 0f0)
    ray_l_prime = OdinJuliaBridge.create_new_line(
        state_ptr, RayLPrimeStart, RayLPrimeStart, RayLColor, 0f0)

    label_h = OdinJuliaBridge.create_new_label(state_ptr, 'h', LabelHPoint, LabelColor, 16f0)
    label_k = OdinJuliaBridge.create_new_label(state_ptr, 'k', LabelKPoint, LabelColor, 16f0)
    label_l = OdinJuliaBridge.create_new_label(state_ptr, 'l', LabelLPoint, LabelColor, 16f0)
    label_h_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'h', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelHPrimePoint, LabelColor, 16f0)
    label_k_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'k', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelKPrimePoint, LabelColor, 16f0)
    label_l_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'l', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelLPrimePoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayHHostId, Float32(ray_h.host_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayHJoint1Id, Float32(ray_h.joint1_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayHJoint2Id, Float32(ray_h.joint2_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayKHostId, Float32(ray_k.host_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayKJoint1Id, Float32(ray_k.joint1_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayKJoint2Id, Float32(ray_k.joint2_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayLHostId, Float32(ray_l.host_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayLJoint1Id, Float32(ray_l.joint1_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayLJoint2Id, Float32(ray_l.joint2_id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayHPrimeHostId, Float32(ray_h_prime.host_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayHPrimeJoint1Id, Float32(ray_h_prime.joint1_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayHPrimeJoint2Id, Float32(ray_h_prime.joint2_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayKPrimeHostId, Float32(ray_k_prime.host_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayKPrimeJoint1Id, Float32(ray_k_prime.joint1_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayKPrimeJoint2Id, Float32(ray_k_prime.joint2_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayLPrimeHostId, Float32(ray_l_prime.host_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayLPrimeJoint1Id, Float32(ray_l_prime.joint1_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayLPrimeJoint2Id, Float32(ray_l_prime.joint2_id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelHId, Float32(label_h.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelKId, Float32(label_k.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelLId, Float32(label_l.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelHPrimeId, Float32(label_h_prime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelKPrimeId, Float32(label_k_prime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelLPrimeId, Float32(label_l_prime.index))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    ray_h_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHHostId))
    ray_h_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHJoint1Id))
    ray_h_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHJoint2Id))
    ray_k_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKHostId))
    ray_k_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKJoint1Id))
    ray_k_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKJoint2Id))
    ray_l_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayLHostId))
    ray_l_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayLJoint1Id))
    ray_l_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayLJoint2Id))

    ray_h_prime_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHPrimeHostId))
    ray_h_prime_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHPrimeJoint1Id))
    ray_h_prime_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHPrimeJoint2Id))
    ray_k_prime_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKPrimeHostId))
    ray_k_prime_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKPrimeJoint1Id))
    ray_k_prime_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKPrimeJoint2Id))
    ray_l_prime_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayLPrimeHostId))
    ray_l_prime_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayLPrimeJoint1Id))
    ray_l_prime_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayLPrimeJoint2Id))

    label_h_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelHId))
    label_k_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelKId))
    label_l_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelLId))
    label_h_prime_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelHPrimeId))
    label_k_prime_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelKPrimeId))
    label_l_prime_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelLPrimeId))

    if ray_h_host_id < 0 || ray_k_host_id < 0 || ray_l_host_id < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescendToO
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, PointO[1], PointO[2])
        timer += dt
        if timer >= DescendDuration
            OdinJuliaBridge.set_pen_active(state_ptr, 0, RayHColor)
            phase = PhaseDrawRayH
            timer = 0f0
        end
    elseif phase == PhaseDrawRayH
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawEdgeDuration, RayHStart, RayHEnd,
            EdgeBrush, RayHColor, ray_h_host_id, ray_h_joint1_id, ray_h_joint2_id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, label_h_id)
            phase = PhaseArcHToO
            timer = 0f0
        end
    elseif phase == PhaseArcHToO
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, RayHEnd, PointO, 0.20f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.set_pen_active(state_ptr, 0, RayKColor)
            phase = PhaseDrawRayK
            timer = 0f0
        end
    elseif phase == PhaseDrawRayK
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawEdgeDuration, RayKStart, RayKEnd,
            EdgeBrush, RayKColor, ray_k_host_id, ray_k_joint1_id, ray_k_joint2_id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, label_k_id)
            phase = PhaseArcKToO
            timer = 0f0
        end
    elseif phase == PhaseArcKToO
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, RayKEnd, PointO, 0.20f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.set_pen_active(state_ptr, 0, RayLColor)
            phase = PhaseDrawRayL
            timer = 0f0
        end
    elseif phase == PhaseDrawRayL
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawEdgeDuration, RayLStart, RayLEnd,
            EdgeBrush, RayLColor, ray_l_host_id, ray_l_joint1_id, ray_l_joint2_id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, label_l_id)
            phase = PhaseArcLToOPrime
            timer = 0f0
        end
    elseif phase == PhaseArcLToOPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, RayLEnd, PointOPrime, 0.30f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.set_pen_active(state_ptr, 0, RayHColor)
            phase = PhaseDrawRayHPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawRayHPrime
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawEdgeDuration, RayHPrimeStart, RayHPrimeEnd,
            EdgeBrush, RayHColor, ray_h_prime_host_id, ray_h_prime_joint1_id, ray_h_prime_joint2_id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, label_h_prime_id)
            phase = PhaseArcHPrimeToOPrime
            timer = 0f0
        end
    elseif phase == PhaseArcHPrimeToOPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, RayHPrimeEnd, PointOPrime, 0.20f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.set_pen_active(state_ptr, 0, RayKColor)
            phase = PhaseDrawRayKPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawRayKPrime
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawEdgeDuration, RayKPrimeStart, RayKPrimeEnd,
            EdgeBrush, RayKColor, ray_k_prime_host_id, ray_k_prime_joint1_id, ray_k_prime_joint2_id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, label_k_prime_id)
            phase = PhaseArcKPrimeToOPrime
            timer = 0f0
        end
    elseif phase == PhaseArcKPrimeToOPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, RayKPrimeEnd, PointOPrime, 0.20f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.set_pen_active(state_ptr, 0, RayLColor)
            phase = PhaseDrawRayLPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawRayLPrime
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawEdgeDuration, RayLPrimeStart, RayLPrimeEnd,
            EdgeBrush, RayLColor, ray_l_prime_host_id, ray_l_prime_joint1_id, ray_l_prime_joint2_id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, label_l_prime_id)
            phase = PhasePenRiseBeforeCompass
            timer = 0f0
        end
    elseif phase == PhasePenRiseBeforeCompass
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ, RayLPrimeEnd[1], RayLPrimeEnd[2])
        timer += dt
        if timer >= PenLiftDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseCompassDescendHL
            timer = 0f0
        end

    elseif phase == PhaseCompassDescendHL
        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, DescendDuration, CompassTopZ,
            PointO[1], PointO[2], MarkerHStart[1], MarkerHStart[2])
        timer += dt
        if timer >= DescendDuration
            phase = PhaseHighlightHLForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightHLForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointO, MarkerHStart, AngleHLTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightHLBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightHLBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointO, MarkerLStart, -AngleHLTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcHLToPrime
            timer = 0f0
        end
    elseif phase == PhaseCompassArcHLToPrime
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointO, PointOPrime,
            MarkerHStart, MarkerHPrimeStart, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightHPrimeLPrimeForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightHPrimeLPrimeForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointOPrime, MarkerHPrimeStart,
            AngleHPrimeLPrimeTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightHPrimeLPrimeBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightHPrimeLPrimeBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointOPrime, MarkerLPrimeStart,
            -AngleHPrimeLPrimeTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcPrimeToKL
            timer = 0f0
        end
    elseif phase == PhaseCompassArcPrimeToKL
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointOPrime, PointO,
            MarkerHPrimeStart, MarkerKStart, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightKLForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightKLForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointO, MarkerKStart, AngleKLTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightKLBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightKLBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointO, MarkerLStart, -AngleKLTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcKLToPrime
            timer = 0f0
        end
    elseif phase == PhaseCompassArcKLToPrime
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointO, PointOPrime,
            MarkerKStart, MarkerKPrimeStart, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightKPrimeLPrimeForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightKPrimeLPrimeForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointOPrime, MarkerKPrimeStart,
            AngleKPrimeLPrimeTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightKPrimeLPrimeBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightKPrimeLPrimeBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointOPrime, MarkerLPrimeStart,
            -AngleKPrimeLPrimeTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcPrimeToHK
            timer = 0f0
        end
    elseif phase == PhaseCompassArcPrimeToHK
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointOPrime, PointO,
            MarkerKPrimeStart, MarkerHStart, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightHKForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightHKForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointO, MarkerHStart, AngleHKTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightHKBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightHKBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointO, MarkerKStart, -AngleHKTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcHKToPrime
            timer = 0f0
        end
    elseif phase == PhaseCompassArcHKToPrime
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointO, PointOPrime,
            MarkerHStart, MarkerHPrimeStart, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightHPrimeKPrimeForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightHPrimeKPrimeForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointOPrime, MarkerHPrimeStart,
            AngleHPrimeKPrimeTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightHPrimeKPrimeBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightHPrimeKPrimeBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointOPrime, MarkerKPrimeStart,
            -AngleHPrimeKPrimeTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassRise
            timer = 0f0
        end
    elseif phase == PhaseCompassRise
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassLiftDuration, CompassTopZ,
            PointOPrime[1], PointOPrime[2], MarkerHPrimeStart[1], MarkerHPrimeStart[2])
        timer += dt
        if timer >= CompassLiftDuration
            OdinJuliaBridge.hide_compass(state_ptr)
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

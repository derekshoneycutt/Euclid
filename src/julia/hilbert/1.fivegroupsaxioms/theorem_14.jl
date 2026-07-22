module HilbertChapterOneTheorem14

using ..OdinJuliaBridge
using ..EuclidAnimations

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
    """David Hilbert - Foundations of Geometry - Theorem 14

Let h, k, l and h', k', l' be two sets of three half-rays, where those of each set emanate from the same point and lie in the same plane. Then, if the congruences

    ∠(h, l) ≡ ∠(h', l'),   ∠(k, l) ≡ ∠(k', l')

are fulfilled, the following congruence is also valid; viz.:

    ∠(h, k) ≡ ∠(h', k')."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    rayHHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHHostId))
    rayHJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHJoint2Id))
    rayKHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKHostId))
    rayKJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKJoint2Id))
    rayLHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayLHostId))
    rayLJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayLJoint2Id))

    rayHPrimeHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHPrimeHostId))
    rayHPrimeJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHPrimeJoint2Id))
    rayKPrimeHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKPrimeHostId))
    rayKPrimeJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKPrimeJoint2Id))
    rayLPrimeHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayLPrimeHostId))
    rayLPrimeJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayLPrimeJoint2Id))

    labelHId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelHId))
    labelKId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelKId))
    labelLId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelLId))
    labelHPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelHPrimeId))
    labelKPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelKPrimeId))
    labelLPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelLPrimeId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [rayHHostId, rayKHostId, rayLHostId,
         rayHPrimeHostId, rayKPrimeHostId, rayLPrimeHostId,
         labelHId, labelKId, labelLId, labelHPrimeId, labelKPrimeId, labelLPrimeId])

    OdinJuliaBridge.set_point_position(state_ptr, rayHJoint2Id, RayHStart)
    OdinJuliaBridge.set_point_position(state_ptr, rayKJoint2Id, RayKStart)
    OdinJuliaBridge.set_point_position(state_ptr, rayLJoint2Id, RayLStart)
    OdinJuliaBridge.set_point_position(state_ptr, rayHPrimeJoint2Id, RayHPrimeStart)
    OdinJuliaBridge.set_point_position(state_ptr, rayKPrimeJoint2Id, RayKPrimeStart)
    OdinJuliaBridge.set_point_position(state_ptr, rayLPrimeJoint2Id, RayLPrimeStart)

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
    rayH = OdinJuliaBridge.create_new_line(state_ptr, RayHStart, RayHStart, RayHColor, 0f0)
    rayK = OdinJuliaBridge.create_new_line(state_ptr, RayKStart, RayKStart, RayKColor, 0f0)
    rayL = OdinJuliaBridge.create_new_line(state_ptr, RayLStart, RayLStart, RayLColor, 0f0)

    rayHPrime = OdinJuliaBridge.create_new_line(
        state_ptr, RayHPrimeStart, RayHPrimeStart, RayHColor, 0f0)
    rayKPrime = OdinJuliaBridge.create_new_line(
        state_ptr, RayKPrimeStart, RayKPrimeStart, RayKColor, 0f0)
    rayLPrime = OdinJuliaBridge.create_new_line(
        state_ptr, RayLPrimeStart, RayLPrimeStart, RayLColor, 0f0)

    labelH = OdinJuliaBridge.create_new_label(state_ptr, 'h', LabelHPoint, LabelColor, 16f0)
    labelK = OdinJuliaBridge.create_new_label(state_ptr, 'k', LabelKPoint, LabelColor, 16f0)
    labelL = OdinJuliaBridge.create_new_label(state_ptr, 'l', LabelLPoint, LabelColor, 16f0)
    labelHPrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'h', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelHPrimePoint, LabelColor, 16f0)
    labelKPrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'k', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelKPrimePoint, LabelColor, 16f0)
    labelLPrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'l', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelLPrimePoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayHHostId, Float32(rayH.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayHJoint1Id, Float32(rayH.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayHJoint2Id, Float32(rayH.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayKHostId, Float32(rayK.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayKJoint1Id, Float32(rayK.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayKJoint2Id, Float32(rayK.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayLHostId, Float32(rayL.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayLJoint1Id, Float32(rayL.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayLJoint2Id, Float32(rayL.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayHPrimeHostId, Float32(rayHPrime.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayHPrimeJoint1Id, Float32(rayHPrime.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayHPrimeJoint2Id, Float32(rayHPrime.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayKPrimeHostId, Float32(rayKPrime.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayKPrimeJoint1Id, Float32(rayKPrime.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayKPrimeJoint2Id, Float32(rayKPrime.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayLPrimeHostId, Float32(rayLPrime.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayLPrimeJoint1Id, Float32(rayLPrime.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayLPrimeJoint2Id, Float32(rayLPrime.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelHId, Float32(labelH.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelKId, Float32(labelK.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelLId, Float32(labelL.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelHPrimeId, Float32(labelHPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelKPrimeId, Float32(labelKPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelLPrimeId, Float32(labelLPrime.index))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    rayHHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHHostId))
    rayHJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHJoint1Id))
    rayHJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHJoint2Id))
    rayKHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKHostId))
    rayKJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKJoint1Id))
    rayKJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKJoint2Id))
    rayLHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayLHostId))
    rayLJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayLJoint1Id))
    rayLJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayLJoint2Id))

    rayHPrimeHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHPrimeHostId))
    rayHPrimeJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHPrimeJoint1Id))
    rayHPrimeJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHPrimeJoint2Id))
    rayKPrimeHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKPrimeHostId))
    rayKPrimeJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKPrimeJoint1Id))
    rayKPrimeJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKPrimeJoint2Id))
    rayLPrimeHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayLPrimeHostId))
    rayLPrimeJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayLPrimeJoint1Id))
    rayLPrimeJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayLPrimeJoint2Id))

    labelHId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelHId))
    labelKId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelKId))
    labelLId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelLId))
    labelHPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelHPrimeId))
    labelKPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelKPrimeId))
    labelLPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelLPrimeId))

    if rayHHostId < 0 || rayKHostId < 0 || rayLHostId < 0
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
            EdgeBrush, RayHColor, rayHHostId, rayHJoint1Id, rayHJoint2Id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, labelHId)
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
            EdgeBrush, RayKColor, rayKHostId, rayKJoint1Id, rayKJoint2Id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, labelKId)
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
            EdgeBrush, RayLColor, rayLHostId, rayLJoint1Id, rayLJoint2Id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, labelLId)
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
            EdgeBrush, RayHColor, rayHPrimeHostId, rayHPrimeJoint1Id, rayHPrimeJoint2Id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, labelHPrimeId)
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
            EdgeBrush, RayKColor, rayKPrimeHostId, rayKPrimeJoint1Id, rayKPrimeJoint2Id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, labelKPrimeId)
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
            EdgeBrush, RayLColor, rayLPrimeHostId, rayLPrimeJoint1Id, rayLPrimeJoint2Id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, labelLPrimeId)
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

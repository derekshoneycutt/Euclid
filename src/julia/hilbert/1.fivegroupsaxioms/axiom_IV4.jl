module HilbertChapterOneAxiomIV4

using ..OdinJuliaBridge
using ..EuclidAnimations

export get_view_text, initialize, clean, loop

const VertexO = [0.28f0, 0.66f0, 0f0]
const VertexOPrime = [0.28f0, 0.30f0, 0f0]
const RayLength = 0.34f0
const AngleTheta = 0.98f0

const RayHStart = VertexO
const RayHEnd = [VertexO[1] + RayLength, VertexO[2], 0f0]
const RayKStart = VertexO
const RayKEnd = [
    VertexO[1] + RayLength * Float32(cos(AngleTheta)),
    VertexO[2] + RayLength * Float32(sin(AngleTheta)),
    0f0,
]

const RayHPrimeStart = VertexOPrime
const RayHPrimeEnd = [VertexOPrime[1] + RayLength, VertexOPrime[2], 0f0]
const RayKPrimeStart = VertexOPrime
const RayKPrimeEnd = [
    VertexOPrime[1] + RayLength * Float32(cos(AngleTheta)),
    VertexOPrime[2] + RayLength * Float32(sin(AngleTheta)),
    0f0,
]

const MarkerRadius = 0.12f0
const Marker1Start = [VertexO[1] + MarkerRadius, VertexO[2], 0f0]
const Marker1End = [
    VertexO[1] + MarkerRadius * Float32(cos(AngleTheta)),
    VertexO[2] + MarkerRadius * Float32(sin(AngleTheta)),
    0f0,
]
const Marker2Start = [VertexOPrime[1] + MarkerRadius, VertexOPrime[2], 0f0]
const Marker2End = [
    VertexOPrime[1] + MarkerRadius * Float32(cos(AngleTheta)),
    VertexOPrime[2] + MarkerRadius * Float32(sin(AngleTheta)),
    0f0,
]

const LabelColor = :plum1
const HighlightColor = :lightgreen
const RayHColor = :steelblue
const RayKColor = :palevioletred1
const RayHPrimeColor = :khaki3
const RayKPrimeColor = :grey60
const MarkerColor = :khaki3

const RayBrush = 5f0
const MarkerBrush = 1f0
const ResetPenLength = 0.14f0

const LabelOPoint = VertexO + [-0.02f0, 0.07f0, 0f0]
const LabelHPoint = RayHEnd + [0.02f0, 0.055f0, 0f0]
const LabelKPoint = RayKEnd + [0.02f0, 0.055f0, 0f0]
const LabelOPrimePoint = VertexOPrime + [-0.02f0, 0.07f0, 0f0]
const LabelHPrimePoint = RayHPrimeEnd + [0.02f0, 0.055f0, 0f0]
const LabelKPrimePoint = RayKPrimeEnd + [0.02f0, 0.055f0, 0f0]

const PenTopZ = 1.4f0
const CompassTopZ = 1.4f0

const DescendDuration = 1.8f0
const DrawRayDuration = 2.4f0
const ArcMoveDuration = 1.4f0
const PenLiftDuration = 1.6f0
const MarkerDrawDuration = 1.2f0
const CompassLiftDuration = 1.8f0
const CompassSweepDuration = 1.0f0
const FinalHoldDuration = 0.9f0

const MetaRayHHostId = 1
const MetaRayHJoint1Id = 2
const MetaRayHJoint2Id = 3
const MetaRayKHostId = 11
const MetaRayKJoint1Id = 12
const MetaRayKJoint2Id = 13
const MetaRayHPrimeHostId = 21
const MetaRayHPrimeJoint1Id = 22
const MetaRayHPrimeJoint2Id = 23
const MetaRayKPrimeHostId = 31
const MetaRayKPrimeJoint1Id = 32
const MetaRayKPrimeJoint2Id = 33

const MetaMarker1HostId = 41
const MetaMarker1StartId = 42
const MetaMarker1EndId = 43
const MetaMarker2HostId = 44
const MetaMarker2StartId = 45
const MetaMarker2EndId = 46

const MetaLabelOId = 61
const MetaLabelHId = 62
const MetaLabelKId = 63
const MetaLabelOPrimeId = 64
const MetaLabelHPrimeId = 65
const MetaLabelKPrimeId = 66

const MetaPhase = 101
const MetaTimer = 102

const PhaseDescendToO = 0f0
const PhaseDrawRayH = 1f0
const PhaseArcToOForK = 2f0
const PhaseDrawRayK = 3f0
const PhasePenLiftForMarker1 = 4f0
const PhaseDrawMarker1 = 5f0
const PhaseCompassLiftAfterMarker1 = 6f0
const PhaseDescendToOPrime = 7f0
const PhaseDrawRayHPrime = 8f0
const PhaseArcToOPrimeForKPrime = 9f0
const PhaseDrawRayKPrime = 10f0
const PhasePenLiftForMarker2 = 11f0
const PhaseDrawMarker2 = 12f0
const PhaseCompassArcToMarker1 = 13f0
const PhaseHighlight1Forward = 14f0
const PhaseHighlight1Back = 15f0
const PhaseCompassArcToMarker2 = 16f0
const PhaseHighlight2Forward = 17f0
const PhaseHighlight2Back = 18f0
const PhaseCompassLiftEnd = 19f0
const PhaseFinalHold = 20f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """David Hilbert - Foundations of Geometry - Axiom IV,4

IV, 4. Let an angle (h, k) be given in the plane α and let a straight line a' be given in a plane α'. Suppose also that, in the plane α, a definite side of the straight line a' be assigned. Denote by h' a half-ray of the straight line a' emanating from a point O' of this line. Then in the plane α' there is one and only one half-ray k' such that the angle (h, k), or (k, h), is congruent to the angle (h', k') and that at the same time all interior points of the angle (h', k') lie upon the given side of a'. We express this relation by means of the notation

∠(h, k) ≡ ∠(h', k')

Every angle is congruent to itself; that is,

∠(h, k) ≡ ∠(h, k)

or

∠(h, k) ≡ ∠(k, h)

We say, briefly, that every angle in a given plane can be laid off upon a given side of a given half-ray in one and only one way."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    rayHHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHHostId))
    rayHJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHJoint2Id))
    rayKHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKHostId))
    rayKJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKJoint2Id))
    rayHPrimeHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHPrimeHostId))
    rayHPrimeJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHPrimeJoint2Id))
    rayKPrimeHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKPrimeHostId))
    rayKPrimeJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKPrimeJoint2Id))

    marker1HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker1HostId))
    marker1EndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker1EndId))
    marker2HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker2HostId))
    marker2EndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker2EndId))

    labelOId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelOId))
    labelHId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelHId))
    labelKId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelKId))
    labelOPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelOPrimeId))
    labelHPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelHPrimeId))
    labelKPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelKPrimeId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [rayHHostId, rayKHostId, rayHPrimeHostId, rayKPrimeHostId,
         marker1HostId, marker2HostId,
         labelOId, labelHId, labelKId, labelOPrimeId, labelHPrimeId, labelKPrimeId])

    OdinJuliaBridge.set_point_position(state_ptr, rayHJoint2Id, RayHStart)
    OdinJuliaBridge.set_point_position(state_ptr, rayKJoint2Id, RayKStart)
    OdinJuliaBridge.set_point_position(state_ptr, rayHPrimeJoint2Id, RayHPrimeStart)
    OdinJuliaBridge.set_point_position(state_ptr, rayKPrimeJoint2Id, RayKPrimeStart)

    OdinJuliaBridge.set_point_position(state_ptr, marker1EndId, Marker1Start)
    OdinJuliaBridge.set_point_position(state_ptr, marker2EndId, Marker2Start)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescendToO)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.hide_compass(state_ptr)
    OdinJuliaBridge.lock_pen_joint1(state_ptr, VertexO[1], VertexO[2], PenTopZ)
    OdinJuliaBridge.move_pen_joint2(state_ptr, VertexO[1], VertexO[2], PenTopZ + ResetPenLength)
    OdinJuliaBridge.lock_compass_joint1(
        state_ptr, VertexO[1], VertexO[2], CompassTopZ, sweep = false)
    OdinJuliaBridge.lock_compass_joint2(
        state_ptr, Marker1Start[1], Marker1Start[2], CompassTopZ, sweep = false)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, RayHColor)
    OdinJuliaBridge.set_compass_active(state_ptr, 0, MarkerColor)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    rayH = OdinJuliaBridge.create_new_line(state_ptr, RayHStart, RayHStart, RayHColor, 0f0)
    rayK = OdinJuliaBridge.create_new_line(state_ptr, RayKStart, RayKStart, RayKColor, 0f0)
    rayHPrime = OdinJuliaBridge.create_new_line(
        state_ptr, RayHPrimeStart, RayHPrimeStart, RayHPrimeColor, 0f0)
    rayKPrime = OdinJuliaBridge.create_new_line(
        state_ptr, RayKPrimeStart, RayKPrimeStart, RayKPrimeColor, 0f0)

    marker1 = OdinJuliaBridge.create_new_filledcircle(
        state_ptr,
        VertexO[1], VertexO[2], VertexO[3],
        MarkerRadius, 0f0, 0f0,
        MarkerColor, 0f0)
    marker2 = OdinJuliaBridge.create_new_filledcircle(
        state_ptr,
        VertexOPrime[1], VertexOPrime[2], VertexOPrime[3],
        MarkerRadius, 0f0, 0f0,
        MarkerColor, 0f0)

    labelO = OdinJuliaBridge.create_new_label(state_ptr, 'O', LabelOPoint, LabelColor, 16f0)
    labelH = OdinJuliaBridge.create_new_label(state_ptr, 'h', LabelHPoint, LabelColor, 16f0)
    labelK = OdinJuliaBridge.create_new_label(state_ptr, 'k', LabelKPoint, LabelColor, 16f0)

    labelOPrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'O', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelOPrimePoint, LabelColor, 16f0)
    labelHPrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'h', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelHPrimePoint, LabelColor, 16f0)
    labelKPrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'k', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelKPrimePoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayHHostId, Float32(rayH.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayHJoint1Id, Float32(rayH.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayHJoint2Id, Float32(rayH.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayKHostId, Float32(rayK.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayKJoint1Id, Float32(rayK.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayKJoint2Id, Float32(rayK.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayHPrimeHostId, Float32(rayHPrime.hostId))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaRayHPrimeJoint1Id, Float32(rayHPrime.joint1Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaRayHPrimeJoint2Id, Float32(rayHPrime.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayKPrimeHostId, Float32(rayKPrime.hostId))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaRayKPrimeJoint1Id, Float32(rayKPrime.joint1Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaRayKPrimeJoint2Id, Float32(rayKPrime.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker1HostId, Float32(marker1.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker1StartId, Float32(marker1.startId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker1EndId, Float32(marker1.endId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker2HostId, Float32(marker2.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker2StartId, Float32(marker2.startId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker2EndId, Float32(marker2.endId))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelOId, Float32(labelO.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelHId, Float32(labelH.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelKId, Float32(labelK.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelOPrimeId, Float32(labelOPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelHPrimeId, Float32(labelHPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelKPrimeId, Float32(labelKPrime.index))

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
    rayHPrimeHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHPrimeHostId))
    rayHPrimeJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHPrimeJoint1Id))
    rayHPrimeJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHPrimeJoint2Id))
    rayKPrimeHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKPrimeHostId))
    rayKPrimeJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKPrimeJoint1Id))
    rayKPrimeJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKPrimeJoint2Id))

    marker1HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker1HostId))
    marker1StartId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker1StartId))
    marker1EndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker1EndId))
    marker2HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker2HostId))
    marker2StartId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker2StartId))
    marker2EndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker2EndId))

    labelOId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelOId))
    labelHId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelHId))
    labelKId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelKId))
    labelOPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelOPrimeId))
    labelHPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelHPrimeId))
    labelKPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelKPrimeId))

    if rayHHostId < 0 || rayKHostId < 0 || rayHPrimeHostId < 0 || rayKPrimeHostId < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescendToO
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, VertexO[1], VertexO[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawRayH
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelOId)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, RayHColor)
        end
    elseif phase == PhaseDrawRayH
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawRayDuration, RayHStart, RayHEnd,
            RayBrush, RayHColor,
            rayHHostId, rayHJoint1Id, rayHJoint2Id)

        timer += dt
        if timer >= DrawRayDuration
            phase = PhaseArcToOForK
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelHId)
        end
    elseif phase == PhaseArcToOForK
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            RayHEnd, VertexO, 0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawRayK
            timer = 0f0
            OdinJuliaBridge.set_pen_active(state_ptr, 0, RayKColor)
        end
    elseif phase == PhaseDrawRayK
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawRayDuration, RayKStart, RayKEnd,
            RayBrush, RayKColor,
            rayKHostId, rayKJoint1Id, rayKJoint2Id)

        timer += dt
        if timer >= DrawRayDuration
            phase = PhasePenLiftForMarker1
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelKId)
        end
    elseif phase == PhasePenLiftForMarker1
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ, RayKEnd[1], RayKEnd[2])
        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, PenLiftDuration, CompassTopZ,
            VertexO[1], VertexO[2], Marker1Start[1], Marker1Start[2])

        timer += dt
        if timer >= PenLiftDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseDrawMarker1
            timer = 0f0
        end
    elseif phase == PhaseDrawMarker1
        EuclidAnimations.animate_draw_filledcircle(
            state_ptr, timer, MarkerDrawDuration,
            VertexO, Marker1Start,
            AngleTheta, MarkerRadius, MarkerBrush, MarkerColor,
            marker1HostId, marker1StartId, marker1EndId)

        timer += dt
        if timer >= MarkerDrawDuration
            phase = PhaseCompassLiftAfterMarker1
            timer = 0f0
        end
    elseif phase == PhaseCompassLiftAfterMarker1
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassLiftDuration, CompassTopZ,
            VertexO[1], VertexO[2], Marker1End[1], Marker1End[2])

        timer += dt
        if timer >= CompassLiftDuration
            OdinJuliaBridge.hide_compass(state_ptr)
            OdinJuliaBridge.show_pen(state_ptr)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, RayHPrimeColor)
            phase = PhaseDescendToOPrime
            timer = 0f0
        end
    elseif phase == PhaseDescendToOPrime
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, VertexOPrime[1], VertexOPrime[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawRayHPrime
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelOPrimeId)
        end
    elseif phase == PhaseDrawRayHPrime
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawRayDuration, RayHPrimeStart, RayHPrimeEnd,
            RayBrush, RayHPrimeColor,
            rayHPrimeHostId, rayHPrimeJoint1Id, rayHPrimeJoint2Id)

        timer += dt
        if timer >= DrawRayDuration
            phase = PhaseArcToOPrimeForKPrime
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelHPrimeId)
        end
    elseif phase == PhaseArcToOPrimeForKPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            RayHPrimeEnd, VertexOPrime, 0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawRayKPrime
            timer = 0f0
            OdinJuliaBridge.set_pen_active(state_ptr, 0, RayKPrimeColor)
        end
    elseif phase == PhaseDrawRayKPrime
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawRayDuration, RayKPrimeStart, RayKPrimeEnd,
            RayBrush, RayKPrimeColor,
            rayKPrimeHostId, rayKPrimeJoint1Id, rayKPrimeJoint2Id)

        timer += dt
        if timer >= DrawRayDuration
            phase = PhasePenLiftForMarker2
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelKPrimeId)
        end
    elseif phase == PhasePenLiftForMarker2
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ, RayKPrimeEnd[1], RayKPrimeEnd[2])
        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, PenLiftDuration, CompassTopZ,
            VertexOPrime[1], VertexOPrime[2], Marker2Start[1], Marker2Start[2])

        timer += dt
        if timer >= PenLiftDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseDrawMarker2
            timer = 0f0
        end
    elseif phase == PhaseDrawMarker2
        EuclidAnimations.animate_draw_filledcircle(
            state_ptr, timer, MarkerDrawDuration,
            VertexOPrime, Marker2Start,
            AngleTheta, MarkerRadius, MarkerBrush, MarkerColor,
            marker2HostId, marker2StartId, marker2EndId)

        timer += dt
        if timer >= MarkerDrawDuration
            phase = PhaseCompassArcToMarker1
            timer = 0f0
        end
    elseif phase == PhaseCompassArcToMarker1
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            VertexOPrime, VertexO,
            Marker2End, Marker1Start,
            0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlight1Forward
            timer = 0f0
        end
    elseif phase == PhaseHighlight1Forward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            VertexO, Marker1Start,
            AngleTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlight1Back
            timer = 0f0
        end
    elseif phase == PhaseHighlight1Back
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            VertexO, Marker1End,
            -AngleTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcToMarker2
            timer = 0f0
        end
    elseif phase == PhaseCompassArcToMarker2
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            VertexO, VertexOPrime,
            Marker1Start, Marker2Start,
            0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlight2Forward
            timer = 0f0
        end
    elseif phase == PhaseHighlight2Forward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            VertexOPrime, Marker2Start,
            AngleTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlight2Back
            timer = 0f0
        end
    elseif phase == PhaseHighlight2Back
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            VertexOPrime, Marker2End,
            -AngleTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassLiftEnd
            timer = 0f0
        end
    elseif phase == PhaseCompassLiftEnd
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassLiftDuration, CompassTopZ,
            VertexOPrime[1], VertexOPrime[2], Marker2Start[1], Marker2Start[2])

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

module HilbertChapterOneAxiomIV5

using ..OdinJuliaBridge
using ..EuclidAnimations

export get_view_text, initialize, clean, loop

const VertexO = [0.18f0, 0.68f0, 0f0]
const VertexOPrime = [0.42f0, 0.50f0, 0f0]
const VertexODoublePrime = [0.66f0, 0.30f0, 0f0]
const RayLength = 0.32f0
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

const RayHDoublePrimeStart = VertexODoublePrime
const RayHDoublePrimeEnd = [VertexODoublePrime[1] + RayLength, VertexODoublePrime[2], 0f0]
const RayKDoublePrimeStart = VertexODoublePrime
const RayKDoublePrimeEnd = [
    VertexODoublePrime[1] + RayLength * Float32(cos(AngleTheta)),
    VertexODoublePrime[2] + RayLength * Float32(sin(AngleTheta)),
    0f0,
]

const MarkerRadius = 0.11f0
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
const Marker3Start = [VertexODoublePrime[1] + MarkerRadius, VertexODoublePrime[2], 0f0]
const Marker3End = [
    VertexODoublePrime[1] + MarkerRadius * Float32(cos(AngleTheta)),
    VertexODoublePrime[2] + MarkerRadius * Float32(sin(AngleTheta)),
    0f0,
]

const LabelColor = :plum1
const HighlightColor = :lightgreen
const RayHColor = :steelblue
const RayKColor = :palevioletred1
const RayHPrimeColor = :grey60
const RayKPrimeColor = :steelblue
const RayHDoublePrimeColor = :palevioletred1
const RayKDoublePrimeColor = :steelblue
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
const LabelODoublePrimePoint = VertexODoublePrime + [-0.02f0, 0.07f0, 0f0]
const LabelHDoublePrimePoint = RayHDoublePrimeEnd + [0.02f0, 0.055f0, 0f0]
const LabelKDoublePrimePoint = RayKDoublePrimeEnd + [0.02f0, 0.055f0, 0f0]

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
const MetaRayHDoublePrimeHostId = 41
const MetaRayHDoublePrimeJoint1Id = 42
const MetaRayHDoublePrimeJoint2Id = 43
const MetaRayKDoublePrimeHostId = 51
const MetaRayKDoublePrimeJoint1Id = 52
const MetaRayKDoublePrimeJoint2Id = 53

const MetaMarker1HostId = 61
const MetaMarker1StartId = 62
const MetaMarker1EndId = 63
const MetaMarker2HostId = 64
const MetaMarker2StartId = 65
const MetaMarker2EndId = 66
const MetaMarker3HostId = 67
const MetaMarker3StartId = 68
const MetaMarker3EndId = 69

const MetaLabelOId = 81
const MetaLabelHId = 82
const MetaLabelKId = 83
const MetaLabelOPrimeId = 84
const MetaLabelHPrimeId = 85
const MetaLabelKPrimeId = 86
const MetaLabelODoublePrimeId = 87
const MetaLabelHDoublePrimeId = 88
const MetaLabelKDoublePrimeId = 89

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
const PhaseCompassLiftAfterMarker2 = 13f0
const PhaseDescendToODoublePrime = 14f0
const PhaseDrawRayHDoublePrime = 15f0
const PhaseArcToODoublePrimeForKDoublePrime = 16f0
const PhaseDrawRayKDoublePrime = 17f0
const PhasePenLiftForMarker3 = 18f0
const PhaseDrawMarker3 = 19f0
const PhaseCompassArc3To1 = 20f0
const PhaseHighlightA1Forward = 21f0
const PhaseHighlightA1Back = 22f0
const PhaseCompassArc1To2 = 23f0
const PhaseHighlightB1Forward = 24f0
const PhaseHighlightB1Back = 25f0
const PhaseCompassArc2To1 = 26f0
const PhaseHighlightA2Forward = 27f0
const PhaseHighlightA2Back = 28f0
const PhaseCompassArc1To3 = 29f0
const PhaseHighlightC1Forward = 30f0
const PhaseHighlightC1Back = 31f0
const PhaseCompassArc3To2 = 32f0
const PhaseHighlightB2Forward = 33f0
const PhaseHighlightB2Back = 34f0
const PhaseCompassArc2To3 = 35f0
const PhaseHighlightC2Forward = 36f0
const PhaseHighlightC2Back = 37f0
const PhaseCompassLiftEnd = 38f0
const PhaseFinalHold = 39f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """David Hilbert - Foundations of Geometry - Axiom IV,5

IV, 5. If the angle (h, k) is congruent to the angle (h', k') and to the angle (h'', k''), then the angle (h', k') is congruent to the angle (h'', k''); that is to say, if ∠(h, k) ≡ ∠(h', k') and ∠(h, k) ≡ ∠(h'', k''), then ∠(h', k') ≡ ∠(h'', k'')."""
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
    rayHDoublePrimeHostId = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaRayHDoublePrimeHostId))
    rayHDoublePrimeJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaRayHDoublePrimeJoint2Id))
    rayKDoublePrimeHostId = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaRayKDoublePrimeHostId))
    rayKDoublePrimeJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaRayKDoublePrimeJoint2Id))

    marker1HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker1HostId))
    marker1EndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker1EndId))
    marker2HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker2HostId))
    marker2EndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker2EndId))
    marker3HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker3HostId))
    marker3EndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker3EndId))

    labelOId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelOId))
    labelHId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelHId))
    labelKId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelKId))
    labelOPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelOPrimeId))
    labelHPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelHPrimeId))
    labelKPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelKPrimeId))
    labelODoublePrimeId = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLabelODoublePrimeId))
    labelHDoublePrimeId = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLabelHDoublePrimeId))
    labelKDoublePrimeId = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLabelKDoublePrimeId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [rayHHostId, rayKHostId, rayHPrimeHostId, rayKPrimeHostId,
         rayHDoublePrimeHostId, rayKDoublePrimeHostId,
         marker1HostId, marker2HostId, marker3HostId,
         labelOId, labelHId, labelKId,
         labelOPrimeId, labelHPrimeId, labelKPrimeId,
         labelODoublePrimeId, labelHDoublePrimeId, labelKDoublePrimeId])

    OdinJuliaBridge.set_point_position(state_ptr, rayHJoint2Id, RayHStart)
    OdinJuliaBridge.set_point_position(state_ptr, rayKJoint2Id, RayKStart)
    OdinJuliaBridge.set_point_position(state_ptr, rayHPrimeJoint2Id, RayHPrimeStart)
    OdinJuliaBridge.set_point_position(state_ptr, rayKPrimeJoint2Id, RayKPrimeStart)
    OdinJuliaBridge.set_point_position(state_ptr, rayHDoublePrimeJoint2Id, RayHDoublePrimeStart)
    OdinJuliaBridge.set_point_position(state_ptr, rayKDoublePrimeJoint2Id, RayKDoublePrimeStart)

    OdinJuliaBridge.set_point_position(state_ptr, marker1EndId, Marker1Start)
    OdinJuliaBridge.set_point_position(state_ptr, marker2EndId, Marker2Start)
    OdinJuliaBridge.set_point_position(state_ptr, marker3EndId, Marker3Start)

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
    rayHDoublePrime = OdinJuliaBridge.create_new_line(
        state_ptr, RayHDoublePrimeStart, RayHDoublePrimeStart, RayHDoublePrimeColor, 0f0)
    rayKDoublePrime = OdinJuliaBridge.create_new_line(
        state_ptr, RayKDoublePrimeStart, RayKDoublePrimeStart, RayKDoublePrimeColor, 0f0)

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
    marker3 = OdinJuliaBridge.create_new_filledcircle(
        state_ptr,
        VertexODoublePrime[1], VertexODoublePrime[2], VertexODoublePrime[3],
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

    labelODoublePrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'O', OdinJuliaBridge.LABEL_DECORATION_DOUBLEPRIME,
        LabelODoublePrimePoint, LabelColor, 16f0)
    labelHDoublePrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'h', OdinJuliaBridge.LABEL_DECORATION_DOUBLEPRIME,
        LabelHDoublePrimePoint, LabelColor, 16f0)
    labelKDoublePrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'k', OdinJuliaBridge.LABEL_DECORATION_DOUBLEPRIME,
        LabelKDoublePrimePoint, LabelColor, 16f0)

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
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaRayHDoublePrimeHostId, Float32(rayHDoublePrime.hostId))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaRayHDoublePrimeJoint1Id, Float32(rayHDoublePrime.joint1Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaRayHDoublePrimeJoint2Id, Float32(rayHDoublePrime.joint2Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaRayKDoublePrimeHostId, Float32(rayKDoublePrime.hostId))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaRayKDoublePrimeJoint1Id, Float32(rayKDoublePrime.joint1Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaRayKDoublePrimeJoint2Id, Float32(rayKDoublePrime.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker1HostId, Float32(marker1.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker1StartId, Float32(marker1.startId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker1EndId, Float32(marker1.endId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker2HostId, Float32(marker2.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker2StartId, Float32(marker2.startId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker2EndId, Float32(marker2.endId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker3HostId, Float32(marker3.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker3StartId, Float32(marker3.startId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker3EndId, Float32(marker3.endId))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelOId, Float32(labelO.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelHId, Float32(labelH.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelKId, Float32(labelK.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelOPrimeId, Float32(labelOPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelHPrimeId, Float32(labelHPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelKPrimeId, Float32(labelKPrime.index))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaLabelODoublePrimeId, Float32(labelODoublePrime.index))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaLabelHDoublePrimeId, Float32(labelHDoublePrime.index))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaLabelKDoublePrimeId, Float32(labelKDoublePrime.index))

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
    rayHDoublePrimeHostId = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaRayHDoublePrimeHostId))
    rayHDoublePrimeJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaRayHDoublePrimeJoint1Id))
    rayHDoublePrimeJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaRayHDoublePrimeJoint2Id))
    rayKDoublePrimeHostId = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaRayKDoublePrimeHostId))
    rayKDoublePrimeJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaRayKDoublePrimeJoint1Id))
    rayKDoublePrimeJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaRayKDoublePrimeJoint2Id))

    marker1HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker1HostId))
    marker1StartId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker1StartId))
    marker1EndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker1EndId))
    marker2HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker2HostId))
    marker2StartId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker2StartId))
    marker2EndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker2EndId))
    marker3HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker3HostId))
    marker3StartId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker3StartId))
    marker3EndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker3EndId))

    labelOId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelOId))
    labelHId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelHId))
    labelKId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelKId))
    labelOPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelOPrimeId))
    labelHPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelHPrimeId))
    labelKPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelKPrimeId))
    labelODoublePrimeId = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLabelODoublePrimeId))
    labelHDoublePrimeId = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLabelHDoublePrimeId))
    labelKDoublePrimeId = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLabelKDoublePrimeId))

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
            phase = PhaseCompassLiftAfterMarker2
            timer = 0f0
        end
    elseif phase == PhaseCompassLiftAfterMarker2
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassLiftDuration, CompassTopZ,
            VertexOPrime[1], VertexOPrime[2], Marker2End[1], Marker2End[2])

        timer += dt
        if timer >= CompassLiftDuration
            OdinJuliaBridge.hide_compass(state_ptr)
            OdinJuliaBridge.show_pen(state_ptr)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, RayHDoublePrimeColor)
            phase = PhaseDescendToODoublePrime
            timer = 0f0
        end
    elseif phase == PhaseDescendToODoublePrime
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, VertexODoublePrime[1], VertexODoublePrime[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawRayHDoublePrime
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelODoublePrimeId)
        end
    elseif phase == PhaseDrawRayHDoublePrime
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawRayDuration, RayHDoublePrimeStart, RayHDoublePrimeEnd,
            RayBrush, RayHDoublePrimeColor,
            rayHDoublePrimeHostId, rayHDoublePrimeJoint1Id, rayHDoublePrimeJoint2Id)

        timer += dt
        if timer >= DrawRayDuration
            phase = PhaseArcToODoublePrimeForKDoublePrime
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelHDoublePrimeId)
        end
    elseif phase == PhaseArcToODoublePrimeForKDoublePrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            RayHDoublePrimeEnd, VertexODoublePrime, 0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawRayKDoublePrime
            timer = 0f0
            OdinJuliaBridge.set_pen_active(state_ptr, 0, RayKDoublePrimeColor)
        end
    elseif phase == PhaseDrawRayKDoublePrime
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawRayDuration, RayKDoublePrimeStart, RayKDoublePrimeEnd,
            RayBrush, RayKDoublePrimeColor,
            rayKDoublePrimeHostId, rayKDoublePrimeJoint1Id, rayKDoublePrimeJoint2Id)

        timer += dt
        if timer >= DrawRayDuration
            phase = PhasePenLiftForMarker3
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelKDoublePrimeId)
        end
    elseif phase == PhasePenLiftForMarker3
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ,
            RayKDoublePrimeEnd[1], RayKDoublePrimeEnd[2])
        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, PenLiftDuration, CompassTopZ,
            VertexODoublePrime[1], VertexODoublePrime[2],
            Marker3Start[1], Marker3Start[2])

        timer += dt
        if timer >= PenLiftDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseDrawMarker3
            timer = 0f0
        end
    elseif phase == PhaseDrawMarker3
        EuclidAnimations.animate_draw_filledcircle(
            state_ptr, timer, MarkerDrawDuration,
            VertexODoublePrime, Marker3Start,
            AngleTheta, MarkerRadius, MarkerBrush, MarkerColor,
            marker3HostId, marker3StartId, marker3EndId)

        timer += dt
        if timer >= MarkerDrawDuration
            phase = PhaseCompassArc3To1
            timer = 0f0
        end
    elseif phase == PhaseCompassArc3To1
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            VertexODoublePrime, VertexO,
            Marker3End, Marker1Start,
            0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightA1Forward
            timer = 0f0
        end
    elseif phase == PhaseHighlightA1Forward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            VertexO, Marker1Start,
            AngleTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightA1Back
            timer = 0f0
        end
    elseif phase == PhaseHighlightA1Back
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            VertexO, Marker1End,
            -AngleTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArc1To2
            timer = 0f0
        end
    elseif phase == PhaseCompassArc1To2
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            VertexO, VertexOPrime,
            Marker1Start, Marker2Start,
            0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightB1Forward
            timer = 0f0
        end
    elseif phase == PhaseHighlightB1Forward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            VertexOPrime, Marker2Start,
            AngleTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightB1Back
            timer = 0f0
        end
    elseif phase == PhaseHighlightB1Back
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            VertexOPrime, Marker2End,
            -AngleTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArc2To1
            timer = 0f0
        end
    elseif phase == PhaseCompassArc2To1
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            VertexOPrime, VertexO,
            Marker2Start, Marker1Start,
            0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightA2Forward
            timer = 0f0
        end
    elseif phase == PhaseHighlightA2Forward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            VertexO, Marker1Start,
            AngleTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightA2Back
            timer = 0f0
        end
    elseif phase == PhaseHighlightA2Back
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            VertexO, Marker1End,
            -AngleTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArc1To3
            timer = 0f0
        end
    elseif phase == PhaseCompassArc1To3
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            VertexO, VertexODoublePrime,
            Marker1Start, Marker3Start,
            0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightC1Forward
            timer = 0f0
        end
    elseif phase == PhaseHighlightC1Forward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            VertexODoublePrime, Marker3Start,
            AngleTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightC1Back
            timer = 0f0
        end
    elseif phase == PhaseHighlightC1Back
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            VertexODoublePrime, Marker3End,
            -AngleTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArc3To2
            timer = 0f0
        end
    elseif phase == PhaseCompassArc3To2
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            VertexODoublePrime, VertexOPrime,
            Marker3Start, Marker2Start,
            0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightB2Forward
            timer = 0f0
        end
    elseif phase == PhaseHighlightB2Forward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            VertexOPrime, Marker2Start,
            AngleTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightB2Back
            timer = 0f0
        end
    elseif phase == PhaseHighlightB2Back
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            VertexOPrime, Marker2End,
            -AngleTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArc2To3
            timer = 0f0
        end
    elseif phase == PhaseCompassArc2To3
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            VertexOPrime, VertexODoublePrime,
            Marker2Start, Marker3Start,
            0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightC2Forward
            timer = 0f0
        end
    elseif phase == PhaseHighlightC2Forward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            VertexODoublePrime, Marker3Start,
            AngleTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightC2Back
            timer = 0f0
        end
    elseif phase == PhaseHighlightC2Back
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            VertexODoublePrime, Marker3End,
            -AngleTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassLiftEnd
            timer = 0f0
        end
    elseif phase == PhaseCompassLiftEnd
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassLiftDuration, CompassTopZ,
            VertexODoublePrime[1], VertexODoublePrime[2],
            Marker3Start[1], Marker3Start[2])

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

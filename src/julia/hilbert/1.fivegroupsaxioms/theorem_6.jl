module HilbertChapterOneTheorem6

using ..OdinJuliaBridge
using ..EuclidAnimations

export get_view_text, initialize, clean, loop

const PolygonV1 = [0.22f0, 0.66f0, 0f0]
const PolygonV2 = [0.39f0, 0.78f0, 0f0]
const PolygonV3 = [0.72f0, 0.68f0, 0f0]
const PolygonV4 = [0.76f0, 0.46f0, 0f0]
const PolygonV5 = [0.55f0, 0.51f0, 0f0]
const PolygonV6 = [0.42f0, 0.16f0, 0f0]

const PointA = [0.45f0, 0.34f0, 0f0]
const PointB = [0.05f0, 0.35f0, 0f0]
const PointAPrime = [0.65f0, 0.56f0, 0f0]
const PointBPrime = [0.82f0, 0.73f0, 0f0]
const BrokenInsideMid = [0.40f0, 0.64f0, 0f0]
const BrokenOutsideMid1 = [0.16f0, 0.78f0, 0f0]
const BrokenOutsideMid2 = [0.41f0, 0.89f0, 0f0]
const PenTopZ = 1.4f0

const ALabelPoint = PointA + [0.012f0, -0.028f0, 0f0]
const BLabelPoint = PointB + [-0.002f0, -0.03f0, 0f0]
const APrimeLabelPoint = PointAPrime + [0.025f0, -0.018f0, 0f0]
const BPrimeLabelPoint = PointBPrime + [0.02f0, -0.028f0, 0f0]

const LabelColor = :plum1
const OutlineColor = :grey60
const PointAColor = :steelblue
const PointBColor = :palevioletred1
const PointAPrimeColor = :khaki3
const PointBPrimeColor = :grey60
const SegmentABColor = :steelblue
const BrokenInsideColor = PointAPrimeColor
const BrokenOutsideColor = PointBColor

const LineMaxBrush = 5f0
const PointMaxBrush = 5f0

const DescendDuration = 1.8f0
const DrawPolygonDuration = 2.2f0
const ArcMoveDuration = 1.8f0
const DrawPointDuration = 1.7f0
const DrawSegmentDuration = 2.0f0
const EndLiftDuration = 1.8f0
const FinalHoldDuration = 0.9f0

const MetaPoly1HostId = 1
const MetaPoly1Joint1Id = 2
const MetaPoly1Joint2Id = 3
const MetaPoly2HostId = 4
const MetaPoly2Joint1Id = 5
const MetaPoly2Joint2Id = 6
const MetaPoly3HostId = 7
const MetaPoly3Joint1Id = 8
const MetaPoly3Joint2Id = 9
const MetaPoly4HostId = 10
const MetaPoly4Joint1Id = 11
const MetaPoly4Joint2Id = 12
const MetaPoly5HostId = 13
const MetaPoly5Joint1Id = 14
const MetaPoly5Joint2Id = 15
const MetaPoly6HostId = 16
const MetaPoly6Joint1Id = 17
const MetaPoly6Joint2Id = 18
const MetaPointAId = 31
const MetaPointBId = 32
const MetaPointAPrimeId = 33
const MetaPointBPrimeId = 34
const MetaSegmentABHostId = 41
const MetaSegmentABJoint1Id = 42
const MetaSegmentABJoint2Id = 43
const MetaInside1HostId = 44
const MetaInside1Joint1Id = 45
const MetaInside1Joint2Id = 46
const MetaInside2HostId = 47
const MetaInside2Joint1Id = 48
const MetaInside2Joint2Id = 49
const MetaOutside1HostId = 50
const MetaOutside1Joint1Id = 51
const MetaOutside1Joint2Id = 52
const MetaOutside2HostId = 53
const MetaOutside2Joint1Id = 54
const MetaOutside2Joint2Id = 55
const MetaOutside3HostId = 56
const MetaOutside3Joint1Id = 57
const MetaOutside3Joint2Id = 58
const MetaLabelAId = 61
const MetaLabelBId = 62
const MetaLabelAPrimeId = 63
const MetaLabelBPrimeId = 64
const MetaPhase = 101
const MetaTimer = 102

const PhaseDescend = 0f0
const PhaseDrawPoly1 = 1f0
const PhaseDrawPoly2 = 2f0
const PhaseDrawPoly3 = 3f0
const PhaseDrawPoly4 = 4f0
const PhaseDrawPoly5 = 5f0
const PhaseDrawPoly6 = 6f0
const PhaseMoveToA = 7f0
const PhasePutA = 8f0
const PhaseMoveToB = 9f0
const PhasePutB = 10f0
const PhaseDrawAB = 11f0
const PhaseMoveToAPrime = 12f0
const PhasePutAPrime = 13f0
const PhaseMoveToAForBroken = 14f0
const PhaseDrawInside1 = 15f0
const PhaseDrawInside2 = 16f0
const PhaseMoveToBPrime = 17f0
const PhasePutBPrime = 18f0
const PhaseMoveToBForBroken = 19f0
const PhaseDrawOutside1 = 20f0
const PhaseDrawOutside2 = 21f0
const PhaseDrawOutside3 = 22f0
const PhaseEndLift = 23f0
const PhaseFinalHold = 24f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """David Hilbert - Foundations of Geometry - Theorem 6

Every simple polygon, whose vertices all lie in a plane α, divides the points of this plane, not belonging to the broken line constituting the sides of the polygon, into two regions, an interior and an exterior, having the following properties: If A is a point of the interior region (interior point) and B a point of the exterior region (exterior point), then any broken line joining A and B must have at least one point in common with the polygon. If, on the other hand, A, A' are two points of the interior and B, B' two points of the exterior region, then there are always broken lines to be found joining A with A' and B with B' without having a point in common with the polygon. There exist straight lines in the plane α which lie entirely outside of the given polygon, but there are none which lie entirely within it."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    poly1HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoly1HostId))
    poly1Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoly1Joint2Id))
    poly2HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoly2HostId))
    poly2Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoly2Joint2Id))
    poly3HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoly3HostId))
    poly3Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoly3Joint2Id))
    poly4HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoly4HostId))
    poly4Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoly4Joint2Id))
    poly5HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoly5HostId))
    poly5Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoly5Joint2Id))
    poly6HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoly6HostId))
    poly6Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoly6Joint2Id))
    pointAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    pointBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    pointAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAPrimeId))
    pointBPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBPrimeId))
    segmentABHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaSegmentABHostId))
    segmentABJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaSegmentABJoint2Id))
    inside1HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaInside1HostId))
    inside1Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaInside1Joint2Id))
    inside2HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaInside2HostId))
    inside2Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaInside2Joint2Id))
    outside1HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaOutside1HostId))
    outside1Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaOutside1Joint2Id))
    outside2HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaOutside2HostId))
    outside2Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaOutside2Joint2Id))
    outside3HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaOutside3HostId))
    outside3Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaOutside3Joint2Id))
    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labelAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAPrimeId))
    labelBPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBPrimeId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [poly1HostId, poly2HostId, poly3HostId, poly4HostId, poly5HostId, poly6HostId,
         pointAId, pointBId, pointAPrimeId, pointBPrimeId,
         segmentABHostId, inside1HostId, inside2HostId,
         outside1HostId, outside2HostId, outside3HostId,
         labelAId, labelBId, labelAPrimeId, labelBPrimeId])

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.set_point_position(state_ptr, poly1Joint2Id, PolygonV1)
    OdinJuliaBridge.set_point_position(state_ptr, poly2Joint2Id, PolygonV2)
    OdinJuliaBridge.set_point_position(state_ptr, poly3Joint2Id, PolygonV3)
    OdinJuliaBridge.set_point_position(state_ptr, poly4Joint2Id, PolygonV4)
    OdinJuliaBridge.set_point_position(state_ptr, poly5Joint2Id, PolygonV5)
    OdinJuliaBridge.set_point_position(state_ptr, poly6Joint2Id, PolygonV6)
    OdinJuliaBridge.set_point_position(state_ptr, segmentABJoint2Id, PointB)
    OdinJuliaBridge.set_point_position(state_ptr, inside1Joint2Id, PointA)
    OdinJuliaBridge.set_point_position(state_ptr, inside2Joint2Id, BrokenInsideMid)
    OdinJuliaBridge.set_point_position(state_ptr, outside1Joint2Id, PointB)
    OdinJuliaBridge.set_point_position(state_ptr, outside2Joint2Id, BrokenOutsideMid1)
    OdinJuliaBridge.set_point_position(state_ptr, outside3Joint2Id, BrokenOutsideMid2)

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, OutlineColor)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    poly1 = OdinJuliaBridge.create_new_line(
        state_ptr, PolygonV1, PolygonV1, OutlineColor, 0f0)
    poly2 = OdinJuliaBridge.create_new_line(
        state_ptr, PolygonV2, PolygonV2, OutlineColor, 0f0)
    poly3 = OdinJuliaBridge.create_new_line(
        state_ptr, PolygonV3, PolygonV3, OutlineColor, 0f0)
    poly4 = OdinJuliaBridge.create_new_line(
        state_ptr, PolygonV4, PolygonV4, OutlineColor, 0f0)
    poly5 = OdinJuliaBridge.create_new_line(
        state_ptr, PolygonV5, PolygonV5, OutlineColor, 0f0)
    poly6 = OdinJuliaBridge.create_new_line(
        state_ptr, PolygonV6, PolygonV6, OutlineColor, 0f0)

    pointA = OdinJuliaBridge.create_new_point(
        state_ptr, PointA, PointAColor, 0f0)
    pointB = OdinJuliaBridge.create_new_point(
        state_ptr, PointB, PointBColor, 0f0)
    pointAPrime = OdinJuliaBridge.create_new_point(
        state_ptr, PointAPrime, PointAPrimeColor, 0f0)
    pointBPrime = OdinJuliaBridge.create_new_point(
        state_ptr, PointBPrime, PointBPrimeColor, 0f0)

    segmentAB = OdinJuliaBridge.create_new_line(
        state_ptr, PointB, PointB, SegmentABColor, 0f0)
    inside1 = OdinJuliaBridge.create_new_line(
        state_ptr, PointA, PointA, BrokenInsideColor, 0f0)
    inside2 = OdinJuliaBridge.create_new_line(
        state_ptr, BrokenInsideMid, BrokenInsideMid, BrokenInsideColor, 0f0)
    outside1 = OdinJuliaBridge.create_new_line(
        state_ptr, PointB, PointB, BrokenOutsideColor, 0f0)
    outside2 = OdinJuliaBridge.create_new_line(
        state_ptr, BrokenOutsideMid1, BrokenOutsideMid1, BrokenOutsideColor, 0f0)
    outside3 = OdinJuliaBridge.create_new_line(
        state_ptr, BrokenOutsideMid2, BrokenOutsideMid2, BrokenOutsideColor, 0f0)

    labelA = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', ALabelPoint, LabelColor, 16f0)
    labelB = OdinJuliaBridge.create_new_label(
        state_ptr, 'B', BLabelPoint, LabelColor, 16f0)
    labelAPrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'A', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        APrimeLabelPoint, LabelColor, 16f0)
    labelBPrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'B', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        BPrimeLabelPoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPoly1HostId, Float32(poly1.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPoly1Joint1Id, Float32(poly1.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPoly1Joint2Id, Float32(poly1.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPoly2HostId, Float32(poly2.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPoly2Joint1Id, Float32(poly2.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPoly2Joint2Id, Float32(poly2.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPoly3HostId, Float32(poly3.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPoly3Joint1Id, Float32(poly3.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPoly3Joint2Id, Float32(poly3.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPoly4HostId, Float32(poly4.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPoly4Joint1Id, Float32(poly4.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPoly4Joint2Id, Float32(poly4.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPoly5HostId, Float32(poly5.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPoly5Joint1Id, Float32(poly5.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPoly5Joint2Id, Float32(poly5.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPoly6HostId, Float32(poly6.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPoly6Joint1Id, Float32(poly6.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPoly6Joint2Id, Float32(poly6.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointAId, Float32(pointA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointBId, Float32(pointB.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointAPrimeId, Float32(pointAPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointBPrimeId, Float32(pointBPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaSegmentABHostId, Float32(segmentAB.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaSegmentABJoint1Id, Float32(segmentAB.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaSegmentABJoint2Id, Float32(segmentAB.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaInside1HostId, Float32(inside1.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaInside1Joint1Id, Float32(inside1.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaInside1Joint2Id, Float32(inside1.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaInside2HostId, Float32(inside2.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaInside2Joint1Id, Float32(inside2.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaInside2Joint2Id, Float32(inside2.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaOutside1HostId, Float32(outside1.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaOutside1Joint1Id, Float32(outside1.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaOutside1Joint2Id, Float32(outside1.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaOutside2HostId, Float32(outside2.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaOutside2Joint1Id, Float32(outside2.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaOutside2Joint2Id, Float32(outside2.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaOutside3HostId, Float32(outside3.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaOutside3Joint1Id, Float32(outside3.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaOutside3Joint2Id, Float32(outside3.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAId, Float32(labelA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBId, Float32(labelB.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAPrimeId, Float32(labelAPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBPrimeId, Float32(labelBPrime.index))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    poly1HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoly1HostId))
    poly1Joint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoly1Joint1Id))
    poly1Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoly1Joint2Id))
    poly2HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoly2HostId))
    poly2Joint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoly2Joint1Id))
    poly2Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoly2Joint2Id))
    poly3HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoly3HostId))
    poly3Joint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoly3Joint1Id))
    poly3Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoly3Joint2Id))
    poly4HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoly4HostId))
    poly4Joint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoly4Joint1Id))
    poly4Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoly4Joint2Id))
    poly5HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoly5HostId))
    poly5Joint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoly5Joint1Id))
    poly5Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoly5Joint2Id))
    poly6HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoly6HostId))
    poly6Joint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoly6Joint1Id))
    poly6Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoly6Joint2Id))
    pointAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    pointBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    pointAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAPrimeId))
    pointBPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBPrimeId))
    segmentABHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaSegmentABHostId))
    segmentABJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaSegmentABJoint1Id))
    segmentABJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaSegmentABJoint2Id))
    inside1HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaInside1HostId))
    inside1Joint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaInside1Joint1Id))
    inside1Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaInside1Joint2Id))
    inside2HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaInside2HostId))
    inside2Joint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaInside2Joint1Id))
    inside2Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaInside2Joint2Id))
    outside1HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaOutside1HostId))
    outside1Joint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaOutside1Joint1Id))
    outside1Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaOutside1Joint2Id))
    outside2HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaOutside2HostId))
    outside2Joint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaOutside2Joint1Id))
    outside2Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaOutside2Joint2Id))
    outside3HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaOutside3HostId))
    outside3Joint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaOutside3Joint1Id))
    outside3Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaOutside3Joint2Id))
    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labelAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAPrimeId))
    labelBPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBPrimeId))

    if poly1HostId < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, PolygonV1[1], PolygonV1[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawPoly1
            timer = 0f0
        end
    elseif phase == PhaseDrawPoly1
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawPolygonDuration, PolygonV1, PolygonV2,
            LineMaxBrush, OutlineColor, poly1HostId, poly1Joint1Id, poly1Joint2Id)

        timer += dt
        if timer >= DrawPolygonDuration
            phase = PhaseDrawPoly2
            timer = 0f0
        end
    elseif phase == PhaseDrawPoly2
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawPolygonDuration, PolygonV2, PolygonV3,
            LineMaxBrush, OutlineColor, poly2HostId, poly2Joint1Id, poly2Joint2Id)

        timer += dt
        if timer >= DrawPolygonDuration
            phase = PhaseDrawPoly3
            timer = 0f0
        end
    elseif phase == PhaseDrawPoly3
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawPolygonDuration, PolygonV3, PolygonV4,
            LineMaxBrush, OutlineColor, poly3HostId, poly3Joint1Id, poly3Joint2Id)

        timer += dt
        if timer >= DrawPolygonDuration
            phase = PhaseDrawPoly4
            timer = 0f0
        end
    elseif phase == PhaseDrawPoly4
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawPolygonDuration, PolygonV4, PolygonV5,
            LineMaxBrush, OutlineColor, poly4HostId, poly4Joint1Id, poly4Joint2Id)

        timer += dt
        if timer >= DrawPolygonDuration
            phase = PhaseDrawPoly5
            timer = 0f0
        end
    elseif phase == PhaseDrawPoly5
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawPolygonDuration, PolygonV5, PolygonV6,
            LineMaxBrush, OutlineColor, poly5HostId, poly5Joint1Id, poly5Joint2Id)

        timer += dt
        if timer >= DrawPolygonDuration
            phase = PhaseDrawPoly6
            timer = 0f0
        end
    elseif phase == PhaseDrawPoly6
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawPolygonDuration, PolygonV6, PolygonV1,
            LineMaxBrush, OutlineColor, poly6HostId, poly6Joint1Id, poly6Joint2Id)

        timer += dt
        if timer >= DrawPolygonDuration
            phase = PhaseMoveToA
            timer = 0f0
        end
    elseif phase == PhaseMoveToA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PolygonV1, PointA, 0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePutA
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelAId)
        end
    elseif phase == PhasePutA
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointA,
            PointMaxBrush, PointAColor, pointAId)

        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseMoveToB
            timer = 0f0
        end
    elseif phase == PhaseMoveToB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointA, PointB, 0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePutB
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelBId)
        end
    elseif phase == PhasePutB
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointB,
            PointMaxBrush, PointBColor, pointBId)

        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseDrawAB
            timer = 0f0
            OdinJuliaBridge.set_pen_active(state_ptr, 0, SegmentABColor)
        end
    elseif phase == PhaseDrawAB
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawSegmentDuration, PointB, PointA,
            LineMaxBrush, SegmentABColor,
            segmentABHostId, segmentABJoint1Id, segmentABJoint2Id)

        timer += dt
        if timer >= DrawSegmentDuration
            phase = PhaseMoveToAPrime
            timer = 0f0
        end
    elseif phase == PhaseMoveToAPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointA, PointAPrime, 0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePutAPrime
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelAPrimeId)
        end
    elseif phase == PhasePutAPrime
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointAPrime,
            PointMaxBrush, PointAPrimeColor, pointAPrimeId)

        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseMoveToAForBroken
            timer = 0f0
        end
    elseif phase == PhaseMoveToAForBroken
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointAPrime, PointA, 0.18f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawInside1
            timer = 0f0
            OdinJuliaBridge.set_pen_active(state_ptr, 0, BrokenInsideColor)
        end
    elseif phase == PhaseDrawInside1
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawSegmentDuration, PointA, BrokenInsideMid,
            LineMaxBrush, BrokenInsideColor,
            inside1HostId, inside1Joint1Id, inside1Joint2Id)

        timer += dt
        if timer >= DrawSegmentDuration
            phase = PhaseDrawInside2
            timer = 0f0
        end
    elseif phase == PhaseDrawInside2
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawSegmentDuration, BrokenInsideMid, PointAPrime,
            LineMaxBrush, BrokenInsideColor,
            inside2HostId, inside2Joint1Id, inside2Joint2Id)

        timer += dt
        if timer >= DrawSegmentDuration
            phase = PhaseMoveToBPrime
            timer = 0f0
        end
    elseif phase == PhaseMoveToBPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointAPrime, PointBPrime, 0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePutBPrime
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelBPrimeId)
        end
    elseif phase == PhasePutBPrime
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointBPrime,
            PointMaxBrush, PointBPrimeColor, pointBPrimeId)

        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseMoveToBForBroken
            timer = 0f0
        end
    elseif phase == PhaseMoveToBForBroken
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointBPrime, PointB, 0.28f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawOutside1
            timer = 0f0
            OdinJuliaBridge.set_pen_active(state_ptr, 0, BrokenOutsideColor)
        end
    elseif phase == PhaseDrawOutside1
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawSegmentDuration, PointB, BrokenOutsideMid1,
            LineMaxBrush, BrokenOutsideColor,
            outside1HostId, outside1Joint1Id, outside1Joint2Id)

        timer += dt
        if timer >= DrawSegmentDuration
            phase = PhaseDrawOutside2
            timer = 0f0
        end
    elseif phase == PhaseDrawOutside2
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawSegmentDuration, BrokenOutsideMid1, BrokenOutsideMid2,
            LineMaxBrush, BrokenOutsideColor,
            outside2HostId, outside2Joint1Id, outside2Joint2Id)

        timer += dt
        if timer >= DrawSegmentDuration
            phase = PhaseDrawOutside3
            timer = 0f0
        end
    elseif phase == PhaseDrawOutside3
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawSegmentDuration, BrokenOutsideMid2, PointBPrime,
            LineMaxBrush, BrokenOutsideColor,
            outside3HostId, outside3Joint1Id, outside3Joint2Id)

        timer += dt
        if timer >= DrawSegmentDuration
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ, PointBPrime[1], PointBPrime[2])

        timer += dt
        if timer >= EndLiftDuration
            phase = PhaseFinalHold
            timer = 0f0
        end
    elseif phase == PhaseFinalHold
        timer += dt
        if timer >= FinalHoldDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            reset_cycle_state(state_ptr)
            return
        end
    end

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, phase)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, timer)
end

end
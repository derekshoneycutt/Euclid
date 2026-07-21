module HilbertChapterOneDefAngle

using ..OdinJuliaBridge
using ..EuclidAnimations

export get_view_text, initialize, clean, loop

const PointO = [0.36f0, 0.40f0, 0f0]
const HalfRayLength = 0.44f0
const AngleTheta = π / 3f0

const HalfRayHStart = PointO
const HalfRayHEnd = [PointO[1] + HalfRayLength, PointO[2], 0f0]
const HalfRayKStart = PointO
const HalfRayKEnd = [
    PointO[1] + HalfRayLength * Float32(cos(AngleTheta)),
    PointO[2] + HalfRayLength * Float32(sin(AngleTheta)),
    0f0,
]

const MarkerRadius = 0.16f0
const MarkerStart = [PointO[1] + MarkerRadius, PointO[2], 0f0]
const MarkerEnd = [
    PointO[1] + MarkerRadius * Float32(cos(AngleTheta)),
    PointO[2] + MarkerRadius * Float32(sin(AngleTheta)),
    0f0,
]

const OLabelPoint = PointO + [-0.014f0, 0.075f0, 0f0]
const HLabelPoint = HalfRayHEnd + [0.01f0, 0.055f0, 0f0]
const KLabelPoint = HalfRayKEnd + [0.02f0, 0.05f0, 0f0]

const LabelColor = :plum1
const PointOColor = :khaki3
const HalfRayHColor = :steelblue
const HalfRayKColor = :palevioletred1
const MarkerColor = :khaki3
const LineMaxBrush = 5f0
const PointMaxBrush = 5f0
const MarkerBrush = 1f0

const PenTopZ = 1.4f0
const CompassTopZ = 1.4f0

const DescendDuration = 1.8f0
const DrawPointDuration = 1.6f0
const DrawRayDuration = 2.8f0
const ArcMoveDuration = 1.5f0
const PenLiftDuration = 1.6f0
const CompassDrawDuration = 1.25f0
const CompassLiftDuration = 2.2f0
const FinalHoldDuration = 0.9f0

const MetaHalfRayHHostId = 1
const MetaHalfRayHJoint1Id = 2
const MetaHalfRayHJoint2Id = 3
const MetaHalfRayKHostId = 11
const MetaHalfRayKJoint1Id = 12
const MetaHalfRayKJoint2Id = 13
const MetaMarkerHostId = 21
const MetaMarkerStartId = 22
const MetaMarkerEndId = 23
const MetaPointOId = 31
const MetaLabelOId = 41
const MetaLabelHId = 42
const MetaLabelKId = 43
const MetaPhase = 101
const MetaTimer = 102

const PhaseDescendToO = 0f0
const PhaseDrawPointO = 1f0
const PhaseDrawHalfRayH = 2f0
const PhaseArcToOForK = 3f0
const PhaseDrawHalfRayK = 4f0
const PhasePenLiftForMarker = 5f0
const PhaseCompassDrawMarker = 6f0
const PhaseCompassLift = 7f0
const PhaseFinalHold = 8f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """David Hilbert - Foundations of Geometry - Definition: Angle

Definitions. Let α be any arbitrary plane and h, k any two distinct half-rays lying in α and emanating from the point O so as to form a part of two different straight lines. We call the system formed by these two half-rays h, k an angle and represent it by the symbol ∠(h, k) or ∠(k, h). From axioms II, 1–5, it follows readily that the half-rays h and k, taken together with the point O, divide the remaining points of the plane a into two regions having the following property: If A is a point of one region and B a point of the other, then every broken line joining A and B either passes through O or has a point in common with one of the half-rays h, k. If, however, A, A0 both lie within the same region, then it is always possible to join these two points by a broken line which neither passes through O nor has a point in common with either of the half-rays h, k. One of these two regions is distinguished from the other in that the segment joining any two points of this region lies entirely within the region. The region so characterised is called the interior of the angle (h, k). To distinguish the other region from this, we call it the exterior of the angle (h, k). The half rays h and k are called the sides of the angle, and the point O is called the vertex of the angle."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    halfRayHHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaHalfRayHHostId))
    halfRayHJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaHalfRayHJoint2Id))
    halfRayKHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaHalfRayKHostId))
    halfRayKJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaHalfRayKJoint2Id))
    markerHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerHostId))
    markerEndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerEndId))
    pointOId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointOId))
    labelOId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelOId))
    labelHId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelHId))
    labelKId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelKId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [halfRayHHostId, halfRayKHostId, markerHostId, pointOId, labelOId, labelHId, labelKId])

    OdinJuliaBridge.set_point_position(state_ptr, halfRayHJoint2Id, HalfRayHStart)
    OdinJuliaBridge.set_point_position(state_ptr, halfRayKJoint2Id, HalfRayKStart)
    OdinJuliaBridge.set_point_position(state_ptr, markerEndId, MarkerStart)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescendToO)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.hide_compass(state_ptr)
    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, PointOColor)
    OdinJuliaBridge.set_compass_active(state_ptr, 0, MarkerColor)
    OdinJuliaBridge.lock_compass_joint1(state_ptr, PointO[1], PointO[2], CompassTopZ)
    OdinJuliaBridge.lock_compass_joint2(state_ptr, MarkerStart[1], MarkerStart[2], CompassTopZ)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    halfRayH = OdinJuliaBridge.create_new_line(
        state_ptr, HalfRayHStart, HalfRayHStart, HalfRayHColor, 0f0)
    halfRayK = OdinJuliaBridge.create_new_line(
        state_ptr, HalfRayKStart, HalfRayKStart, HalfRayKColor, 0f0)
    marker = OdinJuliaBridge.create_new_filledcircle(
        state_ptr,
        PointO[1], PointO[2], PointO[3],
        MarkerRadius, 0f0, 0f0,
        MarkerColor, 0f0)
    pointO = OdinJuliaBridge.create_new_point(state_ptr, PointO, PointOColor, 0f0)

    labelO = OdinJuliaBridge.create_new_label(state_ptr, 'O', OLabelPoint, LabelColor, 16f0)
    labelH = OdinJuliaBridge.create_new_label(state_ptr, 'h', HLabelPoint, LabelColor, 16f0)
    labelK = OdinJuliaBridge.create_new_label(state_ptr, 'k', KLabelPoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaHalfRayHHostId, Float32(halfRayH.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaHalfRayHJoint1Id, Float32(halfRayH.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaHalfRayHJoint2Id, Float32(halfRayH.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaHalfRayKHostId, Float32(halfRayK.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaHalfRayKJoint1Id, Float32(halfRayK.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaHalfRayKJoint2Id, Float32(halfRayK.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarkerHostId, Float32(marker.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarkerStartId, Float32(marker.startId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarkerEndId, Float32(marker.endId))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointOId, Float32(pointO.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelOId, Float32(labelO.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelHId, Float32(labelH.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelKId, Float32(labelK.index))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    halfRayHHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaHalfRayHHostId))
    halfRayHJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaHalfRayHJoint1Id))
    halfRayHJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaHalfRayHJoint2Id))
    halfRayKHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaHalfRayKHostId))
    halfRayKJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaHalfRayKJoint1Id))
    halfRayKJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaHalfRayKJoint2Id))
    markerHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerHostId))
    markerStartId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerStartId))
    markerEndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarkerEndId))
    pointOId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointOId))
    labelOId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelOId))
    labelHId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelHId))
    labelKId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelKId))

    if halfRayHHostId < 0 || halfRayKHostId < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescendToO
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, PointO[1], PointO[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawPointO
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelOId)
        end
    elseif phase == PhaseDrawPointO
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointO,
            PointMaxBrush, PointOColor, pointOId)

        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseDrawHalfRayH
            timer = 0f0
            OdinJuliaBridge.set_pen_active(state_ptr, 0, HalfRayHColor)
        end
    elseif phase == PhaseDrawHalfRayH
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawRayDuration, HalfRayHStart, HalfRayHEnd,
            LineMaxBrush, HalfRayHColor,
            halfRayHHostId, halfRayHJoint1Id, halfRayHJoint2Id)

        timer += dt
        if timer >= DrawRayDuration
            phase = PhaseArcToOForK
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelHId)
        end
    elseif phase == PhaseArcToOForK
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            HalfRayHEnd, PointO, 0.24f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawHalfRayK
            timer = 0f0
            OdinJuliaBridge.set_pen_active(state_ptr, 0, HalfRayKColor)
        end
    elseif phase == PhaseDrawHalfRayK
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawRayDuration, HalfRayKStart, HalfRayKEnd,
            LineMaxBrush, HalfRayKColor,
            halfRayKHostId, halfRayKJoint1Id, halfRayKJoint2Id)

        timer += dt
        if timer >= DrawRayDuration
            phase = PhasePenLiftForMarker
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelKId)
        end
    elseif phase == PhasePenLiftForMarker
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ, HalfRayKEnd[1], HalfRayKEnd[2])

        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, PenLiftDuration, CompassTopZ,
            PointO[1], PointO[2], MarkerStart[1], MarkerStart[2])

        timer += dt
        if timer >= PenLiftDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseCompassDrawMarker
            timer = 0f0
        end
    elseif phase == PhaseCompassDrawMarker
        EuclidAnimations.animate_draw_filledcircle(
            state_ptr, timer, CompassDrawDuration,
            PointO, MarkerStart,
            AngleTheta, MarkerRadius, MarkerBrush, MarkerColor,
            markerHostId, markerStartId, markerEndId)

        timer += dt
        if timer >= CompassDrawDuration
            phase = PhaseCompassLift
            timer = 0f0
        end
    elseif phase == PhaseCompassLift
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassLiftDuration, CompassTopZ,
            PointO[1], PointO[2], MarkerEnd[1], MarkerEnd[2])

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

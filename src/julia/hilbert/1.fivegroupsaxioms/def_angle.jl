module HilbertChapterOneDefAngle

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

export get_view_text, initialize, clean, loop

const PointO = [0.36f0, 0.40f0, 0f0]
const HalfRayLength = 0.44f0
const AngleTheta = π / 3f0

const HalfRayHStart = PointO
const HalfRayHEnd = [PointO[1] + HalfRayLength, PointO[2], 0f0]
const HalfRayKStart = PointO
const HalfRayKEnd = [
    PointO[1] + HalfRayLength * cos(AngleTheta),
    PointO[2] + HalfRayLength * sin(AngleTheta),
    0f0,
]

const MarkerRadius = 0.16f0
const MarkerStart = [PointO[1] + MarkerRadius, PointO[2], 0f0]
const MarkerEnd = [
    PointO[1] + MarkerRadius * cos(AngleTheta),
    PointO[2] + MarkerRadius * sin(AngleTheta),
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

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - Definition: Angle

Let α be any arbitrary plane and h, k any two distinct half-rays lying in α and emanating from the point O so as to form a part of two different straight lines. We call the system formed by these two half-rays h, k an angle and represent it by the symbol ∠(h, k) or ∠(k, h). From axioms II, 1–5, it follows readily that the half-rays h and k, taken together with the point O, divide the remaining points of the plane a into two regions having the following property: If A is a point of one region and B a point of the other, then every broken line joining A and B either passes through O or has a point in common with one of the half-rays h, k. If, however, A, A0 both lie within the same region, then it is always possible to join these two points by a broken line which neither passes through O nor has a point in common with either of the half-rays h, k. One of these two regions is distinguished from the other in that the segment joining any two points of this region lies entirely within the region. The region so characterised is called the interior of the angle (h, k). To distinguish the other region from this, we call it the exterior of the angle (h, k). The half rays h and k are called the sides of the angle, and the point O is called the vertex of the angle."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - Definition}: \textit{Angle}

Let $\alpha$ be any arbitrary plane and $h$ \euclidline[color=steelblue,length=3,thickness=4], $k$ \euclidline[color=palevioletred1,length=3,thickness=4]
any two distinct half-rays lying in $\alpha$ and emanating from the point $O$ \euclidpoint[color=khaki3,size=1] so as to form a part of two different straight lines.
We call the system formed by these two half-rays $h$ \euclidline[color=steelblue,length=3,thickness=4], $k$ \euclidline[color=palevioletred1,length=3,thickness=4] an \textit{angle} and represent it by the symbol
$\angle(h, k)$ \euclidangle[color=khaki3,radius=2,end=60,filled] or $\angle(k, h)$ \euclidangle[color=khaki3,radius=2,end=60,filled].
From \textit{axioms II, 1–5}, it follows readily that the half-rays $h$ \euclidline[color=steelblue,length=3,thickness=4] and $k$ \euclidline[color=palevioletred1,length=3,thickness=4],
taken together with the point $O$ \euclidpoint[color=khaki3,size=1], divide the remaining points of the plane $\alpha$
into two regions having the following property: If $A$ \euclidpoint[color=plum1,size=0.5] is a point
of one region and $B$ \euclidpoint[color=plum1,size=0.5] a point of the other, then every broken line
joining $A$ \euclidpoint[color=plum1,size=0.5] and $B$ \euclidpoint[color=plum1,size=0.5] either passes
through $O$ \euclidpoint[color=khaki3,size=1] or has a point in common with one of the half-rays
$h$ \euclidline[color=steelblue,length=3,thickness=4], $k$ \euclidline[color=palevioletred1,length=3,thickness=4].
If, however, $A$ \euclidpoint[color=plum1,size=0.5], $B$ \euclidpoint[color=plum1,size=0.5] both lie
within the same region, then it is always possible to join these two points by a broken line which
neither passes through $O$ \euclidpoint[color=khaki3,size=1] nor has a point in common with either of
the half-rays $h$ \euclidline[color=steelblue,length=3,thickness=4], $k$ \euclidline[color=palevioletred1,length=3,thickness=4].
One of these two regions is distinguished from the other in that the segment joining any two points of this region lies
entirely within the region. The region so characterised is called the interior of the
angle $(h, k)$ \euclidangle[color=khaki3,radius=2,end=60,filled]. To distinguish the other region
from this, we call it the exterior of the angle $(h, k)$ \euclidangle[color=khaki3,radius=2,end=60,filled].
The half rays $h$ \euclidline[color=steelblue,length=3,thickness=4] and $k$ \euclidline[color=palevioletred1,length=3,thickness=4]
are called the sides of the angle, and the point $O$ \euclidpoint[color=khaki3,size=1] is called the vertex of the angle."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset the state of the animation cycle back to the start of the animation"""
function reset_cycle_state(state_ptr::Ptr{Cvoid})
    half_ray_h_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaHalfRayHHostId))
    half_ray_h_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaHalfRayHJoint2Id))
    half_ray_k_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaHalfRayKHostId))
    half_ray_k_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaHalfRayKJoint2Id))
    marker_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaMarkerHostId))
    marker_end_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaMarkerEndId))
    point_o_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointOId))
    label_o_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelOId))
    label_h_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelHId))
    label_k_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelKId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [half_ray_h_host_id, half_ray_k_host_id, marker_host_id,
         point_o_id, label_o_id, label_h_id, label_k_id])

    OdinJuliaBridge.set_point_position(state_ptr, half_ray_h_joint2_id, HalfRayHStart)
    OdinJuliaBridge.set_point_position(state_ptr, half_ray_k_joint2_id, HalfRayKStart)
    OdinJuliaBridge.set_point_position(state_ptr, marker_end_id, MarkerStart)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescendToO)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.hide_compass(state_ptr)
    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, PointOColor)
    OdinJuliaBridge.set_compass_active(state_ptr, 0, MarkerColor)
    OdinJuliaBridge.lock_compass_joint1(
        state_ptr, PointO[1], PointO[2], CompassTopZ)
    OdinJuliaBridge.lock_compass_joint2(
        state_ptr, MarkerStart[1], MarkerStart[2], CompassTopZ)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    half_ray_h = OdinJuliaBridge.create_new_line(
        state_ptr, HalfRayHStart, HalfRayHStart, HalfRayHColor, 0f0)
    half_ray_k = OdinJuliaBridge.create_new_line(
        state_ptr, HalfRayKStart, HalfRayKStart, HalfRayKColor, 0f0)
    marker = OdinJuliaBridge.create_new_filledcircle(
        state_ptr,
        PointO[1], PointO[2], PointO[3],
        MarkerRadius, 0f0, 0f0,
        MarkerColor, 0f0)
    point_o = OdinJuliaBridge.create_new_point(state_ptr, PointO, PointOColor, 0f0)

    label_o = OdinJuliaBridge.create_new_label(
        state_ptr, 'O', OLabelPoint, LabelColor, 16f0)
    label_h = OdinJuliaBridge.create_new_label(
        state_ptr, 'h', HLabelPoint, LabelColor, 16f0)
    label_k = OdinJuliaBridge.create_new_label(
        state_ptr, 'k', KLabelPoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaHalfRayHHostId, half_ray_h.host_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaHalfRayHJoint1Id, half_ray_h.joint1_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaHalfRayHJoint2Id, half_ray_h.joint2_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaHalfRayKHostId, half_ray_k.host_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaHalfRayKJoint1Id, half_ray_k.joint1_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaHalfRayKJoint2Id, half_ray_k.joint2_id)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarkerHostId, marker.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarkerStartId, marker.start_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarkerEndId, marker.end_id)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointOId, point_o.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelOId, label_o.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelHId, label_h.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelKId, label_k.index)

    reset_cycle_state(state_ptr)
end

"""Clean any extra animation data at the end of performance"""
function clean(state_ptr::Ptr{Cvoid})
end

"""Perform an iteration of the animation loop for this animation"""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    half_ray_h_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaHalfRayHHostId))
    half_ray_h_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaHalfRayHJoint1Id))
    half_ray_h_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaHalfRayHJoint2Id))
    half_ray_k_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaHalfRayKHostId))
    half_ray_k_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaHalfRayKJoint1Id))
    half_ray_k_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaHalfRayKJoint2Id))
    marker_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaMarkerHostId))
    marker_start_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaMarkerStartId))
    marker_end_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaMarkerEndId))
    point_o_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointOId))
    label_o_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelOId))
    label_h_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelHId))
    label_k_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelKId))

    if half_ray_h_host_id < 0 || half_ray_k_host_id < 0
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
            OdinJuliaBridge.show_point(state_ptr, label_o_id)
        end
    elseif phase == PhaseDrawPointO
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointO,
            PointMaxBrush, PointOColor, point_o_id)

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
            half_ray_h_host_id, half_ray_h_joint1_id, half_ray_h_joint2_id)

        timer += dt
        if timer >= DrawRayDuration
            phase = PhaseArcToOForK
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_h_id)
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
            half_ray_k_host_id, half_ray_k_joint1_id, half_ray_k_joint2_id)

        timer += dt
        if timer >= DrawRayDuration
            phase = PhasePenLiftForMarker
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_k_id)
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
            marker_host_id, marker_start_id, marker_end_id)

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

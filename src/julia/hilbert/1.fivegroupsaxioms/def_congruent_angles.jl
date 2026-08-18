module HilbertChapterOneDefCongruentAngles

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

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
const RayHPrimeColor = :steelblue
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
const PhaseCompassArcBackToMarker1 = 19f0
const PhaseHighlight1EncoreForward = 20f0
const PhaseHighlight1EncoreBack = 21f0
const PhaseCompassLiftEnd = 22f0
const PhaseFinalHold = 23f0


function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - Definition: Congruent Angles

Let the angle (h, k) be congruent to the angle (h', k'). Since, according to axiom IV, 4, the angle (h, k) is congruent to itself, it follows from axiom IV, 5 that the angle (h', k') is congruent to the angle (h, k). We say, then, that the angles (h, k) and (h', k') are congruent to one another."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - Definition}: \textit{Congruent Angles}

Let the angle $(h, k)$ \euclidangle[color=khaki3,radius=2,end=60,filled] be congruent to the angle $(h', k')$ \euclidangle[color=khaki3,radius=2,end=60,filled].
Since, according to \textit{axiom IV, 4}, the angle $(h, k)$ \euclidangle[color=khaki3,radius=2,end=60,filled]
is congruent to itself, it follows from \textit{axiom IV, 5} that the angle
$(h', k')$ \euclidangle[color=khaki3,radius=2,end=60,filled] is congruent to the angle
$(h, k)$ \euclidangle[color=khaki3,radius=2,end=60,filled]. We say, then, that the angles
$(h, k)$ \euclidangle[color=khaki3,radius=2,end=60,filled] and $(h', k')$ \euclidangle[color=khaki3,radius=2,end=60,filled] are congruent to one another."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    ray_h_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHHostId))
    ray_h_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHJoint2Id))
    ray_k_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKHostId))
    ray_k_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKJoint2Id))
    ray_h_prime_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHPrimeHostId))
    ray_h_prime_joint2_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHPrimeJoint2Id))
    ray_k_prime_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKPrimeHostId))
    ray_k_prime_joint2_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKPrimeJoint2Id))

    marker1_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker1HostId))
    marker1_end_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker1EndId))
    marker2_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker2HostId))
    marker2_end_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker2EndId))

    label_o_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelOId))
    label_h_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelHId))
    label_k_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelKId))
    label_o_prime_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelOPrimeId))
    label_h_prime_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelHPrimeId))
    label_k_prime_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelKPrimeId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [ray_h_host_id, ray_k_host_id, ray_h_prime_host_id, ray_k_prime_host_id,
         marker1_host_id, marker2_host_id,
         label_o_id, label_h_id, label_k_id, label_o_prime_id, label_h_prime_id, label_k_prime_id])

    OdinJuliaBridge.set_point_position(state_ptr, ray_h_joint2_id, RayHStart)
    OdinJuliaBridge.set_point_position(state_ptr, ray_k_joint2_id, RayKStart)
    OdinJuliaBridge.set_point_position(state_ptr, ray_h_prime_joint2_id, RayHPrimeStart)
    OdinJuliaBridge.set_point_position(state_ptr, ray_k_prime_joint2_id, RayKPrimeStart)

    OdinJuliaBridge.set_point_position(state_ptr, marker1_end_id, Marker1Start)
    OdinJuliaBridge.set_point_position(state_ptr, marker2_end_id, Marker2Start)

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
    ray_h = OdinJuliaBridge.create_new_line(state_ptr, RayHStart, RayHStart, RayHColor, 0f0)
    ray_k = OdinJuliaBridge.create_new_line(state_ptr, RayKStart, RayKStart, RayKColor, 0f0)
    ray_h_prime = OdinJuliaBridge.create_new_line(
        state_ptr, RayHPrimeStart, RayHPrimeStart, RayHPrimeColor, 0f0)
    ray_k_prime = OdinJuliaBridge.create_new_line(
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

    label_o = OdinJuliaBridge.create_new_label(state_ptr, 'O', LabelOPoint, LabelColor, 16f0)
    label_h = OdinJuliaBridge.create_new_label(state_ptr, 'h', LabelHPoint, LabelColor, 16f0)
    label_k = OdinJuliaBridge.create_new_label(state_ptr, 'k', LabelKPoint, LabelColor, 16f0)

    label_o_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'O', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelOPrimePoint, LabelColor, 16f0)
    label_h_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'h', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelHPrimePoint, LabelColor, 16f0)
    label_k_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'k', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelKPrimePoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayHHostId, Float32(ray_h.host_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayHJoint1Id, Float32(ray_h.joint1_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayHJoint2Id, Float32(ray_h.joint2_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayKHostId, Float32(ray_k.host_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayKJoint1Id, Float32(ray_k.joint1_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayKJoint2Id, Float32(ray_k.joint2_id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayHPrimeHostId, Float32(ray_h_prime.host_id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaRayHPrimeJoint1Id, Float32(ray_h_prime.joint1_id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaRayHPrimeJoint2Id, Float32(ray_h_prime.joint2_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaRayKPrimeHostId, Float32(ray_k_prime.host_id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaRayKPrimeJoint1Id, Float32(ray_k_prime.joint1_id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaRayKPrimeJoint2Id, Float32(ray_k_prime.joint2_id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker1HostId, Float32(marker1.host_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker1StartId, Float32(marker1.start_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker1EndId, Float32(marker1.end_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker2HostId, Float32(marker2.host_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker2StartId, Float32(marker2.start_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaMarker2EndId, Float32(marker2.end_id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelOId, Float32(label_o.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelHId, Float32(label_h.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelKId, Float32(label_k.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelOPrimeId, Float32(label_o_prime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelHPrimeId, Float32(label_h_prime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelKPrimeId, Float32(label_k_prime.index))

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
    ray_h_prime_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHPrimeHostId))
    ray_h_prime_joint1_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHPrimeJoint1Id))
    ray_h_prime_joint2_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayHPrimeJoint2Id))
    ray_k_prime_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKPrimeHostId))
    ray_k_prime_joint1_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKPrimeJoint1Id))
    ray_k_prime_joint2_id = Integer(
        OdinJuliaBridge.get_animation_meta(state_ptr, MetaRayKPrimeJoint2Id))

    marker1_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker1HostId))
    marker1_start_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker1StartId))
    marker1_end_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker1EndId))
    marker2_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker2HostId))
    marker2_start_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker2StartId))
    marker2_end_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaMarker2EndId))

    label_o_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelOId))
    label_h_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelHId))
    label_k_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelKId))
    label_o_prime_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelOPrimeId))
    label_h_prime_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelHPrimeId))
    label_k_prime_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelKPrimeId))

    if ray_h_host_id < 0 || ray_k_host_id < 0 || ray_h_prime_host_id < 0 || ray_k_prime_host_id < 0
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
            OdinJuliaBridge.show_point(state_ptr, label_o_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, RayHColor)
        end
    elseif phase == PhaseDrawRayH
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawRayDuration, RayHStart, RayHEnd,
            RayBrush, RayHColor,
            ray_h_host_id, ray_h_joint1_id, ray_h_joint2_id)

        timer += dt
        if timer >= DrawRayDuration
            phase = PhaseArcToOForK
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_h_id)
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
            ray_k_host_id, ray_k_joint1_id, ray_k_joint2_id)

        timer += dt
        if timer >= DrawRayDuration
            phase = PhasePenLiftForMarker1
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_k_id)
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
            marker1_host_id, marker1_start_id, marker1_end_id)

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
            OdinJuliaBridge.show_point(state_ptr, label_o_prime_id)
        end
    elseif phase == PhaseDrawRayHPrime
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawRayDuration, RayHPrimeStart, RayHPrimeEnd,
            RayBrush, RayHPrimeColor,
            ray_h_prime_host_id, ray_h_prime_joint1_id, ray_h_prime_joint2_id)

        timer += dt
        if timer >= DrawRayDuration
            phase = PhaseArcToOPrimeForKPrime
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_h_prime_id)
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
            ray_k_prime_host_id, ray_k_prime_joint1_id, ray_k_prime_joint2_id)

        timer += dt
        if timer >= DrawRayDuration
            phase = PhasePenLiftForMarker2
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_k_prime_id)
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
            marker2_host_id, marker2_start_id, marker2_end_id)

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
            phase = PhaseCompassArcBackToMarker1
            timer = 0f0
        end
    elseif phase == PhaseCompassArcBackToMarker1
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            VertexOPrime, VertexO,
            Marker2Start, Marker1Start,
            0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlight1EncoreForward
            timer = 0f0
        end
    elseif phase == PhaseHighlight1EncoreForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            VertexO, Marker1Start,
            AngleTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlight1EncoreBack
            timer = 0f0
        end
    elseif phase == PhaseHighlight1EncoreBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            VertexO, Marker1End,
            -AngleTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassLiftEnd
            timer = 0f0
        end
    elseif phase == PhaseCompassLiftEnd
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassLiftDuration, CompassTopZ,
            VertexO[1], VertexO[2], Marker1Start[1], Marker1Start[2])

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
